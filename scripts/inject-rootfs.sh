#!/usr/bin/env bash
#
# Patch a Droidian arm64 rootfs image for the Lenovo Tab M10 HD (2nd gen).
#
# What it does:
#   * copies the generic Droidian rootfs.img
#   * grows it (default +1 GiB) so there is room for the kernel modules
#   * injects /usr/lib/modules/<kernel release>
#   * injects the device adaptation overlay (udev rules, systemd units, ...)
#   * injects /boot/{boot,dtbo,vbmeta}.img so the Droidian installer can
#     flash them from inside recovery
#
# The rootfs layout is the "Halium file layout": the device's userdata
# partition is ext4 and contains /rootfs.img.  Do not flash the result
# directly to the userdata partition.
#
# Usage:
#   ./scripts/inject-rootfs.sh [rootfs.img] [output.img]
#
# Environment:
#   VARIANT=lte|wifi     device variant (default: lte)
#   ROOTFS_SRC=...       input image
#   GROW_MB=1024         how much to grow the filesystem (0 to disable)
#   NO_MODULES=1         skip module injection
#   NO_BOOT=1            skip /boot image injection
#
set -euo pipefail

source "$(dirname "$0")/env.sh"

SRC="${1:-$ROOTFS_SRC}"
DST="${2:-$OUT_DIR/rootfs.img}"
GROW_MB="${GROW_MB:-1024}"

[ -f "$SRC" ] || die "rootfs image not found: $SRC (set ROOTFS_SRC)"
for tool in debugfs e2fsck resize2fs truncate; do
  command -v "$tool" >/dev/null || die "missing required tool: $tool"
done

mkdir -p "$OUT_DIR" "$BUILD_DIR"

KREL="$(kernelrelease)"

# ---------------------------------------------------------------------------
# 1. Copy the rootfs
# ---------------------------------------------------------------------------
# Always start from a pristine copy so re-running this script does not grow
# an already-grown image.  Set INPLACE=1 to patch $DST directly instead.
if [ "${INPLACE:-0}" = "1" ] && [ -f "$DST" ]; then
  echo "==> patching $DST in place (INPLACE=1: no copy, no grow)"
  GROW_MB=0
else
  echo "==> copying rootfs -> $DST"
  if [ "$(readlink -f "$SRC")" = "$(readlink -f "$DST" 2>/dev/null || echo "$DST")" ]; then
    die "SRC and DST are the same file; use INPLACE=1 to patch in place"
  fi
  rm -f "$DST"
  cp --sparse=always "$SRC" "$DST"

  # -------------------------------------------------------------------------
  # 2. Grow the filesystem
  # -------------------------------------------------------------------------
  if [ "$GROW_MB" -gt 0 ]; then
    echo "==> growing filesystem by ${GROW_MB} MiB"
    cur_size="$(stat -c %s "$DST")"
    truncate -s "$((cur_size + GROW_MB * 1024 * 1024))" "$DST"
    echo "==> e2fsck (before resize)"
    e2fsck -f -y "$DST" >/dev/null 2>&1 || true
    echo "==> resize2fs"
    resize2fs "$DST"
  fi
fi

# ---------------------------------------------------------------------------
# 3. Build the overlay that will be merged into the image
# ---------------------------------------------------------------------------
OVERLAY="$BUILD_DIR/overlay"
echo "==> staging overlay in $OVERLAY"
rm -rf "$OVERLAY"
mkdir -p "$OVERLAY"
cp -a "$PORT_DIR/adaptation/." "$OVERLAY/"

# Enable the vendor module loader.
mkdir -p "$OVERLAY/etc/systemd/system/multi-user.target.wants"
ln -sfn /etc/systemd/system/amar-modules.service \
  "$OVERLAY/etc/systemd/system/multi-user.target.wants/amar-modules.service"

# Kernel modules.
if [ "${NO_MODULES:-0}" != "1" ]; then
  MODDIR="$STAGE_MODULES/lib/modules/$KREL"
  if [ -d "$MODDIR" ]; then
    echo "==> adding modules: $KREL"
    # These point at the host source tree; never ship them.
    rm -f "$MODDIR/build" "$MODDIR/source"
    mkdir -p "$OVERLAY/usr/lib/modules"
    cp -a "$MODDIR" "$OVERLAY/usr/lib/modules/"
  else
    echo "warning: no modules found in $MODDIR; run scripts/build-kernel.sh" >&2
  fi
fi

# Boot images for the in-recovery installer.
if [ "${NO_BOOT:-0}" != "1" ]; then
  for img in boot.img dtbo.img vbmeta.img; do
    if [ -f "$OUT_DIR/$img" ]; then
      mkdir -p "$OVERLAY/boot"
      cp -f "$OUT_DIR/$img" "$OVERLAY/boot/$img"
    else
      echo "warning: $OUT_DIR/$img missing; run scripts/make-images.sh" >&2
    fi
  done
fi

# ---------------------------------------------------------------------------
# 4. Write the overlay into the ext4 image with debugfs
# ---------------------------------------------------------------------------
CMDS="$BUILD_DIR/debugfs.cmds"
echo "==> generating debugfs script"
python3 "$PORT_DIR/scripts/gen-debugfs.py" "$OVERLAY" > "$CMDS"

echo "==> injecting files"
debugfs -w -f "$CMDS" "$DST" > "$BUILD_DIR/debugfs.log" 2>&1 || {
  echo "debugfs failed, see $BUILD_DIR/debugfs.log" >&2
  tail -20 "$BUILD_DIR/debugfs.log" >&2
  exit 1
}

# Report paths that debugfs could not create.  "Already exists" from mkdir is
# expected (the overlay provides files for directories the rootfs already
# has), and "file not found" comes from the rm-before-write dance.
real_errors="$(grep -E "^(write|symlink|mkdir):" "$BUILD_DIR/debugfs.log" \
  | grep -v "already exists" || true)"
if [ -n "$real_errors" ]; then
  echo "warning: some debugfs operations failed:" >&2
  printf '%s\n' "$real_errors" >&2
fi

# ---------------------------------------------------------------------------
# 5. Clean up
# ---------------------------------------------------------------------------
echo "==> e2fsck (final)"
e2fsck -f -y "$DST" >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# 6. Sanity check
# ---------------------------------------------------------------------------
# An inode written without its S_IFREG type bit looks fine in the debugfs
# log but is dropped by e2fsck, so verify that the important files survived.
echo "==> verifying injected files"
verify_failed=0
check_path() {
  local path="$1" want="$2" out
  out="$(debugfs -R "stat $path" "$DST" 2>/dev/null)"
  if ! printf '%s' "$out" | grep -q "Type: $want"; then
    echo "error: $path missing or not a $want file" >&2
    verify_failed=1
  fi
}
for f in /usr/bin/amar-modules.sh /usr/sbin/amar-mount-vendor.sh \
         /etc/udev/rules.d/70-amar.rules /etc/systemd/system/amar-modules.service; do
  check_path "$f" regular
done
if [ "${NO_BOOT:-0}" != "1" ]; then
  check_path /boot/boot.img regular
  check_path /boot/dtbo.img regular
  check_path /boot/vbmeta.img regular
fi
if [ "${NO_MODULES:-0}" != "1" ]; then
  check_path "/usr/lib/modules/$KREL/modules.dep" regular
fi
check_path /etc/systemd/system/multi-user.target.wants/amar-modules.service symlink
[ "$verify_failed" = "0" ] || die "rootfs verification failed"

echo
echo "==> done: $DST"
echo "    kernel release: $KREL"
du -h "$DST" | awk '{print "    image size:     " $1}'

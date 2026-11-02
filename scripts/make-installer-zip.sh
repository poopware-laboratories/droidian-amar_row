#!/usr/bin/env bash
#
# Repack the patched rootfs into a Droidian-style recovery (TWRP) zip.
#
# The zip layout is exactly the one used by the official Droidian rootfs
# images:
#
#   META-INF/com/google/android/update-binary
#   META-INF/com/google/android/updater-script
#   setup.sh
#   tools/busybox
#   data/rootfs.img        <- patched by scripts/inject-rootfs.sh
#
# Flashing the zip:
#   * extracts rootfs.img to /data
#   * resizes it
#   * flashes /boot/{boot,dtbo,vbmeta}.img found inside the rootfs
#
# Usage:
#   ./scripts/make-installer-zip.sh [rootfs.img]
#
set -euo pipefail

source "$(dirname "$0")/env.sh"

ROOTFS="${1:-$OUT_DIR/rootfs.img}"
TEMPLATE="${ROOTFS_TEMPLATE:-$REPO_DIR/work/rootfs}"
ZIP_LEVEL="${ZIP_LEVEL:-3}"
ZIP_OUT="${ZIP_OUT:-$OUT_DIR/droidian-${DEVICE}.zip}"

[ -f "$ROOTFS" ] || die "patched rootfs not found: $ROOTFS (run scripts/inject-rootfs.sh)"
for path in META-INF/com/google/android/update-binary setup.sh tools/busybox; do
  [ -e "$TEMPLATE/$path" ] || die "installer template missing: $TEMPLATE/$path"
done

STAGE="$BUILD_DIR/zip"
echo "==> staging installer zip in $STAGE"
rm -rf "$STAGE"
mkdir -p "$STAGE/data"
cp -a "$TEMPLATE/META-INF" "$TEMPLATE/setup.sh" "$TEMPLATE/tools" "$STAGE/"

# Hardlink the (large) rootfs image so we do not duplicate it on disk.
ln -f "$ROOTFS" "$STAGE/data/rootfs.img" 2>/dev/null || cp --sparse=always "$ROOTFS" "$STAGE/data/rootfs.img"

rm -f "$ZIP_OUT"
echo "==> creating $ZIP_OUT"
(cd "$STAGE" && zip -r -"$ZIP_LEVEL" -q "$ZIP_OUT" .)

echo
echo "==> done: $ZIP_OUT"
ls -lh "$ZIP_OUT"

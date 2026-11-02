#!/usr/bin/env bash
#
# Build the Droidian kernel for the Lenovo Tab M10 HD (2nd gen).
#
# Usage:
#   ./scripts/build-kernel.sh              # LTE (TB-X306X), default
#   VARIANT=wifi ./scripts/build-kernel.sh # Wi-Fi (TB-X306F)
#
# Environment:
#   JOBS=4          parallel build jobs (default: nproc)
#   KERNEL_SRC=...  alternate kernel source tree
#   KERNEL_OUT=...  alternate object directory
#   STAGE_MODULES=... where modules_install puts the modules
#
set -euo pipefail

source "$(dirname "$0")/env.sh"

JOBS="${JOBS:-$(nproc)}"

[ -d "$KERNEL_SRC" ] || die "kernel source not found: $KERNEL_SRC"

# Keep temporary files off /tmp, which is a small tmpfs on many systems.
mkdir -p "$BUILD_DIR/tmp"
export TMPDIR="$BUILD_DIR/tmp"

MAKE_ARGS=(
  ARCH=arm64
  CROSS_COMPILE=aarch64-linux-androidkernel-
  CLANG_TRIPLE=aarch64-linux-gnu-
  LD=ld.lld
  LD_LIBRARY_PATH="$CLANG_DIR/lib64"
  NM=llvm-nm
  OBJCOPY=llvm-objcopy
  CC=clang
  ROOTDIR="$KERNEL_SRC"
  O="$KERNEL_OUT"
)

echo "==> device:      $DEVICE ($VARIANT)"
echo "==> defconfig:   $DEFCONFIG"
echo "==> kernel out:  $KERNEL_OUT"
echo "==> modules out: $STAGE_MODULES"
echo "==> jobs:        $JOBS"

cd "$KERNEL_SRC"

echo "==> configuring"
make "${MAKE_ARGS[@]}" "$DEFCONFIG"

echo "==> building"
make "${MAKE_ARGS[@]}" -j"$JOBS"

echo "==> installing modules"
rm -rf "$STAGE_MODULES"
make "${MAKE_ARGS[@]}" INSTALL_MOD_PATH="$STAGE_MODULES" modules_install

# The build/source symlinks point at the host source tree and are useless
# (and confusing) inside the installed rootfs.
KREL="$(kernelrelease)"
rm -f "$STAGE_MODULES/lib/modules/$KREL/build" \
      "$STAGE_MODULES/lib/modules/$KREL/source"

echo
echo "==> done"
echo "    kernel release: $KREL"
echo "    kernel image:   $KERNEL_OUT/arch/arm64/boot/Image.gz"
echo "    modules:        $STAGE_MODULES/lib/modules/$KREL"

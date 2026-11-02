#!/usr/bin/env bash
#
# Shared configuration for the Lenovo Tab M10 HD (2nd gen) Droidian port.
# Source this file from the other scripts; do not execute it directly.
#
# The board is sold as:
#   TB-X306X  (LTE,  MT6762)
#   TB-X306F  (Wi-Fi, MT6762)
#
# Both variants share the "amar_row" kernel configuration.  Only the
# defconfig and the base DTB differ.

set -euo pipefail

PORT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(dirname "$PORT_DIR")"

# ---------------------------------------------------------------------------
# Kernel source tree / toolchain (from the Lenovo S220054 Android 11 release)
# ---------------------------------------------------------------------------
KERNEL_SRC="${KERNEL_SRC:-$REPO_DIR/tb-x306x_opensource_tb-x306x_s220054_210625_bmp/kernel-4.19}"
ANDROID_TREE="${ANDROID_TREE:-$REPO_DIR/tb-x306x_opensource_tb-x306x_s220054_210625_bmp}"
PREBUILTS="${PREBUILTS:-$ANDROID_TREE/prebuilts}"
CLANG_DIR="$PREBUILTS/clang/host/linux-x86/clang-r383902"
GCC_DIR="$PREBUILTS/gcc/linux-x86/aarch64/aarch64-linux-android-4.9"

# ---------------------------------------------------------------------------
# Device variant
# ---------------------------------------------------------------------------
VARIANT="${VARIANT:-lte}"
case "$VARIANT" in
  lte)
    DEVICE="amar_row_lte"
    DTB="$PORT_DIR/prebuilt/amar_row_lte_dtb"
    ;;
  wifi)
    DEVICE="amar_row_wifi"
    # The Wi-Fi variant uses the shared "amar" DTB shipped by the port.
    DTB="$PORT_DIR/prebuilt/amar_dtb"
    ;;
  *)
    echo "VARIANT must be 'lte' or 'wifi' (got: $VARIANT)" >&2
    exit 1
    ;;
esac

DEFCONFIG="${DEVICE}_droidian_defconfig"

# ---------------------------------------------------------------------------
# Build / output directories
# ---------------------------------------------------------------------------
# The LTE build uses out-droidian (matching Lenovo's own build_kernel.sh);
# the Wi-Fi build gets its own object directory.
if [ "$VARIANT" = "wifi" ]; then
  DEFAULT_KERNEL_OUT="$KERNEL_SRC/out-droidian-wifi"
else
  DEFAULT_KERNEL_OUT="$KERNEL_SRC/out-droidian"
fi
KERNEL_OUT="${KERNEL_OUT:-$DEFAULT_KERNEL_OUT}"
BUILD_DIR="${BUILD_DIR:-$PORT_DIR/build/$VARIANT}"
OUT_DIR="${OUT_DIR:-$PORT_DIR/out/$VARIANT}"
STAGE_MODULES="$BUILD_DIR/modules"

# ---------------------------------------------------------------------------
# Prebuilt payloads
# ---------------------------------------------------------------------------
INITRAMFS="$PORT_DIR/prebuilt/initrd.img-halium-generic"
DTBO_IMAGE="$PORT_DIR/prebuilt/amar_dtbo.img"

# The input rootfs is the generic Droidian arm64 image (api30).
ROOTFS_SRC="${ROOTFS_SRC:-$REPO_DIR/work/rootfs/data/rootfs.img}"

# ---------------------------------------------------------------------------
# Boot image parameters (identical to the Ubuntu Touch port and to the
# stock Lenovo boot image layout)
# ---------------------------------------------------------------------------
BOOT_BASE=0x40078000
BOOT_KERNEL_OFFSET=0x00008000
BOOT_RAMDISK_OFFSET=0x11a88000
BOOT_SECOND_OFFSET=0x00e88000
BOOT_TAGS_OFFSET=0x07808000
BOOT_DTB_OFFSET=0x07808000
BOOT_PAGE_SIZE=2048
BOOT_HEADER_VERSION=2
BOOT_OS_VERSION=11
BOOT_OS_PATCH_LEVEL=2023-05

# No droidian.lvm.prefer here: this port uses the "Halium file layout"
# (an ext4 userdata partition that contains /rootfs.img), so the LVM
# scan can be skipped and boot becomes a few seconds faster.
CMDLINE="${CMDLINE:-bootopt=64S3,32N2,64N2 buildvariant=user}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
export PYTHONPATH="$PORT_DIR/tools/python${PYTHONPATH:+:$PYTHONPATH}"
export PATH="$CLANG_DIR/bin:$GCC_DIR/bin:$PATH"

kernelrelease() {
  cat "$KERNEL_OUT/include/config/kernel.release"
}

die() {
  echo "error: $*" >&2
  exit 1
}

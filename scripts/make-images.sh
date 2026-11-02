#!/usr/bin/env bash
#
# Assemble the flashable images for the Lenovo Tab M10 HD (2nd gen):
#
#   boot.img    - kernel + Droidian initramfs + base DTB (header v2)
#   dtbo.img    - device tree overlay (taken from the prebuilt UBports port)
#   vbmeta.img  - AVB metadata with verification disabled
#
# The boot image layout mirrors the working Ubuntu Touch port:
#   page size 2048, header v2, no recovery_dtbo area, DTB embedded.
#
# Usage:
#   ./scripts/make-images.sh
#   VARIANT=wifi ./scripts/make-images.sh
#
set -euo pipefail

source "$(dirname "$0")/env.sh"

KREL="$(kernelrelease)"
KIMAGE="$KERNEL_OUT/arch/arm64/boot/Image.gz"
[ -f "$KIMAGE" ] || KIMAGE="$KERNEL_OUT/arch/arm64/boot/Image"
[ -f "$KIMAGE" ] || die "kernel image not found; run scripts/build-kernel.sh first"
[ -f "$INITRAMFS" ] || die "initramfs not found: $INITRAMFS"
[ -f "$DTB" ] || die "DTB not found: $DTB"
[ -f "$DTBO_IMAGE" ] || die "DTBO not found: $DTBO_IMAGE"

mkdir -p "$OUT_DIR"

echo "==> boot.img (kernel $KREL)"
python3 "$PORT_DIR/tools/mkbootimg" \
  --kernel "$KIMAGE" \
  --ramdisk "$INITRAMFS" \
  --dtb "$DTB" \
  --header_version "$BOOT_HEADER_VERSION" \
  --pagesize "$BOOT_PAGE_SIZE" \
  --base "$BOOT_BASE" \
  --kernel_offset "$BOOT_KERNEL_OFFSET" \
  --ramdisk_offset "$BOOT_RAMDISK_OFFSET" \
  --second_offset "$BOOT_SECOND_OFFSET" \
  --tags_offset "$BOOT_TAGS_OFFSET" \
  --dtb_offset "$BOOT_DTB_OFFSET" \
  --os_version "$BOOT_OS_VERSION" \
  --os_patch_level "$BOOT_OS_PATCH_LEVEL" \
  --cmdline "$CMDLINE" \
  -o "$OUT_DIR/boot.img"

echo "==> dtbo.img"
cp -f "$DTBO_IMAGE" "$OUT_DIR/dtbo.img"

echo "==> vbmeta.img (verification disabled)"
python3 "$PORT_DIR/tools/avbtool" make_vbmeta_image \
  --flags 2 \
  --padding_size 4096 \
  --set_hashtree_disabled_flag \
  --output "$OUT_DIR/vbmeta.img"

echo
echo "==> done"
ls -l "$OUT_DIR/boot.img" "$OUT_DIR/dtbo.img" "$OUT_DIR/vbmeta.img"
echo
echo "Verify with:"
echo "  python3 tools/mkbootimg --help >/dev/null"
echo "  file $OUT_DIR/boot.img"

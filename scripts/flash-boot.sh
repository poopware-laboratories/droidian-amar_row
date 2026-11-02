#!/usr/bin/env bash
#
# Flash the boot images and (optionally) reboot to the booted system.
#
# Prerequisites:
#   * bootloader unlocked (fastboot oem unlock / Lenovo unlock tool)
#   * device in fastboot mode (power + volume down, then "fastboot devices")
#
# The rootfs is NOT flashed by this script.  Use the recovery zip or
# "adb push" as described in README.md.
#
# Usage:
#   ./scripts/flash-boot.sh [--reboot]
#
set -euo pipefail

source "$(dirname "$0")/env.sh"

REBOOT=0
[ "${1:-}" = "--reboot" ] && REBOOT=1

command -v fastboot >/dev/null || die "fastboot is not installed"
if ! fastboot devices | grep -q .; then
  die "no fastboot device found (check 'fastboot devices' and the bootloader unlock state)"
fi

for img in boot.img dtbo.img vbmeta.img; do
  [ -f "$OUT_DIR/$img" ] || die "missing $OUT_DIR/$img (run scripts/make-images.sh)"
done

echo "==> flashing boot"
fastboot flash boot "$OUT_DIR/boot.img"

echo "==> flashing dtbo"
fastboot flash dtbo "$OUT_DIR/dtbo.img"

echo "==> flashing vbmeta (verification disabled)"
fastboot --disable-verity --disable-verification flash vbmeta "$OUT_DIR/vbmeta.img"

if [ "$REBOOT" = "1" ]; then
  echo "==> rebooting"
  fastboot reboot
fi

echo
echo "Boot images flashed.  If the rootfs is not installed yet, boot to"
echo "recovery and flash $OUT_DIR/droidian-${DEVICE}.zip."

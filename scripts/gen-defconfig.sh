#!/usr/bin/env bash
#
# Regenerate arch/arm64/configs/<device>_droidian_defconfig from:
#
#   1. the stock Lenovo defconfig            (amar_row_{lte,wifi}_defconfig)
#   2. Droidian's common 4.19 fragments      (droidian/common_fragments/*.config)
#   3. this port's device fragment           (droidian/amar_row_{lte,wifi}.config)
#
# The resulting defconfig is checked in, so a normal kernel build does not
# need to run this script.  Use it after changing one of the fragments.
#
set -euo pipefail

source "$(dirname "$0")/env.sh"

GEN_OUT="${GEN_OUT:-$KERNEL_SRC/out-config-$VARIANT}"
BASE_DEFCONFIG="${DEVICE}_defconfig"
FRAGMENTS=(
  "$KERNEL_SRC/droidian/common_fragments/halium.config"
  "$KERNEL_SRC/droidian/common_fragments/droidian.config"
  "$KERNEL_SRC/droidian/$DEVICE.config"
)

for f in "$BASE_DEFCONFIG" "${FRAGMENTS[@]}"; do
  [ -f "$KERNEL_SRC/arch/arm64/configs/$f" ] || [ -f "$f" ] || die "missing: $f"
done

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
  O="$GEN_OUT"
)

cd "$KERNEL_SRC"
rm -rf "$GEN_OUT"

echo "==> base: $BASE_DEFCONFIG"
make "${MAKE_ARGS[@]}" "$BASE_DEFCONFIG"

echo "==> merging fragments"
"$KERNEL_SRC/scripts/kconfig/merge_config.sh" -m -O "$GEN_OUT" "$GEN_OUT/.config" "${FRAGMENTS[@]}"

echo "==> olddefconfig"
make "${MAKE_ARGS[@]}" olddefconfig

echo "==> savedefconfig"
make "${MAKE_ARGS[@]}" savedefconfig
cp "$GEN_OUT/defconfig" "$KERNEL_SRC/arch/arm64/configs/$DEFCONFIG"

echo
echo "==> wrote arch/arm64/configs/$DEFCONFIG"
grep -E "^(CONFIG_(ANDROID_BINDERFS|MODULE_FORCE_LOAD|SCHED_TUNE|LOCALVERSION|DEVTMPFS|VT))|BINDERFS is not set" "$GEN_OUT/.config" || true

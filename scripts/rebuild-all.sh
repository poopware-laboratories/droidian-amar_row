#!/usr/bin/env bash
#
# Build everything for one device variant:
#   kernel -> boot/dtbo/vbmeta -> patched rootfs -> recovery zip
#
# Usage:
#   ./scripts/rebuild-all.sh
#   VARIANT=wifi ./scripts/rebuild-all.sh
#
set -euo pipefail

HERE="$(dirname "$0")"

"$HERE/build-kernel.sh"
"$HERE/make-images.sh"
"$HERE/inject-rootfs.sh"
"$HERE/make-installer-zip.sh"

echo
echo "All artifacts are in: $(source "$HERE/env.sh" && echo "$OUT_DIR")"

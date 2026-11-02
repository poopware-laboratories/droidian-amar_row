#!/bin/sh
#
# Pre-mount the MediaTek vendor (and persist) partitions before the
# generic Droidian mount-android.sh runs.
#
# The generic script only looks for:
#   /userdata/vendor.img, /var/lib/lxc/android/vendor.img,
#   /dev/disk/by-partlabel/vendor*, /dev/mapper/dynpart-vendor*
# and the (usually absent) device-tree android,fstab node.
#
# MTK devices expose the partition as
#   /dev/block/platform/bootdevice/by-name/vendor
# so without this helper /vendor stays empty and no HAL, firmware or
# vendor kernel module is available.

log() {
    echo "amar-mount-vendor: $*"
}

try_mount() {
    src="$1"
    dst="$2"
    opts="$3"

    [ -e "$src" ] || return 1
    mount -o "$opts" "$src" "$dst" 2>/dev/null || return 1
    return 0
}

# --------------------------------------------------------------------------
# vendor
# --------------------------------------------------------------------------
if [ ! -e /vendor/build.prop ]; then
    for src in \
        /dev/disk/by-partlabel/vendor \
        /dev/disk/by-name/vendor \
        /dev/block/platform/bootdevice/by-name/vendor \
        /dev/block/by-name/vendor
    do
        if try_mount "$src" /vendor ro && [ -e /vendor/build.prop ]; then
            log "mounted $src on /vendor"
            break
        fi
        umount /vendor 2>/dev/null || true
    done
fi

# --------------------------------------------------------------------------
# persist (Bluetooth/Wi-Fi calibration data, sensor calibration, ...)
# --------------------------------------------------------------------------
if ! mountpoint -q /mnt/vendor/persist; then
    mkdir -p /mnt/vendor/persist
    for src in \
        /dev/disk/by-partlabel/persist \
        /dev/disk/by-name/persist \
        /dev/block/platform/bootdevice/by-name/persist \
        /dev/block/by-name/persist
    do
        if try_mount "$src" /mnt/vendor/persist rw; then
            log "mounted $src on /mnt/vendor/persist"
            break
        fi
    done
fi

exit 0

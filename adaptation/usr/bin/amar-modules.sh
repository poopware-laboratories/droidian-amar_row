#!/bin/sh
#
# Lenovo Tab M10 HD (2nd gen) / MT6762 - vendor module bring-up
#
# The Wi-Fi, Bluetooth, GPS and FM drivers on MediaTek platforms are
# shipped as prebuilt kernel modules inside the stock vendor partition
# (/vendor/lib/modules).  Rebuilding the out-of-tree connectivity tree
# is fragile, so we reuse those modules and force-load them: their
# vermagic carries the stock release string instead of ours.
#
# This is the same approach the Xiaomi Redmi 9C (angelica) Droidian
# port uses.
#
# /vendor is a symlink to /android/vendor and is mounted by
# android-mount.service before this unit runs.

KREL="$(uname -r)"
MODDIR="/lib/modules/${KREL}"

mkdir -p "${MODDIR}"

# MediaTek drivers request their firmware by name (WIFI_RAM_CODE_6765,
# BT_RAM_CODE_*, ...).  The files live on the stock vendor partition, so
# point the firmware loader there before anything is modprobed.
if [ -w /sys/module/firmware_class/parameters/path ]; then
    printf '%s' "/vendor/firmware" > /sys/module/firmware_class/parameters/path
fi

if [ -d /vendor/lib/modules ]; then
    for module in /vendor/lib/modules/*.ko; do
        [ -e "${module}" ] || continue
        cp -f "${module}" "${MODDIR}/"
    done
fi

# Rebuild the dependency database.  Failures here are non-fatal: the
# modules can still be force-loaded by name.
depmod -a "${KREL}" 2>/dev/null || true

# wmt_drv exports the symbols used by the other connectivity modules,
# so it has to come first.  Everything is best-effort: a missing module
# (e.g. fmradio on the Wi-Fi-only variant) must not abort the unit.
for module in wmt_drv wmt_chrdev_wifi wlan_drv_gen4m bt_drv gps_drv fmradio_drv fpsgo met; do
    modprobe -f "${module}" 2>/dev/null || true
done

exit 0

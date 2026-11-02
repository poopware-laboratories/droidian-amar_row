# Droidian on the Lenovo Tab M10 HD (2nd gen)

Port of [Droidian](https://droidian.org) (Debian + libhybris/Halium) to the
Lenovo Tab M10 HD 2nd gen:

| Model     | Codename        | SoC            | Connectivity |
|-----------|-----------------|----------------|--------------|
| TB-X306X  | `amar_row_lte`  | MediaTek MT6762 | LTE + Wi-Fi + BT |
| TB-X306F  | `amar_row_wifi` | MediaTek MT6762 | Wi-Fi + BT |

Both variants are supported from the same tree. Everything is built on top of
the Lenovo Android 11 kernel sources (`S220054_210625`, Linux 4.19.127) and
reuses the prebuilt device trees / DTBO from the Ubuntu Touch port, which are
known to work on this tablet.

> **Status:** the kernel, boot image, DTBO, vbmeta, patched Droidian rootfs
> and recovery installer zip are built and ready to flash. The boot image
> header, addresses and embedded DTB were byte-compared against the working
> Ubuntu Touch boot image for this tablet, and the injected rootfs was
> re-read and verified after patching. It has **not** been tested on physical
> hardware yet (no device was attached while building), so treat the first
> boot as bring-up work. See *Known limitations*.

---

## Repository layout

```
droidian-port/
├── adaptation/                 device files injected into the rootfs
│   ├── etc/udev/rules.d/       MTK device permissions + touchscreen
│   ├── etc/ofono/              MediaTek RIL configuration
│   ├── etc/pulse/              libhybris audio card configuration
│   ├── etc/phosh/phoc.ini      panel / scale configuration
│   ├── etc/systemd/system/     amar-modules.service
│   └── usr/                    module loader, vendor HAL override, ...
├── prebuilt/
│   ├── initrd.img-halium-generic   Droidian arm64 initramfs
│   ├── amar_row_lte_dtb            base DTB used by the LTE boot image
│   ├── amar_dtb                    base DTB used by the Wi-Fi boot image
│   └── amar_dtbo.img               device tree overlay
├── scripts/
│   ├── env.sh                  shared configuration
│   ├── gen-defconfig.sh        regenerate the Droidian defconfig
│   ├── build-kernel.sh         build Image.gz + modules
│   ├── make-images.sh          boot.img / dtbo.img / vbmeta.img
│   ├── inject-rootfs.sh        patch a Droidian rootfs image
│   ├── make-installer-zip.sh   recovery-flashable rootfs zip
│   ├── flash-boot.sh           fastboot helper
│   └── rebuild-all.sh          run all of the above
├── tools/                      mkbootimg, avbtool, mkdtboimg + gki module
└── out/<variant>/              build artifacts (git-ignored)
```

The kernel tree itself lives in
`../tb-x306x_opensource_tb-x306x_s220054_210625_bmp/kernel-4.19`.

---

## Requirements

Host packages (Debian/Ubuntu):

```
sudo apt install build-essential bc bison flex libssl-dev libelf-dev \
                 python3 python3-pip zip unzip e2fsprogs android-sdk-platform-tools
```

The prebuilt Android clang (`clang-r383902`) and the aarch64 GCC 4.9
toolchain from the Lenovo source drop are used, so no cross compiler
installation is needed.

Space: ~10 GiB free for the kernel build plus ~12 GiB for the rootfs and
the installer zip.

---

## Building

```bash
cd droidian-port

# LTE tablet (TB-X306X) - default
./scripts/rebuild-all.sh

# Wi-Fi tablet (TB-X306F)
VARIANT=wifi ./scripts/rebuild-all.sh
```

Individual steps:

```bash
./scripts/gen-defconfig.sh        # only when fragments change
./scripts/build-kernel.sh         # kernel + modules
./scripts/make-images.sh          # boot.img, dtbo.img, vbmeta.img
./scripts/inject-rootfs.sh        # patched rootfs.img
./scripts/make-installer-zip.sh   # recovery zip
```

Artifacts land in `out/<variant>/`:

| File                        | Purpose | Typical size |
|-----------------------------|---------|--------------|
| `boot.img`                  | kernel + Droidian initramfs + DTB | ~28 MB |
| `dtbo.img`                  | device tree overlay | 120 KB |
| `vbmeta.img`                | AVB metadata with verification disabled | 4 KB |
| `rootfs.img`                | Droidian rootfs with modules/adaptation/boot images injected | 5 GiB sparse (~3.7 GiB used) |
| `droidian-amar_row_*.zip`   | recovery-flashable installer | ~1.5 GB |

Kernel object trees are kept separately: `out-droidian/` for LTE (the same
name Lenovo's `build_kernel.sh` uses) and `out-droidian-wifi/` for Wi-Fi, both
inside the kernel source directory. A full build takes roughly 20 minutes on
four cores.

`inject-rootfs.sh` expects the stock Droidian image at
`work/rootfs/data/rootfs.img` (override with `ROOTFS_SRC=/path/to/rootfs.img`).
The image used here is
`droidian-OFFICIAL-phosh-phone-rootfs-api30-arm64-101.20251130`.

`inject-rootfs.sh` always copies from `ROOTFS_SRC` into a fresh `rootfs.img`
and grows it by `GROW_MB` (default 1024). To patch an already-copied image
without copying or growing it again, use `INPLACE=1`. Because the userdata
partition must hold both the 5 GiB rootfs image and `/data`, make sure there
is enough room before flashing (8 GiB is a comfortable minimum).

### Kernel configuration notes

* `CONFIG_ANDROID_BINDERFS` is disabled (the `select` in the MediaTek
  `Kconfig.default` is commented out). Debian userspace expects the classic
  `/dev/binder`, `/dev/hwbinder` and `/dev/vndbinder` nodes created from
  `CONFIG_ANDROID_BINDER_DEVICES`.
* `CONFIG_MODULE_FORCE_LOAD` allows the stock vendor modules
  (`wmt_drv`, `wlan_drv_gen4m`, `bt_drv`, `gps_drv`, ...) from
  `/vendor/lib/modules` to be loaded even though their vermagic says
  `4.19.127-gc27c4c16e`.
* `CONFIG_SCHED_TUNE` / `CONFIG_CGROUP_SCHEDTUNE` are kept because the
  vendor `fpsgo` and `met` modules need them.
* The Wi-Fi/BT/GPS/FM drivers are **not** compiled from
  `vendor/mediatek/kernel_modules/connectivity`; the stock modules are reused
  at runtime. `CONFIG_WLAN_DRV_BUILD_IN` is intentionally left unset.

---

## Installation

### 0. Firmware and prerequisites

* The tablet must be on Android 11 firmware `S220054_210625` (or a compatible
  Lenovo Android 11 release). Keep the stock `vendor` and `nvram` partitions.
* Unlock the bootloader (`fastboot flashing unlock` / Lenovo unlock tool) and
  enable "OEM unlocking".
* Keep a copy of the stock firmware images so you can restore the tablet.
* Do **not** flash anything to `vendor`, `nvram`, `persist` or `super`.

### 1. Install the rootfs

The Droidian initramfs uses the *Halium file layout*: the `userdata`
partition is a normal ext4 filesystem that contains `/rootfs.img`. The
rootfs is **not** the userdata filesystem itself.

**Option A - recovery zip (recommended)**

1. Boot into a recovery that can mount `/data` unencrypted (TWRP for the
   TB-X306X/F, or the Halium recovery from the Ubuntu Touch port).
2. If the tablet still has Android userdata, format `/data` first
   (this erases everything).
3. Sideload/flash `out/lte/droidian-amar_row_lte.zip`.
   The zip copies `rootfs.img` to `/data`, resizes it and, because
   `boot.img`, `dtbo.img` and `vbmeta.img` were injected into
   `/boot` inside the rootfs, also flashes them.
4. Reboot to the bootloader and flash the images manually (step 2) if the
   zip could not flash them.

**Option B - manual push**

```bash
# in recovery, with /data mounted
adb push out/lte/rootfs.img /data/rootfs.img
adb shell sync
```

Then flash the boot images from the bootloader (step 2).

### 2. Flash boot images

```bash
cd droidian-port
./scripts/flash-boot.sh          # boots the images in out/lte/
# or manually:
fastboot flash boot    out/lte/boot.img
fastboot flash dtbo    out/lte/dtbo.img
fastboot --disable-verity --disable-verification flash vbmeta out/lte/vbmeta.img
fastboot reboot
```

`dtbo.img` is required: the kernel boot image only embeds the base DTB, the
board-specific overlay lives in the `dtbo` partition.

### 3. First boot

The first boot takes several minutes (the initramfs runs a full `e2fsck` of
the userdata partition). The default `root`/`droidian` password is `1234`.

---

## How the port works

* **Boot chain** - the stock preloader/LK boots `boot.img` (header v2,
  2048-byte pages, base `0x40078000`, kernel `0x8000`, ramdisk
  `0x11a88000`, tags/DTB `0x07808000`). The base DTB is embedded in the
  boot image and the board overlays are applied from `dtbo.img`, exactly as
  the working Ubuntu Touch port does it.
* **Rootfs** - Droidian's generic arm64 initramfs mounts the userdata
  partition, finds `/rootfs.img`, mounts it, and then binds the Halium
  Android 11 system image (inside `/var/lib/lxc/android/android-rootfs.img`)
  into an LXC container.
* **Vendor** - `android-mount.service` mounts the stock `vendor` partition
  (and `persist`) using the DT fstab, then overlays
  `/usr/lib/droid-vendor-overlay` on top of it.
* **Modules** - `amar-modules.service` (enabled via the injected
  `multi-user.target.wants` symlink) copies `/vendor/lib/modules/*.ko` into
  `/lib/modules/$(uname -r)`, runs `depmod` and force-loads
  `wmt_drv` → `wmt_chrdev_wifi` → `wlan_drv_gen4m` → `bt_drv` → `gps_drv` →
  `fmradio_drv` → `fpsgo` → `met`. It runs after `lxc@android.service` and
  before `droidian-boot-wlan.service`.
* **Adaptation** - the files under `adaptation/` provide the MTK device node
  permissions (`70-amar.rules`), the touchscreen quirk, the MTK RIL
  configuration for oFono, the libhybris audio card, the PQ HAL disable
  overlay and a tablet-friendly Phosh scale.

### Partition layout (stock, A-only, dynamic partitions)

```
boot        -> boot.img      dtbo -> dtbo.img      vbmeta -> vbmeta.img
userdata    -> ext4, contains /rootfs.img
super       -> dynamic partitions: system / vendor / product
               (vendor holds the modules and firmware) - DO NOT TOUCH
nvram/persist/metadata -> stock - DO NOT TOUCH
```

The stock `recovery.fstab` marks `system`, `vendor` and `product` as
`logical,first_stage_mount`, so they live inside `super`. The generic
`mount-android.sh` maps `super` with `parse-android-dynparts` +
`dmsetup create --concise` and mounts `/dev/mapper/dynpart-vendor` on
`/vendor`. The extra `amar-mount-vendor.sh` pre-mount step only exists for
firmware where `vendor` is a real `by-name` partition; on this tablet it is a
harmless no-op and the generic path does the work.

---

## Known limitations / bring-up notes

These are the items that still need testing or work on a physical device:

* **Untested on hardware.** Nothing in this tree has been booted on a
  TB-X306X/F yet (no device was available during development). The boot
  image layout and DTBs are copied from the working Ubuntu Touch port, so
  they are the most likely parts to be correct.
* **Modem / telephony.** oFono is configured for MediaTek `radio@1.4`
  (`etc/ofono/ril_subscription.d/mtk.conf`). VoLTE is disabled the same way
  as on the Ubuntu Touch port. Calls/SMS/data need testing; IMS/VoLTE is
  expected not to work.
* **Wi-Fi.** Reuses the stock `wmt_drv`/`wlan_drv_gen4m` modules. The
  firmware is loaded from the stock `vendor` partition. If `wlan0` does not
  appear, check `dmesg` for `wmt`/`wlan` errors and that
  `/dev/wmtWifi` exists.
* **Bluetooth.** `bluebinder` + the stock `bt_drv` module. The MAC address
  is taken from the Android properties by the generic
  `bluebinder_post.sh`; if it is empty, Bluetooth will not start.
* **Camera / GPS / FM / sensors.** The kernel drivers and vendor HALs are
  present but untested. The camera needs the stock vendor partition and may
  require additional `droid-vendor-overlay` fixes.
* **Audio.** Uses the `module-droid-card` PulseAudio module with
  `quirks=+no_hw_volume`. Call audio routing needs testing.
* **Rootfs size.** The installer resizes the rootfs to 8 GiB, leaving the
  rest of userdata for `/data` (photos, documents, ...). Edit `setup.sh` or
  create `/.full_resize` in the image if you want the rootfs to fill
  userdata instead.
* **Boot partition size.** The Droidian generic initramfs is much larger than
  the Ubuntu Touch one, so `boot.img` is about 28 MB. If `fastboot flash boot`
  reports a size error, the stock `boot` partition is smaller than that; trim
  firmware from the initramfs (`prebuilt/initrd.img-halium-generic`) or build
  the boot image without the embedded DTB.
* **Battery/charger.** `mt6359_battery.ko` and `mt6359-accdet.ko` are built as
  modules and are expected to be autoloaded by udev from their device-tree
  aliases. If the battery indicator stays empty, check
  `lsmod | grep mt6359`.
* **No OTA packages.** The kernel is installed by injecting modules into the
  rootfs image; rebuilding on device requires re-running the scripts.

## Debugging

* Serial console: the tablet exposes UART on the headphone/debug pads; the
  kernel cmdline already contains MTK's `bootopt=` string.
* `dmesg` and `journalctl -b` from a root shell (or over SSH/USB networking).
* The Droidian initramfs logs to `/run/e2fsck.out` and the kernel log.
* If the display stays black, check that `dtbo.img` was flashed and that the
  boot image contains the correct base DTB (`amar_row_lte_dtb` for LTE,
  `amar_dtb` for Wi-Fi).
* Restore path: flash the stock `boot`, `dtbo`, `vbmeta` and a stock
  `userdata` image (or `fastboot -w`) to get back to Android.

## Credits

* Lenovo for the Android 11 kernel source release.
* The Ubuntu Touch Lenovo Tab M10 HD port for the prebuilt DTBs, DTBO and
  the verified boot image layout.
* The Droidian project and the `droidian-devices/common_fragments` 4.19
  kernel fragments.
* The Xiaomi Redmi 9C (angelica) Droidian port for the MTK adaptation
  reference (udev rules, module loading, audio, oFono).

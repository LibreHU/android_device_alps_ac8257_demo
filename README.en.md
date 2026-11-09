# LineageOS 16.0 for the UJC201 (Jancar, Autochips AC8257)

*Français : [README.md](README.md)*

**LineageOS 16.0 (Android 9)** device tree for the Jancar UJC201 head unit (`ac8257_demo`, Autochips AC8257 SoC,
MediaTek MT6761 family). A real ROM built from the LineageOS sources, not a GSI.

**Status: starting tree, not built nor tested on the unit yet.**

## Branches

| Branch | Content |
|---|---|
| `twrp` (default) | TWRP recovery for the UJC201, with its CI and releases |
| **`lineage-16.0`** | this branch: LineageOS 16.0 ROM |

Kernel: [android_kernel_autochips_ac8257_4.9](https://github.com/LibreHU/android_kernel_autochips_ac8257_4.9)
(`stable-4.9.337`: Autochips GPL sources + LibreHU changes + linux-stable fixes up to 4.9.337, the only branch
maintained since 01/11/2026). Apps: the `LibreHU-*` repositories of [LibreHU](https://github.com/LibreHU).

## Approach

The unit is **Treble**: separate Android 9 vendor partition (`ro.treble.enabled=true`, `ro.vndk.version=28`,
`ro.product.first_api_level=28`), system-as-root. The framework manifest of the stock `/system` is AOSP's: no
system-side HAL of Jancar's or MediaTek's own. Hence, for phase 1:

| Partition | Content |
|---|---|
| `system` | **LineageOS 16.0 built here** + LibreHU apps (service, launcher, OTA, ViPER4Android, phone, FM, widgets, BtnRemap, EasySource, Disc, MCU Toolkit, Android Auto, CarPlay) + `mcu_ready` |
| `vendor` | **stock vendor**, read from the unit (`tools/get_vendor_img.sh`) and reused (`BOARD_PREBUILT_VENDORIMAGE`), with the ViPERFX_RE driver added (`tools/vendor_add_viper.sh`); stays with you (2 GiB, specific to the unit) |
| `boot` | **boot image from the CI of the LibreHU kernel** `stable-4.9.337` (`tools/fetch_kernel.sh` -> `prebuilt/boot-librehu-bootmenu.img`, taken as it is: `BOARD_PREBUILT_BOOTIMAGE`): header, command line and **AVB footer of the stock boot**, without which the LK refuses the image (reboot at the logo); KernelSU Next for root, TWRP / Android / Fastboot boot menu. LineageOS builds no `boot.img` (see [prebuilt/README.md](prebuilt/README.md)) |
| `dtbo`, `vbmeta`, `lk`, `tee`... | stock, unchanged |
| `recovery` | TWRP (`twrp` branch); LineageOS builds none (`TARGET_NO_RECOVERY`), its zip does not touch it |

LineageOS 16.0 is the only LineageOS version at the same level as Android 9: VNDK 28 and SELinux policy 28.0 match
the stock vendor, with no compatibility layer.

### What the tree contains

| File | Role |
|---|---|
| `BoardConfig.mk` | architecture (Cortex-A53, arm64 + arm), boot (header v1, stock addresses), partitions (eMMC table of kernel #72), prebuilt vendor, VNDK, `SKIP_BOOT_JARS_CHECK` (the `com.autochips.*` package of `autochips.jar` is not in AOSP's whitelist) |
| `lineage_ac8257_demo.mk`, `AndroidProducts.mk`, `vendorsetup.sh` | `lineage_ac8257_demo` product (phone profile: 4G modem), stock vendor fingerprint; **adb without authorization from boot and `adb root` allowed, in every build** (LineageOS `WITH_ADB_INSECURE`: `ro.adb.secure=0`, `persist.sys.usb.config=adb`; `persist.sys.root_access=2`; userdebug and eng only, see "Install") |
| `device.mk` | 1280 x 720 at 160 dpi (stock `wm size`), stock properties, overlays, packages; **persistent logs in every build** (`persist.logd.logpersistd=logcatd` + `logpersist.start`: all logcat buffers in `/data/misc/logd/`, at most 256 files of 1 MiB); call ECNR on as on the stock; `PRODUCT_BOOT_JARS += autochips` |
| `overlay/` | on-screen navigation bar, no auto brightness, fixed landscape, screen always on |
| `mcu_ready/` | native service: sends `PC_READY` to the Jancar MCU (`/dev/ttyS1`) from boot until it answers. **Required**: without it the MCU cuts the SoC about ten seconds after boot (on the stock, `com.jancar.services` sends it) |
| `librehu/` | LibreHU apps, **all in `/system/priv-app`** (as LibreHU-service asks: `SET_TIME`, Bluetooth, reliable start), with the whitelist of their privileged permissions `privapp-permissions-librehu.xml` (LineageOS enforces `ro.control_privapp_permissions=enforce`: a missing permission makes `system_server` crash at boot; `check_privapp.py`, run by `fetch_apks.sh`, checks each APK): **LibreHU-service** (`latest-main`), **LibreHU Launcher** `librehu-service` edition (only home screen, replaces Trebuchet), **LibreHU Apps / OTA** (`latest-main`); APKs downloaded by `fetch_apks.sh`, original signature kept: the OTA app then updates them as on the stock ROM. **ViPER4Android LibreHU** 2.1.1 (`latest-librehu-service`). Also: **phone**, **FM radio**, **widgets** and **BtnRemap** (`librehu-service` edition), **EasySource**, **Disc**, **MCU Toolkit** (`latest-main`), **Android Auto** (Open Headunit LibreHU, `latest-main`) and **CarPlay** (xcertplay LibreHU, `latest-master`); a missing APK is skipped. All signed with the LibreHU key: the OTA app updates them. `ksunext/`: **KernelSU Next v3.4.2 manager** (version pinned to the kernel API, checksum checked by `fetch_apks.sh`), kept in `/system/etc/librehu/` and installed into `/data/app` at first boot by `librehu_ksunext`: the kernel only recognises its manager there (`throne_tracker.c`), never as a system app |
| `proprietary-files.txt`, `extract-files.sh`, `setup-makefiles.sh` | proprietary `/system` files taken from stock V1.151R6: Autochips HIDL interfaces (rear camera, AVM, fast display, iAP2, ATC audio...), `autochips.jar` (BOOTCLASSPATH, pinned by SHA-1) and its JNI libraries, `libusbdvr.so`. They are in the [android_vendor_jancar_ac8257_demo](https://github.com/LibreHU/android_vendor_jancar_ac8257_demo) repository (`lineage-16.0` branch, cloned by the local manifest); `extract-files.sh` is only for another firmware |
| `tools/get_vendor_img.sh` | reads the vendor partition of the unit (read only) |
| `tools/vendor_add_viper.sh` | adds to the local vendor image (debugfs, copy `vendor.img.orig` kept) the [ViPERFX_RE](https://github.com/likelikeslike/ViPERFX_RE) v2.1.1 driver (official module, SHA-256 checked): `libv4a_re.so` in `/lib[64]/soundfx` and the `v4a_standard_re` effect in `/etc/audio_effects.xml`, like the `viper4android-re` zip of LibreHU-flashablesZips. In vendor because under Android 9 Treble effects are loaded by the vendor audio HAL, which cannot load a library from `/system` |
| `tools/fetch_kernel.sh` | LibreHU kernel `stable-4.9.337` (`Image.gz-dtb`) and its Wi-Fi / BT / GPS / FM modules from the `latest-stable-4.9.337` release (GitHub checksums checked, image kernel = modules kernel); not versioned |
| `tools/vendor_add_conn_modules.sh` | puts these modules in `/lib/modules` of the local vendor image (debugfs, rights and SELinux context of the original, `.librehu_conn` marker, copy `vendor.img.orig` kept): the LibreHU kernel refuses those of the stock vendor (different symbol CRCs), as the `kernel-stable` zips do on the unit |
| `sepolicy/private/` | SELinux domain of `mcu_ready` (system side, `BOARD_PLAT_PRIVATE_SEPOLICY_DIR`): without it, Android 9's init **refuses to start the service, even in permissive** ("has incorrect label or no domain transition", `init/service.cpp`), PC_READY is not sent and the MCU cuts the SoC about ten seconds after boot; same for `librehu_ksunext` |
| `config.fs`, `BOARD_ROOT_EXTRA_FOLDERS` | stock mount points at the root of `system`: `/jancar` (0755 root:root, `jancar` partition of the vendor fstab) and `/avm` (0775 root:system). Without `/jancar`, `fs_mgr` cannot mount the partition (read-only root), `mount_all` fails and init does not start the `main` class (zygote): Android does not start. Found by Reo Au In. `/vendor` is created by the build |
| `rootdir/etc/init/librehu.rc` | stock `persist` values an empty `/data` lacks (stock getprop, LibreHU Helper report): `persist.vendor.connsys.chipid` set to `0x8257` at `early-boot` if it is `-1` (vendor build.prop) or `0x0000`, before `wmt_loader` (Wi-Fi) starts; ECNR vendor property aligned on the persist one |
| `rootdir/etc/fstab.ac8257` | stock vendor fstab |

## Build from scratch

**Detailed step-by-step guide** (Proxmox LXC container, Ubuntu 20.04, sources, unit files, build of the flashable zip
and images, install, updates, troubleshooting): [docs/BUILD.en.md](docs/BUILD.en.md). Summary below.

### 1. Machine
- Linux x86-64; **Ubuntu 18.04 or 20.04** recommended (LineageOS 16.0 dates from these versions; on newer ones,
  Python 2 and a few settings are needed).
- **About 200 GB free** (sources + output), **16 GB of RAM** recommended (less = slower; enable zram), SSD. The
  LineageOS wiki gives 200 GB from 17.1 on ([build guide](https://wiki.lineageos.org/devices/s2/build/)).
- The free GitHub CI is not enough (14 GB of disk, 6 h per job): build on a PC or a self-hosted runner.

```bash
sudo apt install bc bison build-essential ccache curl flex g++-multilib gcc-multilib git gnupg gperf \
  imagemagick lib32ncurses5-dev lib32readline-dev lib32z1-dev liblz4-tool libncurses5 libncurses5-dev \
  libsdl1.2-dev libssl-dev libxml2 libxml2-utils lzop pngcrush rsync schedtool squashfs-tools xsltproc zip \
  zlib1g-dev python2 unzip adb
# The Android 9 build calls "python" = Python 2
sudo ln -sf /usr/bin/python2 /usr/local/bin/python
mkdir -p ~/bin && curl -o ~/bin/repo https://storage.googleapis.com/git-repo-downloads/repo && chmod a+x ~/bin/repo
export PATH=~/bin:$PATH
git config --global user.name "Your name" && git config --global user.email "you@example.com"
```

### 2. LineageOS 16.0 sources + this tree
```bash
mkdir -p ~/android/lineage && cd ~/android/lineage
repo init -u https://github.com/LineageOS/android.git -b lineage-16.0 --depth=1
mkdir -p .repo/local_manifests
cat > .repo/local_manifests/ujc201.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <project name="LibreHU/android_device_alps_ac8257_demo" path="device/alps/ac8257_demo"
           remote="github" revision="lineage-16.0" />
  <project name="LibreHU/android_vendor_jancar_ac8257_demo" path="vendor/jancar/ac8257_demo"
           remote="github" revision="lineage-16.0" />
</manifest>
EOF
repo sync -c -j"$(nproc)" --no-tags --no-clone-bundle
```

### 3. Unit files and LibreHU apps
The unit under TWRP (adb root) or under the stock ROM with root, plugged in over USB:
```bash
device/alps/ac8257_demo/tools/get_vendor_img.sh      # -> vendor/jancar/ac8257_demo/vendor.img (2 GB, stays local)
device/alps/ac8257_demo/tools/vendor_add_viper.sh    # ViPERFX_RE driver in this image (sudo apt install e2fsprogs)
device/alps/ac8257_demo/tools/fetch_kernel.sh        # LibreHU kernel stable-4.9.337: boot images + modules (prebuilt/)
# (tools/fetch_kernel.sh test-wifi-chipid: test branch, Wi-Fi chip id fix)
device/alps/ac8257_demo/tools/vendor_add_conn_modules.sh  # these modules in the vendor image (Wi-Fi, BT, GPS, FM)
cd device/alps/ac8257_demo
# proprietary /system files: already in the vendor repo (local manifest); firmware other than V1.151R6:
# ./extract-files.sh (from the unit, adb) or ./extract-files.sh ~/stock (docs/BUILD.en.md, step 5)
librehu/fetch_apks.sh                                # latest LibreHU APKs (every app of the ROM) + KernelSU Next manager
cd ~/android/lineage
```

### 4. Build
```bash
export LC_ALL=C USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache && ccache -M 50G
source build/envsetup.sh
lunch lineage_ac8257_demo-userdebug
mka systemimage           # phase 1: system.img only (boot and vendor stay those of the unit)
mka bootimage             # boot.img = copy of prebuilt/boot-librehu-bootmenu.img (kernel CI, stock AVB footer)
# or all at once: mka bacon (images + TWRP flashable zip, which writes system and boot; vendor: docs/BUILD.en.md)
```
Result: `out/target/product/ac8257_demo/system.img`.

### 5. Install (phase 1)
Nothing is automated. First:
1. **Full backup**: SP Flash Tool (readback) with the stock scatter, and a TWRP backup of `system`, `vendor`, `boot`,
   `data`. Keep `para` too (`dd if=/dev/block/by-name/para of=...`).
2. **vbmeta**, once, by hand (never done by these tools):
   `fastboot --disable-verity flash vbmeta vbmeta.img` (stock vbmeta).
3. In TWRP: *Install > Install Image* > `system.img` > **System Image**, then *Wipe > Format Data* (LineageOS does not
   start on the data of the stock ROM).
4. Going back: restore the TWRP backup (or SP Flash Tool).

Root: LineageOS 16.0 only gives root to adb; several LibreHU-service features need it (as on the stock). The LibreHU
kernel contains KernelSU Next; its manager (v3.4.2) is **installed by itself** into `/data/app` once Android has
started (log: `logcat -s LibreHU-KSU`). Open it, then the Superuser tab: allow LibreHU-service (KernelSU asks
nothing). With the stock kernel, add Magisk.

adb: **on and without authorization from the first boot**, in every userdebug or eng build (the one of
[docs/BUILD.en.md](docs/BUILD.en.md)); in `user`, Android 9 always asks for authorization (`ALLOW_ADBD_NO_AUTH`).
`adb root` is allowed by default (*Developer options > Root access* on "ADB only", `persist.sys.root_access=2`); adbd
starts as shell, type `adb root` once per boot. Warning: anyone who plugs a computer into the unit's USB port gets a
shell, then root, with no confirmation on screen. Setting it back to "Disabled" in the settings closes root (value
kept in `/data`).

Logs: `logcat` of all buffers recorded continuously in `/data/misc/logd/` (kept across a restart, at most 256 MiB).
Read as root: `adb root` then `adb pull /data/misc/logd`, or `su -c 'cat /data/misc/logd/logcat*'`. Kernel log of the
previous boot: `/proc/last_kmsg` (docs/BUILD.en.md, Troubleshooting).

USB: file transfer with a computer (MTP) is **off by default** in LibreHU-service (Advanced -> Autochips setting);
LineageOS has MediaProvider's `MtpReceiver`, so the MTP server starts by itself once the setting is on (on the stock
ROM, the service starts it).

## Roadmap

1. **Starting tree** — ✅ this branch (20/10/2026), not built.
2. **First build** of `system.img` and **first boot** on stock vendor + boot: screen, touch, adb, Wi-Fi, Bluetooth,
   GPS (stock vendor modules), audio (vendor ATC HAL), MCU (`mcu_ready` then LibreHU-service).
3. **Head unit features** with the LibreHU apps: MCU / CAN, steering wheel keys, FM radio, rear camera and AVM, AV-in,
   phone (MediaTek RIL `c6m_1rild` with AOSP telephony), Android Auto / CarPlay.
4. **SELinux policy** of the device: domain of `mcu_ready` done (09/11/2026, required for init to start it); then its
   rules and those of the apps, then enforcing mode (permissive today, like the stock).
5. **LibreHU kernel** instead of the stock kernel, root (KernelSU Next) — in the tree since 01/11/2026; since
   09/11/2026, `boot.img` is the kernel CI image (stock AVB footer), connectivity modules in vendor, to be tested.
6. **Proprietary `/system` files** in a vendor repository — ✅ 09/11/2026: Autochips HIDL interfaces, deodexed
   `autochips.jar` (`PRODUCT_BOOT_JARS`) and its JNI libraries ([android_vendor_jancar_ac8257_demo](https://github.com/LibreHU/android_vendor_jancar_ac8257_demo)), not built.
7. **Full LineageOS zip** (`mka bacon`) installable from TWRP, builds published and updated by the OTA app.

## Known risks

First try by a tester (Reo Au In, 08/11/2026, build of the 07/11 branch): Android started, then the unit restarted
after about ten seconds; no log. Fixed here since (09/11), to be tried again:
- **`mcu_ready` never started** (no SELinux domain, see `sepolicy/`): without PC_READY, the MCU cuts the SoC about ten
  seconds after boot;
- **LineageOS `boot.img` without AVB footer**: refused by the LK (reboot at the logo); it is now the kernel CI image;
- **LibreHU apps in `/system/app`**: without their privileged permissions (time, Bluetooth, widgets...); all in
  `/system/priv-app` with their whitelist;
- **`/jancar` and `/avm` missing from the root** (seen by Reo Au In, who had added them by hand): without `/jancar`,
  `mount_all` fails and init starts neither zygote nor the rest of the `main` class; created by the build since 09/11.

Reo Au In also repaired his 07/11 zip his own way (unsigned vbmeta written by the zip, AVB footer and first-mount flag
removed, vendor hash tree rebuilt, `fpsgo.ko` disabled): this repository keeps its rules (vbmeta never written,
`fastboot --disable-verity` by hand; kernel CI boot image with the stock AVB footer); the stock `fpsgo.ko` is refused
by the LibreHU kernel with no other effect (docs/STABLE.md of the kernel).

Still open:
- **Wi-Fi: chip id `0x0000`**: on an empty `/data` (Format Data), the `stable-4.9.337` kernel answered 0 to the chip id
  request of `wmt_loader`, which stores it in `persist.vendor.connsys.chipid`; the Wi-Fi driver then starts with chip 0
  and the unit reboots in a loop as soon as Wi-Fi turns on (seen by Reo Au In, fixed on his side with
  `setprop persist.vendor.connsys.chipid 0x8257`). Since 09/11, `rootdir/etc/init/librehu.rc` sets `0x8257` at
  `early-boot` (before `wmt_loader`, whatever the kernel) and replaces a `0x0000` already stored; kernel fix also in
  the `test-wifi-chipid` test branch (`tools/fetch_kernel.sh test-wifi-chipid`). Both are to be tried.
- **`autochips.jar`** (09/11): on the stock, the Autochips classes are in `/system/framework/autochips.jar` (in the
  `BOOTCLASSPATH`); without it, LibreHU-service cannot hand the display back to Android after the ARM2 (green hardware
  video: cameras, AV-in) nor read the Autochips settings. Deodexed from `boot-autochips.vdex` (stock V1.151R6) in the
  [android_vendor_jancar_ac8257_demo](https://github.com/LibreHU/android_vendor_jancar_ac8257_demo) repository
  (`lineage-16.0` branch, local manifest above), pinned in `proprietary-files.txt`, `PRODUCT_BOOT_JARS += autochips`
  (`device.mk`), with its JNI libraries (`lib{,64}/lib{atcavm,atcvobsub,dvr,logo,metazone}_jni.so`) and `libusbdvr.so`
  (needed by `libdvr_jni.so`), in `proprietary-files.txt` and the vendor repository like the HIDL interfaces. **Not
  built nor tried yet** (expected: `echo $BOOTCLASSPATH` contains `autochips.jar`, LibreHU-service finds
  `AtcMetazone`, `AtcLogo`, `BackCar`, with no `ClassNotFoundException` nor `UnsatisfiedLinkError`).
- **Other `persist` values of an empty `/data`**: taken from the `getprop` of a stock unit (LibreHU Helper report of
  04/11/2026, 415 `persist` properties, 331 of which come from the stock vendor `build.prop`, kept here). Taken over:
  `connsys.chipid` and call ECNR (`persist.audiohal.third_ecnr_lib.enable=1`). Left out: microphone gain (set again by
  LibreHU-service), `persist.sf.hwrotation=90` (AOSP's SurfaceFlinger only reads `ro.sf.hwrotation`, the screen is
  1280 x 720 rotation 0 on the stock), AEE (`persist.vendor.mtk.aee.mode=4`...: meaning not checked), picture quality
  `persist.vendor.sys.pq.*` and colours `persist.sys.rgb.*` (readers unknown without the vendor files), properties of
  the Jancar apps and their Bluetooth stack, user choices (car, language, time zone) and `persist.netd.stable_secret`
  (specific to each unit).

- **RIL**: MediaTek modem (`ro.vendor.mtk_ril_mode=c6m_1rild`, `mtk-ril.so`) with LineageOS's AOSP telephony: calls
  and data to be checked.
- **Jancar apps missing** (`com.jancar.*`, `com.autochips.*`): their features go through the LibreHU apps; what no
  LibreHU app covers yet will be missing.
- **Rotation and display**: the screen is 1280 x 720 landscape on the stock; to be checked at first boot.
- Nothing is built yet: build errors are likely on the first try, to be fixed here.

## Rules

- Nothing is written under dm-verity and vbmeta is never disabled automatically:
  `fastboot --disable-verity flash vbmeta vbmeta.img` by hand.
- Never publish a unit's own data: Bluetooth and Wi-Fi MAC addresses, serial number, Apple MFi certificate (so neither
  `nvram`, `nvdata`, `proinfo` as they are, nor `persist` / `metazone` unchecked). Jancar / Autochips / MediaTek
  proprietary files are published (vendor repository), checked before each addition.

## Smoothness of the LibreHU apps

The LibreHU apps (Jetpack Compose) are **precompiled to native code** (`speed`) when the ROM is built
(`PRODUCT_DEXPREOPT_SPEED_APPS` in `device.mk`, `LOCAL_DEX_PREOPT := nostripping` in `librehu/Android.mk`: the dex
stays in the APK, the original signature and updates in `/data` stay valid), and `pm.dexopt.install=speed` also
compiles installs and updates. Without this, Android 9 installs an app from outside the Play Store as
`speed-profile`, which without a profile is `verify` (no native code), and only compiles in the background when the
device is idle and charging, which almost never happens on a head unit (source.android.com, *Package Manager
configuration*). On the stock ROM, LibreHU-service does the same with root (Advanced → Tweaks → *Smoothness of the
LibreHU apps*).

## Licence

Copyright (C) 2026 the LibreHU contributors.

LibreHU files are under the **GNU AGPL v3 or later** (`AGPL-3.0-or-later`, [`LICENSE`](LICENSE) file), with the
[additional terms](LICENSE-ADDITIONAL-TERMS.md) of its section 7: keep the notice "Based on LibreHU –
https://github.com/LibreHU" and mark a modified version as such. Whoever distributes a modified version must give its
complete source code under the same licence. The others keep their licence:

| What | Where | Author | Licence |
|---|---|---|---|
| Base files of the tree (Apache-2.0 header kept) | `Android.mk`, `AndroidProducts.mk`, `BoardConfig.mk`, `device.mk`, `lineage_ac8257_demo.mk`, `extract-files.sh`, `setup-makefiles.sh`, `vendorsetup.sh` | [twrpdtgen](https://github.com/twrpdtgen/twrpdtgen) (SebaUbuntu), The Android Open Source Project, The LineageOS Project | Apache-2.0 |
| Stock kernel (binary of the Jancar update; source: `autochips-gpl` branch of the [kernel repository](https://github.com/LibreHU/android_kernel_autochips_ac8257_4.9/tree/autochips-gpl)) | `prebuilt/` | Jancar, AutoChips, the Linux authors | GPL-2.0 |

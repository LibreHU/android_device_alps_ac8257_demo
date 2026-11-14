# LineageOS 16.0 for the UJC201 (Jancar, Autochips AC8257)

*Français : [README.md](README.md)*

**LineageOS 16.0 (Android 9)** device tree for the Jancar UJC201 head unit (`ac8257_demo`, Autochips AC8257 SoC,
MediaTek MT6761 family). A real ROM built from the LineageOS sources, not a GSI.

**Status: built by GitHub's CI (first full build on 12/11/2026, TWRP zip: see
[BUILD.en.md](docs/BUILD.en.md#0-without-a-build-pc-githubs-ci)). Tries of 12/11 on the unit: boot menu, then
reboot to fastboot; two causes found and fixed (`vendor` mount refused by fs_mgr, SELinux policy:
[Known risks](#known-risks)). **LineageOS boots** (12/11 evening, `/init` fixed by hand by the tester): picture and touch
in portrait, brightness inverted, touch outside the screen without calibration; fixed in build `17daf55` (rotation,
backlight, calibration at boot). Feedback of 13/11 (previous build): fast, adb, MTP, USB host / device, mic, MCU,
LibreHU apps, Geekbench OK; kernel crashes (Wi-Fi without a country: zero channel scanned, connsys reset), Wi-Fi access
point not seen, Ethernet not taken by Android, hardware video green until a standby (ARM2 without LibreHU-service's
root), black lock screen, status bar too small. Build `befe5a3` (13/11): Wi-Fi country from the language, Ethernet feature,
KernelSU Next root granted to LibreHU-service out of the box, no lock screen, bigger bars, Aurora Store and LibreHU Helper
(MCU Toolkit removed). Green video: cause found on 13/11, the vendor `backcar` HAL cannot open `/dev/backcardrv` (made
0600 root by ueventd, the stock system held the rule); rule in `rootdir/ueventd.ac8257.rc` (build after `1ec65bc`,
confirmed on the unit on 13/11: no more green video). No sound at all (found by Reo Au In on 13/11): same cause,
`/dev/gpios_ioctl` made 0600 root, LibreHU-service could not release the amplifier mute (GPIO 166); ueventd rule with
the stock permissions (build after 14/11). Compared with the SP Flash Tool dump of the stock: `/dev/di` (video
deinterlacer, CVBS input) and the `/dev/i2c-0` to `5` buses (opened by the stock system's `init.jancar.rc`; LibreHU
CarPlay looks for the MFi chip there) were missing too: rules added. Build after `96472d7` (13/11): AudioFX removed (ViPER4Android
replaces it), update from the app installable in TWRP (uncrypt block map), kernel with a full battery on mains (Android
saw 0-1 %) and without the "MCE keyboard" IR decoder (fake physical keyboard); build `845e87b`: the front panel power
key wakes the locked unit (touch kept awake while the screen is off, reset when it comes back; being tested); being investigated: Bluetooth
streaming and settings, AV IN, audio routing, 5 GHz Wi-Fi. Every build is published as a [release](https://github.com/LibreHU/android_device_alps_ac8257_demo/releases)
(signed zip) and LineageOS's Updates app updates from them. **Install: [docs/INSTALL.en.md](docs/INSTALL.en.md)**
(vbmeta, flashing, updates, troubleshooting) or the [website page](https://librehu.github.io/lineageos.html).**

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
| `recovery` | TWRP (`twrp` branch); LineageOS builds none (`TARGET_NO_RECOVERY`), nothing writes it |

LineageOS 16.0 is the only LineageOS version at the same level as Android 9: VNDK 28 and SELinux policy 28.0 match
the stock vendor, with no compatibility layer.

### What the tree contains

| File | Role |
|---|---|
| `BoardConfig.mk` | architecture (Cortex-A53, arm64 + arm), boot (header v1, stock addresses), partitions (eMMC table of kernel #72), prebuilt vendor, VNDK, the vendor's XML audio policy (`USE_XML_AUDIO_POLICY_CONF`, like the stock; otherwise the goldfish emulator configuration), head unit Bluetooth stack (`bluetooth/`), `SKIP_BOOT_JARS_CHECK` (the `com.autochips.*` package of `autochips.jar` is not in AOSP's whitelist) |
| `lineage_ac8257_demo.mk`, `AndroidProducts.mk`, `vendorsetup.sh` | `lineage_ac8257_demo` product, **userdebug only** (in user: SELinux always enforcing, adb asks for authorization, permissive domains refused) (phone profile: 4G modem), stock vendor fingerprint; **adb without authorization from boot and `adb root` allowed, in every build** (LineageOS `WITH_ADB_INSECURE`: `ro.adb.secure=0`, `persist.sys.usb.config=adb`; `persist.sys.root_access=2`; userdebug and eng only, see "Install") |
| `device.mk` | 1280 x 720 at 160 dpi (stock `wm size`), stock properties, overlays, packages; **persistent logs in every build** (`persist.logd.logpersistd=logcatd` + `logpersist.start`: all logcat buffers in `/data/misc/logd/`, at most 256 files of 1 MiB); call ECNR on as on the stock; `PRODUCT_BOOT_JARS += autochips` |
| `overlay/` | on-screen navigation bar, no auto brightness, fixed landscape, screen always on; **USB tethering of an Android phone** taken as a wired network (`config_ethernet_iface_regex` = `(eth\|usb)\d+`: Android 9 only takes `eth\d`, Linux names this tethering `usb0`; zip `usb-tethering` for the stock ROM); **Bluetooth profiles of a car** (`packages/apps/Bluetooth`: HFP client tied to Telecom, A2DP sink, AVRCP controller, PBAP and MAP client; phone roles off), those of the Android 9 reference car (`packages/services/Car`) |
| `bluetooth/bdroid_buildcfg.h` | Bluetooth stack (`BOARD_BLUETOOTH_BDROID_BUILDCFG_INCLUDE_DIR`): the head unit declares itself as a **car** (class of device `0x240420`: Audio + Rendering, Audio/Video, "Car audio"; smartphone by default) and A2DP sink is built (`BTA_AV_SINK_INCLUDED`, false by default: without it no "Audio Sink" SDP record) |
| `mcu_ready/` | native service: sends `PC_READY` to the Jancar MCU (`/dev/ttyS1`) from boot (`on init`) until it answers. **Required**: without it the MCU cuts the SoC about ten seconds after boot (on the stock, `com.jancar.services` sends it) |
| `librehu/` | LibreHU apps, **all in `/system/priv-app`** (as LibreHU-service asks: `SET_TIME`, Bluetooth, reliable start), with the whitelist of their privileged permissions `privapp-permissions-librehu.xml` (LineageOS enforces `ro.control_privapp_permissions=enforce`: a missing permission makes `system_server` crash at boot; `check_privapp.py`, run by `fetch_apks.sh`, checks each APK): **LibreHU-service** (`latest-main`), **LibreHU Launcher** `librehu-service` edition (only home screen, replaces Trebuchet), **LibreHU Apps / OTA** (`latest-main`); APKs downloaded by `fetch_apks.sh`, original signature kept: the OTA app then updates them as on the stock ROM. **ViPER4Android LibreHU** 2.1.1 (`latest-librehu-service`). Also: **phone**, **FM radio**, **widgets** and **BtnRemap** (`librehu-service` edition), **EasySource**, **Disc**, **MCU Toolkit** (`latest-main`), **Android Auto** (Open Headunit LibreHU, `latest-main`) and **CarPlay** (xcertplay LibreHU, `latest-master`); a missing APK is skipped. All signed with the LibreHU key: the OTA app updates them. **Native libraries** (`native_libs.py`, run by `fetch_apks.sh`): Android 9 never extracts them for a system app, and the build would recompress an APK with compressed libraries, which strips its v2 signature (PackageManager would refuse it); such an APK (Android Auto) is therefore installed as it is and its libraries extracted to `/system/priv-app/<app>/lib/arm64/`; a 32-bit-only app (FM) is precompiled for arm (`LOCAL_MULTILIB := 32`). `ksunext/`: **KernelSU Next v3.4.2 manager** (version pinned to the kernel API, checksum checked by `fetch_apks.sh`), kept in `/system/etc/librehu/` and installed into `/data/app` at first boot by `librehu_ksunext`: the kernel only recognises its manager there (`throne_tracker.c`), never as a system app |
| `proprietary-files.txt`, `extract-files.sh`, `setup-makefiles.sh` | proprietary `/system` files taken from stock V1.151R6: Autochips HIDL interfaces (rear camera, AVM, fast display, iAP2, ATC audio...), `autochips.jar` (BOOTCLASSPATH, pinned by SHA-1) and its JNI libraries, `libusbdvr.so`. They are in the [android_vendor_jancar_ac8257_demo](https://github.com/LibreHU/android_vendor_jancar_ac8257_demo) repository (`lineage-16.0` branch, cloned by the local manifest); `extract-files.sh` is only for another firmware |
| `tools/get_vendor_img.sh` | reads the vendor partition of the unit (read only) |
| `tools/vendor_add_viper.sh` | adds to the local vendor image (debugfs, copy `vendor.img.orig` kept) the [ViPERFX_RE](https://github.com/likelikeslike/ViPERFX_RE) v2.1.1 driver (official module, SHA-256 checked): `libv4a_re.so` in `/lib[64]/soundfx` and the `v4a_standard_re` effect in `/etc/audio_effects.xml`, like the `viper4android-re` zip of LibreHU-flashablesZips. In vendor because under Android 9 Treble effects are loaded by the vendor audio HAL, which cannot load a library from `/system` |
| `tools/fetch_viper.sh` | [ViPERFX_RE](https://github.com/likelikeslike/ViPERFX_RE) v2.1.1 driver (official module, SHA-256 checked, version of the ROM's ViPER4Android app) into `prebuilt/viper` (not versioned): the TWRP zip installs or updates it in `/vendor/lib[64]/soundfx` and declares it in vendor's `audio_effects` (unless `/sdcard/LibreHU/no-viper`, created by the `viper4android-re-restore` zip); used by `tools/vendor_add_viper.sh` too |
| `tools/fetch_kernel.sh` | LibreHU kernel `stable-4.9.337` (`Image.gz-dtb`) and its Wi-Fi / BT / GPS / FM modules from the `latest-stable-4.9.337` release (GitHub checksums checked, image kernel = modules kernel); not versioned. Adds **`androidboot.selinux=permissive`** to the header command line of the boot images (only field changed, AVB footer kept): without it LineageOS's init goes enforcing (`BOARD_KERNEL_CMDLINE` is not used with a prebuilt image, the LK adds nothing); `LIBREHU_SELINUX=enforcing tools/fetch_kernel.sh` not to add it |
| `tools/patch_lineage_sources.sh` | fixes the LineageOS sources after every `repo sync`: panel and touch rotation (SurfaceFlinger, InputReader) and inverted backlight (LightsService), files of `tools/lineage-patches`; and, without which init rebooted to fastboot: `fs_mgr_is_device_unlocked()` sees the unit unlocked unless `vbmeta.device_state=locked` (the Jancar LK reports `green` even unlocked, so fs_mgr refused to mount `vendor`); removes `genfscon fuseblk` from `device/lineage/sepolicy` (conflict with the Jancar vendor SELinux policy); `--check` only tells whether something is left to do |
| `tools/vendor_add_conn_modules.sh` | puts these modules in `/lib/modules` of the local vendor image (debugfs, rights and SELinux context of the original, `.librehu_conn` marker, copy `vendor.img.orig` kept): the LibreHU kernel refuses those of the stock vendor (different symbol CRCs), as the `kernel-stable` zips do on the unit |
| `sepolicy/private/` | SELinux domain of `mcu_ready` (system side, `BOARD_PLAT_PRIVATE_SEPOLICY_DIR`): without it, Android 9's init **refuses to start the service, even in permissive** ("has incorrect label or no domain transition", `init/service.cpp`), PC_READY is not sent and the MCU cuts the SoC about ten seconds after boot; same for `librehu_ksunext`. Both domains are **permissive** on their own (`permissive`, refused in user builds): PC_READY goes out even if SELinux were enforcing (`/dev/ttyS1` is a vendor policy type, which the system policy cannot name); `librehu_gpio_device` type for `/dev/gpios_ioctl`, opened to LibreHU-service (`priv_app`), for the enforcing mode |
| `config.fs`, `BOARD_ROOT_EXTRA_FOLDERS` | stock mount points at the root of `system`: `/jancar` (0755 root:root, `jancar` partition of the vendor fstab) and `/avm` (0775 root:system). Without `/jancar`, `fs_mgr` cannot mount the partition (read-only root), `mount_all` fails and init does not start the `main` class (zygote): Android does not start. Found by Reo Au In. `/vendor` is created by the build |
| `rootdir/etc/init/librehu.rc` | stock `persist` values an empty `/data` lacks (stock getprop, LibreHU Helper report): `persist.vendor.connsys.chipid` set to `0x8257` at `early-boot` if it is `-1` (vendor build.prop) or `0x0000`, before `wmt_loader` (Wi-Fi) starts; ECNR vendor property aligned on the persist one |
| `rootdir/etc/fstab.ac8257` | stock vendor fstab |

## Build from scratch

**Detailed step-by-step guide** (Proxmox LXC container, Ubuntu 20.04, sources, unit files, build of the images, install,
updates, troubleshooting): [docs/BUILD.en.md](docs/BUILD.en.md). Summary below.

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
device/alps/ac8257_demo/tools/fetch_viper.sh         # ViPERFX_RE driver of the TWRP zip (prebuilt/viper)
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
mka systemimage bootimage vendorimage
```
Result in `out/target/product/ac8257_demo/`: `system.img`, `boot.img` (LibreHU kernel CI image, stock AVB footer,
`androidboot.selinux=permissive`), `vendor.img` (your vendor with ViPERFX_RE and the modules of this kernel).
**No zip**: LineageOS 16.0 refuses to make one for a non-A/B device without a recovery (`ota_from_target_files.py`),
and the tree keeps TWRP as the recovery (details: [docs/BUILD.en.md](docs/BUILD.en.md), step 6).

### 5. Install
Nothing is automated. First:
1. **Full backup**: SP Flash Tool (readback) with the stock scatter, and a TWRP backup of `system`, `vendor`, `boot`,
   `data`. Keep `para` too (`dd if=/dev/block/by-name/para of=...`).
2. **vbmeta**, once, by hand (never done by these tools), **with both options**:
   `fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img` (stock vbmeta: your backup, or
   `images/vbmeta.img` of a LibreHU Helper report). The stock vbmeta **chains the `system` partition** (Jancar key) and
   the LineageOS `system.img` does not have the expected AVB footer: with `--disable-verity` alone, the LK and init
   (vendor mount) stop on libavb's `ERROR_INVALID_METADATA`, fatal even when unlocked, and the unit reboots at the logo
   with no log at all. `--disable-verification` makes them skip the chain. Already done with `--disable-verity` alone
   (LibreHU kernel on the stock ROM): do it again with both (details: [docs/BUILD.en.md](docs/BUILD.en.md), step 8).
3. In TWRP: *Wipe > Format Data* (LineageOS does not start on the data of the stock ROM), then `adb reboot bootloader`
   and `fastboot flash` of `system.img`, `boot.img` and `vendor.img`, **all three**: the vendor holds the LibreHU
   kernel modules (the stock kernel refuses them) and only this `boot.img` makes SELinux permissive.
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

1. **Starting tree** — ✅ this branch (20/10/2026).
2. **First build** — ✅ 12/11/2026, by the CI (`system`, `boot`; the vendor stays the unit's). **First boot** on stock
   vendor + LibreHU kernel, to be tried: screen, touch, adb, Wi-Fi, Bluetooth,
   GPS (LibreHU kernel modules in vendor), audio (vendor ATC HAL), MCU (`mcu_ready` then LibreHU-service).
3. **Head unit features** with the LibreHU apps: MCU / CAN, steering wheel keys, FM radio, rear camera and AVM, AV-in,
   phone (MediaTek RIL `c6m_1rild` with AOSP telephony), Android Auto / CarPlay.
4. **SELinux policy** of the device: domain of `mcu_ready` done (09/11/2026, required for init to start it); then its
   rules and those of the apps, then enforcing mode (permissive today, like the stock).
5. **LibreHU kernel** instead of the stock kernel, root (KernelSU Next) — in the tree since 01/11/2026; since
   09/11/2026, `boot.img` is the kernel CI image (stock AVB footer), connectivity modules in vendor, to be tested.
6. **Proprietary `/system` files** in a vendor repository — ✅ 09/11/2026: Autochips HIDL interfaces, deodexed
   `autochips.jar` (`PRODUCT_BOOT_JARS`) and its JNI libraries ([android_vendor_jancar_ac8257_demo](https://github.com/LibreHU/android_vendor_jancar_ac8257_demo)), built (12/11/2026).
7. **Published builds** (images) updated by the OTA app. Flashable zip: ✅ TWRP installer of LibreHU's own
   (`tools/make_flashable_zip.py`, zip made by the CI; LineageOS 16.0 makes none for a non-A/B device without a
   recovery). Publishing and updates by the OTA app: to do.

## Known risks

Tries of the CI builds of 12/11/2026 (TWRP zip, vbmeta with both options): boot menu, then the unit reboots to
fastboot, twice. LineageOS's init hit two fatal errors, found off the unit in the sources; its `LOG(FATAL)` reboots to
the bootloader (`system/core/init/log.cpp`).

1. **`vendor` mount (first stage of init, before SELinux).** The Jancar LK reports
`androidboot.verifiedbootstate=green` even unlocked (getprop of the unit under the stock); with the
`VERIFICATION_DISABLED` flag of vbmeta, it passes no `androidboot.vbmeta.*` at all (libavb skips `avb_append_options`). LineageOS's fs_mgr only believes the unit is unlocked when `orange` (`fs_mgr_is_device_unlocked`,
`system/core/fs_mgr/fs_mgr.cpp`). But `fastboot --disable-verity --disable-verification` changes the flags of the
vbmeta header, which its hash covers (`external/avb/libavb/avb_vbmeta_image.c`): libavb returns `ERROR_VERIFICATION`,
which fs_mgr refuses on a unit it believes locked (`fs_mgr_avb.cpp`). `vendor` (DT fstab, `wait,avb`) is not mounted
and init stops on `Failed to mount required partitions early` (`system/core/init/init.cpp`); confirmed by the console
of the try (`console-ramoops`: `ERROR_VERIFICATION isn't allowed when the device is LOCKED`, then `Failed to mount
required partitions early`). The stock system boots with this same vbmeta: its init does not refuse it. Fixed on 12/11
(night): `tools/patch_lineage_sources.sh` makes `fs_mgr_is_device_unlocked()` see the unit unlocked, unless the LK
explicitly passes `vbmeta.device_state=locked` (a vbmeta that does not verify only reaches init if the LK accepted it);
`BoardConfig.mk` stops the build without this fix.

2. **SELinux policy (right after).** LineageOS labels `fuseblk` as `vfat`
(`device/lineage/sepolicy/common/private/genfs_contexts`), the Jancar vendor policy as `sdcardfs`; `secilc`, run by
init to compile the system + vendor policy, refuses these two `genfscon` (`Found conflicting genfscon rules`, Android
9's `libsepol/cil/src/cil_post.c`), init stops on `Unable to load SELinux policy` and its `LOG(FATAL)` reboots to the
bootloader (`system/core/init/log.cpp`). Fixed on 12/11: `tools/patch_lineage_sources.sh` removes the LineageOS line
after `repo sync` (the policy then compiles with the stock vendor), `BoardConfig.mk` stops the build if it is still
there. The other files merged at boot (`property_contexts`, `hwservice_contexts`, `seapp_contexts`) have no duplicate
with the stock vendor. Build `8a3241e` ([CI of 12/11](https://github.com/LibreHU/android_device_alps_ac8257_demo/actions/runs/43296986221)): its policy, read back from the `system` image of the
zip, compiles with the stock vendor's (`secilc`, same options as init); it still stopped on point 1.

Build with both fixes: to be tried.

First try by a tester (Reo Au In, 08/11/2026, build of the 07/11 branch): Android started, then the unit restarted
after about ten seconds; no log. Most likely cause: the Wi-Fi chip id `0x0000` of an empty `/data` (below). Fixed here
since (09/11), to be tried again:
- **`mcu_ready` never started** (no SELinux domain, see `sepolicy/`): without PC_READY, the MCU cuts the SoC (10 s after
  leaving standby, 15 min on a cold start: `docs/mcu_firmware.md` of MCU-tools-app, section 5). Since 09/11 (night),
  `mcu_ready` waits for the MCU's answer to PC_READY (acknowledgement `C0 1F` or version `0A`), not for whatever frame
  comes first (the MCU relays the CAN box frames without PC_READY), sends again every second, and also writes to the
  kernel log (`dmesg | grep mcu_ready`);
- **LineageOS `boot.img` without AVB footer**: refused by the LK (reboot at the logo); it is now the kernel CI image;
- **LibreHU apps in `/system/app`**: without their privileged permissions (time, Bluetooth, widgets...); all in
  `/system/priv-app` with their whitelist;
- **`/jancar` and `/avm` missing from the root** (seen by Reo Au In, who had added them by hand): without `/jancar`,
  `mount_all` fails and init starts neither zygote nor the rest of the `main` class; created by the build since 09/11.
- **SELinux enforcing** (found in the audit of 09/11 evening): with the prebuilt boot image, the
  `androidboot.selinux=permissive` line of `BoardConfig.mk` was no longer used and the LK does not add it; LineageOS
  userdebug's init therefore went enforcing, `mcu_ready` (no rules) could not open `/dev/ttyS1` and the MCU cut the SoC.
  Fixed: `tools/fetch_kernel.sh` adds it to the header of the boot images, and `mcu_ready` / `librehu_ksunext` are
  permissive domains. To check at boot: `adb shell getenforce` = `Permissive`.
- **vbmeta: `system` is chained** (audit of 09/11, night): the stock vbmeta holds `chain recovery`, `chain system`,
  `hashtree vendor`, `hash dtbo` and `hash boot`. The LK and LineageOS's init follow the `system` chain and read the
  vbmeta of the partition's AVB footer; the LineageOS one has none (`BOARD_AVB_ENABLE := false`):
  `ERROR_INVALID_METADATA`, fatal even when unlocked (Android 9 `external/avb/libavb/avb_slot_verify.c`,
  `result_should_continue`; `system/core/fs_mgr/fs_mgr_avb.cpp`). With `--disable-verity` alone, booting therefore
  depended on leftovers of the stock system at the end of the partition. Fixed: `fastboot --disable-verity
  --disable-verification` (step 5 above), which Reo Au In's "flags 3" vbmeta also did.
- **Privileged permission whitelist in `enforce`** (audit of 09/11, night): LineageOS sets
  `ro.control_privapp_permissions=enforce`, where a single missing privileged permission makes system_server crash at
  every boot; the stock ROM uses `log`. Set back to `log` (`lineage_ac8257_demo.mk`, before the `inherit-product`
  lines so that it comes before LineageOS's value).
- **Properties of the vendor `default.prop`** (audit of 09/11, night): `ro.zygote` and `ro.vndk.version` come from the
  stock vendor `default.prop`; set on the system side too as a safety net, and `persist.sys.usb.config=adb` in the system
  `build.prop` to keep adb whatever the vendor sets (`device.mk`).

Reo Au In also repaired his 07/11 zip his own way (unsigned vbmeta written by the zip, AVB footer and first-mount flag
removed, vendor hash tree rebuilt, `fpsgo.ko` disabled): this repository keeps its rules (vbmeta never written by the
tools, `fastboot --disable-verity --disable-verification` by hand; kernel CI boot image with the stock AVB footer); the
stock `fpsgo.ko` is refused by the LibreHU kernel with no other effect (docs/STABLE.md of the kernel).

Still open:
- **Wi-Fi: chip id `0x0000`**: on an empty `/data` (Format Data), the `stable-4.9.337` kernel answered 0 to the chip id
  request of `wmt_loader`, which stores it in `persist.vendor.connsys.chipid`; the Wi-Fi driver then starts with chip 0
  and the unit reboots in a loop as soon as Wi-Fi turns on (seen by Reo Au In, fixed on his side with
  `setprop persist.vendor.connsys.chipid 0x8257`). Since 09/11, `rootdir/etc/init/librehu.rc` sets `0x8257` at
  `early-boot` (before `wmt_loader`, whatever the kernel) and replaces a `0x0000` already stored; kernel fix (the id
  request probes the consys first, else 0x8257) in `stable-4.9.337` since 13/11/2026 (test branch `test-wifi-chipid`
  merged).
- **`autochips.jar`** (09/11): on the stock, the Autochips classes are in `/system/framework/autochips.jar` (in the
  `BOOTCLASSPATH`); without it, LibreHU-service cannot hand the display back to Android after the ARM2 (green hardware
  video: cameras, AV-in) nor read the Autochips settings. Deodexed from `boot-autochips.vdex` (stock V1.151R6) in the
  [android_vendor_jancar_ac8257_demo](https://github.com/LibreHU/android_vendor_jancar_ac8257_demo) repository
  (`lineage-16.0` branch, local manifest above), pinned in `proprietary-files.txt`, `PRODUCT_BOOT_JARS += autochips`
  (`device.mk`), with its JNI libraries (`lib{,64}/lib{atcavm,atcvobsub,dvr,logo,metazone}_jni.so`) and `libusbdvr.so`
  (needed by `libdvr_jni.so`), in `proprietary-files.txt` and the vendor repository like the HIDL interfaces. **Built
  (12/11/2026), not tried yet** (expected: `echo $BOOTCLASSPATH` contains `autochips.jar`, LibreHU-service finds
  `AtcMetazone`, `AtcLogo`, `BackCar`, with no `ClassNotFoundException` nor `UnsatisfiedLinkError`).
- **Other `persist` values of an empty `/data`**: taken from the `getprop` of a stock unit (LibreHU Helper report of
  04/11/2026, 415 `persist` properties, 331 of which come from the stock vendor `build.prop`, kept here). Taken over:
  `connsys.chipid` and call ECNR (`persist.audiohal.third_ecnr_lib.enable=1`). Left out: microphone gain (set again by
  LibreHU-service), `persist.sf.hwrotation=90` (AOSP's SurfaceFlinger only reads `ro.sf.hwrotation`, the screen is
  1280 x 720 rotation 0 on the stock), AEE (`persist.vendor.mtk.aee.mode=4`...: meaning not checked), picture quality
  `persist.vendor.sys.pq.*` and colours `persist.sys.rgb.*` (readers unknown without the vendor files), properties of
  the Jancar apps and their Bluetooth stack, user choices (car, language, time zone) and `persist.netd.stable_secret`
  (specific to each unit).
- **Bluetooth call audio**: as HFP client, Android 9's Bluetooth hands the call audio to the vendor audio HAL
  (`hfp_enable`, `hfp_set_sampling_rate` parameters, BT SCO devices of `audio_policy_configuration.xml`); does the
  stock MediaTek audio HAL handle them? To be tried (on the stock, Jancar's Bluetooth stack handled calls).

- **RIL**: MediaTek modem (`ro.vendor.mtk_ril_mode=c6m_1rild`, `mtk-ril.so`) with LineageOS's AOSP telephony: calls
  and data to be checked.
- **Jancar apps missing** (`com.jancar.*`, `com.autochips.*`): their features go through the LibreHU apps; what no
  LibreHU app covers yet will be missing.
- **Rotation and display**: the screen is 1280 x 720 landscape on the stock; to be checked at first boot.
- The build passes (CI, 12/11/2026); tries of 12/11 stopped by the `vendor` mount (fs_mgr) and the SELinux policy (fixed), the fixed build is still to be tried.

## Rules

- Nothing is written under dm-verity and vbmeta is never disabled automatically:
  `fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img` by hand.
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

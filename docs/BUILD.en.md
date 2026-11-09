# Building LineageOS 16.0 for the UJC201, step by step

*Français : [BUILD.md](BUILD.md)*

From scratch to the **`system`, `boot` and `vendor` images** to flash, on a **Proxmox VE 8 or 9** server with a
dedicated LXC container (example: 2 × Xeon E5-2699 v3, 72 threads, 256 GB of RAM, 1 TB NVMe). On a PC already
running Ubuntu 20.04, skip step 1.

> **Status**: the tree has never been built yet. Errors on the first build are likely: send the log (step 6), the
> tree will be fixed.

| Step | Where | Time (estimate, not a measurement) |
|---|---|---|
| 1. LXC container | Proxmox host | 10 min |
| 2. Ubuntu 20.04 system | container, root | 10 min |
| 3. Build tools | container, `build` user | 10 min |
| 4. LineageOS sources + tree | container | about 1 h (limited by the servers, not by the fibre) |
| 5. Unit files | PC + unit under TWRP, then container | 20 min |
| 6. Build: images | container | 1 to 2 h the first time, 15 to 30 min afterwards (ccache) |
| 7. Get the files | PC | 5 min |
| 8. Install | PC + unit | 15 min |

**Why Ubuntu 20.04**: LineageOS 16.0 wants `python` = Python 2 and `libncurses5`, and its build guide is only tested
on Ubuntu 20.04 ([LineageOS wiki](https://wiki.lineageos.org/devices/f1f/build/)). Ubuntu 20.04 has both
(`python-is-python2`, `libncurses5`, still on archive.ubuntu.com); Ubuntu 24.04 no longer has Python 2. No Java to
install: LineageOS 16.0's OpenJDK 9 comes with the sources (same wiki page).

**Never publish** a unit's own data: Bluetooth and Wi-Fi MAC addresses, serial number, Apple MFi certificate
(CarPlay), so neither `nvram`, `nvdata`, `proinfo` as they are, nor `persist` / `metazone` unchecked. The Jancar /
Autochips / MediaTek proprietary `/system` files are published in the
[android_vendor_jancar_ac8257_demo](https://github.com/LibreHU/android_vendor_jancar_ac8257_demo) repository (cloned by
the local manifest, step 4); `vendor.img` and `system-stock.img` stay with you (too big, specific to the unit).

## 1. LXC container (root shell of the Proxmox host)

**Ubuntu 20.04 template.** Proxmox 8 still lists it, Proxmox 9 only lists 24.04 and 26.04
([PVE 8 index](http://download.proxmox.com/images/aplinfo-pve-8.dat), [PVE 9 index](http://download.proxmox.com/images/aplinfo-pve-9.dat)),
but the file is still online and Proxmox 9 accepts 20.04
([`known_versions` of pve-container](https://git.proxmox.com/?p=pve-container.git;a=blob;f=src/PVE/LXC/Setup/Ubuntu.pm)).
Same command for both versions, SHA-512 checksum from the Proxmox index:
```bash
cd /var/lib/vz/template/cache
wget http://download.proxmox.com/images/system/ubuntu-20.04-standard_20.04-1_amd64.tar.gz
echo "9ebcf6cce7c3b760d27c2bfe03d00acf3d40a489cd98230b9ab8dd436f82f4ae8dc2de69b012dcd0affae62ffe4ab4863f624a665f3493983d330e6c015a26dd  ubuntu-20.04-standard_20.04-1_amd64.tar.gz" | sha512sum -c -
```

**NVMe storage**: its name in Proxmox (here `nvme`):
```bash
pvesm status
```
If the NVMe is not a storage yet: *node > Disks > LVM-Thin > Create: Thinpool* (**erases the disk**).

**Creation** (ID 160, your choice):
```bash
pct create 160 local:vztmpl/ubuntu-20.04-standard_20.04-1_amd64.tar.gz \
  --hostname lineage-build --unprivileged 1 --features nesting=1 \
  --cores 72 --memory 131072 --swap 16384 \
  --rootfs nvme:600 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp
pct start 160
pct enter 160
```

| Option | Why |
|---|---|
| `--unprivileged 1` | the build needs no rights on the host; the unit is never plugged into the server (step 5: from a PC) |
| `--features nesting=1` | asked by systemd to isolate its services ([`pct` doc](https://pve.proxmox.com/pve-docs/pct.1.html)) |
| `--cores 72` | all threads; give fewer if other VMs must run during the build |
| `--memory 131072 --swap 16384` | 128 GB + 16 GB of swap; the LineageOS wiki asks for 16 GB up to 17.1 |
| `--rootfs nvme:600` | 600 GiB on the NVMe: the wiki counts 200 GB (sources + output) up to 17.1, plus ccache (50 GB) and some margin; can grow later: `pct resize 160 rootfs +100G` |

## 2. System (in the container, root)

```bash
apt update && apt full-upgrade -y
apt install -y sudo openssh-server locales
locale-gen en_US.UTF-8 fr_FR.UTF-8
adduser build
usermod -aG sudo build
ip -4 -br addr show eth0      # IP address of the container, for ssh and scp
```
The rest is done as `build`: `ssh build@<ip>` from the PC (or `su - build`).

## 3. Build tools (`build` user)

Packages of the [LineageOS wiki](https://wiki.lineageos.org/devices/f1f/build/), with those it adds for an Ubuntu older
than 23.10 (`lib32ncurses5-dev libncurses5 libncurses5-dev`; on 20.04, `lib32ncurses5-dev` is called
`lib32ncurses-dev`) and Python 2 by default (`python-is-python2`, LineageOS 11.0 to 16.0). Also: `python3` (`repo`,
scripts of the tree), `unzip` and `e2fsprogs` (`debugfs`), for the scripts of the tree. All in the Ubuntu 20.04 index
(checked on 07/11/2026).
```bash
sudo apt install -y bc bison build-essential ccache curl erofs-utils flex g++-multilib gcc-multilib git git-lfs \
  gnupg gperf imagemagick kmod protobuf-compiler python3-protobuf lib32readline-dev lib32z1-dev libdw-dev \
  libelf-dev libgnutls28-dev lz4 libsdl1.2-dev libssl-dev libxml2 libxml2-utils lzop pngcrush rsync schedtool \
  squashfs-tools xsltproc xxd zip zlib1g-dev \
  lib32ncurses-dev libncurses5 libncurses5-dev python-is-python2 python3 unzip e2fsprogs
python --version              # must print Python 2.7.x
mkdir -p ~/bin ~/android/lineage
curl -o ~/bin/repo https://storage.googleapis.com/git-repo-downloads/repo
chmod a+x ~/bin/repo
cat >> ~/.bashrc <<'EOF'

# LineageOS (docs/BUILD.en.md)
export PATH="$HOME/bin:$PATH"
export USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache
EOF
source ~/.bashrc
ccache -M 50G
git config --global user.name "Your name"
git config --global user.email "you@example.com"
```

## 4. LineageOS 16.0 sources and the UJC201 tree

```bash
cd ~/android/lineage
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
repo sync -c -j16 --no-tags --no-clone-bundle
```
- `--depth=1`: without the history, much less to download.
- `-j16`: 16 repositories at once (LineageOS uses 4 by default). Google's AOSP servers limit each IP address
  ([source.android.com](https://source.android.com/docs/setup/download/troubleshoot-sync), which also advises to just
  run it again): on errors, run the same command again, with `-j4` if they come back; repositories already downloaded
  are not downloaded again.

## 5. Unit files (once)

The build reuses the **vendor partition** of your unit. The proprietary files of its **stock /system**
(`proprietary-files.txt`: Autochips HIDL interfaces, `autochips.jar` and its JNI libraries) come from the vendor
repository, cloned in step 4 (stock ROM V1.151R6); the `system` image is only a backup, or for another firmware. They
are read from a **PC** (Windows, macOS or Linux, with the
[platform-tools](https://developer.android.com/tools/releases/platform-tools)), the unit booted into **TWRP**
(adb root) and plugged in over USB:
```bash
adb devices
adb pull /dev/block/platform/bootdevice/by-name/vendor vendor.img
adb pull /dev/block/platform/bootdevice/by-name/system system-stock.img
```
Expected sizes: `vendor.img` = **2,147,483,648** bytes, `system-stock.img` = **3,221,225,472** bytes (partition table,
`BoardConfig.mk`). Read only: nothing is written to the unit. Keep both files: they are a backup too.

Copy them into the container:
```bash
scp vendor.img system-stock.img build@<ip>:
```

In the container:
```bash
cd ~/android/lineage
mkdir -p vendor/jancar/ac8257_demo
mv ~/vendor.img vendor/jancar/ac8257_demo/vendor.img
stat -c %s vendor/jancar/ac8257_demo/vendor.img        # 2147483648
debugfs -R "cat /build.prop" vendor/jancar/ac8257_demo/vendor.img 2>/dev/null | grep ro.vndk.version   # 28

# Proprietary /system files (Autochips HIDL interfaces, autochips.jar and its JNI libraries): already in the vendor
# repository (local manifest, step 4), taken from stock ROM V1.151R6. Another firmware: take them from yours
# (autochips.jar, pinned, stays the one of the repository):
#   mkdir -p ~/stock && debugfs -R "rdump /system $HOME/stock" ~/system-stock.img
#   (cd device/alps/ac8257_demo && ./extract-files.sh ~/stock)

cd device/alps/ac8257_demo
tools/vendor_add_viper.sh             # ViPERFX_RE driver in vendor.img (copy vendor.img.orig kept)
tools/fetch_kernel.sh                 # LibreHU kernel stable-4.9.337: boot images + Wi-Fi / BT / GPS / FM modules
                                      # (+ androidboot.selinux=permissive in the header of the boot images)
                                      # (tools/fetch_kernel.sh test-wifi-chipid: test branch of the Wi-Fi fix)
tools/vendor_add_conn_modules.sh      # these modules in vendor.img (the LibreHU kernel refuses the stock ones)
librehu/fetch_apks.sh                 # latest LibreHU APKs (all in priv-app; checks their whitelist)
                                      # + KernelSU Next v3.4.2 manager (checksum checked)
cd ~/android/lineage
rm -rf ~/stock                        # if you made it: no longer needed
```
`debugfs rdump` prints "while changing ownership" errors: it cannot give the files to root without being root. No
matter, the content is copied.

## 6. Build: the images

```bash
cd ~/android/lineage
export LC_ALL=C
source build/envsetup.sh
lunch lineage_ac8257_demo-userdebug
mka systemimage bootimage vendorimage 2>&1 | tee ~/build-$(date +%Y%m%d-%H%M).log
```
`mka` spreads the build over all cores.

**First try**: take the boot image without menu, one unknown less if Android does not start (the boot menu was only
tried under the stock ROM): `export LIBREHU_BOOT_IMAGE=plain` before `lunch`. TWRP stays reachable with
`adb reboot recovery` (adb answers from boot).

**On error**: send the log (`~/build-*.log`), or at least its last 200 lines: `tail -n 200 ~/build-*.log`.

**Result**, in `out/target/product/ac8257_demo/`:

| File | Content |
|---|---|
| `system.img` | system image (sparse) |
| `boot.img` | copy of `prebuilt/boot-librehu-bootmenu.img` (or `boot-librehu.img` with `LIBREHU_BOOT_IMAGE=plain`): boot image from the LibreHU kernel CI, with the **AVB footer of the stock boot** without which the LK refuses it, and `androidboot.selinux=permissive` added to its header command line by `tools/fetch_kernel.sh` |
| `vendor.img` | your vendor with ViPERFX_RE and the LibreHU kernel modules (copy of `vendor/jancar/ac8257_demo/vendor.img`); **never published** |

The three go together: `vendor.img` holds the modules of **this** kernel (the stock kernel refuses them), and only this
`boot.img` makes SELinux permissive (without it, `mcu_ready` cannot send PC_READY and the MCU cuts the SoC).

**No flashable zip**, checked in the LineageOS 16.0 sources: its zip generator refuses a non-A/B device without a
recovery ("target build has specified no recovery",
[`ota_from_target_files.py`](https://github.com/LineageOS/android_build/blob/lineage-16.0/tools/releasetools/ota_from_target_files.py#L1984-L1986)),
and `mka bacon` has nothing to package when the boot image is not built by LineageOS (`TARGET_NO_KERNEL`:
`build_ota_package := false`,
[`core/Makefile`](https://github.com/LineageOS/android_build/blob/lineage-16.0/core/Makefile#L2579-L2581)). The tree on
purpose builds neither a recovery (TWRP stays in place) nor a `boot.img` (a LineageOS `boot.img` would lack the AVB
footer of the stock boot: the LK refuses it and the unit reboots at the logo).

## 7. Get the files (on the PC)

```bash
for f in system boot vendor; do scp build@<ip>:android/lineage/out/target/product/ac8257_demo/$f.img .; done
```
From the Proxmox host, `pct pull 160 <file> <destination>` does the same.

## 8. Install

**Before the first install**:
1. **Full TWRP backup** on a USB stick or a microSD card: System Image, Vendor, Boot, Data and the partitions specific
   to the unit. Keep `vendor.img` and `system-stock.img` from step 5 too.
2. **vbmeta**, once, **by hand** if not done yet (never done by these tools):
   `fastboot --disable-verity flash vbmeta vbmeta.img` (stock vbmeta).

**Install**:
1. TWRP: *Wipe > Format Data*, type `yes` (**first install only**: LineageOS does not start on the data of the stock
   ROM).
2. `adb reboot bootloader` (or TWRP: *Reboot > Bootloader*), then on the PC:
   ```bash
   fastboot flash system system.img
   fastboot flash boot boot.img
   fastboot flash vendor vendor.img
   fastboot reboot
   ```
   Without a PC for `system` and `boot`: TWRP, *Install > Install Image* (`system.img` > *System Image*, `boot.img` >
   *Boot*); `vendor.img` needs fastboot (TWRP's fstab has no image entry for vendor).

**After the first boot**, from the PC:
```bash
adb shell getenforce                                               # Permissive
adb shell getprop persist.sys.usb.config                           # contains adb
adb shell 'echo $BOOTCLASSPATH' | tr ':' '\n' | grep autochips      # /system/framework/autochips.jar
adb shell ls /system/priv-app/LibreHUAndroidAuto/lib/arm64         # Android Auto's libraries
```
The phone must see the head unit as a **car** (car icon in its Bluetooth list) and send it music (A2DP) and calls
(HFP). Then: adb on without authorization, `adb root` allowed, logs in `/data/misc/logd/`, KernelSU Next manager
installed by itself (allow LibreHU-service in it); details, root, MTP: [README](../README.en.md#5-install).
**Going back**: restore the TWRP backup.

## 9. Next builds

```bash
cd ~/android/lineage
repo sync -c -j16 --no-tags --no-clone-bundle
device/alps/ac8257_demo/librehu/fetch_apks.sh
device/alps/ac8257_demo/tools/fetch_kernel.sh
device/alps/ac8257_demo/tools/vendor_add_conn_modules.sh
export LC_ALL=C
source build/envsetup.sh
lunch lineage_ac8257_demo-userdebug
mka systemimage bootimage vendorimage 2>&1 | tee ~/build-$(date +%Y%m%d-%H%M).log
```
**Builds made before 09/11/2026**: `vendor/jancar/ac8257_demo/` already existed (your `vendor.img`, and `proprietary/`
from `extract-files.sh`) and is not a git repository, so `repo sync` refuses to clone the vendor repository into it.
Once, instead of the `repo sync` above (keeps `vendor.img` and its copy `vendor.img.orig`):
```bash
cd ~/android/lineage
mv vendor/jancar/ac8257_demo/vendor.img* ~/
rm -rf vendor/jancar/ac8257_demo
repo sync -c -j16 --no-tags --no-clone-bundle
mv ~/vendor.img* vendor/jancar/ac8257_demo/
```

Install: `fastboot flash system system.img` and `fastboot flash boot boot.img` (or TWRP, *Install Image*), **without**
*Format Data*. If `tools/fetch_kernel.sh` took a new kernel, flash `vendor.img` again too: its modules must come from
the same build as the `boot` kernel. Step 5 does not need to be done again (`vendor/jancar/ac8257_demo/` stays).

## Troubleshooting

| Symptom | Fix |
|---|---|
| `repo sync`: download errors, 429, `RESOURCE_EXHAUSTED` | run the same command again, with `-j4` if it comes back |
| `python` not found, or `SyntaxError` in a build script | `python --version` must give 2.7: `sudo apt install python-is-python2` |
| `flex` or `bison`: `Assertion ... loadlocale.c` | `export LC_ALL=C` before `source build/envsetup.sh` |
| `libncurses.so.5: cannot open shared object file` | `sudo apt install libncurses5` |
| `debugfs manquant` | `sudo apt install e2fsprogs` |
| `extract-files.sh`: `!! file not found in source` | (another firmware only) `~/stock/system/lib64/...` missing: redo the `rdump` of step 5 |
| `repo sync`: `vendor/jancar/ac8257_demo` already exists / is not a git repository | folder from a build made before 09/11/2026: see *Next builds* (keep `vendor.img`, delete the folder, `repo sync`) |
| `No rule to make target 'vendor/jancar/ac8257_demo/proprietary/...'` | vendor repository missing or not up to date: local manifest of step 4, then `repo sync` |
| At boot, `ClassNotFoundException` (`com.autochips.*`) or `UnsatisfiedLinkError` (`lib*_jni.so`) in logcat | `echo $BOOTCLASSPATH` (adb shell) must contain `/system/framework/autochips.jar`; otherwise the vendor repository was not up to date at build time: `repo sync` and rebuild; send the logcat |
| Android Auto missing, or stops as soon as it opens | `adb shell ls /system/priv-app/LibreHUAndroidAuto/lib/arm64` must list its libraries: run `librehu/fetch_apks.sh` again (it runs `native_libs.py`) then rebuild. Builds before 09/11/2026 evening: the build recompressed its APK and stripped its v2 signature (PackageManager refused it) |
| No sound | `adb logcat -d \| grep APM::Serializer` must show `/vendor/etc/audio_policy_configuration.xml` being read; builds before 09/11/2026 evening: no `USE_XML_AUDIO_POLICY_CONF`, audio read the emulator configuration |
| The phone does not see the head unit as a car, or no Bluetooth music | builds before 09/11/2026 evening (smartphone device class, A2DP sink not built); otherwise `adb shell settings get global bluetooth_class_of_device` must answer `null` (a value set there wins over the "Car audio" class); forget the device on the phone and pair again |
| `fetch_kernel.sh`: `'str' object has no attribute 'removeprefix'` | fixed on 07/11/2026 (Python 3.8 of Ubuntu 20.04): `repo sync` |
| `prebuilt/boot-librehu-bootmenu.img absent` (warning at `lunch`), then `No rule to make target ... boot-librehu` | run `tools/fetch_kernel.sh` (since 09/11/2026 it also takes the boot images) |
| `fetch_apks.sh`: `privapp-permissions-librehu.xml is short` | an app asks for a new privileged permission: add the printed lines to `librehu/privapp-permissions-librehu.xml` (otherwise `system_server` stops at boot: `Signature|privileged permissions not in privapp-permissions whitelist`) |
| The unit reboots at the logo, with no kernel log | `boot.img` without AVB footer (builds before 09/11/2026): flash `prebuilt/boot-librehu-bootmenu.img` (or the `kernel-stable` zip of LibreHU Apps) into `boot` |
| Endless boot animation, nothing starts; `logcat`: `Failed to mount an un-encryptable or wiped partition on ... at /jancar` | builds before 09/11/2026: `/jancar` missing from the root of `system`, `mount_all` fails and init does not start zygote; `repo sync` and rebuild |
| Android starts then the unit reboots after about ten seconds; or `adb shell getenforce` answers `Enforcing` | boot images taken before the SELinux fix of 09/11/2026 evening (header without `androidboot.selinux=permissive`): `repo sync`, run `tools/fetch_kernel.sh` again (it adds it), rebuild, flash `boot` again. Otherwise, builds before 09/11/2026: `mcu_ready` without SELinux domain, never started by init (no PC_READY, the MCU cuts the SoC); `repo sync` and rebuild. Otherwise, send the kernel log of the failed boot (below) |
| Reboot loop as soon as Wi-Fi turns on (Android Auto turns it on by itself) | `persist.vendor.connsys.chipid` is `0x0000`: `su -c 'getprop persist.vendor.connsys.chipid'`; builds before 09/11/2026 (without `rootdir/etc/init/librehu.rc`): Wi-Fi off, `su -c 'setprop persist.vendor.connsys.chipid 0x8257'` then reboot; kernel fix to try: `tools/fetch_kernel.sh test-wifi-chipid` |
| `fetch_apks.sh`: `sha256sum: WARNING: 1 computed checksum did NOT match` on `KernelSUNext.apk` | damaged download: run again; if it comes back, the KernelSU Next v3.4.2 release changed, do not bypass |
| KernelSU Next manager missing after the first boot | `adb logcat -d -s LibreHU-KSU` (reason `pm install` refused); `ksunext/KernelSUNext.apk` missing at build time: run `fetch_apks.sh` again |
| `Killed` or out of memory | more RAM for the container (`pct set 160 --memory 196608` on the host) or fewer jobs: `m -j36 bacon` |
| `No space left on device` | `df -h ~`, then on the host `pct resize 160 rootfs +100G` |

**Log of a failed boot**: the LibreHU kernel keeps the end (256 KiB) of the log of the previous boot in pstore
(ramoops, reserved zone `0x47c90000`, `CONFIG_PSTORE_RAM`): `/sys/fs/pstore/console-ramoops`, also in `/proc/last_kmsg`
behind the header of the MediaTek RAM console. This log only survives a warm restart (panic, watchdog, `reboot`): a
power cut of the SoC (the MCU cutting it, ignition off) clears the RAM, and only the start of the current boot is then
there (early pstore console of the kernel). Right after the failed restart, as soon as `adb` answers (stock Android or
LineageOS; TWRP if its kernel exposes it too):
`adb shell cat /sys/fs/pstore/console-ramoops > last_kmsg.txt` (or `/proc/last_kmsg`).
Android also files it in the dropbox (`SYSTEM_LAST_KMSG`), which LibreHU-service reads when it starts. With the boot
menu, choosing **TWRP** avoids starting Android again (and overwriting this log) before reading it.

**Android logs** (builds since 09/11/2026): logcat is recorded continuously in `/data/misc/logd/`
(`persist.logd.logpersistd=logcatd`), so it is kept across a restart. adb answers without authorization from boot and
`adb root` is allowed by default: `adb root` then `adb pull /data/misc/logd`.

## Sources

- LineageOS wiki, device build guide in 16.0 (Ubuntu 20.04, packages, Python 2, OpenJDK 9, ccache, `repo`):
  https://wiki.lineageos.org/devices/f1f/build/
- Proxmox VE: [`pct`](https://pve.proxmox.com/pve-docs/pct.1.html) (creation, `nesting`, `rootfs`, `pct enter`,
  `pct resize`, `pveam`), [PVE 8 template index](http://download.proxmox.com/images/aplinfo-pve-8.dat) and
  [PVE 9](http://download.proxmox.com/images/aplinfo-pve-9.dat),
  [accepted Ubuntu versions](https://git.proxmox.com/?p=pve-container.git;a=blob;f=src/PVE/LXC/Setup/Ubuntu.pm)
- AOSP, per-IP quotas: https://source.android.com/docs/setup/download/troubleshoot-sync
- LineageOS 16.0, adb and logs: [`WITH_ADB_INSECURE`](https://github.com/LineageOS/android_vendor_lineage/blob/lineage-16.0/config/common.mk#L19-L30),
  [`post_process_props.py`](https://github.com/LineageOS/android_build/blob/lineage-16.0/tools/post_process_props.py#L40-L54),
  [`ALLOW_ADBD_NO_AUTH`](https://github.com/LineageOS/android_system_core/blob/lineage-16.0/adb/Android.mk#L346),
  [`adb root`](https://github.com/LineageOS/android_system_core/blob/lineage-16.0/adb/services.cpp#L86-L93),
  [Root access](https://github.com/LineageOS/android_packages_apps_Settings/blob/lineage-16.0/src/com/android/settings/development/RootAccessPreferenceController.java#L69-L76),
  [`logcatd.rc`](https://github.com/LineageOS/android_system_core/blob/lineage-16.0/logcat/logcatd.rc),
  [`PRODUCT_PACKAGES_DEBUG`](https://github.com/LineageOS/android_build/blob/lineage-16.0/target/product/base.mk#L168-L173),
  init order ([`init.rc`](https://github.com/LineageOS/android_system_core/blob/lineage-16.0/rootdir/init.rc#L279-L318),
  [`queue_property_triggers`](https://github.com/LineageOS/android_system_core/blob/lineage-16.0/init/init.cpp#L432-L436),
  [`Action::CheckEvent`](https://github.com/LineageOS/android_system_core/blob/lineage-16.0/init/action.cpp#L179-L181))
- LineageOS 16.0, proprietary files: [`extract_utils.sh`](https://github.com/LineageOS/android_vendor_lineage/blob/lineage-16.0/build/tools/extract_utils.sh)
  (pinning `|sha1`, `oat2dex()`, `vdexExtractor`, `compact_dex_converter`)
- KernelSU Next: [release v3.4.2](https://github.com/KernelSU-Next/KernelSU-Next/releases/tag/v3.4.2) (APK checksum);
  the kernel only looks for the manager in `/data/app` (`drivers/kernelsu/manager/throne_tracker.c` of the LibreHU
  kernel)
- LineageOS 16.0: [`ota_from_target_files.py`](https://github.com/LineageOS/android_build/blob/lineage-16.0/tools/releasetools/ota_from_target_files.py),
  [`core/Makefile`](https://github.com/LineageOS/android_build/blob/lineage-16.0/core/Makefile),
  [`init.rc`](https://github.com/LineageOS/android_system_core/blob/lineage-16.0/rootdir/init.rc),
  [`bacon.mk`](https://github.com/LineageOS/android_vendor_lineage/blob/lineage-16.0/build/tasks/bacon.mk)
- Prebuilt apps: [`prebuilt_internal.mk`](https://github.com/LineageOS/android_build/blob/lineage-16.0/core/prebuilt_internal.mk)
  and `uncompress-shared-libs` ([`definitions.mk`](https://github.com/LineageOS/android_build/blob/lineage-16.0/core/definitions.mk));
  Android 9 does not extract the libraries of a system app (`PackageManagerService.derivePackageAbi`)
- Audio: [`frameworks/av/services/audiopolicy/Android.mk`](https://github.com/LineageOS/android_frameworks_av/blob/lineage-16.0/services/audiopolicy/Android.mk)
  (`USE_XML_AUDIO_POLICY_CONF`); Bluetooth: [`bt_target.h`](https://github.com/LineageOS/android_system_bt/blob/lineage-16.0/internal_include/bt_target.h)
  (`BTA_DM_COD`, `BTA_AV_SINK_INCLUDED`), [`fluoride.go`](https://github.com/LineageOS/android_system_bt/blob/lineage-16.0/build/fluoride.go),
  Android 9 car profiles: `packages/services/Car` (`car_product/overlay/packages/apps/Bluetooth`, pie-release)

## TL;DR

1. Proxmox host: Ubuntu 20.04 template, `pct create 160 ... --cores 72 --memory 131072 --rootfs nvme:600`.
2. Container: packages of step 3, `repo init` + local manifest (tree + vendor repository) + `repo sync`.
3. PC + TWRP: `adb pull` of `vendor` and `system`, `scp` into the container, then the `tools/` scripts and
   `librehu/fetch_apks.sh`.
4. `lunch lineage_ac8257_demo-userdebug && mka systemimage bootimage vendorimage` (no zip possible).
5. Install: Format Data (first time), `fastboot flash` of `system`, `boot` and `vendor`; check
   `adb shell getenforce` = `Permissive`.

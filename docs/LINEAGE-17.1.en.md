# LineageOS 17.1 (Android 10) for the UJC201 — experimental branch

*Français : [LINEAGE-17.1.md](LINEAGE-17.1.md)*

Branch **`lineage-17.1`**: the `lineage-16.0` tree (LineageOS 16.0, Android 9) ported to LineageOS 17.1
(Android 10). A real ROM built from the LineageOS sources. The vendor stays the unit's own (Android 9, VNDK 28,
Treble) and the kernel the LibreHU one (`stable-4.9.337`).

**State (15/11/2026): being built by the CI, never tried on the unit.** `lineage-16.0` stays the everyday ROM.

## What changes from `lineage-16.0`

| Topic | `lineage-16.0` (Android 9) | `lineage-17.1` (Android 10) |
|---|---|---|
| Libraries of the stock vendor | VNDK 28 = the system's VNDK | `PRODUCT_EXTRA_VNDK_VERSIONS := 28` (device.mk): the system keeps `/system/lib*/vndk-28` and `vndk-sp-28` (`prebuilts/vndk/v28`) next to its own; the CI checks them |
| LineageOS `genfscon fuseblk` (conflicts with the Jancar vendor policy) | removed by `tools/patch_lineage_sources.sh` | `TARGET_HAS_FUSEBLK_SEPOLICY_ON_VENDOR := true` (LineageOS 17.1 switch, `device/lineage/sepolicy/common/sepolicy.mk`) |
| fs_mgr believing the unit locked (Jancar LK: `verifiedbootstate=green`) | `fs_mgr_is_device_unlocked()` fixed | **both** Android 10 copies of the test fixed: `fs_mgr_is_device_unlocked()` (`fs_mgr/fs_mgr.cpp`) and `IsDeviceUnlocked()` (`fs_mgr/libfs_avb/util.cpp`, vendor mount by the first stage init) |
| Panel and touch rotation | SurfaceFlinger + InputReader patch | same logic, patch redone for Android 10 (`TouchInputMapper::findViewport`) |
| Inverted backlight | LightsService patch | same logic, applied before both Android 10 paths (SurfaceControl and lights HAL) |
| Audio focus of Bluetooth music (A2DP sink) | Bluetooth app patch | Android 10 setting: `a2dp_sink_automatically_request_audio_focus` = true (overlay); no patch |
| `autochips.jar` on the BOOTCLASSPATH | Make module of the vendor repository | Android 10 builds the boot image in Soong, which only finds Soong modules ("failed to find dex jar path"): the script writes `vendor/jancar/ac8257_demo/Android.bp` (`dex_import`, as the LineageOS 17.1 extraction tool does) and removes the Make module of the same name from the local copy of the vendor repository (the repository itself is not changed) |
| APEX | — | flattened (`TARGET_FLATTEN_APEX := true`, Android 10 default without `updatable_apex.mk`) |
| `USE_XML_AUDIO_POLICY_CONF` | needed | removed: Android 10 only reads the vendor's XML |
| Privileged permissions checked | Android 9 list | `librehu/privileged-permissions-android10.txt` (217 permissions); the LibreHU apps of 15/11/2026 pass without additions |
| Updates feed of the Updater app | release `lineage-16.0-ota` | release `lineage-17.1-ota` |

## Update channel (OTA) of its own

A 17.1 only updates from the 17.1 channel, never from the 16.0 one or another version's, and a 16.0 never sees a
17.1. Four barriers:

1. **Separate feed**: the 17.1 Updater app reads `releases/download/lineage-17.1-ota/updater.json`
   (`overlay/packages/apps/Updater`); the 16.0 one reads `lineage-16.0-ota`. Each branch's CI only writes its own
   feed; the `lineage-17.1` one never touches `lineage-16.0-ota`.
2. **CI**: publishes only if the build's `ro.lineage.build.version` is `17.1`, the built Updater app holds the 17.1
   feed address (and not the 16.0 one), and the tag starts with `lineage-17.1-`. Otherwise nothing is published.
3. **LineageOS 17.1 Updater app** (`Utils.isCompatible` / `Utils.canInstall`): an update of an older version (16.0)
   is not even listed; another version is never installable (the same `ro.lineage.build.version` is required).
4. **Zip installer**: an install started by the Updater app (block map) reads the installed LineageOS version (the
   system's `build.prop`) and compares it with the zip's (`info/lineage_version`): when they differ it stops before
   writing anything ("each version has its own update channel"). A manual flash in TWRP stays possible to change
   versions on purpose.

There is no LineageOS 17.0: LineageOS's Android 10 release is 17.1 (`ro.lineage.build.version=17.1`).

## Build

As [BUILD.en.md](BUILD.en.md), with these differences:

```bash
repo init -u https://github.com/LineageOS/android.git -b lineage-17.1 --depth=1
```

Local manifest: the tree at `revision="lineage-17.1"`, the vendor repository at `revision="lineage-16.0"` (its only
branch: the same proprietary files serve).

```xml
<project name="LibreHU/android_device_alps_ac8257_demo" path="device/alps/ac8257_demo" remote="github" revision="lineage-17.1" />
<project name="LibreHU/android_vendor_jancar_ac8257_demo" path="vendor/jancar/ac8257_demo" remote="github" revision="lineage-16.0" />
```

After each `repo sync`, from the top of the sources (the build stops otherwise, `BoardConfig.mk`):

```bash
device/alps/ac8257_demo/tools/patch_lineage_sources.sh
```

Then `librehu/fetch_apks.sh`, `tools/fetch_kernel.sh`, `tools/fetch_viper.sh`, `lunch lineage_ac8257_demo-userdebug`,
`m systemimage signapk`, as for 16.0.

## CI

`.github/workflows/lineage-17.1-build.yml`: on each push to `lineage-17.1` whose message holds `[build]`, or by hand.
Apart from the `lineage-16.0` one: concurrency group `lineage-17.1-build`, ccache `lineage-17.1-ccache-*` (6 GiB, only
one kept: the repository's 10 GB of cache are shared), releases `lineage-17.1-<date>-<tree>` (prereleases), zip
`LibreHU-LineageOS-17.1-ac8257_demo-<date>-<tree>.zip`, feed `lineage-17.1-ota`.

## Install (once a build exists)

1. Full TWRP backup (system, boot, data): that is the way back.
2. Zip in TWRP as for 16.0 ([INSTALL.en.md](INSTALL.en.md)); `vbmeta` stays as it is (verification disabled).
3. **Wiping data** (Wipe > Format Data) is advised: moving from 16.0 to 17.1 with the data was never tried (the
   installer says so when it finds Android 9 data).
4. After the try, send `adb logcat -b all -d`, `adb shell dmesg`, `adb shell getprop` and, after a reboot, the
   content of `/sys/fs/pstore` (from TWRP).

## To check on the unit

- Android 10 property order: the stock vendor's are read **after** the system's (`init/property_service.cpp`,
  `property_load_boot_defaults`, "Overriding previous 'ro.' property"): a vendor value different from `device.mk`
  wins (compare with `getprop`).
- SELinux compilation at boot: Android 10 platform + Android 9 vendor policy through the 28.0 mapping. With
  `androidboot.selinux=permissive` (LibreHU boot image), a compilation failure is still fatal (reboot to the
  bootloader): first thing to look at if the unit does not boot.
- Compatibility matrix (FCM 3): kernel 4.9.337 covered. The experimental 4.19 kernel is not ("internal problem"
  dialog likely, not blocking).
- Activity starts from the background restricted by Android 10: to watch for LibreHU-service (reverse camera,
  sources).

## Sources

See [LINEAGE-17.1.md](LINEAGE-17.1.md#sources) (same links).

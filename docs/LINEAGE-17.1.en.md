# LineageOS 17.1 (Android 10) for the UJC201 — experimental branch

*Français : [LINEAGE-17.1.md](LINEAGE-17.1.md)*

Branch **`lineage-17.1`**: the `lineage-16.0` tree (LineageOS 16.0, Android 9) ported to LineageOS 17.1
(Android 10). A real ROM built from the LineageOS sources. The vendor stays the unit's own (Android 9, VNDK 28,
Treble) and the kernel the LibreHU one: `experimental-4.19.325`, variant `a10`, since 18/11/2026 (one kernel per
ROM: 16.0 keeps `stable-4.9.337`).

**State (18/11/2026): the tries of 18/11 (kernel 4.9, then 4.19) did not finish booting: system_server and SystemUI
died every 8 s. Android 10's Codec2 asks ION for any heap (`~0`) and got `ion_mm_heap_for_pa2mva`, a buffer of no
memory. Fixed in both kernels on 18/11; next build with 4.19 `a10`, to try again.** `lineage-16.0` stays the everyday
ROM.

## What changes from `lineage-16.0`

| Topic | `lineage-16.0` (Android 9) | `lineage-17.1` (Android 10) |
|---|---|---|
| Libraries of the stock vendor | VNDK 28 = the system's VNDK | `PRODUCT_EXTRA_VNDK_VERSIONS := 28` (device.mk): the system keeps `/system/lib*/vndk-28` and `vndk-sp-28` (`prebuilts/vndk/v28`) next to its own; the CI checks them |
| LineageOS `genfscon fuseblk` (conflicts with the Jancar vendor policy) | removed by `tools/patch_lineage_sources.sh` | `TARGET_HAS_FUSEBLK_SEPOLICY_ON_VENDOR := true` (LineageOS 17.1 switch, `device/lineage/sepolicy/common/sepolicy.mk`) |
| fs_mgr believing the unit locked (Jancar LK: `verifiedbootstate=green`) | `fs_mgr_is_device_unlocked()` fixed | **both** Android 10 copies of the test fixed: `fs_mgr_is_device_unlocked()` (`fs_mgr/fs_mgr.cpp`) and `IsDeviceUnlocked()` (`fs_mgr/libfs_avb/util.cpp`, vendor mount by the first stage init) |
| Panel and touch rotation | SurfaceFlinger + InputReader patch | same logic, patch redone for Android 10 (`TouchInputMapper::findViewport`) |
| Inverted backlight | LightsService patch | same logic, applied before both Android 10 paths (SurfaceControl and lights HAL) |
| Audio focus of Bluetooth music (A2DP sink) | Bluetooth app patch | Android 10 setting: `a2dp_sink_automatically_request_audio_focus` = true (overlay); no patch |
| `autochips.jar` on the BOOTCLASSPATH | Make module of the vendor repository (branch `lineage-16.0`) | Android 10 builds the boot image in Soong, which only finds Soong modules ("failed to find dex jar path"): vendor repository branch `lineage-17.1`, `Android.bp` (`dex_import`, as the LineageOS 17.1 extraction tool does); with a `lineage-16.0` copy, the script does the same in the local copy |
| APEX | — | flattened (`TARGET_FLATTEN_APEX := true`, Android 10 default without `updatable_apex.mk`) |
| `USE_XML_AUDIO_POLICY_CONF` | needed | still needed (Android 10 only reads the XML but `AudioPolicyManager.cpp` stops without the flag) |
| Privileged permissions checked | Android 9 list | `librehu/privileged-permissions-android10.txt` (217 permissions); the LibreHU apps of 15/11/2026 pass without additions |
| Updates feed of the Updater app | release `lineage-16.0-ota` | release `lineage-17.1-ota` |
| Audio policy (engine) | curves of the vendor's `audio_policy_configuration.xml` | Android 10 only reads `audio_policy_engine_configuration.xml` from `/vendor/etc` (not in the Android 9 vendor) and then takes the vendor's curves, which miss some streams (`AUDIO_STREAM_ACCESSIBILITY`): `frameworks/av` patch (as Android 11, a missing volume group gets the music curves); without it audioserver crashed in a loop |
| SystemUI | `/system/priv-app` (scanned before `/vendor/app/ivi-systemui`) | Android 10 puts it in `/system/product`, scanned **after** `/vendor/app`: the Jancar `ivi-systemui` (same package `com.android.systemui`) took its place; `frameworks/base` patch: back in `/system/priv-app` |

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

Local manifest: the tree and the vendor repository at `revision="lineage-17.1"` (the same proprietary files as its
`lineage-16.0` branch, `autochips.jar` as a Soong module).

```xml
<project name="LibreHU/android_device_alps_ac8257_demo" path="device/alps/ac8257_demo" remote="github" revision="lineage-17.1" />
<project name="LibreHU/android_vendor_jancar_ac8257_demo" path="vendor/jancar/ac8257_demo" remote="github" revision="lineage-17.1" />
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

## First try on the unit (15/11/2026, build of 15/11, kernel 4.9.337)

- Android did not finish booting (no `sys.boot_completed`): `system_server` waited for `media.audio_policy` forever
  ("Waiting for service 'media.audio_policy'"), as `audioserver` crashed at each start (47 tombstones: SIGSEGV, null
  pointer, `EngineBase::loadAudioPolicyEngineConfig()` of `libaudiopolicyenginedefault.so`). Cause: strategy
  `STRATEGY_ACCESSIBILITY` without a volume group (see the table). Fixed (`frameworks/av` patch).
- SystemUI: the vendor's (`/vendor/app/ivi-systemui`, Android 9) was installed instead of LineageOS's. Fixed
  (`frameworks/base` patch). The 16.0 data was kept: formatting data is still advised.
- Bluetooth: the MediaTek HAL stops ("TurnOn: failed to init Bluetooth!"): to look at in the next try.

## To check on the unit

- Android 10 property order: the stock vendor's are read **after** the system's (`init/property_service.cpp`,
  `property_load_boot_defaults`, "Overriding previous 'ro.' property"): a vendor value different from `device.mk`
  wins (compare with `getprop`).
- SELinux compilation at boot: Android 10 platform + Android 9 vendor policy through the 28.0 mapping. With
  `androidboot.selinux=permissive` (LibreHU boot image), a compilation failure is still fatal (reboot to the
  bootloader): first thing to look at if the unit does not boot.
- Compatibility matrix (FCM 3): Android 10's lists only the 4.4, 4.9 and 4.14 kernels
  (`hardware/interfaces/compatibility_matrices/Android.bp`). With 4.19, `Build.isBuildConsistent()` fails: an
  "internal problem" dialog is expected at boot, not blocking.
- Activity starts from the background restricted by Android 10: to watch for LibreHU-service (reverse camera,
  sources).

## Sources

See [LINEAGE-17.1.md](LINEAGE-17.1.md#sources) (same links).

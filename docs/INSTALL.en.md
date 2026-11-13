# Install LineageOS 16.0 on the UJC201

[Français](INSTALL.md) · Website page: <https://librehu.github.io/lineageos.html>

A real ROM built from the LineageOS sources (Android 9), not a GSI: LibreHU apps built in, LibreHU kernel, vendor
partition of **your** unit (never published). **Test builds**: it boots since 12/11/2026, several things are still
being fixed (see [Known issues](#known-issues)).

Only for the **Jancar UJC201** (Autochips AC8257, product `ac8257_demo`, 1280 x 720 screen). Other AC8257 head units
have another kernel, device tree or screen: do not install it on them.

> **Userdebug builds**: adb answers without authorization and `adb root` is allowed (anyone who plugs into the USB
> port gets a root shell); SELinux is permissive while the port is brought up. The zips are signed with the AOSP test
> key, like the ROM.

## 1. Download

Every build of the CI (branch `lineage-16.0`) is published in the
[releases of the repository](https://github.com/LibreHU/android_device_alps_ac8257_demo/releases) (`lineage-16.0-<date>-<tree>`):

| File | What it is |
|---|---|
| `LibreHU-LineageOS-16.0-ac8257_demo-<date>-<tree>.zip` | TWRP zip (system, boot, kernel modules): **the one to install** |
| `system.img.zst` | system image for fastboot (zstd: unpack before flashing) |
| `boot-librehu-bootmenu.img` / `boot-librehu.img` | boot image with / without the boot menu |
| `SHA256SUMS` | checksums of the files |

Check the zip: `certutil -hashfile file.zip SHA256` (Windows), `sha256sum file.zip` (Linux / macOS).

## 2. Before you start

1. **LibreHU TWRP** installed and working (branch `twrp` of this repository, tutorial on the website).
2. **Backups**, kept off the unit: a TWRP backup of Boot, System Image and Vendor Image; your stock `vbmeta.img`
   (needed below); ideally a full SP Flash Tool readback with `nvram`, `nvdata`, `protect1` / `protect2` (calibration
   and identifiers).
3. A PC with `adb` and `fastboot` (Android platform-tools), a USB cable, a USB drive or microSD card, a stable supply
   (engine running or a bench supply).

## 3. vbmeta: why and how

The `vbmeta` partition (Android Verified Boot) holds the hashes and keys of `boot`, `dtbo` and `vendor`, and a link
to `system` signed with Jancar's key; the bootloader checks it at every boot. The LineageOS `system` is not signed by
Jancar: with the stock vbmeta as it is, **the unit stays on the maker's logo**.

The fix: your own stock vbmeta with verification turned off, two flags of its header (byte 123): `1` = dm-verity off
(`--disable-verity`), `2` = verification off (`--disable-verification`). LineageOS needs **both** (value 3); the stock
also starts with this vbmeta. The zip never writes vbmeta: it checks the flags and stops without writing anything
while verification is on.

With fastboot:

```
adb reboot bootloader
fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img
fastboot reboot
```

Without fastboot (unit stuck on the logo): a copy of vbmeta with both flags (PowerShell, in the folder of the backup),
then SP Flash Tool, *Download* tab, your scatter, **Download Only**, only `vbmeta` with `vbmeta-disabled.img`, and
the unit connected switched off:

```
$b = [IO.File]::ReadAllBytes("$PWD\vbmeta.img")
if ([Text.Encoding]::ASCII.GetString($b, 0, 4) -ne "AVB0") { throw "not a vbmeta" }
$b[123] = $b[123] -bor 3
[IO.File]::WriteAllBytes("$PWD\vbmeta-disabled.img", $b)
```

> **Never** *Format All + Download* or *Firmware Upgrade* (they erase `nvram` / `nvdata`: calibration, MAC addresses,
> identifiers). **Never format `/vendor`** (LineageOS runs on it). **Never flash vbmeta without the two flags** while
> LineageOS is installed.

## 4. Install

1. Copy the (checked) zip to a **USB drive or microSD card**, not to the internal storage (Format Data erases it).
2. Flash vbmeta with both flags (section 3), then `fastboot reboot`.
3. Boot menu -> **TWRP** (or `fastboot oem reboot-recovery`).
4. **First install only** (coming from the stock or another ROM): *Wipe -> Format Data*, type `yes`.
5. *Install* -> the zip -> swipe. It writes `system` (read back and checked), `boot` and the kernel's Wi-Fi /
   Bluetooth / GPS / FM modules into `/vendor/lib/modules` (originals backed up in `/sdcard/LibreHU/backup`). It keeps
   the boot image type installed (with or without the menu); `bootmenu` or `plain` in the zip's name forces one.
6. *Reboot -> System*. The first boot takes a few minutes; the boot menu starts Android by itself after 3 seconds.

## 5. First boot

- Choose **LibreHU Launcher** as the home screen, *Always*.
- Installed by themselves: KernelSU Next manager, Aurora Store, LibreHU Helper (normal apps).
- **LibreHU service gets root** from KernelSU without asking; a choice made later in the manager, refusal included,
  is kept.
- Touch calibration applied at every boot (`/jancar/config/pointercal*.xml`).
- Wi-Fi country from the language chosen in the setup (from the next boot; `CN` until then).
- 720 x 1280 portrait panel turned to landscape (90°). Upside down: `adb root`,
  `adb shell setprop persist.librehu.display_rotation 270`, `adb reboot`.

## 6. Updates

*Settings -> System -> Updates* (LineageOS app): it reads the feed of the published builds (`updater.json` of the
`lineage-16.0-ota` release), downloads the next one, reboots into TWRP and installs it (since the build of
13/11/2026; first tries in progress). By hand: the new zip from TWRP, **without** Format Data.

## 7. Troubleshooting

| Symptom | What to do |
|---|---|
| Stays on the maker's logo | vbmeta still verifies: flash it with both flags (section 3) |
| The zip stops on "vbmeta : verification active" | same, then the zip again (nothing was written) |
| Boot menu, then fastboot | init stopped; without cutting the power: `fastboot oem reboot-recovery`, then in TWRP `adb pull /sys/fs/pstore` and send the log |
| Touch outside the screen | `adb logcat -s LibreHU-Touch` and `adb shell head -c 19 /proc/gt9xx_config` (panel id), to send |
| Green video (Android Auto, players) | known issue (ARM2 hand-over): a standby (ignition off, then on) brings the picture back |
| Black screen with the backlight on | after the screen turned off: known issue (touch wake-up), a USB mouse gets out of it; installed before 13/11: `adb shell locksettings set-disabled true` |
| Wi-Fi network not found | choose your language and region in Settings, reboot |

Reports: LibreHU Helper (installed with the ROM). It contains the unit's serial number: share it privately.

## 8. Back to stock

TWRP -> *Restore* of the backup (Boot, System Image, Vendor Image), then *Wipe -> Format Data* and reboot. The vbmeta
with both flags can stay. Without TWRP: the SP Flash Tool readback, *Download Only*, partition by partition.

## Known issues

- Hardware-decoded video green until the first standby: the ARM2 keeps two display layers, the vendor `backcar` HAL
  refuses the hand-over under LineageOS (being investigated).
- YouTube 1080p stutters; car standby unreliable; touch may not wake up after the screen turns off; Autochips
  watermark service missing (log noise).

Build it yourself: [BUILD.en.md](BUILD.en.md).

## TL;DR

Download the latest zip of the releases, flash your stock vbmeta with `--disable-verity --disable-verification`, then
in TWRP: Format Data (first time), the zip from a USB drive, reboot. Never Format All in SP Flash Tool, never format
`/vendor`. Updates afterwards through the LineageOS app.

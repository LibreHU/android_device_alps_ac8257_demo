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
- **Every LibreHU app gets root** from KernelSU without asking (all the `org.librehu.*` packages and ViPER4Android, at
  every boot); a choice made later in the manager, refusal included,
  is kept.
- Touch calibration applied at every boot (`/jancar/config/pointercal*.xml`).
- Wi-Fi country from the language chosen in the setup (from the next boot; `CN` until then).
- 720 x 1280 portrait panel turned to landscape (90°). Upside down: `adb root`,
  `adb shell setprop persist.librehu.display_rotation 270`, `adb reboot`.

## 6. Updates

*Settings -> System -> Updates* (LineageOS app): it reads the feed of the published builds (`updater.json` of the
`lineage-16.0-ota` release), downloads the next one, reboots into TWRP and installs it (since the build of
13/11/2026). Up to build `96472d7`, the install in TWRP failed ("extraction du zip impossible": the zip misread
uncrypt's block map); fixed afterwards. By hand: the new zip from TWRP, **without** Format Data.

## 7. Troubleshooting

| Symptom | What to do |
|---|---|
| Stays on the maker's logo | vbmeta still verifies: flash it with both flags (section 3) |
| The zip stops on "vbmeta : verification active" | same, then the zip again (nothing was written) |
| Boot menu, then fastboot | init stopped; without cutting the power: `fastboot oem reboot-recovery`, then in TWRP `adb pull /sys/fs/pstore` and send the log |
| Touch outside the screen | `adb logcat -s LibreHU-Touch` and `adb shell head -c 19 /proc/gt9xx_config` (panel id), to send |
| Green video (Android Auto, players) | fixed in the builds after 13/11 (`1ec65bc` and older: a standby, ignition off then on, brings the picture back; or `adb root`, `adb shell chown system:system /dev/backcardrv`, `adb shell chmod 0660 /dev/backcardrv`, `adb shell stop backcar_daemon`, `adb shell start backcar_daemon`, then restart LibreHU-service) |
| Black screen with the backlight on, or touch dead after the screen turned off | a USB mouse or `adb shell input keyevent 26` turns the screen on; build `171f952`: `adb root`, `adb shell "echo 1 > /sys/module/mtk_tpd/parameters/sleep_on_blank"`, then turn the screen off and on (at every boot, fixed in the next build); installed before 13/11: `adb shell locksettings set-disabled true` |
| No sound at all (amplifier muted) | fixed in the build after 14/11; before that: `adb root`, `adb shell chmod 0666 /dev/gpios_ioctl`, then in LibreHU-service, Audio tab, turn mute on then off (until the next reboot) |
| Wi-Fi network not found | choose your language and region in Settings, reboot |

Reports: LibreHU Helper (installed with the ROM). It contains the unit's serial number: share it privately.

## 8. Back to stock

TWRP -> *Restore* of the backup (Boot, System Image, Vendor Image), then *Wipe -> Format Data* and reboot. The vbmeta
with both flags can stay. Without TWRP: the SP Flash Tool readback, *Download Only*, partition by partition.

## Known issues

- Hardware-decoded video green until the first standby (`1ec65bc` and older): the ARM2 keeps two display layers, the
  vendor `backcar` HAL had no access to `/dev/backcardrv`; fixed in the next build (confirmed on the unit on 13/11).
- Fixed in the build after `96472d7` (kernel included): battery seen at 0-1 % (the kernel gives a full battery on
  mains), soft keyboard hidden (the kernel's "MCE keyboard" IR decoder taken for a physical keyboard; on an older
  build: *Settings -> System -> Languages & input -> Physical keyboard -> Show virtual keyboard*), LineageOS's AudioFX
  equalizer removed (it clashed with ViPER4Android); the front panel power key's long press can open Android's power
  menu (LibreHU-service, Touch tab, action "Power button held"). Waking the locked unit with that key: the touch
  panel stays awake while the screen is off; build `171f952` did not reset it when the screen came back (touch dead):
  fixed in the next build.
- No sound at all while Android plays and LibreHU-service shows mute off (builds up to 14/11): `/dev/gpios_ioctl` was
  created 0600 root, so the service could not release the amplifier mute (GPIO 166); ueventd rule added (stock
  permissions), found and confirmed on the unit by Reo Au In on 13/11.
- Bluetooth settings (and "Connected devices") crashing: the print service was missing (feature
  `android.software.print` not declared), and Android 9's Settings then crash; fixed in the build after 14/11.
- Wired Android Auto unavailable ("this head unit does not support USB host mode"), Internet over the cable and USB
  devices invisible to the apps: feature `android.hardware.usb.host` not declared (the stock system declared it);
  fixed in the build after 14/11. USB tethering of recent phones (RNDIS class `ef/04/01`): kernel driver fixed the
  same day.
- Multitouch not declared (the stock system declared it): fixed in the build after 14/11. 360° camera kit: the
  stock `atcavm_server` server and watermark service restored the same day.
- Being investigated (14/11): AV IN 1 and 2, audio routing. Bluetooth streaming: the
  LibreHU-service auto-connect retried an unreachable phone for ever (every 40 s); fixed in the service (`d0debeb`),
  to test again with the phone in range.
- 5 GHz Wi-Fi: the unit sees 5 GHz (channels 36 to 44 and 157 in a scan of 14/11). Android 9 does not know WPA3
  (SAE, added in Android 10): a WPA3-only network shows as "WPA2-EAP" (unknown AKM -> EAP by default in Android 9's
  code) and cannot be joined. Set the access point's 5 GHz radio to WPA2/WPA3 mixed mode, or use 2.4 GHz.
- YouTube in VP9 1080p60 stutters: the same on the stock and in Chrome, a limit of the hardware decoder: measured on
  the unit (codecbench, 13/11/2026), the hardware VP9 decodes 1080p at ~60 fps at most (MediaTek announces 23-79 fps),
  software VP9 at 61 fps, hardware H.264 at 126 fps. Watch in 720p (the screen's definition), 1080p30, or H.264:
  Firefox add-on enhanced-h264ify, with 60 fps allowed in its settings; car standby unreliable; touch may not wake up after the screen turns off; Autochips
  watermark service missing up to the build after 14/11: the vendor 360° HAL looked for it 5 times a second and this
  noise pushed the rest out of the logs (restored from the stock dump, for 360° kits).

Build it yourself: [BUILD.en.md](BUILD.en.md).

## TL;DR

Download the latest zip of the releases, flash your stock vbmeta with `--disable-verity --disable-verification`, then
in TWRP: Format Data (first time), the zip from a USB drive, reboot. Never Format All in SP Flash Tool, never format
`/vendor`. Updates afterwards through the LineageOS app.

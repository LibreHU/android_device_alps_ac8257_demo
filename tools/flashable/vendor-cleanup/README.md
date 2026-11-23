# Why LibreHU removed these files

The LibreHU LineageOS zip removes the head unit maker's apps and a few vendor libraries on purpose. Each removed file
is in this folder, with its permissions, owner, SELinux context and SHA-256 (`files.txt`). `restore.sh` puts
everything back.

LibreHU follows a zero-trust rule: closed-source code that LibreHU does not need, that conflicts with it or that can
talk to the network is not left running on the head unit.

## What was removed

### 1. Every app of the vendor partition (`/vendor/app/*`)
These are the apps of the stock firmware: Jancar (`com.jancar.*`, the `ivi-*` apps), Autochips (`com.autochips.*`),
MediaTek test and factory tools (`com.mediatek.*`), and third-party apps (TXZ voice assistant, CarbitLink /
EasyConnection, WeLink, SpeedPlay, Adobe Reader, Baidu network location...). The exact list depends on the firmware;
see `files.txt`.

- LibreHU replaces them: LibreHU-service (MCU, audio chip, CAN, reverse camera, steering wheel keys, settings),
  LibreHU Launcher, Phone, FM, and the LineageOS apps.
- They do harm on LineageOS:
  - `com.jancar.services` (ivi-services) crashes in a loop every few seconds. Before each crash it sets GPIOs
    (164, 97, 112: tuner power) and mutes Android's media stream (`setStreamMute(STREAM_MUSIC, true)`, then
    `setStreamMute(11)` throws `IllegalArgumentException: Bad stream type 11`): no sound. It also competes with
    LibreHU-service for the MCU serial port (`/dev/ttyS1`).
  - `com.jancar.settings` (ivi-settings) imports a MetaZone (display and hardware settings), a boot logo or a
    `metazone.bin` from any USB key that holds `/AutoUpdate/` or `/RecoveryUpdate/`.
  - `com.jancar.ota` can install a Jancar firmware through the recovery.
  - `com.jancar.tftdisplay` writes the panel voltages (AVDD / VCOM) through the MCU.
  - `ivi-systemui` and `ivi-launcher` use the package names of Android's own SystemUI and Launcher3.
  - Several of them talk to cloud services (TXZ voice, Baidu location, phone projection apps).
- `com.jancar.ecnr` (JanEcnr) only activates a license for the uVoice echo canceller (see 3), online.

### 2. MediaTek's framework overlay (`/vendor/overlay/framework-res__auto_generated_rro.apk`)
A static runtime resource overlay on Android's `framework-res`. It is applied on top of LineageOS's own settings and
changes them: automatic brightness offered (this head unit has no light sensor), screen turned on when the power is
unplugged, multi-user UI with 4 users, navigation bar, MediaTek's Wi-Fi MAC prefix (`00-0C-E7`), the MediaTek IMS
package, and about 1,200 per-carrier telephony values (VoLTE, video calls, Wi-Fi calling, MTU, APN).
The values that LineageOS lacks and that a board with a modem uses are in LibreHU's own overlay instead: the tethering
interfaces (`ap\d`, `rndis\d`, `bt-pan`, `bt-dun`, without which the hotspot cannot share a connection), SIM hot swap,
and the per-carrier tethering APN, MTU, TCP buffers, WAP push and voicemail values. The VoLTE, video call and Wi-Fi
calling flags are not: LineageOS has no IMS stack for them, so they would only show options that cannot work.
The other overlays of `/vendor/overlay` (Android's display cutout and dark theme ones) are kept.

### 3. The uVoice echo canceller and noise reducer for calls (when present)
`/vendor/lib[64]/libEcnrForCustomer.so`, `libuvoice_ecnr_sdk.so`, `libuvoice_ecnr_license.so`.

- Closed source, licensed per unit. The libraries embed an HTTP client (libcurl, OpenSSL) and an online activation
  ("UVoice authentication server", `/v1/activation-code/act`); the license is looked for in several places, for
  example `/jancar/ecnr/ecnr_license.bin`.
- The audio HAL loads them only through `libecnrhelper.so` (kept: the HAL needs it), with `dlopen`. When they are
  missing, the helper logs `libEcnrForAtc dlopen fail` and the call audio goes through without that processing.
- Replaced right after this cleanup by LibreHU's open-source library with the same interface (same file name,
  `libEcnrForCustomer.so`, in each `lib` / `lib64` folder that has `libecnrhelper.so`): WebRTC audio processing (echo
  canceller AEC3 or AECM, noise suppression, automatic gain), source in `native/ecnr-webrtc` of
  https://github.com/LibreHU/LibreHU-flashablesZips, settings in LibreHU-service (Audio > Microphone). Its own backup
  (`LibreHU/backup/ecnr-orig`) and way back: the zip `ecnr-webrtc-restore` (LibreHU Apps), which also stops the ROM
  zips from installing it again. Put `restore.sh` below back afterwards to get the uVoice files themselves.

### 4. The apps of the `jancar` partition (`/jancar/oem/app/*`)
TXZ voice assistant (cloud speech services), factory test and burn-in tools. LineageOS does not even install them
(it has no `/oem`); they only take space.

## What is kept
The HALs, libraries, firmware and init scripts of `/vendor` (LineageOS needs them), the other overlays,
`libecnrhelper.so`, and `/jancar/config` (touch calibration and front panel keys, read by LibreHU-service).

## Put everything back
From TWRP (Advanced > Terminal, or `adb shell` while TWRP runs):

```
sh /data/media/0/LibreHU/backup/<this folder>/restore.sh
```

It mounts `vendor` and `jancar`, copies the files back, sets their permissions, owner and SELinux context, and checks
each SHA-256. Then create `LibreHU/keep-vendor-apps` in the internal storage, or the next LibreHU zip removes them
again:

```
touch /data/media/0/LibreHU/keep-vendor-apps
```

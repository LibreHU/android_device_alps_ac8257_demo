#!/usr/bin/env python3
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: AGPL-3.0-or-later
"""TWRP zips of the WPA3 supplicant (HAL 1.2) for the LibreHU ROMs of Android 10 or newer, from the CI's wifi folder.

    tools/make_wifi_zips.py <wifi dir> <out dir>

<wifi dir>: bin/wpa_supplicant, lib64/android.hardware.wifi.supplicant@1.2.so, SHA256SUMS, vendor_needed.txt, version
(CI step "WPA3 supplicant", after tools/wifi/check_vendor_abi.py). Writes:
  - librehu_wifi_wpa3_twrp.zip: installs it in /vendor (tools/flashable/wifi-wpa3.sh, originals backed up once in
    /sdcard/LibreHU/backup/wifi-hal11-orig), removes LibreHU/no-wpa3 so that the ROM zip keeps it up to date;
  - librehu_wifi_wpa3_restore_twrp.zip: puts the original supplicant (HAL 1.1) back and leaves LibreHU/no-wpa3, so that
    the LibreHU ROM zips no longer install it.
The installer refuses anything but Android 10 or newer (ro.build.version.sdk >= 29: LineageOS 17.1 and later, crDroid
10 and later; Android 9 has no WPA3 in its framework) on ac8257_demo; both refuse a vendor still under dm-verity / AVB
verification (vbmeta flags). Reproducible archives (fixed dates).
"""
import os
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
DATE = (2020, 1, 1, 0, 0, 0)
FILES = ("bin/wpa_supplicant", "lib64/android.hardware.wifi.supplicant@1.2.so", "SHA256SUMS", "vendor_needed.txt",
         "version")

HEAD = r'''#!/sbin/sh
OUTFD=$2
ZIPFILE=$3
ui_print() { if [ -n "$OUTFD" ] && [ -e /proc/self/fd/$OUTFD ]; then echo "ui_print $1" > /proc/self/fd/$OUTFD; echo "ui_print" > /proc/self/fd/$OUTFD; else echo "$1"; fi; }
VENMNT=/vendor
SDCARD=/data/media/0
MOUNTED=0
cleanup() { sync; [ $MOUNTED = 1 ] && umount $VENMNT 2>/dev/null; umount /tmp/librehu_sys 2>/dev/null; }
abort() { ui_print "ERROR: $1"; cleanup; exit 1; }
part() { for p in /dev/block/platform/bootdevice/by-name/$1 /dev/block/by-name/$1; do [ -e $p ] && { echo $p; return; }; done; }

ui_print "LibreHU - %(title)s"
ui_print "--------------------------------"
case "$(getprop ro.product.device)" in ac8257_demo) ;; *) abort "device not supported (ac8257_demo only)";; esac
# Android 10 or newer (sdk 29+): Android 9 has no WPA3 in its framework (its stock supplicant stays). Only checked by
# the installer (%(sdkcheck)s): the way back always works.
mkdir -p /tmp/librehu_sys
mount -t ext4 -o ro $(part system) /tmp/librehu_sys 2>/dev/null
BP=/tmp/librehu_sys/system/build.prop; [ -f $BP ] || BP=/tmp/librehu_sys/build.prop
REL=$(sed -n 's/^ro.build.version.release=//p' $BP 2>/dev/null | head -n 1)
SDK=$(sed -n 's/^ro.build.version.sdk=//p' $BP 2>/dev/null | head -n 1)
umount /tmp/librehu_sys 2>/dev/null
case "$SDK" in ''|*[!0-9]*) SDK=0;; esac
if [ %(sdkcheck)s = 1 ] && [ $SDK -lt 29 ]; then
	abort "Android 10 or newer only (here: Android ${REL:-?}, sdk $SDK): Android 9 has no WPA3"
fi
# vbmeta: verification disabled (flag 2), as for the LineageOS zip: /vendor is written
VB=$(part vbmeta)
FLAGS=$(dd if=$VB bs=1 skip=123 count=1 2>/dev/null | od -An -tu1 | tr -d ' ')
[ $(( ${FLAGS:-0} & 2 )) = 2 ] || abort "vbmeta verification is on: /vendor cannot be changed"
[ -d $SDCARD ] || abort "internal storage not mounted: no backup possible"
umount $VENMNT 2>/dev/null; mkdir -p $VENMNT
mount -t ext4 -o rw $(part vendor) $VENMNT || abort "cannot mount vendor read-write"
MOUNTED=1
'''

INSTALL = r'''
T=/tmp/librehu_wpa3_zip; rm -rf $T; mkdir -p $T
unzip -o -q "$ZIPFILE" 'wifi/*' -d $T || abort "cannot extract the zip"
wifi_wpa3_install $T/wifi || abort "WPA3 not installed (see above); Wi-Fi unchanged"
mkdir -p $SDCARD/LibreHU; rm -f $SDCARD/LibreHU/no-wpa3
rm -rf $T
ui_print "Done. Reboot. WPA3 networks (SAE) and Enhanced Open now appear in the Wi-Fi settings."
ui_print "Way back: librehu_wifi_wpa3_restore_twrp.zip (LibreHU Apps)."
cleanup
exit 0
'''

RESTORE = r'''
wifi_wpa3_restore || abort "original supplicant not put back (see above)"
mkdir -p $SDCARD/LibreHU; echo "LibreHU: the LineageOS zip no longer installs the WPA3 supplicant" > $SDCARD/LibreHU/no-wpa3
ui_print "Done. Reboot. Wi-Fi as in the stock vendor (WPA2, HAL 1.1)."
ui_print "LibreHU/no-wpa3 left in internal storage: the LineageOS zip keeps the original."
cleanup
exit 0
'''


def write(path, script, files):
    with zipfile.ZipFile(path, "w") as z:
        for name, data, mode in [("META-INF/com/google/android/update-binary", script, 0o755),
                                 ("META-INF/com/google/android/updater-script", "# see update-binary\n", 0o755)] + files:
            info = zipfile.ZipInfo(name, date_time=DATE)
            info.external_attr = mode << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, data)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    wifi, out = sys.argv[1:]
    for f in FILES:
        if not os.path.isfile(os.path.join(wifi, f)):
            sys.exit(f"{os.path.join(wifi, f)} missing")
    funcs = open(os.path.join(HERE, "flashable", "wifi-wpa3.sh")).read()
    os.makedirs(out, exist_ok=True)
    files = [(f"wifi/{f}", open(os.path.join(wifi, f), "rb").read(), 0o644) for f in FILES]
    write(os.path.join(out, "librehu_wifi_wpa3_twrp.zip"),
          HEAD % {"title": "WPA3 for Android 10+ (wpa_supplicant HAL 1.2)", "sdkcheck": 1} + funcs + INSTALL, files)
    write(os.path.join(out, "librehu_wifi_wpa3_restore_twrp.zip"),
          HEAD % {"title": "WPA3 removed: original supplicant (HAL 1.1)", "sdkcheck": 0} + funcs + RESTORE, [])


if __name__ == "__main__":
    main()

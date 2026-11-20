#!/bin/bash
# LibreHU - WPA3 package of the ROM zips: the wpa_supplicant with the supplicant HAL 1.2 built once, in the
# LineageOS 17.1 tree, by .github/workflows/wifi-wpa3.yml (branch lineage-17.1), VNDK 28 checked, published in the
# release wifi-wpa3-17.1 of this repository. Every LibreHU ROM of Android 10 or newer runs on the same Android 9 vendor
# (VNDK 28): the same vendor binary serves them all, no ROM build compiles it again.
#
#   tools/ci/fetch_wifi_wpa3.sh <folder>
#
# Takes librehu_wifi_wpa3_twrp.zip from the release, checks it against the release's SHA256SUMS, then its wifi/
# files against their own SHA256SUMS, and leaves them in <folder> (bin/wpa_supplicant,
# lib64/android.hardware.wifi.supplicant@1.2.so, SHA256SUMS, vendor_needed.txt, version): the --wifi folder of
# tools/make_flashable_zip.py. Exit 1 (folder left empty) when the release or a check fails: the ROM is then built
# without WPA3, its installer leaves the stock supplicant alone.
set -euo pipefail
OUT=$1
R=${WPA3_REPO:-LibreHU/android_device_alps_ac8257_demo}
T=wifi-wpa3-17.1
rm -rf "$OUT"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
ok=0
for i in 1 2 3; do
	if gh release download "$T" --repo "$R" --dir "$D" --clobber -p librehu_wifi_wpa3_twrp.zip -p SHA256SUMS; then
		ok=1
		break
	fi
	echo "WPA3: release $T not downloaded (attempt $i of 3)" >&2
	sleep 20
done
[ $ok = 1 ] || { echo "WPA3: no release $T in $R: ROM without WPA3" >&2; exit 1; }
(cd "$D" && grep ' librehu_wifi_wpa3_twrp.zip$' SHA256SUMS | sha256sum -c --quiet) || {
	echo "WPA3: librehu_wifi_wpa3_twrp.zip does not match the release's SHA256SUMS" >&2; exit 1; }
python3 -I - "$D/librehu_wifi_wpa3_twrp.zip" "$D/x" <<'EOF'
import os, sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
for n in z.namelist():
    if n.startswith("wifi/") and not n.endswith("/"):
        p = os.path.normpath(n)
        if p.startswith("..") or os.path.isabs(p):
            sys.exit(f"bad path {n}")
        z.extract(n, sys.argv[2])
EOF
W=$D/x/wifi
for f in bin/wpa_supplicant lib64/android.hardware.wifi.supplicant@1.2.so SHA256SUMS vendor_needed.txt version; do
	[ -f "$W/$f" ] || { echo "WPA3: $f missing from the zip" >&2; exit 1; }
done
(cd "$W" && sha256sum -c --quiet SHA256SUMS) || { echo "WPA3: wifi/ files do not match their SHA256SUMS" >&2; exit 1; }
mkdir -p "$OUT"
cp -r "$W/." "$OUT/"
echo "WPA3: supplicant $(cat "$OUT/version") ready in $OUT"

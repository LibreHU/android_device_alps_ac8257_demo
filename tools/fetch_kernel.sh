#!/bin/bash
#
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: Apache-2.0
#
# Telecharge le noyau LibreHU de la branche stable-4.9.337 de android_kernel_autochips_ac8257_4.9 (la seule suivie
# depuis le 01/11/2026 : correctifs linux-stable jusqu'a 4.9.337, KernelSU Next, veille, frequences CPU / GPU...)
# depuis sa release latest-<branche>, compilee par la CI du depot du noyau :
#   - Image.gz-dtb -> prebuilt/kernel-librehu, pris par BoardConfig.mk a la place du noyau stock (prebuilt/kernel) ;
#   - ses modules Wi-Fi / BT / GPS / FM recompiles avec lui (librehu_connectivity_ksu.zip) -> prebuilt/modules/, a
#     mettre dans l'image vendor par tools/vendor_add_conn_modules.sh : ce noyau refuse ceux du vendor stock (CRC des
#     symboles differents).
# Empreintes verifiees (celles que GitHub donne pour les fichiers de la release), et le noyau de l'image doit etre
# celui des modules. Ces fichiers ne sont pas versionnes (.gitignore) : a relancer pour prendre un nouveau build.
#   tools/fetch_kernel.sh [branche]
#

set -e

MY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRANCH="${1:-stable-4.9.337}"
REPO=LibreHU/android_kernel_autochips_ac8257_4.9
OUT="$MY_DIR/../prebuilt"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

curl -fsSL -o "$T/release.json" "https://api.github.com/repos/$REPO/releases/tags/latest-$BRANCH"
python3 - "$T" <<'PY'
import json, sys
t = sys.argv[1]
r = json.load(open(f"{t}/release.json"))
assets = {a["name"]: a for a in r["assets"]}
with open(f"{t}/assets", "w") as f:
    for n in ("Image.gz-dtb", "librehu_connectivity_ksu.zip", "release.txt"):
        a = assets.get(n)
        if a is None:
            sys.exit(f"{n} absent de la release {r['tag_name']}")
        f.write(f"{n} {a['browser_download_url']} {(a.get('digest') or '').removeprefix('sha256:')}\n")
PY
while read -r NAME URL DIGEST; do
    curl -fsSL -o "$T/$NAME" "$URL"
    SUM=$(sha256sum "$T/$NAME" | cut -d' ' -f1)
    [ -z "$DIGEST" ] || [ "$DIGEST" = "$SUM" ] || { echo "$NAME : empreinte differente de celle de la release" >&2; exit 1; }
done < "$T/assets"

rm -rf "$OUT/modules.new"
mkdir -p "$OUT/modules.new"
python3 - "$T" "$OUT/modules.new" <<'PY'
import hashlib, re, sys, zipfile, zlib
t, out = sys.argv[1], sys.argv[2]
names = ["wmt_drv", "wmt_chrdev_wifi", "bt_drv", "gps_drv", "fmradio_drv", "wlan_drv_gen4m"]
z = zipfile.ZipFile(f"{t}/librehu_connectivity_ksu.zip")
sums = []
for n in names:
    data = z.read(f"modules/{n}.ko")
    if data[:4] != b"\x7fELF":
        sys.exit(f"{n}.ko : pas un module ELF")
    open(f"{out}/{n}.ko", "wb").write(data)
    sums.append(f"{hashlib.sha256(data).hexdigest()}  {n}.ko")
open(f"{out}/SHA256SUMS", "w").write("\n".join(sums) + "\n")
kv = z.read("kernel_version").decode().strip()
# Image.gz-dtb = Image en gzip, puis le DTB : le premier membre gzip seulement
image = zlib.decompressobj(16 + zlib.MAX_WBITS).decompress(open(f"{t}/Image.gz-dtb", "rb").read())
m = re.search(rb"Linux version [^\n\x00]+", image)
if m is None or m.group(0).decode() != kv:
    sys.exit("le noyau de Image.gz-dtb n'est pas celui des modules")
open(f"{out}/kernel_version", "w").write(kv + "\n")
PY
cp "$T/release.txt" "$OUT/modules.new/release.txt"
cp "$T/Image.gz-dtb" "$OUT/kernel-librehu"
rm -rf "$OUT/modules"
mv "$OUT/modules.new" "$OUT/modules"

echo "noyau : $(sed -n 's/^version=//p' "$OUT/modules/release.txt") ($BRANCH)"
echo "  $(cat "$OUT/modules/kernel_version")"
sha256sum "$OUT/kernel-librehu" "$OUT"/modules/*.ko

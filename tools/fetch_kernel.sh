#!/bin/bash
#
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Telecharge le noyau LibreHU de la branche stable-4.9.337 de android_kernel_autochips_ac8257_4.9 (la seule suivie
# depuis le 01/11/2026 : correctifs linux-stable jusqu'a 4.9.337, KernelSU Next, veille, frequences CPU / GPU...)
# depuis sa release latest-<branche>, compilee par la CI du depot du noyau :
#   - Image.gz-dtb -> prebuilt/kernel-librehu, pris par BoardConfig.mk a la place du noyau stock (prebuilt/kernel) ;
#   - ses modules Wi-Fi / BT / GPS / FM recompiles avec lui (librehu_connectivity_ksu.zip) -> prebuilt/modules/, a
#     mettre dans l'image vendor par tools/vendor_add_conn_modules.sh : ce noyau refuse ceux du vendor stock (CRC des
#     symboles differents) ;
#   - ses images de boot (boot_ac8257_bootmenu.img, boot_ac8257.img) -> prebuilt/boot-librehu-bootmenu.img et
#     prebuilt/boot-librehu.img, prises par BoardConfig.mk (BOARD_PREBUILT_BOOTIMAGE) : en-tete, ligne de commande et
#     pied AVB du boot stock, sans lequel le LK refuse l'image. Seul ajout : androidboot.selinux=permissive a la ligne
#     de commande de l'en-tete (voir plus bas ; LIBREHU_SELINUX=enforcing pour ne pas l'ajouter).
# Empreintes verifiees (celles que GitHub donne pour les fichiers de la release), et le noyau de chaque image doit
# etre celui des modules.
# Le correctif de l'identifiant de puce Wi-Fi (persist.vendor.connsys.chipid 0x0000 sur un /data vide, boucle de
# redemarrages des que le Wi-Fi s'allume) est dans stable-4.9.337 depuis le 13/11/2026 (branche de test fusionnee).
# Ces fichiers ne sont pas versionnes (.gitignore) : a relancer pour prendre un nouveau build.
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
    for n in ("Image.gz-dtb", "librehu_connectivity_ksu.zip", "boot_ac8257.img", "boot_ac8257_bootmenu.img", "release.txt"):
        a = assets.get(n)
        if a is None:
            sys.exit(f"{n} absent de la release {r['tag_name']}")
        d = a.get("digest") or ""
        # pas de str.removeprefix : Python 3.8 (Ubuntu 20.04) ne l'a pas
        f.write(f"{n} {a['browser_download_url']} {d[len('sha256:'):] if d.startswith('sha256:') else d}\n")
PY
while read -r NAME URL DIGEST; do
    curl -fsSL -o "$T/$NAME" "$URL"
    SUM=$(sha256sum "$T/$NAME" | cut -d' ' -f1)
    [ -z "$DIGEST" ] || [ "$DIGEST" = "$SUM" ] || { echo "$NAME : empreinte differente de celle de la release" >&2; exit 1; }
done < "$T/assets"

rm -rf "$OUT/modules.new"
mkdir -p "$OUT/modules.new"
python3 - "$T" "$OUT/modules.new" <<'PY'
import hashlib, re, struct, sys, zipfile, zlib
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
# Images de boot : en-tete Android v1, 10 Mio au plus (partition boot), pied AVB, noyau = celui des modules
for n in ("boot_ac8257.img", "boot_ac8257_bootmenu.img"):
    b = open(f"{t}/{n}", "rb").read()
    if b[:8] != b"ANDROID!" or len(b) > 10485760 or b[-64:-60] != b"AVBf":
        sys.exit(f"{n} : pas une image de boot de l'UJC201 (en-tete, taille ou pied AVB)")
    ksize, page = struct.unpack_from("<I", b, 8)[0], struct.unpack_from("<I", b, 36)[0]
    kimg = zlib.decompressobj(16 + zlib.MAX_WBITS).decompress(b[page:page + ksize])
    m = re.search(rb"Linux version [^\n\x00]+", kimg)
    if m is None or m.group(0).decode() != kv:
        sys.exit(f"le noyau de {n} n'est pas celui des modules")
PY
# SELinux permissif pour la mise au point de LineageOS. L'init d'un build userdebug ne passe en permissif que si la
# ligne de commande du noyau contient androidboot.selinux=permissive (system/core/init/selinux.cpp, StatusFromCmdline :
# enforcing par defaut). BOARD_KERNEL_CMDLINE ne sert pas avec une image de boot prebuilt, l'en-tete de ces images est
# celui du stock (bootopt=64S3,32N2,64N2 buildvariant=user) et le LK n'ajoute pas androidboot.selinux (/proc/cmdline du
# stock, rapport LibreHU Helper) : sans cet ajout, LineageOS serait en enforcing, mcu_ready ne pourrait pas ouvrir
# /dev/ttyS1 et le MCU couperait le SoC une dizaine de secondes apres le demarrage. Le LK transmet bien la ligne de
# commande de l'en-tete (bootopt=... est dans /proc/cmdline). Seul ce champ change (octets 64 a 575 de l'en-tete v1) :
# noyau, ramdisk, taille de l'image et pied AVB restent ceux de la CI.
if [ "${LIBREHU_SELINUX:-permissive}" = permissive ]; then
    python3 - "$T/boot_ac8257.img" "$T/boot_ac8257_bootmenu.img" <<'PY'
import sys
ARG = b"androidboot.selinux=permissive"
for p in sys.argv[1:]:
    b = bytearray(open(p, "rb").read())
    size, footer = len(b), bytes(b[-64:])
    cmd = bytes(b[64:576]).rstrip(b"\0")
    if ARG not in cmd.split():
        new = cmd + b" " + ARG if cmd else ARG
        if len(new) > 511:
            sys.exit(f"{p} : ligne de commande de l'en-tete trop longue")
        b[64:576] = new.ljust(512, b"\0")
    if len(b) != size or bytes(b[-64:]) != footer or b[:8] != b"ANDROID!":
        sys.exit(f"{p} : image modifiee au-dela de la ligne de commande")
    open(p, "wb").write(b)
    print(f"{p.rsplit('/', 1)[-1]} : {bytes(b[64:576]).rstrip(bytes(1)).decode()}")
PY
fi
cp "$T/release.txt" "$OUT/modules.new/release.txt"
cp "$T/Image.gz-dtb" "$OUT/kernel-librehu"
cp "$T/boot_ac8257.img" "$OUT/boot-librehu.img"
cp "$T/boot_ac8257_bootmenu.img" "$OUT/boot-librehu-bootmenu.img"
rm -rf "$OUT/modules"
mv "$OUT/modules.new" "$OUT/modules"

echo "noyau : $(sed -n 's/^version=//p' "$OUT/modules/release.txt") ($BRANCH)"
echo "  $(cat "$OUT/modules/kernel_version")"
sha256sum "$OUT/kernel-librehu" "$OUT/boot-librehu.img" "$OUT/boot-librehu-bootmenu.img" "$OUT"/modules/*.ko

#!/bin/bash
#
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Telecharge le noyau LibreHU de LineageOS 21.0 (Android 14) : branche rc-4.19.325 de android_kernel_autochips_ac8257_4.9,
# variante a11-lto32 (config ac8257_a10.config + ac8257_a11.config + ac8257_lto32.config : Android 11+, ThinLTO,
# connectivite integree, image de 32 Mio pour la partition boot agrandie ; le zip de la ROM fait la migration). Un noyau par ROM : 16.0 (Android 9)
# avec stable-4.9.337, 17.1 (Android 10) avec 4.19. Depuis la release latest-<branche>, compilee par la CI du depot
# du noyau :
#   - Image.gz-dtb_a11-lto32 -> prebuilt/kernel-librehu, pris par BoardConfig.mk a la place du noyau stock ;
#   - ses images de boot de 32 Mio (boot_ac8257_bootmenu_a11-lto32.img, boot_ac8257_a11-lto32.img) ->
#     prebuilt/boot-librehu-bootmenu.img et prebuilt/boot-librehu.img, prises par BoardConfig.mk
#     (BOARD_PREBUILT_BOOTIMAGE) : en-tete, ligne de commande et pied AVB du boot stock, sans lequel le LK refuse
#     l'image. Seul ajout : androidboot.selinux=permissive a la ligne de commande de l'en-tete (voir plus bas ;
#     LIBREHU_SELINUX=enforcing pour ne pas l'ajouter) ;
#   - librehu_boot32_twrp.zip (partition boot 10 -> 32 Mio) -> prebuilt/boot32/, mis dans le zip de la ROM, qui le
#     lance quand la partition fait encore 10 Mio ;
#   - prebuilt/modules/ sans module (Wi-Fi / BT / GPS / FM integres au noyau) : SHA256SUMS vide, BUILTIN,
#     kernel_version (banniere de l'Image) et release.txt.
# Variante sans -lto32 (stable-4.9.337, ou 4.19 a9) : modules Wi-Fi / BT / GPS / FM recompiles avec le noyau
# (librehu_connectivity_ksu_<v>.zip) -> prebuilt/modules/, images de boot de 10 Mio au plus.
# Empreintes verifiees (celles que GitHub donne pour les fichiers de la release), et le noyau de chaque image doit
# etre celui des modules (ou de l'Image pour -lto32).
# Le correctif ION d'Android 10 (Codec2 demande n'importe quel heap, ~0 : il recevait ion_mm_heap_for_pa2mva, un
# buffer sans memoire, et system_server mourait a chaque demarrage) est dans les deux branches depuis le 18/11/2026.
# Ces fichiers ne sont pas versionnes (.gitignore) : a relancer pour prendre un nouveau build.
#   tools/fetch_kernel.sh [branche [variante]]     (defaut : rc-4.19.325 a11-lto32 ; stable-4.9.337 sans variante)
#

set -e

MY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRANCH="${1:-rc-4.19.325}"
# les releases 4.19 publient une variante par fichier (suffixe _a9 / _a9-lto32 / _a10-lto32 / _a11-lto32), celles de
# 4.9 aucune. Android 10 et plus : noyaux -lto32 seulement depuis le 19/11/2026 (partition boot de 32 Mio, connectivite
# integree au noyau, aucun module ; les noyaux 10 Mio a10 / a11 ne tenaient plus)
case "$BRANCH" in
    *4.19*) VARIANT="${2:-a11-lto32}" ;;  # Android 11+ : binderfs, pas de RT group scheduling
    *) VARIANT="${2:-}" ;;
esac
case "$VARIANT" in *-lto32) LTO32=1 ;; *) LTO32=0 ;; esac
REPO=LibreHU/android_kernel_autochips_ac8257_4.9
OUT="$MY_DIR/../prebuilt"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# API de GitHub avec le jeton de la CI quand il y en a un (GH_TOKEN / GITHUB_TOKEN) : sans jeton, 60 requetes par heure
# et par adresse IP, partagees entre les runners (403 sinon)
TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
curl -fsSL --retry 4 --retry-delay 20 --retry-all-errors ${TOKEN:+-H "Authorization: Bearer $TOKEN"} \
    -o "$T/release.json" "https://api.github.com/repos/$REPO/releases/tags/latest-$BRANCH"
python3 - "$T" "$VARIANT" "$LTO32" <<'PY'
import json, sys
t, v, lto32 = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
r = json.load(open(f"{t}/release.json"))
assets = {a["name"]: a for a in r["assets"]}
# nom local (celui de la suite du script) -> nom dans la release, avec la variante s'il y en a une
sfx = f"_{v}" if v else ""
names = {
    "Image.gz-dtb": f"Image.gz-dtb{sfx}",
    "boot_ac8257.img": f"boot_ac8257{sfx}.img",
    "boot_ac8257_bootmenu.img": f"boot_ac8257_bootmenu{sfx}.img",
    "release.txt": "release.txt",
}
if lto32:
    # pas de modules (tout integre) ; zip de migration de la partition boot 10 -> 32 Mio, lance par le zip de la ROM
    names["librehu_boot32_twrp.zip"] = "librehu_boot32_twrp.zip"
else:
    names["librehu_connectivity_ksu.zip"] = f"librehu_connectivity_ksu{sfx}.zip"
with open(f"{t}/assets", "w") as f:
    for n, rn in names.items():
        a = assets.get(rn)
        if a is None:
            sys.exit(f"{rn} absent de la release {r['tag_name']}")
        d = a.get("digest") or ""
        # pas de str.removeprefix : Python 3.8 (Ubuntu 20.04) ne l'a pas
        f.write(f"{n} {a['browser_download_url']} {d[len('sha256:'):] if d.startswith('sha256:') else d}\n")
PY
while read -r NAME URL DIGEST; do
    curl -fsSL --retry 4 --retry-delay 20 --retry-all-errors -o "$T/$NAME" "$URL"
    SUM=$(sha256sum "$T/$NAME" | cut -d' ' -f1)
    [ -z "$DIGEST" ] || [ "$DIGEST" = "$SUM" ] || { echo "$NAME : empreinte differente de celle de la release" >&2; exit 1; }
done < "$T/assets"

rm -rf "$OUT/modules.new"
mkdir -p "$OUT/modules.new"
python3 - "$T" "$OUT/modules.new" "$LTO32" <<'PY'
import hashlib, re, struct, sys, zipfile, zlib
t, out, lto32 = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
# Image.gz-dtb = Image en gzip, puis le DTB : le premier membre gzip seulement
image = zlib.decompressobj(16 + zlib.MAX_WBITS).decompress(open(f"{t}/Image.gz-dtb", "rb").read())
m = re.search(rb"Linux version [^\n\x00]+", image)
if m is None:
    sys.exit("Image.gz-dtb : banniere du noyau introuvable")
if lto32:
    # connectivite integree au noyau : aucun module, SHA256SUMS vide (le zip de la ROM n'installe rien dans vendor)
    kv = m.group(0).decode()
    open(f"{out}/SHA256SUMS", "w").write("")
    open(f"{out}/BUILTIN", "w").write("connectivity built into the kernel (-lto32): no module\n")
else:
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
    if m.group(0).decode() != kv:
        sys.exit("le noyau de Image.gz-dtb n'est pas celui des modules")
open(f"{out}/kernel_version", "w").write(kv + "\n")
# Images de boot : en-tete Android v1, pied AVB, noyau = celui de Image.gz-dtb ; 10 Mio au plus (partition boot
# d'origine), exactement 32 Mio pour un noyau -lto32 (partition agrandie par librehu_boot32_twrp.zip)
for n in ("boot_ac8257.img", "boot_ac8257_bootmenu.img"):
    b = open(f"{t}/{n}", "rb").read()
    size_ok = len(b) == 33554432 if lto32 else len(b) <= 10485760
    if b[:8] != b"ANDROID!" or not size_ok or b[-64:-60] != b"AVBf":
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
rm -rf "$OUT/boot32"
if [ "$LTO32" = 1 ]; then
    mkdir -p "$OUT/boot32"
    cp "$T/librehu_boot32_twrp.zip" "$OUT/boot32/librehu_boot32_twrp.zip"
fi
rm -rf "$OUT/modules"
mv "$OUT/modules.new" "$OUT/modules"

echo "noyau : $(sed -n 's/^version=//p' "$OUT/modules/release.txt") ($BRANCH${VARIANT:+ $VARIANT})"
echo "  $(cat "$OUT/modules/kernel_version")"
sha256sum "$OUT/kernel-librehu" "$OUT/boot-librehu.img" "$OUT/boot-librehu-bootmenu.img" $(ls "$OUT"/modules/*.ko "$OUT"/boot32/*.zip 2>/dev/null)

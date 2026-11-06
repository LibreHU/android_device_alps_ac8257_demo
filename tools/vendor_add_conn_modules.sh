#!/bin/bash
#
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Met dans l'image vendor lue par tools/get_vendor_img.sh les modules Wi-Fi / Bluetooth / GPS / radio FM recompiles
# avec le noyau LibreHU (prebuilt/modules, ecrits par tools/fetch_kernel.sh), a la place de ceux du stock : le noyau
# LibreHU linux-stable refuse les modules du vendor stock (CRC des symboles differents). Meme resultat que les zips
# kernel-stable / conn-modules-stable de LibreHU-flashablesZips sur l'unite : memes six fichiers dans /lib/modules de
# vendor, droits et contexte SELinux de l'original, marqueur /lib/modules/.librehu_conn.
# Sans le noyau LibreHU (prebuilt/kernel-librehu absent), ne rien faire : le noyau stock veut les modules du stock.
#
# Modifie seulement l'image locale (debugfs), jamais l'unite. Une copie d'origine est gardee (vendor.img.orig).
#   tools/vendor_add_conn_modules.sh [vendor.img]
#

set -e

MY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMG="${1:-$MY_DIR/../../../../vendor/jancar/ac8257_demo/vendor.img}"
MODS="$MY_DIR/../prebuilt/modules"
NAMES="wmt_drv wmt_chrdev_wifi bt_drv gps_drv fmradio_drv wlan_drv_gen4m"
MD=/lib/modules

command -v debugfs >/dev/null || { echo "debugfs manquant (paquet e2fsprogs)" >&2; exit 1; }
[ -f "$IMG" ] || { echo "$IMG introuvable : lancer d'abord tools/get_vendor_img.sh" >&2; exit 1; }
[ -f "$MODS/SHA256SUMS" ] && [ -f "$MY_DIR/../prebuilt/kernel-librehu" ] || {
    echo "prebuilt/modules ou prebuilt/kernel-librehu absent : lancer d'abord tools/fetch_kernel.sh" >&2; exit 1; }
(cd "$MODS" && sha256sum -c --quiet SHA256SUMS)

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

[ -f "$IMG.orig" ] || cp "$IMG" "$IMG.orig"

dbg() { debugfs -R "$1" "$IMG" 2>/dev/null; }

CMDS="$T/cmds"
: > "$CMDS"
for m in $NAMES; do
    k=$MD/$m.ko
    # Contexte SELinux de l'original (valeur brute de l'attribut, NUL final compris), vendor_file sinon
    rm -f "$T/ctx_$m"
    dbg "ea_get -f $T/ctx_$m $k security.selinux" >/dev/null
    [ -s "$T/ctx_$m" ] || printf 'u:object_r:vendor_file:s0\0' > "$T/ctx_$m"
    {
        echo "rm $k"
        echo "write $MODS/$m.ko $k"
        echo "sif $k mode 0100644"
        echo "sif $k uid 0"
        echo "sif $k gid 0"
        echo "ea_set -f $T/ctx_$m $k security.selinux"
    } >> "$CMDS"
done
{ echo "$(sed -n 's/^version=//p' "$MODS/release.txt") $(sed -n 's/^branch=//p' "$MODS/release.txt")"
  cat "$MODS/kernel_version"; } > "$T/mark"
printf 'u:object_r:vendor_file:s0\0' > "$T/ctx_mark"
{
    echo "rm $MD/.librehu_conn"
    echo "write $T/mark $MD/.librehu_conn"
    echo "sif $MD/.librehu_conn mode 0100644"
    echo "sif $MD/.librehu_conn uid 0"
    echo "sif $MD/.librehu_conn gid 0"
    echo "ea_set -f $T/ctx_mark $MD/.librehu_conn security.selinux"
} >> "$CMDS"
debugfs -w -f "$CMDS" "$IMG" >/dev/null 2>"$T/err" || { cat "$T/err" >&2; exit 1; }
e2fsck -fn "$IMG" >/dev/null

# Verification : chaque module relu dans l'image a l'empreinte attendue
for m in $NAMES; do
    dbg "dump $MD/$m.ko $T/check.ko" >/dev/null
    [ "$(sha256sum "$T/check.ko" | cut -d' ' -f1)" = "$(grep " $m.ko\$" "$MODS/SHA256SUMS" | cut -d' ' -f1)" ] || {
        echo "$m.ko relu different dans $IMG" >&2; exit 1; }
done
echo "modules de connectivite du noyau LibreHU dans $IMG :"
dbg "cat $MD/.librehu_conn"

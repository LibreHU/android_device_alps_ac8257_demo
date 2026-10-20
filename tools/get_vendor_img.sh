#!/bin/bash
#
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: Apache-2.0
#
# Lit la partition vendor de l'unite (lecture seule, rien n'est ecrit sur l'unite) et la place la ou
# BoardConfig.mk l'attend : <racine LineageOS>/vendor/jancar/ac8257_demo/vendor.img.
# L'image reste locale : elle contient les fichiers proprietaires de Jancar / Autochips / MediaTek,
# ne pas la publier.
#
# Unite demarree sous TWRP (adb root) ou sous la ROM stock avec su.
#   tools/get_vendor_img.sh [racine_lineage]
#

set -e

MY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINEAGE_ROOT="${1:-$MY_DIR/../../../..}"
OUT="$LINEAGE_ROOT/vendor/jancar/ac8257_demo/vendor.img"
PART=/dev/block/platform/bootdevice/by-name/vendor
SIZE=2147483648  # 0x80000000, table des partitions du noyau stock #72

mkdir -p "$(dirname "$OUT")"
adb wait-for-device

if [ "$(adb shell id -u | tr -d '\r')" = "0" ]; then
    READ="cat $PART"
else
    READ="su -c 'cat $PART'"
fi

echo "Lecture de $PART vers $OUT (2 Go)..."
adb exec-out "$READ" > "$OUT.part"

GOT=$(stat -c %s "$OUT.part")
if [ "$GOT" != "$SIZE" ]; then
    echo "Taille lue $GOT, attendue $SIZE : lecture incomplete" >&2
    rm -f "$OUT.part"
    exit 1
fi
mv "$OUT.part" "$OUT"

# Verification : image ext4 et build.prop du vendor Android 9 stock
if command -v debugfs >/dev/null; then
    debugfs -R "cat /build.prop" "$OUT" 2>/dev/null | grep -E "ro.vendor.build.fingerprint|ro.vndk.version" || true
fi
sha256sum "$OUT"

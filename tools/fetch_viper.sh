#!/bin/bash
#
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Pilote ViPERFX_RE (https://github.com/likelikeslike/ViPERFX_RE, module officiel non-AIDL, Android 9) dans
# prebuilt/viper/ : libv4a_re_armeabi-v7a.so, libv4a_re_arm64-v8a.so, LICENSE (GPL-2.0), SOURCE, version, SHA256SUMS.
# Pris par tools/make_flashable_zip.py (le zip TWRP l'installe ou le met a jour dans /vendor, voir
# tools/flashable/update-binary.sh) et par tools/vendor_add_viper.sh. Avec l'appli ViPER4Android LibreHU de la ROM
# (2.1.2) : le pilote refuse l'etat complet d'une appli dont la structure viper::ViPERParams differe (2.1.0 et avant :
# effets coches mais non appliques) ; celle des versions 2.1.1 et 2.1.2 est la meme.
#   tools/fetch_viper.sh
#

set -e

MY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$MY_DIR/../prebuilt/viper"
VER=v2.1.2
SHA=16155702c772c4ba68b2dd0bd8c0b3cc5c0d2811b8e9bf4fca99ebd1343342f3
URL="https://github.com/likelikeslike/ViPERFX_RE/releases/download/$VER/ViPER4Android-RE-$VER.zip"
LIBS="libv4a_re_armeabi-v7a.so libv4a_re_arm64-v8a.so"

if [ "$(cat "$OUT/version" 2>/dev/null)" = "$VER" ] && (cd "$OUT" && sha256sum -c --quiet SHA256SUMS 2>/dev/null); then
    echo "prebuilt/viper : ViPERFX_RE $VER deja present"
    exit 0
fi

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
curl -fsSL --retry 3 -o "$T/module.zip" "$URL"
echo "$SHA  $T/module.zip" | sha256sum -c -
unzip -q -o "$T/module.zip" LICENSE 'common/files/*' -d "$T/mod"

rm -rf "$OUT"
mkdir -p "$OUT"
for l in $LIBS; do cp "$T/mod/common/files/$l" "$OUT/"; done
cp "$T/mod/LICENSE" "$OUT/"
echo "$VER" > "$OUT/version"
printf 'ViPERFX_RE %s (GPL-2.0)\nSources : https://github.com/likelikeslike/ViPERFX_RE/tree/%s\nModule : %s\n' "$VER" "$VER" "$URL" > "$OUT/SOURCE"
(cd "$OUT" && sha256sum $LIBS > SHA256SUMS)
echo "prebuilt/viper : ViPERFX_RE $VER"
cat "$OUT/SHA256SUMS"

#!/bin/bash
#
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Bibliotheque ECNR WebRTC de LibreHU (annulation d'echo et reduction de bruit des appels Bluetooth) dans
# prebuilt/ecnr/ : libEcnrForCustomer_armeabi-v7a.so, libEcnrForCustomer_arm64-v8a.so, version, NOTICE, SHA256SUMS,
# depuis la release ecnr-webrtc de LibreHU-flashablesZips (construite et testee par sa CI depuis native/ecnr-webrtc).
# Prise par tools/make_flashable_zip.py (dossier ecnr/ du zip) : le zip TWRP la met a la place de la bibliotheque ECNR
# tierce de Jancar (uVoice) a cote de libecnrhelper.so, le point d'accroche du HAL audio (tools/flashable/update-binary.sh).
# Ces fichiers ne sont pas versionnes (.gitignore). Sortie 3 si la release n'existe pas encore (la ROM se construit
# alors sans elle).
#   tools/fetch_ecnr.sh
#
set -e
MY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$MY_DIR/../prebuilt/ecnr"
BASE="https://github.com/LibreHU/LibreHU-flashablesZips/releases/download/ecnr-webrtc"
FILES="libEcnrForCustomer_armeabi-v7a.so libEcnrForCustomer_arm64-v8a.so version NOTICE"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
curl -fsSL --retry 4 --retry-delay 20 --retry-all-errors -o "$T/SHA256SUMS" "$BASE/SHA256SUMS" || {
    echo "release ecnr-webrtc introuvable" >&2
    exit 3
}
for f in $FILES; do
    curl -fsSL --retry 4 --retry-delay 20 --retry-all-errors -o "$T/$f" "$BASE/$f"
done
(cd "$T" && sha256sum -c --quiet SHA256SUMS)
for f in libEcnrForCustomer_armeabi-v7a.so libEcnrForCustomer_arm64-v8a.so; do
    [ "$(head -c 4 "$T/$f" | od -An -c | tr -d ' ')" = '177ELF' ] || { echo "$f : pas un ELF" >&2; exit 1; }
    grep -q "LibreHU WebRTC ECNR" "$T/$f" || { echo "$f : pas la bibliotheque LibreHU" >&2; exit 1; }
done
rm -rf "$OUT"
mkdir -p "$OUT"
cp "$T"/* "$OUT/"
echo "prebuilt/ecnr : ECNR WebRTC $(cat "$OUT/version")"
sha256sum "$OUT"/*.so

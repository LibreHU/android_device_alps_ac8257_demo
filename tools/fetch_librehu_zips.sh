#!/bin/bash
#
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Zips TWRP de LibreHU embarques dans l'image TWRP (recovery/root/system/etc/librehu, ajoutes au ramdisk par
# tools/ujc201_postprocess.py --overlay recovery/root) : librehu_boot32_twrp.zip (partition boot 10 -> 32 Mio, pour
# les noyaux 32 Mio d'Android 10 et plus) et librehu_boot32_restore_twrp.zip (retour a 10 Mio), de la release
# latest-rc-4.19.325 du depot du noyau (compiles et testes par sa CI : gpt32, coupures de courant simulees).
# Menu Advanced de TWRP (tools/ujc201_theme.py) : flashes par la page de confirmation, comme un zip de la memoire.
# Empreintes verifiees (celles que GitHub donne pour les fichiers de la release). Non versionnes (.gitignore).
#   tools/fetch_librehu_zips.sh
#

set -e
MY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$MY_DIR/../recovery/root/system/etc/librehu"
REPO=LibreHU/android_kernel_autochips_ac8257_4.9
TAG=latest-rc-4.19.325
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# API de GitHub avec le jeton de la CI quand il y en a un (GH_TOKEN / GITHUB_TOKEN) : sans jeton, 60 requetes par heure
# et par adresse IP, partagees entre les runners (403 sinon)
TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
curl -fsSL --retry 4 --retry-delay 20 --retry-all-errors ${TOKEN:+-H "Authorization: Bearer $TOKEN"} \
    -o "$T/release.json" "https://api.github.com/repos/$REPO/releases/tags/$TAG"
python3 - "$T" <<'PY'
import json, sys
t = sys.argv[1]
assets = {a["name"]: a for a in json.load(open(f"{t}/release.json"))["assets"]}
with open(f"{t}/assets", "w") as f:
    for n in ("librehu_boot32_twrp.zip", "librehu_boot32_restore_twrp.zip"):
        a = assets.get(n) or sys.exit(f"{n} missing from the release")
        d = a.get("digest") or ""
        f.write(f"{n} {a['browser_download_url']} {d[len('sha256:'):] if d.startswith('sha256:') else d}\n")
PY
mkdir -p "$OUT"
while read -r NAME URL DIGEST; do
    curl -fsSL --retry 4 --retry-delay 20 --retry-all-errors -o "$T/$NAME" "$URL"
    SUM=$(sha256sum "$T/$NAME" | cut -d' ' -f1)
    [ -z "$DIGEST" ] || [ "$DIGEST" = "$SUM" ] || { echo "$NAME: checksum different from the release" >&2; exit 1; }
    unzip -tq "$T/$NAME" >/dev/null || { echo "$NAME: damaged zip" >&2; exit 1; }
    cp "$T/$NAME" "$OUT/$NAME"
    echo "$SUM  $NAME"
done < "$T/assets"

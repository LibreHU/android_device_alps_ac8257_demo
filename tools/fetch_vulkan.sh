#!/bin/bash
#
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Paquet Vulkan de LibreHU (espace utilisateur PowerVR DDK 1.11, zip TWRP librehu_gpu_ddk111_twrp.zip) dans
# prebuilt/gpu/, depuis la release latest-rc-4.19.325-vulkan du depot du noyau (construit et teste par sa CI :
# tools/gpu/make_vulkan_package.py, tools/gpu/test_twrp_zips.sh). Pris par tools/make_flashable_zip.py (dossier gpu/
# du zip) : le zip de la ROM lance son installateur a la fin (tools/flashable/update-binary.sh). Le paquet n'ecrase
# aucun fichier du vendor et n'agit que sous un noyau -vulkan (ro.boot.librehu_gpu=1.11) : avec le noyau de la ROM, il
# ne change rien ; flasher ensuite le noyau -vulkan suffit pour avoir Vulkan.
# Ces fichiers ne sont pas versionnes (.gitignore). Sortie 3 si la release ou le zip n'existe pas (la ROM se construit
# alors sans lui).
#   tools/fetch_vulkan.sh
#
set -e
MY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$MY_DIR/../prebuilt/gpu"
REPO=LibreHU/android_kernel_autochips_ac8257_4.9
TAG=latest-rc-4.19.325-vulkan
ZIP=librehu_gpu_ddk111_twrp.zip
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
curl -fsSL --retry 4 --retry-delay 20 --retry-all-errors ${TOKEN:+-H "Authorization: Bearer $TOKEN"} \
    -o "$T/release.json" "https://api.github.com/repos/$REPO/releases/tags/$TAG" || {
    echo "release $TAG introuvable" >&2
    exit 3
}
python3 - "$T" "$ZIP" <<'PY' || exit 3
import json, sys
t, zipname = sys.argv[1], sys.argv[2]
assets = {a["name"]: a for a in json.load(open(f"{t}/release.json"))["assets"]}
with open(f"{t}/assets", "w") as f:
    for n in (zipname, "release.txt"):
        a = assets.get(n)
        if a is None:
            sys.exit(f"{n} absent de la release")
        d = a.get("digest") or ""
        f.write(f"{n} {a['browser_download_url']} {d[len('sha256:'):] if d.startswith('sha256:') else d}\n")
PY
while read -r NAME URL DIGEST; do
    curl -fsSL --retry 4 --retry-delay 20 --retry-all-errors -o "$T/$NAME" "$URL"
    SUM=$(sha256sum "$T/$NAME" | cut -d' ' -f1)
    [ -z "$DIGEST" ] || [ "$DIGEST" = "$SUM" ] || { echo "$NAME : empreinte differente de celle de la release" >&2; exit 1; }
done < "$T/assets"

# zip TWRP du paquet : intact, installateur du paquet, manifeste et version
unzip -tq "$T/$ZIP" >/dev/null
unzip -p "$T/$ZIP" META-INF/com/google/android/update-binary | grep -q '^OUTFD=$2; ZIPFILE=$3; ZIP_ID=librehu_gpu_ddk111;' \
    || { echo "$ZIP : pas l'installateur du paquet Vulkan" >&2; exit 1; }
for f in files/MANIFEST files/version files/bound files/unit_vendor.sha256; do
    unzip -l "$T/$ZIP" "$f" >/dev/null || { echo "$ZIP : $f manquant" >&2; exit 1; }
done
rm -rf "$OUT"
mkdir -p "$OUT"
cp "$T/$ZIP" "$T/release.txt" "$OUT/"
unzip -p "$T/$ZIP" files/version > "$OUT/version"
echo "prebuilt/gpu : paquet Vulkan $(cat "$OUT/version") ($(sed -n 's/^version=//p' "$OUT/release.txt"))"
sha256sum "$OUT/$ZIP"

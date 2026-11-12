#!/bin/bash
#
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Corrige les sources LineageOS 16.0 la ou elles empechent de demarrer sur le vendor stock de l'UJC201. A lancer depuis
# la racine des sources (~/android/lineage), apres chaque repo sync : repo sync remet les fichiers d'origine.
# Sans argument : corrige ; --check : dit seulement s'il reste quelque chose a corriger (code 1 si oui).
#
# 1. device/lineage/sepolicy/common/private/genfs_contexts : "genfscon fuseblk / u:object_r:vfat:s0".
#    La politique vendor stock de Jancar (vendor_sepolicy.cil, ligne 1) etiquette deja fuseblk en sdcardfs. Au
#    demarrage, l'init d'Android 9 compile la politique system + vendor avec secilc, qui refuse deux genfscon
#    differents pour le meme systeme de fichiers et le meme chemin ("Found conflicting genfscon rules",
#    libsepol/cil/src/cil_post.c, __cil_post_process_context_rules) ; l'init ne charge alors aucune politique
#    ("Unable to load SELinux policy", system/core/init/selinux.cpp) et son LOG(FATAL) redemarre en bootloader
#    (system/core/init/log.cpp, InitAborter) : menu de demarrage, puis fastboot (premier essai du build de la CI,
#    12/11/2026). La ligne LineageOS est retiree : fuseblk garde l'etiquette du vendor, comme sous le stock.
#    Verifie hors de l'unite : secilc sur le plat_sepolicy.cil du build + mapping 28.0 + plat_pub_versioned.cil et
#    vendor_sepolicy.cil du vendor stock : echec avec la ligne, compile sans.

set -e
TOP=${ANDROID_BUILD_TOP:-$PWD}
GENFS=$TOP/device/lineage/sepolicy/common/private/genfs_contexts
CHECK=0
[ "$1" = "--check" ] && CHECK=1

[ -f "$GENFS" ] || { echo "patch_lineage_sources: $GENFS introuvable (lancer depuis la racine des sources)" >&2; exit 2; }

if grep -q '^genfscon fuseblk ' "$GENFS"; then
    if [ $CHECK = 1 ]; then
        echo "patch_lineage_sources: $GENFS etiquette encore fuseblk (conflit avec le vendor Jancar)"
        exit 1
    fi
    sed -i '/^genfscon fuseblk /d' "$GENFS"
    echo "patch_lineage_sources: genfscon fuseblk retire de device/lineage/sepolicy/common/private/genfs_contexts"
else
    echo "patch_lineage_sources: device/lineage/sepolicy deja corrige"
fi

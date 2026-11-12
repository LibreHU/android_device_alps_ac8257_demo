#!/bin/bash
#
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Corrige les sources LineageOS 16.0 la ou elles empechent de demarrer sur le vendor stock de l'UJC201. A lancer depuis
# la racine des sources (~/android/lineage), apres chaque repo sync : repo sync remet les fichiers d'origine.
# Sans argument : corrige ; --check : dit seulement s'il reste quelque chose a corriger (code 1 si oui).
# Codes : 0 = sources corrigees, 1 = reste a corriger (--check), 2 = fichier introuvable, 3 = sources inattendues.
#
# 1. system/core/fs_mgr/fs_mgr.cpp, fs_mgr_is_device_unlocked() : fs_mgr ne croit l'unite deverrouillee que si
#    androidboot.verifiedbootstate vaut "orange". Le LK de Jancar annonce "green" meme deverrouille (getprop de l'unite
#    sous le stock : ro.boot.verifiedbootstate=green, ro.boot.vbmeta.device_state=unlocked, rapports LibreHU Helper du
#    04/11 et du 10/11/2026) ; avec le drapeau VERIFICATION_DISABLED de vbmeta, il ne passe meme aucun
#    androidboot.vbmeta.* : libavb saute alors avb_append_options (avb_slot_verify.c) ; ligne de commande du noyau de
#    l'essai du 12/11 : verifiedbootstate=green, root=PARTUUID=... de libavb, rien d'autre. Or fastboot
#    --disable-verity / --disable-verification modifie les drapeaux de l'en-tete de vbmeta, que couvre son empreinte
#    (external/avb/libavb/avb_vbmeta_image.c) : libavb rend ERROR_VERIFICATION, que fs_mgr refuse sur une unite qu'il
#    croit verrouillee. Console de l'essai du 12/11 (console-ramoops) :
#      init: [libfs_mgr]ERROR_VERIFICATION isn't allowed when the device is LOCKED
#      init: Failed to setup verity for '/vendor'
#      init: Failed to mount required partitions early ...
#      init: Reboot start, reason: reboot, rebootTarget: bootloader
#    La fonction considere desormais l'unite deverrouillee si vbmeta.device_state vaut "unlocked" ou est absent ; seul
#    un "locked" explicite du LK garde fs_mgr strict. Un vbmeta qui ne se verifie pas n'arrive jusqu'a l'init que si
#    le LK l'a accepte : le refuser n'apporte rien. Le system stock de Jancar demarre avec ce meme vbmeta modifie.
#
# 2. device/lineage/sepolicy/common/private/genfs_contexts : "genfscon fuseblk / u:object_r:vfat:s0".
#    La politique vendor stock de Jancar (vendor_sepolicy.cil, ligne 1) etiquette deja fuseblk en sdcardfs. Au
#    demarrage, l'init d'Android 9 compile la politique system + vendor avec secilc, qui refuse deux genfscon
#    differents pour le meme systeme de fichiers et le meme chemin ("Found conflicting genfscon rules",
#    libsepol/cil/src/cil_post.c, __cil_post_process_context_rules) ; l'init ne charge alors aucune politique
#    ("Unable to load SELinux policy", system/core/init/selinux.cpp) et son LOG(FATAL) redemarre en bootloader
#    (system/core/init/log.cpp, InitAborter). La ligne LineageOS est retiree : fuseblk garde l'etiquette du vendor,
#    comme sous le stock. Verifie hors de l'unite : secilc sur le plat_sepolicy.cil du build + mapping 28.0 +
#    plat_pub_versioned.cil et vendor_sepolicy.cil du vendor stock : echec avec la ligne, compile sans.

set -e
TOP=${ANDROID_BUILD_TOP:-$PWD}
FSMGR=$TOP/system/core/fs_mgr/fs_mgr.cpp
GENFS=$TOP/device/lineage/sepolicy/common/private/genfs_contexts
CHECK=0
[ "$1" = "--check" ] && CHECK=1
TODO=0

for f in "$FSMGR" "$GENFS"; do
    [ -f "$f" ] || { echo "patch_lineage_sources: $f introuvable (lancer depuis la racine des sources)" >&2; exit 2; }
done

# 1. fs_mgr : vbmeta.device_state (librehu_device_state = premiere version du 12/11, insuffisante : retiree)
if grep -q 'librehu_vbmeta_state' "$FSMGR"; then
    echo "patch_lineage_sources: system/core/fs_mgr deja corrige"
elif [ $CHECK = 1 ]; then
    echo "patch_lineage_sources: $FSMGR croit l'unite verrouillee (LK Jancar : verifiedbootstate=green)"
    TODO=1
else
    if grep -q 'librehu_device_state' "$FSMGR"; then
        sed -i '/^    \/\/ LibreHU (UJC201) : le LK de Jancar annonce androidboot.verifiedbootstate=green meme deverrouille, avec$/,/^    }$/d' "$FSMGR"
        grep -q 'librehu_device_state' "$FSMGR" && { echo "patch_lineage_sources: ancienne correction de $FSMGR non retiree" >&2; exit 3; }
    fi
    if [ "$(grep -c '^bool fs_mgr_is_device_unlocked() {$' "$FSMGR")" != 1 ]; then
        echo "patch_lineage_sources: fs_mgr_is_device_unlocked() introuvable dans $FSMGR (sources changees ?)" >&2
        exit 3
    fi
    sed -i '/^bool fs_mgr_is_device_unlocked() {$/r /dev/stdin' "$FSMGR" <<'EOF'
    // LibreHU (UJC201) : le LK de Jancar annonce androidboot.verifiedbootstate=green meme deverrouille et, avec le
    // drapeau VERIFICATION_DISABLED de vbmeta, ne passe aucun androidboot.vbmeta.*. Seul un vbmeta.device_state=locked
    // explicite garde fs_mgr strict : un vbmeta qui ne se verifie pas n'arrive ici que si le LK l'a accepte, et le
    // refuser empeche vendor de se monter (l'init redemarre alors en bootloader).
    std::string librehu_vbmeta_state;
    if (!fs_mgr_get_boot_config("vbmeta.device_state", &librehu_vbmeta_state) ||
        librehu_vbmeta_state == "unlocked") {
        return true;
    }
EOF
    grep -q 'librehu_vbmeta_state' "$FSMGR" || { echo "patch_lineage_sources: correction de $FSMGR impossible" >&2; exit 3; }
    echo "patch_lineage_sources: system/core/fs_mgr/fs_mgr.cpp : unite deverrouillee sauf vbmeta.device_state=locked"
fi

# 2. sepolicy : genfscon fuseblk
if ! grep -q '^genfscon fuseblk ' "$GENFS"; then
    echo "patch_lineage_sources: device/lineage/sepolicy deja corrige"
elif [ $CHECK = 1 ]; then
    echo "patch_lineage_sources: $GENFS etiquette encore fuseblk (conflit avec le vendor Jancar)"
    TODO=1
else
    sed -i '/^genfscon fuseblk /d' "$GENFS"
    echo "patch_lineage_sources: genfscon fuseblk retire de device/lineage/sepolicy/common/private/genfs_contexts"
fi

exit $TODO

#!/bin/bash
#
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Corrige les sources LineageOS 17.1 la ou elles empechent de demarrer sur le vendor stock de l'UJC201 (Android 9).
# A lancer depuis la racine des sources (~/android/lineage), apres chaque repo sync : repo sync remet les fichiers
# d'origine. Sans argument : corrige ; --check : dit seulement s'il reste quelque chose a corriger (code 1 si oui).
# Codes : 0 = sources corrigees, 1 = reste a corriger (--check), 2 = fichier introuvable, 3 = sources inattendues.
# Version de la branche lineage-17.1 : la branche lineage-16.0 a la sienne (correctifs 2 et 5 differents).
# Branche lineage-19.1 (Android 12L) : portage depuis lineage-17.1 (19/11/2026), correctifs encore ceux d'Android
# 10. LIBREHU_PATCH_SOFT=1 (CI) : un correctif qui ne s'applique plus (ou dont le fichier a change de place) est un
# avertissement, le build continue ; --check rend toujours 1 tant qu'il en manque un.
#
# 1. system/core/fs_mgr : fs_mgr ne croit l'unite deverrouillee que si androidboot.verifiedbootstate vaut "orange".
#    Le LK de Jancar annonce "green" meme deverrouille (getprop de l'unite sous le stock :
#    ro.boot.verifiedbootstate=green, ro.boot.vbmeta.device_state=unlocked, rapports LibreHU Helper du 04/11 et du
#    10/11/2026) ; avec le drapeau VERIFICATION_DISABLED de vbmeta, il ne passe meme aucun androidboot.vbmeta.* :
#    libavb saute alors avb_append_options (avb_slot_verify.c) ; ligne de commande du noyau de l'essai du 12/11 :
#    verifiedbootstate=green, root=PARTUUID=... de libavb, rien d'autre. Or fastboot --disable-verity /
#    --disable-verification modifie les drapeaux de l'en-tete de vbmeta, que couvre son empreinte
#    (external/avb/libavb/avb_vbmeta_image.c) : libavb rend ERROR_VERIFICATION, que fs_mgr refuse sur une unite qu'il
#    croit verrouillee ; vendor ne se monte pas et l'init redemarre en bootloader (console de l'essai du 12/11 sous
#    LineageOS 16.0 : « ERROR_VERIFICATION isn't allowed when the device is LOCKED »).
#    Android 10 a deux copies de ce test : fs_mgr_is_device_unlocked() (fs_mgr/fs_mgr.cpp) et IsDeviceUnlocked()
#    (fs_mgr/libfs_avb/util.cpp, appele par AvbHandle::Open pour le vbmeta du montage de vendor par la premiere
#    etape de l'init). Les deux considerent desormais l'unite deverrouillee si vbmeta.device_state vaut "unlocked" ou
#    est absent ; seul un "locked" explicite du LK les garde stricts. Un vbmeta qui ne se verifie pas n'arrive
#    jusqu'a l'init que si le LK l'a accepte : le refuser n'apporte rien.
#
# 2. fuseblk : la politique vendor stock de Jancar (vendor_sepolicy.cil, ligne 1) etiquette deja fuseblk en sdcardfs ;
#    secilc refuse deux genfscon differents pour le meme systeme de fichiers, l'init ne charge alors aucune politique
#    et redemarre en bootloader (essai du 12/11 sous LineageOS 16.0). LineageOS 17.1 prevoit le cas :
#    TARGET_HAS_FUSEBLK_SEPOLICY_ON_VENDOR := true (BoardConfig.mk) retire sa ligne
#    (device/lineage/sepolicy/common/sepolicy.mk, board_excludes_fuseblk_sepolicy dans genfs_contexts). Ce script
#    verifie seulement que genfs_contexts a toujours cette condition.
#
# 3. frameworks/native (lineage-patches/frameworks_native) : la dalle est en portrait (720 x 1280, fb0 « U:720x1280p »)
#    et montee en paysage ; le stock la tourne avec persist.sf.hwrotation=90, propriete du SurfaceFlinger de MediaTek
#    que celui d'AOSP ignore (il ne lit que ro.surface_flinger.primary_display_orientation, sinon le configstore, a 0
#    dans le vendor stock). SurfaceFlinger prend persist.librehu.display_rotation (sinon ro.librehu.display_rotation,
#    90 dans device.mk) ; l'InputReader (TouchInputMapper::findViewport) tourne le tactile interne d'autant.
#
# 4. frameworks/base (lineage-patches/frameworks_base) : retroeclairage Jancar inverse (lcd-backlight 0 = maximum,
#    179 = minimum ; le system stock compense, TWRP aussi dans touchfix) : LightsService convertit la luminosite
#    d'Android quand ro.librehu.backlight_inverted vaut true (device.mk), avant ses deux chemins (SurfaceControl et
#    HAL lights).
#
# 5. Musique Bluetooth (focus audio de l'A2DP sink) : rien a corriger en 17.1, c'est le reglage
#    a2dp_sink_automatically_request_audio_focus d'Android 10 (overlay/packages/apps/Bluetooth).
#
# 6. vendor/jancar/ac8257_demo : autochips.jar est dans PRODUCT_BOOT_JARS (device.mk). Android 10 construit l'image de
#    demarrage (boot.art) dans Soong (build/soong/java/dexpreopt_bootjars.go), qui ne trouve que des modules Soong :
#    le module Make du depot vendor (BUILD_PREBUILT, branche lineage-16.0) donne « failed to find dex jar path for
#    module "autochips" ». La branche lineage-17.1 du depot vendor a deja ce module (Android.bp, dex_import, comme
#    vendor/lineage/build/tools/extract_utils.sh de LineageOS 17.1 pour un jar) : rien a faire. Avec une copie de sa
#    branche lineage-16.0, le script ecrit cet Android.bp et retire le module Make du meme nom d'Android.mk (un nom
#    defini deux fois arrete le build : core/base_rules.mk, « already defined by ») ; seule la copie locale change.
#
# 7. frameworks/av (lineage-patches/frameworks_av) : sans audio_policy_engine_configuration.xml dans /vendor/etc (seul
#    chemin lu par Android 10, EngineConfig.h DEFAULT_PATH ; le vendor Android 9 n'en a pas), le moteur de politique
#    audio prend ses strategies par defaut et les courbes de volume de audio_policy_configuration.xml du vendor, qui
#    n'en a pas pour tous les flux (pas AUDIO_STREAM_ACCESSIBILITY). loadProductStrategies() prenait alors end() pour
#    le groupe absent (ALOG_ASSERT retire en build user) : audioserver plantait a chaque demarrage (SIGSEGV dans
#    EngineBase::loadAudioPolicyEngineConfig(), 47 tombstones du premier essai du 15/11) et system_server attendait
#    media.audio_policy sans fin (pas de boot_completed). Comme Android 11 : un groupe absent prend les courbes
#    d'AUDIO_STREAM_MUSIC (d'AUDIO_STREAM_PATCH pour les flux internes).
#
# 8. frameworks/base (lineage-patches/frameworks_base, 0002) : SystemUI dans /system/priv-app au lieu de
#    /system/product. Android 10 parcourt /vendor/app avant /product (PackageManagerService) : l'ivi-systemui du vendor
#    Jancar, lui aussi com.android.systemui (Android 9, android.uid.system), etait installe a la place de celui de
#    LineageOS (« Failed to scan /system/product/priv-app/SystemUI: ... already installed »). Comme en 16.0, celui du
#    systeme passe avant (l'ivi-systemui est alors ignore). Sa liste de permissions privilegiees le suit.
#
# 9. system/vold (lineage-patches/system_vold) : cles USB d'un Mac, comme en 16.0. vold ne fait un volume public que
#    des partitions FAT / NTFS / exFAT / Linux, et le blkid d'e2fsprogs ne connait pas APFS. Partitions MBR 0xaf et
#    GPT Apple HFS+ / APFS acceptees, APFS reconnu a sa signature « NXSB », hfs / hfsplus montes au nom de media_rw,
#    apfs en lecture seule. Monte seulement si le noyau connait le systeme de fichiers (/proc/filesystems).
#
# 10. frameworks/av (lineage-patches/frameworks_av, 0002) : cameraserver d'Android 10 prend la liste des fournisseurs
#    de camera dans le manifeste VINTF (CameraProviderManager::listServices, listManifestByInterface) et attend chacun
#    dans getService(). Le manifeste du vendor Jancar declare ICameraProvider/internal/0, que personne ne sert (son
#    camhal3lite enregistre internal/1) : cameraserver attendait sans fin (« Waited one second for ...internal/0 »,
#    pile CameraProviderManager::initialize -> getService du rapport du 21/11), le service camera n'etait jamais
#    publie : appli Camera qui plante, pas de camera de recul ni d'AV IN. Android 9 n'essayait que legacy/0 et
#    external/0 sans les attendre. Ne sont plus attendus que les fournisseurs du manifeste deja enregistres ; un
#    fournisseur enregistre plus tard arrive par la notification d'enregistrement (onRegistration).
#
# 11. frameworks/av (lineage-patches/frameworks_av, 0003, apres 0002) : cameras masquees et orientation forcee. Le HAL
#    camera Jancar declare des identifiants sans camera derriere (2, 10, 11, 12 sur l'unite du 21/11 : ouverture en
#    -38, « initMipi: Invalid device ID ») et dit « arriere » de toutes sauf une : l'appli Camera (premiere arriere,
#    premiere avant) ouvrait la 2, morte. CameraProviderManager lit persist.librehu.camera.hidden (« 2,10,11,12 »)
#    et persist.librehu.camera.facing (« 3:back,0:front,8:external ») ; LibreHU-service les pose et redemarre
#    cameraserver. Sans ces proprietes, rien ne change. Une camera masquee branchee a chaud (USB) n'est plus
#    annoncee avec un identifiant vide.
#
# 12. frameworks/base (lineage-patches/frameworks_base, 0003) : SystemUI plantait (NullPointerException dans
#    PhoneStateMonitor.isLauncherShowing, journaux de la 17.1 du 23/11/2026) a chaque tache passee au premier plan
#    sans activite au sommet (topActivity null) ; bug d'AOSP 10, encore dans Android 11. Une telle tache n'est pas
#    l'ecran d'accueil.
#
# 13. frameworks/opt/net/wifi (lineage-patches/frameworks_opt_net_wifi) : pas de scan Wi-Fi interne d'Android tant
#    qu'un groupe Wi-Fi Direct est monte (Android Auto / CarPlay sans fil), comme AOSP le fait deja pour Miracast.
#    La puce MediaTek n'a qu'une radio : chaque scan la sort du canal du groupe ; Wi-Fi de l'autoradio non connecte,
#    le scan periodique toutes les 160 s coupait Android Auto sans fil a chaque fois (journaux du 24/11/2026 : lien
#    perdu 15 s apres chaque scan). Les scans demandes par les applis passent toujours.

set -e
TOP=${ANDROID_BUILD_TOP:-$PWD}
PATCHES=$(cd "$(dirname "$0")" && pwd)/lineage-patches
FSMGR=$TOP/system/core/fs_mgr/fs_mgr.cpp
FSAVB=$TOP/system/core/fs_mgr/libfs_avb/util.cpp
GENFS=$TOP/device/lineage/sepolicy/common/private/genfs_contexts
VENDOR=$TOP/vendor/jancar/ac8257_demo
CHECK=0
SOFT=${LIBREHU_PATCH_SOFT:-0}
# fail <code> <message> : arret (code), ou avertissement en mode souple (LIBREHU_PATCH_SOFT=1)
fail() {
    echo "patch_lineage_sources: $2" >&2
    if [ "$SOFT" = 1 ]; then echo "::warning::patch_lineage_sources: $2"; TODO=1; return 0; fi
    exit "$1"
}
[ "$1" = "--check" ] && CHECK=1
TODO=0

for f in "$FSMGR" "$FSAVB" "$GENFS" "$VENDOR/Android.mk"; do
    [ -f "$f" ] || fail 2 "$f introuvable (lancer depuis la racine des sources)"
done

# 1. fs_mgr : vbmeta.device_state, dans les deux copies du test (fichier, premiere ligne de la fonction)
patch_unlock() {
    local file=$1 func=$2 rel=${1#$TOP/}
    [ -f "$file" ] || { fail 2 "$rel introuvable"; return 0; }
    if grep -q 'librehu_vbmeta_state' "$file"; then
        echo "patch_lineage_sources: $rel deja corrige"
        return
    fi
    if [ $CHECK = 1 ]; then
        echo "patch_lineage_sources: $rel croit l'unite verrouillee (LK Jancar : verifiedbootstate=green)"
        TODO=1
        return
    fi
    if [ "$(grep -c "^$func\$" "$file")" != 1 ]; then
        fail 3 "« $func » introuvable dans $rel (sources changees ?)"
        return 0
    fi
    sed -i "/^$func\$/r /dev/stdin" "$file" <<'EOF'
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
    grep -q 'librehu_vbmeta_state' "$file" || { fail 3 "correction de $rel impossible"; return 0; }
    echo "patch_lineage_sources: $rel : unite deverrouillee sauf vbmeta.device_state=locked"
}
patch_unlock "$FSMGR" 'bool fs_mgr_is_device_unlocked() {'
patch_unlock "$FSAVB" 'bool IsDeviceUnlocked() {'

# 2. sepolicy : la ligne fuseblk de LineageOS doit rester conditionnelle (TARGET_HAS_FUSEBLK_SEPOLICY_ON_VENDOR)
if [ ! -f "$GENFS" ]; then
    : # deja signale
elif grep -q '^ifelse(board_excludes_fuseblk_sepolicy' "$GENFS"; then
    echo "patch_lineage_sources: device/lineage/sepolicy : fuseblk laisse au vendor (TARGET_HAS_FUSEBLK_SEPOLICY_ON_VENDOR)"
elif grep -q '^genfscon fuseblk ' "$GENFS"; then
    fail 3 "$GENFS etiquette fuseblk sans condition (sources changees ?) : conflit avec le vendor Jancar"
fi

# 3, 4. frameworks : fichiers de lineage-patches/ (projet, fichier temoin, marqueur, patch, objet)
apply_patch() {
    local proj=$1 witness=$2 mark=$3 p=$4 what=$5
    [ -f "$TOP/$proj/$witness" ] || { fail 2 "$TOP/$proj/$witness introuvable ($what)"; return 0; }
    if grep -q "$mark" "$TOP/$proj/$witness"; then
        echo "patch_lineage_sources: $proj deja corrige ($what)"
    elif [ $CHECK = 1 ]; then
        echo "patch_lineage_sources: $proj sans correctif ($what)"
        TODO=1
    else
        patch -p1 -N -s --dry-run -d "$TOP/$proj" < "$p" >/dev/null \
            || { fail 3 "$(basename "$p") ne s'applique pas sur $proj ($what, sources d'Android 12L)"; return 0; }
        patch -p1 -N -s -d "$TOP/$proj" < "$p"
        echo "patch_lineage_sources: $proj corrige ($what)"
    fi
}
apply_patch frameworks/native services/inputflinger/InputReader.cpp librehuDisplayRotation \
    "$PATCHES/frameworks_native/0001-librehu-display-rotation.patch" "rotation de la dalle et du tactile"
apply_patch frameworks/base services/core/java/com/android/server/lights/LightsService.java librehu.backlight_inverted \
    "$PATCHES/frameworks_base/0001-librehu-backlight-inverted.patch" "retroeclairage inverse"
# 7, 8.
apply_patch frameworks/av services/audiopolicy/engine/common/src/EngineBase.cpp librehuMissingVolumeGroups \
    "$PATCHES/frameworks_av/0001-librehu-missing-volume-groups.patch" "groupes de volume absents du vendor"
apply_patch frameworks/base packages/SystemUI/Android.bp librehuSystemUiInSystem \
    "$PATCHES/frameworks_base/0002-librehu-systemui-system-priv-app.patch" "SystemUI avant l'ivi-systemui du vendor"
apply_patch system/vold model/PublicVolume.cpp librehu.mac_volumes \
    "$PATCHES/system_vold/0001-librehu-mac-volumes.patch" "cles USB d'un Mac (HFS, HFS+, APFS)"
# 10.
apply_patch frameworks/av services/camera/libcameraservice/common/CameraProviderManager.cpp \
    librehuCameraProvidersRegistered \
    "$PATCHES/frameworks_av/0002-librehu-camera-providers-registered.patch" "fournisseurs de camera du manifeste non servis"
# 11. (apres 10 : meme fichier)
apply_patch frameworks/av services/camera/libcameraservice/common/CameraProviderManager.cpp \
    librehuCameraHiddenFacing \
    "$PATCHES/frameworks_av/0003-librehu-camera-hidden-facing.patch" "cameras masquees et orientation forcee"
# 12.
apply_patch frameworks/base packages/SystemUI/src/com/android/systemui/assist/PhoneStateMonitor.java \
    librehuLauncherShowingNull \
    "$PATCHES/frameworks_base/0003-librehu-systemui-launcher-showing-null.patch" "SystemUI : tache sans activite au sommet"
# 13.
apply_patch frameworks/opt/net/wifi service/java/com/android/server/wifi/WifiConnectivityManager.java \
    librehuP2pGroupScanHold \
    "$PATCHES/frameworks_opt_net_wifi/0001-librehu-p2p-group-scan-hold.patch" "pas de scan Wi-Fi pendant un groupe Wi-Fi Direct"

# 6. autochips.jar en module Soong (copie locale du depot vendor)
VMK=$VENDOR/Android.mk
VBP=$VENDOR/Android.bp
if [ -f "$VMK" ] && grep -q '^LOCAL_MODULE := autochips$' "$VMK"; then
    if [ $CHECK = 1 ]; then
        echo "patch_lineage_sources: vendor/jancar/ac8257_demo/Android.mk definit encore autochips en module Make"
        TODO=1
    else
        # bloc « include $(CLEAR_VARS) ... include $(BUILD_PREBUILT) » qui contient LOCAL_MODULE := autochips
        awk '
            /^include \$\(CLEAR_VARS\)$/ { inblk = 1; buf = $0 "\n"; drop = 0; next }
            inblk { buf = buf $0 "\n"; if ($0 == "LOCAL_MODULE := autochips") drop = 1
                    if ($0 ~ /^include \$\(BUILD_[A-Z_]+\)$/) { if (!drop) printf "%s", buf; inblk = 0 }
                    next }
            { print }
            END { if (inblk) printf "%s", buf }' "$VMK" > "$VMK.librehu"
        mv "$VMK.librehu" "$VMK"
        grep -q '^LOCAL_MODULE := autochips$' "$VMK" && { echo "patch_lineage_sources: module Make autochips non retire" >&2; exit 3; }
        echo "patch_lineage_sources: vendor/jancar/ac8257_demo/Android.mk : module Make autochips retire"
    fi
fi
if ! grep -qs 'name: "autochips"' "$VBP"; then
    if [ $CHECK = 1 ]; then
        echo "patch_lineage_sources: vendor/jancar/ac8257_demo/Android.bp sans le module Soong autochips"
        TODO=1
    else
        if [ ! -f "$VENDOR/proprietary/framework/autochips.jar" ]; then
            fail 2 "$VENDOR/proprietary/framework/autochips.jar introuvable"
        elif [ -f "$VBP" ]; then
            fail 3 "$VBP existe deja sans autochips (depot vendor change ?)"
        else
        cat > "$VBP" <<'EOF'
// LibreHU : ecrit par device/alps/ac8257_demo/tools/patch_lineage_sources.sh (LineageOS 17.1), pas dans le depot.
// autochips.jar est dans PRODUCT_BOOT_JARS : Android 10 construit l'image de demarrage dans Soong, qui ne trouve que
// des modules Soong (le module Make du meme nom est retire d'Android.mk par le meme script).
dex_import {
	name: "autochips",
	owner: "jancar",
	jars: ["proprietary/framework/autochips.jar"],
}
EOF
        echo "patch_lineage_sources: vendor/jancar/ac8257_demo/Android.bp : autochips en dex_import"
        fi
    fi
fi

# mode souple sans --check : le build continue meme s'il manque un correctif (deja signale)
[ "$SOFT" = 1 ] && [ $CHECK = 0 ] && exit 0
exit $TODO

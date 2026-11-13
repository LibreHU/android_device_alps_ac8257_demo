#!/bin/bash
#
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Telecharge les APK des applis LibreHU integrees a la ROM (releases latest-<branche> de GitHub) dans ce dossier.
# Les APK ne sont pas versionnes dans le depot (voir .gitignore) : a relancer avant chaque build pour prendre les
# dernieres versions. Ils restent signes avec la cle commune des applis LibreHU (LOCAL_CERTIFICATE := PRESIGNED),
# l'appli OTA peut donc ensuite les mettre a jour.
# Toutes vont dans /system/priv-app : check_privapp.py verifie ensuite que privapp-permissions-librehu.xml contient
# chaque permission privilegiee qu'elles demandent (sinon LineageOS s'arrete au demarrage) et s'arrete sinon.
# Prend aussi le gestionnaire KernelSU Next (ksunext/KernelSUNext.apk, version figee).
#

set -e
cd "$(dirname "${BASH_SOURCE[0]}")"

# depot  tag  fichier de la release  nom local
APPS=(
    "LibreHU-service      latest-main             LibreHU-service-main.apk                LibreHUService.apk"
    "LibreHU-launcher-app latest-librehu-service  LibreHU-Launcher-librehu-service.apk    LibreHULauncher.apk"
    "LibreHU-OTA-app      latest-main             LibreHU-OTA-main.apk                    LibreHUOTA.apk"
    "LibreHU-viper4android-app latest-librehu-service ViPER4Android-LibreHU-librehu-service.apk LibreHUViPER.apk"
    "LibreHU-dialer-app   latest-librehu-service  LibreHU-Dialer-librehu-service.apk      LibreHUDialer.apk"
    "LibreHU-FM-app       latest-librehu-service  LibreHU-FM-librehu-service.apk          LibreHUFM.apk"
    "LibreHU-widget-app   latest-librehu-service  LibreHU-Widgets-librehu-service.apk     LibreHUWidgets.apk"
    "LibreHU-BtnRemap-app latest-librehu-service  LibreHU-BtnRemap-librehu-service.apk    LibreHUBtnRemap.apk"
    "LibreHU-EasySource-app latest-main           LibreHU-EasySource-main.apk             LibreHUEasySource.apk"
    "LibreHU-disc-app     latest-main             LibreHU-Disc-main.apk                   LibreHUDisc.apk"
    "LibreHU-open-headunit-app latest-main        OpenHeadunit-LibreHU-main.apk           LibreHUAndroidAuto.apk"
    "LibreHU-xcertplay-app latest-master          CarPlay-LibreHU-master.apk              LibreHUCarPlay.apk"
)

for line in "${APPS[@]}"; do
    read -r repo tag asset out <<< "$line"
    url="https://github.com/LibreHU/$repo/releases/download/$tag/$asset"
    echo "$out <- $url"
    curl -fL --retry 3 -o "$out.part" "$url"
    unzip -tq "$out.part" >/dev/null
    mv "$out.part" "$out"
done
sha256sum ./*.apk
python3 -I check_privapp.py .
# Bibliotheques natives : installation brute des APK aux bibliotheques compressees, 32 bits (voir native_libs.py)
python3 -I native_libs.py .

# Gestionnaire KernelSU Next (ksunext/, installe dans /data/app au premier demarrage) : version figee sur celle que
# le noyau LibreHU accepte (KernelSU Next v3.4.2, API 5, drivers/kernelsu/README.ac8257 du noyau) et verifiee par son
# empreinte (celle de la release). Son certificat est celui qu'attend le noyau (KSU_NEXT_MANAGER_SIZE 0x3e6,
# KSU_NEXT_MANAGER_HASH 79e59011... de drivers/kernelsu/Kbuild) ; un autre gestionnaire ne serait pas reconnu.
KSUN_URL=https://github.com/KernelSU-Next/KernelSU-Next/releases/download/v3.4.2/KernelSU_Next_v3.4.2_33355-release.apk
KSUN_SHA256=774a5511f7034a4930e881114e202319cbdc34c5aaaa5c7c6b6d2902364e4c58
echo "ksunext/KernelSUNext.apk <- $KSUN_URL"
curl -fL --retry 3 -o ksunext/KernelSUNext.apk.part "$KSUN_URL"
echo "$KSUN_SHA256  ksunext/KernelSUNext.apk.part" | sha256sum -c -
mv ksunext/KernelSUNext.apk.part ksunext/KernelSUNext.apk

# Applis installees dans /data/app au premier demarrage (userapps/, librehu_ksunext.sh), comme des applis ordinaires :
# elles se mettent a jour seules et l'utilisateur peut les desinstaller (elles ne reviennent pas).
#  - LibreHU Helper (diagnostics, rapports) : derniere release, signee avec la cle commune des applis LibreHU ;
#  - Aurora Store (GPL-3.0, https://gitlab.com/AuroraOSS/AuroraStore) : version figee, build de F-Droid verifie par son
#    empreinte.
mkdir -p userapps
HELPER_URL=https://github.com/LibreHU/LibreHU-helper-app/releases/download/latest-main/LibreHU-Helper-main.apk
echo "userapps/LibreHUHelper.apk <- $HELPER_URL"
curl -fL --retry 3 -o userapps/LibreHUHelper.apk.part "$HELPER_URL"
unzip -tq userapps/LibreHUHelper.apk.part >/dev/null
mv userapps/LibreHUHelper.apk.part userapps/LibreHUHelper.apk
AURORA_URL=https://f-droid.org/repo/com.aurora.store_76.apk
AURORA_SHA256=fd9c75d90d0f4a7c132b9b4a5a2cf1992a45e03b8d8ff988b7dcfbc0db2c4d11
echo "userapps/AuroraStore.apk <- $AURORA_URL (4.8.4)"
curl -fL --retry 3 -o userapps/AuroraStore.apk.part "$AURORA_URL"
echo "$AURORA_SHA256  userapps/AuroraStore.apk.part" | sha256sum -c -
mv userapps/AuroraStore.apk.part userapps/AuroraStore.apk

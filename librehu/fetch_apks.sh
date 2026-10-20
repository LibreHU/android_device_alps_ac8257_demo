#!/bin/bash
#
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: Apache-2.0
#
# Telecharge les APK des applis LibreHU integrees a la ROM (releases latest-<branche> de GitHub) dans ce dossier.
# Les APK ne sont pas versionnes dans le depot (voir .gitignore) : a relancer avant chaque build pour prendre les
# dernieres versions. Ils restent signes avec la cle commune des applis LibreHU (LOCAL_CERTIFICATE := PRESIGNED),
# l'appli OTA peut donc ensuite les mettre a jour.
#

set -e
cd "$(dirname "${BASH_SOURCE[0]}")"

# depot  tag  fichier de la release  nom local
APPS=(
    "LibreHU-service      latest-main             LibreHU-service-main.apk                LibreHUService.apk"
    "LibreHU-launcher-app latest-librehu-service  LibreHU-Launcher-librehu-service.apk    LibreHULauncher.apk"
    "LibreHU-OTA-app      latest-main             LibreHU-OTA-main.apk                    LibreHUOTA.apk"
    "LibreHU-viper4android-app latest-librehu-service ViPER4Android-LibreHU-librehu-service.apk LibreHUViPER.apk"
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

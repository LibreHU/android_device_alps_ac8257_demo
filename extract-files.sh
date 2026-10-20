#!/bin/bash
#
# Copyright (C) 2026 The LineageOS Project
# Copyright (C) 2026 LibreHU
#
# SPDX-License-Identifier: Apache-2.0
#
# Reprend les fichiers de proprietary-files.txt (cote /system) dans vendor/jancar/ac8257_demo.
# Source : "adb" (unite sous ROM stock, adb root) ou un dossier contenant le /system stock extrait.
#   ./extract-files.sh            # depuis l'unite
#   ./extract-files.sh ~/stock    # depuis ~/stock/system/...
# La partition vendor entiere se lit avec tools/get_vendor_img.sh.
#

set -e

DEVICE=ac8257_demo
VENDOR=jancar

# Load extract_utils and do some sanity checks
MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$MY_DIR" ]]; then MY_DIR="$PWD"; fi

LINEAGE_ROOT="$MY_DIR"/../../..

HELPER="$LINEAGE_ROOT"/vendor/lineage/build/tools/extract_utils.sh
if [ ! -f "$HELPER" ]; then
    echo "Unable to find helper script at $HELPER"
    exit 1
fi
. "$HELPER"

# Default to sanitizing the vendor folder before extraction
CLEAN_VENDOR=true

SECTION=
KANG=

while [ "$1" != "" ]; do
    case $1 in
        -n | --no-cleanup )     CLEAN_VENDOR=false
                                ;;
        -k | --kang )           KANG="--kang"
                                ;;
        -s | --section )        shift
                                SECTION=$1
                                CLEAN_VENDOR=false
                                ;;
        * )                     SRC=$1
                                ;;
    esac
    shift
done

if [ -z "$SRC" ]; then
    SRC=adb
fi

# Initialize the helper (le nettoyage ne vide que vendor/jancar/ac8257_demo/proprietary, pas vendor.img)
setup_vendor "$DEVICE" "$VENDOR" "$LINEAGE_ROOT" false "$CLEAN_VENDOR"

extract "$MY_DIR"/proprietary-files.txt "$SRC" "$KANG" --section "$SECTION"

"$MY_DIR"/setup-makefiles.sh

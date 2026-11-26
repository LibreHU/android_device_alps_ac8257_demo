#!/bin/bash
#
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Test de l'etape Vulkan du zip de la ROM (vulkan_install de tools/flashable/update-binary.sh) hors autoradio, avec le
# vrai paquet (prebuilt/gpu/librehu_gpu_ddk111_twrp.zip, tools/fetch_vulkan.sh) sur un faux vendor stock, comme
# tools/gpu/test_twrp_zips.sh du depot du noyau : les fichiers de reference du vendor sont des temoins dont les
# empreintes remplacent celles du vendor stock dans une copie du paquet. Cas : installation (fichiers du manifeste en
# place, fichiers stock intacts), reinstallation, LibreHU/no-vulkan-package (rien d'ecrit), paquet abime (refus, rien
# d'ecrit), refus du paquet lui-meme (pilote Vulkan deja la : rien d'ecrit, l'etape rend une erreur que la ROM ignore).
#   tools/ci/test_vulkan_step.sh [paquet]     (defaut : prebuilt/gpu/librehu_gpu_ddk111_twrp.zip)
set -e
MY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG=$(realpath "${1:-$MY_DIR/../../prebuilt/gpu/librehu_gpu_ddk111_twrp.zip}")
UB=$MY_DIR/../flashable/update-binary.sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
V=$T/vendor
mkdir -p $T/bin $V $T/system/system/etc $T/sdcard/LibreHU $T/dt/firmware/android/fstab/vendor $T/tmp $T/pkg $T/rom/gpu $T/rom/info
printf '#!/bin/sh\n[ "$1" = ro.product.device ] && echo ac8257_demo\n' > $T/bin/getprop; chmod +x $T/bin/getprop
echo 'ro.board.platform=ac8257' > $V/build.prop
echo 'ro.build.version.release=10' > $T/system/system/build.prop
printf 'wait' > $T/dt/firmware/android/fstab/vendor/fsmgr_flags
# copie du paquet avec les empreintes des temoins du faux vendor
cd $T/pkg && unzip -q "$PKG"
while read -r src dst; do mkdir -p "$(dirname "$V${dst#/vendor}")"; echo "stock $dst" > "$V${dst#/vendor}"; done < files/bound
: > files/unit_vendor.sha256.new
while read -r sum path; do
	f=$V${path#/vendor}; mkdir -p "$(dirname "$f")"; echo "reference $path" > "$f"
	echo "$(sha256sum "$f" | cut -d' ' -f1)  $path" >> files/unit_vendor.sha256.new
done < files/unit_vendor.sha256
mv files/unit_vendor.sha256.new files/unit_vendor.sha256
mkdir -p $V/firmware $V/etc/init $V/etc/permissions $V/odm/etc/vintf
echo fw > $V/firmware/rgx.fw.22.68.54.30
echo rc > $V/etc/init/android.hardware.graphics.allocator@2.0-service.rc
echo xml > $V/etc/permissions/handheld_core_hardware.xml
zip -q -r -X $T/rom/gpu/librehu_gpu_ddk111_twrp.zip META-INF files
cd $T/rom
echo "$(sha256sum gpu/librehu_gpu_ddk111_twrp.zip | cut -d' ' -f1)  gpu/librehu_gpu_ddk111_twrp.zip" > info/SHA256SUMS
zip -q -r -X $T/rom.zip gpu info
(cd $V && find . | sort) > $T/vendor.before

# l'etape seule, extraite de update-binary.sh, avec ce qu'elle attend de lui
sed -n '/^vulkan_install() {$/,/^}$/p' "$UB" > $T/step.sh
grep -q '^vulkan_install() {$' $T/step.sh || { echo "vulkan_install absent de update-binary.sh"; exit 1; }
cat > $T/run.sh <<RUN
ui_print() { echo "\$1"; }
ZIPFILE=$T/rom.zip; OUTFD=1; SDCARD=$T/sdcard; TMPD=$T/tmp/lineage; VENMNT=$V; MOUNTED_VEN=0
mkdir -p \$TMPD; unzip -o -q \$ZIPFILE 'info/*' -d \$TMPD
. $T/step.sh
vulkan_install
RUN
export PATH=$T/bin:$PATH UJC_TEST=1 UJC_VENMNT=$V UJC_SYSMNT=$T/system UJC_SDCARD=$T/sdcard UJC_DT=$T/dt \
	UJC_TMP=$T/tmp UJC_VBMETA=$T/none
ok() { echo "OK   $1"; }
ko() { echo "FAIL $1"; cat $T/out; exit 1; }
untouched() { (cd $V && find . | sort) | cmp -s - $T/vendor.before || ko "$1: the vendor changed"; }

touch $T/sdcard/LibreHU/no-vulkan-package
sh $T/run.sh > $T/out 2>&1 || ko "no-vulkan-package: error"
grep -q 'no-vulkan-package found' $T/out || ko "no-vulkan-package: message"
untouched "no-vulkan-package"; ok "LibreHU/no-vulkan-package: nothing written"
rm $T/sdcard/LibreHU/no-vulkan-package

cp $T/rom/info/SHA256SUMS $T/sums; sed -i 's/^./0/' $T/rom/info/SHA256SUMS; (cd $T/rom && zip -q -X $T/rom.zip info/SHA256SUMS)
sh $T/run.sh > $T/out 2>&1 && ko "damaged package: accepted"
grep -q 'package damaged (checksum)' $T/out || ko "damaged package: message"
untouched "damaged package"; ok "damaged package: refused, nothing written"
cp $T/sums $T/rom/info/SHA256SUMS; (cd $T/rom && zip -q -X $T/rom.zip info/SHA256SUMS)

touch $V/lib64/hw/vulkan.ac8257.so; (cd $V && find . | sort) > $T/vendor.driver
sh $T/run.sh > $T/out 2>&1 && ko "package refusal: step returned success"
grep -q 'already has a Vulkan driver' $T/out || ko "package refusal: message"
(cd $V && find . | sort) | cmp -s - $T/vendor.driver || ko "package refusal: the vendor changed"
rm $V/lib64/hw/vulkan.ac8257.so; ok "package refusal (Vulkan driver already there): error returned, nothing written"

sh $T/run.sh > $T/out 2>&1 || ko "install"
while read -r sum path; do
	[ "$(sha256sum "$V${path#/vendor}" | cut -d' ' -f1)" = "$sum" ] || ko "install: $path"
done < $T/pkg/files/MANIFEST
while read -r src dst; do grep -qx "stock $dst" "$V${dst#/vendor}" || ko "install: stock $dst changed"; done < $T/pkg/files/bound
grep -q '^on early-init && property:ro.boot.librehu_gpu=1.11$' $V/etc/init/librehu_gpu_ddk111.rc || ko "install: rc trigger"
ok "install: $(wc -l < $T/pkg/files/MANIFEST) files in place, stock files unchanged, rc only under ro.boot.librehu_gpu=1.11"
sh $T/run.sh > $T/out 2>&1 && grep -q 'Previous installation' $T/out || ko "reinstall"
ok "reinstall"
echo "vulkan step: all tests passed"

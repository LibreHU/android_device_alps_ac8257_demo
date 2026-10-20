#!/bin/bash
#
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: Apache-2.0
#
# Ajoute le pilote ViPERFX_RE (https://github.com/likelikeslike/ViPERFX_RE, module non-AIDL, Android 9) a l'image
# vendor lue par tools/get_vendor_img.sh, comme le fait le zip "viper4android-re" de LibreHU-flashablesZips sur
# l'unite :
#   - libv4a_re.so dans /lib/soundfx et /lib64/soundfx de vendor ;
#   - bibliotheque "v4a_re" et effet "v4a_standard_re" (UUID 90380da3-...) declares dans /etc/audio_effects.xml.
# Sous Android 9 Treble, les effets sont charges par le HAL audio du vendor : le pilote doit etre dans vendor (les
# espaces de noms de l'editeur de liens interdisent a un processus vendor de charger une bibliotheque de /system).
# A utiliser avec l'appli ViPER4Android LibreHU de la meme version (2.1.1).
#
# Modifie seulement l'image locale (debugfs), jamais l'unite. Une copie d'origine est gardee (vendor.img.orig).
#   tools/vendor_add_viper.sh [vendor.img]
#

set -e

MY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMG="${1:-$MY_DIR/../../../../vendor/jancar/ac8257_demo/vendor.img}"
VER=v2.1.1
SHA=c8f769f9d9f470e47f8278d69615c899d54af3916d10291d853fbd299ee847a2
UUID=90380da3-8536-4744-a6a3-5731970e640f
CFG=/etc/audio_effects.xml

command -v debugfs >/dev/null || { echo "debugfs manquant (paquet e2fsprogs)" >&2; exit 1; }
[ -f "$IMG" ] || { echo "$IMG introuvable : lancer d'abord tools/get_vendor_img.sh" >&2; exit 1; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

curl -fsSL -o "$T/module.zip" "https://github.com/likelikeslike/ViPERFX_RE/releases/download/$VER/ViPER4Android-RE-$VER.zip"
echo "$SHA  $T/module.zip" | sha256sum -c -
unzip -q -o "$T/module.zip" 'common/files/*' -d "$T/mod"

[ -f "$IMG.orig" ] || cp "$IMG" "$IMG.orig"

dbg() { debugfs -R "$1" "$IMG" 2>/dev/null; }

# Configuration des effets
dbg "cat $CFG" > "$T/cfg.xml"
grep -q '<libraries>' "$T/cfg.xml" && grep -q '<effects>' "$T/cfg.xml" || {
    echo "$CFG de vendor sans <libraries> / <effects>" >&2; exit 1; }
sed -e '/v4a_standard_re/d' -e '/"v4a_re"/d' \
    -e "s|<libraries>|<libraries>\n        <library name=\"v4a_re\" path=\"libv4a_re.so\"/>|" \
    -e "s|<effects>|<effects>\n        <effect name=\"v4a_standard_re\" library=\"v4a_re\" uuid=\"$UUID\"/>|" \
    "$T/cfg.xml" > "$T/cfg.new"
grep -q "$UUID" "$T/cfg.new"

# Contextes SELinux d'origine (valeur brute de l'attribut, NUL final compris)
dbg "ea_get -f $T/ctx_cfg $CFG security.selinux" >/dev/null
[ -s "$T/ctx_cfg" ] || printf 'u:object_r:vendor_configs_file:s0\0' > "$T/ctx_cfg"
printf 'u:object_r:vendor_file:s0\0' > "$T/ctx_lib"

CMDS="$T/cmds"
{
    echo "rm $CFG"
    echo "write $T/cfg.new $CFG"
    echo "sif $CFG mode 0100644"
    echo "sif $CFG uid 0"
    echo "sif $CFG gid 0"
    echo "ea_set -f $T/ctx_cfg $CFG security.selinux"
    for arch in lib lib64; do
        so=$T/mod/common/files/libv4a_re_armeabi-v7a.so
        [ $arch = lib64 ] && so=$T/mod/common/files/libv4a_re_arm64-v8a.so
        dst=/$arch/soundfx/libv4a_re.so
        echo "rm $dst"
        echo "write $so $dst"
        echo "sif $dst mode 0100644"
        echo "sif $dst uid 0"
        echo "sif $dst gid 0"
        echo "ea_set -f $T/ctx_lib $dst security.selinux"
    done
} > "$CMDS"
debugfs -w -f "$CMDS" "$IMG" >/dev/null 2>"$T/err" || { cat "$T/err" >&2; exit 1; }
e2fsck -fn "$IMG" >/dev/null

# Verification
dbg "cat $CFG" | grep -q "$UUID"
for arch in lib lib64; do dbg "stat /$arch/soundfx/libv4a_re.so" | grep -q "Size:"; done
echo "ViPERFX_RE $VER ajoute a $IMG (copie d'origine : $IMG.orig)"
sha256sum "$IMG"

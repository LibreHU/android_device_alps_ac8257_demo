#!/system/bin/sh
#
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Installe dans /data/app les applis ordinaires de la ROM (APK de /system/etc/librehu), une fois Android demarre
# (librehu_ksunext.rc) :
#  - le gestionnaire KernelSU Next (KernelSUNext.apk) : le noyau LibreHU ne reconnait son gestionnaire que dans
#    /data/app (drivers/kernelsu/manager/throne_tracker.c du noyau : search_manager("/data/app", ...)), jamais en appli
#    systeme. Remis au demarrage suivant s'il a ete desinstalle ; une version plus recente installee est gardee ;
#  - LibreHU Helper (LibreHUHelper.apk) et Aurora Store (AuroraStore.apk) : installes une seule fois
#    (persist.librehu.inst.<paquet>) ; desinstalles par l'utilisateur, ils ne reviennent pas.

DIR=/system/etc/librehu

# $1 : APK, $2 : paquet, $3 : 1 = une seule fois
install_apk() {
    [ -f "$DIR/$1" ] || return 0
    pm path "$2" 2>/dev/null | grep -q '^package:' && return 0
    [ "$3" = 1 ] && [ "$(getprop persist.librehu.inst.$2)" = 1 ] && return 0
    if out=$(pm install "$DIR/$1" 2>&1); then
        log -p i -t LibreHU-Apps "$2 installed: $out"
        [ "$3" = 1 ] && setprop persist.librehu.inst.$2 1
    else
        log -p e -t LibreHU-Apps "$2 not installed: $out"
    fi
}

install_apk KernelSUNext.apk com.rifsxd.ksunext 0
install_apk LibreHUHelper.apk org.librehu.helper 1
install_apk AuroraStore.apk com.aurora.store 1

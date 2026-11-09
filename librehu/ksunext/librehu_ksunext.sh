#!/system/bin/sh
#
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Installe dans /data/app le gestionnaire KernelSU Next de la ROM (/system/etc/librehu/KernelSUNext.apk) s'il n'est
# pas installe. Le noyau LibreHU ne reconnait son gestionnaire que dans /data/app (drivers/kernelsu/manager/
# throne_tracker.c du noyau : search_manager("/data/app", ...)) : en appli systeme il ne le serait jamais, et sans
# gestionnaire aucune appli ne peut recevoir le root (LibreHU-service en a besoin). Lance par librehu_ksunext.rc une
# fois Android demarre. Une version plus recente installee par l'utilisateur est gardee ; un gestionnaire
# desinstalle est remis au demarrage suivant.

APK=/system/etc/librehu/KernelSUNext.apk
PKG=com.rifsxd.ksunext

[ -f "$APK" ] || exit 0
pm path "$PKG" 2>/dev/null | grep -q '^package:' && exit 0
if out=$(pm install "$APK" 2>&1); then
    log -p i -t LibreHU-KSU "KernelSU Next manager installed: $out"
else
    log -p e -t LibreHU-KSU "KernelSU Next manager not installed: $out"
fi

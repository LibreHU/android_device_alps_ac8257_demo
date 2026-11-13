#!/system/bin/sh
#
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Pays du Wi-Fi d'apres la langue choisie a l'installation de LineageOS (persist.sys.locale, par exemple fr-FR -> FR).
# Sans pays, le pilote Wi-Fi MediaTek scanne zero canal (« Country Code is NULL, Detected_Channel_Num = 0 »), remet la
# puce a zero, puis tout le connsys, ce qui finit en plantage du noyau (rapport LibreHU Helper du 13/11/2026) ; une
# borne sur un canal absent n'est pas vue. Le stock pose ro.boot.wificountrycode=CN ; Android 9 le lit au demarrage
# de system_server (WifiCountryCode). Lance par librehu_wificountry.rc juste apres le chargement des proprietes de
# /data, avant system_server. Sans region dans la langue (premier demarrage, langue sans pays), valeur de
# ro.librehu.wificountry_default (device.mk). Changement de langue : pris en compte au demarrage suivant.

[ -n "$(getprop ro.boot.wificountrycode)" ] && exit 0

LOCALE=$(getprop persist.sys.locale)
COUNTRY=${LOCALE##*-}
case "$COUNTRY" in
    [A-Z][A-Z]) ;;
    *) COUNTRY=$(getprop ro.librehu.wificountry_default) ;;
esac
[ -n "$COUNTRY" ] || exit 0

setprop ro.boot.wificountrycode "$COUNTRY"
log -p i -t LibreHU-Wifi "Wi-Fi country code $COUNTRY (locale ${LOCALE:-unset})"

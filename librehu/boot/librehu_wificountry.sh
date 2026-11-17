#!/system/bin/sh
#
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Pays du Wi-Fi (ro.boot.wificountrycode). Sans pays, le pilote Wi-Fi MediaTek scanne zero canal (« Country Code is
# NULL, Detected_Channel_Num = 0 »), remet la puce a zero, puis tout le connsys, ce qui finit en plantage du noyau
# (rapport LibreHU Helper du 13/11/2026) ; une borne sur un canal absent n'est pas vue. Le stock pose
# ro.boot.wificountrycode=CN ; Android 9 le lit au demarrage de system_server (WifiCountryCode). Lance par
# librehu_wificountry.rc juste apres le chargement des proprietes de /data, avant system_server. Changement : pris en
# compte au demarrage suivant. Dans l'ordre :
# 1. persist.librehu.wificountry (deux lettres, choix force : essais, ou pays que rien d'autre ne donne) ;
# 2. le pays du fuseau horaire (persist.sys.timezone, regle par l'assistant, le reseau ou le GPS) d'apres la table
#    d'Android tzlookup.xml (meme table que TimeZoneFinder) : le meilleur indice du pays ou roule la voiture, une
#    langue comme en-US ne dit rien du pays (installation propre du 17/11/2026 : pas de persist.sys.locale, fuseau
#    Europe/Paris, et le pays tombait sur CN, sans le canal 5 GHz 100 de la borne) ;
# 3. la region de la langue (persist.sys.locale, par exemple fr-FR -> FR) ;
# 4. ro.librehu.wificountry_default (device.mk).

[ -n "$(getprop ro.boot.wificountrycode)" ] && exit 0

two_letters() {
    case "$1" in
        [A-Za-z][A-Za-z]) echo "$1" | tr a-z A-Z ;;
    esac
}

# Pays (deux lettres minuscules) du fuseau $1 dans tzlookup.xml : <country code="fr" ...> puis ses <id>...</id>
tz_country() {
    tz=$1
    [ -n "$tz" ] || return
    for f in /data/misc/zoneinfo/current/tzlookup.xml /system/usr/share/zoneinfo/tzlookup.xml; do
        [ -r "$f" ] || continue
        code=
        while IFS= read -r line; do
            case "$line" in
                *'<country code="'*)
                    code=${line#*code=\"}
                    code=${code%%\"*}
                    ;;
                *">$tz</id>"*)
                    echo "$code"
                    return
                    ;;
            esac
        done < "$f"
        return
    done
}

SOURCE=persist.librehu.wificountry
COUNTRY=$(two_letters "$(getprop persist.librehu.wificountry)")
if [ -z "$COUNTRY" ]; then
    TZ_ID=$(getprop persist.sys.timezone)
    COUNTRY=$(two_letters "$(tz_country "$TZ_ID")")
    SOURCE="timezone ${TZ_ID:-unset}"
fi
if [ -z "$COUNTRY" ]; then
    LOCALE=$(getprop persist.sys.locale)
    # region only (upper case, after the last "-"): "fr" alone is a language, not a country
    case "${LOCALE##*-}" in
        [A-Z][A-Z]) COUNTRY=${LOCALE##*-} ;;
    esac
    SOURCE="locale ${LOCALE:-unset}"
fi
if [ -z "$COUNTRY" ]; then
    COUNTRY=$(two_letters "$(getprop ro.librehu.wificountry_default)")
    SOURCE=ro.librehu.wificountry_default
fi
[ -n "$COUNTRY" ] || exit 0

setprop ro.boot.wificountrycode "$COUNTRY"
log -p i -t LibreHU-Wifi "Wi-Fi country code $COUNTRY ($SOURCE)"

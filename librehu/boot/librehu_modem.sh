#!/system/bin/sh
#
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Telephonie seulement s'il y a un modem. Les cartes « +4G » de l'AC8257 utilisent le modem MediaTek integre au SoC
# (MD1) : le LK charge son micrologiciel (partition md1img) et le noyau (pilote CCCI, CONFIG_MTK_ECCCI_DRIVER) l'indique
# dans /sys/kernel/ccci/md_en, « E-D-D-D-D (1->5) » modem 1 actif, « D-D-D-D-D » sinon (ccci_util_lib_sys.c). Sans
# modem (la plupart des UJC201 : « [ccci0/util]no image enabled » dans le dmesg), le manifeste VINTF du vendor stock
# declare quand meme IRadio slot1 / slot2 : l'appli Telephone attend ce service sans fin (RIL.<init> -> getRadioProxy
# -> IRadio.getService(slot1, true)), ANR a chaque demarrage. ro.radio.noril fait de l'unite un appareil Wi-Fi seul :
# ConnectivityService ne declare pas le reseau mobile (ConnectivityService.java l. 803) et RIL.java ne demande plus le
# service radio (l. 356, 469 ; LineageOS 16.0). Les appels Bluetooth (LibreHU Dialer, profil mains-libres) ne passent
# pas par le RIL et restent possibles.
# persist.librehu.radio : « on » = telephonie meme sans modem detecte (modem USB avec son RIL, test), « off » = jamais,
# autre ou vide = detection. Lance par librehu_modem.rc juste apres le chargement des proprietes de /data, avant
# system_server.

[ -n "$(getprop ro.radio.noril)" ] && exit 0

MODE=$(getprop persist.librehu.radio)
MD=$(cat /sys/kernel/ccci/md_en 2>/dev/null)

case "$MODE" in
    on) log -p i -t LibreHU-Radio "telephony on (persist.librehu.radio=on, md_en: ${MD:-absent})"; exit 0 ;;
    off) ;;
    *)
        case "$MD" in
            E*) log -p i -t LibreHU-Radio "integrated modem enabled (md_en: $MD): telephony on"; exit 0 ;;
        esac
        ;;
esac

setprop ro.radio.noril 1
log -p i -t LibreHU-Radio "telephony off (md_en: ${MD:-absent}, persist.librehu.radio=${MODE:-auto}): ro.radio.noril=1, Wi-Fi only"

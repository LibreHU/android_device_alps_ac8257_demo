#!/system/bin/sh
#
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# LibreHU (UJC201) : calibration d'usine de la dalle Goodix, comme ivi-services sous le stock. Le pilote applique la
# matrice de /sys/devices/platform/touch/gt9xx_props ("A B C D E F Div") ; elle vient de /jancar/config :
# pointercal-1280x720.xml puis pointercal.xml, noeud de l'identifiant de la dalle (19 premiers caracteres de
# /proc/gt9xx_config). Sans elle (identite), le tactile tombe hors de l'ecran. Lance en root par librehu_touchcal.rc
# (on boot) : LibreHU-service ne l'ecrit qu'avec le root de KernelSU, pas encore accorde sur un /data neuf. Une
# calibration faite dans LibreHU-service (root accorde) la remplace ensuite.
PROPS=${TOUCHCAL_PROPS:-/sys/devices/platform/touch/gt9xx_props}
CFG=${TOUCHCAL_CFG:-/proc/gt9xx_config}
DIR=${TOUCHCAL_DIR:-/jancar/config}
[ -w "$PROPS" ] || { echo "touchcal: $PROPS absent ou non inscriptible (lancer en root)"; exit 1; }
ID=$(head -c 19 "$CFG" 2>/dev/null)
[ -n "$ID" ] || { echo "touchcal: identifiant de dalle illisible ($CFG)"; exit 1; }
for F in "$DIR/pointercal-1280x720.xml" "$DIR/pointercal.xml"; do
    [ -r "$F" ] || continue
    NODE=$(sed -n "/<node touch=\"$ID\">/,/<\/node>/p" "$F")
    [ -n "$NODE" ] || continue
    M=""
    for K in A B C D E F Div; do
        V=$(echo "$NODE" | sed -n "s/.*<item id=\"$K\">\(-\{0,1\}[0-9]\{1,\}\)<\/item>.*/\1/p" | head -n 1)
        [ -n "$V" ] || { M=""; break; }
        M="$M$V "
    done
    case "$M" in ""|*" 0 ") continue;; esac
    echo "$M" > "$PROPS" || { echo "touchcal: ecriture de $PROPS impossible"; exit 1; }
    echo "touchcal: $ID -> $M($F)"
    log -p i -t LibreHU-Touch "calibration $ID -> $M($F)" 2>/dev/null
    exit 0
done
echo "touchcal: aucune calibration pour la dalle $ID dans $DIR"
log -p w -t LibreHU-Touch "no calibration for panel $ID in $DIR" 2>/dev/null
exit 1

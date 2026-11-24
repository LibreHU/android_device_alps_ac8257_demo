#!/system/bin/sh
#
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Toutes les autorisations aux applis LibreHU, sans rien demander a l'utilisateur (applis d'un autoradio : pas d'ecran
# de demande au demarrage, et Android Auto, CarPlay, le service demarrent sans ecran visible). Lance en root par
# librehu_grants.rc a chaque demarrage d'Android (sys.boot_completed) ; ne fait rien de ce qui est deja en place.
# Paquets : org.librehu.*, ViPER4Android (com.llsl.viper4android) et MCU Toolkit (com.dokt.jacmcu).
#
# Au premier demarrage, avant ce script, Android a deja accorde les permissions de
# /system/etc/default-permissions/default-permissions-librehu.xml et l'acces aux notifications de
# config_defaultListenerAccessPackages (overlay) ; ce script couvre le reste, et les applis mises a jour par LibreHU
# Apps qui demandent une permission de plus (accordee au demarrage suivant) :
# - toutes les permissions dangereuses demandees par l'appli (cmd package grant) ;
# - les autorisations speciales (cmd appops) : superposition, ecriture des reglages, installation d'applis, VPN sans
#   demande, capture d'ecran sans demande, execution en arriere-plan ;
# - pas d'economie de batterie (liste blanche de deviceidle) ;
# - acces aux notifications de chaque NotificationListenerService (cmd notification allow_listener) ;
# - services d'accessibilite actives (BtnRemap) ;
# - administrateur de l'appareil actif (Android Auto : ecran eteint) ;
# - LibreHU Launcher ecran d'accueil par defaut tant qu'aucun n'est choisi (Trebuchet reste en secours) ;
# - economiseur d'ecran du Launcher choisi tant qu'aucun autre ne l'est (pas active pour autant).

TAG=LibreHU-Grants
info() { log -p i -t "$TAG" "$*"; }

pkgs=$(cmd package list packages 2>/dev/null | sed -n 's/^package://p' |
    grep -E '^(org\.librehu\..+|com\.llsl\.viper4android|com\.dokt\.jacmcu)$')
if [ -z "$pkgs" ]; then
    info "no LibreHU app installed"
    exit 0
fi
is_ours() {
    case "${1%%/*}" in
        org.librehu.?*|com.llsl.viper4android|com.dokt.jacmcu) return 0 ;;
    esac
    return 1
}

# Permissions dangereuses connues de cette version d'Android (ACCESS_BACKGROUND_LOCATION n'existe qu'a partir
# d'Android 10 : absente ici sous Android 9, donc jamais demandee)
dangerous=" $(cmd package list permissions -d 2>/dev/null | sed -n 's/^permission://p' | tr '\n' ' ') "

granted=0
for p in $pkgs; do
    # Permissions demandees (section « requested permissions: » de chaque version du paquet, systeme et mise a jour)
    for perm in $(dumpsys package "$p" 2>/dev/null | awk '
        /^ *requested permissions:/ { s = 1; next }
        s && (/^ *[a-zA-Z ]+:$/ || /^ *[a-z]+ permissions:/) { s = 0 }
        s { sub(/^ +/, ""); sub(/[:,].*/, ""); if ($0 != "") print }' | sort -u); do
        case "$dangerous" in
            *" $perm "*)
                cmd package grant "$p" "$perm" >/dev/null 2>&1 && granted=$((granted + 1)) ;;
        esac
    done
    for op in SYSTEM_ALERT_WINDOW WRITE_SETTINGS REQUEST_INSTALL_PACKAGES ACTIVATE_VPN PROJECT_MEDIA \
        RUN_IN_BACKGROUND RUN_ANY_IN_BACKGROUND; do
        cmd appops set "$p" "$op" allow >/dev/null 2>&1
    done
    cmd deviceidle whitelist "+$p" >/dev/null 2>&1
done
info "runtime permissions granted (or already there): $granted, apps: $(echo $pkgs)"

components() {
    cmd package "$1" --components -a "$2" 2>/dev/null | while read -r c; do
        is_ours "$c" && echo "$c"
    done
}

for c in $(components query-services android.service.notification.NotificationListenerService); do
    cmd notification allow_listener "$c" >/dev/null 2>&1 && info "notification access: $c"
done

acc=$(cmd settings get secure enabled_accessibility_services 2>/dev/null)
[ "$acc" = "null" ] && acc=
new=$acc
for c in $(components query-services android.accessibilityservice.AccessibilityService); do
    case ":$new:" in
        *":$c:"*) ;;
        *) new=${new:+$new:}$c ;;
    esac
done
if [ "$new" != "$acc" ]; then
    cmd settings put secure enabled_accessibility_services "$new"
    cmd settings put secure accessibility_enabled 1
    info "accessibility services: $new"
fi

admins=$(dumpsys device_policy 2>/dev/null)
for c in $(components query-receivers android.app.action.DEVICE_ADMIN_ENABLED); do
    case "$admins" in
        *"${c%%/*}"*) ;;
        *) dpm set-active-admin --user 0 "$c" >/dev/null 2>&1 && info "device admin: $c" ;;
    esac
done

launcher=org.librehu.launcher/.MainActivity
case " $(echo $pkgs) " in
    *" org.librehu.launcher "*)
        home=$(cmd package resolve-activity --components -a android.intent.action.MAIN \
            -c android.intent.category.HOME 2>/dev/null | tail -n 1)
        case "$home" in
            *ResolverActivity*|"No activity found"|"")
                cmd package set-home-activity "$launcher" >/dev/null 2>&1 && info "default home: $launcher" ;;
        esac
        dream=$(cmd settings get secure screensaver_components 2>/dev/null)
        case "$dream" in
            ""|null|*deskclock*)
                cmd settings put secure screensaver_components org.librehu.launcher/.standby.StandbyDream
                info "screensaver: org.librehu.launcher/.standby.StandbyDream" ;;
        esac
        ;;
esac
exit 0

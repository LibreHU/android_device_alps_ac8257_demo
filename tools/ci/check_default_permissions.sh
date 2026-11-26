#!/bin/bash
#
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Verifie que chaque permission android.permission.* de librehu/permissions/default-permissions-librehu.xml est declaree
# par la version d'Android compilee (frameworks/base/core/res/AndroidManifest.xml des sources). Une permission inconnue
# dans ce fichier fait planter system_server au demarrage : DefaultPermissionGrantPolicy l'accorde a l'appli qui la
# demande et PermissionManagerService leve IllegalArgumentException « Unknown permission », que rien ne rattrape ;
# l'unite reste sur l'animation de demarrage (16.0 du 24/11/2026 avec ACCESS_BACKGROUND_LOCATION, d'Android 10).
#   tools/ci/check_default_permissions.sh [racine des sources | AndroidManifest.xml]
#   (defaut : $ANDROID_BUILD_TOP, sinon le dossier courant). Code 1 si une permission est inconnue, 2 si fichier absent.
set -e

MY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XML="$MY_DIR/../../librehu/permissions/default-permissions-librehu.xml"
ARG=${1:-${ANDROID_BUILD_TOP:-$PWD}}
if [ -f "$ARG" ]; then MANIFEST=$ARG; else MANIFEST=$ARG/frameworks/base/core/res/AndroidManifest.xml; fi
[ -f "$XML" ] || { echo "check_default_permissions: $XML introuvable" >&2; exit 2; }
[ -f "$MANIFEST" ] || { echo "check_default_permissions: $MANIFEST introuvable" >&2; exit 2; }

bad=0
n=0
for p in $(grep -o 'name="android\.permission\.[A-Za-z0-9_]*"' "$XML" | sed 's/^name="//; s/"$//' | sort -u); do
	n=$((n + 1))
	# declaration (<permission android:name="..."), pas une simple utilisation (<uses-permission ...)
	if ! grep -Eq "<permission[[:space:]]+android:name=\"$p\"" "$MANIFEST"; then
		echo "check_default_permissions: $p inconnue de cette version d'Android (absente de $MANIFEST)" >&2
		bad=1
	fi
done
[ $bad = 0 ] && echo "check_default_permissions: OK ($n permissions, toutes declarees par la plateforme)"
exit $bad

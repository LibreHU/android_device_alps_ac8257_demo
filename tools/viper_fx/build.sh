#!/bin/sh
# Construit les zips TWRP du pilote ViPER4Android RE sans Magisk (dans out/) :
#   ujc201_viper_install.zip et ujc201_viper_restore.zip
# usage : tools/viper_fx/build.sh ViPER4Android-RE-vX.Y.Z.zip   (module Magisk non-AIDL de ViPERFX_RE)
set -e
MOD=$(readlink -f "$1"); [ -f "$MOD" ] || { echo "usage: $0 ViPER4Android-RE-vX.zip" >&2; exit 1; }
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
unzip -q -o "$MOD" module.prop LICENSE 'common/files/*' -d "$W/mod"
VER=$(sed -n 's/^version=//p' "$W/mod/module.prop")
mkdir -p out
for kind in install restore; do
	d=$W/$kind; mkdir -p $d/META-INF/com/google/android
	{ echo '#!/sbin/sh'; echo "OUTFD=\$2; ZIPFILE=\$3; V4A_VERSION=$VER"; cat common.sh; cat $kind.sh; } \
		> $d/META-INF/com/google/android/update-binary
	cp $kind/META-INF/com/google/android/updater-script $d/META-INF/com/google/android/
	if [ $kind = install ]; then
		mkdir -p $d/files
		cp "$W"/mod/common/files/libv4a_re_*.so "$W/mod/LICENSE" $d/files/
	fi
	rm -f out/ujc201_viper_$kind.zip
	(cd $d && zip -q -X -r "$OLDPWD/out/ujc201_viper_$kind.zip" .)
	echo "out/ujc201_viper_$kind.zip ($VER)"
done

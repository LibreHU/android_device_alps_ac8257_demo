# LibreHU - WPA3 (SAE) et OWE sous LineageOS 17.1 : wpa_supplicant avec le HAL android.hardware.wifi.supplicant@1.2.
# Fonctions partagees par l'installateur du zip de la ROM (tools/flashable/update-binary.sh) et les zips
# librehu_wifi_wpa3_twrp.zip / librehu_wifi_wpa3_restore_twrp.zip (tools/make_wifi_zips.py).
# Android 10 n'active WPA3 et OWE qu'avec le HAL 1.2 (source.android.com/docs/core/connect/wifi-wpa3-owe) ; le
# wpa_supplicant du vendor Android 9 (v2.7-devel) a le HAL 1.1, alors que le pilote annonce SAE (driver_flags).
# Fichiers : /vendor/bin/hw/wpa_supplicant (remplace, contenu ecrit dans le fichier existant : droits et contexte SELinux
# du stock gardes), /vendor/lib64/android.hardware.wifi.supplicant@1.2.so (absent du VNDK 28 de l'unite), manifeste VINTF
# du vendor (HAL supplicant 1.1 -> 1.2) et init.connectivity.rc (service wpa_supplicant : interface @1.2 ajoutee).
# Originaux sauvegardes une fois dans $SDCARD/LibreHU/backup/wifi-hal11-orig (jamais ecrases) ; manifeste et .rc toujours
# recalcules depuis cette sauvegarde (pas de double modification). Retour : wifi_wpa3_restore.
# Attend : VENMNT (vendor monte en ecriture), SDCARD, ui_print.

WPA3_MARK=etc/wifi/.librehu_wpa3

wpa3_files() {
	WPA3_BIN=$VENMNT/bin/hw/wpa_supplicant
	WPA3_MAN=$VENMNT/etc/vintf/manifest.xml
	[ -f $WPA3_MAN ] || WPA3_MAN=$VENMNT/manifest.xml
	WPA3_RC=$VENMNT/etc/init/hw/init.connectivity.rc
	WPA3_BK=$SDCARD/LibreHU/backup/wifi-hal11-orig
}

# $1 = dossier avec bin/wpa_supplicant, lib64/android.hardware.wifi.supplicant@1.2.so, SHA256SUMS, vendor_needed.txt
wifi_wpa3_install() {
	W=$1
	wpa3_files
	while read -r S F; do
		[ -n "$F" ] || continue
		[ "$(sha256sum $W/$F | cut -d' ' -f1)" = "$S" ] || { ui_print "WPA3: wrong checksum for $F"; return 1; }
	done < $W/SHA256SUMS
	for f in $WPA3_BIN $WPA3_MAN $WPA3_RC; do
		[ -f $f ] || { ui_print "WPA3: $f not found (not the stock UJC201 vendor?)"; return 1; }
	done
	# bibliotheques du vendor dont le nouveau binaire a besoin (rapport de tools/wifi/check_vendor_abi.py de la CI)
	if [ -f $W/vendor_needed.txt ]; then
		while read -r L; do
			[ -z "$L" ] || [ -f $VENMNT/lib64/$L ] || { ui_print "WPA3: $L missing from /vendor/lib64, nothing changed"; return 1; }
		done < $W/vendor_needed.txt
	fi
	if [ ! -d $WPA3_BK ]; then
		if [ -f $VENMNT/$WPA3_MARK ]; then
			ui_print "WPA3: already installed but no backup in $WPA3_BK: nothing changed"
			return 1
		fi
		grep -q 'android.hardware.wifi.supplicant@1.1::ISupplicant' $WPA3_RC || {
			ui_print "WPA3: init.connectivity.rc is not the stock one (no supplicant @1.1): nothing changed"; return 1; }
		mkdir -p $WPA3_BK || { ui_print "WPA3: cannot create $WPA3_BK"; return 1; }
		cp $WPA3_BIN $WPA3_BK/wpa_supplicant && cp $WPA3_MAN $WPA3_BK/manifest.xml && \
			cp $WPA3_RC $WPA3_BK/init.connectivity.rc || { rm -rf $WPA3_BK; ui_print "WPA3: backup failed"; return 1; }
		echo "$WPA3_MAN" > $WPA3_BK/manifest.path
		(cd $WPA3_BK && sha256sum wpa_supplicant manifest.xml init.connectivity.rc > SHA256SUMS)
		ui_print "WPA3: original supplicant backed up: $WPA3_BK"
	fi
	T=${UJC_TMP:-/tmp}/librehu_wpa3; rm -rf $T; mkdir -p $T
	# manifeste : dans le bloc android.hardware.wifi.supplicant seulement, version 1.1 -> 1.2
	awk '
		/<name>android.hardware.wifi.supplicant<\/name>/ { inb = 1 }
		inb { gsub(/<version>1\.1<\/version>/, "<version>1.2</version>"); gsub(/@1\.1::ISupplicant/, "@1.2::ISupplicant") }
		/<\/hal>/ { inb = 0 }
		{ print }' $WPA3_BK/manifest.xml > $T/manifest.xml
	grep -q '<version>1.2</version>' $T/manifest.xml || { ui_print "WPA3: manifest not changed (unexpected format)"; return 1; }
	# service wpa_supplicant : interface @1.2 ajoutee apres la @1.1 (demarrage a la demande par hwservicemanager)
	awk '{ print }
		/interface android.hardware.wifi.supplicant@1.1::ISupplicant default/ {
			sub(/interface.*/, ""); print $0 "interface android.hardware.wifi.supplicant@1.2::ISupplicant default" }' \
		$WPA3_BK/init.connectivity.rc > $T/init.connectivity.rc
	grep -q 'supplicant@1.2::ISupplicant' $T/init.connectivity.rc || { ui_print "WPA3: .rc not changed"; return 1; }
	# ecriture dans les fichiers existants (droits, proprietaire, contexte SELinux du stock gardes)
	cat $W/bin/wpa_supplicant > $WPA3_BIN || { ui_print "WPA3: cannot write $WPA3_BIN"; wifi_wpa3_restore; return 1; }
	L=$VENMNT/lib64/android.hardware.wifi.supplicant@1.2.so
	cp $W/lib64/android.hardware.wifi.supplicant@1.2.so $L || { ui_print "WPA3: cannot write $L"; wifi_wpa3_restore; return 1; }
	chmod 0644 $L; chown 0:0 $L
	[ -z "$UJC_TEST" ] && chcon u:object_r:vendor_file:s0 $L
	cat $T/manifest.xml > $WPA3_MAN && cat $T/init.connectivity.rc > $WPA3_RC || {
		ui_print "WPA3: cannot write the manifest or the .rc"; wifi_wpa3_restore; return 1; }
	[ "$(sha256sum $WPA3_BIN | cut -d' ' -f1)" = "$(grep ' bin/wpa_supplicant$' $W/SHA256SUMS | cut -d' ' -f1)" ] || {
		ui_print "WPA3: supplicant read back different"; wifi_wpa3_restore; return 1; }
	cat $W/version > $VENMNT/$WPA3_MARK 2>/dev/null || echo installed > $VENMNT/$WPA3_MARK
	chmod 0644 $VENMNT/$WPA3_MARK
	[ -z "$UJC_TEST" ] && chcon u:object_r:vendor_configs_file:s0 $VENMNT/$WPA3_MARK 2>/dev/null
	rm -rf $T
	ui_print "WPA3: supplicant HAL 1.2 installed ($(cat $W/version 2>/dev/null))"
	return 0
}

wifi_wpa3_restore() {
	wpa3_files
	[ -d $WPA3_BK ] || { ui_print "WPA3: no backup in $WPA3_BK"; return 1; }
	while read -r S F; do
		[ "$(sha256sum $WPA3_BK/$F | cut -d' ' -f1)" = "$S" ] || { ui_print "WPA3: backup $F damaged"; return 1; }
	done < $WPA3_BK/SHA256SUMS
	cat $WPA3_BK/wpa_supplicant > $WPA3_BIN && cat $WPA3_BK/manifest.xml > $WPA3_MAN && \
		cat $WPA3_BK/init.connectivity.rc > $WPA3_RC || { ui_print "WPA3: cannot write the originals back"; return 1; }
	rm -f $VENMNT/lib64/android.hardware.wifi.supplicant@1.2.so $VENMNT/$WPA3_MARK
	ui_print "WPA3: original supplicant (HAL 1.1) back"
	return 0
}

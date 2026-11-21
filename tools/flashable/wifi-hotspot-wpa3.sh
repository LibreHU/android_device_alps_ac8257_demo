# LibreHU - WPA3 (SAE) du point d'acces Wi-Fi (partage de connexion) sous les ROM LibreHU Android 11+ : hostapd avec le
# HAL android.hardware.wifi.hostapd@1.2. Android 11 ne propose WPA3 au point d'acces qu'avec le 1.2
# (frameworks/opt/net/wifi HostapdHal : addAccessPoint_1_2, sinon refus) et l'overlay config_wifi_softap_sae_supported
# (mis par la ROM LibreHU) ; le hostapd du vendor Android 9 a le 1.0. Le pilote MediaTek gen4m fait le reste
# (CFG_SUPPORT_SOFTAP_WPA3 : trames AUTH / ASSOC du point d'acces remontees a hostapd, SAE fait par hostapd).
# Fonctions partagees par librehu_wifi_wpa3_hotspot_twrp.zip et librehu_wifi_wpa3_hotspot_restore_twrp.zip
# (tools/make_hotspot_zips.py).
# Fichiers : /vendor/bin/hw/hostapd (remplace, contenu ecrit dans le fichier existant : droits et contexte SELinux du
# stock gardes), /vendor/lib64/android.hardware.wifi.hostapd@1.1.so et @1.2.so (absents du VNDK 28 de l'unite),
# manifeste VINTF du vendor (HAL hostapd 1.0 -> 1.2) et .rc du service hostapd (interfaces @1.1 et @1.2 ajoutees).
# Originaux sauvegardes une fois dans $SDCARD/LibreHU/backup/hostapd-orig (jamais ecrases) ; manifeste et .rc toujours
# recalcules depuis cette sauvegarde. Retour : wifi_hotspot_restore.
# Attend : VENMNT (vendor monte en ecriture), SDCARD, ui_print.

HAP_MARK=etc/wifi/.librehu_hostapd_wpa3
HAP_LIBS="android.hardware.wifi.hostapd@1.1.so android.hardware.wifi.hostapd@1.2.so"

hap_files() {
	HAP_BIN=$VENMNT/bin/hw/hostapd
	HAP_BK=$SDCARD/LibreHU/backup/hostapd-orig
	if [ -f $HAP_BK/rc.path ] && [ -f $HAP_BK/manifest.path ]; then
		HAP_RC=$(cat $HAP_BK/rc.path)
		HAP_MAN=$(cat $HAP_BK/manifest.path)
		return
	fi
	HAP_RC=
	for f in $VENMNT/etc/init/*.rc $VENMNT/etc/init/hw/*.rc; do
		[ -f "$f" ] && grep -q -E '^service hostapd ' "$f" && { HAP_RC=$f; break; }
	done
	HAP_MAN=
	for f in $VENMNT/etc/vintf/manifest.xml $VENMNT/etc/vintf/manifest/*.xml $VENMNT/manifest.xml; do
		[ -f "$f" ] && grep -q '<name>android.hardware.wifi.hostapd</name>' "$f" && { HAP_MAN=$f; break; }
	done
}

# $1 = dossier avec bin/hostapd, lib64/android.hardware.wifi.hostapd@1.1.so et @1.2.so, SHA256SUMS, vendor_needed.txt
wifi_hotspot_install() {
	W=$1
	hap_files
	while read -r S F; do
		[ -n "$F" ] || continue
		[ "$(sha256sum $W/$F | cut -d' ' -f1)" = "$S" ] || { ui_print "Hotspot WPA3: wrong checksum for $F"; return 1; }
	done < $W/SHA256SUMS
	[ -f "$HAP_BIN" ] || { ui_print "Hotspot WPA3: $HAP_BIN not found (not the stock UJC201 vendor?)"; return 1; }
	[ -n "$HAP_RC" ] || { ui_print "Hotspot WPA3: no .rc with 'service hostapd' in /vendor/etc/init"; return 1; }
	[ -n "$HAP_MAN" ] || { ui_print "Hotspot WPA3: android.hardware.wifi.hostapd not in the vendor manifest"; return 1; }
	# bibliotheques du vendor dont le nouveau binaire a besoin (rapport de tools/wifi/check_vendor_abi.py de la CI)
	if [ -f $W/vendor_needed.txt ]; then
		while read -r L; do
			[ -z "$L" ] || [ -f $VENMNT/lib64/$L ] || { ui_print "Hotspot WPA3: $L missing from /vendor/lib64, nothing changed"; return 1; }
		done < $W/vendor_needed.txt
	fi
	if [ ! -d $HAP_BK ]; then
		if [ -f $VENMNT/$HAP_MARK ]; then
			ui_print "Hotspot WPA3: already installed but no backup in $HAP_BK: nothing changed"
			return 1
		fi
		grep -q 'android.hardware.wifi.hostapd@1.0::IHostapd' "$HAP_RC" || {
			ui_print "Hotspot WPA3: $HAP_RC is not the stock one (no hostapd @1.0 interface): nothing changed"; return 1; }
		mkdir -p $HAP_BK || { ui_print "Hotspot WPA3: cannot create $HAP_BK"; return 1; }
		cp $HAP_BIN $HAP_BK/hostapd && cp "$HAP_MAN" $HAP_BK/manifest.xml && cp "$HAP_RC" $HAP_BK/hostapd.rc || {
			rm -rf $HAP_BK; ui_print "Hotspot WPA3: backup failed"; return 1; }
		echo "$HAP_MAN" > $HAP_BK/manifest.path
		echo "$HAP_RC" > $HAP_BK/rc.path
		# a library of the same name already in the vendor (not the stock UJC201 one) is kept to be put back
		for L in $HAP_LIBS; do
			[ -f $VENMNT/lib64/$L ] && { cp $VENMNT/lib64/$L $HAP_BK/$L || { rm -rf $HAP_BK; ui_print "Hotspot WPA3: backup failed"; return 1; }; }
		done
		(cd $HAP_BK && sha256sum hostapd manifest.xml hostapd.rc $(for L in $HAP_LIBS; do [ -f $L ] && echo $L; done) > SHA256SUMS)
		ui_print "Hotspot WPA3: original hostapd backed up: $HAP_BK"
	fi
	T=${UJC_TMP:-/tmp}/librehu_hostapd; rm -rf $T; mkdir -p $T
	# manifeste : dans le bloc android.hardware.wifi.hostapd seulement, version 1.0 (ou 1.1) -> 1.2
	awk '
		/<name>android.hardware.wifi.hostapd<\/name>/ { inb = 1 }
		inb { gsub(/<version>1\.[01]<\/version>/, "<version>1.2</version>"); gsub(/@1\.[01]::IHostapd/, "@1.2::IHostapd") }
		/<\/hal>/ { inb = 0 }
		{ print }' $HAP_BK/manifest.xml > $T/manifest.xml
	grep -A3 '<name>android.hardware.wifi.hostapd</name>' $T/manifest.xml | grep -q -E '1\.2' || {
		ui_print "Hotspot WPA3: manifest not changed (unexpected format)"; return 1; }
	# service hostapd : interfaces @1.1 et @1.2 apres la @1.0 (demarrage a la demande par hwservicemanager)
	awk '{ print }
		/interface android.hardware.wifi.hostapd@1.0::IHostapd default/ && !done {
			p = $0; sub(/interface.*/, "", p)
			print p "interface android.hardware.wifi.hostapd@1.1::IHostapd default"
			print p "interface android.hardware.wifi.hostapd@1.2::IHostapd default"; done = 1 }' \
		$HAP_BK/hostapd.rc | awk '!(/hostapd@1\.[12]::IHostapd default/ && seen[$0]++)' > $T/hostapd.rc
	grep -q 'hostapd@1.2::IHostapd' $T/hostapd.rc || { ui_print "Hotspot WPA3: .rc not changed"; return 1; }
	# ecriture dans les fichiers existants (droits, proprietaire, contexte SELinux du stock gardes)
	cat $W/bin/hostapd > $HAP_BIN || { ui_print "Hotspot WPA3: cannot write $HAP_BIN"; wifi_hotspot_restore; return 1; }
	for L in $HAP_LIBS; do
		cp $W/lib64/$L $VENMNT/lib64/$L || { ui_print "Hotspot WPA3: cannot write $L"; wifi_hotspot_restore; return 1; }
		chmod 0644 $VENMNT/lib64/$L; chown 0:0 $VENMNT/lib64/$L
		[ -z "$UJC_TEST" ] && chcon u:object_r:vendor_file:s0 $VENMNT/lib64/$L
	done
	cat $T/manifest.xml > "$HAP_MAN" && cat $T/hostapd.rc > "$HAP_RC" || {
		ui_print "Hotspot WPA3: cannot write the manifest or the .rc"; wifi_hotspot_restore; return 1; }
	[ "$(sha256sum $HAP_BIN | cut -d' ' -f1)" = "$(grep ' bin/hostapd$' $W/SHA256SUMS | cut -d' ' -f1)" ] || {
		ui_print "Hotspot WPA3: hostapd read back different"; wifi_hotspot_restore; return 1; }
	mkdir -p $VENMNT/etc/wifi
	cat $W/version > $VENMNT/$HAP_MARK 2>/dev/null || echo installed > $VENMNT/$HAP_MARK
	chmod 0644 $VENMNT/$HAP_MARK
	[ -z "$UJC_TEST" ] && chcon u:object_r:vendor_configs_file:s0 $VENMNT/$HAP_MARK 2>/dev/null
	rm -rf $T
	ui_print "Hotspot WPA3: hostapd HAL 1.2 installed ($(cat $W/version 2>/dev/null))"
	return 0
}

wifi_hotspot_restore() {
	hap_files
	[ -d $HAP_BK ] || { ui_print "Hotspot WPA3: no backup in $HAP_BK"; return 1; }
	while read -r S F; do
		[ "$(sha256sum $HAP_BK/$F | cut -d' ' -f1)" = "$S" ] || { ui_print "Hotspot WPA3: backup $F damaged"; return 1; }
	done < $HAP_BK/SHA256SUMS
	cat $HAP_BK/hostapd > $HAP_BIN && cat $HAP_BK/manifest.xml > "$HAP_MAN" && cat $HAP_BK/hostapd.rc > "$HAP_RC" || {
		ui_print "Hotspot WPA3: cannot write the originals back"; return 1; }
	for L in $HAP_LIBS; do
		if [ -f $HAP_BK/$L ]; then cat $HAP_BK/$L > $VENMNT/lib64/$L; else rm -f $VENMNT/lib64/$L; fi
	done
	rm -f $VENMNT/$HAP_MARK
	ui_print "Hotspot WPA3: original hostapd (HAL 1.0) back"
	return 0
}

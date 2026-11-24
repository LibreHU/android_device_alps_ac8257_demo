# RRO tools

Static readers for the stock vendor's `framework-res__auto_generated_rro.apk` (MediaTek runtime resource overlay),
which the ROM zip removes. Nothing in the APK is run.

- `arsc_dump.py resources.arsc`: prints every entry (type/name, configuration qualifiers, value).
- `rro_to_overlay.py resources.arsc <res dir> <key,key...> [skip=qualifier:key,...]`: writes the chosen per-carrier
  entries as `values-mcc*/config.xml` files of a device overlay.

`overlay/frameworks/base/core/res/res/values-mcc*/` was made with:

    python3 -I tools/rro/rro_to_overlay.py resources.arsc overlay/frameworks/base/core/res/res \
        config_tether_apndata,config_mobile_mtu,config_mobile_tcp_buffers,config_valid_wappush_index,config_telephony_use_own_number_for_voicemail,config_use_sim_language_file \
        skip=mcc334-mnc20:config_use_sim_language_file,mcc310-mnc00:config_telephony_use_own_number_for_voicemail,mcc310-mnc00:config_valid_wappush_index

Skipped: entries LineageOS already has (identical) and the
`mnc00` entries of mcc 310 (no real carrier).

Cles lues par version (verifie dans les config.xml de LineageOS 16.0 a 21.0, 24/11/2026) : ne mettre dans les
dossiers values-mcc que celles que la version lit.
- `config_tether_apndata` : Android 9 seulement (absent du framework a partir d'Android 10).
- `config_mobile_tcp_buffers` : jusqu'a Android 12 (marque obsolete, plus lu, a partir d'Android 13).
- `config_mobile_mtu`, `config_valid_wappush_index`, `config_use_sim_language_file` : toutes les versions.
- `config_telephony_use_own_number_for_voicemail` : cle de la telephonie MediaTek, lue par aucune version de
  LineageOS (ni framework ni appli Telephone) : jamais reprise.
- `config_tether_*_regexs` : framework jusqu'a Android 10 ; module Tethering a partir d'Android 11
  (overlay-rro/LibreHUTetheringOverlay). `config_wifi_background_scan_support` : framework jusqu'a Android 10,
  com.android.wifi.resources ensuite (overlay-rro/LibreHUWifiOverlay).


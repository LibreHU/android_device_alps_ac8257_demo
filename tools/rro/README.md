# RRO tools

Static readers for the stock vendor's `framework-res__auto_generated_rro.apk` (MediaTek runtime resource overlay),
which the ROM zip removes. Nothing in the APK is run.

- `arsc_dump.py resources.arsc`: prints every entry (type/name, configuration qualifiers, value).
- `rro_to_overlay.py resources.arsc <res dir> <key,key...> [skip=qualifier:key,...]`: writes the chosen per-carrier
  entries as `values-mcc*/config.xml` files of a device overlay.

`overlay/frameworks/base/core/res/res/values-mcc*/` was made with:

    python3 -I tools/rro/rro_to_overlay.py resources.arsc overlay/frameworks/base/core/res/res \
        config_tether_apndata,config_mobile_mtu,config_mobile_tcp_buffers,config_valid_wappush_index,config_telephony_use_own_number_for_voicemail,config_use_sim_language_file \
        skip=mcc310-mnc410:config_mobile_mtu,mcc334-mnc20:config_use_sim_language_file,mcc310-mnc00:config_telephony_use_own_number_for_voicemail,mcc310-mnc00:config_valid_wappush_index

Skipped: entries LineageOS already has (identical, or AOSP's AT&T MTU 1410 kept over MediaTek's 1430) and the
`mnc00` entries of mcc 310 (no real carrier).

#
# Copyright (C) 2026 The LineageOS Project
# Copyright (C) 2026 LibreHU
#
# SPDX-License-Identifier: Apache-2.0
#

LOCAL_PATH := device/alps/ac8257_demo

# Lance avec Android 9 (ro.product.first_api_level=28) : Treble complet, vendor stock
PRODUCT_SHIPPING_API_LEVEL := 28

# Ecran 1280 x 720 (wm size du stock), 160 dpi
PRODUCT_AAPT_CONFIG := normal
PRODUCT_AAPT_PREF_CONFIG := mdpi
PRODUCT_CHARACTERISTICS := tablet

# Overlays (barre de navigation, pas de batterie, pas de capteur de lumiere)
DEVICE_PACKAGE_OVERLAYS += $(LOCAL_PATH)/overlay

# Proprietes reprises du system stock.
# qemu.hw.mainkeys : 1 sur le stock (barre et menu flottant Jancar) ; 0 ici, LineageOS sans les applis Jancar a
# besoin de sa barre de navigation.
PRODUCT_PROPERTY_OVERRIDES += \
    ro.sf.lcd_density=160 \
    dalvik.vm.heapgrowthlimit=256m \
    dalvik.vm.heapsize=512m \
    ro.zygote.preload.enable=0 \
    ro.telephony.default_network=9,9 \
    qemu.hw.mainkeys=0

# MCU Jancar : PC_READY des le demarrage (sans lui le MCU coupe le SoC), voir mcu_ready/
PRODUCT_PACKAGES += \
    mcu_ready

# Applis LibreHU dans /system/app (service, launcher, OTA, telephone, FM, widgets, touches au volant, sources,
# CD / DVD, outils MCU, Android Auto, CarPlay), ViPER4Android dans /system/priv-app (APK de librehu/fetch_apks.sh ; un APK
# absent est ignore). Le pilote ViPERFX_RE est ajoute a l'image vendor par tools/vendor_add_viper.sh.
PRODUCT_PACKAGES += \
    $(foreach app,LibreHUService LibreHULauncher LibreHUOTA LibreHUViPER LibreHUDialer LibreHUFM LibreHUWidgets \
        LibreHUBtnRemap LibreHUEasySource LibreHUDisc LibreHUMcuTools LibreHUAndroidAuto LibreHUCarPlay,\
        $(if $(wildcard $(LOCAL_PATH)/librehu/$(app).apk),$(app)))

# Proprietaires cote system (interfaces HIDL Autochips / MediaTek, voir proprietary-files.txt)
$(call inherit-product-if-exists, vendor/jancar/ac8257_demo/ac8257_demo-vendor.mk)

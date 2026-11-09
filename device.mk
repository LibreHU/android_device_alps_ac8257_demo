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

# Fluidite des applis LibreHU (Jetpack Compose) : sans code natif, Android 9 les fait tourner en interprete / JIT, et
# la compilation de fond n'a lieu qu'appareil inactif et en charge (presque jamais sur un autoradio). Installations
# et mises a jour (LibreHU Apps) compilees en speed ; applis de la ROM precompilees en speed a la construction.
PRODUCT_PROPERTY_OVERRIDES += \
    pm.dexopt.install=speed

# Journaux persistants a chaque build : logcatd ecrit tous les tampons de logcat dans /data/misc/logd/ (fichiers de
# 1 Mio, 256 au plus), a lire apres un plantage ou un redemarrage (adb, LibreHU Helper). logpersist.start (logcatd et
# son logcatd.rc) n'est mis par AOSP que dans PRODUCT_PACKAGES_DEBUG : ajoute ici pour toutes les variantes.
PRODUCT_PROPERTY_OVERRIDES += \
    persist.logd.logpersistd=logcatd
PRODUCT_PACKAGES += \
    logpersist.start

# Valeurs persist du stock qu'un /data vide n'a pas (getprop du stock, rapport LibreHU Helper) : ECNR des appels active
# (la propriete vendor que lit le HAL audio suit, voir rootdir/etc/init/librehu.rc) ; identifiant de puce connsys du
# Wi-Fi pose par le meme fichier.
PRODUCT_PROPERTY_OVERRIDES += \
    persist.audiohal.third_ecnr_lib.enable=1
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/etc/init/librehu.rc:$(TARGET_COPY_OUT_SYSTEM)/etc/init/librehu.rc

# MCU Jancar : PC_READY des le demarrage (sans lui le MCU coupe le SoC), voir mcu_ready/
PRODUCT_PACKAGES += \
    mcu_ready

# Applis LibreHU dans /system/priv-app (service, launcher, OTA, ViPER4Android, telephone, FM, widgets, touches au
# volant, sources, CD / DVD, outils MCU, Android Auto, CarPlay), avec la liste blanche de leurs permissions privilegiees
# (librehu/privapp-permissions-librehu.xml ; APK de librehu/fetch_apks.sh, qui la verifie ; un APK absent est ignore). Le pilote ViPERFX_RE est ajoute a l'image vendor par tools/vendor_add_viper.sh.
PRODUCT_PACKAGES += \
    $(foreach app,LibreHUService LibreHULauncher LibreHUOTA LibreHUViPER LibreHUDialer LibreHUFM LibreHUWidgets \
        LibreHUBtnRemap LibreHUEasySource LibreHUDisc LibreHUMcuTools LibreHUAndroidAuto LibreHUCarPlay,\
        $(if $(wildcard $(LOCAL_PATH)/librehu/$(app).apk),$(app)))

# Gestionnaire KernelSU Next (root du noyau LibreHU, indispensable a LibreHU-service) : installe dans /data/app au
# premier demarrage, seul endroit ou le noyau le reconnait (librehu/ksunext/ ; APK de librehu/fetch_apks.sh).
PRODUCT_PACKAGES += \
    $(if $(wildcard $(LOCAL_PATH)/librehu/ksunext/KernelSUNext.apk),librehu_ksunext)

# Precompilation speed (code natif complet) de ces applis a la construction de la ROM (dexpreopt d'Android 9).
PRODUCT_DEXPREOPT_SPEED_APPS += \
    LibreHUService LibreHULauncher LibreHUOTA LibreHUViPER LibreHUDialer LibreHUFM LibreHUWidgets \
    LibreHUBtnRemap LibreHUEasySource LibreHUDisc LibreHUMcuTools LibreHUAndroidAuto LibreHUCarPlay

# Proprietaires cote system (interfaces HIDL Autochips / MediaTek, autochips.jar ; voir proprietary-files.txt)
$(call inherit-product-if-exists, vendor/jancar/ac8257_demo/ac8257_demo-vendor.mk)

# autochips.jar dans le BOOTCLASSPATH comme sur le stock (AtcMetazone, AtcLogo, BackCar, LocalBluetoothManager...,
# utilises par LibreHU-service) ; module du depot vendor
PRODUCT_BOOT_JARS += autochips

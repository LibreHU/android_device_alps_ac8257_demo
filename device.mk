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
# Animation de demarrage de LineageOS a la taille de l'ecran (sans ces valeurs : 1080 x 1920, portrait,
# vendor/lineage/bootanimation/Android.mk).
TARGET_SCREEN_WIDTH := 1280
TARGET_SCREEN_HEIGHT := 720
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

# Proprietes que le build met dans le default.prop du vendor (PRODUCT_DEFAULT_PROPERTY_OVERRIDES avec
# BOARD_PROPERTY_OVERRIDES_SPLIT_ENABLED), donc jamais installees ici puisque le vendor est l'image stock : celui-ci
# les a (getprop du stock : ro.zygote=zygote64_32, ro.vndk.version=28). Reprises cote system par securite, memes
# valeurs : sans ro.zygote, init.rc n'importe pas init.zygote64_32.rc et zygote ne demarre pas ; sans ro.vndk.version,
# le linker ne prend pas ld.config.28.txt. Si le vendor les pose aussi, sa valeur est ignoree (ro.* deja posee).
PRODUCT_SYSTEM_DEFAULT_PROPERTIES += \
    ro.zygote=zygote64_32 \
    ro.vndk.version=28

# Dossier des rc du vendor (getprop du stock : /vendor/etc/init/hw/), absent des deux build.prop du stock donc venu
# d'un default.prop : init.ac8257.rc du vendor importe ${ro.vendor.rc}init.connectivity.rc (wpa_supplicant, mnld),
# init.modem.rc, init.ago.rc, init.volte.rc, init.mal.rc, et l'import est developpe a la lecture des rc, quand seuls
# prop.default et /vendor/default.prop sont charges. Sans la valeur : plus de Wi-Fi ni de GPS. Meme valeur que le stock,
# sans effet si le vendor la pose aussi (ro.* : la premiere gagne, prop.default est lu en premier).
PRODUCT_SYSTEM_DEFAULT_PROPERTIES += \
    ro.vendor.rc=/vendor/etc/init/hw/

# adb a chaque demarrage, quoi que pose le default.prop du vendor (contenu inconnu, charge apres prop.default) :
# build.prop du system est lu apres lui (init/property_service.cpp : property_load_boot_defaults puis
# load_system_props), et l'init de LineageOS 16.0 n'ajoute plus « adb » de lui-meme (update_sys_usb_config seulement
# une fois les proprietes de /data chargees). Valeur du stock.
PRODUCT_PROPERTY_OVERRIDES += \
    persist.sys.usb.config=adb

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

# Dalle 720 x 1280 (portrait) montee en paysage : le stock la tourne avec persist.sf.hwrotation=90 (SurfaceFlinger de
# MediaTek). Ici SurfaceFlinger et l'InputReader de LineageOS, corriges par tools/patch_lineage_sources.sh, lisent
# persist.librehu.display_rotation (a regler sans recompiler si l'image est a l'envers : 270), sinon cette valeur.
# Retroeclairage Jancar inverse (lcd-backlight 0 = maximum, 179 = minimum) : LightsService corrige le convertit.
PRODUCT_PROPERTY_OVERRIDES += \
    ro.librehu.display_rotation=90 \
    ro.librehu.backlight_inverted=true \
    ro.librehu.backlight_min=179

# Calibration d'usine de la dalle tactile au demarrage (librehu/touchcal), avant que LibreHU-service ait le root.
PRODUCT_PACKAGES += \
    librehu_touchcal

# Root de KernelSU Next accorde d'office a toutes les applis LibreHU (librehu/ksugrant : org.librehu.* et ViPER4Android) :
# KernelSU n'affiche pas de demande, une appli sans profil est refusee en silence. LibreHU-service : tactile, boutons,
# passage de main de l'ARM2 (video verte) et reglages du service sans passer par le gestionnaire. Un choix de
# l'utilisateur dans le gestionnaire (refus compris) n'est jamais modifie.
PRODUCT_PACKAGES += \
    librehu_ksugrant

# Pays du Wi-Fi d'apres la langue choisie a l'installation (librehu/boot/librehu_wificountry.sh) ; sans pays dans la
# langue, celui du stock. Sans pays, le pilote Wi-Fi MediaTek scanne zero canal et finit par planter le noyau.
PRODUCT_PROPERTY_OVERRIDES += \
    ro.librehu.wificountry_default=CN

# Pas d'ecran de verrouillage (aussi def_lockscreen_disabled dans l'overlay de SettingsProvider) : lu par
# SettingsProvider a la creation de ses reglages (DatabaseHelper, ro.lockscreen.disable.default).
PRODUCT_PROPERTY_OVERRIDES += \
    ro.lockscreen.disable.default=true
PRODUCT_PACKAGES += \
    librehu_wificountry

# Ethernet (adaptateurs USB RTL8152/8153, ASIX..., pilotes integres au noyau LibreHU) : sans la fonctionnalite
# android.hardware.ethernet (le system stock la declarait, celui de LineageOS rien), le service Ethernet d'Android
# n'est lance que si l'hote USB est declare, et l'interface eth0 n'est pas prise comme reseau.
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.ethernet.xml:$(TARGET_COPY_OUT_SYSTEM)/etc/permissions/android.hardware.ethernet.xml

# Impression : sans la fonctionnalite android.software.print (le fichier de fonctionnalites du vendor stock ne la
# declare pas), PrintManagerService ne demarre pas et les Parametres d'Android 9 plantent a l'ouverture de « Appareils
# connectes » (et donc du Bluetooth) : PrintSettingPreferenceController.onStart appelle addPrintJobStateChangeListener
# sur un PrintManager nul (journal du 14/11/2026, « Feature android.software.print not available »). PrintSpooler est
# deja dans LineageOS (build/make/target/product/core.mk).
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.software.print.xml:$(TARGET_COPY_OUT_SYSTEM)/etc/permissions/android.software.print.xml

# Valeurs persist du stock qu'un /data vide n'a pas (getprop du stock, rapport LibreHU Helper) : ECNR des appels active
# (la propriete vendor que lit le HAL audio suit, voir rootdir/etc/init/librehu.rc) ; identifiant de puce connsys du
# Wi-Fi pose par le meme fichier.
PRODUCT_PROPERTY_OVERRIDES += \
    persist.audiohal.third_ecnr_lib.enable=1
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/etc/init/librehu.rc:$(TARGET_COPY_OUT_SYSTEM)/etc/init/librehu.rc

# Droits des noeuds Autochips que le system stock posait (rootdir/ueventd.ac8257.rc : /dev/backcardrv du HAL backcar,
# sans lequel la video materielle reste verte). Racine du system (system-as-root : build_image.py y copie root/).
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/ueventd.ac8257.rc:root/ueventd.ac8257.rc

# MCU Jancar : PC_READY des le demarrage (sans lui le MCU coupe le SoC), voir mcu_ready/
PRODUCT_PACKAGES += \
    mcu_ready

# Applis LibreHU dans /system/priv-app (service, launcher, OTA, ViPER4Android, telephone, FM, widgets, touches au
# volant, sources, CD / DVD, Android Auto, CarPlay), avec la liste blanche de leurs permissions privilegiees
# (librehu/privapp-permissions-librehu.xml ; APK de librehu/fetch_apks.sh, qui la verifie ; un APK absent est ignore). Le pilote ViPERFX_RE est ajoute a l'image vendor par tools/vendor_add_viper.sh.
# LibreHU Helper et Aurora Store sont installes comme applis ordinaires au premier demarrage (librehu/userapps,
# librehu_ksunext ci-dessous) ; MCU Toolkit n'est plus dans la ROM (13/11/2026).
PRODUCT_PACKAGES += \
    $(foreach app,LibreHUService LibreHULauncher LibreHUOTA LibreHUViPER LibreHUDialer LibreHUFM LibreHUWidgets \
        LibreHUBtnRemap LibreHUEasySource LibreHUDisc LibreHUAndroidAuto LibreHUCarPlay,\
        $(if $(wildcard $(LOCAL_PATH)/librehu/$(app).apk),$(app)))

# Applis aux bibliotheques natives compressees (librehu/native_libs.py, installees telles quelles par
# librehu/Android.mk) : leurs bibliotheques extraites dans /system/priv-app/<appli>/lib/<isa>/, la ou Android 9 les
# cherche pour une appli systeme (il ne les extrait pas lui-meme).
librehu_lib_isa = $(notdir $(patsubst %/,%,$(dir $(1))))
librehu_lib_app = $(patsubst %-lib,%,$(notdir $(patsubst %/,%,$(dir $(patsubst %/,%,$(dir $(1)))))))
PRODUCT_COPY_FILES += \
    $(foreach f,$(wildcard $(LOCAL_PATH)/librehu/*-lib/*/*.so),\
        $(f):$(TARGET_COPY_OUT_SYSTEM)/priv-app/$(call librehu_lib_app,$(f))/lib/$(call librehu_lib_isa,$(f))/$(notdir $(f)))

# Gestionnaire KernelSU Next (root du noyau LibreHU, indispensable a LibreHU-service) : installe dans /data/app au
# premier demarrage, seul endroit ou le noyau le reconnait (librehu/ksunext/ ; APK de librehu/fetch_apks.sh).
PRODUCT_PACKAGES += \
    $(if $(wildcard $(LOCAL_PATH)/librehu/ksunext/KernelSUNext.apk),librehu_ksunext)

# Precompilation speed (code natif complet) de ces applis a la construction de la ROM (dexpreopt d'Android 9).
PRODUCT_DEXPREOPT_SPEED_APPS += \
    LibreHUService LibreHULauncher LibreHUOTA LibreHUViPER LibreHUDialer LibreHUFM LibreHUWidgets \
    LibreHUBtnRemap LibreHUEasySource LibreHUDisc LibreHUAndroidAuto LibreHUCarPlay

# Proprietaires cote system (interfaces HIDL Autochips / MediaTek, autochips.jar ; voir proprietary-files.txt)
$(call inherit-product-if-exists, vendor/jancar/ac8257_demo/ac8257_demo-vendor.mk)

# autochips.jar dans le BOOTCLASSPATH comme sur le stock (AtcMetazone, AtcLogo, BackCar, LocalBluetoothManager...,
# utilises par LibreHU-service) ; module du depot vendor
PRODUCT_BOOT_JARS += autochips

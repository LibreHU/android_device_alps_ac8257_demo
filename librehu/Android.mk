#
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Applis LibreHU integrees a /system/priv-app (APK telecharges par fetch_apks.sh, signature d'origine gardee).
# Un APK absent est simplement ignore : la ROM se construit sans lui.
# Toutes privilegiees, comme LibreHU-service le demande (README du service : SET_TIME, Bluetooth, demarrage fiable) :
# leurs permissions privilegiees d'Android 9 sont dans privapp-permissions-librehu.xml ; check_privapp.py le verifie
# pour chaque APK telecharge. LineageOS impose ro.control_privapp_permissions=enforce (une permission absente de la
# liste ferait planter system_server au demarrage) ; lineage_ac8257_demo.mk remet « log » comme le stock : un oubli
# n'est alors qu'un avertissement dans logcat.
# Precompiles a la construction (dexpreopt, filtre speed via PRODUCT_DEXPREOPT_SPEED_APPS de device.mk) sans retirer
# le dex de l'APK (nostripping) : la signature d'origine reste valable et une mise a jour dans /data s'installe.
#

LOCAL_PATH := $(call my-dir)

LIBREHU_APPS := LibreHUService LibreHULauncher LibreHUOTA LibreHUViPER LibreHUDialer LibreHUFM LibreHUWidgets \
    LibreHUBtnRemap LibreHUEasySource LibreHUDisc LibreHUAndroidAuto LibreHUCarPlay

# $(1) : nom du module (= nom de l'APK), $(2) : paquets remplaces
# Bibliotheques natives (native_libs.py, lance par fetch_apks.sh) :
#  - $(1).raw : bibliotheques compressees dans l'APK. Le build de LineageOS 16.0 recompresserait alors l'APK
#    (core/prebuilt_internal.mk, uncompress-shared-libs), ce qui retire sa signature v2 : PackageManager le refuserait.
#    L'APK est donc installe tel quel (module ETC dans /system/priv-app/$(1)/, sans dexpreopt : Android le compile au
#    premier demarrage) et device.mk copie ses bibliotheques extraites dans /system/priv-app/$(1)/lib/<isa>/, la ou
#    Android 9 les cherche pour une appli systeme (il ne les extrait jamais lui-meme). Cas d'Android Auto.
#  - $(1).abi32 : bibliotheques 32 bits seulement (FM) : LOCAL_MULTILIB := 32, precompile pour arm (sinon pour
#    arm64, alors que l'appli tourne en 32 bits).
define librehu-priv-app
ifneq ($$(wildcard $$(LOCAL_PATH)/$(1).apk),)
include $$(CLEAR_VARS)
LOCAL_MODULE := $(1)
LOCAL_SRC_FILES := $(1).apk
LOCAL_REQUIRED_MODULES := privapp-permissions-librehu.xml
ifneq ($$(wildcard $$(LOCAL_PATH)/$(1).raw),)
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_SUFFIX := .apk
LOCAL_MODULE_PATH := $$(TARGET_OUT)/priv-app/$(1)
else
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_SUFFIX := $$(COMMON_ANDROID_PACKAGE_SUFFIX)
LOCAL_CERTIFICATE := PRESIGNED
LOCAL_DEX_PREOPT := nostripping
LOCAL_PRIVILEGED_MODULE := true
LOCAL_OVERRIDES_PACKAGES := $(2)
ifneq ($$(wildcard $$(LOCAL_PATH)/$(1).abi32),)
LOCAL_MULTILIB := 32
endif
endif
include $$(BUILD_PREBUILT)
endif
endef

# LibreHU Launcher : ecran d'accueil ; Trebuchet (lanceur de LineageOS) reste en secours : si LibreHU Launcher plantait
# au demarrage, sans autre ecran d'accueil l'animation de demarrage ne finirait jamais (elle s'arrete quand un ecran
# d'accueil s'affiche). Au premier demarrage Android demande lequel garder : choisir LibreHU Launcher, « Toujours ».
$(eval $(call librehu-priv-app,LibreHULauncher,Launcher3 Launcher3QuickStep))
$(foreach app,$(filter-out LibreHULauncher,$(LIBREHU_APPS)),$(eval $(call librehu-priv-app,$(app),)))

include $(CLEAR_VARS)
LOCAL_MODULE := privapp-permissions-librehu.xml
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_RELATIVE_PATH := permissions
LOCAL_SRC_FILES := privapp-permissions-librehu.xml
include $(BUILD_PREBUILT)

# Gestionnaire KernelSU Next (APK de fetch_apks.sh, version de l'API du noyau LibreHU) : pas une appli systeme, le
# noyau ne reconnait son gestionnaire que dans /data/app. L'APK est garde dans /system/etc/librehu et
# librehu_ksunext l'installe dans /data/app au demarrage s'il n'y est pas (ksunext/).
ifneq ($(wildcard $(LOCAL_PATH)/ksunext/KernelSUNext.apk),)
include $(CLEAR_VARS)
LOCAL_MODULE := KernelSUNext.apk
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_RELATIVE_PATH := librehu
LOCAL_SRC_FILES := ksunext/KernelSUNext.apk
include $(BUILD_PREBUILT)

# Applis ordinaires installees dans /data/app au premier demarrage (userapps/ : LibreHU Helper, Aurora Store), par le
# meme script que le gestionnaire KernelSU Next
LIBREHU_USERAPPS := $(foreach a,LibreHUHelper AuroraStore,$(if $(wildcard $(LOCAL_PATH)/userapps/$(a).apk),$(a).apk))
define librehu-user-apk
include $$(CLEAR_VARS)
LOCAL_MODULE := $(1)
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_RELATIVE_PATH := librehu
LOCAL_SRC_FILES := userapps/$(1)
include $$(BUILD_PREBUILT)
endef
$(foreach a,$(LIBREHU_USERAPPS),$(eval $(call librehu-user-apk,$(a))))

include $(CLEAR_VARS)
LOCAL_MODULE := librehu_ksunext
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_PATH := $(TARGET_OUT_EXECUTABLES)
LOCAL_SRC_FILES := ksunext/librehu_ksunext.sh
LOCAL_INIT_RC := ksunext/librehu_ksunext.rc
LOCAL_REQUIRED_MODULES := KernelSUNext.apk $(LIBREHU_USERAPPS)
include $(BUILD_PREBUILT)
endif

# Calibration d'usine de la dalle tactile au demarrage (touchcal/) : LibreHU-service ne l'ecrit qu'avec le root de
# KernelSU, pas encore accorde au premier demarrage ; sans elle le tactile tombe hors de l'ecran.
include $(CLEAR_VARS)
LOCAL_MODULE := librehu_touchcal
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_PATH := $(TARGET_OUT_EXECUTABLES)
LOCAL_SRC_FILES := touchcal/librehu_touchcal.sh
LOCAL_INIT_RC := touchcal/librehu_touchcal.rc
include $(BUILD_PREBUILT)

# Root de KernelSU Next accorde a LibreHU-service au premier demarrage (ksugrant/), sans passer par le gestionnaire
include $(CLEAR_VARS)
LOCAL_MODULE := librehu_ksugrant
LOCAL_SRC_FILES := ksugrant/librehu_ksugrant.c
LOCAL_SHARED_LIBRARIES := liblog
LOCAL_CFLAGS := -Wall -Werror
LOCAL_INIT_RC := ksugrant/librehu_ksugrant.rc
include $(BUILD_EXECUTABLE)

# Pays du Wi-Fi d'apres la langue choisie a l'installation de LineageOS (boot/)
include $(CLEAR_VARS)
LOCAL_MODULE := librehu_wificountry
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_PATH := $(TARGET_OUT_EXECUTABLES)
LOCAL_SRC_FILES := boot/librehu_wificountry.sh
LOCAL_INIT_RC := boot/librehu_wificountry.rc
include $(BUILD_PREBUILT)

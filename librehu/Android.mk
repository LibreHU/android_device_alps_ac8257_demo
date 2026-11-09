#
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Applis LibreHU integrees a /system/priv-app (APK telecharges par fetch_apks.sh, signature d'origine gardee).
# Un APK absent est simplement ignore : la ROM se construit sans lui.
# Toutes privilegiees, comme LibreHU-service le demande (README du service : SET_TIME, Bluetooth, demarrage fiable) :
# leurs permissions privilegiees d'Android 9 sont dans privapp-permissions-librehu.xml (LineageOS impose
# ro.control_privapp_permissions=enforce : une permission absente de la liste fait planter system_server au
# demarrage) ; check_privapp.py le verifie pour chaque APK telecharge.
# Precompiles a la construction (dexpreopt, filtre speed via PRODUCT_DEXPREOPT_SPEED_APPS de device.mk) sans retirer
# le dex de l'APK (nostripping) : la signature d'origine reste valable et une mise a jour dans /data s'installe.
#

LOCAL_PATH := $(call my-dir)

LIBREHU_APPS := LibreHUService LibreHULauncher LibreHUOTA LibreHUViPER LibreHUDialer LibreHUFM LibreHUWidgets \
    LibreHUBtnRemap LibreHUEasySource LibreHUDisc LibreHUMcuTools LibreHUAndroidAuto LibreHUCarPlay

# $(1) : nom du module (= nom de l'APK), $(2) : paquets remplaces
define librehu-priv-app
ifneq ($$(wildcard $$(LOCAL_PATH)/$(1).apk),)
include $$(CLEAR_VARS)
LOCAL_MODULE := $(1)
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_SUFFIX := $$(COMMON_ANDROID_PACKAGE_SUFFIX)
LOCAL_SRC_FILES := $(1).apk
LOCAL_CERTIFICATE := PRESIGNED
LOCAL_DEX_PREOPT := nostripping
LOCAL_PRIVILEGED_MODULE := true
LOCAL_OVERRIDES_PACKAGES := $(2)
LOCAL_REQUIRED_MODULES := privapp-permissions-librehu.xml
include $$(BUILD_PREBUILT)
endif
endef

# LibreHU Launcher : seul ecran d'accueil, remplace Trebuchet
$(eval $(call librehu-priv-app,LibreHULauncher,Launcher3 Launcher3QuickStep TrebuchetQuickStep))
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

include $(CLEAR_VARS)
LOCAL_MODULE := librehu_ksunext
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_PATH := $(TARGET_OUT_EXECUTABLES)
LOCAL_SRC_FILES := ksunext/librehu_ksunext.sh
LOCAL_INIT_RC := ksunext/librehu_ksunext.rc
LOCAL_REQUIRED_MODULES := KernelSUNext.apk
include $(BUILD_PREBUILT)
endif

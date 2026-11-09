/*
 * Copyright (C) 2026 LibreHU
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Reglages de compilation de la pile Bluetooth (system/bt) pour un autoradio, lus grace a
 * BOARD_BLUETOOTH_BDROID_BUILDCFG_INCLUDE_DIR (BoardConfig.mk ; system/bt/build/fluoride.go : -DHAS_BDROID_BUILDCFG).
 * Les valeurs absentes gardent celles de system/bt/internal_include/bt_target.h.
 */

#ifndef _BDROID_BUILDCFG_H
#define _BDROID_BUILDCFG_H

/*
 * Classe d'appareil (Class of Device) annoncee aux telephones : l'autoradio se declare comme une voiture.
 * {SERVICE_CLASS, MAJOR_CLASS, MINOR_CLASS}, meme format que la valeur par defaut de bt_target.h
 * ({0x5A, 0x02, 0x0C} = smartphone) :
 *   SERVICE_CLASS 0x24 : bit 21 Audio + bit 18 Rendering (le haut-parleur de la voiture)
 *   MAJOR_CLASS   0x04 : Audio/Video
 *   MINOR_CLASS   0x20 : Car audio (valeur 0b001000 des Bluetooth Assigned Numbers, dans les bits 7-2)
 * soit 0x240420. Appliquee a l'activation du Bluetooth (bta_dm_act.cc, BTM_SetDeviceClass) ; le reglage
 * Settings.Global.bluetooth_class_of_device, s'il est pose, passe avant.
 */
#define BTA_DM_COD \
  { 0x24, 0x04, 0x20 }

/*
 * A2DP sink : la musique du telephone jouee par l'autoradio. Sans lui (FALSE par defaut dans bt_target.h), la pile
 * ne publie pas l'enregistrement SDP « Audio Sink » (bta/av/bta_av_main.cc) et le telephone ne voit pas l'autoradio
 * comme une enceinte. Le role A2DP source est coupe dans overlay/packages/apps/Bluetooth (les deux ne vont pas
 * ensemble dans le Bluetooth d'Android 9).
 */
#define BTA_AV_SINK_INCLUDED TRUE

#endif

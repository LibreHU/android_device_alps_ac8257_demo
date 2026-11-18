/*
 * Copyright (C) 2026 LibreHU
 * SPDX-License-Identifier: Apache-2.0
 *
 * LDAC sink for LineageOS 17.1 (Android 10). The Bluetooth stack already decodes LDAC as an A2DP sink
 * (system/bt stack/a2dp/a2dp_vendor_ldac_decoder.cc): it dlopen()s "libldacBT_dec.so" and needs nine functions of
 * Sony's decoder API, a library Sony never published. libldacdec (reverse-engineered, built with this file) has four
 * of them; this file adds the five others and wraps ldacBT_decode() for the way the stack calls it:
 *
 *  - an error must be a negative return, then a code packed as Sony's (API error << 20) by ldacBT_get_error_code():
 *    the stack tests LDACBT_ERROR(ret) and, on LDACBT_FATAL(code), drops the rest of the packet. libldacdec returned
 *    its raw codes (516...), seen by the stack as success: it then advanced by an undefined used_bytes;
 *  - a frame is checked before it is decoded (sync word 0xAA, sampling rate and channel fields in range, whole frame
 *    inside the packet) and decoded from a zero-padded copy, so a corrupt or cut packet is never read past its end
 *    (libldacdec reads its bit stream without bounds).
 */

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "ldacdec.h"
#include "libldacBT_dec.h"

/* libldacdec's own ldacBT_decode(), renamed at compile time (Android.bp: -DldacBT_decode=...) */
int libldacdec_decode_frame(HANDLE_LDAC_BT hLdacBT, uchar *p_stream, void *p_pcm, LDACBT_SMPL_FMT_T fmt,
                            int stream_sz, int *used_bytes, int *pcm_sz);

/* Sony's codes (external/libldac inc/ldacBT.h): API error in bits 20-31, LDACBT_FATAL() from 256 */
#define LHU_ERR_FATAL 256
#define LHU_ERR_ILL_SMPL_FORMAT 517
#define LHU_ERR_ILL_PARAM 518
#define LHU_PACK_API_ERR(e) ((e) << 20)

/* ldacBT_get_version(): version 2.0.2 in Sony's encoding (major << 16 | minor << 8 | patch) */
#define LHU_LDAC_VERSION 0x020002

/* LDAC frame: sync byte, then 3 bits sampling rate, 2 bits channel configuration, 9 bits length - 1, 2 bits status */
#define LHU_FRAME_HEADER 3
#define LHU_FRAME_MAX (512 + LHU_FRAME_HEADER)
/* the bit reader may run a little past a corrupt frame: zeros there, never memory of the stack */
#define LHU_FRAME_PAD 2048

static const int lhu_rates[] = {44100, 48000, 88200, 96000};

static int lhu_fail(HANDLE_LDAC_BT h, int api_err, int *used_bytes, int stream_sz, int *pcm_sz)
{
    if (used_bytes != NULL)
        *used_bytes = stream_sz > 0 ? stream_sz : 0;
    if (pcm_sz != NULL)
        *pcm_sz = 0;
    if (h != NULL)
        h->error_code_api = LHU_PACK_API_ERR(api_err);
    return -1;
}

int ldacBT_decode(HANDLE_LDAC_BT h, uchar *p_stream, void *p_pcm, LDACBT_SMPL_FMT_T fmt, int stream_sz,
                  int *used_bytes, int *pcm_sz)
{
    /* one A2DP sink decoder thread at a time in the stack */
    static uchar frame[LHU_FRAME_MAX + LHU_FRAME_PAD];
    int used = 0, wrote = 0;

    if (h == NULL || h->hLDAC == NULL || p_stream == NULL || p_pcm == NULL || used_bytes == NULL || pcm_sz == NULL)
        return lhu_fail(h, LHU_ERR_ILL_PARAM, used_bytes, stream_sz, pcm_sz);
    if (fmt != LDACBT_SMPL_FMT_S16 && fmt != LDACBT_SMPL_FMT_S32 && fmt != LDACBT_SMPL_FMT_F32)
        return lhu_fail(h, LHU_ERR_ILL_SMPL_FORMAT, used_bytes, stream_sz, pcm_sz);
    if (stream_sz < LHU_FRAME_HEADER || p_stream[0] != 0xAA)
        return lhu_fail(h, LHU_ERR_FATAL, used_bytes, stream_sz, pcm_sz);

    const int rate_id = p_stream[1] >> 5;
    const int channel_id = (p_stream[1] >> 3) & 0x03;
    const int length = (((p_stream[1] & 0x07) << 6) | (p_stream[2] >> 2)) + 1;
    const int total = length + LHU_FRAME_HEADER;
    if (rate_id > 3 || channel_id > 2 || total > stream_sz)
        return lhu_fail(h, LHU_ERR_FATAL, used_bytes, stream_sz, pcm_sz);

    memcpy(frame, p_stream, (size_t)total);
    memset(frame + total, 0, sizeof(frame) - (size_t)total);
    ((ldacdec_t *)h->hLDAC)->streamSize = (unsigned int)total;
    int ret = libldacdec_decode_frame(h, frame, p_pcm, fmt, total, &used, &wrote);
    if (ret != 0)
        return lhu_fail(h, LHU_ERR_FATAL, used_bytes, stream_sz, pcm_sz);

    *used_bytes = total;
    *pcm_sz = wrote;
    h->error_code_api = 0;
    return 0;
}

void ldacBT_close_handle(HANDLE_LDAC_BT h)
{
    /* nothing to release before ldacBT_free_handle(); the next ldacBT_init_handle_decode() starts over */
    if (h != NULL)
        h->error_code_api = 0;
}

int ldacBT_get_version(void)
{
    return LHU_LDAC_VERSION;
}

int ldacBT_get_sampling_freq(HANDLE_LDAC_BT h)
{
    if (h == NULL || h->hLDAC == NULL)
        return -1;
    const ldacdec_t *dec = (const ldacdec_t *)h->hLDAC;
    if (dec->frame.sampleRateId < 0 || dec->frame.sampleRateId > 3)
        return -1;
    return lhu_rates[dec->frame.sampleRateId];
}

int ldacBT_get_bitrate(HANDLE_LDAC_BT h)
{
    if (h == NULL || h->hLDAC == NULL)
        return -1;
    const ldacdec_t *dec = (const ldacdec_t *)h->hLDAC;
    if (dec->frame.sampleRateId < 0 || dec->frame.sampleRateId > 3 || dec->frame.frameSamples <= 0)
        return -1;
    /* kbit/s of the last frame: bytes per frame x frames per second */
    long bits = (long)(dec->frame.frameLength + LHU_FRAME_HEADER) * 8;
    return (int)(bits * lhu_rates[dec->frame.sampleRateId] / dec->frame.frameSamples / 1000);
}

int ldacBT_get_error_code(HANDLE_LDAC_BT h)
{
    if (h == NULL)
        return LHU_PACK_API_ERR(LHU_ERR_ILL_PARAM);
    return h->error_code_api;
}

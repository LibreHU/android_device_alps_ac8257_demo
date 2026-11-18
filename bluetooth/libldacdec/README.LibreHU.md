# libldacBT_dec: LDAC for the Bluetooth music of LineageOS 17.1

The A2DP sink of Android 10 (`system/bt`, `stack/a2dp/a2dp_vendor_ldac_decoder.cc`) decodes LDAC with
`libldacBT_dec.so`, Sony's decoder library, which Sony never published (AOSP `external/libldac` has only the encoder
and the ABR). Without it the stack offers the phone AAC and SBC only. This directory builds that library.

## Sources

- **libldacdec**: reverse-engineered LDAC decoder, <https://github.com/anonymix007/libldacdec>, commit
  `c90094b15e25aef0e47c6d775fa94aceb36cabbc` (files `libldacdec.c`, `bit_allocation.*`, `bit_reader.*`,
  `huffCodes.*`, `imdct.*`, `spectrum.*`, `utility.*`, `ldacdec.h`, `libldacBT_dec.h`, `log.h`; its README is
  `README.upstream.md`). Lineage: hegdi/libldacdec, built on the ATRAC9 work of Alex Barney (LibAtrac9).
  **License**: the upstream repository has no LICENSE file; its Arch Linux package (AUR `libldacdec`) declares
  Apache-2.0. Kept under those terms, with this notice. LDAC is a technology of Sony.
- **ldacBT_dec_android.c** (LibreHU, Apache-2.0): the five functions of the API libldacdec lacks
  (`ldacBT_close_handle`, `ldacBT_get_version`, `ldacBT_get_bitrate`, `ldacBT_get_sampling_freq`,
  `ldacBT_get_error_code`) and the `ldacBT_decode()` the stack calls: frame checked before decoding, errors as Sony's
  codes (`LDACBT_ERROR` / `LDACBT_FATAL` of `ldacBT.h`).

## LibreHU changes to libldacdec (each marked "LibreHU" in the code)

- 32-bit PCM (what the stack asks for): x 2^16 instead of x 2^15 (the output was 6 dB too low) and saturated;
- the bit reader knows the frame size and reads zeros past it (a corrupt frame from a phone read past its packet);
- out-of-range values of a corrupt frame stop it or are clamped: sampling rate and channel ids, band count, gradient
  units and boundary, scale factors (0..31), fine precision (0..15); `gradient[]` sized for 50 units; no undefined
  shifts (`BitReverse32`, `SignExtend32`, `ReadOffsetBinary`).

## Tests (on a PC, 18/11/2026)

- Round trip with Sony's encoder (AOSP `external/libldac`, android10-release), packets fed as the stack does:
  44.1, 48, 88.2 and 96 kHz, quality modes HQ / SQ / MQ (990, 606 or 660, 330 kbit/s): no error, output level equal
  to the input (RMS 0.3534 for 0.3536);
- 600,000 random frames with valid headers, AddressSanitizer and UndefinedBehaviorSanitizer: no fault.

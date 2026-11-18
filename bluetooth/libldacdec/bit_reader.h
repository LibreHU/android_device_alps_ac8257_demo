#pragma once

#include <stdint.h>

typedef struct {
	const uint8_t * Buffer;
	int Position;
	/* LibreHU: bytes readable from Buffer, 0 = no limit; past it the reader returns zeros (corrupt frames from a
	   Bluetooth source must not make the A2DP sink read past its packet) */
	unsigned int Size;
} BitReaderCxt;

// Make MSVC compiler happy. Leave const in for value parameters

void InitBitReaderCxt(BitReaderCxt* br, const void * buffer);
uint32_t PeekInt(BitReaderCxt* br, const int bits);
uint32_t ReadInt(BitReaderCxt* br, const int bits);
int32_t ReadSignedInt(BitReaderCxt* br, const int bits);
int32_t ReadOffsetBinary(BitReaderCxt* br, const int bits);
void AlignPosition(BitReaderCxt* br, const unsigned int multiple);

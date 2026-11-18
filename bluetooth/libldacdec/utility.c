#include "utility.h"
#include <limits.h>

int Max(int a, int b) { return a > b ? a : b; }
int Min(int a, int b) { return a > b ? b : a; }

uint32_t BitReverse32(uint32_t value, int bitCount)
{
	/* LibreHU: no shift by 32 (undefined) for bitCount 0 */
	if (bitCount <= 0)
		return 0;
	value = ((value & 0xaaaaaaaa) >> 1) | ((value & 0x55555555) << 1);
	value = ((value & 0xcccccccc) >> 2) | ((value & 0x33333333) << 2);
	value = ((value & 0xf0f0f0f0) >> 4) | ((value & 0x0f0f0f0f) << 4);
	value = ((value & 0xff00ff00) >> 8) | ((value & 0x00ff00ff) << 8);
	value = (value >> 16) | (value << 16);
	return value >> (32 - bitCount);
}

int32_t SignExtend32(int32_t value, int bits)
{
	/* LibreHU: through unsigned (no signed overflow), 0 bits = 0 */
	if (bits <= 0)
		return 0;
	if (bits >= 32)
		return value;
	const uint32_t sign = 1u << (bits - 1);
	const uint32_t v = (uint32_t)value & ((sign << 1) - 1);
	return (int32_t)(v ^ sign) - (int32_t)sign;
}

int16_t Clamp16(int value)
{
	if (value > SHRT_MAX)
		return SHRT_MAX;
	if (value < SHRT_MIN)
		return SHRT_MIN;
	return (int16_t)value;
}

int Round(scalar x)
{
	x += 0.5;
	return (int)x - (x < (int)x);
}


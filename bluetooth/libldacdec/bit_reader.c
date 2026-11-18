#include "bit_reader.h"
#include "utility.h"

static int PeekIntFallback(BitReaderCxt* br, int bitCount);

void InitBitReaderCxt(BitReaderCxt* br, const void * buffer)
{
	br->Buffer = buffer;
	br->Position = 0;
	br->Size = 0;
}

/* LibreHU: byte [index] of the stream, 0 past its end (or for a negative position) */
static inline uint32_t ByteAt(const BitReaderCxt* br, long index)
{
	if (index < 0 || (br->Size != 0 && (unsigned long)index >= br->Size))
		return 0;
	return br->Buffer[index];
}

uint32_t ReadInt(BitReaderCxt* br, const int bits)
{
    const uint32_t value = PeekInt(br, bits);
	br->Position += bits;
	return value;
}

int32_t ReadSignedInt(BitReaderCxt* br, const int bits)
{
	const int value = PeekInt(br, bits);
	br->Position += bits;
	return SignExtend32(value, bits);
}

int ReadOffsetBinary(BitReaderCxt* br, const int bits)
{
	/* LibreHU: no shift by -1 for 0 bits */
	const int offset = bits > 0 ? 1 << (bits - 1) : 0;
	const int value = PeekInt(br, bits) - offset;
	br->Position += bits;
	return value;
}

uint32_t PeekInt(BitReaderCxt* br, const int bits)
{
	/* LibreHU: bounded byte reads (ByteAt), no shift by 32 or more: 0 to 32 bits */
	if (bits <= 0)
		return 0;
	if (bits > 25)
		return (uint32_t)PeekIntFallback(br, bits > 32 ? 32 : bits);

	const long byteIndex = br->Position / 8;
	const unsigned int bitIndex = (unsigned int)(br->Position % 8);
	const uint32_t value = ByteAt(br, byteIndex) << 24 | ByteAt(br, byteIndex + 1) << 16
		| ByteAt(br, byteIndex + 2) << 8 | ByteAt(br, byteIndex + 3);
	/* the 32 bits from the byte of the position: drop the bits before it, keep [bits] */
	return (uint32_t)((uint64_t)value << bitIndex >> (32 - bits)) & (uint32_t)((1ULL << bits) - 1);
}

void AlignPosition(BitReaderCxt* br, const unsigned int multiple)
{
	const int position = br->Position;
	if (position % multiple == 0)
	{
		return;
	}

	br->Position = position + multiple - position % multiple;
}

static int PeekIntFallback(BitReaderCxt* br, int bitCount)
{
	uint32_t value = 0;
	long byteIndex = br->Position / 8;
	int bitIndex = br->Position % 8;

	while (bitCount > 0)
	{
		if (bitIndex >= 8)
		{
			bitIndex = 0;
			byteIndex++;
		}

		int bitsToRead = bitCount;
		if (bitsToRead > 8 - bitIndex)
		{
			bitsToRead = 8 - bitIndex;
		}

		const uint32_t mask = 0xFFu >> bitIndex;
		const uint32_t currentByte = (mask & ByteAt(br, byteIndex)) >> (8 - bitIndex - bitsToRead);

		value = (uint32_t)((uint64_t)value << bitsToRead) | currentByte;
		bitIndex += bitsToRead;
		bitCount -= bitsToRead;
	}
	return (int)value;
}

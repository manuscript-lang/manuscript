/* base/sha256.h: the SHA-256 digest of a byte range, written as lowercase hexadecimal. */
#ifndef MS_BASE_SHA256_H
#define MS_BASE_SHA256_H

#include "base/safe.h"

#define MS_SHA256_HEX_LEN 64

/* Writes the 64 hexadecimal digits of the digest of `data` to `out`, with no terminator. */
MS_NONNULL void ms_sha256_hex(MsSpan data, uint8_t out[MS_SHA256_HEX_LEN]);

#endif

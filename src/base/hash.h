/* base/hash.h: hashing of integers, byte ranges and composite keys.
 *
 * The integer hash is the one the Manuscript compiler emits inline in map probes, and the byte hash is the
 * one Manuscript strings use, so a change here is a change to generated code. Hashes are lookup aids, not
 * stable identifiers. Integer ids and interned names hash with ms_hash_int; strings with ms_hash_span. */
#ifndef MS_BASE_HASH_H
#define MS_BASE_HASH_H

#include "base/safe.h"

#define MS_HASH_K0 UINT64_C(0x9e3779b97f4a7c15)
#define MS_HASH_K1 UINT64_C(0xff51afd7ed558ccd)

/* One widening multiply folded to 64 bits. */
static inline uint64_t ms_hash_fold(uint64_t a, uint64_t b) {
  const unsigned __int128 product = (unsigned __int128)a * b;
  return (uint64_t)product ^ (uint64_t)(product >> 64);
}

/* The hash of an integer key. */
static inline uint64_t ms_hash_int(uint64_t value) {
  return ms_hash_fold(value ^ MS_HASH_K0, MS_HASH_K1);
}

/* Avalanche of a 64-bit word: the finishing step of every composite hash. */
static inline uint64_t ms_hash_mix(uint64_t hash) {
  hash ^= hash >> 32;
  hash *= MS_HASH_K0;
  return hash ^ (hash >> 29);
}

/* Folds the hash `next` of one more part into the running hash. */
static inline uint64_t ms_hash_combine(uint64_t hash, uint64_t next) {
  return ms_hash_mix(((hash << 5) | (hash >> 59)) ^ next);
}

/* The hash of `length <= 15` bytes whose little-endian words are `low` (bytes 0..7) and `high` (8..15). */
static inline uint64_t ms_hash_short(size_t length, uint64_t low, uint64_t high) {
  const uint64_t seed = MS_HASH_K0 ^ ((uint64_t)length * MS_HASH_K1);
  return ms_hash_fold(ms_hash_fold(seed ^ low, MS_HASH_K1) ^ high, MS_HASH_K0);
}

/* The hash of a byte range. */
static inline uint64_t ms_hash_span(MsSpan span) {
  if (span.len <= 15) {
    uint8_t padded[16] = {0};
    if (span.len != 0) {
      __builtin_memcpy(padded, span.ptr, span.len);
    }
    return ms_hash_short(span.len, ms_load64(padded), ms_load64(padded + 8));
  }
  uint64_t hash = MS_HASH_K0 ^ ((uint64_t)span.len * MS_HASH_K1);
  size_t offset = 0;
  for (; offset + 8 <= span.len; offset += 8) {
    hash = ms_hash_fold(hash ^ ms_load64(span.ptr + offset), MS_HASH_K1);
  }
  /* The last eight bytes, overlapping the words already folded in. */
  return ms_hash_fold(hash ^ ms_load64(span.ptr + span.len - 8), MS_HASH_K0);
}

#endif

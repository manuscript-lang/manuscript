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

/* The little-endian words of `len <= 15` bytes padded with zeros, from overlapping loads: no copy of a variable
 * length. The loads of a short run repeat bytes at the same positions, so ORing them is exact. */
static inline void ms_hash_words(const uint8_t *p, size_t len, uint64_t *low, uint64_t *high) {
  *high = 0;
  if (len >= 8) {
    *low = ms_load64(p);
    if (len > 8) {
      *high = ms_load64(p + len - 8) >> ((16 - len) * 8);
    }
  } else if (len >= 4) {
    *low = (uint64_t)ms_load32(p) | ((uint64_t)ms_load32(p + len - 4) << ((len - 4) * 8));
  } else if (len != 0) {
    const size_t mid = len >> 1;
    *low = (uint64_t)p[0] | ((uint64_t)p[mid] << (mid * 8)) | ((uint64_t)p[len - 1] << ((len - 1) * 8));
  } else {
    *low = 0;
  }
}

/* The hash of a byte range. */
static inline uint64_t ms_hash_span(MsSpan span) {
  if (span.len <= 15) {
    uint64_t low, high;
    ms_hash_words(span.ptr, span.len, &low, &high);
    return ms_hash_short(span.len, low, high);
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

/* str_key.h: hash and equality of strings and byte ranges, inline so that a map probe with String keys
 * (src/runtime/core/map*.c) and the string natives (string.c) compute them with the same code.
 *
 * The hash is bit-identical to crates/ms-rt `hash_bytes`, because the Rust maps and the compiler's inline
 * map probe still compute it themselves.
 */
#ifndef MS_STR_KEY_H
#define MS_STR_KEY_H

#include "hash.h"
#include "ms_rt/alloc.h"
#include "ms_rt/safe.h"
#include "ms_rt/string.h"

static inline uint64_t ms_hash_fold(uint64_t a, uint64_t b) {
    const unsigned __int128 product = (unsigned __int128)a * b;
    return (uint64_t)product ^ (uint64_t)(product >> 64);
}

/* The hash of a string of n <= 15 bytes whose little-endian bits are lo (bytes 0..7) and hi (bytes 8..15). */
static inline uint64_t ms_hash_short(size_t n, uint64_t lo, uint64_t hi) {
    const uint64_t h = MS_HASH_K0 ^ ((uint64_t)n * MS_HASH_K1);
    return ms_hash_fold(ms_hash_fold(h ^ lo, MS_HASH_K1) ^ hi, MS_HASH_K0);
}

/* The hash of `n` bytes at `b`. */
static inline uint64_t ms_hash_bytes(const uint8_t *b, size_t n) {
    if (n <= MS_STR_INLINE_MAX) {
        uint8_t pad[16] = {0};
        __builtin_memcpy(pad, b, n);
        return ms_hash_short(n, ms_load64(pad), ms_load64(pad + 8));
    }
    uint64_t h = MS_HASH_K0 ^ ((uint64_t)n * MS_HASH_K1);
    size_t i = 0;
    while (i + 8 <= n) {
        h = ms_hash_fold(h ^ ms_load64(b + i), MS_HASH_K1);
        i += 8;
    }
    /* Sixteen bytes or more: the last eight bytes, overlapping the words already folded in. */
    return ms_hash_fold(h ^ ms_load64(b + n - 8), MS_HASH_K0);
}

/* The hash of a string; an inline string is hashed from its words as they are. */
static inline uint64_t ms_str_hash(const MsStr *s) {
    if (ms_str_is_inline(s)) {
        const uint64_t hi = s->tagged & ((UINT64_C(1) << MS_STR_INLINE_SHIFT) - 1);
        return ms_hash_short(ms_str_len(s), (uint64_t)(uintptr_t)s->ptr_word, hi);
    }
    return ms_hash_bytes(s->ptr_word, ms_str_len(s));
}

/* Whether two strings hold the same bytes: overlapping word compares for up to 16 bytes. */
static inline bool ms_str_bytes_equal(const MsStr *a, const MsStr *b) {
    const size_t n = ms_str_len(a);
    if (n != ms_str_len(b)) {
        return false;
    }
    const uint8_t *p = ms_str_data(a);
    const uint8_t *q = ms_str_data(b);
    if (n >= 8 && n <= 16) {
        return ms_load64(p) == ms_load64(q) && ms_load64(p + n - 8) == ms_load64(q + n - 8);
    }
    if (n >= 4 && n < 8) {
        return ms_load32(p) == ms_load32(q) && ms_load32(p + n - 4) == ms_load32(q + n - 4);
    }
    if (n < 4) {
        /* The first, middle and last bytes cover every byte of a string of up to three. */
        return n == 0 || (p[0] == q[0] && p[n >> 1] == q[n >> 1] && p[n - 1] == q[n - 1]);
    }
    return __builtin_memcmp(p, q, n) == 0;
}

static inline bool ms_str_equal(const MsStr *a, const MsStr *b) {
    return (a->ptr_word == b->ptr_word && a->tagged == b->tagged) || ms_str_bytes_equal(a, b);
}

#endif

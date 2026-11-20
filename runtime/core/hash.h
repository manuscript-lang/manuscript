/* hash.h: the integer hash of map keys and the mixer behind composite hashes.
 *
 * Generated code probes Int-keyed maps with this same arithmetic, so a change here is a change to the
 * compiler's inline probe (crates/ms-lower). Hashes are lookup aids, not stable identifiers.
 */
#ifndef MS_HASH_H
#define MS_HASH_H

#include "ms_rt/base.h"

#define MS_HASH_K0 UINT64_C(0x9e3779b97f4a7c15)
#define MS_HASH_K1 UINT64_C(0xff51afd7ed558ccd)

/* The hash of an Int key: one widening multiply, folded to 64 bits. */
static inline uint64_t ms_hash_int(uint64_t value) {
    const unsigned __int128 product = (unsigned __int128)(value ^ MS_HASH_K0) * MS_HASH_K1;
    return (uint64_t)product ^ (uint64_t)(product >> 64);
}

/* Avalanche of a 64-bit word: the finishing step of every composite hash. */
static inline uint64_t ms_hash_mix(uint64_t h) {
    h ^= h >> 32;
    h *= MS_HASH_K0;
    return h ^ (h >> 29);
}

/* Folds the hash `next` of one more part into the running hash `h`. */
static inline uint64_t ms_hash_combine(uint64_t h, uint64_t next) {
    return ms_hash_mix(((h << 5) | (h >> 59)) ^ next);
}

#endif

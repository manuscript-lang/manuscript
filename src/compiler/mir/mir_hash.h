/* compiler/mir/mir_hash.h: a small open-addressed map of `uint64_t` to `uint64_t` (a set when the values are
 * unused) for the ownership passes. Its tables live in the arena passed to each update, so a pass keeps
 * every map in one scratch arena and drops it whole; nothing is freed one by one. The zero value is empty. */
#ifndef MS_COMPILER_MIR_MIR_HASH_H
#define MS_COMPILER_MIR_MIR_HASH_H

#include "base/arena.h"
#include "base/safe.h"

typedef struct MirHash {
  uint64_t *key, *val;
  uint8_t *used;
  uint32_t cap, n; /* capacity (a power of two or 0) and entries */
} MirHash;

/* The value of `key` into `*value` (which may be NULL); false when absent. */
bool mh_get(const MirHash *map, uint64_t key, uint64_t *value);
static inline bool mh_has(const MirHash *map, uint64_t key) {
  return mh_get(map, key, NULL);
}
/* Adds or replaces; whether `key` was new. */
bool mh_put(MsArena *arena, MirHash *map, uint64_t key, uint64_t value);
/* The keys in ascending order: `map->n` of them, in the arena. */
uint64_t *mh_keys(MsArena *arena, const MirHash *map);

#endif

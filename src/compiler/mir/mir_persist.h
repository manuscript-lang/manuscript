/* compiler/mir/mir_persist.h: persistent sets and maps of dense `uint32_t` keys.
 *
 * A copy is a struct copy (the tree is shared), an update copies one path, and comparing two sets skips the
 * subtrees they share. The ownership passes copy their per-block state at every block entry and edge; as flat
 * arrays that costs the size of the state each time, which made a function with N live owners quadratic.
 *
 * Nodes live in the arena passed to each update, which must outlive every copy. Nothing is freed one by one:
 * a pass makes a scratch arena and frees it at the end. */
#ifndef MS_COMPILER_MIR_MIR_PERSIST_H
#define MS_COMPILER_MIR_MIR_PERSIST_H

#include "base/arena.h"
#include "base/safe.h"

typedef struct PNode PNode;

/* A set of `uint32_t`. Equal contents compare equal whatever order they were built in; the zero value is
 * the empty set. */
typedef struct OwnerSet {
  const PNode *root;
  uint32_t height; /* 0: the root is a leaf covering 0..64; each level multiplies by 16 */
} OwnerSet;

void owner_insert(MsArena *arena, OwnerSet *set, uint32_t value);
/* Removes `value`; whether it was present. */
bool owner_remove(MsArena *arena, OwnerSet *set, uint32_t value);
static inline bool owner_is_empty(const OwnerSet *set) {
  return set->root == NULL;
}
/* The members in ascending order: `*count` of them, in the arena. */
uint32_t *owner_to_vec(MsArena *arena, const OwnerSet *set, uint32_t *count);

typedef struct PMapNode PMapNode;

/* A map from dense `uint32_t` keys to `uint64_t` values, iterated in key order. */
typedef struct PosMap {
  const PMapNode *root;
  uint32_t height; /* 0: the root is a leaf covering 0..16; each level multiplies by 16 */
  uint32_t len;
} PosMap;

bool posmap_get(const PosMap *map, uint32_t key, uint64_t *out);
void posmap_insert(MsArena *arena, PosMap *map, uint32_t key, uint64_t value);
bool posmap_remove(MsArena *arena, PosMap *map, uint32_t key);
/* The values in key order: `map->len` of them, in the arena. */
uint64_t *posmap_values(MsArena *arena, const PosMap *map);
/* Whether both maps hold the same keys and values, skipping shared subtrees. */
bool posmap_same_entries(const PosMap *x, const PosMap *y);

#endif

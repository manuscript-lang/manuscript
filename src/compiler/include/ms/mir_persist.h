/* Persistent sets and maps of dense `uint32_t` keys, ports of crates/ms-mir/src/persist.rs.
 *
 * A copy is a struct copy (the tree is shared), an update copies one path, and comparing two sets
 * skips the subtrees they share. The ownership passes copy their per-block state at every block
 * entry and edge; as flat arrays that costs the size of the state each time, which made a function
 * with N live owners quadratic (#4020, #4190).
 *
 * Nodes live in the arena passed to each update, which must outlive every copy of the structure.
 * Nothing is freed one by one: a pass makes a scratch arena and frees it at the end. */
#ifndef MS_MIR_PERSIST_H
#define MS_MIR_PERSIST_H

#include "ms/base.h"

typedef struct PNode PNode;

/* A set of `uint32_t`. Equal contents compare equal whatever order they were built in; the
 * zero value is the empty set. */
typedef struct OwnerSet {
    const PNode *root;
    uint32_t height; /* 0: the root is a leaf covering 0..64; each level multiplies by 16 */
} OwnerSet;

bool owner_contains(const OwnerSet *s, uint32_t v);
void owner_insert(MsArena *a, OwnerSet *s, uint32_t v);
/* Removes `v`; whether it was present. */
bool owner_remove(MsArena *a, OwnerSet *s, uint32_t v);
static inline bool owner_is_empty(const OwnerSet *s) { return s->root == NULL; }
bool owner_equal(const OwnerSet *x, const OwnerSet *y);
/* Adds every member of `other`. */
void owner_union(MsArena *a, OwnerSet *s, const OwnerSet *other);
/* The members in ascending order: `*n` of them, in `a`. */
uint32_t *owner_to_vec(MsArena *a, const OwnerSet *s, uint32_t *n);
/* The smallest member; false when empty. */
bool owner_first(const OwnerSet *s, uint32_t *out);
/* The values only in `x` and only in `y`, each ascending, in `a`. */
void owner_diff(MsArena *a, const OwnerSet *x, const OwnerSet *y, uint32_t **only_x,
                uint32_t *nx, uint32_t **only_y, uint32_t *ny);

typedef struct PMapNode PMapNode;

/* A map from dense `uint32_t` keys to `uint64_t` values, iterated in key order. */
typedef struct PosMap {
    const PMapNode *root;
    uint32_t height; /* 0: the root is a leaf covering 0..16; each level multiplies by 16 */
    uint32_t len;
} PosMap;

bool posmap_get(const PosMap *m, uint32_t k, uint64_t *out);
void posmap_insert(MsArena *a, PosMap *m, uint32_t k, uint64_t v);
bool posmap_remove(MsArena *a, PosMap *m, uint32_t k);
/* The values in key order: `m->len` of them, in `a`. */
uint64_t *posmap_values(MsArena *a, const PosMap *m);
/* Whether both maps hold the same keys and values, skipping shared subtrees. */
bool posmap_same_entries(const PosMap *x, const PosMap *y);
/* Whether both maps are the same tree, a quick equality. */
bool posmap_same_tree(const PosMap *x, const PosMap *y);

#endif

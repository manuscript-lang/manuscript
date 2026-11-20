/* slot.h: drop, copy, equality and hash of the value in a slot, dispatched on its type descriptor.
 *
 * The inline functions decide the common cases (plain scalars) without a call; the rest go through
 * desc.c. Every function takes the descriptor of the slot's type and trusts it: a descriptor that does
 * not describe the slot is a compiler bug, not an input the runtime can check.
 */
#ifndef MS_SLOT_H
#define MS_SLOT_H

#include "ms_rt/desc.h"
#include "ms_rt/safe.h"

/* The list or map value stored in a slot. The descriptor of such a slot says `align` 8, which is what makes
 * these views valid. */
static inline MsList *ms_slot_list(uint8_t *slot) {
    return (MsList *)__builtin_assume_aligned(slot, _Alignof(MsList));
}

static inline const MsList *ms_slot_list_const(const uint8_t *slot) {
    return (const MsList *)__builtin_assume_aligned(slot, _Alignof(MsList));
}

static inline MsMap *ms_slot_map(uint8_t *slot) {
    return (MsMap *)__builtin_assume_aligned(slot, _Alignof(MsMap));
}

static inline const MsMap *ms_slot_map_const(const uint8_t *slot) {
    return (const MsMap *)__builtin_assume_aligned(slot, _Alignof(MsMap));
}

/* The string value stored in a slot. */
static inline MsStr *ms_slot_str(uint8_t *slot) {
    return (MsStr *)__builtin_assume_aligned(slot, 8);
}

static inline const MsStr *ms_slot_str_const(const uint8_t *slot) {
    return (const MsStr *)__builtin_assume_aligned(slot, 8);
}

/* True when a value of this type owns nothing and copies bitwise. */
static inline bool ms_desc_is_plain(const MsTypeDesc *d) {
    switch ((MsKind)d->kind) {
    case MS_KIND_INT:
    case MS_KIND_FLOAT:
    case MS_KIND_BOOL:
    case MS_KIND_POD:
        return true;
    case MS_KIND_CUSTOM:
        return d->drop == NULL && d->copy == NULL;
    case MS_KIND_STRING:
    case MS_KIND_BYTES:
    case MS_KIND_SHARED:
    case MS_KIND_LIST:
    case MS_KIND_MAP:
    case MS_KIND_SET:
        return false;
    }
    return false;
}

/* True when dropping a value of this type does nothing. */
static inline bool ms_desc_drop_is_noop(const MsTypeDesc *d) {
    switch ((MsKind)d->kind) {
    case MS_KIND_INT:
    case MS_KIND_FLOAT:
    case MS_KIND_BOOL:
    case MS_KIND_POD:
        return true;
    case MS_KIND_CUSTOM:
        return d->drop == NULL;
    case MS_KIND_STRING:
    case MS_KIND_BYTES:
    case MS_KIND_SHARED:
    case MS_KIND_LIST:
    case MS_KIND_MAP:
    case MS_KIND_SET:
        return false;
    }
    return false;
}

/* True when values of this type can be hashed (floats, lists, maps and sets cannot). */
bool ms_desc_hashable(const MsTypeDesc *d);

void ms_slot_drop_owned(const MsTypeDesc *d, uint8_t *slot);
void ms_slot_copy_general(const MsTypeDesc *d, const uint8_t *src, uint8_t *dst);
bool ms_slot_eq(const MsTypeDesc *d, const uint8_t *a, const uint8_t *b);
uint64_t ms_slot_hash(const MsTypeDesc *d, const uint8_t *slot);

/* Frees what the value in `slot` owns. */
static inline void ms_slot_drop(const MsTypeDesc *d, uint8_t *slot) {
    if (ms_desc_drop_is_noop(d)) {
        return;
    }
    if (d->kind == MS_KIND_CUSTOM) { /* records and alternatives: their compiled glue, without the dispatch */
        d->drop(slot);
        return;
    }
    ms_slot_drop_owned(d, slot);
}

/* Duplicates the value in `src` into the uninitialised `dst` (what `.clone()` does). */
static inline void ms_slot_copy(const MsTypeDesc *d, const uint8_t *src, uint8_t *dst) {
    if (d->kind <= MS_KIND_BOOL && d->size == sizeof(uint64_t)) {
        __builtin_memcpy(dst, src, sizeof(uint64_t));
        return;
    }
    ms_slot_copy_general(d, src, dst);
}

#endif

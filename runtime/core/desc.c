/* Type descriptors: the builtin descriptors and the drop, copy, equality and hash of the value in a slot.
 * Ported from crates/ms-rt/src/desc.rs. The equality cycle guard (msrt_eq_enter, msrt_eq_leave) is in eq.c.
 */
#include "hash.h"
#include "list_ops.h"
#include "map_table.h"
#include "ms_rt/alloc.h"
#include "rt_calls.h"
#include "slot.h"
#include "str_key.h"

#define STR_SLOT_SIZE 16u
#define BYTES_SLOT_SIZE 24u

/* Builtin descriptors have no inner types and no function pointers. */
#define BUILTIN_DESC(slot_size, slot_align, slot_kind) \
    { .size = (slot_size), .align = (slot_align), .kind = (slot_kind) }

const MsTypeDesc msrt_desc_int = BUILTIN_DESC(8, 8, MS_KIND_INT);
const MsTypeDesc msrt_desc_float = BUILTIN_DESC(8, 8, MS_KIND_FLOAT);
const MsTypeDesc msrt_desc_float32 = BUILTIN_DESC(4, 4, MS_KIND_FLOAT);
const MsTypeDesc msrt_desc_bool = BUILTIN_DESC(1, 1, MS_KIND_BOOL);
const MsTypeDesc msrt_desc_string = BUILTIN_DESC(STR_SLOT_SIZE, 8, MS_KIND_STRING);
const MsTypeDesc msrt_desc_bytes = BUILTIN_DESC(BYTES_SLOT_SIZE, 8, MS_KIND_BYTES);

static uint64_t load_word(const uint8_t *slot) {
    uint64_t word = 0;
    __builtin_memcpy(&word, slot, sizeof word);
    return word;
}

/* ---- drop ---- */

static void drop_bytes(MsList *bytes) {
    if (bytes->ptr != NULL) {
        msrt_free(bytes->ptr);
        bytes->ptr = NULL;
    }
}

void ms_slot_drop_owned(const MsTypeDesc *d, uint8_t *slot) {
    switch ((MsKind)d->kind) {
    case MS_KIND_INT:
    case MS_KIND_FLOAT:
    case MS_KIND_BOOL:
    case MS_KIND_POD:
        return;
    case MS_KIND_STRING:
        msrt_string_free(ms_slot_str_const(slot));
        return;
    case MS_KIND_SHARED: {
        MsObj *object = NULL;
        __builtin_memcpy(&object, slot, sizeof(void *));
        msrt_obj_drop(object);
        return;
    }
    case MS_KIND_BYTES:
        drop_bytes(ms_slot_list(slot));
        return;
    case MS_KIND_LIST:
        ms_list_drop(ms_slot_list(slot), d->inner0);
        return;
    case MS_KIND_MAP:
        msrt_map_drop(ms_slot_map(slot), d->inner0, d->inner1);
        return;
    case MS_KIND_SET:
        msrt_map_drop(ms_slot_map(slot), d->inner0, NULL);
        return;
    case MS_KIND_CUSTOM:
        if (d->drop != NULL) {
            d->drop(slot);
        }
        return;
    }
}

/* ---- copy ---- */

void ms_slot_copy_general(const MsTypeDesc *d, const uint8_t *src, uint8_t *dst) {
    switch ((MsKind)d->kind) {
    case MS_KIND_INT:
    case MS_KIND_FLOAT:
    case MS_KIND_BOOL:
    case MS_KIND_POD:
        __builtin_memcpy(dst, src, d->size);
        return;
    case MS_KIND_STRING:
        msrt_string_clone(ms_slot_str_const(src), ms_slot_str(dst));
        return;
    case MS_KIND_SHARED: {
        MsObj *object = NULL;
        __builtin_memcpy(&object, src, sizeof(void *));
        object = msrt_obj_clone(object);
        __builtin_memcpy(dst, &object, sizeof(void *));
        return;
    }
    case MS_KIND_BYTES:
        ms_bytes_clone(ms_slot_list_const(src), ms_slot_list(dst));
        return;
    case MS_KIND_LIST:
        ms_list_clone(ms_slot_list_const(src), d->inner0, ms_slot_list(dst));
        return;
    case MS_KIND_MAP:
        msrt_map_copy(ms_slot_map_const(src), d->inner0, d->inner1, ms_slot_map(dst));
        return;
    case MS_KIND_SET:
        msrt_map_copy(ms_slot_map_const(src), d->inner0, NULL, ms_slot_map(dst));
        return;
    case MS_KIND_CUSTOM:
        if (d->copy != NULL) {
            d->copy(src, dst);
        } else {
            __builtin_memcpy(dst, src, d->size);
        }
        return;
    }
}

/* ---- equality ---- */

static bool bytes_eq(const MsList *a, const MsList *b) {
    return a->len == b->len && (a->len == 0 || __builtin_memcmp(a->ptr, b->ptr, a->len) == 0);
}

/* Objects compare by their override when both are non-null and not the same object; else by identity. */
static bool shared_eq(const MsTypeDesc *d, const uint8_t *a, const uint8_t *b) {
    const uint64_t left = load_word(a);
    const uint64_t right = load_word(b);
    if (d->eq == NULL || left == right) {
        return left == right;
    }
    if (left == 0 || right == 0) {
        return false;
    }
    return d->eq(a, b) != 0;
}

static bool raw_bytes_eq(const MsTypeDesc *d, const uint8_t *a, const uint8_t *b) {
    return d->size == 0 || __builtin_memcmp(a, b, d->size) == 0;
}

static bool float_eq(const MsTypeDesc *d, const uint8_t *a, const uint8_t *b) {
    if (d->size == sizeof(float)) {
        float x = 0;
        float y = 0;
        __builtin_memcpy(&x, a, sizeof x);
        __builtin_memcpy(&y, b, sizeof y);
        return x == y;
    }
    double x = 0;
    double y = 0;
    __builtin_memcpy(&x, a, sizeof x);
    __builtin_memcpy(&y, b, sizeof y);
    return x == y;
}

/* Equality of two slots whose type has an override or falls back to their bytes (POD and CUSTOM). */
static bool override_or_bytes_eq(const MsTypeDesc *d, const uint8_t *a, const uint8_t *b) {
    return d->eq != NULL ? d->eq(a, b) != 0 : raw_bytes_eq(d, a, b);
}

bool ms_slot_eq(const MsTypeDesc *d, const uint8_t *a, const uint8_t *b) {
    switch ((MsKind)d->kind) {
    case MS_KIND_INT:
        return load_word(a) == load_word(b);
    case MS_KIND_FLOAT:
        return float_eq(d, a, b);
    case MS_KIND_BOOL:
        return *a == *b;
    case MS_KIND_STRING:
        return msrt_string_eq(ms_slot_str_const(a), ms_slot_str_const(b)) != 0;
    case MS_KIND_BYTES:
        return bytes_eq(ms_slot_list_const(a), ms_slot_list_const(b));
    case MS_KIND_SHARED:
        return shared_eq(d, a, b);
    case MS_KIND_POD:
    case MS_KIND_CUSTOM:
        return override_or_bytes_eq(d, a, b);
    case MS_KIND_LIST:
        return ms_list_eq(ms_slot_list_const(a), ms_slot_list_const(b), d->inner0);
    case MS_KIND_MAP:
        return ms_map_eq(ms_slot_map_const(a), ms_slot_map_const(b), d->inner0, d->inner1);
    case MS_KIND_SET:
        return ms_map_eq(ms_slot_map_const(a), ms_slot_map_const(b), d->inner0, NULL);
    }
    return false;
}

/* ---- hash ---- */

bool ms_desc_hashable(const MsTypeDesc *d) {
    switch ((MsKind)d->kind) {
    case MS_KIND_FLOAT:
    case MS_KIND_LIST:
    case MS_KIND_MAP:
    case MS_KIND_SET:
        return false;
    case MS_KIND_SHARED:
    case MS_KIND_POD:
        return true;
    case MS_KIND_CUSTOM:
        return d->hash != NULL;
    case MS_KIND_INT:
    case MS_KIND_BOOL:
    case MS_KIND_STRING:
    case MS_KIND_BYTES:
        return true;
    }
    return false;
}

static MS_NORETURN void fault_not_hashable(void) {
    static const char message[] = "runtime invariant: type is not hashable";
    msrt_fault((const uint8_t *)message, sizeof message - 1);
}

static uint64_t bytes_hash(const MsList *bytes) {
    return ms_hash_bytes(bytes->ptr, bytes->len);
}

static uint64_t shared_hash(const MsTypeDesc *d, const uint8_t *slot) {
    const uint64_t word = load_word(slot);
    if (d->hash != NULL && word != 0) {
        return (uint64_t)d->hash(slot);
    }
    return ms_hash_mix(word);
}

/* POD hashes through its override, else over its bytes; CUSTOM has no byte fallback. */
static uint64_t pod_or_custom_hash(const MsTypeDesc *d, const uint8_t *slot) {
    if (d->hash != NULL) {
        return (uint64_t)d->hash(slot);
    }
    if (d->kind != MS_KIND_POD) {
        fault_not_hashable();
    }
    return ms_hash_bytes(slot, d->size);
}

uint64_t ms_slot_hash(const MsTypeDesc *d, const uint8_t *slot) {
    switch ((MsKind)d->kind) {
    case MS_KIND_INT:
        return ms_hash_int(load_word(slot));
    case MS_KIND_BOOL:
        return ms_hash_mix((uint64_t)*slot + 1);
    case MS_KIND_STRING:
        return (uint64_t)msrt_string_hash(ms_slot_str_const(slot));
    case MS_KIND_BYTES:
        return bytes_hash(ms_slot_list_const(slot));
    case MS_KIND_SHARED:
        return shared_hash(d, slot);
    case MS_KIND_POD:
    case MS_KIND_CUSTOM:
        return pod_or_custom_hash(d, slot);
    case MS_KIND_FLOAT:
    case MS_KIND_LIST:
    case MS_KIND_MAP:
    case MS_KIND_SET:
        fault_not_hashable();
    }
    fault_not_hashable();
}

/* ---- exported entry points ---- */

void msrt_slot_drop(const MsTypeDesc *d, uint8_t *slot) { ms_slot_drop(d, slot); }

void msrt_slot_copy(const MsTypeDesc *d, const uint8_t *src, uint8_t *dst) { ms_slot_copy(d, src, dst); }

uint8_t msrt_slot_eq(const MsTypeDesc *d, const uint8_t *a, const uint8_t *b) { return ms_slot_eq(d, a, b); }

int64_t msrt_slot_hash(const MsTypeDesc *d, const uint8_t *slot) { return (int64_t)ms_slot_hash(d, slot); }

int64_t msrt_hash_combine(int64_t a, int64_t b) { return (int64_t)ms_hash_combine((uint64_t)a, (uint64_t)b); }

/* The hash of an Int a generated struct or tuple hash folds in: the word is offset, then avalanched. */
int64_t msrt_hash_int(int64_t v) { return (int64_t)ms_hash_mix((uint64_t)v ^ UINT64_C(0x9e3779b9)); }

/* The hash of `length` bytes at `bytes`, the one a String key has (runtime/core/str_key.h). */
int64_t msrt_hash_bytes(const uint8_t *p, size_t len) { return (int64_t)ms_hash_bytes(p, len); }

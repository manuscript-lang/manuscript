/* ms_rt/desc.h: type descriptors and the values stored in slots (runtime/core/desc.c).
 *
 * The compiler emits one static, read-only MsTypeDesc per slot type. A list, a map or a promise stores its
 * values in slots of `size` bytes and reaches their drop, copy, equality and hash through the descriptor.
 * These layouts are the ABI: generated code reads them, so each has a _Static_assert.
 */
#ifndef MS_RT_DESC_H
#define MS_RT_DESC_H

#include "ms_rt/base.h"

/* What a slot holds. */
typedef enum MsKind {
    MS_KIND_INT = 0,    /* 8 bytes of plain bits */
    MS_KIND_FLOAT = 1,  /* 8 bytes, or 4 for a Float32; plain bits */
    MS_KIND_BOOL = 2,   /* 1 byte */
    MS_KIND_STRING = 3, /* a string value (16 bytes): copy duplicates, drop frees, content equality and hash */
    MS_KIND_BYTES = 4,  /* an MsList of bytes: copy duplicates the buffer */
    MS_KIND_SHARED = 5, /* a nullable pointer to an object with a header (closures, handles): copy and drop call its entries */
    MS_KIND_POD = 6,    /* plain bits without ownership; memcmp equality and byte hash unless `eq`/`hash` is set */
    MS_KIND_LIST = 7,   /* an MsList whose elements are described by `inner0` */
    MS_KIND_MAP = 8,    /* an MsMap with keys `inner0` and values `inner1` */
    MS_KIND_SET = 9,    /* an MsMap with elements `inner0` */
    MS_KIND_CUSTOM = 10 /* records, alternatives and the rest: all behaviour through the function pointers */
} MsKind;

typedef struct MsTypeDesc MsTypeDesc;

/* A string value (two words, ms_rt/string.h). Natives of this layer pass it through and never look inside. */
typedef struct MsStr MsStr;

/* Frees what the value in `slot` owns; the slot memory is the caller's. */
typedef void (*MsSlotDropFn)(uint8_t *slot);
/* Deep-copies the value in `src` into the uninitialised `dst`. */
typedef void (*MsSlotCopyFn)(const uint8_t *src, uint8_t *dst);
/* Equality of two slots: 0 or 1. */
typedef uint8_t (*MsSlotEqFn)(const uint8_t *a, const uint8_t *b);
/* Hash of a slot; equal values hash equally. */
typedef int64_t (*MsSlotHashFn)(const uint8_t *slot);

struct MsTypeDesc {
    uint32_t size;  /* slot size in bytes, a multiple of `align`; zero for Void */
    uint32_t align; /* 1, 2, 4, 8 or 16 */
    uint32_t kind;  /* an MsKind */
    uint32_t reserved;
    const MsTypeDesc *inner0; /* element or key descriptor of a list, map or set */
    const MsTypeDesc *inner1; /* value descriptor of a map */
    MsSlotDropFn drop;        /* MS_KIND_CUSTOM: NULL when the value owns nothing */
    MsSlotCopyFn copy;        /* MS_KIND_CUSTOM: NULL means a bitwise copy */
    MsSlotEqFn eq;            /* MS_KIND_SHARED, POD and CUSTOM: overrides the default equality */
    MsSlotHashFn hash;        /* MS_KIND_SHARED, POD and CUSTOM: overrides the default hash */
};

/* A list, Bytes or a string builder: three words in the owner's slot. `ptr` is NULL while `cap` is 0; the
 * elements are `size` bytes apart. The owner frees the buffer; a view (`cap == 0` with a `ptr`) borrows
 * its elements and frees nothing. */
typedef struct MsList {
    uint8_t *ptr;
    size_t len;
    size_t cap;
} MsList;

/* A map or set: an insertion-ordered hash table (runtime/core/map.c). Only `len` is read by generated code. */
typedef struct MsMap {
    uint8_t *slots;           /* append-only entries: hash word (top bit set when live), key, value */
    uint64_t *index;          /* open-addressing index: hash tag in the high word, slot number in the low */
    size_t len;               /* live entries */
    size_t used;              /* slots used so far, removed ones included */
    size_t cap;               /* slot capacity */
    size_t mask;              /* index size minus one; 0 when there is no index */
    const MsTypeDesc *desc;   /* the creator's key descriptor, or NULL for a descriptor-neutral native map */
} MsMap;

_Static_assert(sizeof(MsTypeDesc) == 64, "descriptor layout is ABI");
_Static_assert(offsetof(MsTypeDesc, inner0) == 16 && offsetof(MsTypeDesc, drop) == 32, "descriptor layout is ABI");
_Static_assert(sizeof(MsList) == 24 && offsetof(MsList, len) == 8 && offsetof(MsList, cap) == 16, "list layout is ABI");
_Static_assert(sizeof(MsMap) == 56 && offsetof(MsMap, len) == 16, "map layout is ABI");

/* The builtin descriptors (generated code references them by name). */
extern const MsTypeDesc msrt_desc_int;
extern const MsTypeDesc msrt_desc_float;
extern const MsTypeDesc msrt_desc_float32;
extern const MsTypeDesc msrt_desc_bool;
extern const MsTypeDesc msrt_desc_string;
extern const MsTypeDesc msrt_desc_bytes;

/* ms-sig: msrt_slot_drop(d: *const TypeDesc, slot: *mut u8) @leaf */
void msrt_slot_drop(const MsTypeDesc *d, uint8_t *slot);
/* ms-sig: msrt_slot_copy(d: *const TypeDesc, src: *const u8, dst: *mut u8) @leaf */
void msrt_slot_copy(const MsTypeDesc *d, const uint8_t *src, uint8_t *dst);
/* ms-sig: msrt_slot_eq(d: *const TypeDesc, a: *const u8, b: *const u8) -> u8 @domain=slot @leaf */
uint8_t msrt_slot_eq(const MsTypeDesc *d, const uint8_t *a, const uint8_t *b);
/* ms-sig: msrt_slot_hash(d: *const TypeDesc, slot: *const u8) -> i64 @leaf */
int64_t msrt_slot_hash(const MsTypeDesc *d, const uint8_t *slot);
/* ms-sig: msrt_hash_combine(a: i64, b: i64) -> i64 @leaf */
int64_t msrt_hash_combine(int64_t a, int64_t b);
/* ms-sig: msrt_hash_bytes(p: *const u8, len: usize) -> i64 @domain=map @leaf */
int64_t msrt_hash_bytes(const uint8_t *p, size_t len);
/* ms-sig: msrt_hash_int(v: i64) -> i64 @domain=map @leaf */
int64_t msrt_hash_int(int64_t v);

/* The equality cycle guard (runtime/core/eq.c): registers the pair of objects being compared, 1, or 0 when the pair is
 * already being compared (a cycle, which the comparison treats as equal). */
/* ms-sig: msrt_eq_enter(a: *const u8, b: *const u8) -> u8 @leaf */
uint8_t msrt_eq_enter(const uint8_t *a, const uint8_t *b);
/* Ends the innermost registration. */
/* ms-sig: msrt_eq_leave(a: *const u8, b: *const u8) @leaf */
void msrt_eq_leave(const uint8_t *a, const uint8_t *b);

#endif

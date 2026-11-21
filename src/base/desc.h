/* base/desc.h: MsTypeDesc and the values stored in slots.
 *
 * The compiler emits one static, read-only descriptor per slot type. A list, map, set or promise stores its
 * values in slots of `size` bytes and reaches their drop, copy, equality and hash through the descriptor.
 * This is the erased tier of the value layer: one implementation serves every element type, driven by the
 * descriptor (the specialized tier is base/map.h's MS_MAP_DEFINE). The layouts are the program ABI.
 *
 * Every function trusts the descriptor it is given: a descriptor that does not describe the slot is a
 * compiler bug, not an input the library can check. Nothing here knows about tasks, faults or I/O; an
 * unrecoverable condition (a type that cannot be hashed) reports through ms_fatal. */
#ifndef MS_BASE_DESC_H
#define MS_BASE_DESC_H

#include "base/list.h"
#include "base/string.h"

/* What a slot holds. */
typedef enum MsKind {
  MS_KIND_INT = 0,    /* 8 bytes of plain bits */
  MS_KIND_FLOAT = 1,  /* 8 bytes, or 4 for a Float32; plain bits */
  MS_KIND_BOOL = 2,   /* 1 byte */
  MS_KIND_STRING = 3, /* an MsString (16 bytes): copy duplicates, drop frees, content equality and hash */
  MS_KIND_BYTES = 4,  /* an MsBytes: copy duplicates the buffer */
  MS_KIND_SHARED = 5, /* a nullable pointer to an MsObj (closures, handles): copy and drop call its entries */
  MS_KIND_POD = 6, /* plain bits without ownership; memcmp equality and byte hash unless `eq`/`hash` is set */
  MS_KIND_LIST = 7,   /* an MsList whose elements are described by `inner0` */
  MS_KIND_MAP = 8,    /* an MsMap with keys `inner0` and values `inner1` */
  MS_KIND_SET = 9,    /* an MsMap with elements `inner0` */
  MS_KIND_CUSTOM = 10 /* records, alternatives and the rest: all behaviour through the function pointers */
} MsKind;

typedef struct MsTypeDesc MsTypeDesc;

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

_Static_assert(sizeof(MsTypeDesc) == 64, "descriptor layout is ABI");
_Static_assert(offsetof(MsTypeDesc, inner0) == 16 && offsetof(MsTypeDesc, drop) == 32,
               "descriptor layout is ABI");

/* The 16-byte header every heap object starts with. `clone` is null for a value with one owner; `drop`
 * drops the children and frees the object. */
typedef struct MsObj MsObj;
struct MsObj {
  MsObj *(*clone)(MsObj *);
  void (*drop)(MsObj *);
};

/* The runtime replaces how an object is dropped (it bounds the depth of nested drops); the default calls
 * `object->drop`. NULL restores the default. Call before any other thread starts. */
void ms_obj_install_drop(void (*drop)(MsObj *));

/* The builtin descriptors (generated code references them by name through the runtime's symbols). */
extern const MsTypeDesc ms_desc_int;
extern const MsTypeDesc ms_desc_float;
extern const MsTypeDesc ms_desc_float32;
extern const MsTypeDesc ms_desc_bool;
extern const MsTypeDesc ms_desc_string;
extern const MsTypeDesc ms_desc_bytes;

/* True when a value of this type owns nothing and copies bitwise. */
bool ms_desc_is_plain(const MsTypeDesc *desc);

/* True when dropping a value of this type does nothing. */
bool ms_desc_drop_is_noop(const MsTypeDesc *desc);

/* True when values of this type can be hashed (floats, lists, maps and sets cannot). */
bool ms_desc_hashable(const MsTypeDesc *desc);

void ms_slot_drop_owned(const MsTypeDesc *desc, uint8_t *slot);
void ms_slot_copy_general(const MsTypeDesc *desc, const uint8_t *src, uint8_t *dst);

/* Frees what the value in `slot` owns. */
static inline void ms_slot_drop(const MsTypeDesc *desc, uint8_t *slot) {
  if (desc->kind <= MS_KIND_BOOL || desc->kind == MS_KIND_POD) {
    return;
  }
  ms_slot_drop_owned(desc, slot);
}

/* Duplicates the value in `src` into the uninitialised `dst` (what `.clone()` does). */
static inline void ms_slot_copy(const MsTypeDesc *desc, const uint8_t *src, uint8_t *dst) {
  if (desc->kind <= MS_KIND_BOOL && desc->size == sizeof(uint64_t)) {
    __builtin_memcpy(dst, src, sizeof(uint64_t));
    return;
  }
  ms_slot_copy_general(desc, src, dst);
}

bool ms_slot_equal(const MsTypeDesc *desc, const uint8_t *a, const uint8_t *b);
uint64_t ms_slot_hash(const MsTypeDesc *desc, const uint8_t *slot);

/* ---- lists of slots ---- */

/* Frees the elements and the buffer of an owned list and leaves it empty. A view is left as it is. */
void ms_list_drop_desc(MsList *list, const MsTypeDesc *element);

/* Deep copy of `source` into the uninitialised `out`. */
void ms_list_clone_desc(const MsList *source, const MsTypeDesc *element, MsList *out);

/* Element-wise equality. */
bool ms_list_equal_desc(const MsList *a, const MsList *b, const MsTypeDesc *element);

/* The address of element `index`, which must be below `list->len`. */
static inline uint8_t *ms_list_slot(const MsList *list, const MsTypeDesc *element, size_t index) {
  return list->ptr + index * element->size;
}

#endif

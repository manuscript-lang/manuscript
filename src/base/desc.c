/* Owns the builtin descriptors and the drop, copy, equality and hash of the value in a slot (see desc.h). */
#include "base/desc.h"

#include "base/alloc.h"
#include "base/bytes.h"
#include "base/fatal.h"
#include "base/hash.h"
#include "base/map.h"

#define BUILTIN_DESC(slot_size, slot_align, slot_kind)                                                       \
  { .size = (slot_size), .align = (slot_align), .kind = (slot_kind) }

const MsTypeDesc ms_desc_int = BUILTIN_DESC(8, 8, MS_KIND_INT);
const MsTypeDesc ms_desc_float = BUILTIN_DESC(8, 8, MS_KIND_FLOAT);
const MsTypeDesc ms_desc_float32 = BUILTIN_DESC(4, 4, MS_KIND_FLOAT);
const MsTypeDesc ms_desc_bool = BUILTIN_DESC(1, 1, MS_KIND_BOOL);
const MsTypeDesc ms_desc_string = BUILTIN_DESC(sizeof(MsString), 8, MS_KIND_STRING);
const MsTypeDesc ms_desc_bytes = BUILTIN_DESC(sizeof(MsBytes), 8, MS_KIND_BYTES);

/* Generated code names the builtin descriptors msrt_desc_*; they are these same objects (one address each, so
 * descriptors compare by pointer). */
#define RUNTIME_ALIAS(name) extern const MsTypeDesc msrt_desc_##name __attribute__((alias("ms_desc_" #name)))
RUNTIME_ALIAS(int);
RUNTIME_ALIAS(float);
RUNTIME_ALIAS(float32);
RUNTIME_ALIAS(bool);
RUNTIME_ALIAS(string);
RUNTIME_ALIAS(bytes);

static void (*installed_drop)(MsObj *) = NULL; /* set once at start-up, before threads */

void ms_obj_install_drop(void (*drop)(MsObj *)) {
  installed_drop = drop;
}

/* Slots hold 8-aligned values (the descriptor says so); these views state it to the compiler. */
static MsList *slot_list(uint8_t *slot) {
  return __builtin_assume_aligned(slot, _Alignof(MsList));
}
static const MsList *slot_list_const(const uint8_t *slot) {
  return __builtin_assume_aligned(slot, _Alignof(MsList));
}
static MsMap *slot_map(uint8_t *slot) {
  return __builtin_assume_aligned(slot, _Alignof(MsMap));
}
static const MsMap *slot_map_const(const uint8_t *slot) {
  return __builtin_assume_aligned(slot, _Alignof(MsMap));
}
static MsString *slot_string(uint8_t *slot) {
  return __builtin_assume_aligned(slot, _Alignof(MsString));
}
static const MsString *slot_string_const(const uint8_t *slot) {
  return __builtin_assume_aligned(slot, _Alignof(MsString));
}

static MsObj *load_object(const uint8_t *slot) {
  MsObj *object = NULL;
  __builtin_memcpy(&object, slot, sizeof object);
  return object;
}

bool ms_desc_is_plain(const MsTypeDesc *desc) {
  switch ((MsKind)desc->kind) {
  case MS_KIND_INT:
  case MS_KIND_FLOAT:
  case MS_KIND_BOOL:
  case MS_KIND_POD:
    return true;
  case MS_KIND_CUSTOM:
    return desc->drop == NULL && desc->copy == NULL;
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

bool ms_desc_drop_is_noop(const MsTypeDesc *desc) {
  return desc->kind == MS_KIND_CUSTOM ? desc->drop == NULL : ms_desc_is_plain(desc);
}

bool ms_desc_hashable(const MsTypeDesc *desc) {
  switch ((MsKind)desc->kind) {
  case MS_KIND_FLOAT:
  case MS_KIND_LIST:
  case MS_KIND_MAP:
  case MS_KIND_SET:
    return false;
  case MS_KIND_CUSTOM:
    return desc->hash != NULL;
  case MS_KIND_INT:
  case MS_KIND_BOOL:
  case MS_KIND_STRING:
  case MS_KIND_BYTES:
  case MS_KIND_SHARED:
  case MS_KIND_POD:
    return true;
  }
  return false;
}

/* ---- drop ---- */

static void drop_object(MsObj *object) {
  if (object == NULL) {
    return;
  }
  if (installed_drop != NULL) {
    installed_drop(object);
    return;
  }
  object->drop(object);
}

void ms_slot_drop_owned(const MsTypeDesc *desc, uint8_t *slot) {
  switch ((MsKind)desc->kind) {
  case MS_KIND_INT:
  case MS_KIND_FLOAT:
  case MS_KIND_BOOL:
  case MS_KIND_POD:
    return;
  case MS_KIND_STRING:
    ms_string_release(slot_string(slot));
    return;
  case MS_KIND_SHARED:
    drop_object(load_object(slot));
    return;
  case MS_KIND_BYTES:
    ms_list_free(slot_list(slot));
    return;
  case MS_KIND_LIST:
    ms_list_drop_desc(slot_list(slot), desc->inner0);
    return;
  case MS_KIND_MAP:
    ms_map_drop(slot_map(slot), desc->inner0, desc->inner1);
    return;
  case MS_KIND_SET:
    ms_map_drop(slot_map(slot), desc->inner0, NULL);
    return;
  case MS_KIND_CUSTOM:
    if (desc->drop != NULL) {
      desc->drop(slot);
    }
    return;
  }
}

/* ---- copy ---- */

static void copy_shared(const uint8_t *src, uint8_t *dst) {
  MsObj *object = load_object(src);
  if (object != NULL) {
    if (object->clone == NULL) {
      ms_fatal(MS_FATAL_INVARIANT, "copy of a value that has one owner");
    }
    object = object->clone(object);
  }
  __builtin_memcpy(dst, &object, sizeof object);
}

void ms_slot_copy_general(const MsTypeDesc *desc, const uint8_t *src, uint8_t *dst) {
  switch ((MsKind)desc->kind) {
  case MS_KIND_INT:
  case MS_KIND_FLOAT:
  case MS_KIND_BOOL:
  case MS_KIND_POD:
    __builtin_memcpy(dst, src, desc->size);
    return;
  case MS_KIND_STRING:
    *slot_string(dst) = ms_string_clone(slot_string_const(src));
    return;
  case MS_KIND_SHARED:
    copy_shared(src, dst);
    return;
  case MS_KIND_BYTES:
    *slot_list(dst) = ms_bytes_from_span(ms_bytes_span(slot_list_const(src)));
    return;
  case MS_KIND_LIST:
    ms_list_clone_desc(slot_list_const(src), desc->inner0, slot_list(dst));
    return;
  case MS_KIND_MAP:
    ms_map_clone(slot_map_const(src), desc->inner0, desc->inner1, slot_map(dst));
    return;
  case MS_KIND_SET:
    ms_map_clone(slot_map_const(src), desc->inner0, NULL, slot_map(dst));
    return;
  case MS_KIND_CUSTOM:
    if (desc->copy != NULL) {
      desc->copy(src, dst);
    } else {
      __builtin_memcpy(dst, src, desc->size);
    }
    return;
  }
}

/* ---- equality ---- */

/* Objects compare by their override when both are non-null and not the same object; else by identity. */
static bool shared_equal(const MsTypeDesc *desc, const uint8_t *a, const uint8_t *b) {
  const uint64_t left = ms_load64(a);
  const uint64_t right = ms_load64(b);
  if (desc->eq == NULL || left == right) {
    return left == right;
  }
  return left != 0 && right != 0 && desc->eq(a, b) != 0;
}

static bool float_equal(const MsTypeDesc *desc, const uint8_t *a, const uint8_t *b) {
  if (desc->size == sizeof(float)) {
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

/* POD and CUSTOM: the override, else the bytes. */
static bool override_or_bytes_equal(const MsTypeDesc *desc, const uint8_t *a, const uint8_t *b) {
  if (desc->eq != NULL) {
    return desc->eq(a, b) != 0;
  }
  return desc->size == 0 || __builtin_memcmp(a, b, desc->size) == 0;
}

bool ms_slot_equal(const MsTypeDesc *desc, const uint8_t *a, const uint8_t *b) {
  switch ((MsKind)desc->kind) {
  case MS_KIND_INT:
    return ms_load64(a) == ms_load64(b);
  case MS_KIND_FLOAT:
    return float_equal(desc, a, b);
  case MS_KIND_BOOL:
    return *a == *b;
  case MS_KIND_STRING:
    return ms_string_equal(slot_string_const(a), slot_string_const(b));
  case MS_KIND_BYTES:
    return ms_span_equal(ms_bytes_span(slot_list_const(a)), ms_bytes_span(slot_list_const(b)));
  case MS_KIND_SHARED:
    return shared_equal(desc, a, b);
  case MS_KIND_POD:
  case MS_KIND_CUSTOM:
    return override_or_bytes_equal(desc, a, b);
  case MS_KIND_LIST:
    return ms_list_equal_desc(slot_list_const(a), slot_list_const(b), desc->inner0);
  case MS_KIND_MAP:
    return ms_map_equal(slot_map_const(a), slot_map_const(b), desc->inner0, desc->inner1);
  case MS_KIND_SET:
    return ms_map_equal(slot_map_const(a), slot_map_const(b), desc->inner0, NULL);
  }
  return false;
}

/* ---- hash ---- */

static MS_NORETURN void not_hashable(void) {
  ms_fatal(MS_FATAL_INVARIANT, "type is not hashable");
}

static uint64_t shared_hash(const MsTypeDesc *desc, const uint8_t *slot) {
  const uint64_t word = ms_load64(slot);
  if (desc->hash != NULL && word != 0) {
    return (uint64_t)desc->hash(slot);
  }
  return ms_hash_mix(word);
}

/* POD hashes through its override, else over its bytes; CUSTOM has no byte fallback. */
static uint64_t pod_or_custom_hash(const MsTypeDesc *desc, const uint8_t *slot) {
  if (desc->hash != NULL) {
    return (uint64_t)desc->hash(slot);
  }
  if (desc->kind != MS_KIND_POD) {
    not_hashable();
  }
  return ms_hash_span(ms_span_of(slot, desc->size));
}

uint64_t ms_slot_hash(const MsTypeDesc *desc, const uint8_t *slot) {
  switch ((MsKind)desc->kind) {
  case MS_KIND_INT:
    return ms_hash_int(ms_load64(slot));
  case MS_KIND_BOOL:
    return ms_hash_mix((uint64_t)*slot + 1);
  case MS_KIND_STRING:
    return ms_string_hash(slot_string_const(slot));
  case MS_KIND_BYTES:
    return ms_hash_span(ms_bytes_span(slot_list_const(slot)));
  case MS_KIND_SHARED:
    return shared_hash(desc, slot);
  case MS_KIND_POD:
  case MS_KIND_CUSTOM:
    return pod_or_custom_hash(desc, slot);
  case MS_KIND_FLOAT:
  case MS_KIND_LIST:
  case MS_KIND_MAP:
  case MS_KIND_SET:
    not_hashable();
  }
  not_hashable();
}

/* ---- lists of slots ---- */

void ms_list_drop_desc(MsList *list, const MsTypeDesc *element) {
  if (list->cap == 0) { /* a view owns nothing */
    return;
  }
  if (!ms_desc_drop_is_noop(element)) {
    for (size_t i = 0; i < list->len; i++) {
      ms_slot_drop(element, ms_list_slot(list, element, i));
    }
  }
  ms_list_free(list);
}

void ms_list_clone_desc(const MsList *source, const MsTypeDesc *element, MsList *out) {
  MsList copy = {0};
  if (source->len != 0) {
    ms_list_reserve(&copy, element->size, source->len);
    if (ms_desc_is_plain(element)) {
      __builtin_memcpy(copy.ptr, source->ptr, source->len * element->size);
    } else {
      for (size_t i = 0; i < source->len; i++) {
        ms_slot_copy(element, ms_list_slot(source, element, i), ms_list_slot(&copy, element, i));
      }
    }
    copy.len = source->len;
  }
  *out = copy;
}

bool ms_list_equal_desc(const MsList *a, const MsList *b, const MsTypeDesc *element) {
  if (a->len != b->len) {
    return false;
  }
  for (size_t i = 0; i < a->len; i++) {
    if (!ms_slot_equal(element, ms_list_slot(a, element, i), ms_list_slot(b, element, i))) {
      return false;
    }
  }
  return true;
}

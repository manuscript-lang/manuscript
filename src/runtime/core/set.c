/* runtime/core/set.c: the natives programs call on sets. A set is a map without values: base/map.h with the
 * value descriptor NULL. */
#include "runtime/core/map.h"

#include "runtime/core/scratch.h"

/* Adds a copy of the key at `key`, first checking for a duplicate unless the caller knows the output has
 * none. */
static void add_copy(MsMap *m, const MsTypeDesc *kd, const uint8_t *key, bool check) {
  if (check && ms_map_has(m, kd, NULL, key)) {
    return;
  }
  MsrtScratch copy;
  msrt_scratch_open(&copy, kd->size);
  ms_slot_copy(kd, key, copy.ptr);
  ms_map_insert(m, kd, NULL, copy.ptr, NULL);
  msrt_scratch_close(&copy);
}

void msrt_set_add_copy(MsMap *m, const MsTypeDesc *kd, const uint8_t *key) {
  add_copy(m, ms_map_key_desc(m, kd), key, true);
}

/* `add(move value)`: the set takes the value, or drops it when an equal one is already present. */
void msrt_set_add(MsMap *m, const MsTypeDesc *kd, uint8_t *key) {
  kd = ms_map_key_desc(m, kd);
  if (ms_map_has(m, kd, NULL, key)) {
    ms_slot_drop(kd, key);
    return;
  }
  ms_map_insert(m, kd, NULL, key, NULL);
}

int64_t msrt_set_length(const MsMap *m) {
  return msrt_map_length(m);
}

uint8_t msrt_set_contains(const MsMap *m, const MsTypeDesc *kd, const uint8_t *key) {
  return msrt_map_contains(m, kd, NULL, key);
}

/* `remove(move value)`: the value is consumed whether or not it was present. */
void msrt_set_remove(MsMap *m, const MsTypeDesc *kd, uint8_t *key) {
  msrt_map_remove(m, kd, NULL, key);
}

void msrt_set_clear(MsMap *m, const MsTypeDesc *kd) {
  msrt_map_clear(m, kd, NULL);
}

void msrt_set_add_copy_w(MsMap *m, const MsTypeDesc *kd, const uint8_t *key) {
  msrt_set_add_copy(m, kd, key);
}

/* Keys are tested against another set, probed with the key behaviour of the module that built it. */
typedef struct Membership {
  const MsMap *other;
  const MsTypeDesc *other_kd;
  bool wanted; /* the answer a key must get from `other` */
} Membership;

static bool has_membership(const Membership *test, const uint8_t *key) {
  return ms_map_has(test->other, test->other_kd, NULL, key) == test->wanted;
}

/* The keys of `a` that have the membership `wanted` in `other`, copied into `out` in a's order. */
static void copy_matching(const MsMap *a, const MsTypeDesc *kd, const Membership *test, bool check,
                          MsMap *out) {
  size_t cursor = 0;
  const uint8_t *key = NULL;
  const uint8_t *unused = NULL;
  while (ms_map_next(a, kd, NULL, &cursor, &key, &unused)) {
    if (has_membership(test, key)) {
      add_copy(out, kd, key, check);
    }
  }
}

/* True when every key of `a` has the membership `wanted` in `b`. */
static bool all_keys_have(const MsMap *a, const MsTypeDesc *a_kd, const Membership *test) {
  size_t cursor = 0;
  const uint8_t *key = NULL;
  const uint8_t *unused = NULL;
  while (ms_map_next(a, a_kd, NULL, &cursor, &key, &unused)) {
    if (!has_membership(test, key)) {
      return false;
    }
  }
  return true;
}

void msrt_set_union(const MsMap *a, const MsMap *b, const MsTypeDesc *kd, MsMap *out) {
  kd = ms_map_key_desc(a, kd);
  ms_map_clone(a, kd, NULL, out);
  size_t cursor = 0;
  const uint8_t *key = NULL;
  const uint8_t *unused = NULL;
  while (ms_map_next(b, kd, NULL, &cursor, &key, &unused)) {
    add_copy(out, kd, key, true);
  }
}

void msrt_set_intersection(const MsMap *a, const MsMap *b, const MsTypeDesc *kd, MsMap *out) {
  *out = (MsMap){.desc = a->desc};
  if (b->len == 0) {
    return;
  }
  const Membership test = {.other = b, .other_kd = ms_map_key_desc(b, kd), .wanted = true};
  copy_matching(a, ms_map_key_desc(a, kd), &test, false, out); /* `a` has no duplicates */
}

void msrt_set_difference(const MsMap *a, const MsMap *b, const MsTypeDesc *kd, MsMap *out) {
  *out = (MsMap){.desc = a->desc};
  const Membership test = {.other = b, .other_kd = ms_map_key_desc(b, kd), .wanted = false};
  copy_matching(a, ms_map_key_desc(a, kd), &test, false, out);
}

void msrt_set_symmetric_difference(const MsMap *a, const MsMap *b, const MsTypeDesc *kd, MsMap *out) {
  const MsTypeDesc *left_kd = ms_map_key_desc(a, kd);
  msrt_set_difference(a, b, kd, out);
  /* Then the keys of `b` that `a` lacks. */
  const Membership test = {.other = a, .other_kd = left_kd, .wanted = false};
  copy_matching(b, left_kd, &test, true, out);
}

uint8_t msrt_set_is_subset_of(const MsMap *a, const MsMap *b, const MsTypeDesc *kd) {
  const Membership test = {.other = b, .other_kd = ms_map_key_desc(b, kd), .wanted = true};
  return all_keys_have(a, ms_map_key_desc(a, kd), &test);
}

uint8_t msrt_set_is_superset_of(const MsMap *a, const MsMap *b, const MsTypeDesc *kd) {
  return msrt_set_is_subset_of(b, a, ms_map_key_desc(a, kd));
}

uint8_t msrt_set_is_disjoint_from(const MsMap *a, const MsMap *b, const MsTypeDesc *kd) {
  if (b->len == 0) {
    return 1;
  }
  const Membership test = {.other = b, .other_kd = ms_map_key_desc(b, kd), .wanted = false};
  return all_keys_have(a, ms_map_key_desc(a, kd), &test);
}

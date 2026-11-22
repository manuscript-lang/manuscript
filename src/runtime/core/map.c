/* runtime/core/map.c: the natives programs call on maps: lifetime, adding, reading, keys and values. The
 * table, the probing and the hash and equality by type are base/map.h. The `_w8` and `_sw8` variants of a
 * native are the general one: base probes Int and String keys without a callback. */
#include "runtime/core/map.h"

#include "base/alloc.h"
#include "runtime/core/fault.h"
#include "runtime/core/list_support.h"
#include "runtime/core/scratch.h"
#include "runtime/core/string_support.h"

/* ---- lifetime and size ---- */

void msrt_map_new(MsMap *out) {
  *out = (MsMap){0};
}

/* Records creator evidence only for an unstamped collection: a copy or derived collection keeps the creator
 * of the one it came from. `kd` and its nested descriptors and callbacks must be static. */
void msrt_map_stamp(MsMap *m, const MsTypeDesc *kd) {
  if (m->desc == NULL) {
    m->desc = kd;
  }
}

void msrt_map_drop(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd) {
  ms_map_drop(m, ms_map_key_desc(m, kd), vd);
}

void msrt_map_clear(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd) {
  ms_map_drop(m, ms_map_key_desc(m, kd), vd);
}

void msrt_map_copy(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, MsMap *out) {
  ms_map_clone(m, ms_map_key_desc(m, kd), vd, out);
}

void msrt_map_reserve(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, int64_t n) {
  if (n > 0) {
    ms_map_reserve(m, ms_map_key_desc(m, kd), vd, (size_t)n);
  }
}

int64_t msrt_map_length(const MsMap *m) {
  return (int64_t)m->len;
}

int64_t msrt_map_slot_count(const MsMap *m) {
  return (int64_t)m->used;
}

/* Borrowed pointers to the key and value of entry `i`; 0 for a hole. */
uint8_t msrt_map_entry_ptrs(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, int64_t i,
                            const uint8_t **key_out, const uint8_t **val_out) {
  if (i < 0 || (uint64_t)i >= m->used) {
    return 0;
  }
  const MsMapLayout layout = ms_map_layout(ms_map_key_desc(m, kd), vd);
  const uint8_t *entry = ms_table_entry(m, &layout, (size_t)i);
  if (!ms_table_entry_is_live(entry)) {
    return 0;
  }
  *key_out = entry + layout.key_offset;
  if (val_out != NULL) {
    *val_out = entry + layout.value_offset;
  }
  return 1;
}

/* ---- adding ---- */

void msrt_map_add(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, uint8_t *key, uint8_t *val) {
  ms_map_insert(m, ms_map_key_desc(m, kd), vd, key, val);
}

void msrt_map_add_w8(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, uint8_t *key, uint8_t *val) {
  msrt_map_add(m, kd, vd, key, val);
}

void msrt_map_add_sw8(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, uint8_t *key, uint8_t *val) {
  msrt_map_add(m, kd, vd, key, val);
}

/* Stores only when the key is absent; both are consumed either way. */
void msrt_map_add_default(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, uint8_t *key, uint8_t *val) {
  kd = ms_map_key_desc(m, kd);
  if (ms_map_has(m, kd, vd, key)) {
    ms_slot_drop(kd, key);
    ms_slot_drop(vd, val);
    return;
  }
  ms_map_insert(m, kd, vd, key, val);
}

void msrt_map_remove(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key) {
  (void)ms_map_remove(m, ms_map_key_desc(m, kd), vd, key);
}

/* Appends an entry for a borrowed key: the entry owns a copy of the key, and `val` is moved in. Returns the
 * value slot. */
static uint8_t *append_lent(MsMap *m, const MsMapLayout *layout, uint64_t hash, const MsTypeDesc *kd,
                            const uint8_t *key, const uint8_t *val) {
  uint8_t *entry = ms_table_next_entry(m, layout);
  ms_store64(entry, hash);
  ms_slot_copy(kd, key, entry + layout->key_offset);
  __builtin_memcpy(entry + layout->value_offset, val, layout->value_size);
  ms_table_publish(m, hash);
  return entry + layout->value_offset;
}

/* The value slot of a borrowed `key`, appending the entry with `default_value` when it is absent. The
 * default is consumed either way: stored when the entry is new, dropped when it exists. One hash and probe
 * serve a read-modify-write: the caller reads and writes through the returned pointer before the map is
 * used again. */
uint8_t *msrt_map_slot_lent(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key,
                            uint8_t *default_value) {
  kd = ms_map_key_desc(m, kd);
  const MsMapLayout layout = ms_map_layout(kd, vd);
  const MsMapProbe probe = ms_map_probe(m, kd, &layout, key);
  if (probe.entry == MS_MAP_NO_ENTRY) {
    return append_lent(m, &layout, probe.hash, kd, key, default_value);
  }
  ms_slot_drop(vd, default_value);
  return ms_table_entry(m, &layout, probe.entry) + layout.value_offset;
}

/* `add(key, value)` with a borrowed key: it is copied only when the entry is absent, so replacing the value
 * of an existing key allocates nothing. */
void msrt_map_add_lent(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key,
                       uint8_t *val) {
  kd = ms_map_key_desc(m, kd);
  const MsMapLayout layout = ms_map_layout(kd, vd);
  const MsMapProbe probe = ms_map_probe(m, kd, &layout, key);
  if (probe.entry == MS_MAP_NO_ENTRY) {
    (void)append_lent(m, &layout, probe.hash, kd, key, val);
    return;
  }
  uint8_t *value = ms_table_entry(m, &layout, probe.entry) + layout.value_offset;
  ms_slot_drop(vd, value);
  __builtin_memcpy(value, val, layout.value_size);
}

/* `add_default(key, value)` with a borrowed key: nothing is copied or stored when the entry exists. */
void msrt_map_add_default_lent(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key,
                               uint8_t *val) {
  kd = ms_map_key_desc(m, kd);
  const MsMapLayout layout = ms_map_layout(kd, vd);
  const MsMapProbe probe = ms_map_probe(m, kd, &layout, key);
  if (probe.entry == MS_MAP_NO_ENTRY) {
    (void)append_lent(m, &layout, probe.hash, kd, key, val);
    return;
  }
  ms_slot_drop(vd, val);
}

/* `merge(other)`: the entries of `other` (borrowed, copied) replace or append. */
void msrt_map_merge(MsMap *m, const MsMap *other, const MsTypeDesc *kd, const MsTypeDesc *vd) {
  kd = ms_map_key_desc(m, kd);
  if (other->len == 0) {
    return;
  }
  const MsMapLayout layout = ms_map_layout(kd, vd);
  /* Each insertion moves the copied slots in, so the scratch slots are reused for every entry. */
  MsrtScratch key;
  MsrtScratch value;
  msrt_scratch_open(&key, layout.key_size);
  msrt_scratch_open(&value, layout.value_size);
  size_t cursor = 0;
  const uint8_t *entry_key = NULL;
  const uint8_t *entry_value = NULL;
  while (ms_map_next(other, kd, vd, &cursor, &entry_key, &entry_value)) {
    ms_slot_copy(kd, entry_key, key.ptr);
    if (vd != NULL) {
      ms_slot_copy(vd, entry_value, value.ptr);
    }
    ms_map_insert(m, kd, vd, key.ptr, value.ptr);
  }
  msrt_scratch_close(&key);
  msrt_scratch_close(&value);
}

/* ---- reading ---- */

uint8_t msrt_map_contains(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key) {
  return ms_map_has(m, ms_map_key_desc(m, kd), vd, key);
}

uint8_t msrt_map_contains_w8(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key) {
  return msrt_map_contains(m, kd, vd, key);
}

uint8_t msrt_map_contains_sw8(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd,
                              const uint8_t *key) {
  return msrt_map_contains(m, kd, vd, key);
}

uint8_t msrt_set_contains_w(const MsMap *m, const MsTypeDesc *kd, const uint8_t *key) {
  return msrt_map_contains(m, kd, NULL, key);
}

const uint8_t *msrt_map_get_ptr(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd,
                                const uint8_t *key) {
  return ms_map_get(m, ms_map_key_desc(m, kd), vd, key);
}

const uint8_t *msrt_map_get_ptr_w8(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd,
                                   const uint8_t *key) {
  return msrt_map_get_ptr(m, kd, vd, key);
}

const uint8_t *msrt_map_get_ptr_sw8(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd,
                                    const uint8_t *key) {
  return msrt_map_get_ptr(m, kd, vd, key);
}

uint8_t msrt_map_get(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key,
                     uint8_t *out) {
  const uint8_t *value = msrt_map_get_ptr(m, kd, vd, key);
  if (value == NULL) {
    return 0;
  }
  ms_slot_copy(vd, value, out);
  return 1;
}

uint8_t msrt_map_get_w8(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key,
                        uint8_t *out) {
  return msrt_map_get(m, kd, vd, key, out);
}

uint8_t msrt_map_get_sw8(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key,
                         uint8_t *out) {
  return msrt_map_get(m, kd, vd, key, out);
}

/* The stored value, or a copy of `fallback`; both are copied into `out`. */
void msrt_map_get_or(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key,
                     const uint8_t *fallback, uint8_t *out) {
  const uint8_t *value = msrt_map_get_ptr(m, kd, vd, key);
  ms_slot_copy(vd, value != NULL ? value : fallback, out);
}

/* ---- keys() and values() ---- */

/* How a key or a value of an entry becomes an element of the list a `keys` or `values` call returns. */
typedef void (*CollectFn)(const MsTypeDesc *d, const uint8_t *slot, uint8_t *element);

static void collect_copy(const MsTypeDesc *d, const uint8_t *slot, uint8_t *element) {
  ms_slot_copy(d, slot, element);
}

/* A string that borrows what `slot` holds: a view of an owned string's bytes, the same words for any
 * other. */
static void collect_borrow(const MsTypeDesc *d, const uint8_t *slot, uint8_t *element) {
  const MsString *string = (const MsString *)__builtin_assume_aligned(slot, _Alignof(MsString));
  MsString borrowed = *string;
  if (msrt_string_owns(string)) {
    borrowed = msrt_string_view_of(msrt_text(string));
  }
  __builtin_memcpy(element, &borrowed, sizeof borrowed);
  (void)d;
}

/* A list of the keys (or the values) of `m`, each made by `make`. */
static void collect(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, bool keys, CollectFn make,
                    MsList *out) {
  const MsTypeDesc *d = keys || vd == NULL ? kd : vd;
  if (m->len == 0) {
    *out = (MsList){0};
    return;
  }
  const MsMapLayout layout = ms_map_layout(kd, vd);
  const size_t offset = keys ? layout.key_offset : layout.value_offset;
  MsList list = {.ptr = ms_alloc(msrt_list_buffer_bytes(m->len, d->size)), .len = 0, .cap = m->len};
  for (size_t number = 0; number < m->used; number++) {
    const uint8_t *entry = ms_table_entry(m, &layout, number);
    if (ms_table_entry_is_live(entry)) {
      make(d, entry + offset, list.ptr + list.len * d->size);
      list.len++;
    }
  }
  *out = list;
}

void msrt_map_keys(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, MsList *out) {
  collect(m, ms_map_key_desc(m, kd), vd, true, collect_copy, out);
}

void msrt_map_values(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, MsList *out) {
  collect(m, ms_map_key_desc(m, kd), vd, false, collect_copy, out);
}

/* `for k in m.keys()` over a map that outlives the loop unchanged: string keys come back as views of the
 * map's own strings, so nothing is copied. Other keys are copied as by `keys`. */
static CollectFn view_maker(const MsTypeDesc *d) {
  return d->kind == MS_KIND_STRING ? collect_borrow : collect_copy;
}

void msrt_map_keys_view(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, MsList *out) {
  kd = ms_map_key_desc(m, kd);
  collect(m, kd, vd, true, view_maker(kd), out);
}

void msrt_map_values_view(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, MsList *out) {
  kd = ms_map_key_desc(m, kd);
  collect(m, kd, vd, false, view_maker(vd != NULL ? vd : kd), out);
}

void msrt_set_values(const MsMap *m, const MsTypeDesc *kd, MsList *out) {
  msrt_map_keys(m, kd, NULL, out);
}

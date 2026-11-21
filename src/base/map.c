/* Owns the erased tier of the map: probing, insertion, removal, copy and equality driven by type
 * descriptors (see map.h). The key-independent table work is in table.c. */
#include "base/map.h"

#include "base/alloc.h"

static uint64_t int_hash(const void *context, const uint8_t *key) {
  (void)context;
  return ms_hash_int(ms_load64(key));
}

static bool int_equal(const void *context, const uint8_t *stored, const uint8_t *key) {
  (void)context;
  return ms_load64(stored) == ms_load64(key);
}

static uint64_t string_hash(const void *context, const uint8_t *key) {
  (void)context;
  return ms_string_hash((const MsString *)(const void *)key);
}

static bool string_equal(const void *context, const uint8_t *stored, const uint8_t *key) {
  (void)context;
  return ms_string_equal((const MsString *)(const void *)stored, (const MsString *)(const void *)key);
}

/* Plain bits without padding: equal when the bytes are equal. */
static uint64_t blob_hash(const void *context, const uint8_t *key) {
  const MsTypeDesc *desc = context;
  return ms_hash_span(ms_span_of(key, desc->size));
}

static bool blob_equal(const void *context, const uint8_t *stored, const uint8_t *key) {
  const MsTypeDesc *desc = context;
  return __builtin_memcmp(stored, key, desc->size) == 0;
}

/* A user's hash is often the identity of a couple of small ints, whose runs of consecutive values would
 * cluster under linear probing, so the table sees a mixed hash. */
static uint64_t desc_hash(const void *context, const uint8_t *key) {
  return ms_hash_int(ms_slot_hash(context, key));
}

static bool desc_equal(const void *context, const uint8_t *stored, const uint8_t *key) {
  return ms_slot_equal(context, stored, key);
}

static const MsKeyOps int_keys = {.cheap_equal = true, .hash = int_hash, .equal = int_equal};
static const MsKeyOps string_keys = {.cheap_equal = false, .hash = string_hash, .equal = string_equal};
static const MsKeyOps blob_keys = {.cheap_equal = true, .hash = blob_hash, .equal = blob_equal};
static const MsKeyOps desc_keys = {.cheap_equal = false, .hash = desc_hash, .equal = desc_equal};

MsMapProbe ms_map_probe(const MsMap *map, const MsTypeDesc *key, const MsMapLayout *layout,
                        const uint8_t *key_slot) {
  MsMapProbe probe = {0, MS_MAP_NO_ENTRY};
  if (key->kind == MS_KIND_INT) {
    probe.hash = ms_table_hash(&int_keys, key, key_slot);
    probe.entry = ms_table_find(&int_keys, key, map, layout, key_slot, probe.hash);
  } else if (key->kind == MS_KIND_STRING) {
    probe.hash = ms_table_hash(&string_keys, key, key_slot);
    probe.entry = ms_table_find(&string_keys, key, map, layout, key_slot, probe.hash);
  } else if (key->kind == MS_KIND_POD && key->eq == NULL && key->hash == NULL) {
    probe.hash = ms_table_hash(&blob_keys, key, key_slot);
    probe.entry = ms_table_find(&blob_keys, key, map, layout, key_slot, probe.hash);
  } else {
    probe.hash = ms_table_hash(&desc_keys, key, key_slot);
    probe.entry = ms_table_find(&desc_keys, key, map, layout, key_slot, probe.hash);
  }
  return probe;
}

bool ms_map_has(const MsMap *map, const MsTypeDesc *key, const MsTypeDesc *value, const uint8_t *key_slot) {
  if (map->len == 0) {
    return false;
  }
  const MsMapLayout layout = ms_map_layout(key, value);
  return ms_map_probe(map, key, &layout, key_slot).entry != MS_MAP_NO_ENTRY;
}

const uint8_t *ms_map_get(const MsMap *map, const MsTypeDesc *key, const MsTypeDesc *value,
                          const uint8_t *key_slot) {
  if (map->len == 0 || value == NULL) {
    return NULL;
  }
  const MsMapLayout layout = ms_map_layout(key, value);
  const MsMapProbe probe = ms_map_probe(map, key, &layout, key_slot);
  return probe.entry == MS_MAP_NO_ENTRY ? NULL
                                        : ms_table_entry(map, &layout, probe.entry) + layout.value_offset;
}

void ms_map_reserve(MsMap *map, const MsTypeDesc *key, const MsTypeDesc *value, size_t count) {
  const MsMapLayout layout = ms_map_layout(key, value);
  size_t total = 0;
  if (ms_size_add(map->used, count, &total)) {
    ms_table_reserve(map, &layout, total);
  }
}

void ms_map_insert(MsMap *map, const MsTypeDesc *key, const MsTypeDesc *value, uint8_t *key_slot,
                   uint8_t *value_slot) {
  const MsMapLayout layout = ms_map_layout(key, value);
  const MsMapProbe probe = ms_map_probe(map, key, &layout, key_slot);
  if (probe.entry != MS_MAP_NO_ENTRY) { /* the key exists: the new key is dropped and the value replaced */
    uint8_t *stored = ms_table_entry(map, &layout, probe.entry) + layout.value_offset;
    ms_slot_drop(key, key_slot);
    if (value != NULL) {
      ms_slot_drop(value, stored);
      __builtin_memcpy(stored, value_slot, layout.value_size);
    }
    return;
  }
  uint8_t *entry = ms_table_next_entry(map, &layout);
  ms_store64(entry, probe.hash);
  __builtin_memcpy(entry + layout.key_offset, key_slot, layout.key_size);
  if (value != NULL) {
    __builtin_memcpy(entry + layout.value_offset, value_slot, layout.value_size);
  }
  ms_table_publish(map, probe.hash);
}

bool ms_map_remove(MsMap *map, const MsTypeDesc *key, const MsTypeDesc *value, const uint8_t *key_slot) {
  if (map->len == 0) {
    return false;
  }
  const MsMapLayout layout = ms_map_layout(key, value);
  const MsMapProbe probe = ms_map_probe(map, key, &layout, key_slot);
  if (probe.entry == MS_MAP_NO_ENTRY) {
    return false;
  }
  uint8_t *entry = ms_table_entry(map, &layout, probe.entry);
  ms_slot_drop(key, entry + layout.key_offset);
  if (value != NULL) {
    ms_slot_drop(value, entry + layout.value_offset);
  }
  ms_table_unlink(map, &layout, probe.hash, probe.entry);
  return true;
}

void ms_map_drop(MsMap *map, const MsTypeDesc *key, const MsTypeDesc *value) {
  if (map->slots == NULL) {
    return;
  }
  const MsMapLayout layout = ms_map_layout(key, value);
  if (!ms_desc_drop_is_noop(key) || (value != NULL && !ms_desc_drop_is_noop(value))) {
    for (size_t number = 0; number < map->used; number++) {
      uint8_t *entry = ms_table_entry(map, &layout, number);
      if (!ms_table_entry_is_live(entry)) {
        continue;
      }
      ms_slot_drop(key, entry + layout.key_offset);
      if (value != NULL) {
        ms_slot_drop(value, entry + layout.value_offset);
      }
    }
  }
  ms_table_free(map);
}

void ms_map_clone(const MsMap *source, const MsTypeDesc *key, const MsTypeDesc *value, MsMap *out) {
  const MsMapLayout layout = ms_map_layout(key, value);
  ms_table_copy_shape(source, &layout, out);
  if (ms_desc_is_plain(key) && (value == NULL || ms_desc_is_plain(value))) {
    return; /* nothing is owned: the bitwise copy is the clone */
  }
  /* The shape copy left each owned part shared with the source: deep-copy them, entry by entry in order. */
  size_t from_number = 0;
  for (size_t number = 0; number < out->used; number++) {
    while (!ms_table_entry_is_live(ms_table_entry(source, &layout, from_number))) {
      from_number++;
    }
    const uint8_t *from = ms_table_entry(source, &layout, from_number++);
    uint8_t *to = ms_table_entry(out, &layout, number);
    ms_slot_copy(key, from + layout.key_offset, to + layout.key_offset);
    if (value != NULL) {
      ms_slot_copy(value, from + layout.value_offset, to + layout.value_offset);
    }
  }
}

bool ms_map_equal(const MsMap *a, const MsMap *b, const MsTypeDesc *key, const MsTypeDesc *value) {
  if (a->len != b->len) {
    return false;
  }
  /* Probe `b` with the identity that built it: the caller may have a different implementation. */
  key = ms_map_key_desc(b, key);
  const MsMapLayout layout = ms_map_layout(key, value);
  for (size_t number = 0; number < a->used; number++) {
    const uint8_t *entry = ms_table_entry(a, &layout, number);
    if (!ms_table_entry_is_live(entry)) {
      continue;
    }
    const MsMapProbe probe = ms_map_probe(b, key, &layout, entry + layout.key_offset);
    if (probe.entry == MS_MAP_NO_ENTRY) {
      return false;
    }
    const uint8_t *other = ms_table_entry(b, &layout, probe.entry);
    if (value != NULL && !ms_slot_equal(value, entry + layout.value_offset, other + layout.value_offset)) {
      return false;
    }
  }
  return true;
}

bool ms_map_next(const MsMap *map, const MsTypeDesc *key, const MsTypeDesc *value, size_t *cursor,
                 const uint8_t **key_slot, const uint8_t **value_slot) {
  const MsMapLayout layout = ms_map_layout(key, value);
  while (*cursor < map->used) {
    const uint8_t *entry = ms_table_entry(map, &layout, (*cursor)++);
    if (ms_table_entry_is_live(entry)) {
      *key_slot = entry + layout.key_offset;
      *value_slot = value != NULL ? entry + layout.value_offset : NULL;
      return true;
    }
  }
  return false;
}

/* base/map.h: MsMap, the insertion-ordered hash map and set, in two tiers over one design.
 *
 * Layout (the program ABI; generated code probes Int-keyed maps with this exact layout and hash): an
 * append-only array of entries `{hash, key, value}` spaced `stride` bytes apart, plus an open-addressing
 * index of 64-bit words. The high half of an index word is the hash's high half (a tag, so a probe skips
 * non-matching entries without touching them) and the low half is the entry number plus one (0 empty,
 * 0xffffffff removed). The top bit of an entry's hash word is set while it is live. A removal leaves a hole
 * that scans skip and compaction reclaims, so iteration order is insertion order and deterministic.
 * A set is a map without values. A zeroed MsMap is an empty map.
 *
 * Erased tier: ms_map_* take descriptors (base/desc.h) and serve runtime values of any type.
 * Specialized tier: MS_MAP_DEFINE / MS_SET_DEFINE instantiate the same map layout and the same core
 * (ms_table_*) for one plain key type, with hash and equality inlined, for the compiler's tables. Plain
 * means the key and value own nothing and copy bitwise. Names that are dense ids need neither tier: use an
 * array or a bitset indexed by the id.
 *
 * Ownership: the map owns its entries and the two buffers; a key or value moved in is owned by the map. A
 * pointer returned by a lookup or iteration is valid until the next insert or remove. */
#ifndef MS_BASE_MAP_H
#define MS_BASE_MAP_H

#include "base/desc.h"
#include "base/hash.h"

typedef struct MsMap {
  uint8_t *slots;         /* owned: append-only entries: hash word (top bit set when live), key, value */
  uint64_t *index;        /* owned: open-addressing index */
  size_t len;             /* live entries */
  size_t used;            /* slots used so far, removed ones included */
  size_t cap;             /* slot capacity */
  size_t mask;            /* index size minus one; 0 when there is no index */
  const MsTypeDesc *desc; /* the creator's key descriptor, or NULL */
} MsMap;

_Static_assert(sizeof(MsMap) == 56 && offsetof(MsMap, len) == 16, "map layout is ABI");

#define MS_MAP_LIVE (UINT64_C(1) << 63)
#define MS_MAP_INDEX_REMOVED UINT64_C(0xffffffff)
#define MS_MAP_NO_ENTRY SIZE_MAX
#define MS_MAP_MAX_CAP ((size_t)UINT32_MAX / 2) /* entry numbers are 32 bits in the index */

/* Where the parts of an entry sit. */
typedef struct MsMapLayout {
  size_t key_offset;
  size_t value_offset;
  size_t stride;
  size_t key_size;
  size_t value_size;
} MsMapLayout;

static inline size_t ms_map_align_up(size_t n, size_t align) { return (n + align - 1) & ~(align - 1); }

/* The layout for a key and (value_size 0 for a set) value of the given sizes and alignments. Constant
 * folded when the arguments are. */
static inline MsMapLayout ms_map_layout_of(size_t key_size, size_t key_align, size_t value_size,
                                           size_t value_align) {
  const size_t key_aligned = key_align > 8 ? key_align : 8;
  const size_t key_offset = ms_map_align_up(8, key_aligned);
  const size_t value_aligned = value_align < 1 ? 1 : value_align;
  const size_t value_offset = ms_map_align_up(key_offset + key_size, value_aligned);
  size_t stride_align = key_aligned > value_aligned ? key_aligned : value_aligned;
  stride_align = stride_align > 8 ? stride_align : 8;
  return (MsMapLayout){.key_offset = key_offset,
                       .value_offset = value_offset,
                       .stride = ms_map_align_up(value_offset + value_size, stride_align),
                       .key_size = key_size,
                       .value_size = value_size};
}

/* The layout of a map with keys `key` and values `value` (NULL for a set). */
static inline MsMapLayout ms_map_layout(const MsTypeDesc *key, const MsTypeDesc *value) {
  return ms_map_layout_of(key->size, key->align, value != NULL ? value->size : 0,
                          value != NULL ? value->align : 1);
}

static inline uint8_t *ms_table_entry(const MsMap *map, const MsMapLayout *layout, size_t number) {
  return map->slots + number * layout->stride;
}

static inline uint64_t ms_table_entry_hash(const uint8_t *entry) { return ms_load64(entry); }

static inline bool ms_table_entry_is_live(const uint8_t *entry) {
  return (ms_table_entry_hash(entry) & MS_MAP_LIVE) != 0;
}

/* Where a hash starts probing. */
static inline size_t ms_table_home(const MsMap *map, uint64_t hash) {
  return ((size_t)hash ^ (size_t)(hash >> 32)) & map->mask;
}

static inline uint64_t ms_table_index_word(uint64_t hash, size_t number) {
  return (hash & ~UINT64_C(0xffffffff)) | ((uint64_t)number + 1);
}

/* ---- the core: no knowledge of keys (table.c) ---- */

/* Makes room for one more entry (compacts when half the entries are holes, else doubles). */
void ms_table_grow(MsMap *map, const MsMapLayout *layout);

/* Room for `count` entries, so that adding that many never regrows the table. */
void ms_table_reserve(MsMap *map, const MsMapLayout *layout, size_t count);

/* The room for one more entry, growing when full: the address where the caller writes hash, key and value
 * before calling ms_table_publish. */
static inline uint8_t *ms_table_next_entry(MsMap *map, const MsMapLayout *layout) {
  if (map->used == map->cap) {
    ms_table_grow(map, layout);
  }
  return ms_table_entry(map, layout, map->used);
}

/* Links the entry written at ms_table_next_entry into the index, so lookups find it. */
static inline void ms_table_publish(MsMap *map, uint64_t hash) {
  size_t pos = ms_table_home(map, hash);
  while (map->index[pos] != 0 && map->index[pos] != MS_MAP_INDEX_REMOVED) {
    pos = (pos + 1) & map->mask;
  }
  map->index[pos] = ms_table_index_word(hash, map->used);
  map->used++;
  map->len++;
}

/* Marks entry `number` (found with `hash`) removed; the caller dropped its key and value. May compact. */
void ms_table_unlink(MsMap *map, const MsMapLayout *layout, uint64_t hash, size_t number);

/* Frees both buffers and leaves the map empty (the creator's descriptor stays). */
void ms_table_free(MsMap *map);

/* The live entries of `source` copied bitwise (holes squeezed out) into an empty `out`; the caller then
 * fixes up owned parts. Returns the number of entries. */
void ms_table_copy_shape(const MsMap *source, const MsMapLayout *layout, MsMap *out);

/* ---- probing: the one place hash and equality are applied ---- */

/* Hash and equality of one kind of key. Hot probe loops pass a static const MapKeyOps so that the calls
 * are resolved at compile time. `equal` compares a stored key with the probe key. */
typedef struct MsKeyOps {
  bool cheap_equal; /* equality is cheaper than reading the entry's stored hash */
  uint64_t (*hash)(const void *context, const uint8_t *key);
  bool (*equal)(const void *context, const uint8_t *stored, const uint8_t *key);
} MsKeyOps;

/* The hash a table stores for a key: its key hash with the live bit. */
static inline MS_ALWAYS_INLINE uint64_t ms_table_hash(const MsKeyOps *ops, const void *context,
                                                      const uint8_t *key) {
  return ops->hash(context, key) | MS_MAP_LIVE;
}

/* The number of the entry holding `key` (whose stored hash is `hash`), or MS_MAP_NO_ENTRY. */
static inline MS_ALWAYS_INLINE size_t ms_table_find(const MsKeyOps *ops, const void *context, const MsMap *map,
                                                    const MsMapLayout *layout, const uint8_t *key,
                                                    uint64_t hash) {
  if (map->len == 0) {
    return MS_MAP_NO_ENTRY;
  }
  size_t pos = ms_table_home(map, hash);
  for (;;) {
    const uint64_t word = map->index[pos];
    if (word == 0) {
      return MS_MAP_NO_ENTRY;
    }
    if (((word ^ hash) >> 32) == 0) {
      const size_t number = (size_t)((uint32_t)word - 1U);
      const uint8_t *entry = ms_table_entry(map, layout, number);
      if ((ops->cheap_equal || ms_table_entry_hash(entry) == hash) &&
          ops->equal(context, entry + layout->key_offset, key)) {
        return number;
      }
    }
    pos = (pos + 1) & map->mask;
  }
}

/* ---- erased tier ---- */

/* The key descriptor a map was created with, else the caller's: a collection keeps the equality and hash
 * of the module that made it. */
static inline const MsTypeDesc *ms_map_key_desc(const MsMap *map, const MsTypeDesc *key) {
  return map->desc != NULL ? map->desc : key;
}

/* A probe: the stored hash of the key and the entry holding it. */
typedef struct MsMapProbe {
  uint64_t hash;
  size_t entry; /* MS_MAP_NO_ENTRY when the key is absent */
} MsMapProbe;

MsMapProbe ms_map_probe(const MsMap *map, const MsTypeDesc *key, const MsMapLayout *layout,
                        const uint8_t *key_slot);

/* Adds `key` and `value` (both moved in; `value` may be NULL for a set), or replaces the value of an equal
 * key and drops `key`. */
void ms_map_insert(MsMap *map, const MsTypeDesc *key, const MsTypeDesc *value, uint8_t *key_slot,
                   uint8_t *value_slot);

bool ms_map_has(const MsMap *map, const MsTypeDesc *key, const MsTypeDesc *value, const uint8_t *key_slot);

/* The value stored for `key`, or NULL; valid until the map changes. A set has no values. */
const uint8_t *ms_map_get(const MsMap *map, const MsTypeDesc *key, const MsTypeDesc *value,
                          const uint8_t *key_slot);

/* Removes `key`, dropping the stored key and value. True when it was present. */
bool ms_map_remove(MsMap *map, const MsTypeDesc *key, const MsTypeDesc *value, const uint8_t *key_slot);

/* Frees the entries and storage. The creator's descriptor stays. */
void ms_map_drop(MsMap *map, const MsTypeDesc *key, const MsTypeDesc *value);

/* A deep copy of `source` in insertion order, without its holes, into the uninitialised `out`. */
void ms_map_clone(const MsMap *source, const MsTypeDesc *key, const MsTypeDesc *value, MsMap *out);

/* Order-independent equality. */
bool ms_map_equal(const MsMap *a, const MsMap *b, const MsTypeDesc *key, const MsTypeDesc *value);

/* Room for `count` more entries. */
void ms_map_reserve(MsMap *map, const MsTypeDesc *key, const MsTypeDesc *value, size_t count);

/* Iteration in insertion order: start with *cursor = 0; each true result gives the next live entry's key and
 * (for a map) value, and advances the cursor. */
MS_NODISCARD MS_NONNULL_ARGS(1, 2, 4, 5, 6) bool ms_map_next(const MsMap *map, const MsTypeDesc *key,
                                                        const MsTypeDesc *value, size_t *cursor,
                                                        const uint8_t **key_slot, const uint8_t **value_slot);

/* ---- specialized tier ---- */

/* Typed map over a plain key K and plain value V, same layout and core as the erased tier, hash and equality
 * inlined:
 *   MS_MAP_DEFINE(SymbolMap, symbol_map, SymbolId, Symbol*, ms_hash_u32_key, ms_equal_u32_key)
 * defines symbol_map_put, _get (pointer to the value or NULL), _has, _remove, _free, _reserve and _next.
 * `hash(const K *)` returns uint64_t, `equal(const K *, const K *)` returns bool. A zeroed map is empty. */
#define MS_MAP_DEFINE(Name, prefix, K, V, hash_fn, equal_fn)                                                  \
  typedef struct Name {                                                                                       \
    MsMap table;                                                                                              \
  } Name;                                                                                                     \
  MS_UNUSED static inline uint64_t prefix##_hash_(const void *context, const uint8_t *key) {                 \
    (void)context;                                                                                            \
    return hash_fn((const K *)(const void *)key);                                                             \
  }                                                                                                           \
  MS_UNUSED static inline bool prefix##_equal_(const void *context, const uint8_t *stored,                    \
                                               const uint8_t *key) {                                          \
    (void)context;                                                                                            \
    return equal_fn((const K *)(const void *)stored, (const K *)(const void *)key);                          \
  }                                                                                                           \
  static const MsKeyOps prefix##_ops_ = {.cheap_equal = true, .hash = prefix##_hash_,                        \
                                         .equal = prefix##_equal_};                                          \
  MS_UNUSED static inline MsMapLayout prefix##_layout_(void) {                                                \
    return ms_map_layout_of(sizeof(K), _Alignof(K), sizeof(V), _Alignof(V));                                  \
  }                                                                                                           \
  MS_UNUSED static inline V *prefix##_get(const Name *map, K key) {                                           \
    const MsMapLayout layout = prefix##_layout_();                                                            \
    const uint64_t hash = ms_table_hash(&prefix##_ops_, NULL, (const uint8_t *)&key);                         \
    const size_t number =                                                                                     \
        ms_table_find(&prefix##_ops_, NULL, &map->table, &layout, (const uint8_t *)&key, hash);               \
    return number == MS_MAP_NO_ENTRY                                                                          \
               ? NULL                                                                                         \
               : (V *)(void *)(ms_table_entry(&map->table, &layout, number) + layout.value_offset);           \
  }                                                                                                           \
  MS_UNUSED static inline bool prefix##_has(const Name *map, K key) { return prefix##_get(map, key) != NULL; } \
  /* Adds or replaces; the previous value is not dropped (V is plain). */                                     \
  MS_UNUSED static inline void prefix##_put(Name *map, K key, V value) {                                      \
    const MsMapLayout layout = prefix##_layout_();                                                            \
    const uint64_t hash = ms_table_hash(&prefix##_ops_, NULL, (const uint8_t *)&key);                         \
    const size_t number =                                                                                     \
        ms_table_find(&prefix##_ops_, NULL, &map->table, &layout, (const uint8_t *)&key, hash);               \
    if (number != MS_MAP_NO_ENTRY) {                                                                          \
      __builtin_memcpy(ms_table_entry(&map->table, &layout, number) + layout.value_offset, &value,            \
                       sizeof(V));                                                                            \
      return;                                                                                                 \
    }                                                                                                         \
    uint8_t *entry = ms_table_next_entry(&map->table, &layout);                                               \
    ms_store64(entry, hash);                                                                                  \
    __builtin_memcpy(entry + layout.key_offset, &key, sizeof(K));                                             \
    __builtin_memcpy(entry + layout.value_offset, &value, sizeof(V));                                         \
    ms_table_publish(&map->table, hash);                                                                      \
  }                                                                                                           \
  MS_UNUSED static inline bool prefix##_remove(Name *map, K key) {                                            \
    const MsMapLayout layout = prefix##_layout_();                                                            \
    const uint64_t hash = ms_table_hash(&prefix##_ops_, NULL, (const uint8_t *)&key);                         \
    const size_t number =                                                                                     \
        ms_table_find(&prefix##_ops_, NULL, &map->table, &layout, (const uint8_t *)&key, hash);               \
    if (number == MS_MAP_NO_ENTRY) {                                                                          \
      return false;                                                                                           \
    }                                                                                                         \
    ms_table_unlink(&map->table, &layout, hash, number);                                                      \
    return true;                                                                                              \
  }                                                                                                           \
  MS_UNUSED static inline void prefix##_reserve(Name *map, size_t count) {                                    \
    const MsMapLayout layout = prefix##_layout_();                                                            \
    ms_table_reserve(&map->table, &layout, count);                                                            \
  }                                                                                                           \
  /* Iteration in insertion order: *cursor starts at 0. */                                                    \
  MS_UNUSED MS_NODISCARD static inline bool prefix##_next(const Name *map, size_t *cursor, K *key,            \
                                                          V **value) {                                        \
    const MsMapLayout layout = prefix##_layout_();                                                            \
    while (*cursor < map->table.used) {                                                                       \
      uint8_t *entry = ms_table_entry(&map->table, &layout, (*cursor)++);                                     \
      if (ms_table_entry_is_live(entry)) {                                                                    \
        __builtin_memcpy(key, entry + layout.key_offset, sizeof(K));                                          \
        *value = (V *)(void *)(entry + layout.value_offset);                                                  \
        return true;                                                                                          \
      }                                                                                                       \
    }                                                                                                         \
    return false;                                                                                             \
  }                                                                                                           \
  MS_UNUSED static inline void prefix##_free(Name *map) { ms_table_free(&map->table); }

/* Typed set: a map whose value is a one-byte unit (so its stride is larger than an erased set's: tables of
 * the two tiers are never passed to each other's functions). */
#define MS_SET_DEFINE(Name, prefix, K, hash_fn, equal_fn)                                                     \
  MS_MAP_DEFINE(Name, prefix, K, uint8_t, hash_fn, equal_fn)                                                  \
  MS_UNUSED static inline bool prefix##_add(Name *set, K key) {                                               \
    if (prefix##_has(set, key)) {                                                                             \
      return false;                                                                                           \
    }                                                                                                         \
    prefix##_put(set, key, 1);                                                                                \
    return true;                                                                                              \
  }                                                                                                           \
  MS_UNUSED static inline bool prefix##_contains(const Name *set, K key) { return prefix##_has(set, key); }

/* Hash and equality of the common plain keys. */
static inline uint64_t ms_hash_u32_key(const uint32_t *key) { return ms_hash_int(*key); }
static inline bool ms_equal_u32_key(const uint32_t *a, const uint32_t *b) { return *a == *b; }
static inline uint64_t ms_hash_u64_key(const uint64_t *key) { return ms_hash_int(*key); }
static inline bool ms_equal_u64_key(const uint64_t *a, const uint64_t *b) { return *a == *b; }

#endif

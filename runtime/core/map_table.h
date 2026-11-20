/* map_table.h: the table behind maps and sets, shared by map.c (growth, removal, copy, equality) and
 * map_api.c (the natives programs call).
 *
 * A map is an append-only array of entries `{hash, key, value}` spaced `stride` bytes apart, plus an
 * open-addressing index of 64-bit words: the high half is the hash's high half (a tag, so a probe skips
 * non-matching entries without touching them) and the low half is the entry number plus one (0 empty,
 * 0xffffffff removed). The top bit of an entry's hash word is set while it is live. A removal leaves a
 * hole that scans skip and compaction reclaims. Generated code probes Int-keyed maps with this exact
 * layout and hash (crates/ms-lower), so none of it changes without the compiler.
 */
#ifndef MS_MAP_TABLE_H
#define MS_MAP_TABLE_H

#include "hash.h"
#include "ms_rt/alloc.h"
#include "ms_rt/desc.h"
#include "ms_rt/safe.h"
#include "ms_rt/string.h"
#include "slot.h"
#include "str_key.h"

#define MS_MAP_LIVE (UINT64_C(1) << 63)
#define MS_MAP_INDEX_REMOVED UINT64_C(0xffffffff)
#define MS_MAP_NO_ENTRY SIZE_MAX
/* Entry numbers are 32 bits in the index. */
#define MS_MAP_MAX_CAP ((size_t)UINT32_MAX / 2)

/* Where the parts of an entry sit, from the key and value descriptors. */
typedef struct MapLayout {
    size_t key_offset;
    size_t value_offset;
    size_t stride;
    size_t key_size;
    size_t value_size;
} MapLayout;

static inline size_t ms_map_align_up(size_t n, size_t align) { return (n + align - 1) & ~(align - 1); }

/* True for an 8-byte, 8-aligned slot. */
static inline bool ms_map_is_word(const MsTypeDesc *d) { return d->size == 8 && d->align == 8; }

/* The layout of a map with keys `kd` and values `vd` (NULL for a set). */
static inline MapLayout ms_map_layout(const MsTypeDesc *kd, const MsTypeDesc *vd) {
    /* Int, Float and pointer keys and values are the common case. */
    if (ms_map_is_word(kd) && vd != NULL && ms_map_is_word(vd)) {
        return (MapLayout){.key_offset = 8, .value_offset = 16, .stride = 24, .key_size = 8, .value_size = 8};
    }
    const size_t key_size = kd->size;
    /* Slots of whole words need only additions. */
    if (kd->align == 8 && key_size % 8 == 0) {
        if (vd == NULL) {
            return (MapLayout){.key_offset = 8, .value_offset = 8 + key_size, .stride = 8 + key_size, .key_size = key_size, .value_size = 0};
        }
        if (vd->align == 8 && vd->size % 8 == 0) {
            return (MapLayout){.key_offset = 8, .value_offset = 8 + key_size, .stride = 8 + key_size + vd->size, .key_size = key_size, .value_size = vd->size};
        }
    }
    const size_t key_align = kd->align > 8 ? kd->align : 8;
    const size_t key_offset = ms_map_align_up(8, key_align);
    const size_t value_align = vd == NULL || vd->align < 1 ? 1 : vd->align;
    const size_t value_size = vd == NULL ? 0 : vd->size;
    const size_t value_offset = ms_map_align_up(key_offset + key_size, value_align);
    size_t stride_align = key_align > value_align ? key_align : value_align;
    stride_align = stride_align > 8 ? stride_align : 8;
    return (MapLayout){.key_offset = key_offset,
                       .value_offset = value_offset,
                       .stride = ms_map_align_up(value_offset + value_size, stride_align),
                       .key_size = key_size,
                       .value_size = value_size};
}

static inline uint64_t ms_map_load_hash(const uint8_t *entry) { return ms_load64(entry); }

static inline void ms_map_store_hash(uint8_t *entry, uint64_t hash) { __builtin_memcpy(entry, &hash, sizeof hash); }

static inline uint8_t *ms_map_entry(const MsMap *m, const MapLayout *l, size_t number) {
    return m->slots + number * l->stride;
}

static inline bool ms_map_entry_is_live(const uint8_t *entry) { return (ms_map_load_hash(entry) & MS_MAP_LIVE) != 0; }

/* Where a hash starts probing. */
static inline size_t ms_map_home(const MsMap *m, uint64_t hash) { return ((size_t)hash ^ (size_t)(hash >> 32)) & m->mask; }

/* The index word of entry `number` with hash `hash`. */
static inline uint64_t ms_map_index_word(uint64_t hash, size_t number) {
    return (hash & ~UINT64_C(0xffffffff)) | ((uint64_t)number + 1);
}

/* ---- Keys ----
 *
 * Hash, equality and ownership of one kind of key, resolved once per probe so that Int, String and plain
 * keys each get a probe loop with their own code inlined, and every other key goes through its descriptor.
 */
typedef struct MapKeyOps {
    bool cheap_eq; /* equality is cheaper than reading the entry's stored hash */
    uint64_t (*hash)(const MsTypeDesc *kd, const uint8_t *key);
    bool (*equal)(const MsTypeDesc *kd, const uint8_t *stored, const uint8_t *key);
} MapKeyOps;

static inline uint64_t int_key_hash(const MsTypeDesc *kd, const uint8_t *key) {
    (void)kd;
    return ms_hash_int(ms_load64(key));
}

static inline bool int_key_equal(const MsTypeDesc *kd, const uint8_t *stored, const uint8_t *key) {
    (void)kd;
    return ms_load64(stored) == ms_load64(key);
}

static inline const MsStr *key_str(const uint8_t *key) {
    return (const MsStr *)__builtin_assume_aligned(key, _Alignof(MsStr));
}

static inline uint64_t str_key_hash(const MsTypeDesc *kd, const uint8_t *key) {
    (void)kd;
    return ms_str_hash(key_str(key));
}

static inline bool str_key_equal(const MsTypeDesc *kd, const uint8_t *stored, const uint8_t *key) {
    (void)kd;
    return ms_str_equal(key_str(stored), key_str(key));
}

/* Plain bits without padding: equal when the bytes are equal. */
static inline uint64_t blob_key_hash(const MsTypeDesc *kd, const uint8_t *key) {
    if (kd->size % 8 != 0) {
        return ms_hash_bytes(key, kd->size);
    }
    uint64_t h = MS_HASH_K0;
    for (size_t i = 0; i < kd->size; i += 8) {
        h = ms_hash_mix(h ^ ms_load64(key + i));
    }
    return h;
}

static inline bool blob_key_equal(const MsTypeDesc *kd, const uint8_t *stored, const uint8_t *key) {
    return __builtin_memcmp(stored, key, kd->size) == 0;
}

/* A user's hash is often the identity of a couple of small ints, whose runs of consecutive values would
 * cluster under linear probing, so the table sees a mixed hash. */
static inline uint64_t desc_key_hash(const MsTypeDesc *kd, const uint8_t *key) {
    return ms_hash_int(ms_slot_hash(kd, key));
}

static inline bool desc_key_equal(const MsTypeDesc *kd, const uint8_t *stored, const uint8_t *key) {
    return ms_slot_eq(kd, stored, key);
}

static const MapKeyOps ms_int_keys = {.cheap_eq = true, .hash = int_key_hash, .equal = int_key_equal};
static const MapKeyOps ms_str_keys = {.cheap_eq = false, .hash = str_key_hash, .equal = str_key_equal};
static const MapKeyOps ms_blob_keys = {.cheap_eq = true, .hash = blob_key_hash, .equal = blob_key_equal};
static const MapKeyOps ms_desc_keys = {.cheap_eq = false, .hash = desc_key_hash, .equal = desc_key_equal};

/* The hash a table stores for `key`: its key hash with the live bit. */
static inline MS_ALWAYS_INLINE uint64_t ms_map_hash(const MapKeyOps *ops, const MsTypeDesc *kd, const uint8_t *key) {
    return ops->hash(kd, key) | MS_MAP_LIVE;
}

/* The number of the entry holding `key` (whose hash is `hash`), or MS_MAP_NO_ENTRY. */
static inline MS_ALWAYS_INLINE size_t ms_map_find(const MapKeyOps *ops, const MsMap *m, const MsTypeDesc *kd,
                                           const MapLayout *l, const uint8_t *key, uint64_t hash) {
    if (m->len == 0) {
        return MS_MAP_NO_ENTRY;
    }
    size_t pos = ms_map_home(m, hash);
    for (;;) {
        const uint64_t word = m->index[pos];
        if (word == 0) {
            return MS_MAP_NO_ENTRY;
        }
        if (((word ^ hash) >> 32) == 0) {
            const size_t number = (size_t)((uint32_t)word - 1U);
            const uint8_t *entry = ms_map_entry(m, l, number);
            if ((ops->cheap_eq || ms_map_load_hash(entry) == hash) && ops->equal(kd, entry + l->key_offset, key)) {
                return number;
            }
        }
        pos = (pos + 1) & m->mask;
    }
}

/* ---- The table (map.c) ---- */

/* A probe: the stored hash of the key and the entry holding it. */
typedef struct MapProbe {
    uint64_t hash;
    size_t entry; /* MS_MAP_NO_ENTRY when the key is absent */
} MapProbe;

/* Hashes `key` and looks for it, with the probe loop of its key kind. */
MapProbe ms_map_probe(const MsMap *m, const MsTypeDesc *kd, const MapLayout *l, const uint8_t *key);

/* Makes room for one more entry (map.c). */
void ms_map_grow(MsMap *m, const MapLayout *l);

/* The room for one more entry, growing the table when it is full: the address of the next entry. The caller
 * writes the hash, key and value there and then calls ms_map_publish. */
static inline uint8_t *ms_map_next_entry(MsMap *m, const MapLayout *l) {
    if (m->used == m->cap) {
        ms_map_grow(m, l);
    }
    return ms_map_entry(m, l, m->used);
}

/* Links the entry written at `ms_map_next_entry` into the index, so lookups find it. */
static inline void ms_map_publish(MsMap *m, uint64_t hash) {
    size_t pos = ms_map_home(m, hash);
    while (m->index[pos] != 0 && m->index[pos] != MS_MAP_INDEX_REMOVED) {
        pos = (pos + 1) & m->mask;
    }
    m->index[pos] = ms_map_index_word(hash, m->used);
    m->used++;
    m->len++;
}

/* Adds `key` and `val` (both moved in), or replaces the value of an equal key and drops `key`. */
void ms_map_insert(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, uint8_t *key, uint8_t *val);

/* True when `key` is present. */
bool ms_map_has(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key);

/* Removes `key`, dropping the stored key and value. True when it was present. */
bool ms_map_remove(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key);

/* The key descriptor a map was created with, else the caller's: a collection keeps the equality and hash of
 * the module that made it. */
static inline const MsTypeDesc *ms_map_key_desc(const MsMap *m, const MsTypeDesc *kd) {
    return m->desc != NULL ? m->desc : kd;
}

/* Frees the entries and storage. The creator's descriptor stays. */
void ms_map_drop(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd);

/* A deep copy of `src` in insertion order, without its holes, into the uninitialised `out`. */
void ms_map_clone(const MsMap *src, const MsTypeDesc *kd, const MsTypeDesc *vd, MsMap *out);

/* Order-independent equality, probing `b` with the key behaviour of the module that built it. */
bool ms_map_eq(const MsMap *a, const MsMap *b, const MsTypeDesc *kd, const MsTypeDesc *vd);

/* Room for `n` entries, so that adding that many never regrows the table. */
void ms_map_reserve(MsMap *m, const MapLayout *l, size_t n);

/* Copies a slot of `size` bytes; the common sizes are a few moves instead of a call. */
static inline void ms_map_copy_slot(uint8_t *dst, const uint8_t *src, size_t size) {
    switch (size) {
    case 8:
        __builtin_memcpy(dst, src, 8);
        return;
    case 16:
        __builtin_memcpy(dst, src, 16);
        return;
    case 24:
        __builtin_memcpy(dst, src, 24);
        return;
    case 32:
        __builtin_memcpy(dst, src, 32);
        return;
    default:
        __builtin_memcpy(dst, src, size);
        return;
    }
}

#endif

/* The table behind maps and sets: probing, growth, removal, copy and equality. The natives programs call
 * are in map_api.c. Ported from crates/ms-rt/src/map.rs with the same layout, hash and growth policy. */
#include "map_table.h"

#include "rt_calls.h"

/* Entries below this many are never worth compacting after a removal. */
#define COMPACT_MIN_USED 32

static MS_NORETURN void fault_map_overflow(void) {
    static const char message[] = "map size overflow";
    msfault_raise(MS_FAULT_OVERFLOW, (const uint8_t *)message, sizeof message - 1);
}

static size_t next_power_of_two(size_t n) {
    return n <= 1 ? 1 : (size_t)1 << (sizeof(size_t) * 8 - (size_t)__builtin_clzll(n - 1));
}

static size_t checked_bytes(size_t count, size_t size) {
    size_t bytes = 0;
    if (!ms_size_mul(count, size, &bytes)) {
        fault_map_overflow();
    }
    return bytes;
}

MapProbe ms_map_probe(const MsMap *m, const MsTypeDesc *kd, const MapLayout *l, const uint8_t *key) {
    MapProbe probe = {0, MS_MAP_NO_ENTRY};
    if (kd->kind == MS_KIND_INT) {
        probe.hash = ms_map_hash(&ms_int_keys, kd, key);
        probe.entry = ms_map_find(&ms_int_keys, m, kd, l, key, probe.hash);
    } else if (kd->kind == MS_KIND_STRING) {
        probe.hash = ms_map_hash(&ms_str_keys, kd, key);
        probe.entry = ms_map_find(&ms_str_keys, m, kd, l, key, probe.hash);
    } else if (kd->kind == MS_KIND_POD && kd->eq == NULL && kd->hash == NULL) {
        probe.hash = ms_map_hash(&ms_blob_keys, kd, key);
        probe.entry = ms_map_find(&ms_blob_keys, m, kd, l, key, probe.hash);
    } else {
        probe.hash = ms_map_hash(&ms_desc_keys, kd, key);
        probe.entry = ms_map_find(&ms_desc_keys, m, kd, l, key, probe.hash);
    }
    return probe;
}

bool ms_map_has(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key) {
    if (m->len == 0) {
        return false;
    }
    const MapLayout l = ms_map_layout(kd, vd);
    return ms_map_probe(m, kd, &l, key).entry != MS_MAP_NO_ENTRY;
}

/* Replaces the index by an empty one of `index_size` words (a power of two) and links every live entry. */
static void rebuild_index(MsMap *m, const MapLayout *l, size_t index_size) {
    msrt_free(m->index);
    m->index = msrt_alloc_zeroed(checked_bytes(index_size, sizeof(uint64_t)));
    m->mask = index_size - 1;
    for (size_t number = 0; number < m->used; number++) {
        const uint64_t hash = ms_map_load_hash(ms_map_entry(m, l, number));
        if ((hash & MS_MAP_LIVE) == 0) {
            continue;
        }
        size_t pos = ms_map_home(m, hash);
        while (m->index[pos] != 0) {
            pos = (pos + 1) & m->mask;
        }
        m->index[pos] = ms_map_index_word(hash, number);
    }
}

/* Moves the live entries down over the holes and rebuilds the index. After a large drop (capacity at least
 * four times what the live entries need) the entries and the index shrink together, so the cost of the next
 * compaction follows the working size, not the historical peak. The factor keeps a map that churns near its
 * size from shrinking and regrowing. */
static void compact(MsMap *m, const MapLayout *l) {
    size_t kept = 0;
    for (size_t number = 0; number < m->used; number++) {
        const uint8_t *entry = ms_map_entry(m, l, number);
        if (!ms_map_entry_is_live(entry)) {
            continue;
        }
        if (kept != number) {
            __builtin_memcpy(ms_map_entry(m, l, kept), entry, l->stride);
        }
        kept++;
    }
    m->used = kept;
    size_t cap = next_power_of_two(m->len * 2);
    cap = cap < 8 ? 8 : cap;
    if (cap <= m->cap / 4) {
        m->slots = msrt_realloc(m->slots, checked_bytes(cap, l->stride));
        m->cap = cap;
    }
    rebuild_index(m, l, m->cap * 2);
}

/* Makes room for entries: compacts when at least half the entries are holes, else doubles. */
void ms_map_grow(MsMap *m, const MapLayout *l) {
    if (m->used > 0 && m->len * 2 <= m->used && m->cap > 0) {
        compact(m, l);
        return;
    }
    const size_t cap = m->cap == 0 ? 8 : m->cap * 2;
    if (cap > MS_MAP_MAX_CAP) {
        fault_map_overflow();
    }
    const size_t bytes = checked_bytes(cap, l->stride);
    m->slots = m->slots == NULL ? msrt_alloc(bytes) : msrt_realloc(m->slots, bytes);
    m->cap = cap;
    rebuild_index(m, l, cap * 2);
}

void ms_map_reserve(MsMap *m, const MapLayout *l, size_t n) {
    if (n <= m->cap || n > MS_MAP_MAX_CAP) {
        return;
    }
    /* Exact room: small objects dominate parsed documents, and `grow` doubles from here. */
    size_t cap = next_power_of_two(n);
    cap = cap < 2 ? 2 : cap;
    const size_t bytes = checked_bytes(cap, l->stride);
    m->slots = m->slots == NULL ? msrt_alloc(bytes) : msrt_realloc(m->slots, bytes);
    m->cap = cap;
    rebuild_index(m, l, cap * 2);
}

void ms_map_insert(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, uint8_t *key, uint8_t *val) {
    const MapLayout l = ms_map_layout(kd, vd);
    const MapProbe probe = ms_map_probe(m, kd, &l, key);
    if (probe.entry != MS_MAP_NO_ENTRY) { /* the key exists: the new key is dropped and the value replaced in place */
        uint8_t *value = ms_map_entry(m, &l, probe.entry) + l.value_offset;
        ms_slot_drop(kd, key);
        if (vd != NULL) {
            ms_slot_drop(vd, value);
            ms_map_copy_slot(value, val, l.value_size);
        }
        return;
    }
    uint8_t *entry = ms_map_next_entry(m, &l);
    ms_map_store_hash(entry, probe.hash);
    ms_map_copy_slot(entry + l.key_offset, key, l.key_size);
    if (vd != NULL) {
        ms_map_copy_slot(entry + l.value_offset, val, l.value_size);
    }
    ms_map_publish(m, probe.hash);
}

/* Marks the index word of entry `number` removed. */
static void unlink_entry(MsMap *m, uint64_t hash, size_t number) {
    size_t pos = ms_map_home(m, hash);
    while (m->index[pos] != ms_map_index_word(hash, number)) {
        pos = (pos + 1) & m->mask;
    }
    m->index[pos] = MS_MAP_INDEX_REMOVED;
}

bool ms_map_remove(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key) {
    if (m->len == 0) {
        return false;
    }
    const MapLayout l = ms_map_layout(kd, vd);
    const MapProbe probe = ms_map_probe(m, kd, &l, key);
    if (probe.entry == MS_MAP_NO_ENTRY) {
        return false;
    }
    uint8_t *entry = ms_map_entry(m, &l, probe.entry);
    unlink_entry(m, probe.hash, probe.entry);
    ms_slot_drop(kd, entry + l.key_offset);
    if (vd != NULL) {
        ms_slot_drop(vd, entry + l.value_offset);
    }
    ms_map_store_hash(entry, 0);
    m->len--;
    if (m->used > COMPACT_MIN_USED && m->len < m->used / 2) {
        compact(m, &l);
    }
    return true;
}

static void drop_entries(MsMap *m, const MapLayout *l, const MsTypeDesc *kd, const MsTypeDesc *vd) {
    const bool key_strings = kd->kind == MS_KIND_STRING;
    const bool value_strings = vd != NULL && vd->kind == MS_KIND_STRING;
    for (size_t number = 0; number < m->used; number++) {
        uint8_t *entry = ms_map_entry(m, l, number);
        if (!ms_map_entry_is_live(entry)) {
            continue;
        }
        if (key_strings) {
            ms_str_release(key_str(entry + l->key_offset));
        } else {
            ms_slot_drop(kd, entry + l->key_offset);
        }
        if (value_strings) {
            ms_str_release(key_str(entry + l->value_offset));
        } else if (vd != NULL) {
            ms_slot_drop(vd, entry + l->value_offset);
        }
    }
}

void ms_map_drop(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd) {
    if (m->slots == NULL) {
        return;
    }
    const MapLayout l = ms_map_layout(kd, vd);
    if (!ms_desc_drop_is_noop(kd) || (vd != NULL && !ms_desc_drop_is_noop(vd))) {
        drop_entries(m, &l, kd, vd);
    }
    msrt_free(m->slots);
    msrt_free(m->index);
    const MsTypeDesc *creator = m->desc;
    *m = (MsMap){.desc = creator};
}

/* Copies the live entries of `src` to the start of `dst`'s empty slot array. */
static void clone_entries(const MsMap *src, MsMap *dst, const MapLayout *l, const MsTypeDesc *kd, const MsTypeDesc *vd) {
    for (size_t number = 0; number < src->used; number++) {
        const uint8_t *from = ms_map_entry(src, l, number);
        if (!ms_map_entry_is_live(from)) {
            continue;
        }
        uint8_t *to = ms_map_entry(dst, l, dst->used);
        ms_map_store_hash(to, ms_map_load_hash(from));
        ms_slot_copy(kd, from + l->key_offset, to + l->key_offset);
        if (vd != NULL) {
            ms_slot_copy(vd, from + l->value_offset, to + l->value_offset);
        }
        dst->used++;
    }
}

void ms_map_clone(const MsMap *src, const MsTypeDesc *kd, const MsTypeDesc *vd, MsMap *out) {
    const MapLayout l = ms_map_layout(kd, vd);
    MsMap copy = {.desc = src->desc};
    if (src->len > 0) {
        size_t cap = next_power_of_two(src->len);
        cap = cap < 8 ? 8 : cap;
        copy.slots = msrt_alloc(checked_bytes(cap, l.stride));
        copy.cap = cap;
        const bool no_holes = src->used == src->len;
        if (no_holes && ms_desc_is_plain(kd) && (vd == NULL || ms_desc_is_plain(vd))) {
            /* Nothing is owned and nothing moves: the same bytes in the same places. */
            __builtin_memcpy(copy.slots, src->slots, src->used * l.stride);
            copy.used = src->used;
        } else {
            clone_entries(src, &copy, &l, kd, vd);
        }
        copy.len = copy.used;
        const size_t index_size = copy.cap * 2;
        if (no_holes && src->mask + 1 == index_size) { /* entry numbers are unchanged, so the index is valid as it is */
            copy.index = msrt_alloc(index_size * sizeof(uint64_t));
            copy.mask = src->mask;
            __builtin_memcpy(copy.index, src->index, index_size * sizeof(uint64_t));
        } else {
            rebuild_index(&copy, &l, index_size);
        }
    }
    *out = copy;
}

bool ms_map_eq(const MsMap *a, const MsMap *b, const MsTypeDesc *kd, const MsTypeDesc *vd) {
    if (a->len != b->len) {
        return false;
    }
    /* Probe `b` with the identity that built it: a caller outside its module may have a different
     * implementation, or no hashing glue at all. */
    kd = ms_map_key_desc(b, kd);
    const MapLayout l = ms_map_layout(kd, vd);
    for (size_t number = 0; number < a->used; number++) {
        const uint8_t *entry = ms_map_entry(a, &l, number);
        if (!ms_map_entry_is_live(entry)) {
            continue;
        }
        const MapProbe probe = ms_map_probe(b, kd, &l, entry + l.key_offset);
        if (probe.entry == MS_MAP_NO_ENTRY) {
            return false;
        }
        if (vd != NULL && !ms_slot_eq(vd, entry + l.value_offset, ms_map_entry(b, &l, probe.entry) + l.value_offset)) {
            return false;
        }
    }
    return true;
}

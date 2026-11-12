// The C reference for `Map[Int, V]` and `Set[Int]`: what Manuscript's `Map` promises, written the
// way a C programmer would write it. Entries keep insertion order in a dense array (the order
// `entries()` iterates in); an open-addressing index of tag-and-position words finds them; the
// table grows when the entry array is full (compacting first when over half are removed) and
// `remove` leaves a hole. Any `long` key works (no sentinel), nothing is presized, and `ORDMAP_AT`
// inserts a zeroed value when the key is absent, the C counterpart of `update`.
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define ORDMAP_LIVE (1ull << 63)
#define ORDMAP_REMOVED 0xffffffffull

static inline uint64_t ordmap_hash(long k) {
    unsigned __int128 m = (unsigned __int128)((uint64_t)k ^ 0x9e3779b97f4a7c15ull) * 0xff51afd7ed558ccdull;
    return ((uint64_t)m ^ (uint64_t)(m >> 64)) | ORDMAP_LIVE;
}

#define ORDMAP(Name, V)                                                                              \
    typedef struct { uint64_t hash; long key; V value; } Name##Slot;                                 \
    typedef struct { Name##Slot *slots; uint64_t *index; size_t len, used, cap, mask; } Name;        \
    static void Name##_index(Name *m, size_t buckets) {                                              \
        free(m->index);                                                                              \
        m->index = calloc(buckets, sizeof(uint64_t));                                                \
        m->mask = buckets - 1;                                                                       \
        for (size_t i = 0; i < m->used; i++) {                                                       \
            uint64_t h = m->slots[i].hash;                                                           \
            if (!(h & ORDMAP_LIVE)) continue;                                                        \
            size_t p = (h ^ (h >> 32)) & m->mask;                                                    \
            while (m->index[p]) p = (p + 1) & m->mask;                                               \
            m->index[p] = (h & ~0xffffffffull) | (i + 1);                                            \
        }                                                                                            \
    }                                                                                                \
    static void Name##_grow(Name *m) {                                                               \
        if (m->len * 2 < m->used) {                                                                  \
            size_t w = 0;                                                                            \
            for (size_t i = 0; i < m->used; i++)                                                     \
                if (m->slots[i].hash & ORDMAP_LIVE) m->slots[w++] = m->slots[i];                     \
            m->used = w;                                                                             \
        } else {                                                                                     \
            m->cap = m->cap ? m->cap * 2 : 8;                                                        \
            m->slots = realloc(m->slots, m->cap * sizeof(Name##Slot));                               \
        }                                                                                            \
        Name##_index(m, m->cap * 2);                                                                 \
    }                                                                                                \
    static V *Name##_find(const Name *m, long key) {                                                 \
        if (!m->len) return NULL;                                                                    \
        uint64_t h = ordmap_hash(key);                                                               \
        for (size_t p = (h ^ (h >> 32)) & m->mask;; p = (p + 1) & m->mask) {                         \
            uint64_t e = m->index[p];                                                                \
            if (!e) return NULL;                                                                     \
            if (e != ORDMAP_REMOVED && ((e ^ h) >> 32) == 0) {                                      \
                Name##Slot *s = &m->slots[(uint32_t)e - 1];                                          \
                if (s->hash == h && s->key == key) return &s->value;                                 \
            }                                                                                        \
        }                                                                                            \
    }                                                                                                \
    /* The value of `key`, inserting a zeroed one at the end of the order when absent. */            \
    static V *Name##_at(Name *m, long key) {                                                         \
        V *found = Name##_find(m, key);                                                              \
        if (found) return found;                                                                     \
        if (m->used == m->cap) Name##_grow(m);                                                       \
        uint64_t h = ordmap_hash(key);                                                               \
        Name##Slot *s = &m->slots[m->used];                                                          \
        memset(s, 0, sizeof *s);                                                                     \
        s->hash = h;                                                                                 \
        s->key = key;                                                                                \
        size_t p = (h ^ (h >> 32)) & m->mask;                                                        \
        while (m->index[p] && m->index[p] != ORDMAP_REMOVED) p = (p + 1) & m->mask;                  \
        m->index[p] = (h & ~0xffffffffull) | (m->used + 1);                                          \
        m->used++;                                                                                   \
        m->len++;                                                                                    \
        return &s->value;                                                                            \
    }                                                                                                \
    static int Name##_remove(Name *m, long key) {                                                    \
        if (!m->len) return 0;                                                                       \
        uint64_t h = ordmap_hash(key);                                                               \
        for (size_t p = (h ^ (h >> 32)) & m->mask;; p = (p + 1) & m->mask) {                         \
            uint64_t e = m->index[p];                                                                \
            if (!e) return 0;                                                                        \
            if (e != ORDMAP_REMOVED && ((e ^ h) >> 32) == 0) {                                       \
                Name##Slot *s = &m->slots[(uint32_t)e - 1];                                          \
                if (s->hash == h && s->key == key) {                                                 \
                    s->hash = 0;                                                                     \
                    m->index[p] = ORDMAP_REMOVED;                                                    \
                    m->len--;                                                                        \
                    return 1;                                                                        \
                }                                                                                    \
            }                                                                                        \
        }                                                                                            \
    }

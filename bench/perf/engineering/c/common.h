// Shared helpers for the C versions: read all of stdin, and a string-keyed counting table.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char *read_stdin(size_t *len) {
    size_t cap = 1 << 20, n = 0;
    char *buf = malloc(cap);
    size_t got;
    while ((got = fread(buf + n, 1, cap - n, stdin)) > 0) {
        n += got;
        if (n == cap) buf = realloc(buf, cap *= 2);
    }
    *len = n;
    return buf;
}

// An insertion-ordered table of owned keys, the C counterpart of `Map[String, Stat]`: entries sit in a
// dense array in the order they were first seen (what `entries()` iterates), an open-addressing
// index of 32-bit positions finds them, the table grows when the entry array is full, and each key is
// copied on insert (`table_remove` leaves a hole that `table_at` skips and growth compacts).
typedef struct { char *key; size_t len; int64_t count; int64_t sum; uint64_t hash; } Entry;
typedef struct { Entry *slots; uint32_t *index; size_t cap, used, len, mask; } Table;

static uint64_t hash_bytes(const char *p, size_t n) {
    uint64_t h = 1469598103934665603ull;
    for (size_t i = 0; i < n; i++) h = (h ^ (unsigned char)p[i]) * 1099511628211ull;
    return h | 1;
}

static void table_reindex(Table *t, size_t buckets) {
    free(t->index);
    t->index = calloc(buckets, sizeof(uint32_t));
    t->mask = buckets - 1;
    for (size_t i = 0; i < t->used; i++) {
        if (!t->slots[i].key) continue;
        size_t j = t->slots[i].hash & t->mask;
        while (t->index[j]) j = (j + 1) & t->mask;
        t->index[j] = (uint32_t)(i + 1);
    }
}

static void table_init(Table *t) {
    t->cap = 1 << 12; t->used = t->len = 0;
    t->slots = calloc(t->cap, sizeof(Entry));
    t->index = NULL;
    table_reindex(t, t->cap * 2);
}

// Returns the entry for the key, inserting a zeroed one at the end of the order. The key is copied.
static Entry *table_at(Table *t, const char *key, size_t len) {
    uint64_t h = hash_bytes(key, len);
    size_t i = h & t->mask;
    for (uint32_t e; (e = t->index[i]); i = (i + 1) & t->mask) {
        Entry *s = &t->slots[e - 1];
        if (s->key && s->hash == h && s->len == len && memcmp(s->key, key, len) == 0) return s;
    }
    if (t->used == t->cap) {
        if (t->len * 2 < t->used) {
            size_t w = 0;
            for (size_t r = 0; r < t->used; r++) if (t->slots[r].key) t->slots[w++] = t->slots[r];
            t->used = w;
        } else {
            t->cap *= 2;
            t->slots = realloc(t->slots, t->cap * sizeof(Entry));
        }
        table_reindex(t, t->cap * 2);
        for (i = h & t->mask; t->index[i]; i = (i + 1) & t->mask) {}
    }
    Entry *s = &t->slots[t->used];
    char *copy = malloc(len ? len : 1);
    memcpy(copy, key, len);
    *s = (Entry){ copy, len, 0, 0, h };
    t->index[i] = (uint32_t)(t->used + 1);
    t->used++; t->len++;
    return s;
}

static int table_remove(Table *t, const char *key, size_t len) {
    uint64_t h = hash_bytes(key, len);
    for (size_t i = h & t->mask; t->index[i]; i = (i + 1) & t->mask) {
        Entry *s = &t->slots[t->index[i] - 1];
        if (s->key && s->hash == h && s->len == len && memcmp(s->key, key, len) == 0) {
            free(s->key); s->key = NULL; t->len--;
            return 1;
        }
    }
    return 0;
}

// Entries sorted by count descending, then key ascending. Returns a fresh array of `used` entries.
static int by_count_then_key(const void *a, const void *b) {
    const Entry *x = a, *y = b;
    if (x->count != y->count) return x->count < y->count ? 1 : -1;
    size_t n = x->len < y->len ? x->len : y->len;
    int c = memcmp(x->key, y->key, n);
    if (c) return c;
    return x->len < y->len ? -1 : x->len > y->len;
}

static Entry *ranked(Table *t) {
    Entry *out = malloc(t->len * sizeof(Entry));
    size_t k = 0;
    for (size_t i = 0; i < t->used; i++) if (t->slots[i].key) out[k++] = t->slots[i];
    qsort(out, k, sizeof(Entry), by_count_then_key);
    return out;
}

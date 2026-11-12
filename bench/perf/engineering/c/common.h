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

typedef struct { const char *key; size_t len; int64_t count; int64_t sum; } Entry;
typedef struct { Entry *slots; size_t cap, used; } Table;

static uint64_t hash_bytes(const char *p, size_t n) {
    uint64_t h = 1469598103934665603ull;
    for (size_t i = 0; i < n; i++) h = (h ^ (unsigned char)p[i]) * 1099511628211ull;
    return h;
}

static void table_init(Table *t) { t->cap = 1 << 12; t->used = 0; t->slots = calloc(t->cap, sizeof(Entry)); }

// Returns the entry for the key, inserting a zeroed one. The key bytes must outlive the table.
static Entry *table_at(Table *t, const char *key, size_t len) {
    if (t->used * 2 >= t->cap) {
        Table bigger = { calloc(t->cap * 2, sizeof(Entry)), t->cap * 2, 0 };
        for (size_t i = 0; i < t->cap; i++) {
            if (!t->slots[i].key) continue;
            size_t j = hash_bytes(t->slots[i].key, t->slots[i].len) & (bigger.cap - 1);
            while (bigger.slots[j].key) j = (j + 1) & (bigger.cap - 1);
            bigger.slots[j] = t->slots[i];
        }
        free(t->slots);
        bigger.used = t->used;
        *t = bigger;
    }
    size_t i = hash_bytes(key, len) & (t->cap - 1);
    while (t->slots[i].key) {
        if (t->slots[i].len == len && memcmp(t->slots[i].key, key, len) == 0) return &t->slots[i];
        i = (i + 1) & (t->cap - 1);
    }
    t->slots[i] = (Entry){ key, len, 0, 0 };
    t->used++;
    return &t->slots[i];
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
    Entry *out = malloc(t->used * sizeof(Entry));
    size_t k = 0;
    for (size_t i = 0; i < t->cap; i++) if (t->slots[i].key) out[k++] = t->slots[i];
    qsort(out, k, sizeof(Entry), by_count_then_key);
    return out;
}

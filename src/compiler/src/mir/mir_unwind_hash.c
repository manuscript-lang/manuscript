/* A small open-addressed hash map for the unwind pass's sets and maps (mir_unwind.h). */
#include "mir/mir_unwind.h"

static uint32_t uh_slot(uint64_t k, uint32_t mask) {
    k ^= k >> 33;
    k *= UINT64_C(0xff51afd7ed558ccd);
    k ^= k >> 33;
    return (uint32_t)k & mask;
}

static uint32_t uh_find(const UwHash *h, uint64_t k) {
    uint32_t i = uh_slot(k, h->cap - 1);
    while (h->used[i] && h->key[i] != k) {
        i = (i + 1) & (h->cap - 1);
    }
    return i;
}

bool uh_get(const UwHash *h, uint64_t k, uint64_t *v) {
    if (h->cap == 0) {
        return false;
    }
    const uint32_t i = uh_find(h, k);
    if (!h->used[i]) {
        return false;
    }
    if (v != NULL) {
        *v = h->val[i];
    }
    return true;
}

static void uh_alloc(MsArena *a, UwHash *h, uint32_t cap) {
    h->key = MS_NEW_N(a, uint64_t, cap);
    h->val = MS_NEW_N(a, uint64_t, cap);
    h->used = MS_NEW_N(a, uint8_t, cap);
    memset(h->used, 0, cap);
    h->cap = cap;
    h->n = 0;
}

bool uh_put(MsArena *a, UwHash *h, uint64_t k, uint64_t v) {
    if (h->cap == 0 || (h->n + 1) * 2 > h->cap) {
        UwHash old = *h;
        uh_alloc(a, h, old.cap ? old.cap * 2 : 16);
        for (uint32_t i = 0; i < old.cap; i++) {
            if (old.used[i]) {
                const uint32_t at = uh_find(h, old.key[i]);
                h->used[at] = 1;
                h->key[at] = old.key[i];
                h->val[at] = old.val[i];
                h->n++;
            }
        }
    }
    const uint32_t i = uh_find(h, k);
    const bool fresh = !h->used[i];
    if (fresh) {
        h->used[i] = 1;
        h->key[i] = k;
        h->n++;
    }
    h->val[i] = v;
    return fresh;
}

bool uh_del(UwHash *h, uint64_t k) {
    if (h->cap == 0) {
        return false;
    }
    const uint32_t mask = h->cap - 1;
    uint32_t i = uh_find(h, k);
    if (!h->used[i]) {
        return false;
    }
    h->used[i] = 0;
    h->n--;
    for (uint32_t j = (i + 1) & mask; h->used[j]; j = (j + 1) & mask) {
        const uint32_t ideal = uh_slot(h->key[j], mask);
        /* `j` may move into the hole `i` unless its ideal slot lies cyclically in (i, j]. */
        const bool stays = i <= j ? (ideal > i && ideal <= j) : (ideal > i || ideal <= j);
        if (!stays) {
            h->key[i] = h->key[j];
            h->val[i] = h->val[j];
            h->used[i] = 1;
            h->used[j] = 0;
            i = j;
        }
    }
    return true;
}

UwHash uh_clone(MsArena *a, const UwHash *h) {
    UwHash out = {0};
    if (h->cap == 0) {
        return out;
    }
    uh_alloc(a, &out, h->cap);
    memcpy(out.key, h->key, sizeof(uint64_t) * h->cap);
    memcpy(out.val, h->val, sizeof(uint64_t) * h->cap);
    memcpy(out.used, h->used, h->cap);
    out.n = h->n;
    return out;
}

static int uh_cmp(const void *x, const void *y) {
    const uint64_t a = *(const uint64_t *)x, b = *(const uint64_t *)y;
    return a < b ? -1 : a > b;
}

uint64_t *uh_keys(MsArena *a, const UwHash *h) {
    uint64_t *out = MS_NEW_N(a, uint64_t, h->n ? h->n : 1);
    uint32_t n = 0;
    for (uint32_t i = 0; i < h->cap; i++) {
        if (h->used[i]) {
            out[n++] = h->key[i];
        }
    }
    if (n > 1) {
        qsort(out, n, sizeof *out, uh_cmp);
    }
    return out;
}

bool uh_equal_sets(const UwHash *x, const UwHash *y) {
    if (x->n != y->n) {
        return false;
    }
    for (uint32_t i = 0; i < x->cap; i++) {
        if (x->used[i] && !uh_has(y, x->key[i])) {
            return false;
        }
    }
    return true;
}

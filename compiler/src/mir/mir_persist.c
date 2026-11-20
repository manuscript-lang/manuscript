/* Persistent sets and maps of dense `uint32_t` keys (mir_persist.h); a port of persist.rs. */
#include <string.h>

#include "ms/mir_persist.h"

enum {
    PS_LEAF_BITS = 6,
    PS_BRANCH_BITS = 4,
    PS_FAN = 1 << PS_BRANCH_BITS,
    PM_FAN = 16
};

struct PNode {
    bool leaf;
    uint64_t word;           /* leaf: values base..base+64, one bit each; never zero */
    const PNode *kids[PS_FAN]; /* branch: at least one is present */
};

static uint32_t ps_slot(uint32_t v, uint32_t height) {
    return (v >> (PS_LEAF_BITS + PS_BRANCH_BITS * (height - 1))) & (PS_FAN - 1);
}

static uint64_t ps_capacity(uint32_t height) {
    return UINT64_C(1) << (PS_LEAF_BITS + PS_BRANCH_BITS * height);
}

static PNode *ps_new(MsArena *a, const PNode *like) {
    PNode *n = MS_NEW_N(a, PNode, 1);
    if (like != NULL) {
        *n = *like;
    } else {
        memset(n, 0, sizeof *n);
    }
    return n;
}

bool owner_contains(const OwnerSet *s, uint32_t v) {
    if ((uint64_t)v >= ps_capacity(s->height)) {
        return false;
    }
    const PNode *n = s->root;
    uint32_t h = s->height;
    while (n != NULL && !n->leaf) {
        n = n->kids[ps_slot(v, h--)];
    }
    return n != NULL && (n->word >> (v & 63) & 1) != 0;
}

static const PNode *ps_insert_in(MsArena *a, const PNode *node, uint32_t height, uint32_t v) {
    PNode *out = ps_new(a, node);
    if (height == 0) {
        out->leaf = true;
        out->word |= UINT64_C(1) << (v & 63);
        return out;
    }
    const uint32_t i = ps_slot(v, height);
    out->kids[i] = ps_insert_in(a, out->kids[i], height - 1, v);
    return out;
}

void owner_insert(MsArena *a, OwnerSet *s, uint32_t v) {
    while ((uint64_t)v >= ps_capacity(s->height)) {
        if (s->root != NULL) {
            PNode *up = ps_new(a, NULL);
            up->kids[0] = s->root;
            s->root = up;
        }
        s->height++;
    }
    s->root = ps_insert_in(a, s->root, s->height, v);
}

static const PNode *ps_remove_in(MsArena *a, const PNode *node, uint32_t height, uint32_t v) {
    if (node->leaf) {
        const uint64_t left = node->word & ~(UINT64_C(1) << (v & 63));
        if (left == node->word) {
            return node;
        }
        if (left == 0) {
            return NULL;
        }
        PNode *out = ps_new(a, node);
        out->word = left;
        return out;
    }
    const uint32_t i = ps_slot(v, height);
    const PNode *child = node->kids[i];
    if (child == NULL) {
        return node;
    }
    const PNode *next = ps_remove_in(a, child, height - 1, v);
    if (next == child) {
        return node;
    }
    PNode *out = ps_new(a, node);
    out->kids[i] = next;
    for (uint32_t k = 0; k < PS_FAN; k++) {
        if (out->kids[k] != NULL) {
            return out;
        }
    }
    return NULL;
}

bool owner_remove(MsArena *a, OwnerSet *s, uint32_t v) {
    if (!owner_contains(s, v)) {
        return false;
    }
    s->root = ps_remove_in(a, s->root, s->height, v);
    return true;
}

typedef struct PsVec {
    MsArena *a;
    uint32_t *v;
    uint32_t n, cap;
} PsVec;

static void ps_push(PsVec *vec, uint32_t x) {
    if (vec->n == vec->cap) {
        const uint32_t cap = vec->cap ? vec->cap * 2 : 16;
        uint32_t *grown = MS_NEW_N(vec->a, uint32_t, cap);
        if (vec->n > 0) {
            memcpy(grown, vec->v, sizeof(uint32_t) * vec->n);
        }
        vec->v = grown;
        vec->cap = cap;
    }
    vec->v[vec->n++] = x;
}

static void ps_push_bits(PsVec *out, uint64_t bits, uint64_t base) {
    while (bits != 0) {
        ps_push(out, (uint32_t)(base + (uint64_t)__builtin_ctzll(bits)));
        bits &= bits - 1;
    }
}

static void ps_collect(const PNode *node, uint32_t height, uint64_t base, PsVec *out) {
    if (node->leaf) {
        ps_push_bits(out, node->word, base);
        return;
    }
    const uint64_t span = ps_capacity(height - 1);
    for (uint32_t i = 0; i < PS_FAN; i++) {
        if (node->kids[i] != NULL) {
            ps_collect(node->kids[i], height - 1, base + (uint64_t)i * span, out);
        }
    }
}

uint32_t *owner_to_vec(MsArena *a, const OwnerSet *s, uint32_t *n) {
    PsVec out = {.a = a};
    if (s->root != NULL) {
        ps_collect(s->root, s->height, 0, &out);
    }
    *n = out.n;
    if (out.v == NULL) {
        out.v = MS_NEW_N(a, uint32_t, 1);
    }
    return out.v;
}

bool owner_first(const OwnerSet *s, uint32_t *out) {
    const PNode *node = s->root;
    uint64_t base = 0;
    uint32_t height = s->height;
    while (node != NULL) {
        if (node->leaf) {
            *out = (uint32_t)(base + (uint64_t)__builtin_ctzll(node->word));
            return true;
        }
        uint32_t i = 0;
        while (i < PS_FAN && node->kids[i] == NULL) {
            i++;
        }
        if (i == PS_FAN) {
            return false;
        }
        base += (uint64_t)i * ps_capacity(height - 1);
        height--;
        node = node->kids[i];
    }
    return false;
}

/* The root of `s` as a tree of `height`, which is at least its own. */
static const PNode *ps_lifted(MsArena *a, const OwnerSet *s, uint32_t height) {
    const PNode *root = s->root;
    for (uint32_t h = s->height; h < height && root != NULL; h++) {
        PNode *up = ps_new(a, NULL);
        up->kids[0] = root;
        root = up;
    }
    return root;
}

static bool ps_same(const PNode *x, const PNode *y) {
    if (x == y) {
        return true;
    }
    if (x == NULL || y == NULL || x->leaf != y->leaf) {
        return false;
    }
    if (x->leaf) {
        return x->word == y->word;
    }
    for (uint32_t i = 0; i < PS_FAN; i++) {
        if (!ps_same(x->kids[i], y->kids[i])) {
            return false;
        }
    }
    return true;
}

/* Compares at the taller height without building the lifted tree: the shorter tree is the first
 * child all the way up. */
static bool ps_same_h(const PNode *tall, uint32_t th, const PNode *shortn, uint32_t sh) {
    while (th > sh) {
        if (tall == NULL) {
            return shortn == NULL;
        }
        for (uint32_t i = 1; i < PS_FAN; i++) {
            if (tall->kids[i] != NULL) {
                return false;
            }
        }
        tall = tall->kids[0];
        th--;
    }
    return ps_same(tall, shortn);
}

bool owner_equal(const OwnerSet *x, const OwnerSet *y) {
    return x->height >= y->height ? ps_same_h(x->root, x->height, y->root, y->height)
                                  : ps_same_h(y->root, y->height, x->root, x->height);
}

static const PNode *ps_union_in(MsArena *a, const PNode *x, const PNode *y) {
    if (x == NULL) {
        return y;
    }
    if (y == NULL || x == y) {
        return x;
    }
    if (x->leaf) {
        const uint64_t word = x->word | y->word;
        if (word == x->word) {
            return x;
        }
        if (word == y->word) {
            return y;
        }
        PNode *out = ps_new(a, NULL);
        out->leaf = true;
        out->word = word;
        return out;
    }
    PNode *out = ps_new(a, NULL);
    bool is_x = true, is_y = true;
    for (uint32_t i = 0; i < PS_FAN; i++) {
        out->kids[i] = ps_union_in(a, x->kids[i], y->kids[i]);
        is_x = is_x && out->kids[i] == x->kids[i];
        is_y = is_y && out->kids[i] == y->kids[i];
    }
    if (is_x) {
        return x;
    }
    return is_y ? y : out;
}

void owner_union(MsArena *a, OwnerSet *s, const OwnerSet *other) {
    const uint32_t height = s->height > other->height ? s->height : other->height;
    const PNode *x = ps_lifted(a, s, height), *y = ps_lifted(a, other, height);
    s->root = ps_union_in(a, x, y);
    s->height = height;
}

static void ps_diff_in(const PNode *x, const PNode *y, uint32_t height, uint64_t base, PsVec *mine,
                       PsVec *theirs) {
    if (x == y) {
        return;
    }
    if (y == NULL) {
        ps_collect(x, height, base, mine);
        return;
    }
    if (x == NULL) {
        ps_collect(y, height, base, theirs);
        return;
    }
    if (x->leaf) {
        ps_push_bits(mine, x->word & ~y->word, base);
        ps_push_bits(theirs, y->word & ~x->word, base);
        return;
    }
    const uint64_t span = ps_capacity(height - 1);
    for (uint32_t i = 0; i < PS_FAN; i++) {
        ps_diff_in(x->kids[i], y->kids[i], height - 1, base + (uint64_t)i * span, mine, theirs);
    }
}

void owner_diff(MsArena *a, const OwnerSet *x, const OwnerSet *y, uint32_t **only_x,
                uint32_t *nx, uint32_t **only_y, uint32_t *ny) {
    const uint32_t height = x->height > y->height ? x->height : y->height;
    PsVec mine = {.a = a}, theirs = {.a = a};
    ps_diff_in(ps_lifted(a, x, height), ps_lifted(a, y, height), height, 0, &mine, &theirs);
    *nx = mine.n;
    *ny = theirs.n;
    *only_x = mine.v != NULL ? mine.v : MS_NEW_N(a, uint32_t, 1);
    *only_y = theirs.v != NULL ? theirs.v : MS_NEW_N(a, uint32_t, 1);
}

/* ---- PosMap ---- */

struct PMapNode {
    bool leaf;
    bool has[PM_FAN];
    uint64_t val[PM_FAN];
    const PMapNode *kids[PM_FAN];
};

static uint32_t pm_slot(uint32_t k, uint32_t height) {
    return (k >> (PS_BRANCH_BITS * height)) & (PM_FAN - 1);
}

static uint64_t pm_capacity(uint32_t height) {
    return UINT64_C(1) << (PS_BRANCH_BITS * (height + 1));
}

static PMapNode *pm_new(MsArena *a, const PMapNode *like) {
    PMapNode *n = MS_NEW_N(a, PMapNode, 1);
    if (like != NULL) {
        *n = *like;
    } else {
        memset(n, 0, sizeof *n);
    }
    return n;
}

bool posmap_get(const PosMap *m, uint32_t k, uint64_t *out) {
    if ((uint64_t)k >= pm_capacity(m->height)) {
        return false;
    }
    const PMapNode *node = m->root;
    uint32_t height = m->height;
    while (node != NULL) {
        if (node->leaf) {
            const uint32_t i = pm_slot(k, 0);
            if (!node->has[i]) {
                return false;
            }
            *out = node->val[i];
            return true;
        }
        node = node->kids[pm_slot(k, height--)];
    }
    return false;
}

static const PMapNode *pm_insert_in(MsArena *a, const PMapNode *node, uint32_t height, uint32_t k,
                                    uint64_t v, bool *grew) {
    PMapNode *out = pm_new(a, node);
    if (height == 0) {
        const uint32_t i = pm_slot(k, 0);
        out->leaf = true;
        *grew = !out->has[i];
        out->has[i] = true;
        out->val[i] = v;
        return out;
    }
    const uint32_t i = pm_slot(k, height);
    out->kids[i] = pm_insert_in(a, out->kids[i], height - 1, k, v, grew);
    return out;
}

void posmap_insert(MsArena *a, PosMap *m, uint32_t k, uint64_t v) {
    while ((uint64_t)k >= pm_capacity(m->height)) {
        if (m->root != NULL) {
            PMapNode *up = pm_new(a, NULL);
            up->kids[0] = m->root;
            m->root = up;
        }
        m->height++;
    }
    bool grew = false;
    m->root = pm_insert_in(a, m->root, m->height, k, v, &grew);
    m->len += grew ? 1u : 0u;
}

static bool pm_any(const PMapNode *n) {
    for (uint32_t i = 0; i < PM_FAN; i++) {
        if (n->leaf ? n->has[i] : n->kids[i] != NULL) {
            return true;
        }
    }
    return false;
}

static const PMapNode *pm_remove_in(MsArena *a, const PMapNode *node, uint32_t height, uint32_t k,
                                    bool *gone) {
    if (node->leaf) {
        const uint32_t i = pm_slot(k, 0);
        if (!node->has[i]) {
            return node;
        }
        *gone = true;
        PMapNode *out = pm_new(a, node);
        out->has[i] = false;
        out->val[i] = 0;
        return pm_any(out) ? out : NULL;
    }
    const uint32_t i = pm_slot(k, height);
    const PMapNode *child = node->kids[i];
    if (child == NULL) {
        return node;
    }
    const PMapNode *next = pm_remove_in(a, child, height - 1, k, gone);
    if (!*gone) {
        return node;
    }
    PMapNode *out = pm_new(a, node);
    out->kids[i] = next;
    return pm_any(out) ? out : NULL;
}

bool posmap_remove(MsArena *a, PosMap *m, uint32_t k) {
    if (m->root == NULL || (uint64_t)k >= pm_capacity(m->height)) {
        return false;
    }
    bool gone = false;
    const PMapNode *next = pm_remove_in(a, m->root, m->height, k, &gone);
    if (gone) {
        m->root = next;
        m->len--;
    }
    return gone;
}

static void pm_walk(const PMapNode *node, uint64_t *out, uint32_t *n) {
    for (uint32_t i = 0; i < PM_FAN; i++) {
        if (node->leaf) {
            if (node->has[i]) {
                out[(*n)++] = node->val[i];
            }
        } else if (node->kids[i] != NULL) {
            pm_walk(node->kids[i], out, n);
        }
    }
}

uint64_t *posmap_values(MsArena *a, const PosMap *m) {
    uint64_t *out = MS_NEW_N(a, uint64_t, m->len ? m->len : 1);
    uint32_t n = 0;
    if (m->root != NULL) {
        pm_walk(m->root, out, &n);
    }
    return out;
}

static bool pm_same(const PMapNode *x, const PMapNode *y) {
    if (x == y) {
        return true;
    }
    if (x == NULL || y == NULL || x->leaf != y->leaf) {
        return false;
    }
    for (uint32_t i = 0; i < PM_FAN; i++) {
        if (x->leaf) {
            if (x->has[i] != y->has[i] || (x->has[i] && x->val[i] != y->val[i])) {
                return false;
            }
        } else if (!pm_same(x->kids[i], y->kids[i])) {
            return false;
        }
    }
    return true;
}

bool posmap_same_entries(const PosMap *x, const PosMap *y) {
    if (x->root == NULL || y->root == NULL) {
        return x->root == y->root;
    }
    return x->height == y->height && pm_same(x->root, y->root);
}

bool posmap_same_tree(const PosMap *x, const PosMap *y) {
    return x->root == y->root && (x->root == NULL || x->height == y->height);
}

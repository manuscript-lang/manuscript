// The whole-program kernels as a no-GC Manuscript backend would emit them from
// ../ms/src/main.ms under value semantics: unique ownership with deterministic
// frees, inline record storage, growable lists, an insertion-ordered map, and
// the current runtime contract (checked Int arithmetic, bounds-checked list
// access, a cancellation poll on every loop back edge).
//
// Each check can be compiled out to measure its cost:
//   -DMS_NO_OVERFLOW  unchecked Int + - * / %
//   -DMS_NO_BOUNDS    unchecked list indexing
//   -DMS_NO_POLL      no cancellation poll in loops
#define _POSIX_C_SOURCE 199309L
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

// ---- runtime ---------------------------------------------------------------

__attribute__((noreturn, noinline, cold)) static void ms_fault(const char *what) {
    fprintf(stderr, "fault: %s\n", what);
    exit(2);
}

static void *ms_alloc(size_t n) {
    void *p = malloc(n);
    if (!p) ms_fault("out of memory");
    return p;
}

static int64_t opaque(int64_t x) {
    __asm__ volatile("" : "+r"(x));
    return x;
}

#define LIKELY(x) __builtin_expect(!!(x), 1)
#define UNLIKELY(x) __builtin_expect(!!(x), 0)

#ifdef MS_NO_OVERFLOW
static inline int64_t ms_add(int64_t a, int64_t b) { return (int64_t)((uint64_t)a + (uint64_t)b); }
static inline int64_t ms_sub(int64_t a, int64_t b) { return (int64_t)((uint64_t)a - (uint64_t)b); }
static inline int64_t ms_mul(int64_t a, int64_t b) { return (int64_t)((uint64_t)a * (uint64_t)b); }
static inline int64_t ms_div(int64_t a, int64_t b) { return a / b; }
static inline int64_t ms_mod(int64_t a, int64_t b) { return a % b; }
#else
static inline int64_t ms_add(int64_t a, int64_t b) {
    int64_t r;
    if (UNLIKELY(__builtin_add_overflow(a, b, &r))) ms_fault("Int overflow");
    return r;
}
static inline int64_t ms_sub(int64_t a, int64_t b) {
    int64_t r;
    if (UNLIKELY(__builtin_sub_overflow(a, b, &r))) ms_fault("Int overflow");
    return r;
}
static inline int64_t ms_mul(int64_t a, int64_t b) {
    int64_t r;
    if (UNLIKELY(__builtin_mul_overflow(a, b, &r))) ms_fault("Int overflow");
    return r;
}
static inline int64_t ms_div(int64_t a, int64_t b) {
    if (UNLIKELY(b == 0)) ms_fault("division by zero");
    if (UNLIKELY(a == INT64_MIN && b == -1)) ms_fault("Int overflow");
    return a / b;
}
static inline int64_t ms_mod(int64_t a, int64_t b) {
    if (UNLIKELY(b == 0)) ms_fault("division by zero");
    if (UNLIKELY(b == -1)) return 0;
    return a % b;
}
#endif

// Set by the scheduler when the enclosing work is cancelled.
static _Atomic int ms_cancelled;

#ifdef MS_NO_POLL
#define MS_POLL() ((void)0)
#else
#define MS_POLL()                                                                  \
    do {                                                                           \
        if (UNLIKELY(atomic_load_explicit(&ms_cancelled, memory_order_relaxed)))  \
            ms_fault("cancelled");                                                 \
    } while (0)
#endif

#ifdef MS_NO_BOUNDS
#define MS_BOUNDS(i, len) ((void)0)
#else
#define MS_BOUNDS(i, len) \
    do { if (UNLIKELY((uint64_t)(i) >= (uint64_t)(len))) ms_fault("index out of range"); } while (0)
#endif

// List[T]: one owner, contiguous inline elements, doubling growth.
#define MS_LIST(T, N)                                                                  \
    typedef struct { T *data; int64_t len, cap; } N;                                   \
    static inline N N##_new(void) { return (N){NULL, 0, 0}; }                          \
    static inline void N##_append(N *l, T v) {                                         \
        if (UNLIKELY(l->len == l->cap)) {                                              \
            l->cap = l->cap ? l->cap * 2 : 8;                                          \
            T *d = realloc(l->data, sizeof(T) * (size_t)l->cap);                       \
            if (!d) ms_fault("out of memory");                                         \
            l->data = d;                                                               \
        }                                                                              \
        l->data[l->len++] = v;                                                         \
    }                                                                                  \
    static inline T *N##_at(const N *l, int64_t i) {                                   \
        MS_BOUNDS(i, l->len);                                                          \
        return &l->data[i];                                                            \
    }

MS_LIST(uint8_t, ListBool)
MS_LIST(int64_t, ListInt)
MS_LIST(double, ListFloat)

static void ListBool_drop(ListBool *l) { free(l->data); }
static void ListInt_drop(ListInt *l) { free(l->data); }
static void ListFloat_drop(ListFloat *l) { free(l->data); }

// ---- kernels -----------------------------------------------------------------

static int64_t sieve(int64_t n) {
    ListBool flags = ListBool_new();
    int64_t i = 0;
    while (i <= n) {
        MS_POLL();
        ListBool_append(&flags, 1);
        i = ms_add(i, 1);
    }
    int64_t count = 0;
    i = 2;
    while (i <= n) {
        MS_POLL();
        if (*ListBool_at(&flags, i)) {
            count = ms_add(count, 1);
            int64_t j = ms_mul(i, i);
            while (j <= n) {
                MS_POLL();
                *ListBool_at(&flags, j) = 0;
                j = ms_add(j, i);
            }
        }
        i = ms_add(i, 1);
    }
    ListBool_drop(&flags);
    return count;
}

typedef struct { double x, y, z, vx, vy, vz, mass; } Body;
MS_LIST(Body, ListBody)

// Two simultaneous `mut` borrows into one list violate exclusivity, so the
// value-semantics source indexes per access: bodies[i].vx -= ...
static double advance(ListBody *bodies, int64_t steps) {
    int64_t n = bodies->len;
    int64_t s = 0;
    while (s < steps) {
        MS_POLL();
        int64_t i = 0;
        while (i < n) {
            MS_POLL();
            int64_t j = ms_add(i, 1);
            while (j < n) {
                MS_POLL();
                const Body a = *ListBody_at(bodies, i);
                const Body b = *ListBody_at(bodies, j);
                double dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z;
                double d2 = dx * dx + dy * dy + dz * dz + 0.01;
                double mag = 0.01 / (d2 * d2);
                ListBody_at(bodies, i)->vx -= dx * b.mass * mag;
                ListBody_at(bodies, i)->vy -= dy * b.mass * mag;
                ListBody_at(bodies, i)->vz -= dz * b.mass * mag;
                ListBody_at(bodies, j)->vx += dx * a.mass * mag;
                ListBody_at(bodies, j)->vy += dy * a.mass * mag;
                ListBody_at(bodies, j)->vz += dz * a.mass * mag;
                j = ms_add(j, 1);
            }
            i = ms_add(i, 1);
        }
        i = 0;
        while (i < n) {
            MS_POLL();
            Body *a = ListBody_at(bodies, i);
            a->x += 0.01 * a->vx;
            a->y += 0.01 * a->vy;
            a->z += 0.01 * a->vz;
            i = ms_add(i, 1);
        }
        s = ms_add(s, 1);
    }
    double e = 0.0;
    int64_t k = 0;
    while (k < n) {
        MS_POLL();
        const Body *a = ListBody_at(bodies, k);
        e += a->mass * (a->vx * a->vx + a->vy * a->vy + a->vz * a->vz);
        k = ms_add(k, 1);
    }
    return e;
}

typedef struct { int64_t width, height; ListInt cells; } Grid;

static int64_t cell(const Grid *g, int64_t x, int64_t y) {
    int64_t wx = ms_mod(ms_add(x, g->width), g->width);
    int64_t wy = ms_mod(ms_add(y, g->height), g->height);
    return *ListInt_at(&g->cells, ms_add(ms_mul(wy, g->width), wx));
}

static int64_t neighbors(const Grid *g, int64_t x, int64_t y) {
    int64_t n = 0;
    int64_t dy = -1;
    while (dy <= 1) {
        MS_POLL();
        int64_t dx = -1;
        while (dx <= 1) {
            MS_POLL();
            if (!(dx == 0 && dy == 0)) n = ms_add(n, cell(g, ms_add(x, dx), ms_add(y, dy)));
            dx = ms_add(dx, 1);
        }
        dy = ms_add(dy, 1);
    }
    return n;
}

static Grid step(const Grid *g) {
    ListInt next = ListInt_new();
    int64_t y = 0;
    while (y < g->height) {
        MS_POLL();
        int64_t x = 0;
        while (x < g->width) {
            MS_POLL();
            int64_t n = neighbors(g, x, y);
            int alive = cell(g, x, y) == 1;
            ListInt_append(&next, (n == 3 || (alive && n == 2)) ? 1 : 0);
            x = ms_add(x, 1);
        }
        y = ms_add(y, 1);
    }
    return (Grid){g->width, g->height, next};
}

static int64_t life(int64_t gens) {
    int64_t size = opaque(128);
    ListInt cells = ListInt_new();
    int64_t i = 0;
    while (i < ms_mul(size, size)) {
        MS_POLL();
        ListInt_append(&cells, (ms_mod(i, 7) == 0 || ms_mod(i, 11) == 0) ? 1 : 0);
        i = ms_add(i, 1);
    }
    Grid g = {size, size, cells};
    int64_t n = 0;
    while (n < gens) {
        MS_POLL();
        Grid next = step(&g);
        ListInt_drop(&g.cells);  // reassignment drops the old value
        g = next;
        n = ms_add(n, 1);
    }
    int64_t acc = 0;  // fold with its closure inlined
    for (int64_t k = 0; k < g.cells.len; k++) {
        MS_POLL();
        acc = ms_add(acc, g.cells.data[k]);
    }
    ListInt_drop(&g.cells);
    return acc;
}

MS_LIST(ListFloat, ListListFloat)

static void ListListFloat_drop(ListListFloat *l) {
    for (int64_t i = 0; i < l->len; i++) ListFloat_drop(&l->data[i]);
    free(l->data);
}

static double matmul(int64_t n) {
    ListListFloat a = ListListFloat_new(), b = ListListFloat_new();
    int64_t i = 0;
    while (i < n) {
        MS_POLL();
        ListFloat ra = ListFloat_new(), rb = ListFloat_new();
        int64_t j = 0;
        while (j < n) {
            MS_POLL();
            ListFloat_append(&ra, (double)ms_add(i, j));
            ListFloat_append(&rb, (double)ms_sub(i, j));
            j = ms_add(j, 1);
        }
        ListListFloat_append(&a, ra);  // last use: moved into the outer list
        ListListFloat_append(&b, rb);
        i = ms_add(i, 1);
    }
    double total = 0.0;
    i = 0;
    while (i < n) {
        MS_POLL();
        int64_t j = 0;
        while (j < n) {
            MS_POLL();
            double s = 0.0;
            int64_t k = 0;
            while (k < n) {
                MS_POLL();
                s += *ListFloat_at(ListListFloat_at(&a, i), k) * *ListFloat_at(ListListFloat_at(&b, k), j);
                k = ms_add(k, 1);
            }
            total += s;
            j = ms_add(j, 1);
        }
        i = ms_add(i, 1);
    }
    ListListFloat_drop(&a);
    ListListFloat_drop(&b);
    return total;
}

// Recursive alternative: Leaf is the null niche, Node is one owned box.
typedef struct Node *Tree;
struct Node { Tree left, right; };

static Tree make(int64_t depth) {
    if (depth == 0) return NULL;
    Tree t = ms_alloc(sizeof(struct Node));
    t->left = make(ms_sub(depth, 1));
    t->right = make(ms_sub(depth, 1));
    return t;
}

static int64_t check(const struct Node *t) {
    if (!t) return 1;
    return ms_add(ms_add(1, check(t->left)), check(t->right));
}

static void Tree_drop(Tree t) {
    if (!t) return;
    Tree_drop(t->left);
    Tree_drop(t->right);
    free(t);
}

static int64_t trees(int64_t rounds) {
    int64_t total = 0;
    int64_t r = 0;
    while (r < rounds) {
        MS_POLL();
        Tree t = make(opaque(16));
        total = ms_add(total, check(t));
        Tree_drop(t);  // the temporary dies at the end of the statement
        r = ms_add(r, 1);
    }
    return total;
}

static int64_t collatz(int64_t limit) {
    int64_t best = 0;
    int64_t n = 1;
    while (n < limit) {
        MS_POLL();
        int64_t x = n, steps = 0;
        while (x != 1) {
            MS_POLL();
            if (ms_mod(x, 2) == 0)
                x = ms_div(x, 2);
            else
                x = ms_add(ms_mul(3, x), 1);
            steps = ms_add(steps, 1);
        }
        if (steps > best) best = steps;
        n = ms_add(n, 1);
    }
    return best;
}

// Map[Int, Int]: insertion-ordered compact dict (dense entries plus an
// open-addressing index), matching Manuscript's ordered Map contract.
typedef struct { int64_t key, value; } Entry;
typedef struct {
    Entry *entries;
    int64_t len, cap;
    int32_t *index;  // -1 marks an empty slot
    int64_t slots;
} MapIntInt;

static uint64_t hash_int(int64_t k) {
    uint64_t z = (uint64_t)k + 0x9e3779b97f4a7c15u;
    z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9u;
    z = (z ^ (z >> 27)) * 0x94d049bb133111ebu;
    return z ^ (z >> 31);
}

static MapIntInt MapIntInt_new(void) {
    MapIntInt m = {NULL, 0, 0, ms_alloc(sizeof(int32_t) * 8), 8};
    memset(m.index, 0xff, sizeof(int32_t) * 8);
    return m;
}

static int64_t MapIntInt_slot(const MapIntInt *m, int64_t key) {
    uint64_t mask = (uint64_t)m->slots - 1, h = hash_int(key) & mask;
    for (;;) {
        int32_t e = m->index[h];
        if (e < 0 || m->entries[e].key == key) return (int64_t)h;
        h = (h + 1) & mask;
    }
}

// get(key) returns Optional[Int]; the caller applies .get(default).
static int64_t MapIntInt_get_or(const MapIntInt *m, int64_t key, int64_t fallback) {
    int32_t e = m->index[MapIntInt_slot(m, key)];
    return e < 0 ? fallback : m->entries[e].value;
}

static void MapIntInt_grow(MapIntInt *m) {
    int64_t slots = m->slots * 2;
    int32_t *index = ms_alloc(sizeof(int32_t) * (size_t)slots);
    memset(index, 0xff, sizeof(int32_t) * (size_t)slots);
    for (int64_t e = 0; e < m->len; e++) {
        uint64_t h = hash_int(m->entries[e].key) & (uint64_t)(slots - 1);
        while (index[h] >= 0) h = (h + 1) & (uint64_t)(slots - 1);
        index[h] = (int32_t)e;
    }
    free(m->index);
    m->index = index;
    m->slots = slots;
}

static void MapIntInt_add(MapIntInt *m, int64_t key, int64_t value) {
    int64_t h = MapIntInt_slot(m, key);
    int32_t e = m->index[h];
    if (e >= 0) {
        m->entries[e].value = value;
        return;
    }
    if (m->len == m->cap) {
        m->cap = m->cap ? m->cap * 2 : 8;
        Entry *d = realloc(m->entries, sizeof(Entry) * (size_t)m->cap);
        if (!d) ms_fault("out of memory");
        m->entries = d;
    }
    m->entries[m->len] = (Entry){key, value};
    m->index[h] = (int32_t)m->len++;
    if (m->len * 4 >= m->slots * 3) MapIntInt_grow(m);
}

static void MapIntInt_drop(MapIntInt *m) {
    free(m->entries);
    free(m->index);
}

static int64_t wordfreq(int64_t n) {
    MapIntInt m = MapIntInt_new();
    int64_t i = 0;
    while (i < n) {
        MS_POLL();
        int64_t k = ms_mod(ms_mul(i, 7919), 5003);
        MapIntInt_add(&m, k, ms_add(MapIntInt_get_or(&m, k, 0), 1));
        i = ms_add(i, 1);
    }
    int64_t len = m.len;
    MapIntInt_drop(&m);
    return len;
}

// ---- driver ------------------------------------------------------------------

static int64_t now_us(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000000 + ts.tv_nsec / 1000;
}

// Float to Int truncation is checked: truncate_to_int() returns none when out of range.
static int64_t truncate_or(double v, int64_t fallback) {
    if (!(v >= -9223372036854775808.0 && v < 9223372036854775808.0)) return fallback;
    return (int64_t)v;
}

#define TIMED(name, expr)                                                         \
    do {                                                                          \
        int64_t t0 = now_us();                                                    \
        int64_t r = (expr);                                                       \
        printf("%s %lld %lld\n", name, (long long)(now_us() - t0), (long long)r); \
    } while (0)

static int64_t nbody(void) {
    ListBody bodies = ListBody_new();
    ListBody_append(&bodies, (Body){0, 0, 0, 0, 0, 0, 10});
    ListBody_append(&bodies, (Body){1, 0, 0, 0, 1, 0, 1});
    ListBody_append(&bodies, (Body){0, 2, 0, 1, 0, 0, 1});
    ListBody_append(&bodies, (Body){0, 0, 3, 0, 0, 1, 1});
    ListBody_append(&bodies, (Body){4, 4, 0, 0, 0, 0, 0.5});
    int64_t r = truncate_or(advance(&bodies, opaque(200000)) * 1000.0, 0);
    free(bodies.data);
    return r;
}

typedef struct { double re, im; } Cx;
static inline Cx cx_mul(Cx a, Cx b) { return (Cx){a.re * b.re - a.im * b.im, a.re * b.im + a.im * b.re}; }
static inline Cx cx_add(Cx a, Cx b) { return (Cx){a.re + b.re, a.im + b.im}; }

static int64_t mandel(int64_t n) {
    int64_t total = 0;
    for (int64_t y = 0; y < n; y = ms_add(y, 1)) {
        MS_POLL();
        for (int64_t x = 0; x < n; x = ms_add(x, 1)) {
            MS_POLL();
            Cx c = {3.0 * (double)x / (double)n - 2.0, 2.0 * (double)y / (double)n - 1.0};
            Cx z = {0.0, 0.0};
            int64_t i = 0;
            while (i < 100 && z.re * z.re + z.im * z.im < 4.0) {
                MS_POLL();
                z = cx_add(cx_mul(z, z), c);
                i = ms_add(i, 1);
            }
            total = ms_add(total, i);
        }
    }
    return total;
}

typedef struct { double x, y, vx, vy; } Particle;
MS_LIST(Particle, ListParticle)

static int64_t particles(int64_t n, int64_t steps) {
    ListParticle ps = ListParticle_new();
    for (int64_t i = 0; i < n; i = ms_add(i, 1)) {
        MS_POLL();
        double f = (double)i;
        ListParticle_append(&ps, (Particle){f, f * 0.5, 1.0, -1.0});
    }
    for (int64_t s = 0; s < steps; s = ms_add(s, 1)) {
        MS_POLL();
        for (int64_t i = 0; i < n; i = ms_add(i, 1)) {
            MS_POLL();
            Particle p = *ListParticle_at(&ps, i);
            p.x += p.vx * 0.01;
            p.y += p.vy * 0.01;
            if (p.x > 100.0) p.vx = -p.vx;
            *ListParticle_at(&ps, i) = p;
        }
    }
    double e = 0.0;
    for (int64_t i = 0; i < ps.len; i = ms_add(i, 1)) {
        MS_POLL();
        const Particle *p = ListParticle_at(&ps, i);
        e += p->x + p->y;
    }
    free(ps.data);
    return (int64_t)e;
}

enum { OP_PUSH, OP_ADD, OP_MUL, OP_DUP, OP_SWAP, OP_POP, OP_JMPNZ, OP_DEC };
typedef struct { int64_t kind, arg; } Op;
MS_LIST(Op, ListOp)

static int64_t list_pop_or_zero(ListInt *l) { return l->len == 0 ? 0 : l->data[--l->len]; }

static int64_t vm(int64_t iters) {
    ListOp code = ListOp_new();
    ListOp_append(&code, (Op){OP_PUSH, 3});
    ListOp_append(&code, (Op){OP_PUSH, 7});
    ListOp_append(&code, (Op){OP_MUL, 0});
    ListOp_append(&code, (Op){OP_POP, 0});
    ListOp_append(&code, (Op){OP_DEC, 0});
    ListOp_append(&code, (Op){OP_JMPNZ, 0});
    ListOp_append(&code, (Op){OP_POP, 0});
    ListInt st = ListInt_new();
    ListInt_append(&st, iters);
    int64_t pc = 0, acc = 0;
    while (pc < code.len) {
        MS_POLL();
        Op o = *ListOp_at(&code, pc);
        switch (o.kind) {
        case OP_PUSH: ListInt_append(&st, o.arg); pc = ms_add(pc, 1); break;
        case OP_ADD: { int64_t b = list_pop_or_zero(&st), a = list_pop_or_zero(&st); ListInt_append(&st, ms_add(a, b)); pc = ms_add(pc, 1); break; }
        case OP_MUL: { int64_t b = list_pop_or_zero(&st), a = list_pop_or_zero(&st); ListInt_append(&st, ms_mod(ms_mul(a, b), 1000003)); pc = ms_add(pc, 1); break; }
        case OP_DUP: { int64_t v = *ListInt_at(&st, ms_sub(st.len, 1)); ListInt_append(&st, v); pc = ms_add(pc, 1); break; }
        case OP_SWAP: { int64_t b = list_pop_or_zero(&st), a = list_pop_or_zero(&st); ListInt_append(&st, b); ListInt_append(&st, a); pc = ms_add(pc, 1); break; }
        case OP_POP: acc = ms_add(acc, list_pop_or_zero(&st)); pc = ms_add(pc, 1); break;
        case OP_JMPNZ: if (*ListInt_at(&st, ms_sub(st.len, 1)) != 0) pc = o.arg; else pc = ms_add(pc, 1); break;
        case OP_DEC: { int64_t v = list_pop_or_zero(&st); ListInt_append(&st, ms_sub(v, 1)); pc = ms_add(pc, 1); break; }
        }
    }
    free(st.data);
    free(code.data);
    return acc;
}

typedef struct Expr { int64_t kind, n; struct Expr *l, *r; } Expr;

static Expr *expr_build(int64_t d, int64_t s) {
    Expr *e = ms_alloc(sizeof(Expr));
    e->n = 0;
    e->l = e->r = NULL;
    if (d == 0) { e->kind = 0; e->n = ms_mod(s, 10); return e; }
    if (ms_mod(d, 2) == 0) {
        e->kind = 1;
        e->l = expr_build(ms_sub(d, 1), ms_add(ms_mul(s, 3), 1));
        e->r = expr_build(ms_sub(d, 1), ms_add(ms_mul(s, 7), 2));
    } else {
        e->kind = 2;
        e->l = expr_build(ms_sub(d, 1), ms_add(s, 1));
        e->r = expr_build(ms_sub(d, 1), ms_add(s, 3));
    }
    return e;
}

static int64_t expr_eval(const Expr *e) {
    if (e->kind == 0) return e->n;
    if (e->kind == 1) return ms_mod(ms_add(expr_eval(e->l), expr_eval(e->r)), 1000003);
    return ms_mod(ms_mul(expr_eval(e->l), expr_eval(e->r)), 1000003);
}

static void expr_free(Expr *e) {
    if (!e) return;
    expr_free(e->l);
    expr_free(e->r);
    free(e);
}

static int64_t exprs(int64_t d, int64_t reps) {
    Expr *e = expr_build(d, 1);
    int64_t t = 0;
    for (int64_t i = 0; i < reps; i = ms_add(i, 1)) {
        MS_POLL();
        t = ms_add(t, expr_eval(e));
    }
    expr_free(e);
    return t;
}

static int64_t closures(int64_t n) {
    int64_t k = 7, t = 0;
    for (int64_t i = 0; i < n; i = ms_add(i, 1)) {
        MS_POLL();
        t = ms_add(t, ms_mod(ms_add(ms_mul(i, k), 1), 13));
    }
    ListInt xs = ListInt_new();
    for (int64_t i = 0; i < 1000; i = ms_add(i, 1)) {
        MS_POLL();
        ListInt_append(&xs, ms_mul(i, k));
    }
    for (int64_t r = 0; r < ms_div(n, 1000); r = ms_add(r, 1)) {
        MS_POLL();
        int64_t s = 0;
        for (int64_t i = 0; i < xs.len; i = ms_add(i, 1)) {
            MS_POLL();
            int64_t v = ms_add(*ListInt_at(&xs, i), k);
            if (ms_mod(v, 3) == 0) s = ms_add(s, v);
        }
        t = ms_add(t, s);
    }
    free(xs.data);
    return t;
}

static int64_t stencil(int64_t n, int64_t iters) {
    int64_t nn = ms_mul(n, n);
    ListInt a = ListInt_new(), b = ListInt_new();
    for (int64_t i = 0; i < nn; i = ms_add(i, 1)) {
        MS_POLL();
        ListInt_append(&a, 0);
        ListInt_append(&b, 0);
    }
    for (int64_t i = 0; i < nn; i = ms_add(i, 1)) {
        MS_POLL();
        *ListInt_at(&a, i) = ms_mod(i, 17);
    }
    for (int64_t it = 0; it < iters; it = ms_add(it, 1)) {
        MS_POLL();
        for (int64_t y = 1; y < ms_sub(n, 1); y = ms_add(y, 1)) {
            MS_POLL();
            for (int64_t x = 1; x < ms_sub(n, 1); x = ms_add(x, 1)) {
                MS_POLL();
                int64_t v = ms_add(ms_add(ms_add(
                    *ListInt_at(&a, ms_sub(ms_add(ms_mul(y, n), x), 1)),
                    *ListInt_at(&a, ms_add(ms_add(ms_mul(y, n), x), 1))),
                    *ListInt_at(&a, ms_add(ms_mul(ms_sub(y, 1), n), x))),
                    *ListInt_at(&a, ms_add(ms_mul(ms_add(y, 1), n), x)));
                *ListInt_at(&b, ms_add(ms_mul(y, n), x)) = ms_mod(v, 1009);
            }
        }
        ListInt t = a; a = b; b = t;
    }
    int64_t s = 0;
    for (int64_t i = 0; i < a.len; i = ms_add(i, 1)) {
        MS_POLL();
        s = ms_add(s, *ListInt_at(&a, i));
    }
    free(a.data);
    free(b.data);
    return s;
}

int main(void) {
    TIMED("sieve_5M", sieve(opaque(5000000)));
    TIMED("nbody_200k", nbody());
    TIMED("life_128x128_50", life(opaque(50)));
    TIMED("matmul_200", truncate_or(matmul(opaque(200)), 0));
    TIMED("trees_d16_x20", trees(opaque(20)));
    TIMED("collatz_1M", collatz(opaque(1000000)));
    TIMED("map_count_2M", wordfreq(opaque(2000000)));
    TIMED("mandel_400", mandel(opaque(400)));
    TIMED("particles_1k_5k", particles(opaque(1000), opaque(5000)));
    TIMED("vm_5M", vm(opaque(5000000)));
    TIMED("expr_d20_x20", exprs(opaque(20), opaque(20)));
    TIMED("closures_20M", closures(opaque(20000000)));
    TIMED("stencil_1000_20", stencil(opaque(1000), opaque(20)));
    return 0;
}

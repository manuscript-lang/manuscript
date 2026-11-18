// Hand-written C ceiling for the whole-program kernels: the same algorithms as
// ../go/main.go, written the way a C programmer would (inline structs, exact
// allocations, an unordered open-addressing map, no checks).
#define _POSIX_C_SOURCE 199309L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

// Hides constants from the optimizer so no kernel is folded at compile time.
static int64_t opaque(int64_t x) {
    __asm__ volatile("" : "+r"(x));
    return x;
}

static void *xmalloc(size_t n) {
    void *p = malloc(n);
    if (!p) abort();
    return p;
}

static int64_t sieve(int64_t n) {
    uint8_t *flags = xmalloc((size_t)n + 1);
    memset(flags, 1, (size_t)n + 1);
    int64_t count = 0;
    for (int64_t i = 2; i <= n; i++) {
        if (flags[i]) {
            count++;
            for (int64_t j = i * i; j <= n; j += i) flags[j] = 0;
        }
    }
    free(flags);
    return count;
}

typedef struct { double x, y, z, vx, vy, vz, mass; } Body;

static double advance(Body *b, int64_t n, int64_t steps) {
    for (int64_t s = 0; s < steps; s++) {
        for (int64_t i = 0; i < n; i++) {
            Body *a = &b[i];
            for (int64_t j = i + 1; j < n; j++) {
                Body *c = &b[j];
                double dx = a->x - c->x, dy = a->y - c->y, dz = a->z - c->z;
                double d2 = dx * dx + dy * dy + dz * dz + 0.01;
                double mag = 0.01 / (d2 * d2);
                a->vx -= dx * c->mass * mag;
                a->vy -= dy * c->mass * mag;
                a->vz -= dz * c->mass * mag;
                c->vx += dx * a->mass * mag;
                c->vy += dy * a->mass * mag;
                c->vz += dz * a->mass * mag;
            }
        }
        for (int64_t i = 0; i < n; i++) {
            b[i].x += 0.01 * b[i].vx;
            b[i].y += 0.01 * b[i].vy;
            b[i].z += 0.01 * b[i].vz;
        }
    }
    double e = 0.0;
    for (int64_t i = 0; i < n; i++)
        e += b[i].mass * (b[i].vx * b[i].vx + b[i].vy * b[i].vy + b[i].vz * b[i].vz);
    return e;
}

typedef struct { int64_t width, height; int64_t *cells; } Grid;

static int64_t cell(const Grid *g, int64_t x, int64_t y) {
    int64_t wx = (x + g->width) % g->width;
    int64_t wy = (y + g->height) % g->height;
    return g->cells[wy * g->width + wx];
}

static int64_t neighbors(const Grid *g, int64_t x, int64_t y) {
    int64_t n = 0;
    for (int64_t dy = -1; dy <= 1; dy++)
        for (int64_t dx = -1; dx <= 1; dx++)
            if (!(dx == 0 && dy == 0)) n += cell(g, x + dx, y + dy);
    return n;
}

static Grid step(const Grid *g) {
    int64_t *next = xmalloc(sizeof(int64_t) * (size_t)(g->width * g->height));
    for (int64_t y = 0; y < g->height; y++)
        for (int64_t x = 0; x < g->width; x++) {
            int64_t n = neighbors(g, x, y);
            int alive = cell(g, x, y) == 1;
            next[y * g->width + x] = (n == 3 || (alive && n == 2)) ? 1 : 0;
        }
    return (Grid){g->width, g->height, next};
}

static int64_t life(int64_t gens) {
    int64_t size = opaque(128);
    Grid g = {size, size, xmalloc(sizeof(int64_t) * (size_t)(size * size))};
    for (int64_t i = 0; i < size * size; i++) g.cells[i] = (i % 7 == 0 || i % 11 == 0) ? 1 : 0;
    for (int64_t n = 0; n < gens; n++) {
        Grid next = step(&g);
        free(g.cells);
        g = next;
    }
    int64_t s = 0;
    for (int64_t i = 0; i < g.width * g.height; i++) s += g.cells[i];
    free(g.cells);
    return s;
}

static double matmul(int64_t n) {
    double *a = xmalloc(sizeof(double) * (size_t)(n * n));
    double *b = xmalloc(sizeof(double) * (size_t)(n * n));
    for (int64_t i = 0; i < n; i++)
        for (int64_t j = 0; j < n; j++) {
            a[i * n + j] = (double)(i + j);
            b[i * n + j] = (double)(i - j);
        }
    double total = 0.0;
    for (int64_t i = 0; i < n; i++)
        for (int64_t j = 0; j < n; j++) {
            double s = 0.0;
            for (int64_t k = 0; k < n; k++) s += a[i * n + k] * b[k * n + j];
            total += s;
        }
    free(a);
    free(b);
    return total;
}

typedef struct Tree { struct Tree *l, *r; } Tree;

static Tree *make(int64_t d) {
    if (d == 0) return NULL;
    Tree *t = xmalloc(sizeof(Tree));
    t->l = make(d - 1);
    t->r = make(d - 1);
    return t;
}

static int64_t check(const Tree *t) {
    if (!t) return 1;
    return 1 + check(t->l) + check(t->r);
}

static void drop(Tree *t) {
    if (!t) return;
    drop(t->l);
    drop(t->r);
    free(t);
}

static int64_t trees(int64_t rounds) {
    int64_t total = 0;
    for (int64_t r = 0; r < rounds; r++) {
        Tree *t = make(opaque(16));
        total += check(t);
        drop(t);
    }
    return total;
}

static int64_t collatz(int64_t limit) {
    int64_t best = 0;
    for (int64_t n = 1; n < limit; n++) {
        int64_t x = n, steps = 0;
        while (x != 1) {
            x = (x % 2 == 0) ? x / 2 : 3 * x + 1;
            steps++;
        }
        if (steps > best) best = steps;
    }
    return best;
}

typedef struct { double re, im; } Cx;
static inline Cx cx_mul(Cx a, Cx b) { return (Cx){a.re * b.re - a.im * b.im, a.re * b.im + a.im * b.re}; }
static inline Cx cx_add(Cx a, Cx b) { return (Cx){a.re + b.re, a.im + b.im}; }

static int64_t mandel(int64_t n) {
    int64_t total = 0;
    for (int64_t y = 0; y < n; y++)
        for (int64_t x = 0; x < n; x++) {
            Cx c = {3.0 * (double)x / (double)n - 2.0, 2.0 * (double)y / (double)n - 1.0};
            Cx z = {0.0, 0.0};
            int64_t i = 0;
            while (i < 100 && z.re * z.re + z.im * z.im < 4.0) {
                z = cx_add(cx_mul(z, z), c);
                i++;
            }
            total += i;
        }
    return total;
}

typedef struct { double x, y, vx, vy; } Particle;

static int64_t particles(int64_t n, int64_t steps) {
    Particle *ps = xmalloc(sizeof(Particle) * (size_t)n);
    for (int64_t i = 0; i < n; i++) ps[i] = (Particle){(double)i, (double)i * 0.5, 1.0, -1.0};
    for (int64_t s = 0; s < steps; s++)
        for (int64_t i = 0; i < n; i++) {
            Particle p = ps[i];
            p.x += p.vx * 0.01;
            p.y += p.vy * 0.01;
            if (p.x > 100.0) p.vx = -p.vx;
            ps[i] = p;
        }
    double e = 0.0;
    for (int64_t i = 0; i < n; i++) e += ps[i].x + ps[i].y;
    free(ps);
    return (int64_t)e;
}

enum { OP_PUSH, OP_ADD, OP_MUL, OP_DUP, OP_SWAP, OP_POP, OP_JMPNZ, OP_DEC };
typedef struct { int64_t kind, arg; } Op;

static int64_t vm(int64_t iters) {
    Op code[] = {{OP_PUSH, 3}, {OP_PUSH, 7}, {OP_MUL, 0}, {OP_POP, 0}, {OP_DEC, 0}, {OP_JMPNZ, 0}, {OP_POP, 0}};
    int64_t ncode = 7, cap = 4, len = 0, pc = 0, acc = 0;
    int64_t *st = xmalloc(sizeof(int64_t) * (size_t)cap);
#define PUSHV(v) do { if (len == cap) { cap *= 2; st = realloc(st, sizeof(int64_t) * (size_t)cap); } st[len++] = (v); } while (0)
#define POPV() (len == 0 ? 0 : st[--len])
    PUSHV(iters);
    while (pc < ncode) {
        Op o = code[pc];
        switch (o.kind) {
        case OP_PUSH: PUSHV(o.arg); pc++; break;
        case OP_ADD: { int64_t b = POPV(), a = POPV(); PUSHV(a + b); pc++; break; }
        case OP_MUL: { int64_t b = POPV(), a = POPV(); PUSHV(a * b % 1000003); pc++; break; }
        case OP_DUP: { int64_t v = st[len - 1]; PUSHV(v); pc++; break; }
        case OP_SWAP: { int64_t b = POPV(), a = POPV(); PUSHV(b); PUSHV(a); pc++; break; }
        case OP_POP: acc += POPV(); pc++; break;
        case OP_JMPNZ: if (st[len - 1] != 0) pc = o.arg; else pc++; break;
        case OP_DEC: { int64_t v = POPV(); PUSHV(v - 1); pc++; break; }
        }
    }
    free(st);
    return acc;
}

typedef struct Expr { int64_t kind, n; struct Expr *l, *r; } Expr;

static Expr *expr_build(int64_t d, int64_t s) {
    Expr *e = xmalloc(sizeof(Expr));
    e->n = 0;
    e->l = e->r = NULL;
    if (d == 0) { e->kind = 0; e->n = s % 10; return e; }
    if (d % 2 == 0) { e->kind = 1; e->l = expr_build(d - 1, s * 3 + 1); e->r = expr_build(d - 1, s * 7 + 2); }
    else { e->kind = 2; e->l = expr_build(d - 1, s + 1); e->r = expr_build(d - 1, s + 3); }
    return e;
}

static int64_t expr_eval(const Expr *e) {
    if (e->kind == 0) return e->n;
    if (e->kind == 1) return (expr_eval(e->l) + expr_eval(e->r)) % 1000003;
    return expr_eval(e->l) * expr_eval(e->r) % 1000003;
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
    for (int64_t i = 0; i < reps; i++) t += expr_eval(e);
    expr_free(e);
    return t;
}

static int64_t closures(int64_t n) {
    int64_t k = opaque(7), t = 0;
    for (int64_t i = 0; i < n; i++) t += (i * k + 1) % 13;
    int64_t *xs = xmalloc(sizeof(int64_t) * 1000);
    for (int64_t i = 0; i < 1000; i++) xs[i] = i * k;
    for (int64_t r = 0; r < n / 1000; r++)
        for (int64_t i = 0; i < 1000; i++) {
            int64_t v = xs[i] + k;
            if (v % 3 == 0) t += v;
        }
    free(xs);
    return t;
}

static int64_t stencil(int64_t n, int64_t iters) {
    int64_t *a = xmalloc(sizeof(int64_t) * (size_t)(n * n)), *b = xmalloc(sizeof(int64_t) * (size_t)(n * n));
    for (int64_t i = 0; i < n * n; i++) { a[i] = i % 17; b[i] = 0; }
    for (int64_t it = 0; it < iters; it++) {
        for (int64_t y = 1; y < n - 1; y++)
            for (int64_t x = 1; x < n - 1; x++)
                b[y * n + x] = (a[y * n + x - 1] + a[y * n + x + 1] + a[(y - 1) * n + x] + a[(y + 1) * n + x]) % 1009;
        int64_t *t = a; a = b; b = t;
    }
    int64_t s = 0;
    for (int64_t i = 0; i < n * n; i++) s += a[i];
    free(a);
    free(b);
    return s;
}

static int64_t now_us(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000000 + ts.tv_nsec / 1000;
}

#define TIMED(name, expr)                                              \
    do {                                                               \
        int64_t t0 = now_us();                                         \
        int64_t r = (expr);                                            \
        printf("%s %lld %lld\n", name, (long long)(now_us() - t0), (long long)r); \
    } while (0)

static int64_t nbody(void) {
    Body b[] = {{0, 0, 0, 0, 0, 0, 10}, {1, 0, 0, 0, 1, 0, 1}, {0, 2, 0, 1, 0, 0, 1}, {0, 0, 3, 0, 0, 1, 1}, {4, 4, 0, 0, 0, 0, 0.5}};
    return (int64_t)(advance(b, opaque(5), opaque(200000)) * 1000);
}

int main(void) {
    TIMED("sieve_5M", sieve(opaque(5000000)));
    TIMED("nbody_200k", nbody());
    TIMED("life_128x128_50", life(opaque(50)));
    TIMED("matmul_200", (int64_t)matmul(opaque(200)));
    TIMED("trees_d16_x20", trees(opaque(20)));
    TIMED("collatz_1M", collatz(opaque(1000000)));
    TIMED("mandel_400", mandel(opaque(400)));
    TIMED("particles_1k_5k", particles(opaque(1000), opaque(5000)));
    TIMED("vm_5M", vm(opaque(5000000)));
    TIMED("expr_d20_x20", exprs(opaque(20), opaque(20)));
    TIMED("closures_20M", closures(opaque(20000000)));
    TIMED("stencil_1000_20", stencil(opaque(1000), opaque(20)));
    return 0;
}

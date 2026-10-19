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

static uint64_t hash(int64_t k) {
    uint64_t z = (uint64_t)k + 0x9e3779b97f4a7c15u;
    z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9u;
    z = (z ^ (z >> 27)) * 0x94d049bb133111ebu;
    return z ^ (z >> 31);
}

// Unordered open addressing with linear probing; one probe per increment.
static int64_t wordfreq(int64_t n) {
    size_t cap = 16, len = 0;
    int64_t *keys = xmalloc(sizeof(int64_t) * cap), *vals = xmalloc(sizeof(int64_t) * cap);
    uint8_t *used = calloc(cap, 1);
    for (int64_t i = 0; i < n; i++) {
        int64_t k = (i * 7919) % 5003;
        size_t mask = cap - 1, h = hash(k) & mask;
        while (used[h] && keys[h] != k) h = (h + 1) & mask;
        if (used[h]) {
            vals[h]++;
            continue;
        }
        used[h] = 1, keys[h] = k, vals[h] = 1, len++;
        if (len * 4 >= cap * 3) {
            size_t ncap = cap * 2;
            int64_t *nk = xmalloc(sizeof(int64_t) * ncap), *nv = xmalloc(sizeof(int64_t) * ncap);
            uint8_t *nu = calloc(ncap, 1);
            for (size_t s = 0; s < cap; s++) {
                if (!used[s]) continue;
                size_t p = hash(keys[s]) & (ncap - 1);
                while (nu[p]) p = (p + 1) & (ncap - 1);
                nu[p] = 1, nk[p] = keys[s], nv[p] = vals[s];
            }
            free(keys), free(vals), free(used);
            keys = nk, vals = nv, used = nu, cap = ncap;
        }
    }
    free(keys), free(vals), free(used);
    return (int64_t)len;
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
    TIMED("map_count_2M", wordfreq(opaque(2000000)));
    return 0;
}

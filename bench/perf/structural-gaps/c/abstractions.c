#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef struct { long x, y, z; } Vec;
static Vec vadd(Vec a, Vec o) { return (Vec){a.x + o.x, a.y + o.y, a.z + o.z}; }
static long vdot(Vec a, Vec o) { return a.x * o.x + a.y * o.y + a.z * o.z; }
static Vec vwrap(Vec a) { return (Vec){a.x % 1000, a.y % 1000, a.z % 1000}; }
static long case_a(void) { Vec p = {1, 2, 3}; long t = 0;
  for (long i = 0; i < 20000000; i++) { Vec d = {i % 7, i % 5, i % 3}; p = vwrap(vadd(p, d)); t = (t + vdot(p, d)) % 1000003; } return t; }
typedef struct { char *name; long tier; } Customer;
typedef struct { long sku, qty, price; } Line;
typedef struct { long id; Customer customer; Line *lines; long nlines; } Order;
static long total(const Order *o) { long s = 0; for (long i = 0; i < o->nlines; i++) s += o->lines[i].qty * o->lines[i].price; return s; }
static long case_b(void) { long n = 100000; Order *os = malloc(n * sizeof(Order));
  for (long i = 0; i < n; i++) { Line *l = malloc(4 * sizeof(Line)); for (long k = 0; k < 4; k++) l[k] = (Line){i + k, k + 1, (i * 7 + k) % 100};
    char b[16]; snprintf(b, 16, "c%ld", i % 100); os[i] = (Order){i, {strdup(b), i % 3}, l, 4}; }
  long t = 0; for (int r = 0; r < 50; r++) for (long i = 0; i < n; i++) if (os[i].customer.tier != 1) t = (t + total(&os[i])) % 1000003; return t; }
typedef struct Shape { long (*area)(const struct Shape *); long a, b; } Shape;
static long ra(const Shape *s) { return s->a * s->b; }
static long sa(const Shape *s) { return s->a * s->a; }
static long ta(const Shape *s) { return s->a * s->b / 2; }
static long case_c(void) { long n = 100000; Shape **sh = malloc(n * sizeof(Shape *));
  for (long i = 0; i < n; i++) { Shape *s = malloc(sizeof(Shape)); long k = i % 3;
    if (k == 0) *s = (Shape){ra, i % 50, 3}; if (k == 1) *s = (Shape){sa, i % 40, 0}; if (k == 2) *s = (Shape){ta, i % 30, 4}; sh[i] = s; }
  long t = 0; for (int r = 0; r < 100; r++) for (long i = 0; i < n; i++) t = (t + sh[i]->area(sh[i])) % 1000003; return t; }
typedef struct { long (*f)(void *, long); void *env; } Fn;
static long f0(void *e, long v) { return v * *(long *)e; }
static long f1(void *e, long v) { return v + *(long *)e; }
static long f2(void *e, long v) { return v % (*(long *)e + 1); }
static long f3(void *e, long v) { return v * *(long *)e + 1; }
__attribute__((noinline)) static long apply_n(long n, Fn f) { long t = 0; for (long i = 0; i < n; i++) t = (t + f.f(f.env, i)) % 1000003; return t; }
static long case_d(void) { long k = 17; Fn fs[3] = {{f0, &k}, {f1, &k}, {f2, &k}}; long t = 0;
  for (long i = 0; i < 10000000; i++) t = (t + fs[i % 3].f(fs[i % 3].env, i)) % 1000003; return t + apply_n(10000000, (Fn){f3, &k}); }
__attribute__((noinline)) static long largest(const long *xs, long n) { long best = 0; for (long i = 1; i < n; i++) if (xs[i] > xs[best]) best = i; return best; }
static long case_e(void) { long n = 10000; long *xs = malloc(n * sizeof(long)); for (long i = 0; i < n; i++) xs[i] = i * 7919 % 10007;
  long t = 0; for (int r = 0; r < 2000; r++) { xs[r] += r; t += largest(xs, n); } return t; }
typedef struct { long count, sum; } Stats; typedef struct { char *name; Stats stats; } Meter;
__attribute__((noinline)) static void record(Meter *m, long v) { m->stats.count += 1; m->stats.sum = (m->stats.sum + v) % 1000003; }
static long case_f(void) { Meter m = {"m", {0, 0}}; for (long i = 0; i < 30000000; i++) record(&m, i); return m.stats.sum + m.stats.count; }
int main(void) { printf("%ld %ld %ld %ld %ld %ld\n", case_a(), case_b(), case_c(), case_d(), case_e(), case_f()); return 0; }

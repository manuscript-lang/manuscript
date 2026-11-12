#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "ordmap.h"
typedef struct { long count, sum, max; } S;
ORDMAP(StatMap, S)
static long case_a(void) { StatMap m = {0}; long x = 12345;
  for (long i = 0; i < 2000000; i++) { x = (x * 1103515245 + 12345) % 2147483648; long k = x % 1000;
    S *s = StatMap_at(&m, k); s->count++; s->sum += i % 100; if (i % 100 > s->max) s->max = i % 100; }
  long t = 0; for (size_t i = 0; i < m.used; i++) if (m.slots[i].hash) t += m.slots[i].value.count + m.slots[i].value.sum + m.slots[i].value.max; return t; }
typedef struct E { int tag; long v; struct E *l, *r; } E;
static E *mk(int tag, long v, E *l, E *r) { E *e = malloc(sizeof(E)); e->tag = tag; e->v = v; e->l = l; e->r = r; return e; }
static E *build(long d, long s) { if (d == 0) return mk(0, s % 10, 0, 0); long k = s % 5;
  if (k == 0) return mk(3, 0, build(d - 1, s * 7 + 1), 0);
  if (k == 1) { E *l = build(d - 1, s * 3 + 1); return mk(2, 0, l, build(d - 1, s + 3)); }
  E *l = build(d - 1, s * 5 + 2); return mk(1, 0, l, build(d - 1, s * 11 + 3)); }
static long ev(const E *e) { switch (e->tag) { case 0: return e->v; case 1: return (ev(e->l) + ev(e->r)) % 1000003;
    case 2: return (ev(e->l) * ev(e->r)) % 1000003; default: return -ev(e->l); } }
static void fr(E *e) { if (!e) return; fr(e->l); fr(e->r); free(e); }
static long case_b(void) { long t = 0; for (long r = 0; r < 4; r++) { E *e = build(20, r + 2); for (int k = 0; k < 10; k++) t = (t + ev(e)) % 1000003; fr(e); } return t; }
typedef struct { long v; char some; } O;
static long case_c(void) { long n = 1000000; O *c = malloc(n * sizeof(O)); for (long i = 0; i < n; i++) { c[i].some = i % 3 != 0; c[i].v = i; }
  long t = 0; for (int r = 0; r < 30; r++) for (long i = 0; i < n; i++) if (c[i].some) t += c[i].v % 7; return t; }
__attribute__((noinline)) static long wsum(const long *xs, long n) { long s = 0; for (long i = 0; i < n; i++) s += xs[i]; return s; }
static long case_d(void) { long n = 100000; long *xs = malloc(n * 8); for (long i = 0; i < n; i++) xs[i] = i % 1000; long t = 0;
  for (int r = 0; r < 200; r++) for (long w = 0; w < 100; w++) t += wsum(xs + w * 1000, 1000); return t % 1000003; }
static long case_e(void) { long t = 0; char line[96], b[128];
  for (long i = 0; i < 300000; i++) { int n = snprintf(line, 96, "  Hello, World number %ld  ", i); char *a = line; while (isspace((unsigned char)*a)) a++, n--; while (n && isspace((unsigned char)a[n - 1])) n--; a[n] = 0;
    char *p = strstr(a, "World"); size_t m = 0; if (p) { memcpy(b, a, p - a); m = p - a; memcpy(b + m, "there", 5); m += 5; strcpy(b + m, p + 5); } else strcpy(b, a);
    for (char *q = b; *q; q++) *q = toupper((unsigned char)*q); if (strstr(b, "THERE")) t += strlen(b); } return t; }
typedef struct { char unused; } Unit;
ORDMAP(IntSet, Unit)
static long case_f(void) { IntSet s = {0}; long x = 12345, dup = 0;
  for (long i = 0; i < 3000000; i++) { x = (x * 1103515245 + 12345) % 2147483648; long k = x % 200000;
    size_t before = s.len; IntSet_at(&s, k); if (s.len == before) dup++; } return dup + s.len; }
int main(void) { printf("%ld %ld %ld %ld %ld %ld\n", case_a(), case_b(), case_c(), case_d(), case_e(), case_f()); return 0; }

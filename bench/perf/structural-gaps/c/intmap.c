#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef struct { long k, v; char used; } E;
static E *tab; static long cap = 16, len = 0;
static inline unsigned long h(long k) { unsigned long z = (unsigned long)k * 0x9E3779B97F4A7C15ul; return z ^ (z >> 32); }
static E *find(long k) { unsigned long i = h(k) & (cap - 1); while (tab[i].used && tab[i].k != k) i = (i + 1) & (cap - 1); return &tab[i]; }
static void grow(void) { E *old = tab; long oc = cap; cap *= 2; tab = calloc(cap, sizeof(E));
  for (long i = 0; i < oc; i++) if (old[i].used) { E *e = find(old[i].k); *e = old[i]; } free(old); }
int main(void) {
  tab = calloc(cap, sizeof(E)); long x = 12345;
  for (long i = 0; i < 2000000; i++) { x = (x * 1103515245 + 12345) % 2147483648; long k = x % 50000;
    E *e = find(k); if (!e->used) { if ((len + 1) * 4 > cap * 3) { grow(); e = find(k); } e->used = 1; e->k = k; e->v = 0; len++; } e->v++; }
  long best = 0, hits = 0;
  for (long i = 0; i < 2000000; i++) { x = (x * 1103515245 + 12345) % 2147483648; if (find(x % 100000)->used) hits++; }
  for (long i = 0; i < cap; i++) if (tab[i].used && tab[i].v > best) best = tab[i].v;
  printf("%ld %ld %ld\n", len, best, hits); return 0;
}

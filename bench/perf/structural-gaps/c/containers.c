#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef struct { char *k; size_t kl; long count, sum; } SS;
static unsigned long hs(const char *s, size_t n) { unsigned long h = 1469598103934665603ul; for (size_t i = 0; i < n; i++) h = (h ^ (unsigned char)s[i]) * 1099511628211ul; return h; }
static long case_a(void) { char **names = malloc(2000 * sizeof(char *)); size_t *nl = malloc(2000 * sizeof(size_t)); char b[32];
  for (long i = 0; i < 2000; i++) { nl[i] = snprintf(b, 32, "user-%ld", i * 7919 % 2003); names[i] = strdup(b); }
  long cap = 4096; SS *tab = calloc(cap, sizeof(SS));
  for (long i = 0; i < 2000000; i++) { const char *n = names[i % 2000]; size_t l = nl[i % 2000]; unsigned long h = hs(n, l) & (cap - 1);
    while (tab[h].k && !(tab[h].kl == l && !memcmp(tab[h].k, n, l))) h = (h + 1) & (cap - 1);
    if (!tab[h].k) { tab[h].k = strdup(n); tab[h].kl = l; } tab[h].count++; tab[h].sum += i % 10; }
  long t = 0; for (long i = 0; i < cap; i++) if (tab[i].k) t += tab[i].count + tab[i].sum; return t; }
typedef struct { long k, v; char used; } E;
static long case_b(void) { long cap = 1 << 19; E *tab = calloc(cap, sizeof(E)); long *order = malloc(200000 * 8); long n = 0;
  for (long i = 0; i < 200000; i++) { long k = i * 7919 % 200003; unsigned long h = ((unsigned long)k * 0x9E3779B97F4A7C15ul) >> 45;
    while (tab[h].used && tab[h].k != k) h = (h + 1) & (cap - 1); if (!tab[h].used) { tab[h].used = 1; tab[h].k = k; order[n++] = h; } tab[h].v = i; }
  long t = 0; for (int r = 0; r < 20; r++) { for (long i = 0; i < n; i++) t += tab[order[i]].v % 7;
    for (long i = 0; i < n; i++) { long k = tab[order[i]].k; unsigned long h = ((unsigned long)k * 0x9E3779B97F4A7C15ul) >> 45; while (tab[h].k != k) h = (h + 1) & (cap - 1); t += tab[h].v % 3; }
    for (long i = 0; i < n; i++) t += tab[order[i]].v % 5; } return t; }
static long case_c(void) { size_t cap = 1 << 16, len = 0; char *out = malloc(cap);
  for (long i = 0; i < 300000; i++) { if (len + 96 > cap) out = realloc(out, cap *= 2); len += sprintf(out + len, "%ld,user%ld,%ld,ok\n", i, i % 97, i * 31 % 1000); } return len; }
static long case_d(void) { long n = 2000; long *xs = malloc((n + 1) * 8); for (long i = 0; i < n; i++) xs[i] = i; long t = 0;
  for (long r = 0; r < 200000; r++) { long v = xs[0]; memmove(xs, xs + 1, (n - 1) * 8); memmove(xs + 1001, xs + 1000, (n - 1 - 1000) * 8); xs[1000] = v;
    t += xs[n - 1]; memmove(xs + 1, xs, (n - 1) * 8); xs[0] = t % 2000; } return t % 1000003; }
typedef struct { long rows, cols; double *d; } Mx;
static Mx zeros(long r, long c) { return (Mx){r, c, calloc(r * c, 8)}; }
__attribute__((noinline)) static Mx mul(const Mx *a, const Mx *b) { Mx c = zeros(a->rows, b->cols);
  for (long i = 0; i < a->rows; i++) for (long j = 0; j < b->cols; j++) { double s = 0; for (long k = 0; k < a->cols; k++) s += a->d[i * a->cols + k] * b->d[k * b->cols + j]; c.d[i * c.cols + j] = s; } return c; }
static long case_e(void) { long n = 200; Mx a = zeros(n, n), b = zeros(n, n);
  for (long i = 0; i < n; i++) for (long j = 0; j < n; j++) { a.d[i * n + j] = (double)(i + j) * 0.01; b.d[i * n + j] = (double)(i - j) * 0.02; }
  double t = 0; for (int r = 0; r < 3; r++) { Mx c = mul(&a, &b); t += c.d[r * n + r + 1]; free(c.d); } return (long)t; }
static long case_f(void) { long cap = 16, len = 0; long *s = malloc(cap * 8); long t = 0;
  for (long i = 0; i < 20000000; i++) { if (len == cap) s = realloc(s, (cap *= 2) * 8); s[len++] = i;
    if (i % 3 == 2) { t += (len ? s[--len] : 0) % 7; t += (len ? s[--len] : 0) % 5; } } return t + len; }
int main(void) { printf("%ld %ld %ld %ld %ld %ld\n", case_a(), case_b(), case_c(), case_d(), case_e(), case_f()); return 0; }

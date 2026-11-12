#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
static long case_a(void) { long n = 100000; double *xs = malloc(n * 8), *ys = malloc(n * 8);
  for (long i = 0; i < n; i++) { xs[i] = (double)i * 0.5; ys[i] = 1.0; } double s = 0;
  for (int r = 0; r < 300; r++) { for (long i = 0; i < n; i++) ys[i] = ys[i] * 0.999 + xs[i] * 0.001; for (long i = 0; i < n; i++) s += ys[i]; }
  return (long)s % 1000003; }
typedef struct { long id, score; char *name; } Rec;
static int cmp(const void *a, const void *b) { long d = ((const Rec *)a)->score - ((const Rec *)b)->score; return d < 0 ? -1 : d > 0; }
static long case_b(void) { long t = 0; for (int r = 0; r < 5; r++) { long n = 200000; Rec *rs = malloc(n * sizeof(Rec)); char b[16];
    for (long i = 0; i < n; i++) { snprintf(b, 16, "n%ld", i % 1000); rs[i] = (Rec){i, (i * 7919 + r) % 100003, strdup(b)}; }
    qsort(rs, n, sizeof(Rec), cmp); t += rs[1000].id; for (long i = 0; i < n; i++) free(rs[i].name); free(rs); } return t; }
typedef struct Node { long key; struct Node *l, *r; } Node;
static Node *mk(long k) { Node *n = malloc(sizeof(Node)); n->key = k; n->l = n->r = 0; return n; }
static void ins(Node *n, long k) { for (;;) { Node **s = k < n->key ? &n->l : &n->r; if (!*s) { *s = mk(k); return; } n = *s; } }
static long depth(const Node *n) { if (!n) return 0; long a = depth(n->l), b = depth(n->r); return 1 + (a > b ? a : b); }
static void fr(Node *n) { if (!n) return; fr(n->l); fr(n->r); free(n); }
static long case_c(void) { Node *root = mk(500000); long x = 12345;
  for (long i = 0; i < 200000; i++) { x = (x * 1103515245 + 12345) % 2147483648; ins(root, x % 1000000); } long d = depth(root); fr(root); return d; }
static long case_d(void) { return 0; }
static long case_e(void) { long n = 200000; char **w = malloc(n * sizeof(char *)); size_t *len = malloc(n * sizeof(size_t)); char b[16];
  for (long i = 0; i < n; i++) { len[i] = snprintf(b, 16, "w%ld", i * 7919 % 5003); w[i] = strdup(b); } long t = 0;
  for (int r = 0; r < 20; r++) for (long i = 0; i < n; i++) { if ((len[i] == 3 && !memcmp(w[i], "w42", 3)) || (len[i] >= 3 && !memcmp(w[i], "w49", 3))) t++; t += len[i]; } return t; }
static long case_f(void) { long n = 1000000; long *xs = malloc(n * 8); for (long i = 0; i < n; i++) xs[i] = i * 7919 % 10007; long t = 0;
  for (long r = 0; r < 20; r++) { long *f = malloc(n * 8), nf = 0; for (long i = 0; i < n; i++) if (xs[i] % 3 == 0) f[nf++] = xs[i]; t += nf; free(f);
    long *m = malloc(n * 8); for (long i = 0; i < n; i++) m[i] = xs[i] + r; long a = 0; for (long i = 0; i < n; i++) a = (a + m[i]) % 1000003; t += a; free(m);
    for (long i = 0; i < n; i++) if (xs[i] == -r - 1) { t++; break; }
    long at = 0; for (long i = 0; i < n; i++) if (xs[i] == 10006 - r) { at = i; break; } t += at; } return t; }
int main(void) { printf("%ld %ld %ld %ld %ld %ld\n", case_a(), case_b(), case_c(), case_d(), case_e(), case_f()); return 0; }

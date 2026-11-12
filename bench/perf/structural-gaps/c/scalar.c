#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
__attribute__((noinline)) static uint64_t fnv(const unsigned char *d, long n) { uint64_t h = 1469598103934665603ull; for (long i = 0; i < n; i++) h = (h ^ d[i]) * 1099511628211ull; return h; }
static long case_a(void) { const char *s = "the quick brown fox jumps over the lazy dog, again and again and again"; long l = strlen(s); unsigned char *d = malloc(l * 1000);
  for (int i = 0; i < 1000; i++) memcpy(d + i * l, s, l); uint64_t t = 0; for (int r = 0; r < 300; r++) { t ^= fnv(d, l * 1000); } return t & 1048575; }
static long case_b(void) { uint64_t x = 88172645463325252ull, t = 0; for (long i = 0; i < 50000000; i++) { x ^= x << 13; x ^= x >> 7; x ^= x << 17; t += x & 255; } return t & 1048575; }
static long case_c(void) { long n = 1000000; unsigned char *p = malloc(n); for (long i = 0; i < n; i++) p[i] = i * 31 % 256; long t = 0;
  for (int r = 0; r < 30; r++) for (long i = 0; i < n; i++) { long v = p[i]; t += (v * 77 + 150 * (255 - v) + 29) / 256; } return t % 1000003; }
static long case_d(void) { long n = 100000; long *xs = malloc(n * 8); for (long i = 0; i < n; i++) xs[i] = i * 7919 % 100003; long t = 0;
  for (long r = 0; r < 300; r++) { for (long i = 0; i < n; i++) if (xs[i] == 100002 - r) { t++; break; }
    long at = 0; for (long i = 0; i < n; i++) if (xs[i] > 99990 - r) { at = i; break; } t += at;
    int all = 1; for (long i = 0; i < n; i++) if (!(xs[i] >= 0)) { all = 0; break; } t += all; } return t; }
__attribute__((noinline)) static long kind(const char *w) { if (!strcmp(w, "if")) return 1; if (!strcmp(w, "else")) return 2; if (!strcmp(w, "while")) return 3;
  if (!strcmp(w, "for")) return 4; if (!strcmp(w, "return")) return 5; if (!strcmp(w, "fn")) return 6; return 0; }
static long case_e(void) { const char *words[] = {"if", "x", "else", "while", "name", "for", "return", "fn", "value", "other"}; long t = 0;
  for (long i = 0; i < 20000000; i++) t += kind(words[i % 10]); return t; }
typedef struct { long *total, *calls; } Env;
static void bump(void *e, long v) { Env *x = e; *x->total = (*x->total + v) % 1000003; *x->calls += 1; }
__attribute__((noinline)) static void each(long n, void (*f)(void *, long), void *e) { for (long i = 0; i < n; i++) f(e, i); }
static long case_f(void) { long total = 0, calls = 0; Env e = {&total, &calls}; each(30000000, bump, &e); return total + calls; }
int main(void) { printf("%ld %ld %ld %ld %ld %ld\n", case_a(), case_b(), case_c(), case_d(), case_e(), case_f()); return 0; }

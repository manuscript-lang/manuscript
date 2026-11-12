#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
typedef struct { long x, y, vx, vy; bool alive; } P;
__attribute__((noinline)) static void step(P *ps, long n) {
  for (long i = 0; i < n; i++) if (ps[i].alive) {
    ps[i].x += ps[i].vx; ps[i].y += ps[i].vy;
    if (ps[i].x > 100000 || ps[i].x < 0) ps[i].vx = -ps[i].vx;
  }
}
__attribute__((noinline)) static long energy(const P *ps, long n) {
  long e = 0;
  for (long i = 0; i < n; i++) if (ps[i].alive) e += ps[i].vx * ps[i].vx + ps[i].vy * ps[i].vy;
  return e;
}
int main(void) {
  long n = 100000; P *ps = malloc(n * sizeof(P));
  for (long i = 0; i < n; i++) ps[i] = (P){i, i * 2 % 1000, i % 7 - 3, i % 5 - 2, i % 9 != 0};
  long t = 0;
  for (int r = 0; r < 200; r++) { step(ps, n); t = (t + energy(ps, n)) % 1000003; }
  printf("%ld %ld\n", t, ps[77].x); return 0;
}

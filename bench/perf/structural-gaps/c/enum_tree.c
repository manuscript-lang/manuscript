#include <stdio.h>
#include <stdlib.h>
// Twin of enum_tree.ms: Add and Mul trap on overflow and Neg on the minimum, as Manuscript's checked Int does.
typedef struct E { int tag; long v; struct E *l, *r; } E;
static E *mk(int tag, long v, E *l, E *r) { E *e = malloc(sizeof(E)); e->tag = tag; e->v = v; e->l = l; e->r = r; return e; }
static E *build(long d, long s) { if (d == 0) return mk(0, s % 10, 0, 0); long k = s % 5;
  if (k == 0) return mk(3, 0, build(d - 1, s * 7 + 1), 0);
  if (k == 1) { E *l = build(d - 1, s * 3 + 1); return mk(2, 0, l, build(d - 1, s + 3)); }
  E *l = build(d - 1, s * 5 + 2); return mk(1, 0, l, build(d - 1, s * 11 + 3)); }
static long ev(const E *e) { switch (e->tag) { case 0: return e->v; case 1: { long a=ev(e->l), b=ev(e->r), c; if (__builtin_add_overflow(a,b,&c)) __builtin_trap(); return c % 1000003; }
    case 2: { long a=ev(e->l), b=ev(e->r), c; if (__builtin_mul_overflow(a,b,&c)) __builtin_trap(); return c % 1000003; } default: { long a=ev(e->l); if (a==(-9223372036854775807L-1)) __builtin_trap(); return -a; } } }
static void fr(E *e) { if (!e) return; fr(e->l); fr(e->r); free(e); }
int main(void) {
	long t = 0;
	for (long r = 0; r < 4; r++) {
		E *e = build(20, r + 2);
		for (int k = 0; k < 10; k++) t = (t + ev(e)) % 1000003;
		fr(e);
	}
	printf("%ld\n", t);
	return 0;
}

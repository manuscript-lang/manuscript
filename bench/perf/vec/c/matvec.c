/* The matrix-vector product of ms/src/main.ms in C. KERNEL picks the inner loop:
 *   scalar  plain loop, strict IEEE order (no -ffast-math), what C gives without opting in
 *   lanes   explicit 8-lane vectors, four accumulators, the same order as @std/vec.ms
 *   fast    plain loop; build with -ffast-math so the compiler may reorder and vectorize it */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef float V __attribute__((vector_size(32)));
static inline V ld(const float *p) { V v; memcpy(&v, p, sizeof v); return v; }

static float dot(const float *a, const float *b, long n) {
#if defined(KERNEL_lanes)
    V a0 = {0}, a1 = {0}, a2 = {0}, a3 = {0};
    long i = 0;
    for (; i + 32 <= n; i += 32) {
        a0 += ld(a + i) * ld(b + i);
        a1 += ld(a + i + 8) * ld(b + i + 8);
        a2 += ld(a + i + 16) * ld(b + i + 16);
        a3 += ld(a + i + 24) * ld(b + i + 24);
    }
    for (; i + 8 <= n; i += 8) a0 += ld(a + i) * ld(b + i);
    V t = (a0 + a1) + (a2 + a3);
    float s = ((t[0] + t[4]) + (t[2] + t[6])) + ((t[1] + t[5]) + (t[3] + t[7]));
    for (; i < n; i++) s += a[i] * b[i];
    return s;
#else
    float s = 0;
    for (long i = 0; i < n; i++) s += a[i] * b[i];
    return s;
#endif
}

static void run(const char *name, int rows, int cols, int reps) {
    float *w = malloc(sizeof(float) * (long)rows * cols), *x = malloc(sizeof(float) * cols), *o = malloc(sizeof(float) * rows);
    for (long k = 0; k < (long)rows * cols; k++) w[k] = ((k % 17) - 8) * 0.01f;
    for (int k = 0; k < cols; k++) x[k] = (k % 5) * 0.1f;
    struct timespec a, b;
    clock_gettime(CLOCK_MONOTONIC, &a);
    for (int r = 0; r < reps; r++)
        for (int i = 0; i < rows; i++) o[i] = dot(w + (long)i * cols, x, cols);
    clock_gettime(CLOCK_MONOTONIC, &b);
    double ns = (b.tv_sec - a.tv_sec) * 1e9 + (b.tv_nsec - a.tv_nsec);
    printf("%s %dx%d %f %g\n", name, rows, cols, 2.0 * rows * cols * reps / ns, o[0]);
    free(w); free(x); free(o);
}

int main(int argc, char **argv) {
    const char *name = argc > 1 ? argv[1] : "c";
    run(name, 288, 288, 20000);
    run(name, 768, 288, 5000);
    run(name, 4096, 4096, 20);
    return 0;
}

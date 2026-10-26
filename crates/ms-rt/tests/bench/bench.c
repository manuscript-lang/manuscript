// Micro-benchmarks of hot runtime paths, driven like generated code. Prints "name ns/op".
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include "../../../ms-rt-abi/include/ms_abi.h"

typedef struct { uint8_t *ptr; size_t len, cap; } VecVal;
typedef struct { void *slots, *index; size_t len, used, cap, mask; const void *desc; } MapVal;
extern int32_t msrt_start(int64_t (*)(void), const void *, int, char **);
extern const char msrt_desc_int[], msrt_desc_string[];
extern void msrt_list_push(VecVal *, const void *, const void *);
extern void msrt_list_drop(VecVal *, const void *);
extern void msrt_list_sort_in_place(VecVal *, const void *, int64_t (*)(void *, const void *, const void *), void *);
extern void msrt_map_add(MapVal *, const void *, const void *, void *, void *);
extern const void *msrt_map_get_ptr(const MapVal *, const void *, const void *, const void *);
extern void msrt_map_drop(MapVal *, const void *, const void *);
extern void msrt_string_concat(const ms_str *, const ms_str *, ms_str *);
extern void msrt_string_free(const ms_str *);
extern int64_t msrt_string_length(const ms_str *);

static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1e9 + t.tv_nsec; }
static void report(const char *n, double t0, long ops) { printf("%s %.1f\n", n, (now() - t0) / ops); }
static int64_t cmp(void *e, const void *a, const void *b) { int64_t x = *(int64_t *)a, y = *(int64_t *)b; return x < y ? -1 : x > y; }

static int64_t entry(void) {
    const long N = 2000000;
    double t = now();
    VecVal v = {0};
    for (int64_t i = 0; i < N; i++) { int64_t x = (i * 2654435761u) % 1000003; msrt_list_push(&v, msrt_desc_int, &x); }
    report("list_push_int", t, N);
    t = now();
    msrt_list_sort_in_place(&v, msrt_desc_int, cmp, 0);
    report("list_sort_int", t, N);
    msrt_list_drop(&v, msrt_desc_int);

    t = now();
    MapVal m = {0};
    for (int64_t i = 0; i < N / 2; i++) { int64_t k = i * 7, val = i; msrt_map_add(&m, msrt_desc_int, msrt_desc_int, &k, &val); }
    report("map_insert_int", t, N / 2);
    t = now();
    long hits = 0;
    for (int64_t i = 0; i < N / 2; i++) { int64_t k = i * 7; hits += msrt_map_get_ptr(&m, msrt_desc_int, msrt_desc_int, &k) != 0; }
    report("map_get_int", t, N / 2);
    msrt_map_drop(&m, msrt_desc_int, msrt_desc_int);

    t = now();
    ms_str s;
    msrt_string_from_bytes((const uint8_t *)"ab", 2, &s);
    for (int i = 0; i < N / 10; i++) { ms_str c; msrt_string_concat(&s, &s, &c); hits += msrt_string_length(&c); msrt_string_free(&c); }
    report("string_concat_len", t, N / 10);
    msrt_string_free(&s);
    return hits != N / 2 + 4 * (N / 10);
}

int main(int argc, char **argv) { return msrt_start(entry, 0, argc, argv); }

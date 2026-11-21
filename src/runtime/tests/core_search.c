/* Unit test for src/runtime/core/search.c: a naive search as the reference, then adversarial inputs that must
 * finish quickly. `make c-test` builds it with ASan and UBSan. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "ms_rt/search.h"

static void check(bool ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "core_search.c:%d: %s\n", line, text);
        abort();
    }
}
#define CHECK(cond) check((cond), __LINE__, #cond)

static uint64_t seed = 88172645463325252ULL;
static uint32_t rnd(void) {
    seed ^= seed << 13;
    seed ^= seed >> 7;
    seed ^= seed << 17;
    return (uint32_t)(seed >> 16);
}

static size_t naive_find(const uint8_t *h, size_t n, const uint8_t *x, size_t m) {
    if (m == 0) return 0;
    for (size_t i = 0; i + m <= n; i++) {
        if (memcmp(h + i, x, m) == 0) return i;
    }
    return SIZE_MAX;
}

static size_t naive_count(const uint8_t *h, size_t n, const uint8_t *x, size_t m) {
    size_t c = 0, pos = 0;
    while (m && n - pos >= m) {
        size_t i = naive_find(h + pos, n - pos, x, m);
        if (i == SIZE_MAX) break;
        c++;
        pos += i + m;
    }
    return c;
}

int main(void) {
    uint8_t hay[700], nd[80];
    for (int iter = 0; iter < 400000; iter++) {
        unsigned alpha = 1 + rnd() % 3;
        size_t n = rnd() % 600, m = rnd() % 70;
        for (size_t i = 0; i < n; i++) hay[i] = (uint8_t)('a' + rnd() % alpha);
        if (rnd() % 2 && n >= m) {
            memcpy(nd, hay + (n - m ? rnd() % (n - m + 1) : 0), m);
        } else {
            for (size_t i = 0; i < m; i++) nd[i] = (uint8_t)('a' + rnd() % alpha);
        }
        CHECK(ms_find(hay, n, nd, m) == naive_find(hay, n, nd, m));
        CHECK(ms_count(hay, n, nd, m) == naive_count(hay, n, nd, m));
    }
    /* Spaces and punctuation, the bytes the short path skips as pivots. */
    const char *text = "the quick  brown / fox, jumps - over: a_lazy.dog and the dog barks";
    CHECK(ms_find((const uint8_t *)text, strlen(text), (const uint8_t *)" / ", 3) == naive_find((const uint8_t *)text, strlen(text), (const uint8_t *)" / ", 3));
    /* Adversarial long inputs finish in linear time: a quadratic search would take minutes. */
    size_t big = 16u << 20;
    uint8_t *h = malloc(big), *x = malloc(1001);
    memset(h, 'a', big);
    memset(x, 'a', 1000);
    x[1000] = 'b';
    clock_t t0 = clock();
    CHECK(ms_find(h, big, x, 1001) == SIZE_MAX);
    for (size_t i = 0; i < big; i++) h[i] = (uint8_t)((i & 1) ? 'b' : 'a');
    for (size_t i = 0; i < 1001; i++) x[i] = (uint8_t)((i & 1) ? 'b' : 'a');
    CHECK(ms_find(h, big, x, 1001) == 0);
    x[999] = 'a'; /* "aa" never occurs in the alternating text */
    CHECK(ms_find(h, big, x, 1001) == SIZE_MAX);
    memset(h, 'a', big);
    CHECK(ms_count(h, big, (const uint8_t *)"aa", 2) == big / 2);
    CHECK((double)(clock() - t0) / CLOCKS_PER_SEC < 30.0);
    free(h);
    free(x);
    puts("core_search: ok");
    return 0;
}

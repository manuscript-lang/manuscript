/* Unit test for src/runtime/sys/mem_x86.c: every copy size and offset, forward and backward overlaps, fills, and the order
 * of comparisons. Ported from the tests of crates/ms-rt/src/mem.rs. The routines exist on x86-64 only. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(__x86_64__)
#include "../sys/mem_x86.h"

static void check(int ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "sys_mem_x86.c:%d: %s\n", line, text);
        abort();
    }
}
#define CHECK(cond) check((cond), __LINE__, #cond)

static void pattern(unsigned char *buffer, size_t n, unsigned char seed) {
    for (size_t i = 0; i < n; i++) {
        buffer[i] = (unsigned char)(i * 31u + seed);
    }
}

static int all_equal(const unsigned char *p, size_t n, unsigned char value) {
    for (size_t i = 0; i < n; i++) {
        if (p[i] != value) {
            return 0;
        }
    }
    return 1;
}

/* Copies every size from two to 4097 bytes at odd offsets and checks the bytes around the destination are untouched. */
static void test_copy_sizes(void) {
    static const size_t extra[] = {1023, 1024, 2047, 2048, 2049, 4097};
    for (size_t k = 0; k < 301 + sizeof extra / sizeof *extra; k++) {
        const size_t n = k <= 300 ? k : extra[k - 301];
        unsigned char *src = malloc(n + 16), *dst = malloc(n + 16);
        pattern(src, n + 16, 5);
        memset(dst, 0xAA, n + 16);
        CHECK(ms_mem_copy(dst + 3, src + 1, n) == dst + 3);
        CHECK(memcmp(dst + 3, src + 1, n) == 0);
        CHECK(all_equal(dst, 3, 0xAA) && all_equal(dst + 3 + n, 13, 0xAA));
        free(src);
        free(dst);
    }
}

/* A move inside one buffer equals the same copy through a snapshot, for every shift in both directions. */
static void check_move(size_t n, size_t shift, size_t offset, int forward) {
    const size_t total = offset + shift + n + 17;
    unsigned char *buffer = malloc(total), *expected = malloc(total);
    for (size_t i = 0; i < total; i++) {
        buffer[i] = (unsigned char)((i * 31u) ^ (i / 251u));
    }
    memcpy(expected, buffer, total);
    if (forward) { /* dst above src: a backward copy */
        memcpy(expected + offset + shift, buffer + offset, n);
        CHECK(ms_mem_move(buffer + offset + shift, buffer + offset, n) == buffer + offset + shift);
    } else { /* dst below src: a forward copy */
        memcpy(expected + offset, buffer + offset + shift, n);
        CHECK(ms_mem_move(buffer + offset, buffer + offset + shift, n) == buffer + offset);
    }
    CHECK(memcmp(buffer, expected, total) == 0);
    free(buffer);
    free(expected);
}

static void test_moves(void) {
    for (size_t n = 0; n <= 130; n++) {
        for (size_t shift = 0; shift <= 130; shift++) {
            for (size_t offset = 0; offset < 8; offset += 3) {
                check_move(n, shift, offset, 1);
                check_move(n, shift, offset, 0);
            }
        }
    }
    static const size_t big[] = {255, 256, 257, 1023, 1024, 1025, 24576, 73728};
    for (size_t i = 0; i < sizeof big / sizeof *big; i++) {
        const size_t n = big[i];
        const size_t shifts[] = {0, 1, 7, 8, 15, 16, 31, 32, 63, 64, 65, 127, 128, n - 1, n, n + 1};
        for (size_t s = 0; s < sizeof shifts / sizeof *shifts; s++) {
            check_move(n, shifts[s], 1, 1);
            check_move(n, shifts[s], 7, 0);
        }
    }
}

static void test_set(void) {
    for (size_t n = 0; n <= 300; n++) {
        for (size_t offset = 0; offset < 4; offset++) {
            unsigned char *buffer = malloc(n + 8);
            memset(buffer, 0x11, n + 8);
            CHECK(ms_mem_set(buffer + offset, 0x1C7, n) == buffer + offset); /* only the low byte counts */
            CHECK(all_equal(buffer, offset, 0x11) && all_equal(buffer + offset, n, 0xC7) &&
                  all_equal(buffer + offset + n, 8 - offset, 0x11));
            free(buffer);
        }
    }
}

static int sign(int v) { return (v > 0) - (v < 0); }

static void test_compare(void) {
    for (size_t n = 0; n <= 40; n++) {
        unsigned char a[48], b[48];
        pattern(a, sizeof a, 1);
        memcpy(b, a, sizeof b);
        CHECK(ms_mem_compare(a, b, n) == 0);
        for (size_t at = 0; at < n; at++) {
            for (unsigned delta = 1; delta <= 200; delta += 199) {
                b[at] = (unsigned char)(a[at] + delta);
                CHECK(sign(ms_mem_compare(a, b, n)) == sign(memcmp(a, b, n)));
                b[at] = a[at];
            }
        }
    }
}

int main(void) {
    test_copy_sizes();
    test_moves();
    test_set();
    test_compare();
    puts("sys_mem_x86: ok");
    return 0;
}
#else
int main(void) {
    puts("sys_mem_x86: not applicable (x86-64 only)");
    return 0;
}
#endif

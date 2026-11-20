/* Tests for ms_rt/safe.h: checked sizes and spans refuse what would overflow or read out of bounds. */
#include "ms_rt/safe.h"

#include <stdio.h>
#include <stdlib.h>

#define CHECK(condition) \
    do { \
        if (!(condition)) { \
            fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, #condition); \
            exit(1); \
        } \
    } while (0)

static void test_sizes(void) {
    size_t out = 0;
    CHECK(ms_size_add(2, 3, &out) && out == 5);
    CHECK(!ms_size_add(SIZE_MAX, 1, &out) && out == 5);
    CHECK(ms_size_mul(6, 7, &out) && out == 42);
    CHECK(!ms_size_mul(SIZE_MAX / 2 + 1, 2, &out) && out == 42);
    CHECK(ms_size_sub(7, 7, &out) && out == 0);
    CHECK(!ms_size_sub(3, 4, &out) && out == 0);
}

static void test_spans(void) {
    const uint8_t text[] = {'a', 'b', 'c', 'd'};
    CHECK(MS_COUNT_OF(text) == 4);
    MsBytes all = ms_bytes_of(text, MS_COUNT_OF(text));

    uint8_t byte = 0;
    CHECK(ms_bytes_get(all, 3, &byte) && byte == 'd');
    CHECK(!ms_bytes_get(all, 4, &byte));

    MsBytes middle = {0};
    CHECK(ms_bytes_slice(all, 1, 3, &middle) && middle.len == 2 && middle.ptr[0] == 'b');
    CHECK(ms_bytes_slice(all, 4, 4, &middle) && middle.len == 0);
    CHECK(!ms_bytes_slice(all, 3, 2, &middle));
    CHECK(!ms_bytes_slice(all, 0, 5, &middle));

    MsBytes empty = ms_bytes_of(NULL, 0);
    CHECK(ms_bytes_slice(empty, 0, 0, &middle) && middle.len == 0);
    CHECK(!ms_bytes_get(empty, 0, &byte));

    uint8_t storage[3] = {0};
    MsBytesMut destination = ms_bytes_mut(storage, MS_COUNT_OF(storage));
    CHECK(!ms_bytes_copy(destination, all));
    CHECK(storage[0] == 0);
    CHECK(ms_bytes_slice(all, 0, 3, &middle) && ms_bytes_copy(destination, middle));
    CHECK(ms_bytes_equal(ms_bytes_view(destination), middle));
    CHECK(!ms_bytes_equal(ms_bytes_view(destination), all));

    /* Overlapping copy: shift "abc" one to the right inside the same storage. */
    uint8_t shifted[4] = {'a', 'b', 'c', 0};
    CHECK(ms_bytes_copy(ms_bytes_mut(shifted + 1, 3), ms_bytes_of(shifted, 3)));
    CHECK(shifted[1] == 'a' && shifted[2] == 'b' && shifted[3] == 'c');

    MsBytesMut tail = {0};
    CHECK(ms_bytes_mut_slice(destination, 2, 3, &tail) && tail.len == 1 && *tail.ptr == 'c');
    CHECK(!ms_bytes_mut_slice(destination, 2, 4, &tail));
}

int main(void) {
    test_sizes();
    test_spans();
    puts("safe ok");
    return 0;
}

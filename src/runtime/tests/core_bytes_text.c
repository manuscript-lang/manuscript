/* Unit test for src/runtime/core/bytes_text.c and num_text.c: decoding Bytes to text, the string builder, UInt64
 * division, number error messages and the precision forms of Float. `make c-test` builds it with ASan and UBSan. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ms_rt/alloc.h"
#include "ms_rt/bytes.h"
#include "ms_rt/num.h"
#include "ms_rt/string.h"
#include "support/rt_stubs.h"

static void check(bool ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "core_bytes_text.c:%d: %s\n", line, text);
        abort();
    }
}
#define CHECK(cond) check((cond), __LINE__, #cond)

static bool is(const MsStr *s, const char *t) {
    return ms_str_len(s) == strlen(t) && memcmp(ms_str_data(s), t, strlen(t)) == 0;
}

/* An owned Bytes of the text, with `spare` bytes of room past it. */
static MsList owned(const char *text, size_t spare) {
    const size_t n = strlen(text);
    uint8_t *data = msrt_alloc(n + spare + 1);
    memcpy(data, text, n);
    return (MsList){.ptr = data, .len = n, .cap = n + spare == 0 ? 1 : n + spare}; /* cap 0 would mean a view */
}

static void test_decode(void) {
    static const char *const valid[] = {"", "a", "ab", "fifteen-bytes!!", "sixteen-bytes!!!", "caf\xc3\xa9 and a long text with \xe2\x82\xac in it"};
    for (size_t i = 0; i < sizeof valid / sizeof *valid; i++) {
        for (size_t spare = 0; spare < 3; spare += 2) {
            MsList b = owned(valid[i], spare);
            MsStr s;
            CHECK(msrt_bytes_decode_utf8(&b, &s) == 1 && is(&s, valid[i]));
            msrt_string_free(&s);
            CHECK(msrt_bytes_decode_utf8_take(&b, &s) == 1 && is(&s, valid[i]) && b.ptr == NULL && b.len == 0);
            msrt_string_free(&s);
        }
    }
    /* A view borrows its bytes: taking it copies and leaves the storage alone. */
    const char *text = "a long borrowed view of bytes";
    MsList view = {.ptr = (uint8_t *)(uintptr_t)text, .len = strlen(text), .cap = 0};
    MsStr s;
    CHECK(msrt_bytes_decode_utf8_take(&view, &s) == 1 && is(&s, text));
    msrt_string_free(&s);
    /* Invalid UTF-8: absent, and the taken buffer is freed. */
    static const char *const invalid[] = {"\xff", "ab\xc3", "\xed\xa0\x80", "\xc0\xaf", "long enough to leave inline \xf0\x28\x8c\xbc"};
    for (size_t i = 0; i < sizeof invalid / sizeof *invalid; i++) {
        MsList b = owned(invalid[i], 0);
        CHECK(msrt_bytes_decode_utf8(&b, &s) == 0);
        CHECK(msrt_bytes_decode_utf8_take(&b, &s) == 0 && b.ptr == NULL);
    }
    /* A range decodes the part between the bounds. */
    MsList b = owned("ab\xc3\xa9yz", 0);
    CHECK(msrt_bytes_decode_utf8_range(&b, 0, 4, &s) == 1 && is(&s, "ab\xc3\xa9"));
    msrt_string_free(&s);
    CHECK(msrt_bytes_decode_utf8_range(&b, 3, 5, &s) == 0);
    CHECK(msrt_bytes_decode_utf8_range(&b, 4, 4, &s) == 1 && is(&s, ""));
    msrt_bytes_drop(&b);
}

/* Appends `piece` to the NUL-terminated text in `buffer`, which holds `capacity` bytes. */
static void add(char *buffer, size_t capacity, const char *piece) {
    const size_t used = strlen(buffer);
    CHECK(snprintf(buffer + used, capacity - used, "%s", piece) >= 0);
}

static void test_builder(void) {
    MsList b = {0};
    MsStr s;
    msrt_strbuilder_freeze(&b, &s);
    CHECK(is(&s, "") && b.ptr == NULL);
    /* Short text, then enough to grow past the inline size and the first allocation. */
    char expect[2048] = "";
    for (int i = 0; i < 40; i++) {
        char piece[32];
        snprintf(piece, sizeof piece, "[%d:%s]", i, i % 3 == 0 ? "x" : "\xc3\xa9\xc3\xa9");
        MsStr part;
        msrt_string_from_bytes((const uint8_t *)piece, strlen(piece), &part);
        msrt_strbuilder_append(&b, &part);
        msrt_string_free(&part);
        add(expect, sizeof expect, piece);
        msrt_strbuilder_append_int(&b, i * 1000003 - 7);
        char digits[24];
        snprintf(digits, sizeof digits, "%d", i * 1000003 - 7);
        add(expect, sizeof expect, digits);
    }
    msrt_strbuilder_append_int(&b, INT64_MIN);
    add(expect, sizeof expect, "-9223372036854775808");
    CHECK(b.len == strlen(expect));
    msrt_strbuilder_freeze(&b, &s);
    CHECK(is(&s, expect) && b.ptr == NULL && b.len == 0);
    msrt_string_free(&s);
    /* A short builder gives an inline string, and an ASCII long one is flagged ASCII. */
    MsStr one;
    msrt_string_from_bytes((const uint8_t *)"hi", 2, &one);
    msrt_strbuilder_append(&b, &one);
    msrt_strbuilder_append_slow(&b, &one);
    msrt_strbuilder_freeze(&b, &s);
    CHECK(is(&s, "hihi"));
    msrt_string_free(&s);
    msrt_string_free(&one);
    MsStr ascii;
    msrt_string_from_bytes((const uint8_t *)"an ASCII string longer than fifteen bytes", 41, &ascii);
    msrt_strbuilder_append(&b, &ascii);
    msrt_strbuilder_freeze(&b, &s);
    CHECK(is(&s, "an ASCII string longer than fifteen bytes") && (s.tagged & MS_STR_ASCII) != 0);
    msrt_string_free(&s);
    msrt_string_free(&ascii);
}

static void test_numbers(void) {
    const int64_t big = -1; /* UInt64 max as a bit pattern */
    CHECK((uint64_t)msrt_uint_div(big, 2) == UINT64_MAX / 2 && msrt_uint_rem(big, 10) == 5);
    CHECK(msrt_uint_div(7, 2) == 3 && msrt_uint_rem(7, 2) == 1);
    MsStr s;
    msrt_numbers_error_message(MS_STATUS_INVALID_INPUT, &s);
    CHECK(is(&s, "number: invalid input"));
    msrt_string_free(&s);
    msrt_numbers_error_message(MS_STATUS_INVALID_DATA, &s);
    CHECK(is(&s, "number: invalid data"));
    msrt_string_free(&s);
    msrt_numbers_error_message(MS_STATUS_OUT_OF_RANGE, &s);
    CHECK(is(&s, "number: value out of range"));
    msrt_string_free(&s);
    msrt_numbers_error_message(MS_STATUS_FAILED, &s);
    CHECK(is(&s, "number: operation failed"));
    msrt_string_free(&s);
    msrt_float_to_fixed(1.005, 2, &s);
    CHECK(is(&s, "1.00"));
    msrt_string_free(&s);
    msrt_float_to_fixed(3.14158, 2, &s);
    CHECK(is(&s, "3.14"));
    msrt_string_free(&s);
    msrt_float_to_exponential(1234.5678, 2, &s);
    CHECK(is(&s, "1.23e+3"));
    msrt_string_free(&s);
    msrt_float_to_precision(1234.5678, 6, &s);
    CHECK(is(&s, "1234.57"));
    msrt_string_free(&s);
    msrt_float_to_precision(1e10, 3, &s);
    CHECK(is(&s, "1.00e+10"));
    msrt_string_free(&s);
}

int main(void) {
    test_decode();
    test_builder();
    test_numbers();
    puts("core_bytes_text: ok");
    return 0;
}

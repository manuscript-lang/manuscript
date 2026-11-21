/* Unit test for src/runtime/core/string_join.c and string_fmt.c: f-string joins, in-place appends and `to_string`. */
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms_rt/alloc.h"
#include "ms_rt/string.h"
#include "rt_calls.h"
#include "rt_stubs.h"

static void check(bool ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "core_string_join.c:%d: %s\n", line, text);
        abort();
    }
}
#define CHECK(cond) check((cond), __LINE__, #cond)

/* An inline string of up to 15 bytes: the bytes in the value's own two words, length in bits 56..59. */
static MsStr inl(const char *text) {
    size_t n = strlen(text);
    uint8_t raw[16] = {0};
    memcpy(raw, text, n);
    MsStr s;
    memcpy(&s.ptr_word, raw, 8);
    uint64_t hi = 0;
    memcpy(&hi, raw + 8, 8);
    s.tagged = hi | (UINT64_C(1) << 62) | ((uint64_t)n << MS_STR_INLINE_SHIFT);
    return s;
}

/* A string in a heap block of the allocator, as a join result or an appended string is. */
static MsStr heap(const char *text, bool ascii) {
    size_t n = strlen(text);
    uint8_t *bytes = msrt_alloc(n + 1);
    memcpy(bytes, text, n + 1);
    return (MsStr){.ptr_word = bytes, .tagged = n | (ascii ? MS_STR_ASCII : 0)};
}

static size_t address(const MsStr *s) {
    size_t word;
    memcpy(&word, &s, sizeof word);
    return word;
}

static bool is_text(const MsStr *s, const char *text) {
    size_t n = strlen(text);
    return ms_str_len(s) == n && memcmp(ms_str_data(s), text, n) == 0;
}

static void free_owned(const MsStr *s) {
    if (s->tagged < (UINT64_C(1) << 62)) {
        msrt_free(s->ptr_word);
    }
}

static void test_join(void) {
    MsStr name = inl("n");
    MsStr out;
    /* Part 1 is an Int (bit 1): "n=" then 42. */
    MsStr eq = inl("=");
    msrt_string_fmt3(0b010, address(&name), (size_t)42, address(&eq), &out);
    CHECK(is_text(&out, "n42="));
    CHECK(ms_str_is_inline(&out));
    MsStr long_part = heap("a fairly long piece of text", true);
    msrt_string_fmt2(0b10, address(&long_part), (size_t)-7, &out);
    CHECK(is_text(&out, "a fairly long piece of text-7"));
    CHECK(!ms_str_is_inline(&out));
    CHECK(out.ptr_word[ms_str_len(&out)] == 0);
    free_owned(&out);
    /* Six parts, all Int: INT64_MIN has the longest digits. */
    msrt_string_fmt6(0b111111, (size_t)1, (size_t)-1, (size_t)0, (size_t)INT64_MIN, (size_t)10, (size_t)99, &out);
    CHECK(is_text(&out, "1-10-922337203685477580810" "99"));
    free_owned(&out);
    free_owned(&long_part);
}

static void test_append(void) {
    MsStr eq = inl("=");
    /* Bit 0 of the mask is the appended string, so the first part is bit 1. An owned string grows in place and stays flagged ASCII. */
    MsStr acc = heap("a string that is longer than inline", true);
    MsStr out;
    msrt_string_append_fmt2(&acc, 0b100, address(&eq), (size_t)5, &out);
    CHECK(is_text(&out, "a string that is longer than inline=5"));
    CHECK((out.tagged & MS_STR_ASCII) != 0);
    CHECK(out.ptr_word[ms_str_len(&out)] == 0);
    /* A part that is not ASCII drops the flag. */
    MsStr accent = inl("\xc3\xa9");
    MsStr second;
    msrt_string_append_fmt1(&out, 0b0, address(&accent), &second);
    CHECK(is_text(&second, "a string that is longer than inline=5\xc3\xa9"));
    CHECK((second.tagged & MS_STR_ASCII) == 0);
    /* An inline string joins into a new one, here still inline. */
    MsStr small = inl("ab");
    MsStr third;
    msrt_string_append_fmt2(&small, 0b100, address(&eq), (size_t)12, &third);
    CHECK(is_text(&third, "ab=12"));
    CHECK(ms_str_is_inline(&third));
    /* A part that views the appended string's own bytes is read before they move. */
    MsStr loop = heap("repeat-me-repeat-me", true);
    MsStr view = {.ptr_word = loop.ptr_word, .tagged = 6 | (UINT64_C(3) << 62)};
    MsStr fourth;
    msrt_string_append_fmt1(&loop, 0b0, address(&view), &fourth);
    CHECK(is_text(&fourth, "repeat-me-repeat-merepeat"));
    free_owned(&second);
    free_owned(&fourth);
}

/* Checks the text of a stub string, which owns a malloc copy, and frees it. */
static void expect(MsStr *s, const char *text) {
    CHECK(is_text(s, text));
    msrt_string_free(s);
}

static void test_to_string(void) {
    MsStr out;
    msrt_int_to_string(INT64_MIN, &out);
    expect(&out, "-9223372036854775808");
    msrt_uint_to_string(-1, &out);
    expect(&out, "18446744073709551615");
    msrt_int_to_string_radix(-255, 16, &out);
    expect(&out, "-ff");
    msrt_int_to_string_radix(INT64_MIN, 2, &out);
    CHECK(ms_str_len(&out) == 65);
    msrt_string_free(&out);
    msrt_uint_to_string_radix(-1, 36, &out);
    expect(&out, "3w5e11264sgsf");
    msrt_float_to_string(0.1, &out);
    expect(&out, "0.1");
    msrt_float32_to_string((double)0.1f, &out);
    expect(&out, "0.1");
    msrt_bool_to_string(1, &out);
    expect(&out, "true");
    msrt_bool_to_string(0, &out);
    expect(&out, "false");
    /* A radix outside 2..=36 faults with the radix in the message. */
    jmp_buf jump;
    ms_test_fault = &jump;
    if (setjmp(jump) == 0) {
        msrt_int_to_string_radix(1, 37, &out);
        CHECK(false);
    }
    ms_test_fault = NULL;
    CHECK(strcmp(ms_test_fault_message, "to_string_radix: radix must be between 2 and 36, found 37") == 0);
}

int main(void) {
    test_join();
    test_append();
    test_to_string();
    puts("core_string_join: ok");
    return 0;
}

/* Unit test for src/runtime/core/string_scan.c and ms_rfind: index_any, trim_chars and last_index_of over ASCII,
 * multi-byte and malformed texts. `make c-test` builds it with ASan and UBSan. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ms_rt/alloc.h"
#include "ms_rt/search.h"
#include "ms_rt/string.h"
#include "support/rt_stubs.h"

static void check(bool ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "core_string_scan.c:%d: %s\n", line, text);
        abort();
    }
}
#define CHECK(cond) check((cond), __LINE__, #cond)

static MsStr make(const char *text) {
    MsStr s;
    msrt_string_from_bytes((const uint8_t *)text, strlen(text), &s);
    return s;
}

static bool is(const MsStr *s, const char *text) {
    return ms_str_len(s) == strlen(text) && memcmp(ms_str_data(s), text, strlen(text)) == 0;
}

/* The offset of the first scalar of `text` in `set`, or -1. */
static int64_t index_any(const char *text, const char *set) {
    MsStr t = make(text);
    MsStr m = make(set);
    int64_t at = -1;
    if (msrt_string_index_any(&t, &m, &at) == 0) {
        at = -1;
    }
    msrt_string_free(&t);
    msrt_string_free(&m);
    return at;
}

static int64_t last_index_of(const char *text, const char *needle) {
    MsStr t = make(text);
    MsStr n = make(needle);
    int64_t at = -1;
    if (msrt_string_last_index_of(&t, &n, &at) == 0) {
        at = -1;
    }
    msrt_string_free(&t);
    msrt_string_free(&n);
    return at;
}

/* The text after trim_chars with the given sides, compared with `want`. */
static bool trimmed_is(const char *text, const char *set, bool start, bool end, const char *want) {
    MsStr t = make(text);
    MsStr m = make(set);
    MsStr out;
    msrt_string_trim_chars(&t, &m, start, end, &out);
    const bool same = is(&out, want);
    msrt_string_free(&out);
    msrt_string_free(&t);
    msrt_string_free(&m);
    return same;
}

static void test_index_any(void) {
    CHECK(index_any("hello, world", ",!") == 5);
    CHECK(index_any("hello", ",!") == -1);
    CHECK(index_any("", ",!") == -1);
    CHECK(index_any("abc", "") == -1);
    CHECK(index_any("a\x01z", "\x01") == 1);
    CHECK(index_any("x\x7f", "\x7f") == 1);
    /* Members at both mask boundaries: 63 and 64. */
    CHECK(index_any("a?@", "@") == 2);
    CHECK(index_any("a?@", "?") == 1);
    /* A multi-byte member, found at its byte offset; ASCII members still match beside it. */
    CHECK(index_any("ab\xc3\xa9z", "\xc3\xa9") == 2);
    CHECK(index_any("ab\xc3\xa9z", "z\xc3\xa9") == 2);
    CHECK(index_any("abz", "\xc3\xa9z") == 2);
    CHECK(index_any("a\xf0\x9f\x99\x82z", "\xf0\x9f\x99\x82") == 1);
    /* A stray byte reads as U+FFFD in text and set alike. */
    CHECK(index_any("a\xffz", "\xff") == 1);
    CHECK(index_any("a\xffz", "\xef\xbf\xbd") == 1);
    CHECK(index_any("a\xc3z", "q") == -1);
    /* Long ASCII text, a hit in the last byte. */
    char long_text[1000];
    memset(long_text, 'a', sizeof long_text - 1);
    long_text[sizeof long_text - 1] = '\0';
    long_text[sizeof long_text - 2] = ';';
    CHECK(index_any(long_text, ";,.") == (int64_t)sizeof long_text - 2);
}

static void test_trim_chars(void) {
    CHECK(trimmed_is("--ab--", "-", true, true, "ab"));
    CHECK(trimmed_is("--ab--", "-", true, false, "ab--"));
    CHECK(trimmed_is("--ab--", "-", false, true, "--ab"));
    CHECK(trimmed_is("----", "-", true, true, ""));
    CHECK(trimmed_is("----", "-", false, true, ""));
    CHECK(trimmed_is("", "-", true, true, ""));
    CHECK(trimmed_is("abc", "", true, true, "abc"));
    CHECK(trimmed_is("xyabcyx", "xy", true, true, "abc"));
    /* Multi-byte members at either end; the middle is kept. */
    CHECK(trimmed_is("\xc3\xa9\xc3\xa9" "a\xc3\xa9" "b\xc3\xa9", "\xc3\xa9", true, true, "a\xc3\xa9" "b"));
    CHECK(trimmed_is("\xf0\x9f\x99\x82_hi_\xf0\x9f\x99\x82", "_\xf0\x9f\x99\x82", true, true, "hi"));
    /* A multi-byte set member never matches half of another scalar. */
    CHECK(trimmed_is("\xc3\xa9", "\xc3\xa8", true, true, "\xc3\xa9"));
    /* A stray trailing byte is U+FFFD. */
    CHECK(trimmed_is("ab\xff", "\xff", false, true, "ab"));
    CHECK(trimmed_is("ab\xff", "b", false, true, "ab\xff"));
}

/* scalar_at with a default of -1: the scalar that starts at `offset`, or -1. */
static int64_t scalar_at(const char *text, int64_t offset) {
    MsStr t = make(text);
    const int64_t scalar = msrt_string_scalar_at(&t, offset, 1, -1);
    msrt_string_free(&t);
    return scalar;
}

static void test_scalar_at(void) {
    CHECK(scalar_at("h\xc3\xa9llo", 0) == 'h');
    CHECK(scalar_at("h\xc3\xa9llo", 1) == 0xE9);
    CHECK(scalar_at("h\xc3\xa9llo", 2) == -1); /* inside a scalar */
    CHECK(scalar_at("h\xc3\xa9llo", 3) == 'l');
    CHECK(scalar_at("h\xc3\xa9llo", 6) == -1); /* the end */
    CHECK(scalar_at("h\xc3\xa9llo", -1) == -1);
    CHECK(scalar_at("\xf0\x9f\x99\x82", 0) == 0x1F642);
    CHECK(scalar_at("\xf0\x9f\x99\x82", 1) == -1);
    CHECK(scalar_at("\xf0\x9f\x99\x82", 3) == -1);
    CHECK(scalar_at("a\xffz", 1) == 0xFFFD); /* a stray byte starts a scalar and reads as U+FFFD */
    CHECK(scalar_at("", 0) == -1);
    MsStr t = make("abc");
    CHECK(msrt_string_scalar_at(&t, 1, 0, 0) == 'b');
    CHECK(msrt_string_scalar_at(&t, 9, 1, 77) == 77);
    msrt_string_free(&t);
}

static void test_last_index_of(void) {
    CHECK(last_index_of("abcabc", "bc") == 4);
    CHECK(last_index_of("abcabc", "abc") == 3);
    CHECK(last_index_of("abcabc", "d") == -1);
    CHECK(last_index_of("abc", "abcd") == -1);
    CHECK(last_index_of("abc", "") == 3);
    CHECK(last_index_of("", "") == 0);
    CHECK(last_index_of("aaaa", "aa") == 2);
    CHECK(last_index_of("h\xc3\xa9llo h\xc3\xa9llo", "h\xc3\xa9") == 7);
    CHECK(last_index_of("a", "a") == 0);
}

int main(void) {
    test_index_any();
    test_trim_chars();
    test_last_index_of();
    test_scalar_at();
    puts("core_string_scan ok");
    return 0;
}

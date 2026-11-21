/* Unit test for src/runtime/core/string_case.c and string_normalize.c: upper and lower (ASCII, full mappings, final sigma,
 * in-place _take) and the four normalization forms (quick check, reordering, composition, Hangul, long mark runs,
 * limits). Expected texts come from the Unicode normalization conformance data and the standard library's case
 * mappings. `make c-test` builds it with ASan and UBSan. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ms_rt/alloc.h"
#include "ms_rt/string.h"
#include "support/rt_stubs.h"

static void check(bool ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "core_unicode.c:%d: %s\n", line, text);
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

/* The result of a mapping of `text`, compared with `want`. */
static bool upper_is(const char *text, const char *want) {
    MsStr s = make(text), r;
    msrt_string_upper(&s, &r);
    const bool same = is(&r, want);
    msrt_string_free(&r);
    msrt_string_free(&s);
    return same;
}

static bool lower_is(const char *text, const char *want) {
    MsStr s = make(text), r;
    msrt_string_lower(&s, &r);
    const bool same = is(&r, want);
    msrt_string_free(&r);
    msrt_string_free(&s);
    return same;
}

static bool normalize_is(const char *text, int64_t kind, const char *want) {
    MsStr s = make(text), r;
    CHECK(msrt_string_normalize_kind(&s, kind, 0, 0, &r) == MS_STATUS_OK);
    const bool same = is(&r, want);
    msrt_string_free(&r);
    msrt_string_free(&s);
    return same;
}

static void test_case(void) {
    CHECK(upper_is("hello, World 123", "HELLO, WORLD 123"));
    CHECK(lower_is("HELLO, World 123", "hello, world 123"));
    CHECK(upper_is("a", "A"));
    CHECK(lower_is("already lower case text over sixteen bytes", "already lower case text over sixteen bytes"));
    CHECK(upper_is("straße", "STRASSE"));
    CHECK(upper_is("ŉ ǰ ΐ ﬃ", "\u02BCN J\u030C \u0399\u0308\u0301 FFI"));
    CHECK(upper_is("ᾷ", "\u0391\u0342\u0399"));
    CHECK(lower_is("İ", "i\xCC\x87"));
    CHECK(upper_is("éa\xE1\xBA\x9E", "ÉA\xE1\xBA\x9E"));
    CHECK(lower_is("\xE2\x84\xA6 \xE2\x84\xAA", "ω k")); /* Ohm sign and Kelvin sign */
    CHECK(upper_is("ıſ", "IS"));
    /* Final sigma: a cased letter before it and none after, case-ignorable scalars aside. */
    CHECK(lower_is("ΟΔΟΣ", "οδος"));
    CHECK(lower_is("ΟΔΟΣ ΑΣ", "οδος ας"));
    CHECK(lower_is("Σ", "σ"));
    CHECK(lower_is("ΑΣΑ", "ασα"));
    CHECK(lower_is("A\u2060Σ", "a\u2060ς"));
    CHECK(lower_is("AΣ\u2060A", "aσ\u2060a"));
    CHECK(lower_is("A.Σ", "a.ς"));
    CHECK(lower_is("A.ΣB", "a.σb"));
}

static void test_case_take(void) {
    MsStr big = make("a long ascii string, over fifteen bytes");
    MsStr r;
    msrt_string_upper_take(&big, &r);
    CHECK(is(&r, "A LONG ASCII STRING, OVER FIFTEEN BYTES"));
    msrt_string_free(&r);
    MsStr mixed = make("a long string with ß and Σ in it, over fifteen");
    msrt_string_upper_take(&mixed, &r);
    CHECK(is(&r, "A LONG STRING WITH SS AND Σ IN IT, OVER FIFTEEN"));
    msrt_string_free(&r);
    MsStr again = make("A LONG STRING WITH SS AND Σ IN IT, OVER FIFTEEN");
    msrt_string_lower_take(&again, &r);
    CHECK(is(&r, "a long string with ss and σ in it, over fifteen"));
    msrt_string_free(&r);
}

static void test_normalize(void) {
    /* From NormalizationTest.txt (Part 0 and 1). */
    CHECK(normalize_is("\xE1\xB8\x8A\xCC\xA3", 0, "\xE1\xB8\x8C\xCC\x87")); /* Ḍ̇ composes with the dot below first */
    CHECK(normalize_is("\xE1\xB8\x8A\xCC\xA3", 1, "D\xCC\xA3\xCC\x87"));
    CHECK(normalize_is("D\xCC\x87\xCC\xA3", 0, "\xE1\xB8\x8C\xCC\x87"));
    CHECK(normalize_is("\xEF\xAC\x81", 0, "\xEF\xAC\x81")); /* ﬁ ligature is stable under canonical forms */
    CHECK(normalize_is("\xEF\xAC\x81", 2, "fi"));
    CHECK(normalize_is("\xEF\xAC\x81", 3, "fi"));
    CHECK(normalize_is("\xE2\x84\xAB", 0, "\xC3\x85")); /* Angstrom sign is a singleton */
    CHECK(normalize_is("\xE2\x84\xAB", 1, "A\xCC\x8A"));
    CHECK(normalize_is("\xEF\xB7\xBA", 3, /* U+FDFA: eighteen scalars */
                       "\xD8\xB5\xD9\x84\xD9\x89 \xD8\xA7\xD9\x84\xD9\x84\xD9\x87 \xD8\xB9\xD9\x84\xD9\x8A\xD9\x87 "
                       "\xD9\x88\xD8\xB3\xD9\x84\xD9\x85"));
    CHECK(normalize_is("e\xCC\x81", 0, "\xC3\xA9"));
    CHECK(normalize_is("\xC3\xA9", 1, "e\xCC\x81"));
    CHECK(normalize_is("a\xCC\x81\xCC\xA3", 1, "a\xCC\xA3\xCC\x81")); /* marks reorder by class */
    CHECK(normalize_is("\xC4\x85\xCC\x81", 0, "\xC4\x85\xCC\x81"));
    /* Hangul. */
    CHECK(normalize_is("\xE1\x84\x80\xE1\x85\xA1\xE1\x86\xA8", 0, "\xEA\xB0\x81")); /* ᄀ ᅡ ᆨ composes to 각 */
    CHECK(normalize_is("\xEA\xB0\x81", 1, "\xE1\x84\x80\xE1\x85\xA1\xE1\x86\xA8"));
    CHECK(normalize_is("\xEA\xB0\x80", 1, "\xE1\x84\x80\xE1\x85\xA1"));
    CHECK(normalize_is("\xEA\xB0\x80\xE1\x86\xA8", 0, "\xEA\xB0\x81")); /* LV and T */
    /* Marks after ASCII in the middle of ASCII text. */
    CHECK(normalize_is("abc e\xCC\x81 def", 0, "abc \xC3\xA9 def"));
    CHECK(normalize_is("abc \xC3\xA9 def", 1, "abc e\xCC\x81 def"));
    CHECK(normalize_is("<\xCC\xB8", 0, "\xE2\x89\xAE")); /* a composite of an ASCII starter */
}

static void test_long_mark_run(void) {
    /* A run past the insertion sort limit puts 150 marks of two classes in order: 230 (U+0301) and 220 (U+0323). */
    char text[1024] = "a";
    char want[1024] = "a";
    size_t at = 1;
    for (int i = 0; i < 75; i++) {
        memcpy(text + at, "\xCC\x81\xCC\xA3", 4);
        at += 4;
    }
    text[at] = 0;
    size_t put = 1;
    for (int i = 0; i < 75; i++) {
        memcpy(want + put, "\xCC\xA3", 2);
        put += 2;
    }
    for (int i = 0; i < 75; i++) {
        memcpy(want + put, "\xCC\x81", 2);
        put += 2;
    }
    want[put] = 0;
    CHECK(normalize_is(text, 1, want));
}

static void test_status(void) {
    MsStr s = make("e\xCC\x81 and more text after it");
    MsStr r;
    MsStr form = make("NFC");
    CHECK(msrt_string_normalize(&s, &form, 0, 0, &r) == MS_STATUS_OK);
    CHECK(is(&r, "\xC3\xA9 and more text after it"));
    msrt_string_free(&r);
    CHECK(msrt_string_normalize(&s, &form, 1, 3, &r) == MS_STATUS_LIMIT_EXCEEDED);
    CHECK(msrt_string_normalize(&s, &form, 1, 100, &r) == MS_STATUS_OK);
    msrt_string_free(&r);
    CHECK(msrt_string_normalize(&s, &form, 1, -1, &r) == MS_STATUS_INVALID_INPUT);
    MsStr nfd = make("NFD");
    CHECK(msrt_string_normalize(&s, &nfd, 1, 25, &r) == MS_STATUS_LIMIT_EXCEEDED); /* three bytes more than 25 */
    MsStr bad = make("nfc");
    CHECK(msrt_string_normalize(&s, &bad, 0, 0, &r) == MS_STATUS_INVALID_INPUT);
    MsStr ascii = make("plain ASCII text, over fifteen");
    CHECK(msrt_string_normalize(&ascii, &form, 1, 5, &r) == MS_STATUS_LIMIT_EXCEEDED);
    CHECK(msrt_string_normalize(&ascii, &form, 0, 0, &r) == MS_STATUS_OK);
    msrt_string_free(&r);
    msrt_string_free(&ascii);
    msrt_string_free(&bad);
    msrt_string_free(&nfd);
    msrt_string_free(&form);
    msrt_string_free(&s);
}

int main(void) {
    test_case();
    test_case_take();
    test_normalize();
    test_long_mark_run();
    test_status();
    return 0;
}

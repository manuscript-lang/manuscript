/* The @std/unicode natives (src/runtime/std/unicode.c): scalar properties and UTF-8 validation. */
#include <stdio.h>
#include <string.h>

#include "ms_rt/unicode.h"
#include "fake_rt.h"

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

static void test_properties(void) {
    CHECK(msstd_unicode_is_alphabetic('a') && msstd_unicode_is_alphabetic(0xE9) && msstd_unicode_is_alphabetic(0x4E2D));
    CHECK(!msstd_unicode_is_alphabetic('1') && !msstd_unicode_is_alphabetic(' ') && !msstd_unicode_is_alphabetic(0x1F642));
    CHECK(msstd_unicode_is_numeric('5') && msstd_unicode_is_numeric(0x0663) && msstd_unicode_is_numeric(0xBD) &&
          msstd_unicode_is_numeric(0x2163));
    CHECK(!msstd_unicode_is_numeric('a') && !msstd_unicode_is_numeric(0x4E2D));
    CHECK(msstd_unicode_is_alphanumeric('a') && msstd_unicode_is_alphanumeric('7') && msstd_unicode_is_alphanumeric(0x0663));
    CHECK(!msstd_unicode_is_alphanumeric('-') && !msstd_unicode_is_alphanumeric(0x2003));
    CHECK(msstd_unicode_is_lowercase('a') && msstd_unicode_is_lowercase(0xDF) && !msstd_unicode_is_lowercase('A'));
    CHECK(msstd_unicode_is_uppercase('A') && msstd_unicode_is_uppercase(0xC9) && !msstd_unicode_is_uppercase('a'));
    CHECK(!msstd_unicode_is_lowercase('1') && !msstd_unicode_is_uppercase('1'));
    for (int64_t space = 9; space <= 13; space++) CHECK(msstd_unicode_is_whitespace(space));
    CHECK(msstd_unicode_is_whitespace(' ') && msstd_unicode_is_whitespace(0x85) && msstd_unicode_is_whitespace(0xA0) &&
          msstd_unicode_is_whitespace(0x2003) && msstd_unicode_is_whitespace(0x3000));
    CHECK(!msstd_unicode_is_whitespace(0x200B) && !msstd_unicode_is_whitespace('a') && !msstd_unicode_is_whitespace(0x1C));
    CHECK(msstd_unicode_is_control(0) && msstd_unicode_is_control(0x1F) && msstd_unicode_is_control(0x7F) &&
          msstd_unicode_is_control(0x85) && msstd_unicode_is_control(0x9F));
    CHECK(!msstd_unicode_is_control(' ') && !msstd_unicode_is_control(0xA0) && !msstd_unicode_is_control('a'));
    CHECK(msstd_unicode_is_ascii(0) && msstd_unicode_is_ascii(127) && !msstd_unicode_is_ascii(128));
}

static void test_non_scalars(void) {
    const int64_t values[] = {-1, INT64_MIN, 0xD800, 0xDFFF, 0x110000, INT64_MAX};
    for (size_t i = 0; i < sizeof values / sizeof values[0]; i++) {
        const int64_t v = values[i];
        CHECK(!msstd_unicode_is_alphabetic(v) && !msstd_unicode_is_alphanumeric(v) && !msstd_unicode_is_numeric(v));
        CHECK(!msstd_unicode_is_lowercase(v) && !msstd_unicode_is_uppercase(v) && !msstd_unicode_is_whitespace(v));
        CHECK(!msstd_unicode_is_control(v) && !msstd_unicode_is_ascii(v));
    }
}

static bool valid(const char *text, size_t length) {
    char copy[16];
    memcpy(copy, text, length);
    const MsVec v = {copy, length, length};
    return msstd_utf8_is_valid(&v);
}

static void test_utf8(void) {
    CHECK(valid("", 0) && valid("abc", 3) && valid("\xc3\xa9", 2) && valid("\xe4\xb8\xad", 3) && valid("\xf0\x9f\x99\x82", 4));
    CHECK(!valid("\xff", 1) && !valid("\xc3", 1) && !valid("\xc0\x80", 2) && !valid("\xed\xa0\x80", 3) &&
          !valid("\xf4\x90\x80\x80", 4) && !valid("\x80", 1));
}

/* The columns of `text` (a literal), or -1 when the native refuses it. */
static int64_t columns(const char *text) {
    const MsStr view = {.bytes = (const uint8_t *)text, .tagged = (UINT64_C(3) << 62) | strlen(text)};
    int64_t width = 0;
    return msstd_unicode_display_width(&view, &width) == 0 ? width : -1;
}

static void test_display_width(void) {
    CHECK(columns("") == 0 && columns("abc") == 3 && columns("a b") == 3);
    CHECK(columns("e\xcc\x81") == 1);                       /* e + combining acute */
    CHECK(columns("\xe7\x95\x8c") == 2);                   /* 界 */
    CHECK(columns("\xe7\x95\x8c\xe7\x95\x8c") == 4);
    CHECK(columns("\xc2\xb7") == 1);                      /* · is ambiguous, narrow */
    CHECK(columns("\xf0\x9f\x91\xa9\xe2\x80\x8d\xf0\x9f\x92\xbb") == 2); /* woman technologist */
    CHECK(columns("\xf0\x9f\x87\xba\xf0\x9f\x87\xb8") == 2); /* the US flag */
    CHECK(columns("\xf0\x9f\x87\xba\xf0\x9f\x87\xb8\xf0\x9f\x87\xa8") == 3); /* flag, then a lone indicator */
    CHECK(columns("1\xef\xb8\x8f\xe2\x83\xa3") == 2);    /* keycap 1 */
    CHECK(columns("\xe2\x9d\xa4\xef\xb8\x8f") == 2);      /* red heart with VS16 */
    CHECK(columns("\xe2\x9d\xa4") == 1);                   /* red heart, text presentation */
    CHECK(columns("\xe1\x84\x80\xe1\x85\xa1") == 2);    /* Hangul jamo syllable */
    CHECK(columns("\xcc\x81") == 0);                      /* a lone combining mark */
    CHECK(columns("\t") == -1 && columns("a\n") == -1 && columns("\x1b[31m") == -1 && columns("\x7f") == -1);
    CHECK(columns("\xc2\x85") == -1 && columns("\xe2\x80\xa8") == -1 && columns("\xe2\x80\xa9") == -1);
}

int main(void) {
    test_display_width();
    test_properties();
    test_non_scalars();
    test_utf8();
    puts(failures == 0 ? "std_unicode: ok" : "std_unicode: FAILED");
    return failures == 0 ? 0 : 1;
}

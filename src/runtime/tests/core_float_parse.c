/* Unit test for src/runtime/core/float_parse.c and src/runtime/sys/strtod.c: the syntax, the exact fast path, the
 * strtod path, overflow and underflow, and the named values. `make c-test` builds it with ASan and UBSan. */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ms_rt/num.h"
#include "ms_rt/string.h"

static void check(bool ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "core_float_parse.c:%d: %s\n", line, text);
        abort();
    }
}
#define CHECK(cond) check((cond), __LINE__, #cond)
/* INFINITY is a float macro; the runtime's Float is a double. */
#define INFINITY_D ((double)INFINITY)

/* The status of parsing `text`; `*value` is set on success. */
static uint8_t parse(const char *text, double *value) {
    MsStr s;
    msrt_string_from_bytes((const uint8_t *)text, strlen(text), &s);
    const uint8_t status = msrt_numbers_parse_float(&s, value);
    msrt_string_free(&s);
    return status;
}

/* The text parses to exactly `want` (same bits, so -0.0 differs from 0.0). */
static bool parses_to(const char *text, double want) {
    double got = 0;
    return parse(text, &got) == MS_STATUS_OK && memcmp(&got, &want, sizeof got) == 0;
}

static bool is_invalid(const char *text) {
    double got = 0;
    return parse(text, &got) == MS_STATUS_INVALID_DATA;
}

static void test_fast_path(void) {
    CHECK(parses_to("0", 0.0));
    CHECK(parses_to("-0", -0.0));
    CHECK(parses_to("-0.0", -0.0));
    CHECK(parses_to("1", 1.0));
    CHECK(parses_to("+1.5", 1.5));
    CHECK(parses_to("0.1", 0.1));
    CHECK(parses_to("123.456", 123.456));
    CHECK(parses_to("2.5e1", 25.0));
    CHECK(parses_to("2.5E+1", 25.0));
    CHECK(parses_to("1.5e3", 1500.0));
    CHECK(parses_to("1e22", 1e22));
    CHECK(parses_to("5e-22", 5e-22));
    CHECK(parses_to("9007199254740992", 9007199254740992.0));
    CHECK(parses_to("00000000000000000000001", 1.0)); /* more than 19 digits: the library path */
}

static void test_library_path(void) {
    CHECK(parses_to("9007199254740993", 9007199254740992.0)); /* 2^53 + 1 rounds to even */
    CHECK(parses_to("1e23", 1e23));
    CHECK(parses_to("5e-23", 5e-23));
    CHECK(parses_to("123456789012345678901", 123456789012345678901.0));
    CHECK(parses_to("2.2250738585072011e-308", 2.2250738585072011e-308));
    CHECK(parses_to("4.9e-324", 4.9e-324));
    CHECK(parses_to("1.7976931348623157e308", 1.7976931348623157e308));
    CHECK(parses_to("-1.7976931348623157e308", -1.7976931348623157e308));
    CHECK(parses_to("1e-400", 0.0));
    CHECK(parses_to("-1e-400", -0.0));
    /* A literal longer than the library's stack buffer. */
    char long_text[400];
    memset(long_text, '9', sizeof long_text - 1);
    long_text[0] = '1';
    long_text[sizeof long_text - 1] = '\0';
    double value = 0;
    CHECK(parse(long_text, &value) == MS_STATUS_OUT_OF_RANGE);
    memset(long_text, '0', sizeof long_text - 1);
    long_text[0] = '1';
    long_text[1] = '.';
    long_text[sizeof long_text - 2] = '5';
    CHECK(parses_to(long_text, 1.0));
}

static void test_range(void) {
    double value = 7;
    CHECK(parse("1e400", &value) == MS_STATUS_OUT_OF_RANGE && value == 7);
    CHECK(parse("-1e400", &value) == MS_STATUS_OUT_OF_RANGE);
    CHECK(parse("1e99999999999999999999", &value) == MS_STATUS_OUT_OF_RANGE);
    CHECK(parses_to("1e-99999999999999999999", 0.0));
}

static void test_named(void) {
    double value = 0;
    CHECK(parse("NaN", &value) == MS_STATUS_OK && isnan(value));
    CHECK(parses_to("Infinity", INFINITY_D));
    CHECK(parses_to("+Infinity", INFINITY_D));
    CHECK(parses_to("-Infinity", -INFINITY_D));
    CHECK(is_invalid("+NaN") && is_invalid("-NaN") && is_invalid("nan") && is_invalid("inf") && is_invalid("infinity"));
}

static void test_syntax(void) {
    const char *const bad[] = {"",    "+",   "-",   ".5",  "5.",  "1e",   "1e+",   "e5",  "1.5x", " 1",
                               "1 ",  "0x10", "1_0", "--1", "1..2", "1e5.5", "1e+-5", "1,5", "\xc3\xa9"};
    for (size_t i = 0; i < sizeof bad / sizeof bad[0]; i++) {
        CHECK(is_invalid(bad[i]));
    }
}

static void test_string_form(void) {
    MsStr s;
    msrt_string_from_bytes((const uint8_t *)"2.5", 3, &s);
    double value = 0;
    CHECK(msrt_string_parse_float(&s, &value) == 1 && value == 2.5);
    msrt_string_free(&s);
    msrt_string_from_bytes((const uint8_t *)"2.5x", 4, &s);
    CHECK(msrt_string_parse_float(&s, &value) == 0);
    msrt_string_free(&s);
}

int main(void) {
    test_fast_path();
    test_library_path();
    test_range();
    test_named();
    test_syntax();
    test_string_form();
    puts("core_float_parse ok");
    return 0;
}

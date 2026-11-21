/* Unit test for src/runtime/core/num.c; `make c-test` builds it with ASan and UBSan. */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ms_rt/num.h"
#include "ms_rt/string.h"

static void check(bool ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "core_num.c:%d: %s\n", line, text);
        abort();
    }
}
/* NAN and INFINITY are float macros; the runtime's Float is a double. */
#define NAN_D ((double)NAN)
#define INFINITY_D ((double)INFINITY)
#define CHECK(cond) check((cond), __LINE__, #cond)

int main(void) {
    CHECK(msrt_int_compare(1, 2) == -1 && msrt_int_compare(2, 1) == 1 && msrt_int_compare(-5, -5) == 0);
    CHECK(msrt_int_compare(INT64_MIN, INT64_MAX) == -1);
    int64_t big = -1; /* UInt64 max as a bit pattern */
    CHECK(msrt_uint_compare(1, big) == -1 && msrt_uint_compare(big, 1) == 1 && msrt_uint_compare(big, big) == 0);
    CHECK(msrt_float_compare(NAN_D, 1.0) == 1 && msrt_float_compare(1.0, NAN_D) == -1);
    CHECK(msrt_float_compare(NAN_D, NAN_D) == 0 && msrt_float_compare(-0.0, 0.0) == 0);
    CHECK(msrt_float_compare(1.0, 2.0) == -1 && msrt_float_compare(INFINITY_D, 2.0) == 1);
    CHECK(msrt_uint_to_float(big) == 18446744073709551616.0);
    /* Rounds once to binary32: the double-rounding cases of crates/ms-rt/src/num.rs. */
    CHECK(msrt_uint_to_float32((int64_t)4611686293305294849ULL) == 4611686568183201792.0);
    CHECK(msrt_uint_to_float32((int64_t)9223372586610589695ULL) == 9223372036854775808.0);
    CHECK(msrt_uint_to_float32(big) == 18446744073709551616.0);
    CHECK(msrt_float_to_bits(1.0) == 0x3ff0000000000000LL && msrt_float_from_bits(0x3ff0000000000000LL) == 1.0);
    CHECK(msrt_float32_to_bits(1.0) == 0x3f800000 && msrt_float32_from_bits((int64_t)0xffffffff3f800000ULL) == 1.0);
    int64_t n = 7;
    CHECK(msrt_float_truncate_to_int(-3.9, &n) == 1 && n == -3);
    CHECK(msrt_float_truncate_to_int(-9223372036854775808.0, &n) == 1 && n == INT64_MIN);
    n = 7;
    CHECK(msrt_float_truncate_to_int(9223372036854775808.0, &n) == 0 && n == 7);
    CHECK(msrt_float_truncate_to_int(NAN_D, &n) == 0 && n == 7);
    float f = 0;
    CHECK(msrt_float_to_float32(1.5, &f) == 1 && f == 1.5F);
    CHECK(msrt_float_to_float32(1e300, &f) == 0 && f == 1.5F);
    CHECK(msrt_float_to_float32(INFINITY_D, &f) == 1 && isinf((double)f));
    CHECK(msrt_float_to_float32(NAN_D, &f) == 1 && isnan((double)f));
    /* parse_int: signs, radixes, prefixes, the limits and the status that wins. */
    int64_t parsed = 0;
    struct {
        const char *text;
        int64_t radix;
        uint8_t status;
        int64_t value;
    } const cases[] = {
        {"12", 10, 0, 12}, {"+12", 10, 0, 12}, {"-12", 10, 0, -12}, {"-ff", 16, 0, -255},
        {"0xFF", 0, 0, 255}, {"-0b101", 0, 0, -5}, {"0o17", 0, 0, 15}, {"017", 0, 0, 17}, {"z", 36, 0, 35},
        {"9223372036854775807", 10, 0, INT64_MAX}, {"-9223372036854775808", 10, 0, INT64_MIN},
        {"0000000000000000000000000000012", 10, 0, 12},
        {"9223372036854775808", 10, 2, 0}, {"-9223372036854775809", 10, 2, 0},
        {"99999999999999999999999999999z", 10, 4, 0}, {"", 10, 4, 0}, {"-", 10, 4, 0}, {"+-1", 10, 4, 0},
        {"0x", 0, 4, 0}, {"12", 2, 4, 0}, {"1 2", 10, 4, 0}, {"FF", 16, 0, 255}, {"-8000000000000000", 16, 0, INT64_MIN}, {"8000000000000000", 16, 2, 0}, {"-0x1f", 0, 0, -31}, {"0B101", 0, 0, 5},
        {"0x1f", 10, 4, 0}, {"1", 1, 1, 0}, {"1", 37, 1, 0}, {"1", -1, 1, 0},
    };
    for (size_t i = 0; i < sizeof cases / sizeof *cases; i++) {
        MsStr text;
        msrt_string_from_bytes((const uint8_t *)cases[i].text, strlen(cases[i].text), &text);
        parsed = 77;
        CHECK(msrt_numbers_parse_int(&text, cases[i].radix, &parsed) == cases[i].status);
        CHECK(parsed == (cases[i].status == 0 ? cases[i].value : 77));
        if (cases[i].radix == 10) {
            parsed = 77;
            CHECK(msrt_string_parse_int(&text, &parsed) == (cases[i].status == 0));
            CHECK(parsed == (cases[i].status == 0 ? cases[i].value : 77));
        }
        msrt_string_free(&text);
    }
    puts("core_num: ok");
    return 0;
}

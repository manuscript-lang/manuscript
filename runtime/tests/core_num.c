/* Unit test for runtime/core/num.c; `make c-test` builds it with ASan and UBSan. */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include "ms_rt.h"

static void check(bool ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "core_num.c:%d: %s\n", line, text);
        abort();
    }
}
#define CHECK(cond) check((cond), __LINE__, #cond)

int main(void) {
    CHECK(msrt_int_compare(1, 2) == -1 && msrt_int_compare(2, 1) == 1 && msrt_int_compare(-5, -5) == 0);
    CHECK(msrt_int_compare(INT64_MIN, INT64_MAX) == -1);
    int64_t big = -1; /* UInt64 max as a bit pattern */
    CHECK(msrt_uint_compare(1, big) == -1 && msrt_uint_compare(big, 1) == 1 && msrt_uint_compare(big, big) == 0);
    CHECK(msrt_float_compare(NAN, 1.0) == 1 && msrt_float_compare(1.0, NAN) == -1);
    CHECK(msrt_float_compare(NAN, NAN) == 0 && msrt_float_compare(-0.0, 0.0) == 0);
    CHECK(msrt_float_compare(1.0, 2.0) == -1 && msrt_float_compare(INFINITY, 2.0) == 1);
    CHECK(msrt_uint_to_float(big) == 18446744073709551616.0);
    /* Rounds once to binary32: the double-rounding cases of crates/ms-rt/src/num.rs. */
    CHECK(msrt_uint_to_float32((int64_t)4611686293305294849ULL) == 4611686568183201792.0);
    CHECK(msrt_uint_to_float32((int64_t)9223372586610589695ULL) == 9223372036854775808.0);
    CHECK(msrt_uint_to_float32(big) == 18446744073709551616.0);
    CHECK(msrt_float_to_bits(1.0) == 0x3ff0000000000000LL && msrt_float_from_bits(0x3ff0000000000000LL) == 1.0);
    CHECK(msrt_float32_to_bits(1.0) == 0x3f800000 && msrt_float32_from_bits(0xffffffff3f800000LL) == 1.0);
    int64_t n = 7;
    CHECK(msrt_float_truncate_to_int(-3.9, &n) == 1 && n == -3);
    CHECK(msrt_float_truncate_to_int(-9223372036854775808.0, &n) == 1 && n == INT64_MIN);
    n = 7;
    CHECK(msrt_float_truncate_to_int(9223372036854775808.0, &n) == 0 && n == 7);
    CHECK(msrt_float_truncate_to_int(NAN, &n) == 0 && n == 7);
    float f = 0;
    CHECK(msrt_float_to_float32(1.5, &f) == 1 && f == 1.5f);
    CHECK(msrt_float_to_float32(1e300, &f) == 0 && f == 1.5f);
    CHECK(msrt_float_to_float32(INFINITY, &f) == 1 && isinf(f));
    CHECK(msrt_float_to_float32(NAN, &f) == 1 && isnan(f));
    puts("core_num: ok");
    return 0;
}

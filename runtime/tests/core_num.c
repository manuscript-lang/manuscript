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
    puts("core_num: ok");
    return 0;
}

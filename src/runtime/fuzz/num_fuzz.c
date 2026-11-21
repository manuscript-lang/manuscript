/* Fuzz harness for src/runtime/core/num.c: algebraic laws on arbitrary bit patterns. Input is two 8-byte words. */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "ms_rt/num.h"

#define REQUIRE(c) do { if (!(c)) abort(); } while (0)

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size < 16) return 0;
    int64_t x, y;
    memcpy(&x, data, 8);
    memcpy(&y, data + 8, 8);
    double a = msrt_float_from_bits(x), b = msrt_float_from_bits(y);
    REQUIRE(msrt_float_compare(a, b) == -msrt_float_compare(b, a));
    REQUIRE(msrt_float_compare(a, a) == 0);
    REQUIRE(msrt_int_compare(x, y) == -msrt_int_compare(y, x));
    REQUIRE(msrt_uint_compare(x, y) == -msrt_uint_compare(y, x));
    REQUIRE(msrt_int_compare(x, x) == 0 && msrt_uint_compare(x, x) == 0);
    REQUIRE(msrt_float_to_bits(a) == x);
    if (a == a) {
        REQUIRE(msrt_float_from_bits(msrt_float_to_bits(a)) == a || a != a);
        int64_t t = 0;
        if (msrt_float_truncate_to_int(a, &t)) REQUIRE(t == (int64_t)a);
        float f = 0;
        if (msrt_float_to_float32(a, &f)) REQUIRE(f == f);
    }
    double w = msrt_float32_from_bits(x);
    if (w == w) REQUIRE(msrt_float32_to_bits(w) == (int64_t)(uint32_t)x);
    return 0;
}

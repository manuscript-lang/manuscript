/* Number primitives with no runtime state. Ported from crates/ms-rt/src/num.rs. */
#include "ms_rt.h"

/* Float.compare: a total order in which -0.0 == 0.0 and NaN is equal to itself and sorts last. */
int64_t msrt_float_compare(double a, double b) {
    if (a != a || b != b) {
        return (int64_t)(a != a) - (int64_t)(b != b);
    }
    return (int64_t)(a > b) - (int64_t)(a < b);
}

/* Int.compare. */
int64_t msrt_int_compare(int64_t a, int64_t b) {
    return (int64_t)(a > b) - (int64_t)(a < b);
}

/* UInt64.compare: the operands are bit patterns. */
int64_t msrt_uint_compare(int64_t a, int64_t b) {
    uint64_t x = (uint64_t)a, y = (uint64_t)b;
    return (int64_t)(x > y) - (int64_t)(x < y);
}

/* UInt64.to_float. */
double msrt_uint_to_float(int64_t v) {
    return (double)(uint64_t)v;
}

/* UInt64.to_float32: round once to binary32, then widen for the runtime ABI. */
double msrt_uint_to_float32(int64_t v) {
    return (double)(float)(uint64_t)v;
}

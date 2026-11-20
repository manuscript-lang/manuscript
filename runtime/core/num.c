/* Number primitives with no runtime state. Ported from crates/ms-rt/src/num.rs. */
#include "ms_rt/num.h"

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

/* The Float with this IEEE 754 binary64 bit pattern. */
double msrt_float_from_bits(int64_t bits) {
    double value;
    __builtin_memcpy(&value, &bits, sizeof value);
    return value;
}

/* The IEEE 754 binary64 bit pattern of a Float. */
int64_t msrt_float_to_bits(double value) {
    int64_t bits;
    __builtin_memcpy(&bits, &value, sizeof bits);
    return bits;
}

/* The binary32 with this bit pattern (the low 32 bits), widened exactly to the double a Float32 register holds. */
double msrt_float32_from_bits(int64_t bits) {
    uint32_t low = (uint32_t)bits;
    float value;
    __builtin_memcpy(&value, &low, sizeof value);
    return (double)value;
}

/* The binary32 bit pattern of a value a Float32 register holds as a double. */
int64_t msrt_float32_to_bits(double value) {
    float narrowed = (float)value;
    uint32_t bits;
    __builtin_memcpy(&bits, &narrowed, sizeof bits);
    return (int64_t)bits;
}

/* Float.truncate_to_int(): present flag, value through out only when present. */
uint8_t msrt_float_truncate_to_int(double v, int64_t *out) {
    const double limit = 9223372036854775808.0;
    if (!(v >= -limit && v < limit)) {
        return 0;
    }
    *out = (int64_t)v;
    return 1;
}

/* Float.to_float32(): present flag, value through out only when present. A finite value too large for
 * binary32 is absent; NaN and infinities convert unchanged. */
uint8_t msrt_float_to_float32(double v, float *out) {
    float narrowed = (float)v;
    bool finite = v == v && v - v == 0.0;
    if (finite && (narrowed > 3.4028234663852886e38f || narrowed < -3.4028234663852886e38f)) {
        return 0;
    }
    *out = narrowed;
    return 1;
}

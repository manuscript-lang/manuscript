/* 128-bit integer division for the compiler's `__int128` operators. The archive is linked without compiler-rt or
 * libgcc, and the C sources divide 128-bit values (decimals, big numbers, float formatting), so the helpers
 * the compiler calls live here. Weak, so a program that also links a builtins library keeps working.
 */
#include <stdint.h>

typedef unsigned __int128 U128;
typedef __int128 I128;

/* The names the compiler emits calls to; declared here so the strict warnings see a prototype. */
U128 __udivmodti4(U128 n, U128 d, U128 *rem); // NOLINT(bugprone-reserved-identifier): the name the compiler calls
U128 __udivti3(U128 n, U128 d); // NOLINT(bugprone-reserved-identifier): the name the compiler calls
U128 __umodti3(U128 n, U128 d); // NOLINT(bugprone-reserved-identifier): the name the compiler calls
I128 __modti3(I128 n, I128 d); // NOLINT(bugprone-reserved-identifier): the name the compiler calls
I128 __divti3(I128 n, I128 d); // NOLINT(bugprone-reserved-identifier): the name the compiler calls
I128 __ashlti3(I128 value, int count); // NOLINT(bugprone-reserved-identifier): the name the compiler calls
I128 __ashrti3(I128 value, int count); // NOLINT(bugprone-reserved-identifier): the name the compiler calls
I128 __lshrti3(I128 value, int count); // NOLINT(bugprone-reserved-identifier): the name the compiler calls

/* Shift-and-subtract division, one quotient bit per step; the wide case is rare (decimal and big-number code). */
static U128 divmod(U128 n, U128 d, U128 *rem) {
    if (d == 0) {
        __builtin_trap();
    }
    if ((n >> 64) == 0 && (d >> 64) == 0) {
        *rem = (uint64_t)n % (uint64_t)d;
        return (uint64_t)n / (uint64_t)d;
    }
    U128 quotient = 0;
    U128 rest = 0;
    for (int bit = 127; bit >= 0; bit--) {
        const U128 carry = rest >> 127;
        rest = (rest << 1) | ((n >> bit) & 1);
        if (carry != 0 || rest >= d) {
            rest -= d;
            quotient |= (U128)1 << bit;
        }
    }
    *rem = rest;
    return quotient;
}

__attribute__((weak)) U128 __udivmodti4(U128 n, U128 d, U128 *rem) { // NOLINT(bugprone-reserved-identifier): the name the compiler calls
    return divmod(n, d, rem);
}

__attribute__((weak)) U128 __udivti3(U128 n, U128 d) { // NOLINT(bugprone-reserved-identifier): the name the compiler calls
    U128 rem;
    return divmod(n, d, &rem);
}

__attribute__((weak)) U128 __umodti3(U128 n, U128 d) { // NOLINT(bugprone-reserved-identifier): the name the compiler calls
    U128 rem;
    (void)divmod(n, d, &rem);
    return rem;
}

__attribute__((weak)) I128 __divti3(I128 n, I128 d) { // NOLINT(bugprone-reserved-identifier): the name the compiler calls
    const U128 magnitude_n = n < 0 ? -(U128)n : (U128)n;
    const U128 magnitude_d = d < 0 ? -(U128)d : (U128)d;
    U128 rem;
    const U128 quotient = divmod(magnitude_n, magnitude_d, &rem);
    return (n < 0) != (d < 0) ? (I128)(-quotient) : (I128)quotient;
}

/* The remainder takes the sign of the dividend. */
__attribute__((weak)) I128 __modti3(I128 n, I128 d) { // NOLINT(bugprone-reserved-identifier): the name the compiler calls
    const U128 magnitude_n = n < 0 ? -(U128)n : (U128)n;
    const U128 magnitude_d = d < 0 ? -(U128)d : (U128)d;
    U128 rem;
    (void)divmod(magnitude_n, magnitude_d, &rem);
    return n < 0 ? (I128)(-rem) : (I128)rem;
}

/* Shifts by a count that is not a constant: gcc on aarch64 calls these. They work on 64-bit halves, so they never
 * shift a 128-bit value themselves (that would call them). A count outside 0 to 127 is undefined, as in C. */
__attribute__((weak)) I128 __ashlti3(I128 value, int count) { // NOLINT(bugprone-reserved-identifier): the name the compiler calls
    const uint64_t low = (uint64_t)(U128)value;
    const uint64_t high = (uint64_t)((U128)value >> 64);
    uint64_t out_low;
    uint64_t out_high;
    if (count == 0) {
        return value;
    }
    if (count >= 64) {
        out_low = 0;
        out_high = low << (count - 64);
    } else {
        out_low = low << count;
        out_high = (high << count) | (low >> (64 - count));
    }
    return (I128)(((U128)out_high << 64) | out_low);
}

__attribute__((weak)) I128 __lshrti3(I128 value, int count) { // NOLINT(bugprone-reserved-identifier): the name the compiler calls
    const uint64_t low = (uint64_t)(U128)value;
    const uint64_t high = (uint64_t)((U128)value >> 64);
    uint64_t out_low;
    uint64_t out_high;
    if (count == 0) {
        return value;
    }
    if (count >= 64) {
        out_high = 0;
        out_low = high >> (count - 64);
    } else {
        out_high = high >> count;
        out_low = (low >> count) | (high << (64 - count));
    }
    return (I128)(((U128)out_high << 64) | out_low);
}

__attribute__((weak)) I128 __ashrti3(I128 value, int count) { // NOLINT(bugprone-reserved-identifier): the name the compiler calls
    const uint64_t low = (uint64_t)(U128)value;
    const int64_t high = (int64_t)((U128)value >> 64);
    int64_t out_high;
    uint64_t out_low;
    if (count == 0) {
        return value;
    }
    if (count >= 64) {
        out_high = high < 0 ? -1 : 0;
        out_low = (uint64_t)(high >> (count - 64));
    } else {
        out_high = high >> count;
        out_low = (low >> count) | ((uint64_t)high << (64 - count));
    }
    return (I128)(((U128)(uint64_t)out_high << 64) | out_low);
}

/* base/wide.h: division of 128-bit integers by 64-bit and 128-bit integers without the compiler's runtime library.
 *
 * `/` and `%` on __int128 call `__udivti3` and friends, which programs linked against the runtime do not carry (and
 * not every target has); these helpers do the same with 64-bit arithmetic. A divisor of zero is the caller's
 * check. */
#ifndef MS_BASE_WIDE_H
#define MS_BASE_WIDE_H

#include <stdbool.h>
#include <stdint.h>

typedef unsigned __int128 MsU128;
typedef __int128 MsI128;

/* The quotient of the 128-bit value `high:low` by `divisor` (whose high half `high` must be below) and its remainder. */
uint64_t ms_wide_divide(uint64_t high, uint64_t low, uint64_t divisor, uint64_t *remainder);

/* numerator / divisor and numerator % divisor, unsigned. */
MsU128 ms_u128_div(MsU128 numerator, MsU128 divisor);
MsU128 ms_u128_mod(MsU128 numerator, MsU128 divisor);

/* numerator / divisor, truncated toward zero. */
MsI128 ms_i128_div(MsI128 numerator, MsI128 divisor);

/* a * b into *out; false when the product does not fit 128 bits (true on success). `__builtin_mul_overflow` on __int128 calls
 * `__muloti4` on aarch64, which neither glibc nor the runtime carries; this goes through the unsigned builtin, which
 * expands inline everywhere. */
bool ms_i128_mul(MsI128 a, MsI128 b, MsI128 *out);

#endif

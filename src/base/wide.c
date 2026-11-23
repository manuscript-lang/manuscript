/* Owns the 128-bit division of base/wide.h. */
#include "base/wide.h"

enum { HALF_BITS = 32 };
static const uint64_t HALF_BASE = UINT64_C(1) << HALF_BITS;

uint64_t ms_wide_divide(uint64_t high, uint64_t low, uint64_t divisor, uint64_t *remainder) {
  /* Knuth's algorithm D with 32-bit digits (Hacker's Delight, divlu). */
  const unsigned shift = (unsigned)__builtin_clzll(divisor);
  const uint64_t d = divisor << shift;
  const uint64_t d1 = d >> HALF_BITS;
  const uint64_t d0 = d & (HALF_BASE - 1);
  const uint64_t top = shift == 0 ? high : (high << shift) | (low >> (64 - shift));
  const uint64_t bottom = low << shift;
  const uint64_t n1 = bottom >> HALF_BITS;
  const uint64_t n0 = bottom & (HALF_BASE - 1);

  uint64_t q1 = top / d1;
  uint64_t rhat = top - q1 * d1;
  while (q1 >= HALF_BASE || q1 * d0 > ((rhat << HALF_BITS) | n1)) {
    q1--;
    rhat += d1;
    if (rhat >= HALF_BASE) {
      break;
    }
  }
  const uint64_t middle = (top << HALF_BITS) + n1 - q1 * d;

  uint64_t q0 = middle / d1;
  rhat = middle - q0 * d1;
  while (q0 >= HALF_BASE || q0 * d0 > ((rhat << HALF_BITS) | n0)) {
    q0--;
    rhat += d1;
    if (rhat >= HALF_BASE) {
      break;
    }
  }
  *remainder = ((middle << HALF_BITS) + n0 - q0 * d) >> shift;
  return (q1 << HALF_BITS) + q0;
}

static MsU128 divmod(MsU128 numerator, MsU128 divisor, MsU128 *remainder) {
  const uint64_t divisor_high = (uint64_t)(divisor >> 64);
  const uint64_t high = (uint64_t)(numerator >> 64);
  const uint64_t low = (uint64_t)numerator;
  if (divisor_high == 0) {
    const uint64_t d = (uint64_t)divisor;
    uint64_t rest = 0;
    const uint64_t quotient_high = high / d;
    const uint64_t quotient_low = ms_wide_divide(high % d, low, d, &rest);
    *remainder = rest;
    return ((MsU128)quotient_high << 64) | quotient_low;
  }
  if (numerator < divisor) {
    *remainder = numerator;
    return 0;
  }
  /* The quotient is below 2^64: restoring division one bit at a time. */
  MsU128 rest = 0;
  uint64_t quotient = 0;
  for (int bit = 127; bit >= 0; bit--) {
    rest = (rest << 1) | ((numerator >> bit) & 1);
    quotient <<= 1;
    if (rest >= divisor) {
      rest -= divisor;
      quotient |= 1;
    }
  }
  *remainder = rest;
  return quotient;
}

MsU128 ms_u128_div(MsU128 numerator, MsU128 divisor) {
  MsU128 remainder = 0;
  return divmod(numerator, divisor, &remainder);
}

MsU128 ms_u128_mod(MsU128 numerator, MsU128 divisor) {
  MsU128 remainder = 0;
  (void)divmod(numerator, divisor, &remainder);
  return remainder;
}

MsI128 ms_i128_div(MsI128 numerator, MsI128 divisor) {
  const bool negative = (numerator < 0) != (divisor < 0);
  const MsU128 n = numerator < 0 ? (MsU128)0 - (MsU128)numerator : (MsU128)numerator;
  const MsU128 d = divisor < 0 ? (MsU128)0 - (MsU128)divisor : (MsU128)divisor;
  const MsU128 q = ms_u128_div(n, d);
  return negative ? (MsI128)((MsU128)0 - q) : (MsI128)q;
}

bool ms_i128_mul(MsI128 a, MsI128 b, MsI128 *out) {
  const bool negative = (a < 0) != (b < 0);
  const MsU128 ua = a < 0 ? -(MsU128)a : (MsU128)a;
  const MsU128 ub = b < 0 ? -(MsU128)b : (MsU128)b;
  MsU128 product;
  if (__builtin_mul_overflow(ua, ub, &product)) {
    return false;
  }
  const MsU128 limit = (MsU128)1 << 127;
  if (product > limit || (product == limit && !negative)) {
    return false;
  }
  *out = negative ? (MsI128)(0 - product) : (MsI128)product;
  return true;
}

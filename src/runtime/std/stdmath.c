/* @std/math natives: libm for the functions of Float, and 128-bit arithmetic for the wide-word helpers. */
#include <limits.h>
#include <math.h>
#include <stdint.h>

#include "abi/status.h"
#include "base/bytes.h"
#include "runtime/std/stdmath.h"

enum { MAX_SAFE_INTEGER_BITS = 53 };

typedef unsigned __int128 WideWord;

/* ---- functions of one Float ---- */

double msstd_math_acos(double v) {
  return acos(v);
}
double msstd_math_acosh(double v) {
  return acosh(v);
}
double msstd_math_asin(double v) {
  return asin(v);
}
double msstd_math_asinh(double v) {
  return asinh(v);
}
double msstd_math_atan(double v) {
  return atan(v);
}
double msstd_math_atanh(double v) {
  return atanh(v);
}
double msstd_math_cbrt(double v) {
  return cbrt(v);
}
double msstd_math_ceil(double v) {
  return ceil(v);
}
double msstd_math_cos(double v) {
  return cos(v);
}
double msstd_math_cosh(double v) {
  return cosh(v);
}
double msstd_math_exp(double v) {
  return exp(v);
}
double msstd_math_exp2(double v) {
  return exp2(v);
}
double msstd_math_expm1(double v) {
  return expm1(v);
}
double msstd_math_floor(double v) {
  return floor(v);
}
double msstd_math_log(double v) {
  return log(v);
}
double msstd_math_log10(double v) {
  return log10(v);
}
double msstd_math_log1p(double v) {
  return log1p(v);
}
double msstd_math_log2(double v) {
  return log2(v);
}
double msstd_math_sin(double v) {
  return sin(v);
}
double msstd_math_sinh(double v) {
  return sinh(v);
}
double msstd_math_sqrt(double v) {
  return sqrt(v);
}
double msstd_math_tan(double v) {
  return tan(v);
}
double msstd_math_tanh(double v) {
  return tanh(v);
}
double msstd_math_truncate(double v) {
  return trunc(v);
}
double msstd_math_round_to_even(double v) {
  return rint(v);
} /* ties to even in the default rounding mode */

/* Ties toward positive infinity, signed zero kept: `round(-0.2)` is -0. */
double msstd_math_round(double v) {
  if (!isfinite(v) || v == 0.0) {
    return v;
  }
  double rounded = floor(v);
  if (v - rounded >= 0.5) {
    rounded += 1.0;
  }
  return rounded == 0.0 ? copysign(0.0, v) : rounded;
}

/* -1, 0 or 1, keeping signed zero and NaN. */
double msstd_math_sign(double v) {
  if (isnan(v) || v == 0.0) {
    return v;
  }
  return v > 0.0 ? 1.0 : -1.0;
}

/* ---- functions of two or three Floats ---- */

double msstd_math_atan2(double y, double x) {
  return atan2(y, x);
}
double msstd_math_copy_sign(double value, double sign) {
  return copysign(value, sign);
}
double msstd_math_fma(double left, double right, double addend) {
  return fma(left, right, addend);
}
double msstd_math_hypot(double left, double right) {
  return hypot(left, right);
}
double msstd_math_ieee_remainder(double left, double right) {
  return remainder(left, right);
}
double msstd_math_next_after(double value, double toward) {
  return nextafter(value, toward);
}
double msstd_math_pow(double base, double exponent) {
  return pow(base, exponent);
}
/* `Math.remainder` is C `fmod`, not the IEEE remainder. */
double msstd_math_remainder(double left, double right) {
  return fmod(left, right);
}

/* A beyond-int exponent overflows or underflows every nonzero finite value, so clamping keeps every result.
 */
double msstd_math_ldexp(double fraction, int64_t exponent) {
  int64_t clamped = exponent;
  if (clamped < INT_MIN) {
    clamped = INT_MIN;
  }
  if (clamped > INT_MAX) {
    clamped = INT_MAX;
  }
  return ldexp(fraction, (int)clamped);
}

void msstd_math_frexp(double value, MsBinaryFloatParts *out) {
  int exponent = 0;
  out->fraction =
      isfinite(value) ? frexp(value, &exponent) : value; /* the exponent of infinity and NaN is unspecified */
  out->exponent = exponent;
}

void msstd_math_modf(double value, MsFloatParts *out) {
  double integer = 0.0;
  out->fraction = modf(value, &integer);
  out->integer = integer;
}

uint8_t msstd_math_is_integer(double v) {
  return isfinite(v) && v == trunc(v);
}
uint8_t msstd_math_is_safe_integer(double v) {
  return msstd_math_is_integer(v) && fabs(v) <= (double)((INT64_C(1) << MAX_SAFE_INTEGER_BITS) - 1);
}
uint8_t msstd_math_sign_bit(double value) {
  return signbit(value) != 0;
}

/* ---- wide words ---- */

void msstd_math_add_with_carry(uint64_t left, uint64_t right, uint8_t carry, MsWordSum *out) {
  const WideWord total = (WideWord)left + right + (carry != 0);
  out->sum = (uint64_t)total;
  out->carry = (uint8_t)(total >> 64);
}

void msstd_math_subtract_with_borrow(uint64_t left, uint64_t right, uint8_t borrow, MsWordDifference *out) {
  const WideWord taken = (WideWord)right + (borrow != 0);
  out->difference = (uint64_t)((WideWord)left - taken);
  out->borrow = left < taken;
}

void msstd_math_multiply_wide(uint64_t left, uint64_t right, MsWideProduct *out) {
  const WideWord product = (WideWord)left * right;
  out->high = (uint64_t)(product >> 64);
  out->low = (uint64_t)product;
}

static WideWord wide_of(uint64_t high, uint64_t low) {
  return ((WideWord)high << 64) | low;
}

uint8_t msstd_math_divide_wide(uint64_t high, uint64_t low, uint64_t divisor, MsWordDivision *out) {
  if (divisor == 0) {
    return MS_STATUS_INVALID_INPUT;
  }
  if (high >= divisor) {
    return MS_STATUS_OUT_OF_RANGE;
  }
  const WideWord dividend = wide_of(high, low);
  out->quotient = (uint64_t)(dividend / divisor);
  out->remainder = (uint64_t)(dividend % divisor);
  return MS_STATUS_OK;
}

uint8_t msstd_math_remainder_wide(uint64_t high, uint64_t low, uint64_t divisor, uint64_t *out) {
  if (divisor == 0) {
    return MS_STATUS_INVALID_INPUT;
  }
  *out = (uint64_t)(wide_of(high, low) % divisor);
  return MS_STATUS_OK;
}

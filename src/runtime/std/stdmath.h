/* ms_rt/stdmath.h: the @std/math natives (src/runtime/std/stdmath.c) over the C library's libm. A function of
 * Float is the libm function of the same name, except `round` (ties toward positive infinity), `sign` and the
 * integer tests. The wide-word helpers return their pair through `out`. Symbols are listed in
 * src/runtime/symbols/stdmath.txt. */
#ifndef MS_RUNTIME_STD_STDMATH_H
#define MS_RUNTIME_STD_STDMATH_H

#include "abi/status.h"
#include "base/bytes.h"

/* `WordSum`, `WordDifference`, `WideProduct`, `WordDivision`, `BinaryFloatParts` and `FloatParts`, in
 * declaration order. */
typedef struct MsWordSum {
  uint64_t sum;
  uint8_t carry;
} MsWordSum;
typedef struct MsWordDifference {
  uint64_t difference;
  uint8_t borrow;
} MsWordDifference;
typedef struct MsWideProduct {
  uint64_t high, low;
} MsWideProduct;
typedef struct MsWordDivision {
  uint64_t quotient, remainder;
} MsWordDivision;
typedef struct MsBinaryFloatParts {
  double fraction;
  int64_t exponent;
} MsBinaryFloatParts;
typedef struct MsFloatParts {
  double integer, fraction;
} MsFloatParts;

/* ms-sig: msstd_math_acos(v: f64) -> f64 @domain=number @leaf */
double msstd_math_acos(double v);
/* ms-sig: msstd_math_acosh(v: f64) -> f64 @domain=number @leaf */
double msstd_math_acosh(double v);
/* ms-sig: msstd_math_add_with_carry(left: u64, right: u64, carry: u8, out: *mut WordSumOut) @domain=number
 * @leaf */
void msstd_math_add_with_carry(uint64_t left, uint64_t right, uint8_t carry, MsWordSum *out);
/* ms-sig: msstd_math_asin(v: f64) -> f64 @domain=number @leaf */
double msstd_math_asin(double v);
/* ms-sig: msstd_math_asinh(v: f64) -> f64 @domain=number @leaf */
double msstd_math_asinh(double v);
/* ms-sig: msstd_math_atan(v: f64) -> f64 @domain=number @leaf */
double msstd_math_atan(double v);
/* ms-sig: msstd_math_atan2(y: f64, x: f64) -> f64 @domain=number @leaf */
double msstd_math_atan2(double y, double x);
/* ms-sig: msstd_math_atanh(v: f64) -> f64 @domain=number @leaf */
double msstd_math_atanh(double v);
/* ms-sig: msstd_math_cbrt(v: f64) -> f64 @domain=number @leaf */
double msstd_math_cbrt(double v);
/* ms-sig: msstd_math_ceil(v: f64) -> f64 @domain=number @leaf @op=fceil */
double msstd_math_ceil(double v);
/* ms-sig: msstd_math_copy_sign(value: f64, sign: f64) -> f64 @domain=number @leaf */
double msstd_math_copy_sign(double value, double sign);
/* ms-sig: msstd_math_cos(v: f64) -> f64 @domain=number @leaf */
double msstd_math_cos(double v);
/* ms-sig: msstd_math_cosh(v: f64) -> f64 @domain=number @leaf */
double msstd_math_cosh(double v);
/* ms-sig: msstd_math_divide_wide(high: u64, low: u64, divisor: u64, out: *mut WordDivisionOut) -> u8
 * @domain=number @leaf */
uint8_t msstd_math_divide_wide(uint64_t high, uint64_t low, uint64_t divisor, MsWordDivision *out);
/* ms-sig: msstd_math_exp(v: f64) -> f64 @domain=number @leaf */
double msstd_math_exp(double v);
/* ms-sig: msstd_math_exp2(v: f64) -> f64 @domain=number @leaf */
double msstd_math_exp2(double v);
/* ms-sig: msstd_math_expm1(v: f64) -> f64 @domain=number @leaf */
double msstd_math_expm1(double v);
/* ms-sig: msstd_math_floor(v: f64) -> f64 @domain=number @leaf @op=ffloor */
double msstd_math_floor(double v);
/* ms-sig: msstd_math_fma(left: f64, right: f64, addend: f64) -> f64 @domain=number @leaf */
double msstd_math_fma(double left, double right, double addend);
/* ms-sig: msstd_math_frexp(value: f64, out: *mut BinaryFloatPartsOut) @domain=number @leaf */
void msstd_math_frexp(double value, MsBinaryFloatParts *out);
/* ms-sig: msstd_math_hypot(left: f64, right: f64) -> f64 @domain=number @leaf */
double msstd_math_hypot(double left, double right);
/* ms-sig: msstd_math_ieee_remainder(left: f64, right: f64) -> f64 @domain=number @leaf */
double msstd_math_ieee_remainder(double left, double right);
/* ms-sig: msstd_math_is_integer(v: f64) -> u8 @domain=number @leaf */
uint8_t msstd_math_is_integer(double v);
/* ms-sig: msstd_math_is_safe_integer(v: f64) -> u8 @domain=number @leaf */
uint8_t msstd_math_is_safe_integer(double v);
/* ms-sig: msstd_math_ldexp(fraction: f64, exponent: i64) -> f64 @domain=number @leaf */
double msstd_math_ldexp(double fraction, int64_t exponent);
/* ms-sig: msstd_math_log(v: f64) -> f64 @domain=number @leaf */
double msstd_math_log(double v);
/* ms-sig: msstd_math_log10(v: f64) -> f64 @domain=number @leaf */
double msstd_math_log10(double v);
/* ms-sig: msstd_math_log1p(v: f64) -> f64 @domain=number @leaf */
double msstd_math_log1p(double v);
/* ms-sig: msstd_math_log2(v: f64) -> f64 @domain=number @leaf */
double msstd_math_log2(double v);
/* ms-sig: msstd_math_modf(value: f64, out: *mut FloatPartsOut) @domain=number @leaf */
void msstd_math_modf(double value, MsFloatParts *out);
/* ms-sig: msstd_math_multiply_wide(left: u64, right: u64, out: *mut WideProductOut) @domain=number @leaf */
void msstd_math_multiply_wide(uint64_t left, uint64_t right, MsWideProduct *out);
/* ms-sig: msstd_math_next_after(value: f64, toward: f64) -> f64 @domain=number @leaf */
double msstd_math_next_after(double value, double toward);
/* ms-sig: msstd_math_pow(base: f64, exponent: f64) -> f64 @domain=number @leaf */
double msstd_math_pow(double base, double exponent);
/* ms-sig: msstd_math_remainder(left: f64, right: f64) -> f64 @domain=number @leaf */
double msstd_math_remainder(double left, double right);
/* ms-sig: msstd_math_remainder_wide(high: u64, low: u64, divisor: u64, out: *mut u64) -> u8 @domain=number
 * @leaf */
uint8_t msstd_math_remainder_wide(uint64_t high, uint64_t low, uint64_t divisor, uint64_t *out);
/* ms-sig: msstd_math_round(v: f64) -> f64 @domain=number @leaf */
double msstd_math_round(double v);
/* ms-sig: msstd_math_round_to_even(v: f64) -> f64 @domain=number @leaf */
double msstd_math_round_to_even(double v);
/* ms-sig: msstd_math_sign(v: f64) -> f64 @domain=number @leaf */
double msstd_math_sign(double v);
/* ms-sig: msstd_math_sign_bit(value: f64) -> u8 @domain=number @leaf */
uint8_t msstd_math_sign_bit(double value);
/* ms-sig: msstd_math_sin(v: f64) -> f64 @domain=number @leaf */
double msstd_math_sin(double v);
/* ms-sig: msstd_math_sinh(v: f64) -> f64 @domain=number @leaf */
double msstd_math_sinh(double v);
/* ms-sig: msstd_math_sqrt(v: f64) -> f64 @domain=number @leaf @op=fsqrt */
double msstd_math_sqrt(double v);
/* ms-sig: msstd_math_subtract_with_borrow(left: u64, right: u64, borrow: u8, out: *mut WordDifferenceOut)
 * @domain=number @leaf */
void msstd_math_subtract_with_borrow(uint64_t left, uint64_t right, uint8_t borrow, MsWordDifference *out);
/* ms-sig: msstd_math_tan(v: f64) -> f64 @domain=number @leaf */
double msstd_math_tan(double v);
/* ms-sig: msstd_math_tanh(v: f64) -> f64 @domain=number @leaf */
double msstd_math_tanh(double v);
/* ms-sig: msstd_math_truncate(v: f64) -> f64 @domain=number @leaf @op=ftrunc */
double msstd_math_truncate(double v);

#endif

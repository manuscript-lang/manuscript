/* Number primitives with no runtime state. Ported from crates/ms-rt/src/num.rs. */
#include "abi/status.h"
#include "base/chars.h"
#include "base/float_parse.h"
#include "runtime/core/num.h"
#include "runtime/core/string_support.h"

/* Float.compare: a total order in which -0.0 == 0.0 and NaN is equal to itself and sorts last. */
int64_t msrt_float_compare(double a, double b) {
  if (a != a || b != b) {
    return (int64_t)(a != a) - (int64_t)(b != b);
  }
  return (int64_t)(a > b) - (int64_t)(a < b);
}

/* Float.is_nan and Float.is_finite: the MIR the lowering emits for them is lowered in the compiler. */
uint8_t msrt_float_is_nan(double x) {
  return x != x;
}

uint8_t msrt_float_is_finite(double x) {
  return x - x == 0.0;
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

/* The binary32 with this bit pattern (the low 32 bits), widened exactly to the double a Float32 register
 * holds. */
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

/* ---- Parsing integers ---- */

/* The radix that ends parsing digits at a character that is not one. */
#define MS_RADIX_MAX 36

/* The value of a digit character in bases up to 36, or MS_RADIX_MAX when it is not one. */
static uint32_t digit_value(uint8_t c) {
  if (ms_ascii_is_digit(c)) {
    return (uint32_t)(c - '0');
  }
  if (ms_ascii_is_alpha(c)) {
    return (uint32_t)(ms_ascii_to_lower(c) - 'a') + 10;
  }
  return MS_RADIX_MAX;
}

/* The radix a `0x`, `0o` or `0b` prefix names (any case), or 0 when `digits` has none. */
static uint32_t prefix_radix(MsSpan digits) {
  if (digits.len < 2 || digits.ptr[0] != '0') {
    return 0;
  }
  switch (ms_ascii_to_lower(digits.ptr[1])) {
  case 'x':
    return 16;
  case 'o':
    return 8;
  case 'b':
    return 2;
  default:
    return 0;
  }
}

/* Whether every byte of `digits` is a digit of `radix`. */
static bool all_digits_in(MsSpan digits, uint32_t radix) {
  for (size_t i = 0; i < digits.len; i++) {
    if (digit_value(digits.ptr[i]) >= radix) {
      return false;
    }
  }
  return true;
}

/* The digits as a magnitude no larger than `limit`; false when it is larger. */
static bool accumulate(MsSpan digits, uint32_t radix, uint64_t limit, uint64_t *magnitude) {
  uint64_t value = 0;
  for (size_t i = 0; i < digits.len; i++) {
    if (__builtin_mul_overflow(value, (uint64_t)radix, &value) ||
        __builtin_add_overflow(value, (uint64_t)digit_value(digits.ptr[i]), &value) || value > limit) {
      return false;
    }
  }
  *magnitude = value;
  return true;
}

/* `Numbers.parse_int`: an optional sign, then digits of `radix` (2 to 36), or with radix 0 a `0x`, `0o` or
 * `0b` prefix after the sign and otherwise base 10. The status is invalid input for a bad radix, invalid data
 * for text that is not a number, and out of range for a value that does not fit. `*out` is written only on
 * success. */
uint8_t msrt_numbers_parse_int(const MsString *text, int64_t radix, int64_t *out) {
  if (radix != 0 && (radix < 2 || radix > MS_RADIX_MAX)) {
    return MS_STATUS_INVALID_INPUT;
  }
  MsSpan digits = msrt_text(text);
  const bool negative = digits.len > 0 && digits.ptr[0] == '-';
  const bool signed_text = negative || (digits.len > 0 && digits.ptr[0] == '+');
  digits = ms_span_of(digits.ptr + (signed_text ? 1 : 0), digits.len - (signed_text ? 1 : 0));
  uint32_t base = (uint32_t)radix;
  if (radix == 0) {
    base = prefix_radix(digits);
    digits = ms_span_of(digits.ptr + (base != 0 ? 2 : 0), digits.len - (base != 0 ? 2 : 0));
    base = base != 0 ? base : 10;
  }
  if (digits.len == 0 || !all_digits_in(digits, base)) {
    return MS_STATUS_INVALID_DATA;
  }
  const uint64_t limit = negative ? UINT64_C(1) << 63 : (UINT64_C(1) << 63) - 1;
  uint64_t magnitude = 0;
  if (!accumulate(digits, base, limit, &magnitude)) {
    return MS_STATUS_OUT_OF_RANGE;
  }
  *out = negative ? (int64_t)(UINT64_C(0) - magnitude) : (int64_t)magnitude;
  return MS_STATUS_OK;
}

/* `String.parse_int`: whether the text is a decimal integer that fits, and its value through `out`. */
uint8_t msrt_string_parse_int(const MsString *s, int64_t *out) {
  return msrt_numbers_parse_int(s, 10, out) == MS_STATUS_OK;
}

/* ---- parsing floats ---- */

/* `Numbers.parse_float`: the status is invalid data for text that is not a number and out of range for a
 * value too large for a Float. `*out` is written only on success. */
uint8_t msrt_numbers_parse_float(const MsString *text, double *out) {
  switch (ms_parse_float(msrt_text(text), out)) {
  case MS_PARSE_FLOAT_OK:
    return MS_STATUS_OK;
  case MS_PARSE_FLOAT_INVALID:
    return MS_STATUS_INVALID_DATA;
  case MS_PARSE_FLOAT_OUT_OF_RANGE:
    return MS_STATUS_OUT_OF_RANGE;
  }
  return MS_STATUS_INVALID_DATA;
}

/* `String.parse_float`: whether the text is a number, and its value through `out`. */
uint8_t msrt_string_parse_float(const MsString *s, double *out) {
  return msrt_numbers_parse_float(s, out) == MS_STATUS_OK;
}

/* The @std/math Decimal natives (runtime/std/decimal.h). A value is coefficient * 10^exponent with at most 34
 * significant digits; the coefficient fits a signed 128-bit integer, so the common cases (comparison,
 * negation, conversion) use plain 128-bit arithmetic and only the operators that need exact wide
 * intermediates (a sum across very different exponents, a product, a quotient, directed rounding) go through
 * the bignum. Rounding is half to even unless a mode says otherwise; the results are those of the Rust crate
 * this replaces. */
#include <stdio.h>
#include <stdlib.h>

#include "base/strbuild.h"
#include "runtime/core/fault.h"
#include "runtime/std/bignum.h"
#include "runtime/std/decimal.h"
#include "runtime/std/decimal_internal.h"

/* ---- 128-bit helpers ---- */

enum { POW10_WORD_MAX = 19 }; /* 10^19 is the largest power of ten in 64 bits */

/* 10^exponent for an exponent up to 38 (the largest power of ten in 128 bits): two table lookups. */
MsU128 ms_dec_power_of_ten(unsigned exponent) {
  static const uint64_t words[POW10_WORD_MAX + 1] = {
      1ULL,
      10ULL,
      100ULL,
      1000ULL,
      10000ULL,
      100000ULL,
      1000000ULL,
      10000000ULL,
      100000000ULL,
      1000000000ULL,
      10000000000ULL,
      100000000000ULL,
      1000000000000ULL,
      10000000000000ULL,
      100000000000000ULL,
      1000000000000000ULL,
      10000000000000000ULL,
      100000000000000000ULL,
      1000000000000000000ULL,
      10000000000000000000ULL,
  };
  if (exponent <= POW10_WORD_MAX) {
    return words[exponent];
  }
  return (MsU128)words[POW10_WORD_MAX] * words[exponent - POW10_WORD_MAX];
}

/* Decimal digits of a nonzero 128-bit value (1 for zero). */
unsigned ms_dec_digits_of(MsU128 value) {
  if (value == 0) {
    return 1;
  }
  const unsigned long long high = (unsigned long long)(value >> 64);
  const unsigned bits = high != 0 ? 128 - (unsigned)__builtin_clzll(high)
                                  : 64 - (unsigned)__builtin_clzll((unsigned long long)value);
  const unsigned guess = (bits * 1233) >> 12; /* floor(bits * log10(2)) */
  return guess + 1 - (value < ms_dec_power_of_ten(guess) ? 1 : 0);
}

MsI128 ms_dec_coefficient_of(const MsDecimal *d) {
  return (MsI128)(((MsU128)(uint64_t)d->high << 64) | d->low);
}

MsDecimal ms_dec_pack(MsI128 coefficient, int64_t exponent) {
  const MsU128 bits = (MsU128)coefficient;
  return (MsDecimal){.low = (uint64_t)bits,
                     .high = (int64_t)(uint64_t)(bits >> 64),
                     .exponent = coefficient == 0 ? 0 : exponent};
}

bool ms_dec_is_zero(const MsDecimal *d) {
  return d->low == 0 && d->high == 0;
}

MsU128 ms_dec_magnitude_of(MsI128 value) {
  return value < 0 ? (MsU128)0 - (MsU128)value : (MsU128)value;
}

/* Strips trailing zeros of a coefficient into the exponent. */
void ms_dec_normalize(MsU128 *magnitude, int64_t *exponent) {
  while (*magnitude >> 64 != 0) { /* wide values go down to 64 bits first */
    const MsU128 tenth = ms_u128_div(*magnitude, 10);
    if (*magnitude != tenth * 10) {
      return;
    }
    *magnitude = tenth;
    (*exponent)++;
  }
  uint64_t narrow = (uint64_t)*magnitude;
  while (narrow != 0 && narrow % 10 == 0) {
    narrow /= 10;
    (*exponent)++;
  }
  *magnitude = narrow;
}

/* ---- the bignum bridge ---- */

void ms_dec_big_from_coefficient(MsBig *out, const MsDecimal *d) {
  const MsI128 value = ms_dec_coefficient_of(d);
  const MsU128 magnitude = ms_dec_magnitude_of(value);
  ms_big_set_u128(out, (uint64_t)(magnitude >> 64), (uint64_t)magnitude, value < 0);
}

/* Decimal digits of the magnitude of a bignum. Up to 128 bits they are counted directly; beyond that by an
 * estimate from the bit length that never overshoots (1233 / 4096 is just below log10(2)), raised while the
 * value reaches the next power of ten. */
static int64_t big_digits(const MsBig *a) {
  uint64_t high, low;
  if (ms_big_to_u128(a, &high, &low)) {
    return (int64_t)ms_dec_digits_of(((MsU128)high << 64) | low);
  }
  size_t digits = (ms_big_bit_length(a) - 1) * 1233 / 4096 + 1;
  MsBig power = MS_BIG_ZERO;
  for (;;) {
    ms_big_pow10(&power, digits);
    if (ms_big_cmp_abs(a, &power) < 0) {
      break;
    }
    digits++;
  }
  ms_big_free(&power);
  return (int64_t)digits;
}

/* The magnitude of `a` as a 128-bit integer; callers know it fits. */
static MsU128 big_magnitude(const MsBig *a) {
  uint64_t high = 0;
  uint64_t low = 0;
  if (!ms_big_to_u128(a, &high, &low)) {
    ms_fault_text(MS_FAULT_KIND_FAULT, "Decimal: internal coefficient wider than 128 bits");
  }
  return ((MsU128)high << 64) | low;
}

/* Divides |coefficient| by 10^drop, rounds the discarded part half to even, and stores the result in `out`.
 */
static void drop_digits_half_even(MsBig *out, const MsBig *coefficient, int64_t drop) {
  MsBig denominator = MS_BIG_ZERO;
  MsBig remainder = MS_BIG_ZERO;
  MsBig twice = MS_BIG_ZERO;
  MsBig one = MS_BIG_ZERO;
  ms_big_pow10(&denominator, (size_t)drop);
  ms_big_abs(out, coefficient);
  ms_big_divmod(out, &remainder, out, &denominator);
  ms_big_shift_left(&twice, &remainder, 1);
  const int comparison = ms_big_cmp(&twice, &denominator);
  if (comparison > 0 || (comparison == 0 && ms_big_is_odd(out))) {
    ms_big_set_u64(&one, 1);
    ms_big_add(out, out, &one);
  }
  ms_big_free(&denominator);
  ms_big_free(&remainder);
  ms_big_free(&twice);
  ms_big_free(&one);
}

/* Rounds the exact value +-magnitude * 10^exponent half to even at 34 digits. Returns false when the
 * magnitude exceeds the format. */
MS_NODISCARD static bool round_wide(MsU128 magnitude, bool negative, int64_t exponent, MsDecimal *out) {
  if (magnitude == 0) {
    *out = ms_dec_pack(0, 0);
    return true;
  }
  const int64_t digits = ms_dec_digits_of(magnitude);
  const int64_t leading = exponent + digits - 1;
  const int64_t quantum = leading - (MS_DECIMAL_DIGITS - 1) > MS_DECIMAL_MIN_QUANTUM
                              ? leading - (MS_DECIMAL_DIGITS - 1)
                              : MS_DECIMAL_MIN_QUANTUM;
  const int64_t drop = quantum - exponent;
  if (drop > 0) {
    exponent = quantum;
    if (drop > MS_DECIMAL_WIDE_DIGITS) { /* below half of one unit of the quantum */
      magnitude = 0;
    } else {
      const MsU128 unit = ms_dec_power_of_ten((unsigned)drop);
      const MsU128 remainder = ms_u128_mod(magnitude, unit);
      magnitude = ms_u128_div(magnitude, unit);
      const MsU128 complement = unit - remainder;
      if (remainder > complement || (remainder == complement && (magnitude & 1) != 0)) {
        magnitude++;
      }
    }
  }
  ms_dec_normalize(&magnitude, &exponent);
  if (magnitude != 0 && exponent + (int64_t)ms_dec_digits_of(magnitude) - 1 > MS_DECIMAL_MAX_EXPONENT) {
    return false;
  }
  *out = ms_dec_pack(negative ? -(MsI128)magnitude : (MsI128)magnitude, exponent);
  return true;
}

/* Rounds the exact value coefficient * 10^exponent half to even at 34 digits. Returns false when the
 * magnitude exceeds the format. */
MS_NODISCARD static bool rounded(const MsBig *coefficient, int64_t exponent, MsDecimal *out) {
  if (ms_big_is_zero(coefficient)) {
    *out = ms_dec_pack(0, 0);
    return true;
  }
  uint64_t high = 0;
  uint64_t low = 0;
  if (ms_big_to_u128(coefficient, &high, &low)) {
    return round_wide(((MsU128)high << 64) | low, ms_big_sign(coefficient) < 0, exponent, out);
  }
  const int64_t digits = big_digits(coefficient);
  const int64_t leading = exponent + digits - 1;
  const int64_t quantum = leading - (MS_DECIMAL_DIGITS - 1) > MS_DECIMAL_MIN_QUANTUM
                              ? leading - (MS_DECIMAL_DIGITS - 1)
                              : MS_DECIMAL_MIN_QUANTUM;
  const int64_t drop = quantum - exponent;
  const bool negative = ms_big_sign(coefficient) < 0;
  MsBig kept = MS_BIG_ZERO;
  if (drop <= 0) {
    ms_big_abs(&kept, coefficient);
  } else {
    drop_digits_half_even(&kept, coefficient, drop);
    exponent = quantum;
  }
  MsU128 magnitude = big_magnitude(&kept);
  ms_big_free(&kept);
  ms_dec_normalize(&magnitude, &exponent);
  if (magnitude != 0 && exponent + (int64_t)ms_dec_digits_of(magnitude) - 1 > MS_DECIMAL_MAX_EXPONENT) {
    return false;
  }
  const MsI128 signed_value = negative ? -(MsI128)magnitude : (MsI128)magnitude;
  *out = ms_dec_pack(signed_value, exponent);
  return true;
}

/* ---- faults ---- */

/* Appends `count` copies of `byte`. */
static void append_repeat(MsStrBuild *text, uint8_t byte, size_t count) {
  for (size_t i = 0; i < count; i++) {
    ms_strbuild_append_byte(text, byte);
  }
}

/* The text of interpolation: at most 34 significant digits, appended to `text`. */
static void render_into(const MsDecimal *d, MsStrBuild *text) {
  if (ms_dec_is_zero(d)) {
    ms_strbuild_append_byte(text, '0');
    return;
  }
  const MsI128 coefficient = ms_dec_coefficient_of(d);
  MsU128 magnitude = ms_dec_magnitude_of(coefficient);
  uint8_t digits[MS_DECIMAL_RENDER_MAX] = {0};
  size_t count = 0;
  for (; magnitude != 0; magnitude /= 10) {
    digits[count++] = (uint8_t)('0' + (int)(magnitude % 10));
  }
  for (size_t i = 0; i < count / 2; i++) { /* reverse in place */
    const uint8_t swap = digits[i];
    digits[i] = digits[count - 1 - i];
    digits[count - 1 - i] = swap;
  }
  const int64_t exponent = d->exponent + (int64_t)count - 1;
  while (count > 1 && digits[count - 1] == '0') {
    count--;
  }
  if (coefficient < 0) {
    ms_strbuild_append_byte(text, '-');
  }
  if (exponent >= -6 && exponent <= 20) {
    const int64_t point = exponent + 1;
    if (point <= 0) {
      ms_strbuild_append_text(text, "0.");
      append_repeat(text, '0', (size_t)-point);
      ms_strbuild_append(text, ms_span_of(digits, count));
    } else if ((size_t)point >= count) {
      ms_strbuild_append(text, ms_span_of(digits, count));
      append_repeat(text, '0', (size_t)point - count);
    } else {
      ms_strbuild_append(text, ms_span_of(digits, (size_t)point));
      ms_strbuild_append_byte(text, '.');
      ms_strbuild_append(text, ms_span_of(digits + point, count - (size_t)point));
    }
    return;
  }
  ms_strbuild_append_byte(text, digits[0]);
  if (count > 1) {
    ms_strbuild_append_byte(text, '.');
    ms_strbuild_append(text, ms_span_of(digits + 1, count - 1));
  }
  ms_strbuild_printf(text, "e%s%lld", exponent >= 0 ? "+" : "", (long long)exponent);
}

/* Raises the overflow fault of an operator, naming both operands. */
MS_NORETURN static void overflow_fault(const char *operation, const MsDecimal *left, const MsDecimal *right) {
  MsStrBuild left_text = ms_strbuild_new();
  MsStrBuild right_text = ms_strbuild_new();
  render_into(left, &left_text);
  render_into(right, &right_text);
  MsStrBuild message = ms_strbuild_new();
  ms_strbuild_printf(&message,
                     "Decimal.%s: overflow; found left %.*s and right %.*s; rounded magnitude must be at "
                     "most 9.999999999999999999999999999999999e6144 (34 significant digits)",
                     operation, (int)ms_strbuild_length(&left_text),
                     (const char *)ms_strbuild_span(&left_text).ptr, (int)ms_strbuild_length(&right_text),
                     (const char *)ms_strbuild_span(&right_text).ptr);
  ms_strbuild_append_byte(&message, 0); /* the fault takes a C string */
  ms_fault_text(MS_FAULT_KIND_OVERFLOW, (const char *)ms_strbuild_span(&message).ptr);
}

/* ---- arithmetic ---- */

/* The magnitude of d's coefficient scaled up by 10^shift; false when it does not fit 128 bits. */
static bool scaled_magnitude(const MsDecimal *d, int64_t shift, MsU128 *out) {
  if (shift > MS_DECIMAL_WIDE_DIGITS) {
    return false;
  }
  return !__builtin_mul_overflow(ms_dec_magnitude_of(ms_dec_coefficient_of(d)),
                                 ms_dec_power_of_ten((unsigned)shift), out);
}

/* The sum or difference when both aligned coefficients and their combination fit 128 bits (the common case).
 */
static bool combine_wide(const MsDecimal *a, const MsDecimal *b, bool subtract, int64_t exponent,
                         MsDecimal *out) {
  MsU128 left = 0;
  MsU128 right = 0;
  if (!scaled_magnitude(a, a->exponent - exponent, &left) ||
      !scaled_magnitude(b, b->exponent - exponent, &right)) {
    return false;
  }
  const bool left_negative = ms_dec_coefficient_of(a) < 0;
  const bool right_negative = (ms_dec_coefficient_of(b) < 0) != subtract;
  MsU128 magnitude = 0;
  bool negative = left_negative;
  if (left_negative == right_negative) {
    if (__builtin_add_overflow(left, right, &magnitude)) {
      return false;
    }
  } else if (left >= right) {
    magnitude = left - right;
  } else {
    magnitude = right - left;
    negative = right_negative;
  }
  if (!round_wide(magnitude, negative, exponent, out)) {
    overflow_fault(subtract ? "-" : "+", a, b);
  }
  return true;
}

/* The exact sum or difference shares one alignment: both coefficients are scaled to the smaller exponent. */
static void combine(const MsDecimal *a, const MsDecimal *b, bool subtract, MsDecimal *out) {
  if (ms_dec_is_zero(b)) {
    *out = *a;
    return;
  }
  if (ms_dec_is_zero(a)) {
    if (subtract) {
      msstd_decimal_negate(b, out);
    } else {
      *out = *b;
    }
    return;
  }
  const int64_t exponent = a->exponent < b->exponent ? a->exponent : b->exponent;
  if (combine_wide(a, b, subtract, exponent, out)) {
    return;
  }
  MsBig left = MS_BIG_ZERO;
  MsBig right = MS_BIG_ZERO;
  MsBig scale = MS_BIG_ZERO;
  ms_dec_big_from_coefficient(&left, a);
  ms_dec_big_from_coefficient(&right, b);
  ms_big_pow10(&scale, (size_t)(a->exponent - exponent));
  ms_big_mul(&left, &left, &scale);
  ms_big_pow10(&scale, (size_t)(b->exponent - exponent));
  ms_big_mul(&right, &right, &scale);
  if (subtract) {
    ms_big_sub(&left, &left, &right);
  } else {
    ms_big_add(&left, &left, &right);
  }
  const bool fits = rounded(&left, exponent, out);
  ms_big_free(&left);
  ms_big_free(&right);
  ms_big_free(&scale);
  if (!fits) {
    overflow_fault(subtract ? "-" : "+", a, b);
  }
}

void msstd_decimal_add(const MsDecimal *a, const MsDecimal *b, MsDecimal *out) {
  combine(a, b, false, out);
}

void msstd_decimal_subtract(const MsDecimal *a, const MsDecimal *b, MsDecimal *out) {
  combine(a, b, true, out);
}

void msstd_decimal_multiply(const MsDecimal *a, const MsDecimal *b, MsDecimal *out) {
  MsU128 product = 0;
  if (!__builtin_mul_overflow(ms_dec_magnitude_of(ms_dec_coefficient_of(a)),
                              ms_dec_magnitude_of(ms_dec_coefficient_of(b)), &product)) {
    const bool negative = (ms_dec_coefficient_of(a) < 0) != (ms_dec_coefficient_of(b) < 0);
    if (!round_wide(product, negative, a->exponent + b->exponent, out)) {
      overflow_fault("*", a, b);
    }
    return;
  }
  MsBig left = MS_BIG_ZERO;
  MsBig right = MS_BIG_ZERO;
  ms_dec_big_from_coefficient(&left, a);
  ms_dec_big_from_coefficient(&right, b);
  ms_big_mul(&left, &left, &right);
  const bool fits = rounded(&left, a->exponent + b->exponent, out);
  ms_big_free(&left);
  ms_big_free(&right);
  if (!fits) {
    overflow_fault("*", a, b);
  }
}

/* The quotient to 36 or more digits plus a sticky digit, so rounding at 34 digits is exact. */
void msstd_decimal_divide(const MsDecimal *a, const MsDecimal *b, MsDecimal *out) {
  static const char zero_message[] = "Decimal./: division by zero; right must be nonzero, found 0";
  if (ms_dec_is_zero(b)) {
    ms_fault_text(MS_FAULT_KIND_DIVISION_BY_ZERO, zero_message);
  }
  if (ms_dec_is_zero(a)) {
    *out = ms_dec_pack(0, 0);
    return;
  }
  const bool negative = (ms_dec_coefficient_of(a) < 0) != (ms_dec_coefficient_of(b) < 0);
  MsBig dividend = MS_BIG_ZERO;
  MsBig divisor = MS_BIG_ZERO;
  MsBig scale = MS_BIG_ZERO;
  MsBig remainder = MS_BIG_ZERO;
  ms_dec_big_from_coefficient(&dividend, a);
  ms_dec_big_from_coefficient(&divisor, b);
  ms_big_abs(&dividend, &dividend);
  ms_big_abs(&divisor, &divisor);
  int64_t shift = MS_DECIMAL_DIGITS + 2 + big_digits(&divisor) - big_digits(&dividend);
  shift = shift > 0 ? shift : 0;
  int64_t exponent = a->exponent - b->exponent - shift;
  ms_big_pow10(&scale, (size_t)shift);
  ms_big_mul(&dividend, &dividend, &scale);
  ms_big_divmod(&dividend, &remainder, &dividend, &divisor);
  if (!ms_big_is_zero(
          &remainder)) { /* a sticky digit: the quotient has at least 35 digits, so it only breaks ties */
    ms_big_set_u64(&scale, 10);
    ms_big_mul(&dividend, &dividend, &scale);
    ms_big_set_u64(&scale, 1);
    ms_big_add(&dividend, &dividend, &scale);
    exponent--;
  }
  if (negative) {
    ms_big_negate(&dividend, &dividend);
  }
  const bool fits = rounded(&dividend, exponent, out);
  ms_big_free(&dividend);
  ms_big_free(&divisor);
  ms_big_free(&scale);
  ms_big_free(&remainder);
  if (!fits) {
    overflow_fault("/", a, b);
  }
}

void msstd_decimal_negate(const MsDecimal *a, MsDecimal *out) {
  *out = ms_dec_pack(-ms_dec_coefficient_of(a), a->exponent); /* at most 34 digits, so the negation fits */
}

/* ---- comparison ---- */

static int compare_magnitudes(MsU128 a, int64_t a_exponent, MsU128 b, int64_t b_exponent) {
  const unsigned a_digits = ms_dec_digits_of(a) - 1;
  const unsigned b_digits = ms_dec_digits_of(b) - 1;
  const MsI128 a_lead = (MsI128)a_exponent + (MsI128)a_digits;
  const MsI128 b_lead = (MsI128)b_exponent + (MsI128)b_digits;
  if (a_lead != b_lead) {
    return a_lead < b_lead ? -1 : 1;
  }
  /* Equal leading exponents need at most 33 places of alignment; a wider product cannot be the smaller. */
  MsU128 scaled = 0;
  if (a_digits < b_digits) {
    if (__builtin_mul_overflow(a, ms_dec_power_of_ten(b_digits - a_digits), &scaled)) {
      return 1;
    }
    return (scaled > b) - (scaled < b);
  }
  if (__builtin_mul_overflow(b, ms_dec_power_of_ten(a_digits - b_digits), &scaled)) {
    return -1;
  }
  return (a > scaled) - (a < scaled);
}

int64_t msstd_decimal_compare(const MsDecimal *a, const MsDecimal *b) {
  const MsI128 x = ms_dec_coefficient_of(a);
  const MsI128 y = ms_dec_coefficient_of(b);
  if (a->exponent == b->exponent || (x < 0) != (y < 0) || x == 0 || y == 0) {
    return (x > y) - (x < y);
  }
  const int magnitude =
      compare_magnitudes(ms_dec_magnitude_of(x), a->exponent, ms_dec_magnitude_of(y), b->exponent);
  return x < 0 ? -magnitude : magnitude;
}

/* ---- construction and conversion ---- */

static MsDecimal from_integer(uint64_t magnitude, bool negative) {
  int64_t exponent = 0;
  MsU128 value = magnitude;
  ms_dec_normalize(&value, &exponent);
  return ms_dec_pack(negative ? -(MsI128)value : (MsI128)value, exponent);
}

void msstd_decimal_from_int(int64_t n, MsDecimal *out) {
  *out = from_integer(n < 0 ? 0 - (uint64_t)n : (uint64_t)n, n < 0);
}

void msstd_decimal_from_uint(int64_t n, MsDecimal *out) {
  *out = from_integer((uint64_t)n, false);
}

void msstd_decimal_to_string(const MsDecimal *a, MsString *out) {
  MsStrBuild text = ms_strbuild_new();
  render_into(a, &text);
  *out = ms_strbuild_finish(&text);
  ms_strbuild_free(&text);
}

/* The nearest double of coefficient * 10^exponent, from the text `<coefficient>e<exponent>`, which the C
 * library rounds correctly and which has no decimal point to depend on the locale. */
double msstd_decimal_to_float(const MsDecimal *a) {
  if (ms_dec_is_zero(a)) {
    return 0.0;
  }
  char digits[MS_DECIMAL_RENDER_MAX];
  const MsI128 coefficient = ms_dec_coefficient_of(a);
  MsU128 magnitude = ms_dec_magnitude_of(coefficient);
  size_t start = sizeof digits;
  for (; magnitude != 0; magnitude /= 10) {
    digits[--start] = (char)('0' + (int)(magnitude % 10));
  }
  char text[MS_DECIMAL_RENDER_MAX + 16];
  const int length = snprintf(text, sizeof text, "%s%.*se%lld", coefficient < 0 ? "-" : "",
                              (int)(sizeof digits - start), digits + start, (long long)a->exponent);
  return length > 0 ? strtod(text, NULL) : 0.0;
}

/* The integer part toward zero, when it fits an int64_t. */
uint8_t msstd_decimal_truncate_to_int(const MsDecimal *a, int64_t *out) {
  const MsI128 coefficient = ms_dec_coefficient_of(a);
  MsI128 value = 0;
  if (a->exponent >= 0) {
    if (coefficient == 0) {
      *out = 0;
      return 1;
    }
    if (a->exponent > 19 ||
        __builtin_mul_overflow(coefficient, (MsI128)ms_dec_power_of_ten((unsigned)a->exponent), &value)) {
      return 0;
    }
  } else if (-a->exponent > 38) {
    *out = 0; /* the coefficient has at most 34 digits */
    return 1;
  } else {
    value = ms_i128_div(coefficient, (MsI128)ms_dec_power_of_ten((unsigned)-a->exponent));
  }
  if (value < INT64_MIN || value > INT64_MAX) {
    return 0;
  }
  *out = (int64_t)value;
  return 1;
}

/* `to_decimal()` of each integer type: the exactly equal Decimal. */
#define TO_DECIMAL(name, from)                                                                                   \
  void msrt_##name##_to_decimal(int64_t v, MsDecimal *out) {                                                   \
    from(v, out);                                                                                              \
  }

TO_DECIMAL(int, msstd_decimal_from_int)
TO_DECIMAL(int8, msstd_decimal_from_int)
TO_DECIMAL(int16, msstd_decimal_from_int)
TO_DECIMAL(int32, msstd_decimal_from_int)
TO_DECIMAL(int64, msstd_decimal_from_int)
TO_DECIMAL(uint8, msstd_decimal_from_int)
TO_DECIMAL(uint16, msstd_decimal_from_int)
TO_DECIMAL(uint32, msstd_decimal_from_int)
TO_DECIMAL(uint64, msstd_decimal_from_uint)

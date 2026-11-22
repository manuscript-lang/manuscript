/* The Decimal natives for text and rounding: parse, round and to_fixed (decimal.h). */
#include <stdlib.h>

#include "base/alloc.h"
#include "base/strbuild.h"
#include "runtime/core/fault.h"
#include "runtime/std/decimal_internal.h"

/* How round and to_fixed discard digits: the declaration order of RoundingMode. */
typedef enum MsRounding {
  MS_ROUND_HALF_EVEN,
  MS_ROUND_HALF_AWAY,
  MS_ROUND_TOWARD_ZERO,
  MS_ROUND_FLOOR,
  MS_ROUND_CEIL,
} MsRounding;

/* ---- parsing ---- */

/* An exponent written with an optional sign, in the range of an int32_t; false when it is not. */
MS_NODISCARD static bool parse_exponent(MsSpan text, int64_t *out) {
  size_t at = 0;
  const bool negative = text.len > 0 && text.ptr[0] == '-';
  if (text.len > 0 && (text.ptr[0] == '-' || text.ptr[0] == '+')) {
    at = 1;
  }
  int64_t value = 0;
  for (; at < text.len; at++) {
    value = value * 10 + (text.ptr[at] - '0');
    if (value > (int64_t)INT32_MAX + 1) {
      return false;
    }
  }
  if (value > INT32_MAX && !(negative && value == (int64_t)INT32_MAX + 1)) {
    return false;
  }
  *out = negative ? -value : value;
  return true;
}

static bool is_digit(uint8_t byte) {
  return byte >= '0' && byte <= '9';
}

/* The digits of a mantissa with at most one point inside it, point removed; false for anything else. Stores
 * the digit count and the number of fraction digits. */
typedef struct MsMantissa {
  size_t leading_zeros;
  size_t trailing_zeros;
  size_t count;
  size_t fraction;
  MsU128 trimmed; /* the digits without leading or trailing zeros, when there are at most 34 of them */
  bool too_wide;
} MsMantissa;

MS_NODISCARD static bool scan_mantissa(MsSpan text, MsMantissa *out) {
  MsMantissa m = {0};
  size_t point = text.len;
  for (size_t i = 0; i < text.len; i++) {
    if (text.ptr[i] == '.' && point == text.len) {
      point = i;
    } else if (!is_digit(text.ptr[i])) {
      return false;
    }
  }
  if (point != text.len && (point == 0 || point == text.len - 1)) {
    return false;
  }
  bool seen_nonzero = false;
  size_t zeros = 0;
  for (size_t i = 0; i < text.len; i++) {
    if (i == point) {
      continue;
    }
    const uint8_t digit = (uint8_t)(text.ptr[i] - '0');
    m.count++;
    if (digit == 0 && !seen_nonzero) {
      m.leading_zeros++;
    } else {
      seen_nonzero = true;
      zeros = digit == 0 ? zeros + 1 : 0;
      m.too_wide = m.too_wide || m.count - m.leading_zeros - zeros > MS_DECIMAL_DIGITS;
    }
  }
  m.trailing_zeros = seen_nonzero ? zeros : 0;
  m.fraction = point == text.len ? 0 : text.len - point - 1;
  *out = m;
  return true;
}

/* Accumulates the significant digits (all but leading and trailing zeros); there are at most 34. */
static MsU128 significant_digits(MsSpan text, const MsMantissa *m) {
  MsU128 value = 0;
  size_t seen = 0;
  const size_t end = m->count - m->trailing_zeros;
  for (size_t i = 0; i < text.len; i++) {
    if (!is_digit(text.ptr[i])) {
      continue; /* the point */
    }
    if (seen >= m->leading_zeros && seen < end) {
      value = value * 10 + (MsU128)(text.ptr[i] - '0');
    }
    seen++;
  }
  return value;
}

/* The literal grammar of Decimal: an optional sign, digits with at most one inner point, an optional exponent
 * (`e` or `E`, signed digits) and an optional trailing `d`. */
MS_NODISCARD static bool parse_literal(MsSpan text, MsDecimal *out) {
  size_t end = text.len;
  size_t start = 0;
  if (end > 0 && text.ptr[end - 1] == 'd') {
    end--;
  }
  const bool negative = end > 0 && text.ptr[0] == '-';
  if (end > 0 && (text.ptr[0] == '-' || text.ptr[0] == '+')) {
    start = 1;
  }
  size_t marker = end;
  for (size_t i = start; i < end && marker == end; i++) {
    if (text.ptr[i] == 'e' || text.ptr[i] == 'E') {
      marker = i;
    }
  }
  const MsSpan mantissa_text = ms_span_of(text.ptr + start, marker - start);
  const MsSpan exponent_text = marker == end ? ms_span_of((const uint8_t *)"0", 1)
                                             : ms_span_of(text.ptr + marker + 1, end - marker - 1);
  size_t sign = exponent_text.len > 0 && (exponent_text.ptr[0] == '-' || exponent_text.ptr[0] == '+') ? 1 : 0;
  MsMantissa m = {0};
  if (exponent_text.len == sign || mantissa_text.len == 0) {
    return false;
  }
  for (; sign < exponent_text.len; sign++) {
    if (!is_digit(exponent_text.ptr[sign])) {
      return false;
    }
  }
  if (!scan_mantissa(mantissa_text, &m)) {
    return false;
  }
  int64_t exponent = 0;
  if (m.leading_zeros == m.count) {
    *out = ms_dec_pack(0, 0);
    return true;
  }
  if (!parse_exponent(exponent_text, &exponent)) {
    return false;
  }
  const int64_t quantum = exponent - (int64_t)m.fraction + (int64_t)m.trailing_zeros;
  const int64_t width = (int64_t)(m.count - m.leading_zeros - m.trailing_zeros);
  if (m.too_wide || quantum < MS_DECIMAL_MIN_QUANTUM || quantum + width - 1 > MS_DECIMAL_MAX_EXPONENT) {
    return false;
  }
  const MsI128 value = (MsI128)significant_digits(mantissa_text, &m);
  *out = ms_dec_pack(negative ? -value : value, quantum);
  return true;
}

uint8_t msstd_decimal_parse(const MsString *text, MsDecimal *out) {
  MsDecimal parsed = {0};
  if (!parse_literal(ms_string_span(text), &parsed)) {
    return MS_STATUS_INVALID_INPUT;
  }
  *out = parsed;
  return MS_STATUS_OK;
}

/* ---- rounding ---- */

MS_NODISCARD static bool rounding_of(uint8_t has_mode, int64_t index, MsRounding *mode) {
  if (has_mode == 0) {
    *mode = MS_ROUND_HALF_EVEN;
    return true;
  }
  if (index < MS_ROUND_HALF_EVEN || index > MS_ROUND_CEIL) {
    return false;
  }
  *mode = (MsRounding)index;
  return true;
}

/* Whether discarding a nonzero remainder moves the kept magnitude up by one. */
static bool rounds_up(MsRounding mode, int comparison_with_half, bool kept_is_odd, bool negative) {
  switch (mode) {
  case MS_ROUND_HALF_EVEN:
    return comparison_with_half > 0 || (comparison_with_half == 0 && kept_is_odd);
  case MS_ROUND_HALF_AWAY:
    return comparison_with_half >= 0;
  case MS_ROUND_TOWARD_ZERO:
    return false;
  case MS_ROUND_FLOOR:
    return negative;
  case MS_ROUND_CEIL:
    return !negative;
  }
  return false;
}

/* The coefficient of `d` rounded to a multiple of 10^-places. */
static void scaled_coefficient(MsBig *out, const MsDecimal *d, int64_t places, MsRounding mode) {
  ms_dec_big_from_coefficient(out, d);
  if (ms_big_is_zero(out)) {
    return;
  }
  const int64_t shift = d->exponent + places;
  MsBig scale = MS_BIG_ZERO;
  if (shift >= 0) {
    ms_big_pow10(&scale, (size_t)shift);
    ms_big_mul(out, out, &scale);
    ms_big_free(&scale);
    return;
  }
  const bool negative = ms_big_sign(out) < 0;
  if (-shift > MS_DECIMAL_DIGITS) {
    /* The coefficient has at most 34 digits, so twice it is below the divisor: nearest rounding and
     * truncation give zero and only a directed mode moves one unit away. */
    const bool away = (mode == MS_ROUND_FLOOR && negative) || (mode == MS_ROUND_CEIL && !negative);
    const int unit = negative ? -1 : 1;
    ms_big_set_i64(out, away ? unit : 0);
    return;
  }
  MsBig remainder = MS_BIG_ZERO;
  MsBig twice = MS_BIG_ZERO;
  ms_big_pow10(&scale, (size_t)-shift);
  ms_big_abs(out, out);
  ms_big_divmod(out, &remainder, out, &scale);
  if (!ms_big_is_zero(&remainder)) {
    ms_big_shift_left(&twice, &remainder, 1);
    if (rounds_up(mode, ms_big_cmp(&twice, &scale), ms_big_is_odd(out), negative)) {
      ms_big_set_u64(&twice, 1);
      ms_big_add(out, out, &twice);
    }
  }
  if (negative) {
    ms_big_negate(out, out);
  }
  ms_big_free(&scale);
  ms_big_free(&remainder);
  ms_big_free(&twice);
}

/* |coefficient| / 10^drop rounded by `mode`, for a drop of at least one digit. A 34-digit coefficient is
 * below 10^34, so a drop beyond 34 digits leaves less than half a unit: nearest rounding and truncation give
 * zero and only a directed mode moves one unit away. */
static MsU128 rounded_magnitude(MsU128 magnitude, bool negative, int64_t drop, MsRounding mode) {
  if (drop > MS_DECIMAL_DIGITS) {
    const bool away = (mode == MS_ROUND_FLOOR && negative) || (mode == MS_ROUND_CEIL && !negative);
    return away ? 1 : 0;
  }
  const MsU128 unit = ms_dec_power_of_ten((unsigned)drop);
  const MsU128 remainder = ms_u128_mod(magnitude, unit);
  MsU128 quotient = ms_u128_div(magnitude, unit);
  if (remainder != 0) {
    const MsU128 complement = unit - remainder;
    const int comparison_with_half = (remainder > complement) - (remainder < complement);
    if (rounds_up(mode, comparison_with_half, (quotient & 1) != 0, negative)) {
      quotient++;
    }
  }
  return quotient;
}

uint8_t msstd_decimal_round(const MsDecimal *value, int64_t places, uint8_t has_mode, int64_t mode,
                            MsDecimal *out) {
  MsRounding rounding = MS_ROUND_HALF_EVEN;
  if (!rounding_of(has_mode, mode, &rounding) || places < -6144 || places > 6176) {
    return MS_STATUS_INVALID_INPUT;
  }
  if (ms_dec_is_zero(value) ||
      value->exponent + places >= 0) { /* already an exact multiple of this quantum */
    *out = *value;
    return MS_STATUS_OK;
  }
  const bool negative = ms_dec_coefficient_of(value) < 0;
  const int64_t drop = -(value->exponent + places);
  MsU128 magnitude =
      rounded_magnitude(ms_dec_magnitude_of(ms_dec_coefficient_of(value)), negative, drop, rounding);
  int64_t exponent = -places;
  ms_dec_normalize(&magnitude, &exponent);
  if (magnitude != 0) {
    const int64_t digits = ms_dec_digits_of(magnitude);
    if (digits > MS_DECIMAL_DIGITS || exponent < MS_DECIMAL_MIN_QUANTUM ||
        exponent + digits - 1 > MS_DECIMAL_MAX_EXPONENT) {
      return MS_STATUS_OUT_OF_RANGE;
    }
  }
  *out = ms_dec_pack(negative ? -(MsI128)magnitude : (MsI128)magnitude, exponent);
  return MS_STATUS_OK;
}

/* Plain notation with exactly `places` fractional digits, built from the digits of the scaled coefficient. */
static void format_fixed(const MsBig *scaled, int64_t places, MsString *out) {
  size_t count = 0;
  uint8_t *const digits = ms_big_digits_new(scaled, 10, &count);
  const size_t fraction = (size_t)places;
  const size_t padded = count > fraction ? count : fraction + 1; /* an integer digit before the point */
  uint8_t *const text = ms_alloc(padded + 3);
  size_t length = 0;
  if (ms_big_sign(scaled) < 0) {
    text[length++] = '-';
  }
  for (size_t i = 0; i < padded; i++) {
    if (i == padded - fraction && fraction > 0) {
      text[length++] = '.';
    }
    const size_t from_end = padded - i; /* position counted from the last digit */
    text[length++] = from_end > count ? '0' : digits[count - from_end];
  }
  *(out) = ms_string_from_span(ms_span_of(text, length));
  ms_free(text);
  ms_free(digits);
}

uint8_t msstd_decimal_to_fixed(const MsDecimal *value, int64_t digits, uint8_t has_mode, int64_t mode,
                               MsString *out) {
  MsRounding rounding = MS_ROUND_HALF_EVEN;
  if (!rounding_of(has_mode, mode, &rounding) || digits < 0 || digits > 6176) {
    return MS_STATUS_INVALID_INPUT;
  }
  MsBig scaled = MS_BIG_ZERO;
  scaled_coefficient(&scaled, value, digits, rounding);
  format_fixed(&scaled, digits, out);
  ms_big_free(&scaled);
  return MS_STATUS_OK;
}

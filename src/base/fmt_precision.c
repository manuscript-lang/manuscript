/* base/fmt_precision.c: the precision forms of a float: to_fixed, to_exponential and to_precision, from the
 * exact decimal expansion of the value, rounded half to even. */
#include "base/fmt_sink.h"

typedef unsigned __int128 MsU128;

/* ---- precision forms: the exact decimal expansion, rounded half to even ---- */

#define MS_LIMB_BASE 1000000000u
#define MS_LIMB_DIGITS 9
/* c * 5^1074 is below 10^768; the limbs also hold c * 2^971. */
#define MS_LIMB_CAPACITY 96
#define MS_EXACT_DIGITS_CAPACITY ((size_t)MS_LIMB_CAPACITY * MS_LIMB_DIGITS)
/* The most digits any precision form keeps: 22 before the point and 100 after, plus a carry. */
#define MS_KEPT_CAPACITY 128
#define MS_PRECISION_MAX 100

/* A non-negative integer in base 10^9, least significant limb first. */
typedef struct MsBigNumber {
  uint32_t limbs[MS_LIMB_CAPACITY];
  size_t count;
} MsBigNumber;

static MsBigNumber big_from_unsigned(uint64_t value) {
  MsBigNumber number = {.limbs = {0}, .count = 0};
  for (; value != 0; value /= MS_LIMB_BASE) {
    number.limbs[number.count++] = (uint32_t)(value % MS_LIMB_BASE); /* a UInt64 has at most 3 limbs */
  }
  return number;
}

/* number *= multiplier; false when the result needs more limbs than there are. */
MS_NODISCARD static bool big_multiply(MsBigNumber *number, uint32_t multiplier) {
  uint64_t carry = 0;
  for (size_t i = 0; i < number->count; i++) {
    const uint64_t product = (uint64_t)number->limbs[i] * multiplier + carry; /* limbs are below 10^9, so this fits */
    number->limbs[i] = (uint32_t)(product % MS_LIMB_BASE);
    carry = product / MS_LIMB_BASE;
  }
  for (; carry != 0; carry /= MS_LIMB_BASE) {
    if (number->count >= MS_LIMB_CAPACITY) {
      return false;
    }
    number->limbs[number->count++] = (uint32_t)(carry % MS_LIMB_BASE);
  }
  return true;
}

/* number *= base^exponent, in steps whose multiplier fits 32 bits. */
MS_NODISCARD static bool big_multiply_power(MsBigNumber *number, uint32_t base, int exponent,
                                            int step_limit) {
  for (int left = exponent; left > 0;) {
    const int step = left < step_limit ? left : step_limit;
    uint32_t multiplier = 1;
    for (int i = 0; i < step; i++) {
      multiplier *= base;
    }
    if (!big_multiply(number, multiplier)) {
      return false;
    }
    left -= step;
  }
  return true;
}

/* Decimal digits, most significant first without leading zeros, and the exponent of the first. */
typedef struct MsExactDigits {
  uint8_t text[MS_EXACT_DIGITS_CAPACITY];
  size_t length;
  int point;
} MsExactDigits;

static void exact_push_limb(MsExactDigits *digits, uint32_t limb) {
  uint8_t text[MS_LIMB_DIGITS] = {0};
  for (size_t i = MS_LIMB_DIGITS; i > 0; i--) {
    text[i - 1] = (uint8_t)('0' + limb % 10);
    limb /= 10;
  }
  size_t first = 0;
  while (digits->length == 0 && first < MS_LIMB_DIGITS - 1 && text[first] == '0') {
    first++; /* no leading zeros in the number */
  }
  for (size_t i = first; i < MS_LIMB_DIGITS && digits->length < MS_EXACT_DIGITS_CAPACITY; i++) {
    digits->text[digits->length++] = text[i];
  }
}

/* The exact decimal expansion of the positive value c * 2^q. A negative q is c * 5^-q divided by 10^-q, so
 * the digits are those of an integer and only the exponent moves. */
MS_NODISCARD static bool exact_expansion(uint64_t c, int q, MsExactDigits *digits) {
  MsBigNumber number = big_from_unsigned(c);
  const bool grown = q >= 0 ? big_multiply_power(&number, 2, q, 29) : big_multiply_power(&number, 5, -q, 13);
  if (!grown) {
    return false;
  }
  digits->length = 0;
  for (size_t i = number.count; i > 0; i--) {
    exact_push_limb(digits, number.limbs[i - 1]);
  }
  const int decimal_shift = q < 0 ? q : 0;
  digits->point = (int)digits->length - 1 + decimal_shift; /* length is at most 864 */
  return true;
}

/* The leading `keep` digits of the expansion (zero-padded when it is shorter) rounded half to even, and the
 * exponent of the first kept digit, which grows by one when the rounding carries out. */
typedef struct MsKept {
  uint8_t text[MS_KEPT_CAPACITY];
  size_t length;
  int point;
} MsKept;

static bool any_nonzero(const MsExactDigits *digits, size_t from) {
  for (size_t i = from; i < digits->length; i++) {
    if (digits->text[i] != '0') {
      return true;
    }
  }
  return false;
}

static uint8_t exact_digit(const MsExactDigits *digits, size_t index) {
  return index < digits->length ? digits->text[index] : '0';
}

/* Whether the digits after the first `keep` are above half a unit, or exactly half with an odd last kept
 * digit. */
static bool rounds_up(const MsExactDigits *digits, const MsKept *kept) {
  const size_t keep = kept->length;
  const uint8_t next = exact_digit(digits, keep);
  if (next != '5') {
    return next > '5';
  }
  if (any_nonzero(digits, keep + 1)) {
    return true;
  }
  return keep > 0 && ((kept->text[keep - 1] - '0') & 1) != 0;
}

/* Rounds to `keep` digits, 1..=MS_KEPT_CAPACITY. */
MS_NODISCARD static bool round_digits(const MsExactDigits *digits, size_t keep, MsKept *kept) {
  if (keep == 0 || keep > MS_KEPT_CAPACITY) {
    return false;
  }
  kept->length = keep;
  kept->point = digits->point;
  for (size_t i = 0; i < keep; i++) {
    kept->text[i] = exact_digit(digits, i);
  }
  if (!rounds_up(digits, kept)) {
    return true;
  }
  size_t i = keep;
  while (i > 0 && kept->text[i - 1] == '9') {
    i--;
    kept->text[i] = '0';
  }
  if (i == 0) {
    kept->text[0] = '1'; /* 99.9 rounded up is 100: the leading digit and the exponent move */
    kept->point++;
  } else {
    kept->text[i - 1]++;
  }
  return true;
}

static uint8_t kept_digit_at(const MsKept *kept, int exponent) {
  const int index = kept->point - exponent;
  return index >= 0 && (size_t)index < kept->length ? kept->text[index] : '0';
}

/* The fast path of to_fixed: up to 15 fractional digits of a value below 2^53, where c * 2^q * 10^digits is
 * an integer product that fits 128 bits. It is divided by a power of two, the remainder deciding the rounding
 * (a tie goes to the even last digit). */
#define MS_FIXED_FAST_DIGITS 15

typedef struct MsFixedRequest {
  bool negative;
  uint64_t c;
  int q;
  size_t digits;
} MsFixedRequest;

/* The value scaled to an integer count of 10^-digits, rounded; false when it does not fit 64 bits or the
 * request is out of this path's range. */
MS_NODISCARD static bool fixed_scaled(MsFixedRequest request, uint64_t scale, uint64_t *scaled) {
  if (request.q > 0) {
    return false;
  }
  const MsU128 product = (MsU128)request.c * scale;
  const unsigned shift = (unsigned)-request.q;
  MsU128 rounded = product;
  if (shift >= 128) {
    rounded = 0;
  } else if (shift > 0) {
    const MsU128 whole = product >> shift;
    const MsU128 rest = product & (((MsU128)1 << shift) - 1);
    const MsU128 half = (MsU128)1 << (shift - 1);
    rounded = whole + ((rest > half || (rest == half && (whole & 1) != 0)) ? 1 : 0);
  }
  if ((rounded >> 64) != 0) {
    return false;
  }
  *scaled = (uint64_t)rounded;
  return true;
}

static bool sink_put_fixed_fast(MsFmtSink *sink, MsFixedRequest request) {
  if (request.digits > MS_FIXED_FAST_DIGITS) {
    return false;
  }
  uint64_t scale = 1;
  for (size_t i = 0; i < request.digits; i++) {
    scale *= 10;
  }
  uint64_t scaled = 0;
  if (!fixed_scaled(request, scale, &scaled)) {
    return false;
  }
  if (request.negative) {
    ms_fmt_sink_put_byte(sink, '-');
  }
  ms_fmt_sink_put_unsigned(sink, scaled / scale);
  if (request.digits > 0) {
    const uint64_t fraction = scaled % scale;
    ms_fmt_sink_put_byte(sink, '.');
    ms_fmt_sink_put_zeros(sink, request.digits - ms_fmt_decimal_length(fraction));
    ms_fmt_sink_put_unsigned(sink, fraction);
  }
  return true;
}

/* A value split for the precision forms. */
typedef struct MsPrecisionValue {
  bool negative;
  uint64_t c; /* zero for 0.0 */
  int q;
} MsPrecisionValue;

static MsPrecisionValue split_precision(double value) {
  const uint64_t bits = ms_fmt_double_bits(value);
  const int biased = (int)((bits >> 52) & 0x7ff);
  const uint64_t fraction = bits & ((UINT64_C(1) << 52) - 1);
  const bool normal = biased != 0;
  return (MsPrecisionValue){.negative = (bits & MS_FMT_SIGN_BIT_64) != 0,
                            .c = normal ? (fraction | (UINT64_C(1) << 52)) : fraction,
                            .q = normal ? biased - 1075 : -1074};
}

/* to_fixed through the exact expansion: digits are kept down to 10^-want. */
static bool sink_put_fixed_exact(MsFmtSink *sink, MsPrecisionValue value, size_t want) {
  MsExactDigits exact = {.text = {0}, .length = 0, .point = 0};
  MsKept kept = {.text = {0}, .length = 0, .point = 0};
  if (value.c != 0) {
    if (!exact_expansion(value.c, value.q, &exact)) {
      return false;
    }
    const int keep = exact.point + 1 + (int)want;
    if (keep > 0 && !round_digits(&exact, (size_t)keep, &kept)) {
      return false;
    }
    if (keep == 0 && (exact.text[0] > '5' || (exact.text[0] == '5' && any_nonzero(&exact, 1)))) {
      /* Below one unit of the last place but above half of it: rounds up to that unit. */
      kept = (MsKept){.text = {'1'}, .length = 1, .point = -(int)want};
    }
  }
  if (value.negative) {
    ms_fmt_sink_put_byte(sink, '-');
  }
  if (kept.length == 0 || kept.point < 0) {
    ms_fmt_sink_put_byte(sink, '0');
  } else {
    for (int e = kept.point; e >= 0; e--) {
      ms_fmt_sink_put_byte(sink, kept_digit_at(&kept, e));
    }
  }
  if (want > 0) {
    ms_fmt_sink_put_byte(sink, '.');
    for (size_t i = 0; i < want; i++) {
      ms_fmt_sink_put_byte(sink, kept_digit_at(&kept, -1 - (int)i));
    }
  }
  return true;
}

typedef enum MsPrecisionForm {
  MS_FORM_FIXED,       /* 'f': digits after the point */
  MS_FORM_EXPONENTIAL, /* 'e': digits after the first digit */
  MS_FORM_PRECISION,   /* 'g': significant digits, plain notation for exponents -6..digits */
} MsPrecisionForm;

static bool parse_form(uint8_t letter, MsPrecisionForm *form) {
  switch (letter) {
  case 'f':
    *form = MS_FORM_FIXED;
    return true;
  case 'e':
    *form = MS_FORM_EXPONENTIAL;
    return true;
  case 'g':
    *form = MS_FORM_PRECISION;
    return true;
  default:
    return false;
  }
}

/* The scientific forms: `after` digits follow the first, rounded from the exact expansion. */
static bool sink_put_significant(MsFmtSink *sink, MsPrecisionValue value, MsPrecisionForm form,
                                 size_t digits) {
  const size_t after = form == MS_FORM_PRECISION ? digits - 1 : digits;
  MsKept kept = {.text = {0}, .length = after + 1, .point = 0}; /* 0.0 keeps zeros at exponent 0 */
  for (size_t i = 0; i < kept.length && i < MS_KEPT_CAPACITY; i++) {
    kept.text[i] = '0';
  }
  if (value.c != 0) {
    MsExactDigits exact = {.text = {0}, .length = 0, .point = 0};
    if (!exact_expansion(value.c, value.q, &exact) || !round_digits(&exact, after + 1, &kept)) {
      return false;
    }
  }
  if (value.negative) {
    ms_fmt_sink_put_byte(sink, '-');
  }
  const int exponent = kept.point;
  if (form == MS_FORM_PRECISION && exponent >= MS_FMT_PLAIN_EXPONENT_MIN && exponent < (int)digits) {
    ms_fmt_put_plain(sink, ms_span_of(kept.text, kept.length), exponent);
    return true;
  }
  ms_fmt_sink_put_byte(sink, kept.text[0]);
  if (after > 0) {
    ms_fmt_sink_put_byte(sink, '.');
    for (size_t i = 1; i <= after; i++) {
      ms_fmt_sink_put_byte(sink, kept.text[i]);
    }
  }
  ms_fmt_sink_put_byte(sink, 'e');
  if (exponent >= 0) {
    ms_fmt_sink_put_byte(sink, '+');
  }
  ms_fmt_sink_put_signed(sink, exponent);
  return true;
}

bool ms_fmt_float_precision(double value, uint8_t format, int64_t digits, uint8_t *out, size_t capacity,
                            size_t *length) {
  MsPrecisionForm form = MS_FORM_FIXED;
  const int64_t minimum = format == 'g' ? 1 : 0;
  if (!parse_form(format, &form) || digits < minimum || digits > MS_PRECISION_MAX) {
    return false;
  }
  MsFmtSink sink = ms_fmt_sink_new(out, capacity);
  const bool fixed_overflows_precision = form == MS_FORM_FIXED && (value >= 1e21 || value <= -1e21);
  if (__builtin_isnan(value) || __builtin_isinf(value) || fixed_overflows_precision) {
    return ms_fmt_put_float(&sink, value) && ms_fmt_sink_finish(&sink, length);
  }
  const MsPrecisionValue split = split_precision(value);
  bool written = false;
  if (form == MS_FORM_FIXED) {
    const MsFixedRequest request = {
        .negative = split.negative, .c = split.c, .q = split.q, .digits = (size_t)digits};
    written = sink_put_fixed_fast(&sink, request) || sink_put_fixed_exact(&sink, split, (size_t)digits);
  } else {
    written = sink_put_significant(&sink, split, form, (size_t)digits);
  }
  return written && ms_fmt_sink_finish(&sink, length);
}

/* base/fmt_float.c: floats to text: the shortest digits that read back as the same value (Schubfach,
 * Giulietti 2020) and the Float and Float32 spelling (plain notation for exponents -6..=20, else scientific).
 * Output is byte-identical to the Rust runtime's. */
#include "base/fmt_sink.h"
#include "base/float_table.h"

typedef unsigned __int128 MsU128;

/* ---- shortest digits: Schubfach (Giulietti, 2020), as crates/ms-rt/src/float_digits.rs ---- */

#define MASK63 ((UINT64_C(1) << 63) - 1)

/* The layout of an IEEE 754 binary format. */
typedef struct MsFloatFormat {
  int mantissa_bits;
  int bias;
} MsFloatFormat;

static const MsFloatFormat binary64_format = {.mantissa_bits = 52, .bias = 1023};
static const MsFloatFormat binary32_format = {.mantissa_bits = 23, .bias = 127};

/* Floor of a scaled product, by a shift of a signed value: the compilers we build with shift arithmetically.
 */
static int floor_log10_pow2(int e) {
  return (int)(((int64_t)e * INT64_C(677859288149821)) >> 51);
}

static int floor_log10_three_quarters_pow2(int e) {
  return (int)(((int64_t)e * INT64_C(677859288149821) - INT64_C(281337023816645)) >> 51);
}

static int floor_log2_pow10(int e) {
  return (int)(((int64_t)e * INT64_C(935039633142891)) >> 48);
}

/* g * cp / 2^127 rounded to odd, where g = g1 * 2^63 + g0. */
static uint64_t round_to_odd(uint64_t g1, uint64_t g0, uint64_t cp) {
  const uint64_t x1 = (uint64_t)(((MsU128)g0 * cp) >> 64);
  const MsU128 y = (MsU128)g1 * cp;
  const uint64_t y1 = (uint64_t)(y >> 64);
  const uint64_t y0 = (uint64_t)y;
  const uint64_t z = (y0 >> 1) + x1;
  const uint64_t high = y1 + (z >> 63);
  return high | (((z & MASK63) + MASK63) >> 63);
}

/* A finite positive value as c * 2^q, with the format's smallest exponent and implicit bit. */
typedef struct MsBinaryValue {
  int q;
  uint64_t c;
  int q_min;
  uint64_t c_min;
} MsBinaryValue;

static MsBinaryValue split_binary(uint64_t bits, MsFloatFormat format) {
  const uint64_t c_min = UINT64_C(1) << format.mantissa_bits;
  const int biased = (int)((bits >> format.mantissa_bits) & 0x7ff); /* the sign bit is already clear */
  const uint64_t fraction = bits & (c_min - 1);
  const int q_min = 1 - format.bias - format.mantissa_bits;
  if (biased == 0) {
    return (MsBinaryValue){.q = q_min, .c = fraction, .q_min = q_min, .c_min = c_min};
  }
  return (MsBinaryValue){.q = biased - format.bias - format.mantissa_bits,
                         .c = fraction | c_min,
                         .q_min = q_min,
                         .c_min = c_min};
}

/* The decimal d * 10^exponent nearest to the value among the shortest ones that round to it (an exact tie
 * takes the even digit); d may still end in zeros. False if the power-of-ten table has no entry, which no
 * finite value reaches. */
MS_NODISCARD static bool schubfach(MsBinaryValue value, uint64_t *digits, int *exponent) {
  const uint64_t out = value.c & 1;
  const uint64_t cb = value.c << 2;
  const uint64_t cbr = cb + 2;
  const bool lower_gap_is_half = value.c == value.c_min && value.q != value.q_min;
  const uint64_t cbl = lower_gap_is_half ? cb - 1 : cb - 2;
  const int k = lower_gap_is_half ? floor_log10_three_quarters_pow2(value.q) : floor_log10_pow2(value.q);
  const int shift = value.q + floor_log2_pow10(-k) + 2;
  const int table_index = k - MS_FLOAT_K_MIN;
  if (table_index < 0 || (size_t)table_index >= MS_COUNT_OF(ms_float_g) || shift < 0 || shift > 8) {
    return false;
  }
  const uint64_t g1 = ms_float_g[table_index][0];
  const uint64_t g0 = ms_float_g[table_index][1];
  const uint64_t vb = round_to_odd(g1, g0, cb << shift);
  const uint64_t vbl = round_to_odd(g1, g0, cbl << shift);
  const uint64_t vbr = round_to_odd(g1, g0, cbr << shift);
  *exponent = k;

  const uint64_t s = vb >> 2;
  if (s >= 10) {
    /* A multiple of ten inside the interval gives one digit fewer than `s` does. */
    const uint64_t s_tens = 10 * (s / 10);
    const uint64_t t_tens = s_tens + 10;
    const bool lower_in = vbl + out <= s_tens << 2;
    const bool upper_in = (t_tens << 2) + out <= vbr;
    if (lower_in != upper_in) {
      *digits = lower_in ? s_tens : t_tens;
      return true;
    }
  }
  const uint64_t t = s + 1;
  const bool s_in = vbl + out <= s << 2;
  const bool t_in = (t << 2) + out <= vbr;
  if (s_in != t_in) {
    *digits = s_in ? s : t;
    return true;
  }
  /* Both or neither is inside: the one nearer the value, an exact tie going to the even one. */
  const int64_t cmp = (int64_t)vb - (int64_t)((s + t) << 1);
  *digits = (cmp < 0 || (cmp == 0 && (s & 1) == 0)) ? s : t;
  return true;
}

/* Decimal digits with the decimal exponent of the first one: 12.5 is "125" with exponent 1. A shortest form
 * has at most 17 digits and an integer 20. */
#define MS_DIGITS_CAPACITY 24

typedef struct MsDigits {
  uint8_t text[MS_DIGITS_CAPACITY];
  size_t length;
  int exponent;
} MsDigits;

static MsDigits digits_of_unsigned(uint64_t value, int exponent_of_last_digit) {
  MsDigits digits = {.text = {0}, .length = 0, .exponent = 0};
  if (!ms_fmt_write_decimal(ms_span_mut_of(digits.text, MS_DIGITS_CAPACITY), value, &digits.length)) {
    return digits; /* unreachable: a UInt64 has at most 20 digits */
  }
  /* `length` is at most 20, so the conversion is exact. */
  digits.exponent = exponent_of_last_digit + (int)digits.length - 1;
  return digits;
}

/* The shortest digits of the finite positive value with the given sign-cleared bits. */
MS_NODISCARD static bool shortest_digits(uint64_t bits, MsFloatFormat format, MsDigits *out) {
  uint64_t scaled = 0;
  int exponent = 0;
  if (!schubfach(split_binary(bits, format), &scaled, &exponent)) {
    return false;
  }
  while (scaled % 10 == 0) {
    scaled /= 10;
    exponent++;
  }
  *out = digits_of_unsigned(scaled, exponent);
  return true;
}

/* ---- float text ---- */

/* Plain notation for exponents in -6..=20, else scientific. */
#define MS_PLAIN_EXPONENT_MAX 20

/* digits[start..end], or an overflow when the range is wrong (which no caller's arithmetic produces). */
static void sink_put_slice(MsFmtSink *sink, MsSpan digits, size_t start, size_t end) {
  MsSpan piece = {0};
  if (ms_span_slice(digits, start, end, &piece)) {
    ms_fmt_sink_put(sink, piece);
  } else {
    sink->overflowed = true;
  }
}

/* Plain notation: the digits with the decimal point placed by `exponent`, the exponent of the first digit. */
void ms_fmt_put_plain(MsFmtSink *sink, MsSpan digits, int exponent) {
  const int point = exponent + 1; /* digits before the decimal point */
  if (point <= 0) {
    ms_fmt_sink_put_text(sink, "0.");
    ms_fmt_sink_put_zeros(sink, (size_t)-point);
    ms_fmt_sink_put(sink, digits);
  } else if ((size_t)point >= digits.len) {
    ms_fmt_sink_put(sink, digits);
    ms_fmt_sink_put_zeros(sink, (size_t)point - digits.len);
  } else {
    sink_put_slice(sink, digits, 0, (size_t)point);
    ms_fmt_sink_put_byte(sink, '.');
    sink_put_slice(sink, digits, (size_t)point, digits.len);
  }
}

static void sink_put_scientific(MsFmtSink *sink, MsSpan digits, int exponent) {
  sink_put_slice(sink, digits, 0, 1);
  if (digits.len > 1) {
    ms_fmt_sink_put_byte(sink, '.');
    sink_put_slice(sink, digits, 1, digits.len);
  }
  ms_fmt_sink_put_byte(sink, 'e');
  if (exponent >= 0) {
    ms_fmt_sink_put_byte(sink, '+');
  }
  ms_fmt_sink_put_signed(sink, exponent);
}

/* The digits as the shortest float text, trailing zeros dropped first. */
static void sink_put_decimal_text(MsFmtSink *sink, const MsDigits *digits, bool negative) {
  size_t length = digits->length;
  while (length > 1 && digits->text[length - 1] == '0') {
    length--;
  }
  const MsSpan significant = ms_span_of(digits->text, length);
  if (negative) {
    ms_fmt_sink_put_byte(sink, '-');
  }
  if (digits->exponent >= MS_FMT_PLAIN_EXPONENT_MIN && digits->exponent <= MS_PLAIN_EXPONENT_MAX) {
    ms_fmt_put_plain(sink, significant, digits->exponent);
  } else {
    sink_put_scientific(sink, significant, digits->exponent);
  }
}

uint64_t ms_fmt_double_bits(double value) {
  uint64_t bits = 0;
  __builtin_memcpy(&bits, &value, sizeof bits);
  return bits;
}

static uint32_t float_bits(float value) {
  uint32_t bits = 0;
  __builtin_memcpy(&bits, &value, sizeof bits);
  return bits;
}

/* NaN, an infinity or a zero: the values with fixed text. Returns whether `value` was one of them. */
static bool sink_put_special(MsFmtSink *sink, double value) {
  const bool negative = (ms_fmt_double_bits(value) & MS_FMT_SIGN_BIT_64) != 0;
  if (__builtin_isnan(value)) {
    ms_fmt_sink_put_text(sink, "NaN");
  } else if (__builtin_isinf(value)) {
    ms_fmt_sink_put_text(sink, negative ? "-Infinity" : "Infinity");
  } else if (value == 0.0) {
    ms_fmt_sink_put_text(sink, negative ? "-0" : "0");
  } else {
    return false;
  }
  return true;
}

/* An integral magnitude below 2^53 is exactly representable: its digits are the integer itself. */
#define MS_EXACT_INTEGER_LIMIT 9007199254740992.0

static bool float_digits(double magnitude, MsDigits *digits) {
  if (magnitude < MS_EXACT_INTEGER_LIMIT && magnitude == (double)(int64_t)magnitude) {
    *digits = digits_of_unsigned((uint64_t)magnitude, 0);
    return true;
  }
  return shortest_digits(ms_fmt_double_bits(magnitude), binary64_format, digits);
}

bool ms_fmt_put_float(MsFmtSink *sink, double value) {
  if (sink_put_special(sink, value)) {
    return true;
  }
  const bool negative = value < 0.0;
  MsDigits digits = {.text = {0}, .length = 0, .exponent = 0};
  if (!float_digits(negative ? -value : value, &digits)) {
    return false;
  }
  sink_put_decimal_text(sink, &digits, negative);
  return true;
}

bool ms_fmt_float(double value, uint8_t *out, size_t capacity, size_t *length) {
  MsFmtSink sink = ms_fmt_sink_new(out, capacity);
  return ms_fmt_put_float(&sink, value) && ms_fmt_sink_finish(&sink, length);
}

bool ms_fmt_float32(double value, uint8_t *out, size_t capacity, size_t *length) {
  const float narrowed = (float)value;
  MsFmtSink sink = ms_fmt_sink_new(out, capacity);
  if (sink_put_special(&sink, (double)narrowed)) {
    return ms_fmt_sink_finish(&sink, length);
  }
  MsDigits digits = {.text = {0}, .length = 0, .exponent = 0};
  const uint32_t bits = float_bits(narrowed);
  if (!shortest_digits(bits & 0x7fffffffu, binary32_format, &digits)) {
    return false;
  }
  sink_put_decimal_text(&sink, &digits, (bits >> 31) != 0);
  return ms_fmt_sink_finish(&sink, length);
}

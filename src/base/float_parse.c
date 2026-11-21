/* base/float_parse.c: decimal text to a Float. Syntax only: `^[+-]?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$`,
 * plus the spellings NaN, Infinity, +Infinity and -Infinity. One pass checks the syntax and collects what the
 * fast path needs; a literal with at most 19 digits, a mantissa of at most 2^53 and a power of ten within 22
 * is two exact binary64 operands and one correctly rounded multiplication or division (Clinger). Every other
 * literal goes to the C library's strtod, which rounds correctly on every platform we target. */
#include "base/float_parse.h"

#include <stdlib.h>

#include "base/alloc.h"
#include "base/chars.h"

/* The fast path's limits: digits that fit a uint64, a mantissa binary64 holds exactly, powers of ten it
 * holds. */
#define MS_FAST_DIGITS 19
#define MS_FAST_MANTISSA (UINT64_C(1) << 53)
#define MS_FAST_POWER 22
/* An exponent written with more digits than this is far beyond any double; it stops growing here. */
#define MS_EXPONENT_CAP 100000

static const double powers_of_ten[MS_FAST_POWER + 1] = {
    1e0,  1e1,  1e2,  1e3,  1e4,  1e5,  1e6,  1e7,  1e8,  1e9,  1e10, 1e11,
    1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22,
};

/* What one pass over a valid literal found. */
typedef struct Literal {
  bool negative;
  uint64_t mantissa; /* all digits as an integer; meaningful when digits <= MS_FAST_DIGITS */
  size_t digits;
  int64_t exponent; /* the written exponent less the fraction digits */
} Literal;

/* The number of digits in the run that starts at `at`. */
static size_t digit_run(MsSpan text, size_t at) {
  size_t end = at;
  while (end < text.len && ms_ascii_is_digit(text.ptr[end])) {
    end++;
  }
  return end - at;
}

static void add_digits(Literal *literal, MsSpan text, size_t at, size_t count) {
  for (size_t i = 0; i < count; i++) {
    literal->digits++;
    if (literal->digits <= MS_FAST_DIGITS) {
      literal->mantissa = literal->mantissa * 10 + (uint64_t)(text.ptr[at + i] - '0');
    }
  }
}

/* Checks the syntax of the whole text and fills `literal`; false for anything else. */
static bool scan(MsSpan text, Literal *literal) {
  size_t at = 0;
  if (at < text.len && (text.ptr[at] == '+' || text.ptr[at] == '-')) {
    literal->negative = text.ptr[at] == '-';
    at++;
  }
  size_t count = digit_run(text, at);
  if (count == 0) {
    return false;
  }
  add_digits(literal, text, at, count);
  at += count;
  if (at < text.len && text.ptr[at] == '.') {
    at++;
    count = digit_run(text, at);
    if (count == 0) {
      return false;
    }
    add_digits(literal, text, at, count);
    literal->exponent -= (int64_t)count;
    at += count;
  }
  if (at < text.len && (text.ptr[at] == 'e' || text.ptr[at] == 'E')) {
    at++;
    const bool down = at < text.len && text.ptr[at] == '-';
    if (at < text.len && (text.ptr[at] == '+' || text.ptr[at] == '-')) {
      at++;
    }
    count = digit_run(text, at);
    if (count == 0) {
      return false;
    }
    int64_t written = 0;
    for (size_t i = 0; i < count && written < MS_EXPONENT_CAP; i++) {
      written = written * 10 + (text.ptr[at + i] - '0');
    }
    literal->exponent += down ? -written : written;
    at += count;
  }
  return at == text.len;
}

/* Whether the literal is exactly two binary64 operands and a power of ten the table holds. */
static bool fast_path(const Literal *literal) {
  return literal->digits <= MS_FAST_DIGITS && literal->mantissa <= MS_FAST_MANTISSA &&
         literal->exponent >= -MS_FAST_POWER && literal->exponent <= MS_FAST_POWER;
}

static double fast_value(const Literal *literal) {
  const double mantissa = (double)literal->mantissa;
  const double value = literal->exponent < 0 ? mantissa / powers_of_ten[-literal->exponent]
                                             : mantissa * powers_of_ten[literal->exponent];
  return literal->negative ? -value : value;
}

/* NaN, Infinity, +Infinity and -Infinity; false for any other text. */
static bool named_value(MsSpan text, double *value) {
  if (ms_span_is_text(text, "NaN")) {
    *value = __builtin_nan("");
  } else if (ms_span_is_text(text, "Infinity") || ms_span_is_text(text, "+Infinity")) {
    *value = __builtin_inf();
  } else if (ms_span_is_text(text, "-Infinity")) {
    *value = -__builtin_inf();
  } else {
    return false;
  }
  return true;
}

/* The value of an accepted literal the fast path cannot take: strtod on a NUL-terminated copy of the text. */
static double slow_value(MsSpan text) {
  uint8_t stack[64];
  uint8_t *copy = text.len < sizeof stack ? stack : ms_alloc(text.len + 1);
  __builtin_memcpy(copy, text.ptr, text.len);
  copy[text.len] = 0;
  const double value = strtod((const char *)copy, NULL);
  if (copy != stack) {
    ms_free(copy);
  }
  return value;
}

MsParseFloat ms_parse_float(MsSpan text, double *out) {
  if (named_value(text, out)) {
    return MS_PARSE_FLOAT_OK;
  }
  Literal literal = {0};
  if (!scan(text, &literal)) {
    return MS_PARSE_FLOAT_INVALID;
  }
  if (fast_path(&literal)) {
    *out = fast_value(&literal);
    return MS_PARSE_FLOAT_OK;
  }
  const double value = slow_value(text);
  if (__builtin_isinf(value)) {
    return MS_PARSE_FLOAT_OUT_OF_RANGE;
  }
  *out = value;
  return MS_PARSE_FLOAT_OK;
}

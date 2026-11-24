/* runtime/core/num_text.c: the number natives that fault or build strings: UInt64 division, number error
 * messages, to_string of the scalar types and the precision forms of Float. */
#include "abi/status.h"
#include "base/fmt.h"
#include "base/strbuild.h"
#include "runtime/core/fault.h"
#include "runtime/core/num.h"
#include "runtime/core/string_support.h"

/* ---- division and messages ---- */

/* UInt64./: the operands are bit patterns. */
int64_t msrt_uint_div(int64_t a, int64_t b) {
  if (b == 0) {
    ms_fault_post_text(MS_FAULT_KIND_DIVISION_BY_ZERO, "division by zero; right must be nonzero, found 0");
    return 0;
  }
  return (int64_t)((uint64_t)a / (uint64_t)b);
}

/* UInt64.%: the operands are bit patterns. */
int64_t msrt_uint_rem(int64_t a, int64_t b) {
  if (b == 0) {
    ms_fault_post_text(MS_FAULT_KIND_DIVISION_BY_ZERO, "remainder by zero; right must be nonzero, found 0");
    return 0;
  }
  return (int64_t)((uint64_t)a % (uint64_t)b);
}

/* The error message for a number status code. */
void msrt_numbers_error_message(uint8_t status, MsString *out) {
  const char *message = "number: operation failed";
  switch (status) {
  case MS_STATUS_INVALID_INPUT:
    message = "number: invalid input";
    break;
  case MS_STATUS_INVALID_DATA:
    message = "number: invalid data";
    break;
  case MS_STATUS_OUT_OF_RANGE:
    message = "number: value out of range";
    break;
  default:
    break;
  }
  *out = msrt_string_make(ms_span_of_text(message));
}

/* ---- to_string ---- */

/* The capacities of base/fmt.h hold every valid argument, so a refusal is a bug in this runtime. */
static void put_formatted(bool fitted, const uint8_t *buffer, size_t length, MsString *out) {
  if (!fitted) {
    ms_fault_post_text(MS_FAULT_KIND_FAULT, "to_string: the text does not fit its buffer");
    return;
  }
  *out = msrt_string_make(ms_span_of(buffer, length));
}

void msrt_int_to_string(int64_t v, MsString *out) {
  uint8_t buffer[MS_FMT_INTEGER_CAPACITY];
  const size_t length = ms_fmt_i64_fixed(v, buffer);
  *out = msrt_string_make(ms_span_of(buffer, length));
}

void msrt_uint_to_string(int64_t v, MsString *out) {
  uint8_t buffer[MS_FMT_INTEGER_CAPACITY];
  size_t length = 0;
  put_formatted(ms_fmt_u64((uint64_t)v, buffer, sizeof buffer, &length), buffer, length, out);
}

uint8_t msrt_int_to_string_radix(int64_t v, int64_t radix, MsString *out) {
  if (radix < 2 || radix > 36) {
    return 0;
  }
  const uint32_t base = (uint32_t)radix;
  uint8_t buffer[MS_FMT_RADIX_CAPACITY];
  size_t length = 0;
  /* The magnitude of INT64_MIN needs the unsigned negation. */
  const uint64_t magnitude = v < 0 ? (uint64_t)0 - (uint64_t)v : (uint64_t)v;
  put_formatted(ms_fmt_radix(magnitude, base, v < 0, buffer, sizeof buffer, &length), buffer, length, out);
  return 1;
}

uint8_t msrt_uint_to_string_radix(int64_t v, int64_t radix, MsString *out) {
  if (radix < 2 || radix > 36) {
    return 0;
  }
  const uint32_t base = (uint32_t)radix;
  uint8_t buffer[MS_FMT_RADIX_CAPACITY];
  size_t length = 0;
  put_formatted(ms_fmt_radix((uint64_t)v, base, false, buffer, sizeof buffer, &length), buffer, length, out);
  return 1;
}

void msrt_float_to_string(double v, MsString *out) {
  uint8_t buffer[MS_FMT_FLOAT_CAPACITY];
  size_t length = 0;
  put_formatted(ms_fmt_float(v, buffer, sizeof buffer, &length), buffer, length, out);
}

void msrt_float32_to_string(double v, MsString *out) {
  uint8_t buffer[MS_FMT_FLOAT_CAPACITY];
  size_t length = 0;
  put_formatted(ms_fmt_float32(v, buffer, sizeof buffer, &length), buffer, length, out);
}

void msrt_bool_to_string(uint8_t v, MsString *out) {
  *out = msrt_string_make(ms_span_of_text(v != 0 ? "true" : "false"));
}

/* ---- the precision forms ---- */

/* Formats `v` as `format` ('g', 'e' or 'f') with `digits` in `minimum..=100`, otherwise a fault naming
 * `name`. */
static void precision_out(double v, uint8_t format, int64_t digits, int64_t minimum, const char *name,
                          MsString *out) {
  MsStrBuild message = ms_strbuild_new();
  if (digits < minimum || digits > 100) {
    ms_strbuild_append_text(&message, name);
    ms_strbuild_append_text(&message, ": digits must be at least ");
    ms_strbuild_append_i64(&message, minimum);
    ms_strbuild_append_text(&message, " and at most 100, found ");
    ms_strbuild_append_i64(&message, digits);
    ms_fault_post_built(MS_FAULT_KIND_FAULT, &message);
    return;
  }
  uint8_t buffer[MS_FMT_PRECISION_CAPACITY];
  size_t length = 0;
  if (!ms_fmt_float_precision(v, format, digits, buffer, sizeof buffer, &length)) {
    ms_strbuild_append_text(&message, name);
    ms_strbuild_append_text(&message, ": formatting buffer too small");
    ms_fault_post_built(MS_FAULT_KIND_FAULT, &message);
    return;
  }
  *out = msrt_string_make(ms_span_of(buffer, length));
}

/* Float.to_precision(digits): digits in 1..=100, otherwise a fault. */
void msrt_float_to_precision(double v, int64_t digits, MsString *out) {
  precision_out(v, 'g', digits, 1, "to_precision", out);
}

/* Float.to_exponential(digits): digits in 0..=100, otherwise a fault. */
void msrt_float_to_exponential(double v, int64_t digits, MsString *out) {
  precision_out(v, 'e', digits, 0, "to_exponential", out);
}

/* Float.to_fixed(digits): digits in 0..=100, otherwise a fault. */
void msrt_float_to_fixed(double v, int64_t digits, MsString *out) {
  precision_out(v, 'f', digits, 0, "to_fixed", out);
}

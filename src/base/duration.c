/* Owns duration.h. */
#include "base/duration.h"

typedef struct Unit {
  const char *name;
  int64_t nanoseconds;
} Unit;

static const Unit UNITS[] = {{"ns", 1},          {"us", 1000},          {"\xc2\xb5s", 1000}, {"\xce\xbcs", 1000},
                             {"ms", 1000000},    {"s", 1000000000},     {"m", 60000000000},  {"h", 3600000000000}};

static bool is_digit(uint8_t c) {
  return c >= '0' && c <= '9';
}

static size_t digits(MsSpan text, size_t at) {
  size_t end = at;
  while (end < text.len && is_digit(text.ptr[end])) {
    end++;
  }
  return end;
}

static bool unit_scale(MsSpan unit, int64_t *scale) {
  for (size_t i = 0; i < sizeof UNITS / sizeof UNITS[0]; i++) {
    if (ms_span_is_text(unit, UNITS[i].name)) {
      *scale = UNITS[i].nanoseconds;
      return true;
    }
  }
  return false;
}

static bool whole_value(MsSpan text, int64_t scale, int64_t *total) {
  int64_t value = 0;
  for (size_t i = 0; i < text.len; i++) {
    if (__builtin_mul_overflow(value, 10, &value) || __builtin_add_overflow(value, text.ptr[i] - '0', &value)) {
      return false;
    }
  }
  int64_t scaled = 0;
  return !__builtin_mul_overflow(value, scale, &scaled) && !__builtin_add_overflow(*total, scaled, total);
}

/* floor(fraction * scale), by evaluating the decimal digits from the last. */
static int64_t fraction_value(MsSpan fraction, int64_t scale) {
  long double nanos = 0;
  for (size_t i = fraction.len; i > 0; i--) {
    nanos = ((long double)(fraction.ptr[i - 1] - '0') * (long double)scale + nanos) / 10;
  }
  return (int64_t)nanos;
}

/* One `<number><unit>` component at `*at`, added to `total`. */
static bool component(MsSpan text, size_t *at, int64_t *total) {
  const size_t whole_end = digits(text, *at);
  const MsSpan whole = ms_span_of(text.ptr + *at, whole_end - *at);
  MsSpan fraction = {0};
  size_t next = whole_end;
  if (next < text.len && text.ptr[next] == '.') {
    const size_t end = digits(text, next + 1);
    fraction = ms_span_of(text.ptr + next + 1, end - next - 1);
    next = end;
  }
  if (whole.len == 0 && fraction.len == 0) {
    return false;
  }
  size_t unit_end = next;
  while (unit_end < text.len && text.ptr[unit_end] != '.' && !is_digit(text.ptr[unit_end])) {
    unit_end++;
  }
  int64_t scale = 0;
  if (!unit_scale(ms_span_of(text.ptr + next, unit_end - next), &scale) || !whole_value(whole, scale, total) ||
      __builtin_add_overflow(*total, fraction_value(fraction, scale), total)) {
    return false;
  }
  *at = unit_end;
  return true;
}

bool ms_duration_parse(MsSpan text, int64_t *nanoseconds) {
  size_t at = 0;
  const bool negative = text.len > 0 && text.ptr[0] == '-';
  at = text.len > 0 && (text.ptr[0] == '-' || text.ptr[0] == '+') ? 1 : 0;
  if (ms_span_equal(ms_span_of(text.ptr + at, text.len - at), ms_span_of_text("0"))) {
    *nanoseconds = 0;
    return true;
  }
  if (at >= text.len) {
    return false;
  }
  int64_t total = 0;
  while (at < text.len) {
    if (!component(text, &at, &total)) {
      return false;
    }
  }
  *nanoseconds = negative ? -total : total;
  return true;
}

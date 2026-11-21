/* base/fmt.c: integers to text: decimal and radix. Floats are in fmt_float.c and fmt_precision.c. */
#include "base/fmt.h"
#include "base/fmt_sink.h"

bool ms_fmt_u64(uint64_t value, uint8_t *out, size_t capacity, size_t *length) {
  MsFmtSink sink = ms_fmt_sink_new(out, capacity);
  ms_fmt_sink_put_unsigned(&sink, value);
  return ms_fmt_sink_finish(&sink, length);
}

size_t ms_fmt_i64_fixed(int64_t value, uint8_t out[static MS_FMT_INTEGER_CAPACITY]) {
  const bool negative = value < 0;
  out[0] = '-'; /* overwritten by the first digit of a value that is not negative */
  /* The magnitude of INT64_MIN is 2^63, which only the unsigned negation represents. */
  const uint64_t magnitude = negative ? UINT64_C(0) - (uint64_t)value : (uint64_t)value;
  size_t written = 0;
  /* The room is the capacity less the sign, which holds the 19 digits of a magnitude below 2^63 and the 20 of
   * a UInt64 never written here. */
  const MsSpanMut room =
      ms_span_mut_of(out + (negative ? 1 : 0), MS_FMT_INTEGER_CAPACITY - (negative ? 1 : 0));
  const bool fitted = ms_fmt_write_decimal(room, magnitude, &written);
  (void)fitted; /* a magnitude of at most 2^63 has at most 19 digits */
  return written + (negative ? 1 : 0);
}

bool ms_fmt_i64(int64_t value, uint8_t *out, size_t capacity, size_t *length) {
  MsFmtSink sink = ms_fmt_sink_new(out, capacity);
  ms_fmt_sink_put_signed(&sink, value);
  return ms_fmt_sink_finish(&sink, length);
}

#define MS_RADIX_MIN 2
#define MS_RADIX_MAX 36
#define MS_RADIX_DIGITS 64

bool ms_fmt_radix(uint64_t magnitude, uint32_t radix, uint8_t negative, uint8_t *out, size_t capacity,
                  size_t *length) {
  if (radix < MS_RADIX_MIN || radix > MS_RADIX_MAX) {
    return false;
  }
  uint8_t reversed[MS_RADIX_DIGITS] = {0}; /* a UInt64 has at most 64 binary digits */
  size_t count = 0;
  do {
    const uint32_t digit = (uint32_t)(magnitude % radix);
    reversed[count] = (uint8_t)(digit < 10 ? '0' + digit : 'a' + (digit - 10));
    count++;
    magnitude /= radix;
  } while (magnitude != 0 && count < MS_COUNT_OF(reversed));
  MsFmtSink sink = ms_fmt_sink_new(out, capacity);
  if (negative != 0) {
    ms_fmt_sink_put_byte(&sink, '-');
  }
  while (count > 0) {
    count--;
    ms_fmt_sink_put_byte(&sink, reversed[count]);
  }
  return ms_fmt_sink_finish(&sink, length);
}

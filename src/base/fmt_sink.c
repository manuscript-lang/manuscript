/* base/fmt_sink.c: the output sink and the decimal digit writer behind every number formatter. */
#include "base/fmt_sink.h"

MsFmtSink ms_fmt_sink_new(uint8_t *out, size_t capacity) {
  return (MsFmtSink){.buffer = ms_span_mut_of(out, capacity), .length = 0, .overflowed = false};
}

void ms_fmt_sink_put(MsFmtSink *sink, MsSpan bytes) {
  if (sink->overflowed) {
    return;
  }
  MsSpanMut room = {0};
  if (!ms_span_mut_slice(sink->buffer, sink->length, sink->buffer.len, &room) || !ms_span_copy(room, bytes)) {
    sink->overflowed = true;
    return;
  }
  sink->length += bytes.len; /* the copy fit, so this stays within buffer.len */
}

void ms_fmt_sink_put_byte(MsFmtSink *sink, uint8_t byte) {
  if (sink->overflowed || sink->length >= sink->buffer.len) {
    sink->overflowed = true;
    return;
  }
  sink->buffer.ptr[sink->length] = byte;
  sink->length++;
}

void ms_fmt_sink_put_text(MsFmtSink *sink, const char *text) {
  for (const char *c = text; *c != '\0'; c++) {
    ms_fmt_sink_put_byte(sink, (uint8_t)*c);
  }
}

void ms_fmt_sink_put_zeros(MsFmtSink *sink, size_t count) {
  for (size_t i = 0; i < count; i++) {
    ms_fmt_sink_put_byte(sink, '0');
  }
}

/* Reports the sink as the entry points do: true with the length written, or false when anything overflowed.
 */
MS_NODISCARD bool ms_fmt_sink_finish(const MsFmtSink *sink, size_t *length) {
  if (sink->overflowed) {
    return false;
  }
  *length = sink->length;
  return true;
}

/* ---- decimal digits ---- */

#define MS_U64_DIGITS 20

static const char decimal_pairs[] = "0001020304050607080910111213141516171819"
                                    "2021222324252627282930313233343536373839"
                                    "4041424344454647484950515253545556575859"
                                    "6061626364656667686970717273747576777879"
                                    "8081828384858687888990919293949596979899";
_Static_assert(sizeof decimal_pairs == 201, "two digits for each of 0..99 and the terminator");

static const uint64_t powers_of_ten[MS_U64_DIGITS] = {
    UINT64_C(1),
    UINT64_C(10),
    UINT64_C(100),
    UINT64_C(1000),
    UINT64_C(10000),
    UINT64_C(100000),
    UINT64_C(1000000),
    UINT64_C(10000000),
    UINT64_C(100000000),
    UINT64_C(1000000000),
    UINT64_C(10000000000),
    UINT64_C(100000000000),
    UINT64_C(1000000000000),
    UINT64_C(10000000000000),
    UINT64_C(100000000000000),
    UINT64_C(1000000000000000),
    UINT64_C(10000000000000000),
    UINT64_C(100000000000000000),
    UINT64_C(1000000000000000000),
    UINT64_C(10000000000000000000),
};

/* How many decimal digits `value` has, 1..=20. A value with `bits` significant bits has about bits * log10(2)
 * digits; `estimate` is that rounded down, so it is the digit count minus one, or equal to it when the value
 * is below 10^estimate (Hacker's Delight, "Integer Log"). `estimate` is at most 19 for 64 bits, inside the
 * table. */
size_t ms_fmt_decimal_length(uint64_t value) {
  const uint64_t nonzero =
      value | 1; /* clz of 0 is undefined; 0 and 1 both have one digit, and the powers are even */
  const unsigned bits = 64 - (unsigned)__builtin_clzll(nonzero);
  const size_t estimate = ((size_t)bits * 1233) >> 12;
  return estimate + (nonzero >= powers_of_ten[estimate] ? 1 : 0);
}

/* Writes the decimal digits of `value` at the start of `room`, two digits at a time from the end, and returns
 * how many. The length is checked against the room once; `position` then stays inside it because it starts at
 * the digit count and each step removes the digits it writes. */
MS_NODISCARD bool ms_fmt_write_decimal(MsSpanMut room, uint64_t value, size_t *written) {
  const size_t length = ms_fmt_decimal_length(value);
  if (room.ptr == NULL || length > room.len) {
    return false;
  }
  size_t position = length;
  while (value >= 100) {
    const size_t pair = (size_t)(value % 100) * 2;
    value /= 100;
    position -= 2;
    room.ptr[position] = (uint8_t)decimal_pairs[pair];
    room.ptr[position + 1] = (uint8_t)decimal_pairs[pair + 1];
  }
  if (value >= 10) {
    const size_t pair = (size_t)value * 2;
    room.ptr[0] = (uint8_t)decimal_pairs[pair];
    room.ptr[1] = (uint8_t)decimal_pairs[pair + 1];
  } else {
    room.ptr[0] = (uint8_t)('0' + value);
  }
  *written = length;
  return true;
}

/* The room left in the sink's buffer. */
static MsSpanMut sink_room(const MsFmtSink *sink) {
  MsSpanMut room = {0};
  if (!ms_span_mut_slice(sink->buffer, sink->length, sink->buffer.len, &room)) {
    return ms_span_mut_of(NULL, 0);
  }
  return room;
}

void ms_fmt_sink_put_unsigned(MsFmtSink *sink, uint64_t value) {
  size_t written = 0;
  if (sink->overflowed || !ms_fmt_write_decimal(sink_room(sink), value, &written)) {
    sink->overflowed = true;
    return;
  }
  sink->length += written; /* ms_fmt_write_decimal stayed within the room */
}

void ms_fmt_sink_put_signed(MsFmtSink *sink, int64_t value) {
  if (value < 0) {
    ms_fmt_sink_put_byte(sink, '-');
  }
  /* The magnitude of INT64_MIN is 2^63, which only the unsigned negation represents. */
  ms_fmt_sink_put_unsigned(sink, value < 0 ? UINT64_C(0) - (uint64_t)value : (uint64_t)value);
}

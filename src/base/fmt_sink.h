/* base/fmt_sink.h: the output sink of the number formatters (fmt*.c; not for other callers).
 *
 * Bytes are appended until the caller's buffer is full. A write that does not fit sets `overflowed` and every
 * later write does nothing, so a formatter writes straight through and the entry point checks once at the
 * end. */
#ifndef MS_BASE_FMT_SINK_H
#define MS_BASE_FMT_SINK_H

#include "base/fmt.h"

typedef struct MsFmtSink {
  MsSpanMut buffer; /* borrowed from the caller */
  size_t length;    /* bytes written so far, at most buffer.len */
  bool overflowed;
} MsFmtSink;

MsFmtSink ms_fmt_sink_new(uint8_t *out, size_t capacity);
void ms_fmt_sink_put(MsFmtSink *sink, MsSpan bytes);
void ms_fmt_sink_put_byte(MsFmtSink *sink, uint8_t byte);
void ms_fmt_sink_put_text(MsFmtSink *sink, const char *text);
void ms_fmt_sink_put_zeros(MsFmtSink *sink, size_t count);
void ms_fmt_sink_put_unsigned(MsFmtSink *sink, uint64_t value);
void ms_fmt_sink_put_signed(MsFmtSink *sink, int64_t value);

/* Reports the sink as the entry points do: true with the length written, or false when anything overflowed.
 */
MS_NODISCARD bool ms_fmt_sink_finish(const MsFmtSink *sink, size_t *length);

/* Writes the decimal digits of `value` at the start of `room`; false when they do not fit. */
MS_NODISCARD bool ms_fmt_write_decimal(MsSpanMut room, uint64_t value, size_t *written);

/* How many decimal digits `value` has, 1..=20. */
size_t ms_fmt_decimal_length(uint64_t value);

/* The bits of a double. */
uint64_t ms_fmt_double_bits(double value);

/* Plain notation: the digits with the decimal point placed by `exponent`, the exponent of the first digit. */
void ms_fmt_put_plain(MsFmtSink *sink, MsSpan digits, int exponent);

/* The shortest text of a Float (sign, NaN and the infinities included); false when the sink overflowed. */
bool ms_fmt_put_float(MsFmtSink *sink, double value);

/* Exponents written in plain notation by the float forms: -6 up to this one. */
#define MS_FMT_PLAIN_EXPONENT_MIN (-6)
#define MS_FMT_SIGN_BIT_64 (UINT64_C(1) << 63)

#endif

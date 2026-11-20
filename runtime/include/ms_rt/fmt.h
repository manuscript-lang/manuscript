/* ms_rt/fmt.h: number to text, written into a caller's buffer (runtime/core/fmt.c). Nothing allocates; each
 * returns the byte count. These are runtime-internal: the string natives and the JSON encoder call them. */
#ifndef MS_RT_FMT_H
#define MS_RT_FMT_H

#include "ms_rt/base.h"

/* Decimal; out holds at least 20 bytes. */
size_t msrt_fmt_u64(uint64_t n, uint8_t *out);
size_t msrt_fmt_i64(int64_t v, uint8_t *out);
/* Lowercase digits in radix 2..=36 of the magnitude n, with a leading '-' when negative is set; out holds at least 65. */
size_t msrt_fmt_radix(uint64_t n, uint32_t radix, uint8_t negative, uint8_t *out);
/* Float.to_string: the shortest text that reads back as the same value; out holds at least 40 bytes. */
size_t msrt_fmt_float(double v, uint8_t *out);
/* Float32.to_string for a value a Float32 register holds as a double; out holds at least 40 bytes. */
size_t msrt_fmt_float32(double v, uint8_t *out);
/* to_precision ('g'), to_exponential ('e') and to_fixed ('f') with digits in 0..=100 ('g': 1..=100); out holds
 * at least 160 bytes. Rounds half to even on the exact value. */
size_t msrt_fmt_float_precision(double v, uint8_t format, int64_t digits, uint8_t *out);

#endif

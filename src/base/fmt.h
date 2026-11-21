/* base/fmt.h: number to text, written into a caller's buffer (fmt.c, fmt_float.c, fmt_precision.c). Nothing
 * allocates.
 *
 * Every function takes the buffer and its capacity and reports through `length` how many bytes it wrote. It
 * returns false, leaving `length` untouched, when the text does not fit or an argument is out of range; the
 * buffer contents are then unspecified. The capacities below always suffice for valid arguments. One copy
 * serves string interpolation, to_string, the compiler and the JSON encoder; the text is byte-identical to
 * the Rust runtime's. */
#ifndef MS_BASE_FMT_H
#define MS_BASE_FMT_H

#include "base/safe.h"

/* The longest text of each kind: a UInt64 or an Int with its sign, an Int in radix 2 with its sign, a Float
 * or a Float32 (a sign, 17 digits, up to 20 zeros or 6 leading ones, a point or an exponent), and the
 * precision forms of a value below 1e21 with 100 digits. */
#define MS_FMT_INTEGER_CAPACITY 20
#define MS_FMT_RADIX_CAPACITY 65
#define MS_FMT_FLOAT_CAPACITY 40
#define MS_FMT_PRECISION_CAPACITY 160

/* Decimal. */
MS_NODISCARD bool ms_fmt_u64(uint64_t value, uint8_t *out, size_t capacity, size_t *length);
MS_NODISCARD bool ms_fmt_i64(int64_t value, uint8_t *out, size_t capacity, size_t *length);

/* The decimal text of `value` at the start of `out`, and its length. It needs no capacity check, since the
 * buffer holds the longest Int. */
MS_NONNULL size_t ms_fmt_i64_fixed(int64_t value, uint8_t out[static MS_FMT_INTEGER_CAPACITY]);

/* Lowercase digits in radix 2..=36 of the magnitude, with a leading '-' when `negative` is set. */
MS_NODISCARD bool ms_fmt_radix(uint64_t magnitude, uint32_t radix, uint8_t negative, uint8_t *out,
                               size_t capacity, size_t *length);

/* Float.to_string: the shortest text that reads back as the same value. */
MS_NODISCARD bool ms_fmt_float(double value, uint8_t *out, size_t capacity, size_t *length);

/* Float32.to_string for a value a Float32 register holds as a double. */
MS_NODISCARD bool ms_fmt_float32(double value, uint8_t *out, size_t capacity, size_t *length);

/* to_precision ('g', digits 1..=100), to_exponential ('e') and to_fixed ('f') with digits 0..=100. Rounds
 * half to even on the exact value. */
MS_NODISCARD bool ms_fmt_float_precision(double value, uint8_t format, int64_t digits, uint8_t *out,
                                         size_t capacity, size_t *length);

#endif

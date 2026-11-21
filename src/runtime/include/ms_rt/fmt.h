/* ms_rt/fmt.h: number to text, written into a caller's buffer (src/runtime/core/fmt.c). Nothing allocates.
 *
 * Every function takes the buffer and its capacity and reports through `length` how many bytes it wrote. It
 * returns false, leaving `length` untouched, when the text does not fit or an argument is out of range; the
 * buffer contents are then unspecified. The capacities below always suffice for valid arguments.
 * These are runtime-internal: the string natives and the JSON encoder call them.
 */
#ifndef MS_RT_FMT_H
#define MS_RT_FMT_H

/* ms: domain number */

#include "ms_rt/safe.h"

/* The longest text of each kind: a UInt64 or an Int with its sign, an Int in radix 2 with its sign, a Float or a
 * Float32 (a sign, 17 digits, up to 20 zeros or 6 leading ones, a point or an exponent), and the precision forms
 * of a value below 1e21 with 100 digits. */
#define MS_FMT_INTEGER_CAPACITY 20
#define MS_FMT_RADIX_CAPACITY 65
#define MS_FMT_FLOAT_CAPACITY 40
#define MS_FMT_PRECISION_CAPACITY 160

/* Decimal. */
/* ms-sig: msrt_fmt_u64(value: u64, out: *mut u8, capacity: usize, length: *mut usize) -> bool */
MS_NODISCARD bool msrt_fmt_u64(uint64_t value, uint8_t *out, size_t capacity, size_t *length);
/* ms-sig: msrt_fmt_i64(value: i64, out: *mut u8, capacity: usize, length: *mut usize) -> bool */
MS_NODISCARD bool msrt_fmt_i64(int64_t value, uint8_t *out, size_t capacity, size_t *length);
/* Lowercase digits in radix 2..=36 of the magnitude, with a leading '-' when `negative` is set. */
/* ms-sig: msrt_fmt_radix(magnitude: u64, radix: u32, negative: u8, out: *mut u8, capacity: usize, length: *mut usize) -> bool */
MS_NODISCARD bool msrt_fmt_radix(uint64_t magnitude, uint32_t radix, uint8_t negative, uint8_t *out, size_t capacity, size_t *length);
/* Float.to_string: the shortest text that reads back as the same value. */
/* ms-sig: msrt_fmt_float(value: f64, out: *mut u8, capacity: usize, length: *mut usize) -> bool */
MS_NODISCARD bool msrt_fmt_float(double value, uint8_t *out, size_t capacity, size_t *length);
/* Float32.to_string for a value a Float32 register holds as a double. */
/* ms-sig: msrt_fmt_float32(value: f64, out: *mut u8, capacity: usize, length: *mut usize) -> bool */
MS_NODISCARD bool msrt_fmt_float32(double value, uint8_t *out, size_t capacity, size_t *length);
/* to_precision ('g', digits 1..=100), to_exponential ('e') and to_fixed ('f') with digits 0..=100. Rounds half
 * to even on the exact value. */
/* ms-sig: msrt_fmt_float_precision(value: f64, format: u8, digits: i64, out: *mut u8, capacity: usize, length: *mut usize) -> bool */
MS_NODISCARD bool msrt_fmt_float_precision(double value, uint8_t format, int64_t digits, uint8_t *out, size_t capacity, size_t *length);

#endif

/* runtime/core/bits.h: the integer bit operations of @std/math (bits.c). Generated code inlines the ones that
 * carry an `@op`; the others are calls. */
#ifndef MS_RUNTIME_CORE_BITS_H
#define MS_RUNTIME_CORE_BITS_H

#include "base/safe.h"

/* ms-sig: msrt_bits_bit_and(left: i64, right: i64) -> i64 @op=and */
int64_t msrt_bits_bit_and(int64_t left, int64_t right);
/* ms-sig: msrt_bits_bit_or(left: i64, right: i64) -> i64 @op=or */
int64_t msrt_bits_bit_or(int64_t left, int64_t right);
/* ms-sig: msrt_bits_bit_xor(left: i64, right: i64) -> i64 @op=xor */
int64_t msrt_bits_bit_xor(int64_t left, int64_t right);
/* ms-sig: msrt_bits_shift_left(value: i64, count: i64) -> i64 @op=shl */
int64_t msrt_bits_shift_left(int64_t value, int64_t count);
/* ms-sig: msrt_bits_shift_right(value: i64, count: i64) -> i64 @op=sshr */
int64_t msrt_bits_shift_right(int64_t value, int64_t count);
/* ms-sig: msrt_bits_shift_right_unsigned(value: i64, count: i64) -> i64 @op=ushr */
int64_t msrt_bits_shift_right_unsigned(int64_t value, int64_t count);
/* ms-sig: msrt_bits_rotate_left(value: i64, count: i64) -> i64 @op=rotl */
int64_t msrt_bits_rotate_left(int64_t value, int64_t count);
/* ms-sig: msrt_bits_rotate_right(value: i64, count: i64) -> i64 @op=rotr */
int64_t msrt_bits_rotate_right(int64_t value, int64_t count);
/* ms-sig: msrt_bits_count_ones(value: i64) -> i64 @op=popcnt */
int64_t msrt_bits_count_ones(int64_t value);
/* ms-sig: msrt_bits_leading_zeros(value: i64) -> i64 @op=clz */
int64_t msrt_bits_leading_zeros(int64_t value);
/* ms-sig: msrt_bits_trailing_zeros(value: i64) -> i64 @op=ctz */
int64_t msrt_bits_trailing_zeros(int64_t value);
/* ms-sig: msrt_bits_wrapping_add(left: i64, right: i64) -> i64 @op=iadd */
int64_t msrt_bits_wrapping_add(int64_t left, int64_t right);
/* ms-sig: msrt_bits_wrapping_subtract(left: i64, right: i64) -> i64 @op=isub */
int64_t msrt_bits_wrapping_subtract(int64_t left, int64_t right);
/* ms-sig: msrt_bits_wrapping_multiply(left: i64, right: i64) -> i64 @op=imul */
int64_t msrt_bits_wrapping_multiply(int64_t left, int64_t right);

#endif

/* ms_rt/bits.h: integer bit operations of @std/math (src/runtime/core/bits.c). Each is one MIR instruction (`op=`), which
 * lowering emits in place of the call. Shifts fault outside 0 through 63; rotations take the count modulo 64; the
 * wrapping operations never fault. */
#ifndef MS_RT_BITS_H
#define MS_RT_BITS_H

#include "ms_rt/base.h"

/* ms-sig: msrt_bits_bit_and(left: i64, right: i64) -> i64 @leaf @op=and */
int64_t msrt_bits_bit_and(int64_t left, int64_t right);
/* ms-sig: msrt_bits_bit_or(left: i64, right: i64) -> i64 @leaf @op=or */
int64_t msrt_bits_bit_or(int64_t left, int64_t right);
/* ms-sig: msrt_bits_bit_xor(left: i64, right: i64) -> i64 @leaf @op=xor */
int64_t msrt_bits_bit_xor(int64_t left, int64_t right);
/* ms-sig: msrt_bits_shift_left(value: i64, count: i64) -> i64 @leaf @op=shl */
int64_t msrt_bits_shift_left(int64_t value, int64_t count);
/* ms-sig: msrt_bits_shift_right(value: i64, count: i64) -> i64 @leaf @op=sshr */
int64_t msrt_bits_shift_right(int64_t value, int64_t count);
/* ms-sig: msrt_bits_shift_right_unsigned(value: i64, count: i64) -> i64 @leaf @op=ushr */
int64_t msrt_bits_shift_right_unsigned(int64_t value, int64_t count);
/* ms-sig: msrt_bits_rotate_left(value: i64, count: i64) -> i64 @leaf @op=rotl */
int64_t msrt_bits_rotate_left(int64_t value, int64_t count);
/* ms-sig: msrt_bits_rotate_right(value: i64, count: i64) -> i64 @leaf @op=rotr */
int64_t msrt_bits_rotate_right(int64_t value, int64_t count);
/* ms-sig: msrt_bits_count_ones(value: i64) -> i64 @leaf @op=popcnt */
int64_t msrt_bits_count_ones(int64_t value);
/* ms-sig: msrt_bits_leading_zeros(value: i64) -> i64 @leaf @op=clz */
int64_t msrt_bits_leading_zeros(int64_t value);
/* ms-sig: msrt_bits_trailing_zeros(value: i64) -> i64 @leaf @op=ctz */
int64_t msrt_bits_trailing_zeros(int64_t value);
/* ms-sig: msrt_bits_wrapping_add(left: i64, right: i64) -> i64 @leaf @op=iadd */
int64_t msrt_bits_wrapping_add(int64_t left, int64_t right);
/* ms-sig: msrt_bits_wrapping_subtract(left: i64, right: i64) -> i64 @leaf @op=isub */
int64_t msrt_bits_wrapping_subtract(int64_t left, int64_t right);
/* ms-sig: msrt_bits_wrapping_multiply(left: i64, right: i64) -> i64 @leaf @op=imul */
int64_t msrt_bits_wrapping_multiply(int64_t left, int64_t right);

#endif

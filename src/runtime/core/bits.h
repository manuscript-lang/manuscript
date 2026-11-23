/* runtime/core/bits.h: the integer bit operations of @std/math (bits.c). Generated code inlines the ones that
 * carry an `@op`; the others are calls. */
#ifndef MS_RUNTIME_CORE_BITS_H
#define MS_RUNTIME_CORE_BITS_H

#include "base/safe.h"

/* ms-op: msrt_bits_bit_and and */
int64_t msrt_bits_bit_and(int64_t left, int64_t right);
/* ms-op: msrt_bits_bit_or or */
int64_t msrt_bits_bit_or(int64_t left, int64_t right);
/* ms-op: msrt_bits_bit_xor xor */
int64_t msrt_bits_bit_xor(int64_t left, int64_t right);
/* ms-op: msrt_bits_shift_left shl */
int64_t msrt_bits_shift_left(int64_t value, int64_t count);
/* ms-op: msrt_bits_shift_right sshr */
int64_t msrt_bits_shift_right(int64_t value, int64_t count);
/* ms-op: msrt_bits_shift_right_unsigned ushr */
int64_t msrt_bits_shift_right_unsigned(int64_t value, int64_t count);
/* ms-op: msrt_bits_rotate_left rotl */
int64_t msrt_bits_rotate_left(int64_t value, int64_t count);
/* ms-op: msrt_bits_rotate_right rotr */
int64_t msrt_bits_rotate_right(int64_t value, int64_t count);
/* ms-op: msrt_bits_count_ones popcnt */
int64_t msrt_bits_count_ones(int64_t value);
/* ms-op: msrt_bits_leading_zeros clz */
int64_t msrt_bits_leading_zeros(int64_t value);
/* ms-op: msrt_bits_trailing_zeros ctz */
int64_t msrt_bits_trailing_zeros(int64_t value);
/* ms-op: msrt_bits_wrapping_add iadd */
int64_t msrt_bits_wrapping_add(int64_t left, int64_t right);
/* ms-op: msrt_bits_wrapping_subtract isub */
int64_t msrt_bits_wrapping_subtract(int64_t left, int64_t right);
/* ms-op: msrt_bits_wrapping_multiply imul */
int64_t msrt_bits_wrapping_multiply(int64_t left, int64_t right);

#endif

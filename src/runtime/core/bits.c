/* runtime/core/bits.c: the integer bit operations of @std/math. */
#include "base/strbuild.h"
#include "runtime/core/bits.h"
#include "runtime/core/fault.h"

/* Faults unless `count` is a valid shift count (0 through 63). */
static unsigned shift_count(const char *operation, int64_t count) {
  if (count < 0 || count > 63) {
    MsStrBuild message = ms_strbuild_new();
    ms_strbuild_append_text(&message, operation);
    ms_strbuild_append_text(&message, ": count must be between 0 and 63, found ");
    ms_strbuild_append_i64(&message, count);
    ms_fault(MS_FAULT_KIND_FAULT, ms_strbuild_span(&message));
  }
  return (unsigned)count;
}

/* Rotations take the count modulo 64, negative counts rotating the other way. */
static unsigned rotation(int64_t count) {
  return (unsigned)((uint64_t)count & 63U);
}

int64_t msrt_bits_bit_and(int64_t left, int64_t right) {
  return left & right;
}

int64_t msrt_bits_bit_or(int64_t left, int64_t right) {
  return left | right;
}

int64_t msrt_bits_bit_xor(int64_t left, int64_t right) {
  return left ^ right;
}

int64_t msrt_bits_shift_left(int64_t value, int64_t count) {
  return (int64_t)((uint64_t)value << shift_count("shift_left", count));
}

int64_t msrt_bits_shift_right(int64_t value, int64_t count) {
  const unsigned n = shift_count("shift_right", count);
  return value < 0 ? ~(~value >> n)
                   : value >> n; /* arithmetic, whatever the compiler does with >> on negatives */
}

int64_t msrt_bits_shift_right_unsigned(int64_t value, int64_t count) {
  return (int64_t)((uint64_t)value >> shift_count("shift_right_unsigned", count));
}

int64_t msrt_bits_rotate_left(int64_t value, int64_t count) {
  const unsigned n = rotation(count);
  const uint64_t v = (uint64_t)value;
  return (int64_t)(n == 0 ? v : (v << n) | (v >> (64 - n)));
}

int64_t msrt_bits_rotate_right(int64_t value, int64_t count) {
  const unsigned n = rotation(count);
  const uint64_t v = (uint64_t)value;
  return (int64_t)(n == 0 ? v : (v >> n) | (v << (64 - n)));
}

int64_t msrt_bits_count_ones(int64_t value) {
  return __builtin_popcountll((uint64_t)value);
}

int64_t msrt_bits_leading_zeros(int64_t value) {
  return value == 0 ? 64 : __builtin_clzll((uint64_t)value);
}

int64_t msrt_bits_trailing_zeros(int64_t value) {
  return value == 0 ? 64 : __builtin_ctzll((uint64_t)value);
}

int64_t msrt_bits_wrapping_add(int64_t left, int64_t right) {
  return (int64_t)((uint64_t)left + (uint64_t)right);
}

int64_t msrt_bits_wrapping_subtract(int64_t left, int64_t right) {
  return (int64_t)((uint64_t)left - (uint64_t)right);
}

int64_t msrt_bits_wrapping_multiply(int64_t left, int64_t right) {
  return (int64_t)((uint64_t)left * (uint64_t)right);
}

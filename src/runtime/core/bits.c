/* Integer bit operations of @std/math. See ms_rt/bits.h. */
#include "ms_rt/bits.h"

#include <stdio.h>

#include "rt_calls.h"

/* Faults unless `count` is a valid shift count (0 through 63). */
static unsigned shift_count(const char *operation, int64_t count) {
    if (count < 0 || count > 63) {
        char message[128];
        const int length =
            snprintf(message, sizeof message, "%s: count must be between 0 and 63, found %lld", operation, (long long)count);
        msrt_fault((const uint8_t *)message, (size_t)length);
    }
    return (unsigned)count;
}

/* Rotations take the count modulo 64, negative counts rotating the other way. */
static unsigned rotation(int64_t count) { return (unsigned)((uint64_t)count & 63U); }

int64_t msrt_bits_bit_and(int64_t left, int64_t right) { return left & right; }
int64_t msrt_bits_bit_or(int64_t left, int64_t right) { return left | right; }
int64_t msrt_bits_bit_xor(int64_t left, int64_t right) { return left ^ right; }

int64_t msrt_bits_shift_left(int64_t value, int64_t count) {
    return (int64_t)((uint64_t)value << shift_count("shift_left", count));
}

int64_t msrt_bits_shift_right(int64_t value, int64_t count) {
    const unsigned n = shift_count("shift_right", count);
    return value < 0 ? ~(~value >> n) : value >> n; /* arithmetic, whatever the compiler does with >> on negatives */
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

int64_t msrt_bits_count_ones(int64_t value) { return __builtin_popcountll((uint64_t)value); }
int64_t msrt_bits_leading_zeros(int64_t value) { return value == 0 ? 64 : __builtin_clzll((uint64_t)value); }
int64_t msrt_bits_trailing_zeros(int64_t value) { return value == 0 ? 64 : __builtin_ctzll((uint64_t)value); }

int64_t msrt_bits_wrapping_add(int64_t left, int64_t right) { return (int64_t)((uint64_t)left + (uint64_t)right); }
int64_t msrt_bits_wrapping_subtract(int64_t left, int64_t right) { return (int64_t)((uint64_t)left - (uint64_t)right); }
int64_t msrt_bits_wrapping_multiply(int64_t left, int64_t right) { return (int64_t)((uint64_t)left * (uint64_t)right); }

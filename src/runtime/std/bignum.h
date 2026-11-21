/* Arbitrary-precision integers for the BigInt and Decimal natives (src/runtime/std/bignum.c), on OpenSSL's BIGNUM.
 *
 * A MsBig owns a BIGNUM, or none for zero. Every operation computes its result in fresh memory when it would
 * overlap an operand, so `out` may be the same object as an operand, and the previous contents of `out` are
 * released. A MsBig must be initialised (MS_BIG_ZERO or the result of an earlier call) and released with
 * ms_big_free. An exhausted allocator faults, so no function here reports an allocation failure.
 *
 * Division truncates toward zero, shifts round toward negative infinity and the bitwise operations act on the
 * infinite two's complement form, as Manuscript's BigInt defines them. BIGNUM has no bitwise operations on
 * negative values, floor shifts, integer square roots, doubles or two's complement, so bignum.c adds those.
 */
#ifndef MS_STD_BIGNUM_H
#define MS_STD_BIGNUM_H

#include <openssl/bn.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "ms_rt/runtime.h"

typedef struct MsBig {
    BIGNUM *bn; /* owned; NULL for zero */
} MsBig;

#define MS_BIG_ZERO ((MsBig){.bn = NULL})

/* The digits of a radix in 2..36, lowercase; also the validity table of ms_big_digit_value. */
#define MS_BIG_MIN_RADIX 2u
#define MS_BIG_MAX_RADIX 36u

void ms_big_free(MsBig *x) MS_NONNULL;
void ms_big_copy(MsBig *out, const MsBig *a) MS_NONNULL;
void ms_big_set_u64(MsBig *out, uint64_t value) MS_NONNULL;
void ms_big_set_i64(MsBig *out, int64_t value) MS_NONNULL;
/* out = magnitude * (negative ? -1 : 1) for a 128-bit magnitude given as two limbs. */
void ms_big_set_u128(MsBig *out, uint64_t high, uint64_t low, bool negative) MS_NONNULL;

bool ms_big_is_zero(const MsBig *a) MS_NONNULL;
/* -1, 0 or 1. */
int ms_big_sign(const MsBig *a) MS_NONNULL;
int ms_big_cmp(const MsBig *a, const MsBig *b) MS_NONNULL;
int ms_big_cmp_abs(const MsBig *a, const MsBig *b) MS_NONNULL;
bool ms_big_is_odd(const MsBig *a) MS_NONNULL;
/* Number of bits of the magnitude; 0 for zero. */
size_t ms_big_bit_length(const MsBig *a) MS_NONNULL;
/* The bit at `index` of the magnitude. */
bool ms_big_magnitude_bit(const MsBig *a, size_t index) MS_NONNULL;

void ms_big_negate(MsBig *out, const MsBig *a) MS_NONNULL;
void ms_big_abs(MsBig *out, const MsBig *a) MS_NONNULL;
void ms_big_add(MsBig *out, const MsBig *a, const MsBig *b) MS_NONNULL;
void ms_big_sub(MsBig *out, const MsBig *a, const MsBig *b) MS_NONNULL;
void ms_big_mul(MsBig *out, const MsBig *a, const MsBig *b) MS_NONNULL;
/* Quotient (toward zero) and remainder (the dividend's sign); b must be nonzero. Either output may be NULL. */
void ms_big_divmod(MsBig *quotient, MsBig *remainder, const MsBig *a, const MsBig *b);
/* The remainder in 0..|m|-1 (floor modulo for a positive m); m must be nonzero. */
void ms_big_mod_floor(MsBig *out, const MsBig *a, const MsBig *m) MS_NONNULL;
void ms_big_shift_left(MsBig *out, const MsBig *a, size_t count) MS_NONNULL;
/* Rounds toward negative infinity. */
void ms_big_shift_right(MsBig *out, const MsBig *a, size_t count) MS_NONNULL;
void ms_big_and(MsBig *out, const MsBig *a, const MsBig *b) MS_NONNULL;
void ms_big_or(MsBig *out, const MsBig *a, const MsBig *b) MS_NONNULL;
void ms_big_xor(MsBig *out, const MsBig *a, const MsBig *b) MS_NONNULL;
void ms_big_not(MsBig *out, const MsBig *a) MS_NONNULL;
/* a^exponent; the caller bounds the size of the result. */
void ms_big_pow(MsBig *out, const MsBig *a, uint64_t exponent) MS_NONNULL;
/* 10^exponent. */
void ms_big_pow10(MsBig *out, size_t exponent) MS_NONNULL;
/* floor(sqrt(a)); a must not be negative. */
void ms_big_sqrt(MsBig *out, const MsBig *a) MS_NONNULL;
/* Greatest common divisor of the magnitudes; never negative. */
void ms_big_gcd(MsBig *out, const MsBig *a, const MsBig *b) MS_NONNULL;
/* a^exponent mod modulus in 0..modulus-1; exponent must not be negative and modulus must be positive. */
void ms_big_pow_mod(MsBig *out, const MsBig *a, const MsBig *exponent, const MsBig *modulus) MS_NONNULL;
/* The x in 0..modulus-1 with a*x = 1 (mod modulus); false, leaving `out`, when none exists. modulus > 1. */
MS_NODISCARD bool ms_big_inverse_mod(MsBig *out, const MsBig *a, const MsBig *modulus) MS_NONNULL;

/* The nearest double, ties to even; infinity of the same sign beyond the range. */
double ms_big_to_double(const MsBig *a) MS_NONNULL;
/* Stores the magnitude as two limbs and returns true when it fits in 128 bits (the sign is the caller's). */
MS_NODISCARD bool ms_big_to_u128(const MsBig *a, uint64_t *high, uint64_t *low) MS_NONNULL;
/* Stores the value and returns true when it fits an int64_t. */
MS_NODISCARD bool ms_big_to_i64(const MsBig *a, int64_t *out) MS_NONNULL;

/* The value of one digit character in radix 36 (0-9, a-z, A-Z), or 255 for any other byte. */
uint8_t ms_big_digit_value(uint8_t byte);
/* Parses digits of `radix` (2..36) that the caller has checked are all valid; `digits` has no sign. */
void ms_big_parse_digits(MsBig *out, MsBytes digits, unsigned radix) MS_NONNULL_ARGS(1);
/* Writes the magnitude in `radix` as lowercase digits into a new buffer from the runtime allocator (release it
 * with msrt_free) and stores the digit count; at least one digit, so zero is "0". The sign is not written. */
MS_NODISCARD MS_RETURNS_NONNULL uint8_t *ms_big_digits_new(const MsBig *a, unsigned radix, size_t *length) MS_NONNULL;

#endif

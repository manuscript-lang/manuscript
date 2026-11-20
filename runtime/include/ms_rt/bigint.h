/* ms_rt/bigint.h: the @std/math BigInt natives (runtime/std/bigint.c). A BigInt is a runtime object holding a
 * MsBig (runtime/std/bignum.h); every call borrows its BigInt arguments and returns new objects, so values are
 * immutable. Failures are the STATUS_* codes of ms-rt-abi; an out pointer is written only on success. */
#ifndef MS_RT_BIGINT_H
#define MS_RT_BIGINT_H

#include "ms_rt/base.h"
#include "ms_rt/runtime.h"
#include "ms_rt/string.h"

typedef struct MsBigCell MsBigCell;
MsBigCell *msstd_bigint_from_int(int64_t value);
MsBigCell *msstd_bigint_from_u64(int64_t value);
MsBigCell *msstd_bigint_from_seconds_nanos(int64_t seconds, int64_t nanoseconds);
uint8_t msstd_bigint_parse(const ms_str *text, int64_t radix, HasRaw has_max, int64_t max, MsBigCell **out);
MsBigCell *msstd_bigint_add(const MsBigCell *a, const MsBigCell *other);
MsBigCell *msstd_bigint_subtract(const MsBigCell *a, const MsBigCell *other);
MsBigCell *msstd_bigint_multiply(const MsBigCell *a, const MsBigCell *other);
MsBigCell *msstd_bigint_gcd(const MsBigCell *a, const MsBigCell *other);
MsBigCell *msstd_bigint_lcm(const MsBigCell *a, const MsBigCell *other);
uint8_t msstd_bigint_sqrt(const MsBigCell *a, MsBigCell **out);
uint8_t msstd_bigint_pow_mod(const MsBigCell *a, const MsBigCell *exponent, const MsBigCell *modulus, MsBigCell **out);
uint8_t msstd_bigint_inverse_mod(const MsBigCell *a, const MsBigCell *modulus, MsBigCell **out);
MsBigCell *msstd_bigint_bit_and(const MsBigCell *a, const MsBigCell *other);
MsBigCell *msstd_bigint_bit_or(const MsBigCell *a, const MsBigCell *other);
MsBigCell *msstd_bigint_bit_xor(const MsBigCell *a, const MsBigCell *other);
uint8_t msstd_bigint_divide(const MsBigCell *a, const MsBigCell *other, MsBigCell **out);
uint8_t msstd_bigint_remainder(const MsBigCell *a, const MsBigCell *other, MsBigCell **out);
MsBigCell *msstd_bigint_quotient(const MsBigCell *a, const MsBigCell *other);
MsBigCell *msstd_bigint_modulo(const MsBigCell *a, const MsBigCell *other);
int64_t msstd_bigint_compare(const MsBigCell *a, const MsBigCell *other);
MsBigCell *msstd_bigint_bit_not(const MsBigCell *a);
MsBigCell *msstd_bigint_negate(const MsBigCell *a);
MsBigCell *msstd_bigint_abs(const MsBigCell *a);
int64_t msstd_bigint_sign(const MsBigCell *a);
uint8_t msstd_bigint_pow(const MsBigCell *a, int64_t exponent, MsBigCell **out);
uint8_t msstd_bigint_shift_left(const MsBigCell *a, int64_t count, MsBigCell **out);
uint8_t msstd_bigint_shift_right(const MsBigCell *a, int64_t count, MsBigCell **out);
double msstd_bigint_to_float(const MsBigCell *a);
uint8_t msstd_bigint_to_int(const MsBigCell *a, int64_t *out);
void msstd_bigint_to_string_radix(const MsBigCell *a, int64_t radix, ms_str *out);
uint8_t msstd_bigint_equal(const MsBigCell *a, const MsBigCell *other);

#endif

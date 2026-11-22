/* runtime/std/bigint.h: the @std/math BigInt natives (src/runtime/std/bigint.c). A BigInt is a runtime object
 * holding a MsBig (src/runtime/std/bignum.h); every call borrows its BigInt arguments and returns new
 * objects, so values are immutable. Failures are the MS_STATUS_* codes of ms-rt-abi; an out pointer is
 * written only on success. */
#ifndef MS_RUNTIME_STD_BIGINT_H
#define MS_RUNTIME_STD_BIGINT_H

#include "abi/status.h"
#include "base/desc.h"
#include "base/string.h"

typedef struct MsBigCell MsBigCell;
/* ms-sig: msstd_bigint_from_int(value: i64) -> *mut ObjCell<Big> @handle @domain=big integer @leaf */
MsBigCell *msstd_bigint_from_int(int64_t value);
/* ms-sig: msstd_bigint_from_u64(value: i64) -> *mut ObjCell<Big> @handle @domain=big integer @leaf */
MsBigCell *msstd_bigint_from_u64(int64_t value);
/* ms-sig: msstd_bigint_from_seconds_nanos(seconds: i64, nanoseconds: i64) -> *mut ObjCell<Big> @handle
 * @domain=big integer @leaf */
MsBigCell *msstd_bigint_from_seconds_nanos(int64_t seconds, int64_t nanoseconds);
/* ms-sig: msstd_bigint_parse(text: *const StrVal, radix: i64, has_max: uint8_t, max: i64, out: *mut *mut
 * ObjCell<Big>) -> u8 @domain=big integer @leaf */
uint8_t msstd_bigint_parse(const MsString *text, int64_t radix, uint8_t has_max, int64_t max,
                           MsBigCell **out);
/* ms-sig: msstd_bigint_add(handle a: *const ObjCell<Big>, handle other: *const ObjCell<Big>) -> *mut
 * ObjCell<Big> @handle @domain=big integer @leaf */
MsBigCell *msstd_bigint_add(const MsBigCell *a, const MsBigCell *other);
/* ms-sig: msstd_bigint_subtract(handle a: *const ObjCell<Big>, handle other: *const ObjCell<Big>) -> *mut
 * ObjCell<Big> @handle @domain=big integer @leaf */
MsBigCell *msstd_bigint_subtract(const MsBigCell *a, const MsBigCell *other);
/* ms-sig: msstd_bigint_multiply(handle a: *const ObjCell<Big>, handle other: *const ObjCell<Big>) -> *mut
 * ObjCell<Big> @handle @domain=big integer @leaf */
MsBigCell *msstd_bigint_multiply(const MsBigCell *a, const MsBigCell *other);
/* ms-sig: msstd_bigint_gcd(handle a: *const ObjCell<Big>, handle other: *const ObjCell<Big>) -> *mut
 * ObjCell<Big> @handle @domain=big integer @leaf */
MsBigCell *msstd_bigint_gcd(const MsBigCell *a, const MsBigCell *other);
/* ms-sig: msstd_bigint_lcm(handle a: *const ObjCell<Big>, handle other: *const ObjCell<Big>) -> *mut
 * ObjCell<Big> @handle @domain=big integer @leaf */
MsBigCell *msstd_bigint_lcm(const MsBigCell *a, const MsBigCell *other);
/* ms-sig: msstd_bigint_sqrt(handle a: *const ObjCell<Big>, out: *mut *mut ObjCell<Big>) -> u8 @domain=big
 * integer @leaf */
uint8_t msstd_bigint_sqrt(const MsBigCell *a, MsBigCell **out);
/* ms-sig: msstd_bigint_pow_mod(handle a: *const ObjCell<Big>, handle exponent: *const ObjCell<Big>, handle
 * modulus: *const ObjCell<Big>, out: *mut *mut ObjCell<Big>) -> u8 @domain=big integer @leaf */
uint8_t msstd_bigint_pow_mod(const MsBigCell *a, const MsBigCell *exponent, const MsBigCell *modulus,
                             MsBigCell **out);
/* ms-sig: msstd_bigint_inverse_mod(handle a: *const ObjCell<Big>, handle modulus: *const ObjCell<Big>, out:
 * *mut *mut ObjCell<Big>) -> u8 @domain=big integer @leaf */
uint8_t msstd_bigint_inverse_mod(const MsBigCell *a, const MsBigCell *modulus, MsBigCell **out);
/* ms-sig: msstd_bigint_bit_and(handle a: *const ObjCell<Big>, handle other: *const ObjCell<Big>) -> *mut
 * ObjCell<Big> @handle @domain=big integer @leaf */
MsBigCell *msstd_bigint_bit_and(const MsBigCell *a, const MsBigCell *other);
/* ms-sig: msstd_bigint_bit_or(handle a: *const ObjCell<Big>, handle other: *const ObjCell<Big>) -> *mut
 * ObjCell<Big> @handle @domain=big integer @leaf */
MsBigCell *msstd_bigint_bit_or(const MsBigCell *a, const MsBigCell *other);
/* ms-sig: msstd_bigint_bit_xor(handle a: *const ObjCell<Big>, handle other: *const ObjCell<Big>) -> *mut
 * ObjCell<Big> @handle @domain=big integer @leaf */
MsBigCell *msstd_bigint_bit_xor(const MsBigCell *a, const MsBigCell *other);
/* ms-sig: msstd_bigint_divide(handle a: *const ObjCell<Big>, handle other: *const ObjCell<Big>, out: *mut
 * *mut ObjCell<Big>) -> u8 @domain=big integer @leaf */
uint8_t msstd_bigint_divide(const MsBigCell *a, const MsBigCell *other, MsBigCell **out);
/* ms-sig: msstd_bigint_remainder(handle a: *const ObjCell<Big>, handle other: *const ObjCell<Big>, out: *mut
 * *mut ObjCell<Big>) -> u8 @domain=big integer @leaf */
uint8_t msstd_bigint_remainder(const MsBigCell *a, const MsBigCell *other, MsBigCell **out);
/* ms-sig: msstd_bigint_quotient(handle a: *const ObjCell<Big>, handle other: *const ObjCell<Big>) -> *mut
 * ObjCell<Big> @handle @domain=big integer @leaf */
MsBigCell *msstd_bigint_quotient(const MsBigCell *a, const MsBigCell *other);
/* ms-sig: msstd_bigint_modulo(handle a: *const ObjCell<Big>, handle other: *const ObjCell<Big>) -> *mut
 * ObjCell<Big> @handle @domain=big integer @leaf */
MsBigCell *msstd_bigint_modulo(const MsBigCell *a, const MsBigCell *other);
/* ms-sig: msstd_bigint_compare(handle a: *const ObjCell<Big>, handle other: *const ObjCell<Big>) -> i64
 * @domain=big integer @leaf */
int64_t msstd_bigint_compare(const MsBigCell *a, const MsBigCell *other);
/* ms-sig: msstd_bigint_bit_not(handle a: *const ObjCell<Big>) -> *mut ObjCell<Big> @handle @domain=big
 * integer @leaf */
MsBigCell *msstd_bigint_bit_not(const MsBigCell *a);
/* ms-sig: msstd_bigint_negate(handle a: *const ObjCell<Big>) -> *mut ObjCell<Big> @handle @domain=big integer
 * @leaf */
MsBigCell *msstd_bigint_negate(const MsBigCell *a);
/* ms-sig: msstd_bigint_abs(handle a: *const ObjCell<Big>) -> *mut ObjCell<Big> @handle @domain=big integer
 * @leaf */
MsBigCell *msstd_bigint_abs(const MsBigCell *a);
/* ms-sig: msstd_bigint_sign(handle a: *const ObjCell<Big>) -> i64 @domain=big integer @leaf */
int64_t msstd_bigint_sign(const MsBigCell *a);
/* ms-sig: msstd_bigint_pow(handle a: *const ObjCell<Big>, exponent: i64, out: *mut *mut ObjCell<Big>) -> u8
 * @domain=big integer @leaf */
uint8_t msstd_bigint_pow(const MsBigCell *a, int64_t exponent, MsBigCell **out);
/* ms-sig: msstd_bigint_shift_left(handle a: *const ObjCell<Big>, count: i64, out: *mut *mut ObjCell<Big>) ->
 * u8 @domain=big integer @leaf */
uint8_t msstd_bigint_shift_left(const MsBigCell *a, int64_t count, MsBigCell **out);
/* ms-sig: msstd_bigint_shift_right(handle a: *const ObjCell<Big>, count: i64, out: *mut *mut ObjCell<Big>) ->
 * u8 @domain=big integer @leaf */
uint8_t msstd_bigint_shift_right(const MsBigCell *a, int64_t count, MsBigCell **out);
/* ms-sig: msstd_bigint_to_float(handle a: *const ObjCell<Big>) -> f64 @domain=big integer @leaf */
double msstd_bigint_to_float(const MsBigCell *a);
/* ms-sig: msstd_bigint_to_int(handle a: *const ObjCell<Big>, out: *mut i64) -> u8 @domain=big integer @leaf
 */
uint8_t msstd_bigint_to_int(const MsBigCell *a, int64_t *out);
/* `BigInt.to_string()`: the decimal digits. */
/* ms-sig: msrt_bigint_to_string(handle a: *const ObjCell<Big>, out: *mut StrVal) @domain=big integer @leaf */
void msrt_bigint_to_string(const MsBigCell *a, MsString *out);
/* ms-sig: msstd_bigint_to_string_radix(handle a: *const ObjCell<Big>, radix: i64, out: *mut StrVal)
 * @domain=big integer @leaf */
void msstd_bigint_to_string_radix(const MsBigCell *a, int64_t radix, MsString *out);
/* ms-sig: msstd_bigint_equal(handle a: *const ObjCell<Big>, handle other: *const ObjCell<Big>) -> u8
 * @domain=big integer @leaf */
uint8_t msstd_bigint_equal(const MsBigCell *a, const MsBigCell *other);

#endif

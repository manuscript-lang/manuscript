/* runtime/std/decimal.h: the @std/math Decimal natives (src/runtime/std/decimal.c). A Decimal is coefficient
 * * 10^exponent with at most 34 significant digits and no trailing zeros in the coefficient, so equal values
 * have equal records. The coefficient is a signed 128-bit integer in two words. Operators compute exactly and
 * round half to even at 34 digits; a magnitude beyond 9.99...e6144 faults. Failures are MS_STATUS_* codes;
 * *out is written only on success. */
#ifndef MS_RUNTIME_STD_DECIMAL_H
#define MS_RUNTIME_STD_DECIMAL_H

#include "abi/status.h"
#include "base/string.h"

typedef struct MsDecimal {
  uint64_t low;     /* the coefficient's low 64 bits */
  int64_t high;     /* its high 64 bits, signed */
  int64_t exponent; /* 0 when the coefficient is 0 */
} MsDecimal;

/* ms-sig: msstd_decimal_add(a: *const DecType, b: *const DecType, out: *mut DecType) @domain=number @leaf */
void msstd_decimal_add(const MsDecimal *a, const MsDecimal *b, MsDecimal *out);
/* ms-sig: msstd_decimal_subtract(a: *const DecType, b: *const DecType, out: *mut DecType) @domain=number
 * @leaf */
void msstd_decimal_subtract(const MsDecimal *a, const MsDecimal *b, MsDecimal *out);
/* ms-sig: msstd_decimal_multiply(a: *const DecType, b: *const DecType, out: *mut DecType) @domain=number
 * @leaf */
void msstd_decimal_multiply(const MsDecimal *a, const MsDecimal *b, MsDecimal *out);
/* ms-sig: msstd_decimal_divide(a: *const DecType, b: *const DecType, out: *mut DecType) @domain=number @leaf
 */
void msstd_decimal_divide(const MsDecimal *a, const MsDecimal *b, MsDecimal *out);
/* ms-sig: msstd_decimal_negate(a: *const DecType, out: *mut DecType) @domain=number @leaf */
void msstd_decimal_negate(const MsDecimal *a, MsDecimal *out);
/* ms-sig: msstd_decimal_compare(a: *const DecType, b: *const DecType) -> i64 @domain=number @leaf */
int64_t msstd_decimal_compare(const MsDecimal *a, const MsDecimal *b);
/* ms-sig: msstd_decimal_parse(text: *const StrVal, out: *mut DecType) -> u8 @domain=number @leaf */
uint8_t msstd_decimal_parse(const MsString *text, MsDecimal *out);
/* ms-sig: msstd_decimal_from_int(n: i64, out: *mut DecType) @domain=number @leaf */
void msstd_decimal_from_int(int64_t n, MsDecimal *out);
/* ms-sig: msstd_decimal_from_uint(n: i64, out: *mut DecType) @domain=number @leaf */
void msstd_decimal_from_uint(int64_t n, MsDecimal *out);
/* ms-sig: msstd_decimal_round(value: *const DecType, places: i64, has_mode: uint8_t, mode: i64, out: *mut
 * DecType) -> u8 @domain=number @leaf */
uint8_t msstd_decimal_round(const MsDecimal *value, int64_t places, uint8_t has_mode, int64_t mode,
                            MsDecimal *out);
/* ms-sig: msstd_decimal_to_fixed(value: *const DecType, digits: i64, has_mode: uint8_t, mode: i64, out: *mut
 * StrVal) -> u8 @domain=number @leaf */
uint8_t msstd_decimal_to_fixed(const MsDecimal *value, int64_t digits, uint8_t has_mode, int64_t mode,
                               MsString *out);
/* ms-sig: msstd_decimal_to_float(a: *const DecType) -> f64 @domain=number @leaf */
double msstd_decimal_to_float(const MsDecimal *a);
/* ms-sig: msstd_decimal_to_string(a: *const DecType, out: *mut StrVal) @domain=number @leaf */
void msstd_decimal_to_string(const MsDecimal *a, MsString *out);
/* ms-sig: msstd_decimal_truncate_to_int(a: *const DecType, out: *mut i64) -> u8 @domain=number @leaf */
uint8_t msstd_decimal_truncate_to_int(const MsDecimal *a, int64_t *out);

/* `to_decimal()` of each integer type. */
void msrt_int_to_decimal(int64_t v, MsDecimal *out);
void msrt_int8_to_decimal(int64_t v, MsDecimal *out);
void msrt_int16_to_decimal(int64_t v, MsDecimal *out);
void msrt_int32_to_decimal(int64_t v, MsDecimal *out);
void msrt_int64_to_decimal(int64_t v, MsDecimal *out);
void msrt_uint8_to_decimal(int64_t v, MsDecimal *out);
void msrt_uint16_to_decimal(int64_t v, MsDecimal *out);
void msrt_uint32_to_decimal(int64_t v, MsDecimal *out);
void msrt_uint64_to_decimal(int64_t v, MsDecimal *out);

#endif

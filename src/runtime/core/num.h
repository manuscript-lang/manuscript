/* runtime/core/num.h: the number natives (num.c, num_text.c): comparison, bit casts, conversions, parsing,
 * to_string of the scalar types and the precision forms of Float. */
#ifndef MS_RUNTIME_CORE_NUM_H
#define MS_RUNTIME_CORE_NUM_H

#include "base/string.h"

/* ms-op: msrt_float_compare fcompare */
int64_t msrt_float_compare(double a, double b);
/* ms-op: msrt_int_compare icompare */
int64_t msrt_int_compare(int64_t a, int64_t b);
/* ms-op: msrt_uint_compare icompare */
int64_t msrt_uint_compare(int64_t a, int64_t b);
/* ms-sig: msrt_uint_to_float(v: i64) -> f64 @domain=number */
double msrt_uint_to_float(int64_t v);
/* ms-sig: msrt_uint_to_float32(v: i64) -> f64 @domain=number */
double msrt_uint_to_float32(int64_t v);
/* ms-op: msrt_float_is_nan fis_nan */
uint8_t msrt_float_is_nan(double x);
/* ms-op: msrt_float_is_finite fis_finite */
uint8_t msrt_float_is_finite(double x);
/* ms-sig: msrt_float_from_bits(bits: i64) -> f64 @domain=number @end */
double msrt_float_from_bits(int64_t bits);
/* ms-sig: msrt_float_to_bits(value: f64) -> i64 @domain=number @end */
int64_t msrt_float_to_bits(double value);
/* ms-sig: msrt_float32_from_bits(bits: i64) -> f64 @domain=number @end */
double msrt_float32_from_bits(int64_t bits);
/* ms-sig: msrt_float32_to_bits(value: f64) -> i64 @domain=number @end */
int64_t msrt_float32_to_bits(double value);
/* ms-sig: msrt_float_truncate_to_int(v: f64, out: *mut i64) -> u8 @domain=number @end */
/* ms-op: msrt_float_truncate_to_int ftruncate_int */
uint8_t msrt_float_truncate_to_int(double v, int64_t *out);
/* ms-sig: msrt_float_to_float32(v: f64, out: *mut f32) -> u8 @domain=number @end */
uint8_t msrt_float_to_float32(double v, float *out);
/* ms-sig: msrt_uint_div(a: i64, b: i64) -> i64 @domain=number */
int64_t msrt_uint_div(int64_t a, int64_t b);
/* ms-sig: msrt_uint_rem(a: i64, b: i64) -> i64 @domain=number */
int64_t msrt_uint_rem(int64_t a, int64_t b);
/* ms-sig: msrt_numbers_error_message(status: u8, out: *mut StrVal) @domain=number @end */
void msrt_numbers_error_message(uint8_t status, MsString *out);
/* ms-sig: msrt_float_to_precision(v: f64, digits: i64, out: *mut StrVal) @domain=number @end */
void msrt_float_to_precision(double v, int64_t digits, MsString *out);
/* ms-sig: msrt_float_to_exponential(v: f64, digits: i64, out: *mut StrVal) @domain=number @end */
void msrt_float_to_exponential(double v, int64_t digits, MsString *out);
/* ms-sig: msrt_float_to_fixed(v: f64, digits: i64, out: *mut StrVal) @domain=number @end */
void msrt_float_to_fixed(double v, int64_t digits, MsString *out);
/* ms-sig: msrt_numbers_parse_int(text: *const StrVal, radix: i64, out: *mut i64) -> u8 @domain=number @end */
uint8_t msrt_numbers_parse_int(const MsString *text, int64_t radix, int64_t *out);
/* ms-sig: msrt_numbers_parse_float(text: *const StrVal, out: *mut f64) -> u8 @domain=number @end */
uint8_t msrt_numbers_parse_float(const MsString *text, double *out);
/* ms-sig: msrt_string_parse_int(s: *const StrVal, out: *mut i64) -> u8 @domain=string @end */
uint8_t msrt_string_parse_int(const MsString *s, int64_t *out);
/* ms-sig: msrt_string_parse_float(s: *const StrVal, out: *mut f64) -> u8 @domain=string @end */
uint8_t msrt_string_parse_float(const MsString *s, double *out);
/* ms-sig: msrt_int_to_string(v: i64, out: *mut StrVal) @end */
void msrt_int_to_string(int64_t v, MsString *out);
/* ms-sig: msrt_uint_to_string(v: i64, out: *mut StrVal) */
void msrt_uint_to_string(int64_t v, MsString *out);
/* ms-sig: msrt_int_to_string_radix(v: i64, radix: i64, out: *mut StrVal) -> u8 @end */
uint8_t msrt_int_to_string_radix(int64_t v, int64_t radix, MsString *out);
/* ms-sig: msrt_uint_to_string_radix(v: i64, radix: i64, out: *mut StrVal) -> u8 */
uint8_t msrt_uint_to_string_radix(int64_t v, int64_t radix, MsString *out);
/* ms-sig: msrt_float_to_string(v: f64, out: *mut StrVal) @end */
void msrt_float_to_string(double v, MsString *out);
/* ms-sig: msrt_float32_to_string(v: f64, out: *mut StrVal) @end */
void msrt_float32_to_string(double v, MsString *out);
/* ms-sig: msrt_bool_to_string(v: u8, out: *mut StrVal) @end */
void msrt_bool_to_string(uint8_t v, MsString *out);

#endif

/* ms_rt/num.h: number primitives (runtime/core/num.c). */
#ifndef MS_RT_NUM_H
#define MS_RT_NUM_H

#include "ms_rt/base.h"
#include "ms_rt/string.h"

/* ms-sig: msrt_float_compare(a: f64, b: f64) -> i64 @domain=number @leaf */
int64_t msrt_float_compare(double a, double b);
/* ms-sig: msrt_int_compare(a: i64, b: i64) -> i64 @domain=number @leaf */
int64_t msrt_int_compare(int64_t a, int64_t b);
/* ms-sig: msrt_uint_compare(a: i64, b: i64) -> i64 @domain=number */
int64_t msrt_uint_compare(int64_t a, int64_t b);
/* ms-sig: msrt_uint_to_float(v: i64) -> f64 @domain=number */
double msrt_uint_to_float(int64_t v);
/* ms-sig: msrt_uint_to_float32(v: i64) -> f64 @domain=number */
double msrt_uint_to_float32(int64_t v);
/* ms-sig: msrt_float_is_nan(x: f64) -> u8 @domain=number @leaf @seq=fcmp.ne:$0:$0>bool */
uint8_t msrt_float_is_nan(double x);
/* ms-sig: msrt_float_is_finite(x: f64) -> u8 @domain=number @leaf @seq=fsub:$0:$0>float,fconst:#0.0>float,fcmp.eq:%0:%1>bool */
uint8_t msrt_float_is_finite(double x);
/* ms-sig: msrt_float_from_bits(bits: i64) -> f64 @domain=number @leaf */
double msrt_float_from_bits(int64_t bits);
/* ms-sig: msrt_float_to_bits(value: f64) -> i64 @domain=number @leaf */
int64_t msrt_float_to_bits(double value);
/* ms-sig: msrt_float32_from_bits(bits: i64) -> f64 @domain=number @leaf */
double msrt_float32_from_bits(int64_t bits);
/* ms-sig: msrt_float32_to_bits(value: f64) -> i64 @domain=number @leaf */
int64_t msrt_float32_to_bits(double value);
/* ms-sig: msrt_float_truncate_to_int(v: f64, out: *mut i64) -> u8 @domain=number @leaf */
uint8_t msrt_float_truncate_to_int(double v, int64_t *out);
/* ms-sig: msrt_float_to_float32(v: f64, out: *mut f32) -> u8 @domain=number @leaf */
uint8_t msrt_float_to_float32(double v, float *out);

/* ms-sig: msrt_uint_div(a: i64, b: i64) -> i64 @domain=number */
int64_t msrt_uint_div(int64_t a, int64_t b);
/* ms-sig: msrt_uint_rem(a: i64, b: i64) -> i64 @domain=number */
int64_t msrt_uint_rem(int64_t a, int64_t b);
/* ms-sig: msrt_numbers_error_message(status: u8, out: *mut StrVal) @domain=number @leaf */
void msrt_numbers_error_message(uint8_t status, MsStr *out);
/* ms-sig: msrt_float_to_precision(v: f64, digits: i64, out: *mut StrVal) @domain=number @leaf */
void msrt_float_to_precision(double v, int64_t digits, MsStr *out);
/* ms-sig: msrt_float_to_exponential(v: f64, digits: i64, out: *mut StrVal) @domain=number @leaf */
void msrt_float_to_exponential(double v, int64_t digits, MsStr *out);
/* ms-sig: msrt_float_to_fixed(v: f64, digits: i64, out: *mut StrVal) @domain=number @leaf */
void msrt_float_to_fixed(double v, int64_t digits, MsStr *out);

/* ms-sig: msrt_numbers_parse_int(text: *const StrVal, radix: i64, out: *mut i64) -> u8 @domain=number @leaf */
uint8_t msrt_numbers_parse_int(const MsStr *text, int64_t radix, int64_t *out);

/* ms-sig: msrt_numbers_parse_float(text: *const StrVal, out: *mut f64) -> u8 @domain=number @leaf */
uint8_t msrt_numbers_parse_float(const MsStr *text, double *out);

#endif

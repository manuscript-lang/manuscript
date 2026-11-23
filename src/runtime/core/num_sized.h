/* runtime/core/num_sized.h: the receiver operations of the sized number types (num_sized.c), named
 * `msrt_<type>_<operation>` as lowering names a bodiless standard operation. Integers travel as an int64 holding
 * the value (UInt64 as its bit pattern); an operation that can have no result returns a presence flag and writes
 * the value through `out`. */
#ifndef MS_RUNTIME_CORE_NUM_SIZED_H
#define MS_RUNTIME_CORE_NUM_SIZED_H

#include "base/string.h"

#define DECLARE_NUMBER(name)                                                                                     \
  void msrt_##name##_to_hex(int64_t v, MsString *out);                                                          \
  void msrt_##name##_to_binary(int64_t v, MsString *out);                                                       \
  double msrt_##name##_to_float(int64_t v);                                                                     \
  double msrt_##name##_to_float32(int64_t v);
#define DECLARE_TEXT(name)                                                                                       \
  void msrt_##name##_to_string(int64_t v, MsString *out);                                                       \
  uint8_t msrt_##name##_to_string_radix(int64_t v, int64_t radix, MsString *out);
#define DECLARE_INTEGER(name)                                                                                    \
  DECLARE_TEXT(name)                                                                                             \
  DECLARE_NUMBER(name)                                                                                           \
  int64_t msrt_##name##_compare(int64_t a, int64_t b);
#define DECLARE_SIGNED(name)                                                                                     \
  int64_t msrt_##name##_abs(int64_t v);                                                                         \
  int64_t msrt_##name##_sign(int64_t v);
#define DECLARE_EXACT(from, to) int64_t msrt_##from##_to_##to(int64_t v);
#define DECLARE_RANGE(from, to) uint8_t msrt_##from##_to_##to(int64_t v, int64_t *out);

DECLARE_NUMBER(int)
DECLARE_INTEGER(int8)
DECLARE_INTEGER(int16)
DECLARE_INTEGER(int32)
DECLARE_INTEGER(int64)
DECLARE_INTEGER(uint8)
DECLARE_INTEGER(uint16)
DECLARE_INTEGER(uint32)
DECLARE_INTEGER(uint64)
DECLARE_SIGNED(int)
DECLARE_SIGNED(int8)
DECLARE_SIGNED(int16)
DECLARE_SIGNED(int32)
DECLARE_SIGNED(int64)

DECLARE_EXACT(int8, int16)
DECLARE_EXACT(int8, int32)
DECLARE_EXACT(int8, int64)
DECLARE_EXACT(int8, int)
DECLARE_EXACT(int16, int64)
DECLARE_EXACT(int16, int)
DECLARE_EXACT(int32, int64)
DECLARE_EXACT(int32, int)
DECLARE_EXACT(uint8, int)
DECLARE_EXACT(uint16, int)
DECLARE_EXACT(uint32, int64)
DECLARE_EXACT(uint32, int)
DECLARE_EXACT(int, int64)

DECLARE_RANGE(int16, int8)
DECLARE_RANGE(int32, int8)
DECLARE_RANGE(int32, int16)
DECLARE_RANGE(uint16, uint8)
DECLARE_RANGE(uint32, int32)
DECLARE_RANGE(int, int8)
DECLARE_RANGE(int, int16)
DECLARE_RANGE(int, int32)
DECLARE_RANGE(int, uint8)
DECLARE_RANGE(int, uint16)
DECLARE_RANGE(int, uint32)
DECLARE_RANGE(int, uint64)
DECLARE_RANGE(uint64, int)
DECLARE_RANGE(uint64, uint8)
DECLARE_RANGE(uint64, uint32)

/* The natives the macros above declare, as the signature table reads them. */
/* ms-sig: msrt_int8_compare(a: i64, b: i64) -> i64 @op=icompare */
/* ms-sig: msrt_int16_compare(a: i64, b: i64) -> i64 @op=icompare */
/* ms-sig: msrt_int32_compare(a: i64, b: i64) -> i64 @op=icompare */
/* ms-sig: msrt_int64_compare(a: i64, b: i64) -> i64 @op=icompare */
/* ms-sig: msrt_uint8_compare(a: i64, b: i64) -> i64 @op=icompare */
/* ms-sig: msrt_uint16_compare(a: i64, b: i64) -> i64 @op=icompare */
/* ms-sig: msrt_uint32_compare(a: i64, b: i64) -> i64 @op=icompare */
/* ms-sig: msrt_uint64_compare(a: i64, b: i64) -> i64 @op=icompare */
/* ms-sig: msrt_int_sign(v: i64) -> i64 @op=isign */
/* ms-sig: msrt_int8_sign(v: i64) -> i64 @op=isign */
/* ms-sig: msrt_int16_sign(v: i64) -> i64 @op=isign */
/* ms-sig: msrt_int32_sign(v: i64) -> i64 @op=isign */
/* ms-sig: msrt_int64_sign(v: i64) -> i64 @op=isign */
/* ms-sig: msrt_int_abs(v: i64) -> i64 @op=iabs */
/* ms-sig: msrt_int64_abs(v: i64) -> i64 @op=iabs */
/* ms-sig: msrt_int8_abs(v: i64) -> i64 @op=sized_abs */
/* ms-sig: msrt_int16_abs(v: i64) -> i64 @op=sized_abs */
/* ms-sig: msrt_int32_abs(v: i64) -> i64 @op=sized_abs */
/* ms-sig: msrt_int_to_float(v: i64) -> f64 @op=to_float */
/* ms-sig: msrt_int_to_float32(v: i64) -> f64 @op=to_float */
/* ms-sig: msrt_int8_to_float(v: i64) -> f64 @op=to_float */
/* ms-sig: msrt_int8_to_float32(v: i64) -> f64 @op=to_float */
/* ms-sig: msrt_int16_to_float(v: i64) -> f64 @op=to_float */
/* ms-sig: msrt_int16_to_float32(v: i64) -> f64 @op=to_float */
/* ms-sig: msrt_int32_to_float(v: i64) -> f64 @op=to_float */
/* ms-sig: msrt_int32_to_float32(v: i64) -> f64 @op=to_float */
/* ms-sig: msrt_int64_to_float(v: i64) -> f64 @op=to_float */
/* ms-sig: msrt_int64_to_float32(v: i64) -> f64 @op=to_float */
/* ms-sig: msrt_uint8_to_float(v: i64) -> f64 @op=to_float */
/* ms-sig: msrt_uint8_to_float32(v: i64) -> f64 @op=to_float */
/* ms-sig: msrt_uint16_to_float(v: i64) -> f64 @op=to_float */
/* ms-sig: msrt_uint16_to_float32(v: i64) -> f64 @op=to_float */
/* ms-sig: msrt_uint32_to_float(v: i64) -> f64 @op=to_float */
/* ms-sig: msrt_uint32_to_float32(v: i64) -> f64 @op=to_float */
/* ms-sig: msrt_int8_to_int16(v: i64) -> i64 @op=widen */
/* ms-sig: msrt_int8_to_int32(v: i64) -> i64 @op=widen */
/* ms-sig: msrt_int8_to_int64(v: i64) -> i64 @op=widen */
/* ms-sig: msrt_int8_to_int(v: i64) -> i64 @op=widen */
/* ms-sig: msrt_int16_to_int64(v: i64) -> i64 @op=widen */
/* ms-sig: msrt_int16_to_int(v: i64) -> i64 @op=widen */
/* ms-sig: msrt_int32_to_int64(v: i64) -> i64 @op=widen */
/* ms-sig: msrt_int32_to_int(v: i64) -> i64 @op=widen */
/* ms-sig: msrt_uint8_to_int(v: i64) -> i64 @op=widen */
/* ms-sig: msrt_uint16_to_int(v: i64) -> i64 @op=widen */
/* ms-sig: msrt_uint32_to_int64(v: i64) -> i64 @op=widen */
/* ms-sig: msrt_uint32_to_int(v: i64) -> i64 @op=widen */
/* ms-sig: msrt_int_to_int64(v: i64) -> i64 @op=widen */
/* ms-sig: msrt_float32_is_nan(v: f64) -> u8 @op=fis_nan */
/* ms-sig: msrt_float32_is_finite(v: f64) -> u8 @op=fis_finite */
/* ms-sig: msrt_float32_compare(a: f64, b: f64) -> i64 @op=fcompare */
/* ms-sig: msrt_float32_abs(v: f64) -> f64 @op=fabs */
/* ms-sig: msrt_float32_sign(v: f64) -> f64 @op=fsign */
/* ms-sig: msrt_float32_to_float(v: f64) -> f64 @op=float_widen */
/* ms-sig: msrt_float32_to_float64(v: f64) -> f64 @op=float_widen */
/* ms-sig: msrt_float_abs(v: f64) -> f64 @op=fabs */
/* ms-sig: msrt_float_sign(v: f64) -> f64 @op=fsign */
/* ms-sig: msrt_int16_to_int8(v: i64, out: *mut i64) -> u8 @op=narrow */
/* ms-sig: msrt_int32_to_int8(v: i64, out: *mut i64) -> u8 @op=narrow */
/* ms-sig: msrt_int32_to_int16(v: i64, out: *mut i64) -> u8 @op=narrow */
/* ms-sig: msrt_uint16_to_uint8(v: i64, out: *mut i64) -> u8 @op=narrow */
/* ms-sig: msrt_uint32_to_int32(v: i64, out: *mut i64) -> u8 @op=narrow */
/* ms-sig: msrt_int_to_int8(v: i64, out: *mut i64) -> u8 @op=narrow */
/* ms-sig: msrt_int_to_int16(v: i64, out: *mut i64) -> u8 @op=narrow */
/* ms-sig: msrt_int_to_int32(v: i64, out: *mut i64) -> u8 @op=narrow */
/* ms-sig: msrt_int_to_uint8(v: i64, out: *mut i64) -> u8 @op=narrow */
/* ms-sig: msrt_int_to_uint16(v: i64, out: *mut i64) -> u8 @op=narrow */
/* ms-sig: msrt_int_to_uint32(v: i64, out: *mut i64) -> u8 @op=narrow */
/* ms-sig: msrt_int_to_uint64(v: i64, out: *mut i64) -> u8 @op=narrow */
/* ms-sig: msrt_uint64_to_int(v: i64, out: *mut i64) -> u8 @op=narrow */
/* ms-sig: msrt_uint64_to_uint8(v: i64, out: *mut i64) -> u8 @op=narrow */
/* ms-sig: msrt_uint64_to_uint32(v: i64, out: *mut i64) -> u8 @op=narrow */
/* ms-sig: msrt_int8_to_string_radix(v: i64, radix: i64, out: *mut StrVal) -> u8 @end */
/* ms-sig: msrt_int16_to_string_radix(v: i64, radix: i64, out: *mut StrVal) -> u8 @end */
/* ms-sig: msrt_int32_to_string_radix(v: i64, radix: i64, out: *mut StrVal) -> u8 @end */
/* ms-sig: msrt_int64_to_string_radix(v: i64, radix: i64, out: *mut StrVal) -> u8 @end */
/* ms-sig: msrt_uint8_to_string_radix(v: i64, radix: i64, out: *mut StrVal) -> u8 @end */
/* ms-sig: msrt_uint16_to_string_radix(v: i64, radix: i64, out: *mut StrVal) -> u8 @end */
/* ms-sig: msrt_uint32_to_string_radix(v: i64, radix: i64, out: *mut StrVal) -> u8 @end */
/* ms-sig: msrt_uint64_to_string_radix(v: i64, radix: i64, out: *mut StrVal) -> u8 @end */
/* ms-sig: msrt_float32_truncate_to_int(v: f64, out: *mut i64) -> u8 @op=ftruncate_int */

uint8_t msrt_float32_is_nan(double v);
uint8_t msrt_float32_is_finite(double v);
int64_t msrt_float32_compare(double a, double b);
double msrt_float32_abs(double v);
double msrt_float32_sign(double v);
uint8_t msrt_float32_truncate_to_int(double v, int64_t *out);
double msrt_float32_to_float(double v);
double msrt_float32_to_float64(double v);
double msrt_float_abs(double v);
double msrt_float_sign(double v);

#endif

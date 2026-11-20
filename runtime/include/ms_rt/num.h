/* ms_rt/num.h: number primitives (runtime/core/num.c). */
#ifndef MS_RT_NUM_H
#define MS_RT_NUM_H

#include "ms_rt/base.h"

int64_t msrt_float_compare(double a, double b);
int64_t msrt_int_compare(int64_t a, int64_t b);
int64_t msrt_uint_compare(int64_t a, int64_t b);
double msrt_uint_to_float(int64_t v);
double msrt_uint_to_float32(int64_t v);
double msrt_float_from_bits(int64_t bits);
int64_t msrt_float_to_bits(double value);
double msrt_float32_from_bits(int64_t bits);
int64_t msrt_float32_to_bits(double value);
uint8_t msrt_float_truncate_to_int(double v, int64_t *out);
uint8_t msrt_float_to_float32(double v, float *out);

#endif

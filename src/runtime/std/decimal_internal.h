/* What decimal.c shares with decimal_text.c: the 128-bit helpers and the packed record. */
#ifndef MS_RUNTIME_STD_DECIMAL_INTERNAL_H
#define MS_RUNTIME_STD_DECIMAL_INTERNAL_H

#include <stdbool.h>

#include "base/wide.h"
#include "runtime/std/bignum.h"
#include "runtime/std/decimal.h"

enum {
  MS_DECIMAL_DIGITS = 34,
  MS_DECIMAL_WIDE_DIGITS = 38, /* the most digits dropped from a 128-bit value */
  MS_DECIMAL_MIN_QUANTUM = -6176,
  MS_DECIMAL_MAX_EXPONENT = 6144,
  /* The most digits a rendering can hold: sign, 34 digits, a point, `e+6144`. */
  MS_DECIMAL_RENDER_MAX = 48,
};

/* 10^exponent for an exponent up to 38. */
MsU128 ms_dec_power_of_ten(unsigned exponent);
/* The number of decimal digits of a value; 0 for 0. */
unsigned ms_dec_digits_of(MsU128 value);
MsI128 ms_dec_coefficient_of(const MsDecimal *d) MS_NONNULL;
MsDecimal ms_dec_pack(MsI128 coefficient, int64_t exponent);
bool ms_dec_is_zero(const MsDecimal *d) MS_NONNULL;
MsU128 ms_dec_magnitude_of(MsI128 value);
/* Strips trailing zeros of the magnitude into the exponent. */
void ms_dec_normalize(MsU128 *magnitude, int64_t *exponent) MS_NONNULL;
void ms_dec_big_from_coefficient(MsBig *out, const MsDecimal *d) MS_NONNULL;

#endif

/* fmt_fixed.h: the integer formatter for callers that own a buffer of MS_FMT_INTEGER_CAPACITY bytes (src/runtime/core
 * only; it is no ABI, so ms_rt/fmt.h and the symbol lists do not carry it). */
#ifndef MS_FMT_FIXED_H
#define MS_FMT_FIXED_H

#include "ms_rt/fmt.h"

/* The decimal text of `value` written at the start of `out`, and its length. It needs no capacity check, since the
 * buffer holds the longest Int. */
MS_NONNULL size_t ms_fmt_i64_fixed(int64_t value, uint8_t out[static MS_FMT_INTEGER_CAPACITY]);

#endif

/* The plumbing bignum.c shares with bignum_text.c: pooled BIGNUMs and result placement. */
#ifndef MS_STD_BIGNUM_INTERNAL_H
#define MS_STD_BIGNUM_INTERNAL_H

#include "runtime/std/bignum.h"

/* Faults when a BN_* call failed (`ok` is zero): too large, or out of memory. */
void ms_big_must(int ok);
/* A pooled BIGNUM, and its return to the pool. */
MS_NODISCARD MS_RETURNS_NONNULL BIGNUM *ms_big_new_bn(void);
void ms_big_release_bn(BIGNUM *bn);
/* The BIGNUM of `a`, or a shared zero. */
MS_NODISCARD const BIGNUM *ms_big_value_of(const MsBig *a) MS_NONNULL;
/* Makes `result` the value of `out`, releasing the previous contents. */
void ms_big_result_end(MsBig *out, BIGNUM *result) MS_NONNULL;

#endif

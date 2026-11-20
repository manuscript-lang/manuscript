/* Magnitude kernels under bignum.c: arithmetic on unsigned little-endian limb arrays (runtime/std/bignum_mag.c).
 *
 * A magnitude is a pointer and a limb count. Inputs are "normal": no leading zero limb. Each function documents
 * how many limbs its output buffer needs; outputs never overlap inputs unless a function says so. Results are
 * returned as normal lengths. Nothing here allocates except ms_mag_mul and ms_mag_divmod, which take scratch
 * space from the runtime allocator for the duration of the call. A pointer may be NULL when its length is 0.
 */
#ifndef MS_STD_BIGNUM_MAG_H
#define MS_STD_BIGNUM_MAG_H

#include <stddef.h>

#include "bignum.h"

/* A divisor of one limb prepared for repeated division (Moller and Granlund's reciprocal method). */
typedef struct MsLimbDivisor {
    MsLimb normalized; /* the divisor shifted left until its top bit is set */
    MsLimb reciprocal; /* floor((2^128 - 1) / normalized) - 2^64 */
    unsigned shift;    /* the shift applied; the divisor must be nonzero */
} MsLimbDivisor;

MsLimbDivisor ms_mag_limb_divisor(MsLimb divisor);

/* Length of `a` without leading zero limbs. */
size_t ms_mag_normal_length(const MsLimb *a, size_t length);
int ms_mag_cmp(const MsLimb *a, size_t a_len, const MsLimb *b, size_t b_len);
/* r = a + b; r holds max(a_len, b_len) + 1 limbs. */
size_t ms_mag_add(MsLimb *r, const MsLimb *a, size_t a_len, const MsLimb *b, size_t b_len);
/* r = a - b with a >= b; r holds a_len limbs. */
size_t ms_mag_sub(MsLimb *r, const MsLimb *a, size_t a_len, const MsLimb *b, size_t b_len);
/* r = a * b; r holds a_len + b_len limbs. Karatsuba above a threshold, so large products are fast. */
size_t ms_mag_mul(MsLimb *r, const MsLimb *a, size_t a_len, const MsLimb *b, size_t b_len);
/* r = a << count; r holds a_len + count / 64 + 1 limbs. */
size_t ms_mag_shl(MsLimb *r, const MsLimb *a, size_t a_len, size_t count);
/* r = a >> count (toward zero); r holds a_len limbs. Sets *sticky when a one bit was shifted out. */
size_t ms_mag_shr(MsLimb *r, const MsLimb *a, size_t a_len, size_t count, bool *sticky);
/* Quotient and remainder of a / b with a_len >= b_len >= 1 and b normal: q holds a_len - b_len + 1 limbs and r
 * holds b_len limbs. The lengths of the normal results are stored. */
void ms_mag_divmod(MsLimb *q, size_t *q_len, MsLimb *r, size_t *r_len, const MsLimb *a, size_t a_len,
                   const MsLimb *b, size_t b_len);
/* a = a / divisor in place (a_len limbs, the top may become zero); returns the remainder. */
MsLimb ms_mag_divmod_limb(MsLimb *a, size_t a_len, MsLimbDivisor divisor);
/* a * b mod the divisor, for a and b below it; no allocation. */
MsLimb ms_mag_mul_mod_limb(MsLimb a, MsLimb b, MsLimbDivisor divisor);
/* a = a * factor + addend in place over a_len limbs; returns the carry out of the top limb. */
MsLimb ms_mag_mul_add_limb(MsLimb *a, size_t a_len, MsLimb factor, MsLimb addend);

#endif

/* Multiplication of wide integers by number-theoretic transforms, for the
 * products OpenSSL's Karatsuba multiply is too slow for (over about 2^16 bits).
 */
#ifndef MS_STD_BIGNUM_NTT_H
#define MS_STD_BIGNUM_NTT_H

#include <openssl/bn.h>
#include <stdbool.h>

/* result = |a| * |b| (the sign is the caller's). `result` must be neither
 * operand. Passing the same BIGNUM as `a` and `b` squares it with one forward
 * transform fewer. Returns false when the product is wider than the transform
 * supports (about 2^26 bits); the caller then uses BN_mul. */
bool ms_ntt_multiply(BIGNUM *result, const BIGNUM *a, const BIGNUM *b);

#endif

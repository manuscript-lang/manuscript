/* Wide multiplication: each operand is cut into 32-bit limbs, transformed modulo three primes whose product exceeds
 * the largest coefficient of the product (n * 2^64 with n below 2^22), multiplied pointwise, transformed back, and
 * recombined by Garner's formula. Arithmetic is Montgomery form on 32-bit words. */
#include "bignum_ntt.h"

#include <stdint.h>
#include <string.h>

#include "ms_rt/alloc.h"
#include "ms_rt/runtime.h"

typedef unsigned __int128 U128;

enum {
    LIMB_BITS = 32,
    LIMB_BYTES = 4,
    PRIME_COUNT = 3,
    MAX_LOG2_LENGTH = 22, /* the longest transform: coefficients below 2^22 * 2^64 stay under the prime product */
};

typedef struct Prime {
    uint32_t modulus;
    uint32_t generator;
    uint32_t negative_inverse; /* -modulus^-1 mod 2^32 */
    uint32_t one;              /* 2^32 mod modulus: 1 in Montgomery form */
    uint32_t square;           /* 2^64 mod modulus: converts into Montgomery form */
} Prime;

static const uint32_t prime_moduli[PRIME_COUNT] = {998244353u, 167772161u, 469762049u}; /* each 1 mod 2^23, generator 3 */

static uint32_t mont_reduce(const Prime *p, uint64_t t) {
    const uint32_t m = (uint32_t)t * p->negative_inverse;
    const uint32_t u = (uint32_t)((t + (uint64_t)m * p->modulus) >> LIMB_BITS);
    return u >= p->modulus ? u - p->modulus : u;
}

static uint32_t mont_mul(const Prime *p, uint32_t a, uint32_t b) { return mont_reduce(p, (uint64_t)a * b); }
static uint32_t mont_in(const Prime *p, uint32_t a) { return mont_mul(p, a % p->modulus, p->square); }
static uint32_t mont_out(const Prime *p, uint32_t a) { return mont_reduce(p, a); }

static uint32_t add_mod(const Prime *p, uint32_t a, uint32_t b) {
    const uint32_t s = a + b; /* below 2^31 * 2: no wrap for 30-bit moduli */
    return s >= p->modulus ? s - p->modulus : s;
}

static uint32_t sub_mod(const Prime *p, uint32_t a, uint32_t b) { return a >= b ? a - b : a + p->modulus - b; }

static Prime prime_new(uint32_t modulus) {
    Prime p = {.modulus = modulus, .generator = 3};
    uint32_t inverse = modulus; /* Newton: each step doubles the correct low bits */
    for (int i = 0; i < 5; i++) {
        inverse *= 2 - modulus * inverse;
    }
    p.negative_inverse = 0u - inverse;
    p.one = (uint32_t)((1ull << LIMB_BITS) % modulus);
    p.square = (uint32_t)((U128)p.one * p.one % modulus);
    return p;
}

static uint32_t mont_pow(const Prime *p, uint32_t base, uint32_t exponent) {
    uint32_t result = p->one;
    while (exponent != 0) {
        if ((exponent & 1) != 0) {
            result = mont_mul(p, result, base);
        }
        base = mont_mul(p, base, base);
        exponent >>= 1;
    }
    return result;
}

/* roots[half + j] = w^j for w the primitive (2 * half)-th root of unity, for half = 1, 2, 4, ... n / 2. */
static void fill_roots(const Prime *p, uint32_t *roots, size_t n) {
    const uint32_t generator = mont_in(p, p->generator);
    for (size_t half = 1; half < n; half <<= 1) {
        const uint32_t w = mont_pow(p, generator, (p->modulus - 1) / (uint32_t)(2 * half));
        uint32_t power = p->one;
        for (size_t j = 0; j < half; j++) {
            roots[half + j] = power;
            power = mont_mul(p, power, w);
        }
    }
}

/* Natural order in, bit-reversed order out (decimation in frequency). */
static void forward(const Prime *p, uint32_t *a, size_t n, const uint32_t *roots) {
    for (size_t length = n; length >= 2; length >>= 1) {
        const size_t half = length / 2;
        for (size_t start = 0; start < n; start += length) {
            for (size_t j = 0; j < half; j++) {
                const uint32_t u = a[start + j];
                const uint32_t v = a[start + j + half];
                a[start + j] = add_mod(p, u, v);
                a[start + j + half] = mont_mul(p, sub_mod(p, u, v), roots[half + j]);
            }
        }
    }
}

/* Bit-reversed order in, natural order out (decimation in time), with the inverse roots w^-j = -w^(half - j). */
static void inverse(const Prime *p, uint32_t *a, size_t n, const uint32_t *roots) {
    for (size_t length = 2; length <= n; length <<= 1) {
        const size_t half = length / 2;
        for (size_t start = 0; start < n; start += length) {
            for (size_t j = 0; j < half; j++) {
                const uint32_t w = j == 0 ? p->one : p->modulus - roots[length - j];
                const uint32_t u = a[start + j];
                const uint32_t v = mont_mul(p, a[start + j + half], w);
                a[start + j] = add_mod(p, u, v);
                a[start + j + half] = sub_mod(p, u, v);
            }
        }
    }
}

/* The product's coefficients modulo one prime, in `out` (n values). `b` is NULL for a square. */
static void product_mod(const Prime *p, const uint32_t *a, size_t la, const uint32_t *b, size_t lb, size_t n,
                        uint32_t *out) {
    uint32_t *const roots = msrt_alloc(n * sizeof *roots);
    fill_roots(p, roots, n);
    uint32_t *const fa = out;
    for (size_t i = 0; i < n; i++) {
        fa[i] = i < la ? mont_in(p, a[i]) : 0;
    }
    forward(p, fa, n, roots);
    if (b == NULL) {
        for (size_t i = 0; i < n; i++) {
            fa[i] = mont_mul(p, fa[i], fa[i]);
        }
    } else {
        uint32_t *const fb = msrt_alloc(n * sizeof *fb);
        for (size_t i = 0; i < n; i++) {
            fb[i] = i < lb ? mont_in(p, b[i]) : 0;
        }
        forward(p, fb, n, roots);
        for (size_t i = 0; i < n; i++) {
            fa[i] = mont_mul(p, fa[i], fb[i]);
        }
        msrt_free(fb);
    }
    inverse(p, fa, n, roots);
    const uint32_t scale = mont_pow(p, mont_in(p, (uint32_t)n), p->modulus - 2); /* n^-1 */
    for (size_t i = 0; i < n; i++) {
        fa[i] = mont_out(p, mont_mul(p, fa[i], scale));
    }
    msrt_free(roots);
}

static uint64_t plain_pow(uint64_t base, uint64_t exponent, uint64_t modulus) {
    uint64_t result = 1;
    base %= modulus;
    while (exponent != 0) {
        if ((exponent & 1) != 0) {
            result = result * base % modulus;
        }
        base = base * base % modulus;
        exponent >>= 1;
    }
    return result;
}

static size_t limbs_of(const BIGNUM *a, uint32_t **limbs) {
    const size_t bytes = (size_t)BN_num_bytes(a);
    const size_t count = (bytes + LIMB_BYTES - 1) / LIMB_BYTES;
    *limbs = msrt_alloc((count + 1) * sizeof **limbs);
    memset(*limbs, 0, (count + 1) * sizeof **limbs);
    if (bytes != 0) {
        (void)BN_bn2lebinpad(a, (unsigned char *)*limbs, (int)bytes); /* little-endian hosts only: checked below */
    }
    return count;
}

bool ms_ntt_multiply(BIGNUM *result, const BIGNUM *a, const BIGNUM *b) {
    const uint32_t probe = 1;
    if (*(const unsigned char *)&probe != 1) {
        return false; /* the limb view of the bytes assumes a little-endian host */
    }
    uint32_t *la_limbs = NULL;
    uint32_t *lb_limbs = NULL;
    const size_t la = limbs_of(a, &la_limbs);
    const bool square = a == b;
    const size_t lb = square ? la : limbs_of(b, &lb_limbs);
    size_t n = 1;
    size_t log2_n = 0;
    while (n < la + lb) {
        n <<= 1;
        log2_n++;
    }
    bool done = false;
    if (log2_n <= MAX_LOG2_LENGTH) {
        uint32_t *const residues[PRIME_COUNT] = {msrt_alloc(n * 4), msrt_alloc(n * 4), msrt_alloc(n * 4)};
        Prime primes[PRIME_COUNT];
        for (int k = 0; k < PRIME_COUNT; k++) {
            primes[k] = prime_new(prime_moduli[k]);
            product_mod(&primes[k], la_limbs, la, square ? NULL : lb_limbs, lb, n, residues[k]);
        }
        const uint64_t p1 = prime_moduli[0];
        const uint64_t p2 = prime_moduli[1];
        const uint64_t p3 = prime_moduli[2];
        const uint64_t inverse_p1_mod_p2 = plain_pow(p1, p2 - 2, p2);
        const uint64_t inverse_p12_mod_p3 = plain_pow(p1 * p2 % p3, p3 - 2, p3);
        const size_t out_limbs = la + lb;
        uint32_t *const out = msrt_alloc((out_limbs + 1) * sizeof *out);
        U128 carry = 0;
        for (size_t i = 0; i < out_limbs; i++) {
            const uint64_t r1 = residues[0][i];
            const uint64_t r2 = residues[1][i];
            const uint64_t r3 = residues[2][i];
            const uint64_t k2 = (r2 + p2 - r1 % p2) % p2 * inverse_p1_mod_p2 % p2;
            const uint64_t partial = (r1 + p1 * k2) % p3;
            const uint64_t k3 = (r3 + p3 - partial) % p3 * inverse_p12_mod_p3 % p3;
            carry += (U128)r1 + (U128)p1 * k2 + (U128)p1 * p2 * k3;
            out[i] = (uint32_t)carry;
            carry >>= LIMB_BITS;
        }
        out[out_limbs] = 0;
        done = BN_lebin2bn((const unsigned char *)out, (int)(out_limbs * LIMB_BYTES), result) != NULL;
        msrt_free(out);
        for (int k = 0; k < PRIME_COUNT; k++) {
            msrt_free(residues[k]);
        }
    }
    msrt_free(la_limbs);
    if (!square) {
        msrt_free(lb_limbs);
    }
    return done;
}

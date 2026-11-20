/* The signed layer of the bignum (see bignum.h): signs, comparison, the bitwise operations, powers, roots, gcd and
 * modular arithmetic, all expressed over the magnitude kernels of bignum_mag.c. Radix conversion lives in
 * bignum_radix.c. */
#include "bignum.h"

#include <math.h>

#include "bignum_mag.h"

enum { MS_LIMB_BITS = 64 };

/* ---- ownership ---- */

static MsLimb *limbs_new(size_t count) {
    size_t bytes = 0;
    if (!ms_size_mul(count, sizeof(MsLimb), &bytes)) {
        msrt_fault("bignum: value too large", 23);
    }
    return msrt_alloc(bytes == 0 ? sizeof(MsLimb) : bytes);
}

void ms_big_free(MsBig *x) {
    msrt_free(x->limbs);
    *x = MS_BIG_ZERO;
}

/* Replaces `out` with the value of `limbs[0..len)` (taking ownership of the buffer; leading zeros are trimmed). */
static void install(MsBig *out, MsLimb *limbs, size_t len, bool negative) {
    const size_t used = ms_mag_normal_length(limbs, len);
    ms_big_free(out);
    if (used == 0) {
        msrt_free(limbs);
        return;
    }
    *out = (MsBig){.limbs = limbs, .len = used, .negative = negative};
}

void ms_big_copy(MsBig *out, const MsBig *a) {
    MsLimb *const limbs = limbs_new(a->len);
    for (size_t i = 0; i < a->len; i++) {
        limbs[i] = a->limbs[i];
    }
    install(out, limbs, a->len, a->negative);
}

void ms_big_set_u64(MsBig *out, uint64_t value) {
    MsLimb *const limbs = limbs_new(1);
    limbs[0] = value;
    install(out, limbs, 1, false);
}

void ms_big_set_i64(MsBig *out, int64_t value) {
    const uint64_t magnitude = value < 0 ? 0 - (uint64_t)value : (uint64_t)value;
    ms_big_set_u64(out, magnitude);
    out->negative = value < 0;
}

void ms_big_set_u128(MsBig *out, uint64_t high, uint64_t low, bool negative) {
    MsLimb *const limbs = limbs_new(2);
    limbs[0] = low;
    limbs[1] = high;
    install(out, limbs, 2, negative);
}

/* ---- inspection ---- */

bool ms_big_is_zero(const MsBig *a) { return a->len == 0; }

int ms_big_sign(const MsBig *a) {
    if (a->len == 0) {
        return 0;
    }
    return a->negative ? -1 : 1;
}

int ms_big_cmp_abs(const MsBig *a, const MsBig *b) { return ms_mag_cmp(a->limbs, a->len, b->limbs, b->len); }

int ms_big_cmp(const MsBig *a, const MsBig *b) {
    if (a->negative != b->negative) {
        return a->negative ? -1 : 1;
    }
    const int magnitude = ms_big_cmp_abs(a, b);
    return a->negative ? -magnitude : magnitude;
}

bool ms_big_is_odd(const MsBig *a) { return a->len > 0 && (a->limbs[0] & 1) != 0; }

size_t ms_big_bit_length(const MsBig *a) {
    if (a->len == 0) {
        return 0;
    }
    return a->len * MS_LIMB_BITS - (size_t)__builtin_clzll(a->limbs[a->len - 1]);
}

bool ms_big_magnitude_bit(const MsBig *a, size_t index) {
    const size_t limb = index / MS_LIMB_BITS;
    return limb < a->len && ((a->limbs[limb] >> (index % MS_LIMB_BITS)) & 1) != 0;
}

bool ms_big_to_i64(const MsBig *a, int64_t *out) {
    if (a->len == 0) {
        *out = 0;
        return true;
    }
    if (a->len > 1) {
        return false;
    }
    const uint64_t magnitude = a->limbs[0];
    if (a->negative) {
        if (magnitude > (uint64_t)INT64_MAX + 1) {
            return false;
        }
        *out = (int64_t)(0 - magnitude);
        return true;
    }
    if (magnitude > (uint64_t)INT64_MAX) {
        return false;
    }
    *out = (int64_t)magnitude;
    return true;
}

bool ms_big_to_u128(const MsBig *a, uint64_t *high, uint64_t *low) {
    if (a->len > 2) {
        return false;
    }
    *low = a->len > 0 ? a->limbs[0] : 0;
    *high = a->len > 1 ? a->limbs[1] : 0;
    return true;
}

double ms_big_to_double(const MsBig *a) {
    const size_t bits = ms_big_bit_length(a);
    if (bits == 0) {
        return 0.0;
    }
    uint64_t mantissa = a->limbs[0];
    size_t exponent = 0;
    if (bits > MS_LIMB_BITS) {
        /* Take the top 64 bits and fold everything below them into the lowest, so the conversion below rounds the
         * whole value to nearest, ties to even. */
        exponent = bits - MS_LIMB_BITS;
        const size_t index = exponent / MS_LIMB_BITS;
        const unsigned offset = (unsigned)(exponent % MS_LIMB_BITS);
        mantissa = a->limbs[index] >> offset;
        bool sticky = offset != 0 && (a->limbs[index] << (MS_LIMB_BITS - offset)) != 0;
        if (offset != 0) {
            mantissa |= a->limbs[index + 1] << (MS_LIMB_BITS - offset);
        }
        for (size_t i = 0; i < index && !sticky; i++) {
            sticky = a->limbs[i] != 0;
        }
        mantissa |= sticky ? 1 : 0;
    }
    const double magnitude = ldexp((double)mantissa, exponent > INT32_MAX ? INT32_MAX : (int)exponent);
    return a->negative ? -magnitude : magnitude;
}

/* ---- sign and addition ---- */

void ms_big_negate(MsBig *out, const MsBig *a) {
    const bool negative = a->len != 0 && !a->negative;
    ms_big_copy(out, a);
    out->negative = negative;
}

void ms_big_abs(MsBig *out, const MsBig *a) {
    ms_big_copy(out, a);
    out->negative = false;
}

/* out = a + (negate_b ? -b : b). */
static void add_signed(MsBig *out, const MsBig *a, const MsBig *b, bool negate_b) {
    const bool b_negative = b->len != 0 && (b->negative != negate_b);
    const bool a_negative = a->negative;
    const size_t longest = a->len > b->len ? a->len : b->len;
    MsLimb *const limbs = limbs_new(longest + 1);
    size_t len = 0;
    bool negative = a_negative;
    if (a_negative == b_negative) {
        len = ms_mag_add(limbs, a->limbs, a->len, b->limbs, b->len);
    } else if (ms_mag_cmp(a->limbs, a->len, b->limbs, b->len) >= 0) {
        len = ms_mag_sub(limbs, a->limbs, a->len, b->limbs, b->len);
    } else {
        len = ms_mag_sub(limbs, b->limbs, b->len, a->limbs, a->len);
        negative = b_negative;
    }
    install(out, limbs, len, negative);
}

void ms_big_add(MsBig *out, const MsBig *a, const MsBig *b) { add_signed(out, a, b, false); }

void ms_big_sub(MsBig *out, const MsBig *a, const MsBig *b) { add_signed(out, a, b, true); }

void ms_big_mul(MsBig *out, const MsBig *a, const MsBig *b) {
    const bool negative = a->negative != b->negative;
    if (a->len == 0 || b->len == 0) {
        ms_big_free(out);
        return;
    }
    size_t total = 0;
    if (!ms_size_add(a->len, b->len, &total)) {
        msrt_fault("bignum: product too large", 25);
    }
    MsLimb *const limbs = limbs_new(total);
    const size_t len = ms_mag_mul(limbs, a->limbs, a->len, b->limbs, b->len);
    install(out, limbs, len, negative);
}

/* ---- division ---- */

void ms_big_divmod(MsBig *quotient, MsBig *remainder, const MsBig *a, const MsBig *b) {
    const bool quotient_negative = a->negative != b->negative;
    const bool remainder_negative = a->negative;
    MsLimb *q = NULL;
    MsLimb *r = NULL;
    size_t q_len = 0;
    size_t r_len = 0;
    if (ms_mag_cmp(a->limbs, a->len, b->limbs, b->len) < 0) {
        q = limbs_new(0);
        r = limbs_new(a->len);
        for (size_t i = 0; i < a->len; i++) {
            r[i] = a->limbs[i];
        }
        r_len = a->len;
    } else {
        q = limbs_new(a->len - b->len + 1);
        r = limbs_new(b->len);
        ms_mag_divmod(q, &q_len, r, &r_len, a->limbs, a->len, b->limbs, b->len);
    }
    if (quotient != NULL) {
        install(quotient, q, q_len, quotient_negative);
    } else {
        msrt_free(q);
    }
    if (remainder != NULL) {
        install(remainder, r, r_len, remainder_negative);
    } else {
        msrt_free(r);
    }
}

void ms_big_mod_floor(MsBig *out, const MsBig *a, const MsBig *m) {
    MsBig remainder = MS_BIG_ZERO;
    ms_big_divmod(NULL, &remainder, a, m);
    if (remainder.negative) {
        ms_big_add(&remainder, &remainder, m);
    }
    ms_big_free(out);
    *out = remainder;
}

/* ---- shifts ---- */

void ms_big_shift_left(MsBig *out, const MsBig *a, size_t count) {
    const bool negative = a->negative;
    if (a->len == 0) {
        ms_big_free(out);
        return;
    }
    MsLimb *const limbs = limbs_new(a->len + count / MS_LIMB_BITS + 1);
    const size_t len = ms_mag_shl(limbs, a->limbs, a->len, count);
    install(out, limbs, len, negative);
}

void ms_big_shift_right(MsBig *out, const MsBig *a, size_t count) {
    const bool negative = a->negative;
    MsLimb *const limbs = limbs_new(a->len + 1);
    bool sticky = false;
    size_t len = ms_mag_shr(limbs, a->limbs, a->len, count, &sticky);
    if (negative && sticky) { /* floor: a negative value that loses bits moves one further from zero */
        len = ms_mag_add(limbs, limbs, len, (const MsLimb[]){1}, 1);
    }
    install(out, limbs, len, negative);
}

/* ---- bitwise operations on the infinite two's complement form ---- */

typedef enum MsBitOp { MS_BIT_AND, MS_BIT_OR, MS_BIT_XOR } MsBitOp;

/* Negates the n-limb two's complement number in place. */
static void twos_negate(MsLimb *x, size_t n) {
    MsLimb carry = 1;
    for (size_t i = 0; i < n; i++) {
        x[i] = ~x[i] + carry;
        carry = carry != 0 && x[i] == 0;
    }
}

/* Writes `a` as n limbs of two's complement; n must exceed a's length. */
static void to_twos(MsLimb *out, size_t n, const MsBig *a) {
    for (size_t i = 0; i < n; i++) {
        out[i] = i < a->len ? a->limbs[i] : 0;
    }
    if (a->negative) {
        twos_negate(out, n);
    }
}

static MsLimb apply(MsBitOp op, MsLimb x, MsLimb y) {
    switch (op) {
    case MS_BIT_AND: return x & y;
    case MS_BIT_OR: return x | y;
    case MS_BIT_XOR: return x ^ y;
    }
    return 0;
}

static void bitwise(MsBig *out, const MsBig *a, const MsBig *b, MsBitOp op) {
    const size_t n = (a->len > b->len ? a->len : b->len) + 1;
    MsLimb *const x = limbs_new(n);
    MsLimb *const y = limbs_new(n);
    to_twos(x, n, a);
    to_twos(y, n, b);
    for (size_t i = 0; i < n; i++) {
        x[i] = apply(op, x[i], y[i]);
    }
    msrt_free(y);
    const bool negative = (x[n - 1] >> (MS_LIMB_BITS - 1)) != 0;
    if (negative) {
        twos_negate(x, n);
    }
    install(out, x, n, negative);
}

void ms_big_and(MsBig *out, const MsBig *a, const MsBig *b) { bitwise(out, a, b, MS_BIT_AND); }
void ms_big_or(MsBig *out, const MsBig *a, const MsBig *b) { bitwise(out, a, b, MS_BIT_OR); }
void ms_big_xor(MsBig *out, const MsBig *a, const MsBig *b) { bitwise(out, a, b, MS_BIT_XOR); }

/* ~a = -a - 1. */
void ms_big_not(MsBig *out, const MsBig *a) {
    MsBig one = MS_BIG_ZERO;
    ms_big_set_u64(&one, 1);
    ms_big_negate(out, a);
    ms_big_sub(out, out, &one);
    ms_big_free(&one);
}

/* ---- powers and roots ---- */

void ms_big_pow(MsBig *out, const MsBig *a, uint64_t exponent) {
    MsBig result = MS_BIG_ZERO;
    MsBig base = MS_BIG_ZERO;
    ms_big_copy(&base, a);
    ms_big_set_u64(&result, 1);
    for (unsigned bit = MS_LIMB_BITS; bit > 0; bit--) { /* from the top bit down; leading zero bits keep 1 */
        ms_big_mul(&result, &result, &result);
        if (((exponent >> (bit - 1)) & 1) != 0) {
            ms_big_mul(&result, &result, &base);
        }
    }
    ms_big_free(out);
    *out = result;
    ms_big_free(&base);
}

/* 10^0 .. 10^19: the largest power of ten in a limb is 10^19. */
static const uint64_t ten_powers[20] = {
    UINT64_C(1),
    UINT64_C(10),
    UINT64_C(100),
    UINT64_C(1000),
    UINT64_C(10000),
    UINT64_C(100000),
    UINT64_C(1000000),
    UINT64_C(10000000),
    UINT64_C(100000000),
    UINT64_C(1000000000),
    UINT64_C(10000000000),
    UINT64_C(100000000000),
    UINT64_C(1000000000000),
    UINT64_C(10000000000000),
    UINT64_C(100000000000000),
    UINT64_C(1000000000000000),
    UINT64_C(10000000000000000),
    UINT64_C(100000000000000000),
    UINT64_C(1000000000000000000),
    UINT64_C(10000000000000000000),
};
enum { TEN_POWER_LIMB_DIGITS = 19 };

/* Powers up to 10^38 are two table entries multiplied in 128 bits, which covers every Decimal scale; larger ones
 * raise 10^19 to the whole number of limbs and scale by the rest. */
void ms_big_pow10(MsBig *out, size_t exponent) {
    const size_t rest = exponent % TEN_POWER_LIMB_DIGITS;
    const size_t whole = exponent / TEN_POWER_LIMB_DIGITS;
    if (whole <= 1) {
        const unsigned __int128 product = (unsigned __int128)ten_powers[rest] * (whole == 0 ? 1 : ten_powers[TEN_POWER_LIMB_DIGITS]);
        ms_big_set_u128(out, (uint64_t)(product >> 64), (uint64_t)product, false);
        return;
    }
    MsBig limb_power = MS_BIG_ZERO;
    MsBig scale = MS_BIG_ZERO;
    ms_big_set_u64(&limb_power, ten_powers[TEN_POWER_LIMB_DIGITS]);
    ms_big_set_u64(&scale, ten_powers[rest]);
    ms_big_pow(out, &limb_power, whole);
    ms_big_mul(out, out, &scale);
    ms_big_free(&limb_power);
    ms_big_free(&scale);
}

/* Newton's iteration from a power of two at or above the root: it decreases until it reaches floor(sqrt(a)). */
void ms_big_sqrt(MsBig *out, const MsBig *a) {
    if (a->len == 0) {
        ms_big_free(out);
        return;
    }
    MsBig x = MS_BIG_ZERO;
    MsBig y = MS_BIG_ZERO;
    MsBig one = MS_BIG_ZERO;
    ms_big_set_u64(&one, 1);
    ms_big_shift_left(&x, &one, (ms_big_bit_length(a) + 1) / 2);
    for (;;) {
        ms_big_divmod(&y, NULL, a, &x);
        ms_big_add(&y, &y, &x);
        ms_big_shift_right(&y, &y, 1);
        if (ms_big_cmp(&y, &x) >= 0) {
            break;
        }
        ms_big_free(&x);
        x = y;
        y = MS_BIG_ZERO;
    }
    ms_big_free(out);
    *out = x;
    ms_big_free(&y);
    ms_big_free(&one);
}

void ms_big_gcd(MsBig *out, const MsBig *a, const MsBig *b) {
    MsBig x = MS_BIG_ZERO;
    MsBig y = MS_BIG_ZERO;
    MsBig rest = MS_BIG_ZERO;
    ms_big_abs(&x, a);
    ms_big_abs(&y, b);
    while (y.len != 0) {
        ms_big_divmod(NULL, &rest, &x, &y);
        ms_big_free(&x);
        x = y;
        y = rest;
        rest = MS_BIG_ZERO;
    }
    ms_big_free(out);
    *out = x;
}

/* ---- modular arithmetic ---- */

/* base^exponent mod a one-limb modulus with every value in a machine word: no allocation per step. */
static void pow_mod_limb(MsBig *out, const MsBig *reduced_base, const MsBig *exponent, MsLimb modulus) {
    const MsLimbDivisor divisor = ms_mag_limb_divisor(modulus);
    const MsLimb base = reduced_base->len == 0 ? 0 : reduced_base->limbs[0];
    MsLimb result = 1 % modulus;
    for (size_t bit = ms_big_bit_length(exponent); bit > 0; bit--) {
        result = ms_mag_mul_mod_limb(result, result, divisor);
        if (ms_big_magnitude_bit(exponent, bit - 1)) {
            result = ms_mag_mul_mod_limb(result, base, divisor);
        }
    }
    ms_big_set_u64(out, result);
}

void ms_big_pow_mod(MsBig *out, const MsBig *a, const MsBig *exponent, const MsBig *modulus) {
    MsBig base = MS_BIG_ZERO;
    MsBig result = MS_BIG_ZERO;
    ms_big_mod_floor(&base, a, modulus);
    if (modulus->len == 1) {
        pow_mod_limb(out, &base, exponent, modulus->limbs[0]);
        ms_big_free(&base);
        return;
    }
    ms_big_set_u64(&result, 1);
    ms_big_mod_floor(&result, &result, modulus); /* 1 mod 1 is 0 */
    for (size_t bit = ms_big_bit_length(exponent); bit > 0; bit--) {
        ms_big_mul(&result, &result, &result);
        ms_big_mod_floor(&result, &result, modulus);
        if (ms_big_magnitude_bit(exponent, bit - 1)) {
            ms_big_mul(&result, &result, &base);
            ms_big_mod_floor(&result, &result, modulus);
        }
    }
    ms_big_free(out);
    *out = result;
    ms_big_free(&base);
}

/* Extended Euclid keeping only the coefficient of a: r0 = t0 * a (mod m) throughout. */
bool ms_big_inverse_mod(MsBig *out, const MsBig *a, const MsBig *modulus) {
    MsBig r0 = MS_BIG_ZERO;
    MsBig r1 = MS_BIG_ZERO;
    MsBig t0 = MS_BIG_ZERO;
    MsBig t1 = MS_BIG_ZERO;
    MsBig q = MS_BIG_ZERO;
    MsBig next = MS_BIG_ZERO;
    ms_big_copy(&r0, modulus);
    ms_big_mod_floor(&r1, a, modulus);
    ms_big_set_u64(&t1, 1);
    while (r1.len != 0) {
        ms_big_divmod(&q, &next, &r0, &r1);
        ms_big_free(&r0);
        r0 = r1;
        r1 = next;
        next = MS_BIG_ZERO;
        ms_big_mul(&next, &q, &t1);
        ms_big_sub(&next, &t0, &next);
        ms_big_free(&t0);
        t0 = t1;
        t1 = next;
        next = MS_BIG_ZERO;
    }
    const bool invertible = r0.len == 1 && r0.limbs[0] == 1;
    if (invertible) {
        ms_big_mod_floor(out, &t0, modulus);
    }
    ms_big_free(&r0);
    ms_big_free(&r1);
    ms_big_free(&t0);
    ms_big_free(&t1);
    ms_big_free(&q);
    return invertible;
}

/* Magnitude kernels of the bignum (see bignum_mag.h): addition, subtraction, multiplication with Karatsuba,
 * shifts and Knuth division. Limbs are 64 bits; products and sums go through the compiler's 128-bit integer,
 * which both clang and gcc provide on every 64-bit target we build for. Divisions by a limb multiply by a
 * precomputed reciprocal instead of dividing, which is several times faster than the compiler's 128-bit divide. */
#include "bignum_mag.h"


typedef unsigned __int128 MsWide;

enum {
    MS_LIMB_BITS = 64,
    /* Products with a shorter side below this many limbs use the schoolbook loop. */
    MS_KARATSUBA_THRESHOLD = 32,
};

/* ---- carries and single limbs ---- */

/* r = a + b over n limbs (r may be a or b); returns the carry out. */
static MsLimb add_n(MsLimb *r, const MsLimb *a, const MsLimb *b, size_t n) {
    MsLimb carry = 0;
    for (size_t i = 0; i < n; i++) {
        const MsWide sum = (MsWide)a[i] + b[i] + carry;
        r[i] = (MsLimb)sum;
        carry = (MsLimb)(sum >> MS_LIMB_BITS);
    }
    return carry;
}

/* r = a - b over n limbs (r may be a or b); returns the borrow out. */
static MsLimb sub_n(MsLimb *r, const MsLimb *a, const MsLimb *b, size_t n) {
    MsLimb borrow = 0;
    for (size_t i = 0; i < n; i++) {
        const MsLimb difference = a[i] - b[i];
        const MsLimb underflow = a[i] < b[i];
        r[i] = difference - borrow;
        borrow = underflow | (difference < borrow);
    }
    return borrow;
}

/* r += carry across n limbs; returns what is left to carry out of the top. */
static MsLimb add_carry(MsLimb *r, size_t n, MsLimb carry) {
    for (size_t i = 0; i < n && carry != 0; i++) {
        r[i] += carry;
        carry = r[i] < carry;
    }
    return carry;
}

/* r -= borrow across n limbs; returns what is left to borrow from beyond the top. */
static MsLimb sub_borrow(MsLimb *r, size_t n, MsLimb borrow) {
    for (size_t i = 0; i < n && borrow != 0; i++) {
        const MsLimb limb = r[i];
        r[i] = limb - borrow;
        borrow = limb < borrow;
    }
    return borrow;
}

/* r -= x where x_len <= r_len, with the borrow carried through the rest of r; returns the final borrow. */
static MsLimb sub_in_place(MsLimb *r, size_t r_len, const MsLimb *x, size_t x_len) {
    return sub_borrow(r + x_len, r_len - x_len, sub_n(r, r, x, x_len));
}

/* r = a * m + carry_in over n limbs (r may be a); returns the high limb. */
static MsLimb mul_limb(MsLimb *r, const MsLimb *a, size_t n, MsLimb m, MsLimb carry) {
    for (size_t i = 0; i < n; i++) {
        const MsWide product = (MsWide)a[i] * m + carry;
        r[i] = (MsLimb)product;
        carry = (MsLimb)(product >> MS_LIMB_BITS);
    }
    return carry;
}

/* r += a * m over n limbs; returns the carry limb. */
static MsLimb addmul_limb(MsLimb *r, const MsLimb *a, size_t n, MsLimb m) {
    MsLimb carry = 0;
    for (size_t i = 0; i < n; i++) {
        const MsWide product = (MsWide)a[i] * m + r[i] + carry;
        r[i] = (MsLimb)product;
        carry = (MsLimb)(product >> MS_LIMB_BITS);
    }
    return carry;
}

/* r -= a * m over n limbs; returns the borrow limb. */
static MsLimb submul_limb(MsLimb *r, const MsLimb *a, size_t n, MsLimb m) {
    MsLimb borrow = 0;
    for (size_t i = 0; i < n; i++) {
        const MsWide product = (MsWide)a[i] * m + borrow;
        const MsLimb low = (MsLimb)product;
        borrow = (MsLimb)(product >> MS_LIMB_BITS) + (r[i] < low);
        r[i] -= low;
    }
    return borrow;
}

/* ---- sizes and comparison ---- */

size_t ms_mag_normal_length(const MsLimb *a, size_t length) {
    while (length > 0 && a[length - 1] == 0) {
        length--;
    }
    return length;
}

int ms_mag_cmp(const MsLimb *a, size_t a_len, const MsLimb *b, size_t b_len) {
    if (a_len != b_len) {
        return a_len < b_len ? -1 : 1;
    }
    for (size_t i = a_len; i > 0; i--) {
        if (a[i - 1] != b[i - 1]) {
            return a[i - 1] < b[i - 1] ? -1 : 1;
        }
    }
    return 0;
}

/* ---- addition and subtraction ---- */

size_t ms_mag_add(MsLimb *r, const MsLimb *a, size_t a_len, const MsLimb *b, size_t b_len) {
    if (a_len < b_len) {
        const MsLimb *const longer = b;
        const size_t longer_len = b_len;
        b = a;
        b_len = a_len;
        a = longer;
        a_len = longer_len;
    }
    MsLimb carry = add_n(r, a, b, b_len);
    for (size_t i = b_len; i < a_len; i++) {
        r[i] = a[i] + carry;
        carry = r[i] < carry;
    }
    r[a_len] = carry;
    return ms_mag_normal_length(r, a_len + 1);
}

size_t ms_mag_sub(MsLimb *r, const MsLimb *a, size_t a_len, const MsLimb *b, size_t b_len) {
    MsLimb borrow = sub_n(r, a, b, b_len);
    for (size_t i = b_len; i < a_len; i++) {
        const MsLimb limb = a[i];
        r[i] = limb - borrow;
        borrow = limb < borrow;
    }
    return ms_mag_normal_length(r, a_len);
}

/* ---- multiplication ---- */

/* r = a * b by the schoolbook method; a_len >= b_len >= 1; r holds a_len + b_len limbs. */
static void mul_basecase(MsLimb *r, const MsLimb *a, size_t a_len, const MsLimb *b, size_t b_len) {
    r[a_len] = mul_limb(r, a, a_len, b[0], 0);
    for (size_t j = 1; j < b_len; j++) {
        r[a_len + j] = addmul_limb(r + j, a, a_len, b[j]);
    }
}

/* Scratch limbs mul_rec needs for operands of these lengths (a_len >= b_len). Recursion halves the longer
 * operand, so its depth is at most 64. */
static size_t scratch_limbs(size_t a_len, size_t b_len) {
    if (b_len < MS_KARATSUBA_THRESHOLD) {
        return 0;
    }
    const size_t half = (a_len + 1) / 2;
    if (b_len <= half) {
        return (a_len - half) + b_len + scratch_limbs(half, b_len);
    }
    return 4 * (half + 1) + scratch_limbs(half + 1, half + 1);
}

static void mul_rec(MsLimb *r, const MsLimb *a, size_t a_len, const MsLimb *b, size_t b_len, MsLimb *scratch);

/* mul_rec for operands in either order. */
static void mul_any(MsLimb *r, const MsLimb *a, size_t a_len, const MsLimb *b, size_t b_len, MsLimb *scratch) {
    if (a_len >= b_len) {
        mul_rec(r, a, a_len, b, b_len, scratch);
    } else {
        mul_rec(r, b, b_len, a, a_len, scratch); // NOLINT(readability-suspicious-call-argument): swapped on purpose
    }
}

/* r = a * b when b is no longer than half of a: the low half of a times b, plus the high half times b one
 * half up. */
static void mul_lopsided(MsLimb *r, const MsLimb *a, size_t a_len, const MsLimb *b, size_t b_len,
                         MsLimb *scratch) {
    const size_t half = (a_len + 1) / 2;
    const size_t high_len = a_len - half;
    MsLimb *const high_product = scratch;
    MsLimb *const rest = scratch + high_len + b_len;
    mul_any(r, a, half, b, b_len, rest);
    for (size_t i = half + b_len; i < a_len + b_len; i++) {
        r[i] = 0;
    }
    mul_any(high_product, a + half, high_len, b, b_len, rest);
    (void)add_n(r + half, r + half, high_product, high_len + b_len);
}

/* Adds the two halves of a number: sum = lo + hi over lo_len limbs, hi_len <= lo_len; sum has lo_len + 1. */
static void add_halves(MsLimb *sum, const MsLimb *lo, size_t lo_len, const MsLimb *hi, size_t hi_len) {
    MsLimb carry = add_n(sum, lo, hi, hi_len);
    for (size_t i = hi_len; i < lo_len; i++) {
        sum[i] = lo[i] + carry;
        carry = sum[i] < carry;
    }
    sum[lo_len] = carry;
}

/* Karatsuba: with a = a1 B^k + a0 and b = b1 B^k + b0, a*b = z2 B^2k + (z1 - z0 - z2) B^k + z0 where
 * z0 = a0 b0, z2 = a1 b1 and z1 = (a0 + a1)(b0 + b1). Needs b_len > half so b1 is not empty. */
static void mul_karatsuba(MsLimb *r, const MsLimb *a, size_t a_len, const MsLimb *b, size_t b_len,
                          MsLimb *scratch) {
    const size_t half = (a_len + 1) / 2;
    const size_t span = half + 1;
    MsLimb *const a_sum = scratch;
    MsLimb *const b_sum = scratch + span;
    MsLimb *const z1 = scratch + 2 * span;
    MsLimb *const rest = scratch + 4 * span;
    const size_t z2_len = (a_len - half) + (b_len - half);

    add_halves(a_sum, a, half, a + half, a_len - half);
    add_halves(b_sum, b, half, b + half, b_len - half);
    mul_rec(r, a, half, b, half, rest);
    mul_any(r + 2 * half, a + half, a_len - half, b + half, b_len - half, rest);
    mul_rec(z1, a_sum, span, b_sum, span, rest);
    (void)sub_in_place(z1, 2 * span, r, 2 * half); /* z1 >= z0 + z2, so no borrow leaves z1 */
    (void)sub_in_place(z1, 2 * span, r + 2 * half, z2_len);
    const size_t z1_len = ms_mag_normal_length(z1, 2 * span);
    const size_t window = a_len + b_len - half;
    const MsLimb carry = add_n(r + half, r + half, z1, z1_len);
    (void)add_carry(r + half + z1_len, window - z1_len, carry);
}

/* r = a * b with a_len >= b_len >= 1; r holds a_len + b_len limbs; `scratch` holds scratch_limbs(a_len, b_len).
 * The recursion depth is at most 64 because each level halves the longer operand. */
static void mul_rec(MsLimb *r, const MsLimb *a, size_t a_len, const MsLimb *b, size_t b_len, MsLimb *scratch) {
    if (b_len < MS_KARATSUBA_THRESHOLD) {
        mul_basecase(r, a, a_len, b, b_len);
    } else if (b_len <= (a_len + 1) / 2) {
        mul_lopsided(r, a, a_len, b, b_len, scratch);
    } else {
        mul_karatsuba(r, a, a_len, b, b_len, scratch);
    }
}

/* ---- squaring: about two thirds the work of a product ---- */

/* r = a * a over n limbs by the schoolbook method; r holds 2n limbs. Each cross product a[i] a[j] with i < j is
 * summed once, the sum is doubled, and the squares of the limbs are added. */
static void sqr_basecase(MsLimb *r, const MsLimb *a, size_t n) {
    for (size_t i = 0; i < 2 * n; i++) {
        r[i] = 0;
    }
    for (size_t i = 0; i + 1 < n; i++) {
        r[n + i] = addmul_limb(r + 2 * i + 1, a + i + 1, n - i - 1, a[i]);
    }
    MsLimb top_bit = 0;
    for (size_t i = 0; i < 2 * n; i++) { /* r <<= 1; the cross sum is below a^2 / 2, so no bit leaves */
        const MsLimb limb = r[i];
        r[i] = (limb << 1) | top_bit;
        top_bit = limb >> (MS_LIMB_BITS - 1);
    }
    MsLimb carry = 0;
    for (size_t i = 0; i < n; i++) {
        const MsWide square = (MsWide)a[i] * a[i];
        const MsWide low = (MsWide)r[2 * i] + (MsLimb)square + carry;
        r[2 * i] = (MsLimb)low;
        const MsWide high = (MsWide)r[2 * i + 1] + (MsLimb)(square >> MS_LIMB_BITS) + (MsLimb)(low >> MS_LIMB_BITS);
        r[2 * i + 1] = (MsLimb)high;
        carry = (MsLimb)(high >> MS_LIMB_BITS);
    }
}

/* Scratch limbs sqr_rec needs for n limbs. */
static size_t sqr_scratch_limbs(size_t n) {
    if (n < MS_KARATSUBA_THRESHOLD) {
        return 0;
    }
    const size_t span = (n + 1) / 2 + 1;
    return 3 * span + sqr_scratch_limbs(span);
}

/* r = a * a by Karatsuba: (a1 B^k + a0)^2 = a1^2 B^2k + ((a0 + a1)^2 - a0^2 - a1^2) B^k + a0^2. */
static void sqr_rec(MsLimb *r, const MsLimb *a, size_t n, MsLimb *scratch) {
    if (n < MS_KARATSUBA_THRESHOLD) {
        sqr_basecase(r, a, n);
        return;
    }
    const size_t half = (n + 1) / 2;
    const size_t high_len = n - half;
    const size_t span = half + 1;
    MsLimb *const a_sum = scratch;
    MsLimb *const z1 = scratch + span;
    MsLimb *const rest = scratch + 3 * span;
    add_halves(a_sum, a, half, a + half, high_len);
    sqr_rec(r, a, half, rest);
    sqr_rec(r + 2 * half, a + half, high_len, rest);
    sqr_rec(z1, a_sum, span, rest);
    (void)sub_in_place(z1, 2 * span, r, 2 * half);
    (void)sub_in_place(z1, 2 * span, r + 2 * half, 2 * high_len);
    const size_t z1_len = ms_mag_normal_length(z1, 2 * span);
    const MsLimb carry = add_n(r + half, r + half, z1, z1_len);
    (void)add_carry(r + half + z1_len, 2 * n - half - z1_len, carry);
}

size_t ms_mag_mul(MsLimb *r, const MsLimb *a, size_t a_len, const MsLimb *b, size_t b_len) {
    if (a_len < b_len) {
        const MsLimb *const longer = b;
        const size_t longer_len = b_len;
        b = a;
        b_len = a_len;
        a = longer;
        a_len = longer_len;
    }
    if (b_len == 0) {
        return 0;
    }
    const bool square = a == b && a_len == b_len;
    const size_t scratch_len = square ? sqr_scratch_limbs(a_len) : scratch_limbs(a_len, b_len);
    size_t scratch_bytes = 0;
    if (!ms_size_mul(scratch_len, sizeof(MsLimb), &scratch_bytes)) {
        msrt_fault("bignum: product too large", 25);
    }
    MsLimb *const scratch = msrt_alloc(scratch_bytes == 0 ? sizeof(MsLimb) : scratch_bytes);
    if (square) {
        sqr_rec(r, a, a_len, scratch);
    } else {
        mul_rec(r, a, a_len, b, b_len, scratch);
    }
    msrt_free(scratch);
    return ms_mag_normal_length(r, a_len + b_len);
}

/* ---- shifts ---- */

size_t ms_mag_shl(MsLimb *r, const MsLimb *a, size_t a_len, size_t count) {
    const size_t whole = count / MS_LIMB_BITS;
    const unsigned bits = (unsigned)(count % MS_LIMB_BITS);
    for (size_t i = 0; i < whole; i++) {
        r[i] = 0;
    }
    MsLimb carry = 0;
    for (size_t i = 0; i < a_len; i++) {
        r[whole + i] = bits == 0 ? a[i] : (a[i] << bits) | carry;
        carry = bits == 0 ? 0 : a[i] >> (MS_LIMB_BITS - bits);
    }
    r[whole + a_len] = carry;
    return ms_mag_normal_length(r, whole + a_len + 1);
}

size_t ms_mag_shr(MsLimb *r, const MsLimb *a, size_t a_len, size_t count, bool *sticky) {
    const size_t whole = count / MS_LIMB_BITS;
    const unsigned bits = (unsigned)(count % MS_LIMB_BITS);
    *sticky = false;
    for (size_t i = 0; i < whole && i < a_len; i++) {
        *sticky = *sticky || a[i] != 0;
    }
    if (whole >= a_len) {
        return 0;
    }
    if (bits != 0) {
        *sticky = *sticky || (a[whole] << (MS_LIMB_BITS - bits)) != 0;
    }
    const size_t kept = a_len - whole;
    for (size_t i = 0; i < kept; i++) {
        const MsLimb low = a[whole + i] >> bits;
        const MsLimb high = (bits != 0 && whole + i + 1 < a_len) ? a[whole + i + 1] << (MS_LIMB_BITS - bits) : 0;
        r[i] = low | high;
    }
    return ms_mag_normal_length(r, kept);
}

/* ---- division ---- */

MsLimbDivisor ms_mag_limb_divisor(MsLimb divisor) {
    const unsigned shift = (unsigned)__builtin_clzll(divisor);
    const MsLimb normalized = divisor << shift;
    const MsWide numerator = ((MsWide)~normalized << MS_LIMB_BITS) | UINT64_MAX;
    return (MsLimbDivisor){
        .normalized = normalized, .reciprocal = (MsLimb)(numerator / normalized), .shift = shift};
}

/* The quotient and remainder of (high, low) / divisor.normalized; high must be below the divisor. */
static MsLimb divide_two_limbs(MsLimb *remainder, MsLimb high, MsLimb low, const MsLimbDivisor *divisor) {
    const MsLimb d = divisor->normalized;
    MsWide product = (MsWide)divisor->reciprocal * high;
    product += ((MsWide)high << MS_LIMB_BITS) | low;
    MsLimb quotient = (MsLimb)(product >> MS_LIMB_BITS) + 1;
    MsLimb rest = low - quotient * d;
    if (rest > (MsLimb)product) {
        quotient--;
        rest += d;
    }
    if (rest >= d) {
        quotient++;
        rest -= d;
    }
    *remainder = rest;
    return quotient;
}

MsLimb ms_mag_divmod_limb(MsLimb *a, size_t a_len, MsLimbDivisor divisor) {
    const unsigned shift = divisor.shift;
    MsLimb remainder = (shift != 0 && a_len > 0) ? a[a_len - 1] >> (MS_LIMB_BITS - shift) : 0;
    for (size_t i = a_len; i > 0; i--) {
        const MsLimb below = (shift != 0 && i > 1) ? a[i - 2] >> (MS_LIMB_BITS - shift) : 0;
        const MsLimb limb = (a[i - 1] << shift) | below;
        a[i - 1] = divide_two_limbs(&remainder, remainder, limb, &divisor);
    }
    return remainder >> shift;
}

MsLimb ms_mag_mul_mod_limb(MsLimb a, MsLimb b, MsLimbDivisor divisor) {
    const MsWide product = (MsWide)a * b;
    const unsigned shift = divisor.shift;
    MsLimb high = (MsLimb)(product >> MS_LIMB_BITS);
    MsLimb low = (MsLimb)product;
    if (shift != 0) { /* shifted left with the divisor, the high word stays below it because a, b < divisor */
        high = (high << shift) | (low >> (MS_LIMB_BITS - shift));
        low <<= shift;
    }
    MsLimb remainder = 0;
    (void)divide_two_limbs(&remainder, high, low, &divisor);
    return remainder >> shift;
}

MsLimb ms_mag_mul_add_limb(MsLimb *a, size_t a_len, MsLimb factor, MsLimb addend) {
    return mul_limb(a, a, a_len, factor, addend);
}

/* q = u / v for the normalised v (top bit set) of n >= 2 limbs and u of u_len = m + n + 1 limbs: Knuth's
 * algorithm D. q receives m + 1 limbs; u becomes the remainder (still shifted) in its low n limbs. */
static void divide_normalized(MsLimb *q, MsLimb *u, size_t u_len, const MsLimb *v, size_t n) {
    const MsLimbDivisor divisor = ms_mag_limb_divisor(v[n - 1]); /* already normalised: shift 0 */
    for (size_t j = u_len - n; j-- > 0;) {
        MsLimb quotient = 0;
        MsLimb remainder = 0;
        bool remainder_overflow = false;
        if (u[j + n] >= v[n - 1]) {
            quotient = UINT64_MAX;
            remainder_overflow = __builtin_add_overflow(u[j + n - 1], v[n - 1], &remainder);
        } else {
            quotient = divide_two_limbs(&remainder, u[j + n], u[j + n - 1], &divisor);
        }
        while (!remainder_overflow && (MsWide)quotient * v[n - 2] > (((MsWide)remainder << MS_LIMB_BITS) | u[j + n - 2])) {
            quotient--;
            remainder_overflow = __builtin_add_overflow(remainder, v[n - 1], &remainder);
        }
        const MsLimb borrow = submul_limb(u + j, v, n, quotient);
        const bool negative = u[j + n] < borrow;
        u[j + n] -= borrow;
        if (negative) {
            quotient--;
            u[j + n] += add_n(u + j, u + j, v, n);
        }
        q[j] = quotient;
    }
}

void ms_mag_divmod(MsLimb *q, size_t *q_len, MsLimb *r, size_t *r_len, const MsLimb *a, size_t a_len,
                   const MsLimb *b, size_t b_len) {
    if (b_len == 1) {
        const MsLimbDivisor divisor = ms_mag_limb_divisor(b[0]);
        for (size_t i = 0; i < a_len; i++) {
            q[i] = a[i];
        }
        r[0] = ms_mag_divmod_limb(q, a_len, divisor);
        *q_len = ms_mag_normal_length(q, a_len);
        *r_len = ms_mag_normal_length(r, 1);
        return;
    }
    const unsigned shift = (unsigned)__builtin_clzll(b[b_len - 1]);
    size_t bytes = 0;
    if (!ms_size_mul(a_len + b_len + 2, sizeof(MsLimb), &bytes)) {
        msrt_fault("bignum: quotient too large", 26);
    }
    MsLimb *const u = msrt_alloc(bytes);
    MsLimb *const v = u + a_len + 1;
    (void)ms_mag_shl(v, b, b_len, shift); /* the shift is below one limb, so v keeps b_len limbs */
    (void)ms_mag_shl(u, a, a_len, shift);
    divide_normalized(q, u, a_len + 1, v, b_len);
    bool sticky = false;
    *r_len = ms_mag_shr(r, u, b_len, shift, &sticky);
    *q_len = ms_mag_normal_length(q, a_len - b_len + 1);
    msrt_free(u);
}

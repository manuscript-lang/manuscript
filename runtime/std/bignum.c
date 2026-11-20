/* The bignum of bignum.h on OpenSSL's BIGNUM: arithmetic, comparison, shifts, powers, gcd and modular inverses
 * are BN_* calls; this file adds what BIGNUM lacks (floor shifts, two's complement bitwise operations, integer
 * square roots, correctly rounded doubles, 128-bit and int64 conversion, text in any radix). */
#include "bignum.h"
#include "bignum_ntt.h"

#include <limits.h>
#include <math.h>
#include <openssl/crypto.h>
#include <openssl/err.h>
#include <stdlib.h>
#include <string.h>

typedef unsigned __int128 U128;

enum { BITS_PER_BYTE = 8 };

/* ---- plumbing ---- */

/* A BN_* call fails when OpenSSL's size cap (about 2^29 bits) is reached or when memory runs out; each faults as the
 * rest of the runtime does. */
static void must(int ok) {
    if (ok != 0) {
        return;
    }
    const int reason = ERR_GET_REASON(ERR_peek_last_error());
    ERR_clear_error();
    if (reason == BN_R_BIGNUM_TOO_LONG) {
        static const char message[] = "bignum: result exceeds the largest supported size";
        msfault_raise(MS_FAULT_OVERFLOW, message, sizeof message - 1);
    }
    static const char message[] = "bignum: out of memory";
    msfault_raise(MS_FAULT_OUT_OF_MEMORY, message, sizeof message - 1);
}

/* Decimal and BigInt operations are short and many, so each thread keeps a few released BIGNUMs (and one context)
 * for reuse instead of going through malloc for every operation; they live until the thread exits. */
enum { POOL_SIZE = 16, POOL_MAX_BITS = 4096 }; /* larger values are not worth keeping */

typedef struct Pool {
    BIGNUM *free_list[POOL_SIZE];
    size_t count;
    BN_CTX *ctx;
    BIGNUM *limit; /* 2^POOL_MAX_BITS: BN_ucmp against it is much cheaper than BN_num_bits */
} Pool;

static Pool *pool(void) {
    static _Thread_local Pool state;
    return &state;
}

static BIGNUM *new_bn(void) {
    Pool *const p = pool();
    if (p->count > 0) {
        return p->free_list[--p->count];
    }
    BIGNUM *const bn = BN_new();
    must(bn != NULL);
    return bn;
}

static const BIGNUM *pool_limit(void) {
    Pool *const p = pool();
    if (p->limit == NULL) {
        p->limit = BN_new();
        must(p->limit != NULL && BN_set_bit(p->limit, POOL_MAX_BITS));
    }
    return p->limit;
}

static bool is_wide(const MsBig *a) { return a != NULL && a->bn != NULL && BN_ucmp(a->bn, pool_limit()) >= 0; }

static void release_bn(BIGNUM *bn) {
    if (bn == NULL) {
        return;
    }
    Pool *const p = pool();
    if (p->count == POOL_SIZE || BN_ucmp(bn, pool_limit()) >= 0) {
        BN_free(bn);
        return;
    }
    BN_zero(bn);
    p->free_list[p->count++] = bn;
}

/* The thread's context for one operation's temporaries. */
static BN_CTX *new_ctx(void) {
    Pool *const p = pool();
    if (p->ctx == NULL) {
        p->ctx = BN_CTX_new();
        must(p->ctx != NULL);
    }
    return p->ctx;
}

/* The shared read-only zero that stands in for an operand with no BIGNUM. */
static const BIGNUM *zero_bn(void) {
    static _Thread_local BIGNUM *zero;
    if (zero == NULL) {
        zero = new_bn();
        BN_zero(zero);
    }
    return zero;
}

static const BIGNUM *value_of(const MsBig *a) { return a->bn != NULL ? a->bn : zero_bn(); }

/* A scratch BIGNUM for the result of an operation on `a` and `b`: `out`'s own when it is neither operand's. */
static BIGNUM *result_begin(MsBig *out, const MsBig *a, const MsBig *b) {
    const bool overlaps = out->bn != NULL && (out->bn == a->bn || (b != NULL && out->bn == b->bn));
    if (overlaps || out->bn == NULL) {
        return new_bn();
    }
    return out->bn;
}

/* Makes `result` (from result_begin) the value of `out`. */
static void result_end(MsBig *out, BIGNUM *result) {
    if (out->bn == result) {
        return;
    }
    release_bn(out->bn);
    out->bn = result;
}

/* Like result_end for an operation whose result can be much smaller than its operands (a difference, a remainder,
 * a shift right). When an operand was at least POOL_MAX_BITS wide the result moves into a right-sized BIGNUM, and
 * the context's temporaries are released: a thread does not keep the buffers of the widest value it ever saw.
 * `wide` is computed before the operation, since `out` may be an operand. */
static void result_end_shrinking(MsBig *out, BIGNUM *result, bool wide) {
    BIGNUM *final = result;
    if (wide) {
        Pool *const p = pool();
        BN_CTX_free(p->ctx);
        p->ctx = NULL;
        if (BN_ucmp(result, pool_limit()) < 0) {
            final = BN_dup(result);
            must(final != NULL);
            BN_free(result);
        }
    }
    if (out->bn != result) {
        release_bn(out->bn);
    }
    out->bn = final;
}

/* Runs `op` into a fresh result for binary operations that BN_* permits to share no storage with an operand. */
typedef int (*BinaryOp)(BIGNUM *r, const BIGNUM *a, const BIGNUM *b, BN_CTX *ctx);

static void binary(MsBig *out, const MsBig *a, const MsBig *b, BinaryOp op) {
    BIGNUM *const result = result_begin(out, a, b);
    BN_CTX *const ctx = new_ctx();
    must(op(result, value_of(a), value_of(b), ctx));
    result_end(out, result);
}

/* ---- construction and inspection ---- */

void ms_big_free(MsBig *x) {
    release_bn(x->bn);
    x->bn = NULL;
}

void ms_big_copy(MsBig *out, const MsBig *a) {
    if (out->bn == a->bn) {
        return;
    }
    BIGNUM *const result = new_bn();
    must(BN_copy(result, value_of(a)) != NULL);
    result_end(out, result);
}

/* Sets `out` to the little-endian bytes as a magnitude. */
static void set_le(MsBig *out, const uint8_t *bytes, size_t length, bool negative) {
    BIGNUM *const result = new_bn();
    must(BN_lebin2bn(bytes, (int)length, result) != NULL);
    BN_set_negative(result, negative && !BN_is_zero(result));
    result_end(out, result);
}

void ms_big_set_u128(MsBig *out, uint64_t high, uint64_t low, bool negative) {
    if (sizeof(BN_ULONG) == sizeof low) { /* two words, no byte shuffling */
        BIGNUM *const result = new_bn();
        must(BN_set_word(result, (BN_ULONG)high));
        if (high != 0) {
            must(BN_lshift(result, result, 64));
        }
        must(BN_add_word(result, (BN_ULONG)low));
        BN_set_negative(result, negative && !BN_is_zero(result));
        result_end(out, result);
        return;
    }
    uint8_t bytes[16];
    for (int i = 0; i < 8; i++) {
        bytes[i] = (uint8_t)(low >> (BITS_PER_BYTE * i));
        bytes[8 + i] = (uint8_t)(high >> (BITS_PER_BYTE * i));
    }
    set_le(out, bytes, sizeof bytes, negative);
}

void ms_big_set_u64(MsBig *out, uint64_t value) { ms_big_set_u128(out, 0, value, false); }

void ms_big_set_i64(MsBig *out, int64_t value) {
    const uint64_t magnitude = value < 0 ? UINT64_C(0) - (uint64_t)value : (uint64_t)value;
    ms_big_set_u128(out, 0, magnitude, value < 0);
}

bool ms_big_is_zero(const MsBig *a) { return a->bn == NULL || BN_is_zero(a->bn); }

int ms_big_sign(const MsBig *a) {
    if (ms_big_is_zero(a)) {
        return 0;
    }
    return BN_is_negative(a->bn) ? -1 : 1;
}

int ms_big_cmp(const MsBig *a, const MsBig *b) { return BN_cmp(value_of(a), value_of(b)); }
int ms_big_cmp_abs(const MsBig *a, const MsBig *b) { return BN_ucmp(value_of(a), value_of(b)); }
bool ms_big_is_odd(const MsBig *a) { return a->bn != NULL && BN_is_odd(a->bn); }
size_t ms_big_bit_length(const MsBig *a) { return (size_t)BN_num_bits(value_of(a)); }

bool ms_big_magnitude_bit(const MsBig *a, size_t index) {
    return index <= INT_MAX && BN_is_bit_set(value_of(a), (int)index);
}

/* ---- arithmetic ---- */

void ms_big_negate(MsBig *out, const MsBig *a) {
    ms_big_copy(out, a);
    if (out->bn != NULL && !BN_is_zero(out->bn)) {
        BN_set_negative(out->bn, !BN_is_negative(out->bn));
    }
}

void ms_big_abs(MsBig *out, const MsBig *a) {
    ms_big_copy(out, a);
    if (out->bn != NULL) {
        BN_set_negative(out->bn, 0);
    }
}

void ms_big_add(MsBig *out, const MsBig *a, const MsBig *b) {
    BIGNUM *const result = result_begin(out, a, b);
    must(BN_add(result, value_of(a), value_of(b)));
    result_end(out, result);
}

void ms_big_sub(MsBig *out, const MsBig *a, const MsBig *b) {
    const bool wide = is_wide(a) || is_wide(b);
    BIGNUM *const result = result_begin(out, a, b);
    must(BN_sub(result, value_of(a), value_of(b)));
    result_end_shrinking(out, result, wide);
}

enum { NTT_MIN_BITS = 1 << 16 }; /* below this OpenSSL's Karatsuba multiply is faster than the transforms */

/* Wide products go through number-theoretic transforms. The cheap pool-limit test rejects small operands first. */
static bool use_transform(const BIGNUM *a, const BIGNUM *b) {
    if (BN_ucmp(a, pool_limit()) < 0 || BN_ucmp(b, pool_limit()) < 0) {
        return false;
    }
    return BN_num_bits(a) >= NTT_MIN_BITS && BN_num_bits(b) >= NTT_MIN_BITS;
}

void ms_big_mul(MsBig *out, const MsBig *a, const MsBig *b) {
    const BIGNUM *const x = value_of(a);
    const BIGNUM *const y = value_of(b);
    if (use_transform(x, y)) {
        BIGNUM *const result = result_begin(out, a, b);
        if (ms_ntt_multiply(result, x, y)) {
            BN_set_negative(result, BN_is_negative(x) != BN_is_negative(y));
            result_end(out, result);
            return;
        }
        if (result != out->bn) {
            release_bn(result);
        }
    }
    binary(out, a, b, BN_mul);
}

void ms_big_divmod(MsBig *quotient, MsBig *remainder, const MsBig *a, const MsBig *b) {
    const bool wide = is_wide(a) || is_wide(b);
    BIGNUM *const q = new_bn();
    BIGNUM *const r = new_bn();
    BN_CTX *const ctx = new_ctx();
    must(BN_div(q, r, value_of(a), value_of(b), ctx));
    if (quotient != NULL) {
        result_end_shrinking(quotient, q, wide);
    } else {
        release_bn(q);
    }
    if (remainder != NULL) {
        result_end_shrinking(remainder, r, wide);
    } else {
        release_bn(r);
    }
}

void ms_big_mod_floor(MsBig *out, const MsBig *a, const MsBig *m) {
    const bool wide = is_wide(a) || is_wide(m);
    BIGNUM *const result = result_begin(out, a, m);
    BN_CTX *const ctx = new_ctx();
    must(BN_nnmod(result, value_of(a), value_of(m), ctx));
    result_end_shrinking(out, result, wide);
}

/* ---- shifts and bitwise operations ---- */

static int shift_count(size_t count) { return count > (size_t)INT_MAX ? INT_MAX : (int)count; }

void ms_big_shift_left(MsBig *out, const MsBig *a, size_t count) {
    BIGNUM *const result = result_begin(out, a, NULL);
    must(BN_lshift(result, value_of(a), shift_count(count)));
    result_end(out, result);
}

/* Rounds toward negative infinity: a negative value that loses a set bit moves one further from zero. */
void ms_big_shift_right(MsBig *out, const MsBig *a, size_t count) {
    const bool wide = is_wide(a);
    const BIGNUM *const value = value_of(a);
    const int bits = shift_count(count);
    BIGNUM *const result = new_bn();
    must(BN_rshift(result, value, bits));
    if (BN_is_negative(value)) {
        BIGNUM *const back = new_bn();
        must(BN_lshift(back, result, bits));
        if (BN_ucmp(back, value) != 0) {
            must(BN_sub(result, result, BN_value_one()));
        }
        release_bn(back);
    }
    result_end_shrinking(out, result, wide);
}

/* The two's complement of `a` as `width` little-endian bytes (width covers the magnitude and a sign bit). */
static void to_twos(const BIGNUM *a, uint8_t *bytes, size_t width) {
    must(BN_bn2lebinpad(a, bytes, (int)width) >= 0);
    if (!BN_is_negative(a)) {
        return;
    }
    unsigned carry = 1;
    for (size_t i = 0; i < width; i++) {
        const unsigned sum = (uint8_t)~bytes[i] + carry;
        bytes[i] = (uint8_t)sum;
        carry = sum >> BITS_PER_BYTE;
    }
}

/* Sets `out` to the value of `width` two's complement bytes. */
static void from_twos(MsBig *out, uint8_t *bytes, size_t width) {
    const bool negative = (bytes[width - 1] & 0x80) != 0;
    if (negative) {
        unsigned carry = 1;
        for (size_t i = 0; i < width; i++) {
            const unsigned sum = (uint8_t)~bytes[i] + carry;
            bytes[i] = (uint8_t)sum;
            carry = sum >> BITS_PER_BYTE;
        }
    }
    set_le(out, bytes, width, negative);
}

typedef uint8_t (*ByteOp)(uint8_t x, uint8_t y);

static uint8_t byte_and(uint8_t x, uint8_t y) { return (uint8_t)(x & y); }
static uint8_t byte_or(uint8_t x, uint8_t y) { return (uint8_t)(x | y); }
static uint8_t byte_xor(uint8_t x, uint8_t y) { return (uint8_t)(x ^ y); }

static void bitwise(MsBig *out, const MsBig *a, const MsBig *b, ByteOp op) {
    const BIGNUM *const x = value_of(a);
    const BIGNUM *const y = value_of(b);
    const int bits = BN_num_bits(x) > BN_num_bits(y) ? BN_num_bits(x) : BN_num_bits(y);
    const size_t width = (size_t)bits / BITS_PER_BYTE + 1; /* room for the sign bit */
    uint8_t *const left = msrt_alloc(2 * width);
    uint8_t *const right = left + width;
    to_twos(x, left, width);
    to_twos(y, right, width);
    for (size_t i = 0; i < width; i++) {
        left[i] = op(left[i], right[i]);
    }
    from_twos(out, left, width);
    msrt_free(left);
}

void ms_big_and(MsBig *out, const MsBig *a, const MsBig *b) { bitwise(out, a, b, byte_and); }
void ms_big_or(MsBig *out, const MsBig *a, const MsBig *b) { bitwise(out, a, b, byte_or); }
void ms_big_xor(MsBig *out, const MsBig *a, const MsBig *b) { bitwise(out, a, b, byte_xor); }

/* ~a = -a - 1. */
void ms_big_not(MsBig *out, const MsBig *a) {
    BIGNUM *const result = result_begin(out, a, NULL);
    must(BN_set_word(result, 1));
    BN_set_negative(result, 1);
    must(BN_sub(result, result, value_of(a)));
    result_end(out, result);
}

/* ---- powers, roots and number theory ---- */

/* True when |a| is a power of two other than one (exactly one bit set, above bit 0). */
static bool is_power_of_two(const BIGNUM *a) {
    const int bits = BN_num_bits(a);
    if (bits < 2) {
        return false;
    }
    BIGNUM *const rest = new_bn();
    must(BN_copy(rest, a) != NULL);
    must(BN_clear_bit(rest, bits - 1));
    const bool single = BN_is_zero(rest);
    release_bn(rest);
    return single;
}

/* (+-2^k)^e is +-2^(k*e): one shift, where repeated squaring of a huge power of two would take seconds. */
static bool pow_of_two(MsBig *out, const BIGNUM *a, uint64_t exponent) {
    if (!is_power_of_two(a)) {
        return false;
    }
    const uint64_t k = (uint64_t)BN_num_bits(a) - 1;
    if (exponent > (uint64_t)INT_MAX / k) {
        ms_fault_text("bignum: value too large", 23);
    }
    BIGNUM *const result = new_bn();
    BN_zero(result);
    must(BN_set_bit(result, (int)(k * exponent)));
    BN_set_negative(result, BN_is_negative(a) && (exponent & 1) != 0);
    result_end(out, result);
    return true;
}

/* Left-to-right square and multiply through ms_big_mul, so wide squares take the transform. */
static void pow_by_squaring(MsBig *out, const MsBig *a, uint64_t exponent) {
    MsBig base = MS_BIG_ZERO;
    ms_big_copy(&base, a);
    MsBig result = MS_BIG_ZERO;
    ms_big_set_u64(&result, 1);
    for (int bit = 63 - __builtin_clzll(exponent); bit >= 0; bit--) {
        ms_big_mul(&result, &result, &result);
        if (((exponent >> bit) & 1) != 0) {
            ms_big_mul(&result, &result, &base);
        }
    }
    ms_big_free(&base);
    ms_big_free(out);
    *out = result;
}

enum { POW_BY_SQUARING_BITS = 1 << 16 }; /* results this wide gain from the transform multiply */

void ms_big_pow(MsBig *out, const MsBig *a, uint64_t exponent) {
    if (pow_of_two(out, value_of(a), exponent)) {
        return;
    }
    const uint64_t estimate = (uint64_t)BN_num_bits(value_of(a)) * (exponent > POW_BY_SQUARING_BITS ? POW_BY_SQUARING_BITS : exponent);
    if (exponent > 1 && estimate >= POW_BY_SQUARING_BITS) {
        pow_by_squaring(out, a, exponent);
        return;
    }
    MsBig power = MS_BIG_ZERO;
    ms_big_set_u64(&power, exponent);
    BIGNUM *const result = new_bn();
    BN_CTX *const ctx = new_ctx();
    must(BN_exp(result, value_of(a), power.bn, ctx));
    ms_big_free(&power);
    result_end(out, result);
}

enum { POW10_TABLE = 39 }; /* 10^38 is the largest power of ten in 128 bits */

static U128 ten_power_u128(size_t exponent) {
    U128 value = 1;
    for (size_t i = 0; i < exponent; i++) {
        value *= 10;
    }
    return value;
}

void ms_big_pow10(MsBig *out, size_t exponent) {
    if (exponent < POW10_TABLE) {
        const U128 value = ten_power_u128(exponent);
        ms_big_set_u128(out, (uint64_t)(value >> 64), (uint64_t)value, false);
        return;
    }
    MsBig ten = MS_BIG_ZERO;
    ms_big_set_u64(&ten, 10);
    ms_big_pow(out, &ten, exponent);
    ms_big_free(&ten);
}

/* floor(sqrt(a)) by Newton's iteration from a power of two above the root. */
void ms_big_sqrt(MsBig *out, const MsBig *a) {
    if (ms_big_is_zero(a)) {
        ms_big_set_u64(out, 0);
        return;
    }
    BN_CTX *const ctx = new_ctx();
    BIGNUM *const x = new_bn();
    BIGNUM *const y = new_bn();
    BIGNUM *const quotient = new_bn();
    must(BN_set_bit(x, (BN_num_bits(a->bn) + 1) / 2));
    for (;;) {
        must(BN_div(quotient, NULL, a->bn, x, ctx));
        must(BN_add(y, x, quotient));
        must(BN_rshift1(y, y));
        if (BN_cmp(y, x) >= 0) {
            break;
        }
        must(BN_copy(x, y) != NULL);
    }
    release_bn(y);
    release_bn(quotient);
    result_end(out, x);
}

void ms_big_gcd(MsBig *out, const MsBig *a, const MsBig *b) {
    /* Euclid's remainders: BN_gcd is the constant-time binary algorithm, many times slower on wide operands. */
    const bool wide = is_wide(a) || is_wide(b);
    BIGNUM *larger = new_bn();
    BIGNUM *smaller = new_bn();
    BIGNUM *rest = new_bn();
    BN_CTX *const ctx = new_ctx();
    must(BN_copy(larger, value_of(a)) != NULL && BN_copy(smaller, value_of(b)) != NULL);
    BN_set_negative(larger, 0);
    BN_set_negative(smaller, 0);
    while (!BN_is_zero(smaller)) {
        must(BN_mod(rest, larger, smaller, ctx));
        BIGNUM *const next = larger;
        larger = smaller;
        smaller = rest;
        rest = next;
    }
    if (wide) { /* the remainders still own buffers as wide as the operands */
        BN_free(smaller);
        BN_free(rest);
    } else {
        release_bn(smaller);
        release_bn(rest);
    }
    result_end_shrinking(out, larger, wide);
}

void ms_big_pow_mod(MsBig *out, const MsBig *a, const MsBig *exponent, const MsBig *modulus) {
    BIGNUM *const result = new_bn();
    BIGNUM *const base = new_bn();
    BN_CTX *const ctx = new_ctx();
    must(BN_nnmod(base, value_of(a), value_of(modulus), ctx));
    must(BN_mod_exp(result, base, value_of(exponent), value_of(modulus), ctx));
    release_bn(base);
    result_end(out, result);
}

bool ms_big_inverse_mod(MsBig *out, const MsBig *a, const MsBig *modulus) {
    BIGNUM *const base = new_bn();
    BN_CTX *const ctx = new_ctx();
    must(BN_nnmod(base, value_of(a), value_of(modulus), ctx));
    BIGNUM *const result = BN_mod_inverse(NULL, base, value_of(modulus), ctx);
    release_bn(base);
    if (result == NULL) {
        const bool none = ERR_GET_REASON(ERR_peek_last_error()) == BN_R_NO_INVERSE;
        ERR_clear_error();
        must(none);
        return false;
    }
    result_end(out, result);
    return true;
}

/* ---- conversions ---- */

/* The low 64 bits of the magnitude; `a` must have at most 64 bits. */
static uint64_t low_word(const BIGNUM *a) {
    uint8_t bytes[8];
    must(BN_bn2lebinpad(a, bytes, sizeof bytes) >= 0);
    uint64_t word = 0;
    for (int i = 7; i >= 0; i--) {
        word = word << BITS_PER_BYTE | bytes[i];
    }
    return word;
}

/* The nearest double, ties to even: the top 64 bits with a sticky bit for the rest round once in the cast. */
double ms_big_to_double(const MsBig *a) {
    const BIGNUM *const value = value_of(a);
    const int bits = BN_num_bits(value);
    double magnitude;
    if (bits <= 64) {
        magnitude = (double)low_word(value);
    } else {
        BIGNUM *const top = new_bn();
        BIGNUM *const back = new_bn();
        must(BN_rshift(top, value, bits - 64));
        must(BN_lshift(back, top, bits - 64));
        uint64_t word = low_word(top);
        if (BN_ucmp(back, value) != 0) {
            word |= 1;
        }
        release_bn(top);
        release_bn(back);
        magnitude = ldexp((double)word, bits - 64);
    }
    return BN_is_negative(value) ? -magnitude : magnitude;
}

bool ms_big_to_u128(const MsBig *a, uint64_t *high, uint64_t *low) {
    const BIGNUM *const value = value_of(a);
    const int bits = BN_num_bits(value);
    if (bits > 128) {
        return false;
    }
    if (bits <= 64 && sizeof(BN_ULONG) == sizeof *low) {
        *high = 0;
        *low = BN_get_word(value);
        return true;
    }
    if (sizeof(BN_ULONG) == sizeof *low) { /* the low word is the value less its high word shifted back */
        BIGNUM *const part = new_bn();
        must(BN_rshift(part, value, 64));
        *high = BN_get_word(part);
        must(BN_copy(part, value) != NULL);
        must(BN_mask_bits(part, 64));
        *low = BN_get_word(part);
        release_bn(part);
        return true;
    }
    uint8_t bytes[16];
    must(BN_bn2lebinpad(value, bytes, sizeof bytes) >= 0);
    *low = 0;
    *high = 0;
    for (int i = 7; i >= 0; i--) {
        *low = *low << BITS_PER_BYTE | bytes[i];
        *high = *high << BITS_PER_BYTE | bytes[8 + i];
    }
    return true;
}

bool ms_big_to_i64(const MsBig *a, int64_t *out) {
    const BIGNUM *const value = value_of(a);
    if (BN_num_bits(value) > 64) {
        return false;
    }
    const uint64_t magnitude = low_word(value);
    if (BN_is_negative(value)) {
        if (magnitude > UINT64_C(1) << 63) {
            return false;
        }
        *out = (int64_t)(UINT64_C(0) - magnitude);
        return true;
    }
    if (magnitude > (uint64_t)INT64_MAX) {
        return false;
    }
    *out = (int64_t)magnitude;
    return true;
}

/* ---- text ---- */

uint8_t ms_big_digit_value(uint8_t byte) {
    if (byte >= '0' && byte <= '9') {
        return (uint8_t)(byte - '0');
    }
    if (byte >= 'a' && byte <= 'z') {
        return (uint8_t)(byte - 'a' + 10);
    }
    if (byte >= 'A' && byte <= 'Z') {
        return (uint8_t)(byte - 'A' + 10);
    }
    return 255;
}

/* The digits per BN_ULONG chunk of a radix: the largest k with radix^k in a BN_ULONG, and that power. */
static size_t chunk_of(unsigned radix, uint64_t *power) {
    size_t digits = 0;
    uint64_t p = 1;
    while (p <= (uint64_t)(BN_ULONG)-1 / radix) {
        p *= radix;
        digits++;
    }
    *power = p;
    return digits;
}

/* Digits of a power-of-two radix packed straight into the little-endian bytes of the value. */
static void parse_digits_by_bits(MsBig *out, MsBytes digits, unsigned radix) {
    unsigned bits_per_digit = 1;
    while ((1u << bits_per_digit) < radix) {
        bits_per_digit++;
    }
    const size_t bytes = (digits.len * bits_per_digit + BITS_PER_BYTE - 1) / BITS_PER_BYTE;
    uint8_t *const magnitude = msrt_alloc(bytes + 1);
    memset(magnitude, 0, bytes + 1);
    for (size_t i = 0; i < digits.len; i++) {
        const unsigned value = ms_big_digit_value(digits.ptr[digits.len - 1 - i]);
        for (unsigned k = 0; k < bits_per_digit; k++) {
            const size_t bit = i * bits_per_digit + k;
            magnitude[bit / BITS_PER_BYTE] |= (uint8_t)(((value >> k) & 1u) << (bit % BITS_PER_BYTE));
        }
    }
    BIGNUM *const result = new_bn();
    must(BN_lebin2bn(magnitude, (int)bytes, result) != NULL);
    msrt_free(magnitude);
    result_end(out, result);
}

void ms_big_parse_digits(MsBig *out, MsBytes digits, unsigned radix) {
    if ((radix & (radix - 1)) == 0) {
        parse_digits_by_bits(out, digits, radix);
        return;
    }
    BIGNUM *const result = new_bn();
    uint64_t chunk_power;
    const size_t chunk = chunk_of(radix, &chunk_power);
    size_t at = 0;
    while (at < digits.len) {
        const size_t take = digits.len - at < chunk ? digits.len - at : chunk;
        uint64_t word = 0;
        uint64_t scale = 1;
        for (size_t i = 0; i < take; i++) {
            word = word * radix + ms_big_digit_value(digits.ptr[at + i]);
            scale *= radix;
        }
        must(BN_mul_word(result, take == chunk ? chunk_power : scale));
        must(BN_add_word(result, word));
        at += take;
    }
    result_end(out, result);
}

/* Digits of `radix` of the magnitude, least significant first, by dividing a copy by radix^chunk. */
static uint8_t *digits_by_division(const BIGNUM *a, unsigned radix, size_t *length) {
    uint64_t chunk_power;
    const size_t chunk = chunk_of(radix, &chunk_power);
    BIGNUM *const work = BN_dup(a);
    must(work != NULL);
    BN_set_negative(work, 0);
    const size_t capacity = (size_t)BN_num_bits(a) + 1; /* at most one digit per bit */
    uint8_t *const reversed = msrt_alloc(capacity + chunk);
    size_t count = 0;
    while (!BN_is_zero(work)) {
        BN_ULONG rest = BN_div_word(work, (BN_ULONG)chunk_power);
        must(rest != (BN_ULONG)-1);
        for (size_t i = 0; i < chunk && (rest != 0 || !BN_is_zero(work)); i++) {
            reversed[count++] = (uint8_t)(rest % radix);
            rest /= radix;
        }
    }
    release_bn(work);
    if (count == 0) {
        reversed[count++] = 0;
    }
    *length = count;
    return reversed;
}

/* Digits of a power-of-two radix of the magnitude, least significant first, read straight from its bits. */
static uint8_t *digits_by_bits(const BIGNUM *a, unsigned radix, size_t *length) {
    unsigned bits_per_digit = 1; /* radix is at least 2 */
    while ((1u << bits_per_digit) < radix) {
        bits_per_digit++;
    }
    const size_t bits = (size_t)BN_num_bits(a);
    const size_t count = bits == 0 ? 1 : (bits + bits_per_digit - 1) / bits_per_digit;
    const size_t bytes = (count * bits_per_digit) / BITS_PER_BYTE + 1; /* zero padded past the top digit */
    uint8_t *const magnitude = msrt_alloc(bytes);
    must(BN_bn2lebinpad(a, magnitude, (int)bytes) >= 0);
    uint8_t *const digits = msrt_alloc(count);
    for (size_t i = 0; i < count; i++) {
        unsigned digit = 0;
        for (unsigned k = 0; k < bits_per_digit; k++) {
            const size_t bit = i * bits_per_digit + k;
            digit |= (unsigned)((magnitude[bit / BITS_PER_BYTE] >> (bit % BITS_PER_BYTE)) & 1u) << k;
        }
        digits[i] = (uint8_t)digit;
    }
    msrt_free(magnitude);
    *length = count;
    return digits;
}

static bool is_power_of_two_radix(unsigned radix) { return (radix & (radix - 1)) == 0; }

uint8_t *ms_big_digits_new(const MsBig *a, unsigned radix, size_t *length) {
    uint8_t *const digits = is_power_of_two_radix(radix) ? digits_by_bits(value_of(a), radix, length)
                                                         : digits_by_division(value_of(a), radix, length);
    for (size_t i = 0; i < *length / 2; i++) {
        const uint8_t swap = digits[i];
        digits[i] = digits[*length - 1 - i];
        digits[*length - 1 - i] = swap;
    }
    for (size_t i = 0; i < *length; i++) {
        digits[i] = (uint8_t)"0123456789abcdefghijklmnopqrstuvwxyz"[digits[i]];
    }
    return digits;
}

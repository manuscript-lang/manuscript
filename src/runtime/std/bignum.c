/* The bignum of bignum.h on OpenSSL's BIGNUM: arithmetic, comparison, shifts,
 * powers, gcd and modular inverses are BN_* calls; this file adds what BIGNUM
 * lacks (floor shifts, two's complement bitwise operations, integer square
 * roots, correctly rounded doubles, 128-bit and int64 conversion, text in any
 * radix). */
#include "runtime/std/bignum.h"
#include "runtime/std/bignum_internal.h"
#include "runtime/std/bignum_ntt.h"

#include <limits.h>
#include <math.h>
#include <openssl/crypto.h>
#include <openssl/err.h>

#include "base/alloc.h"
#include "runtime/core/fault.h"

typedef unsigned __int128 U128;

enum { BITS_PER_BYTE = 8 };

/* ---- plumbing ---- */

/* A BN_* call fails when OpenSSL's size cap (about 2^29 bits) is reached or
 * when memory runs out; each faults as the rest of the runtime does. */
void ms_big_must(int ok) {
  if (ok != 0) {
    return;
  }
  const int reason = ERR_GET_REASON(ERR_peek_last_error());
  ERR_clear_error();
  if (reason == BN_R_BIGNUM_TOO_LONG) {
    static const char message[] = "bignum: result exceeds the largest supported size";
    ms_fault_text(MS_FAULT_KIND_OVERFLOW, message);
  }
  static const char message[] = "bignum: out of memory";
  ms_fault_text(MS_FAULT_KIND_OUT_OF_MEMORY, message);
}

/* Decimal and BigInt operations are short and many, so each thread keeps a few
 * released BIGNUMs (and one context) for reuse instead of going through malloc
 * for every operation; they live until the thread exits. */
enum { POOL_SIZE = 16, POOL_MAX_BITS = 4096 }; /* larger values are not worth keeping */

typedef struct Pool {
  BIGNUM *free_list[POOL_SIZE];
  size_t count;
  BN_CTX *ctx;
  BIGNUM *limit; /* 2^POOL_MAX_BITS: BN_ucmp against it is much cheaper than
                    BN_num_bits */
} Pool;

static Pool *pool(void) {
  static _Thread_local Pool state;
  return &state;
}

BIGNUM *ms_big_new_bn(void) {
  Pool *const p = pool();
  if (p->count > 0) {
    return p->free_list[--p->count];
  }
  BIGNUM *const bn = BN_new();
  ms_big_must(bn != NULL);
  return bn;
}

static const BIGNUM *pool_limit(void) {
  Pool *const p = pool();
  if (p->limit == NULL) {
    p->limit = BN_new();
    ms_big_must(p->limit != NULL && BN_set_bit(p->limit, POOL_MAX_BITS));
  }
  return p->limit;
}

static bool is_wide(const MsBig *a) {
  return a != NULL && a->bn != NULL && BN_ucmp(a->bn, pool_limit()) >= 0;
}

void ms_big_release_bn(BIGNUM *bn) {
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
    ms_big_must(p->ctx != NULL);
  }
  return p->ctx;
}

/* The shared read-only zero that stands in for an operand with no BIGNUM. */
static const BIGNUM *zero_bn(void) {
  static _Thread_local BIGNUM *zero;
  if (zero == NULL) {
    zero = ms_big_new_bn();
    BN_zero(zero);
  }
  return zero;
}

const BIGNUM *ms_big_value_of(const MsBig *a) {
  return a->bn != NULL ? a->bn : zero_bn();
}

/* A scratch BIGNUM for the result of an operation on `a` and `b`: `out`'s own
 * when it is neither operand's. */
static BIGNUM *result_begin(MsBig *out, const MsBig *a, const MsBig *b) {
  const bool overlaps = out->bn != NULL && (out->bn == a->bn || (b != NULL && out->bn == b->bn));
  if (overlaps || out->bn == NULL) {
    return ms_big_new_bn();
  }
  return out->bn;
}

/* Makes `result` (from result_begin) the value of `out`. */
void ms_big_result_end(MsBig *out, BIGNUM *result) {
  if (out->bn == result) {
    return;
  }
  ms_big_release_bn(out->bn);
  out->bn = result;
}

/* Like result_end for an operation whose result can be much smaller than its
 * operands (a difference, a remainder, a shift right). When an operand was at
 * least POOL_MAX_BITS wide the result moves into a right-sized BIGNUM, and the
 * context's temporaries are released: a thread does not keep the buffers of the
 * widest value it ever saw. `wide` is computed before the operation, since
 * `out` may be an operand. */
static void result_end_shrinking(MsBig *out, BIGNUM *result, bool wide) {
  BIGNUM *final = result;
  if (wide) {
    Pool *const p = pool();
    BN_CTX_free(p->ctx);
    p->ctx = NULL;
    if (BN_ucmp(result, pool_limit()) < 0) {
      final = BN_dup(result);
      ms_big_must(final != NULL);
      BN_free(result);
    }
  }
  if (out->bn != result) {
    ms_big_release_bn(out->bn);
  }
  out->bn = final;
}

/* Runs `op` into a fresh result for binary operations that BN_* permits to
 * share no storage with an operand. */
typedef int (*BinaryOp)(BIGNUM *r, const BIGNUM *a, const BIGNUM *b, BN_CTX *ctx);

static void binary(MsBig *out, const MsBig *a, const MsBig *b, BinaryOp op) {
  BIGNUM *const result = result_begin(out, a, b);
  BN_CTX *const ctx = new_ctx();
  ms_big_must(op(result, ms_big_value_of(a), ms_big_value_of(b), ctx));
  ms_big_result_end(out, result);
}

/* ---- construction and inspection ---- */

void ms_big_free(MsBig *x) {
  ms_big_release_bn(x->bn);
  x->bn = NULL;
}

void ms_big_copy(MsBig *out, const MsBig *a) {
  if (out->bn == a->bn) {
    return;
  }
  BIGNUM *const result = ms_big_new_bn();
  ms_big_must(BN_copy(result, ms_big_value_of(a)) != NULL);
  ms_big_result_end(out, result);
}

/* Sets `out` to the little-endian bytes as a magnitude. */
static void set_le(MsBig *out, const uint8_t *bytes, size_t length, bool negative) {
  BIGNUM *const result = ms_big_new_bn();
  ms_big_must(BN_lebin2bn(bytes, (int)length, result) != NULL);
  BN_set_negative(result, negative && !BN_is_zero(result));
  ms_big_result_end(out, result);
}

void ms_big_set_u128(MsBig *out, uint64_t high, uint64_t low, bool negative) {
  if (sizeof(BN_ULONG) == sizeof low) { /* two words, no byte shuffling */
    BIGNUM *const result = ms_big_new_bn();
    ms_big_must(BN_set_word(result, (BN_ULONG)high));
    if (high != 0) {
      ms_big_must(BN_lshift(result, result, 64));
    }
    ms_big_must(BN_add_word(result, (BN_ULONG)low));
    BN_set_negative(result, negative && !BN_is_zero(result));
    ms_big_result_end(out, result);
    return;
  }
  uint8_t bytes[16];
  for (int i = 0; i < 8; i++) {
    bytes[i] = (uint8_t)(low >> (BITS_PER_BYTE * i));
    bytes[8 + i] = (uint8_t)(high >> (BITS_PER_BYTE * i));
  }
  set_le(out, bytes, sizeof bytes, negative);
}

void ms_big_set_u64(MsBig *out, uint64_t value) {
  ms_big_set_u128(out, 0, value, false);
}

void ms_big_set_i64(MsBig *out, int64_t value) {
  const uint64_t magnitude = value < 0 ? UINT64_C(0) - (uint64_t)value : (uint64_t)value;
  ms_big_set_u128(out, 0, magnitude, value < 0);
}

bool ms_big_is_zero(const MsBig *a) {
  return a->bn == NULL || BN_is_zero(a->bn);
}

int ms_big_sign(const MsBig *a) {
  if (ms_big_is_zero(a)) {
    return 0;
  }
  return BN_is_negative(a->bn) ? -1 : 1;
}

int ms_big_cmp(const MsBig *a, const MsBig *b) {
  return BN_cmp(ms_big_value_of(a), ms_big_value_of(b));
}
int ms_big_cmp_abs(const MsBig *a, const MsBig *b) {
  return BN_ucmp(ms_big_value_of(a), ms_big_value_of(b));
}
bool ms_big_is_odd(const MsBig *a) {
  return a->bn != NULL && BN_is_odd(a->bn);
}
size_t ms_big_bit_length(const MsBig *a) {
  return (size_t)BN_num_bits(ms_big_value_of(a));
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
  ms_big_must(BN_add(result, ms_big_value_of(a), ms_big_value_of(b)));
  ms_big_result_end(out, result);
}

void ms_big_sub(MsBig *out, const MsBig *a, const MsBig *b) {
  const bool wide = is_wide(a) || is_wide(b);
  BIGNUM *const result = result_begin(out, a, b);
  ms_big_must(BN_sub(result, ms_big_value_of(a), ms_big_value_of(b)));
  result_end_shrinking(out, result, wide);
}

enum { NTT_MIN_BITS = 1 << 16 }; /* below this OpenSSL's Karatsuba multiply is faster than the transforms */

/* Wide products go through number-theoretic transforms. The cheap pool-limit
 * test rejects small operands first. */
static bool use_transform(const BIGNUM *a, const BIGNUM *b) {
  if (BN_ucmp(a, pool_limit()) < 0 || BN_ucmp(b, pool_limit()) < 0) {
    return false;
  }
  return BN_num_bits(a) >= NTT_MIN_BITS && BN_num_bits(b) >= NTT_MIN_BITS;
}

void ms_big_mul(MsBig *out, const MsBig *a, const MsBig *b) {
  const BIGNUM *const x = ms_big_value_of(a);
  const BIGNUM *const y = ms_big_value_of(b);
  if (use_transform(x, y)) {
    BIGNUM *const result = result_begin(out, a, b);
    if (ms_ntt_multiply(result, x, y)) {
      BN_set_negative(result, BN_is_negative(x) != BN_is_negative(y));
      ms_big_result_end(out, result);
      return;
    }
    if (result != out->bn) {
      ms_big_release_bn(result);
    }
  }
  binary(out, a, b, BN_mul);
}

void ms_big_divmod(MsBig *quotient, MsBig *remainder, const MsBig *a, const MsBig *b) {
  const bool wide = is_wide(a) || is_wide(b);
  BIGNUM *const q = ms_big_new_bn();
  BIGNUM *const r = ms_big_new_bn();
  BN_CTX *const ctx = new_ctx();
  ms_big_must(BN_div(q, r, ms_big_value_of(a), ms_big_value_of(b), ctx));
  if (quotient != NULL) {
    result_end_shrinking(quotient, q, wide);
  } else {
    ms_big_release_bn(q);
  }
  if (remainder != NULL) {
    result_end_shrinking(remainder, r, wide);
  } else {
    ms_big_release_bn(r);
  }
}

/* ---- shifts and bitwise operations ---- */

static int shift_count(size_t count) {
  return count > (size_t)INT_MAX ? INT_MAX : (int)count;
}

void ms_big_shift_left(MsBig *out, const MsBig *a, size_t count) {
  BIGNUM *const result = result_begin(out, a, NULL);
  ms_big_must(BN_lshift(result, ms_big_value_of(a), shift_count(count)));
  ms_big_result_end(out, result);
}

/* Rounds toward negative infinity: a negative value that loses a set bit moves
 * one further from zero. */
void ms_big_shift_right(MsBig *out, const MsBig *a, size_t count) {
  const bool wide = is_wide(a);
  const BIGNUM *const value = ms_big_value_of(a);
  const int bits = shift_count(count);
  BIGNUM *const result = ms_big_new_bn();
  ms_big_must(BN_rshift(result, value, bits));
  if (BN_is_negative(value)) {
    BIGNUM *const back = ms_big_new_bn();
    ms_big_must(BN_lshift(back, result, bits));
    if (BN_ucmp(back, value) != 0) {
      ms_big_must(BN_sub(result, result, BN_value_one()));
    }
    ms_big_release_bn(back);
  }
  result_end_shrinking(out, result, wide);
}

/* The two's complement of `a` as `width` little-endian bytes (width covers the
 * magnitude and a sign bit). */
static void to_twos(const BIGNUM *a, uint8_t *bytes, size_t width) {
  ms_big_must(BN_bn2lebinpad(a, bytes, (int)width) >= 0);
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

static uint8_t byte_and(uint8_t x, uint8_t y) {
  return (uint8_t)(x & y);
}
static uint8_t byte_or(uint8_t x, uint8_t y) {
  return (uint8_t)(x | y);
}
static uint8_t byte_xor(uint8_t x, uint8_t y) {
  return (uint8_t)(x ^ y);
}

static void bitwise(MsBig *out, const MsBig *a, const MsBig *b, ByteOp op) {
  const BIGNUM *const x = ms_big_value_of(a);
  const BIGNUM *const y = ms_big_value_of(b);
  const int bits = BN_num_bits(x) > BN_num_bits(y) ? BN_num_bits(x) : BN_num_bits(y);
  const size_t width = (size_t)bits / BITS_PER_BYTE + 1; /* room for the sign bit */
  uint8_t *const left = ms_alloc(2 * width);
  uint8_t *const right = left + width;
  to_twos(x, left, width);
  to_twos(y, right, width);
  for (size_t i = 0; i < width; i++) {
    left[i] = op(left[i], right[i]);
  }
  from_twos(out, left, width);
  ms_free(left);
}

void ms_big_and(MsBig *out, const MsBig *a, const MsBig *b) {
  bitwise(out, a, b, byte_and);
}
void ms_big_or(MsBig *out, const MsBig *a, const MsBig *b) {
  bitwise(out, a, b, byte_or);
}
void ms_big_xor(MsBig *out, const MsBig *a, const MsBig *b) {
  bitwise(out, a, b, byte_xor);
}

/* ~a = -a - 1. */
void ms_big_not(MsBig *out, const MsBig *a) {
  BIGNUM *const result = result_begin(out, a, NULL);
  ms_big_must(BN_set_word(result, 1));
  BN_set_negative(result, 1);
  ms_big_must(BN_sub(result, result, ms_big_value_of(a)));
  ms_big_result_end(out, result);
}

/* ---- powers, roots and number theory ---- */

/* True when |a| is a power of two other than one (exactly one bit set, above
 * bit 0). */
static bool is_power_of_two(const BIGNUM *a) {
  const int bits = BN_num_bits(a);
  if (bits < 2) {
    return false;
  }
  BIGNUM *const rest = ms_big_new_bn();
  ms_big_must(BN_copy(rest, a) != NULL);
  ms_big_must(BN_clear_bit(rest, bits - 1));
  const bool single = BN_is_zero(rest);
  ms_big_release_bn(rest);
  return single;
}

/* (+-2^k)^e is +-2^(k*e): one shift, where repeated squaring of a huge power of
 * two would take seconds. */
static bool pow_of_two(MsBig *out, const BIGNUM *a, uint64_t exponent) {
  if (!is_power_of_two(a)) {
    return false;
  }
  const uint64_t k = (uint64_t)BN_num_bits(a) - 1;
  if (exponent > (uint64_t)INT_MAX / k) {
    ms_fault_text(MS_FAULT_KIND_OVERFLOW, "bignum: value too large");
  }
  BIGNUM *const result = ms_big_new_bn();
  BN_zero(result);
  ms_big_must(BN_set_bit(result, (int)(k * exponent)));
  BN_set_negative(result, BN_is_negative(a) && (exponent & 1) != 0);
  ms_big_result_end(out, result);
  return true;
}

/* Left-to-right square and multiply through ms_big_mul, so wide squares take
 * the transform. */
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
  if (pow_of_two(out, ms_big_value_of(a), exponent)) {
    return;
  }
  const uint64_t estimate = (uint64_t)BN_num_bits(ms_big_value_of(a)) *
                            (exponent > POW_BY_SQUARING_BITS ? POW_BY_SQUARING_BITS : exponent);
  if (exponent > 1 && estimate >= POW_BY_SQUARING_BITS) {
    pow_by_squaring(out, a, exponent);
    return;
  }
  MsBig power = MS_BIG_ZERO;
  ms_big_set_u64(&power, exponent);
  BIGNUM *const result = ms_big_new_bn();
  BN_CTX *const ctx = new_ctx();
  ms_big_must(BN_exp(result, ms_big_value_of(a), power.bn, ctx));
  ms_big_free(&power);
  ms_big_result_end(out, result);
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
  BIGNUM *const x = ms_big_new_bn();
  BIGNUM *const y = ms_big_new_bn();
  BIGNUM *const quotient = ms_big_new_bn();
  ms_big_must(BN_set_bit(x, (BN_num_bits(a->bn) + 1) / 2));
  for (;;) {
    ms_big_must(BN_div(quotient, NULL, a->bn, x, ctx));
    ms_big_must(BN_add(y, x, quotient));
    ms_big_must(BN_rshift1(y, y));
    if (BN_cmp(y, x) >= 0) {
      break;
    }
    ms_big_must(BN_copy(x, y) != NULL);
  }
  ms_big_release_bn(y);
  ms_big_release_bn(quotient);
  ms_big_result_end(out, x);
}

void ms_big_gcd(MsBig *out, const MsBig *a, const MsBig *b) {
  /* Euclid's remainders: BN_gcd is the constant-time binary algorithm, many
   * times slower on wide operands. */
  const bool wide = is_wide(a) || is_wide(b);
  BIGNUM *larger = ms_big_new_bn();
  BIGNUM *smaller = ms_big_new_bn();
  BIGNUM *rest = ms_big_new_bn();
  BN_CTX *const ctx = new_ctx();
  ms_big_must(BN_copy(larger, ms_big_value_of(a)) != NULL && BN_copy(smaller, ms_big_value_of(b)) != NULL);
  BN_set_negative(larger, 0);
  BN_set_negative(smaller, 0);
  while (!BN_is_zero(smaller)) {
    ms_big_must(BN_mod(rest, larger, smaller, ctx));
    BIGNUM *const next = larger;
    larger = smaller;
    smaller = rest;
    rest = next;
  }
  if (wide) { /* the remainders still own buffers as wide as the operands */
    BN_free(smaller);
    BN_free(rest);
  } else {
    ms_big_release_bn(smaller);
    ms_big_release_bn(rest);
  }
  result_end_shrinking(out, larger, wide);
}

void ms_big_pow_mod(MsBig *out, const MsBig *a, const MsBig *exponent, const MsBig *modulus) {
  BIGNUM *const result = ms_big_new_bn();
  BIGNUM *const base = ms_big_new_bn();
  BN_CTX *const ctx = new_ctx();
  ms_big_must(BN_nnmod(base, ms_big_value_of(a), ms_big_value_of(modulus), ctx));
  ms_big_must(BN_mod_exp(result, base, ms_big_value_of(exponent), ms_big_value_of(modulus), ctx));
  ms_big_release_bn(base);
  ms_big_result_end(out, result);
}

bool ms_big_inverse_mod(MsBig *out, const MsBig *a, const MsBig *modulus) {
  BIGNUM *const base = ms_big_new_bn();
  BN_CTX *const ctx = new_ctx();
  ms_big_must(BN_nnmod(base, ms_big_value_of(a), ms_big_value_of(modulus), ctx));
  BIGNUM *const result = BN_mod_inverse(NULL, base, ms_big_value_of(modulus), ctx);
  ms_big_release_bn(base);
  if (result == NULL) {
    const bool none = ERR_GET_REASON(ERR_peek_last_error()) == BN_R_NO_INVERSE;
    ERR_clear_error();
    ms_big_must(none);
    return false;
  }
  ms_big_result_end(out, result);
  return true;
}

/* ---- conversions ---- */

/* The low 64 bits of the magnitude; `a` must have at most 64 bits. */
static uint64_t low_word(const BIGNUM *a) {
  uint8_t bytes[8];
  ms_big_must(BN_bn2lebinpad(a, bytes, sizeof bytes) >= 0);
  uint64_t word = 0;
  for (int i = 7; i >= 0; i--) {
    word = word << BITS_PER_BYTE | bytes[i];
  }
  return word;
}

/* The nearest double, ties to even: the top 64 bits with a sticky bit for the
 * rest round once in the cast. */
double ms_big_to_double(const MsBig *a) {
  const BIGNUM *const value = ms_big_value_of(a);
  const int bits = BN_num_bits(value);
  double magnitude;
  if (bits <= 64) {
    magnitude = (double)low_word(value);
  } else {
    BIGNUM *const top = ms_big_new_bn();
    BIGNUM *const back = ms_big_new_bn();
    ms_big_must(BN_rshift(top, value, bits - 64));
    ms_big_must(BN_lshift(back, top, bits - 64));
    uint64_t word = low_word(top);
    if (BN_ucmp(back, value) != 0) {
      word |= 1;
    }
    ms_big_release_bn(top);
    ms_big_release_bn(back);
    magnitude = ldexp((double)word, bits - 64);
  }
  return BN_is_negative(value) ? -magnitude : magnitude;
}

bool ms_big_to_u128(const MsBig *a, uint64_t *high, uint64_t *low) {
  const BIGNUM *const value = ms_big_value_of(a);
  const int bits = BN_num_bits(value);
  if (bits > 128) {
    return false;
  }
  if (bits <= 64 && sizeof(BN_ULONG) == sizeof *low) {
    *high = 0;
    *low = BN_get_word(value);
    return true;
  }
  if (sizeof(BN_ULONG) == sizeof *low) { /* the low word is the value less its
                                            high word shifted back */
    BIGNUM *const part = ms_big_new_bn();
    ms_big_must(BN_rshift(part, value, 64));
    *high = BN_get_word(part);
    ms_big_must(BN_copy(part, value) != NULL);
    ms_big_must(BN_mask_bits(part, 64));
    *low = BN_get_word(part);
    ms_big_release_bn(part);
    return true;
  }
  uint8_t bytes[16];
  ms_big_must(BN_bn2lebinpad(value, bytes, sizeof bytes) >= 0);
  *low = 0;
  *high = 0;
  for (int i = 7; i >= 0; i--) {
    *low = *low << BITS_PER_BYTE | bytes[i];
    *high = *high << BITS_PER_BYTE | bytes[8 + i];
  }
  return true;
}

bool ms_big_to_i64(const MsBig *a, int64_t *out) {
  const BIGNUM *const value = ms_big_value_of(a);
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


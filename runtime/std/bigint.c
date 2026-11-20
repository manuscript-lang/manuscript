/* The @std/math BigInt natives (ms_rt/bigint.h) over the bignum of bignum.h. A BigInt is a runtime object: the two
 * entry points every object has (clone and drop) followed by a MsBig that the object owns. The limits and error
 * precedence are those of the Rust crate this replaces. */
#include <math.h>
#include <stdio.h>
#include <string.h>

#include "bignum.h"
#include "ms_rt/bigint.h"
#include "ms_rt/runtime.h"

/* Results of pow and shift_left may not exceed this many bits. */
#define MS_BIGINT_MAX_BITS ((int64_t)1 << 24)

struct MsBigCell {
    MsObj header;
    MsBig value; /* owned */
};

/* ---- the object ---- */

static MsObj *cell_clone_entry(MsObj *object);
static void cell_drop_entry(MsObj *object);

/* A new object that takes ownership of the limbs of `value`, which is left zero. */
static MsBigCell *cell_new(MsBig *value) {
    MsBigCell *const cell = msrt_alloc(sizeof *cell);
    cell->header.clone = cell_clone_entry;
    cell->header.drop = cell_drop_entry;
    cell->value = *value;
    *value = MS_BIG_ZERO;
    return cell;
}

static MsObj *cell_clone_entry(MsObj *object) {
    MsBig copy = MS_BIG_ZERO;
    ms_big_copy(&copy, &((const MsBigCell *)object)->value);
    return &cell_new(&copy)->header; /* the header is the first member, so this is the object's address */
}

static void cell_drop_entry(MsObj *object) {
    ms_big_free(&((MsBigCell *)object)->value);
    msrt_free(object);
}

/* Stores a new object holding `value` in *out and reports success. */
static uint8_t cell_ok(MsBig *value, MsBigCell **out) {
    *out = cell_new(value);
    return MS_STATUS_OK;
}

/* ---- construction ---- */

MsBigCell *msstd_bigint_from_int(int64_t value) {
    MsBig big = MS_BIG_ZERO;
    ms_big_set_i64(&big, value);
    return cell_new(&big);
}

MsBigCell *msstd_bigint_from_u64(int64_t value) {
    MsBig big = MS_BIG_ZERO;
    ms_big_set_u64(&big, (uint64_t)value);
    return cell_new(&big);
}

MsBigCell *msstd_bigint_from_seconds_nanos(int64_t seconds, int64_t nanoseconds) {
    MsBig total = MS_BIG_ZERO;
    MsBig part = MS_BIG_ZERO;
    ms_big_set_i64(&total, seconds);
    ms_big_set_u64(&part, UINT64_C(1000000000));
    ms_big_mul(&total, &total, &part);
    ms_big_set_i64(&part, nanoseconds);
    ms_big_add(&total, &total, &part);
    ms_big_free(&part);
    return cell_new(&total);
}

uint8_t msstd_bigint_parse(const MsStr *text, int64_t radix, HasRaw has_max, int64_t max, MsBigCell **out) {
    const int64_t limit = has_max != 0 ? max : INT64_MAX;
    if (radix < (int64_t)MS_BIG_MIN_RADIX || radix > (int64_t)MS_BIG_MAX_RADIX || limit < 0) {
        return MS_STATUS_INVALID_INPUT;
    }
    const uint8_t *bytes = ms_str_data(text);
    size_t length = ms_str_len(text);
    const bool signed_text = length > 0 && (bytes[0] == '+' || bytes[0] == '-');
    const bool negative = length > 0 && bytes[0] == '-';
    if (signed_text) {
        bytes++;
        length--;
    }
    if ((uint64_t)length > (uint64_t)limit) {
        return MS_STATUS_LIMIT_EXCEEDED;
    }
    if (length == 0) {
        return MS_STATUS_INVALID_DATA;
    }
    for (size_t i = 0; i < length; i++) {
        if (ms_big_digit_value(bytes[i]) >= radix) {
            return MS_STATUS_INVALID_DATA;
        }
    }
    MsBig value = MS_BIG_ZERO;
    ms_big_parse_digits(&value, ms_bytes_of(bytes, length), (unsigned)radix);
    if (negative) {
        ms_big_negate(&value, &value);
    }
    return cell_ok(&value, out);
}

/* ---- arithmetic ---- */

MsBigCell *msstd_bigint_add(const MsBigCell *a, const MsBigCell *other) {
    MsBig result = MS_BIG_ZERO;
    ms_big_add(&result, &a->value, &other->value);
    return cell_new(&result);
}

MsBigCell *msstd_bigint_subtract(const MsBigCell *a, const MsBigCell *other) {
    MsBig result = MS_BIG_ZERO;
    ms_big_sub(&result, &a->value, &other->value);
    return cell_new(&result);
}

MsBigCell *msstd_bigint_multiply(const MsBigCell *a, const MsBigCell *other) {
    MsBig result = MS_BIG_ZERO;
    ms_big_mul(&result, &a->value, &other->value);
    return cell_new(&result);
}

MsBigCell *msstd_bigint_gcd(const MsBigCell *a, const MsBigCell *other) {
    MsBig result = MS_BIG_ZERO;
    ms_big_gcd(&result, &a->value, &other->value);
    return cell_new(&result);
}

/* |a| / gcd * |b|, or 0 when either is 0. */
MsBigCell *msstd_bigint_lcm(const MsBigCell *a, const MsBigCell *other) {
    MsBig divisor = MS_BIG_ZERO;
    MsBig result = MS_BIG_ZERO;
    ms_big_gcd(&divisor, &a->value, &other->value);
    if (!ms_big_is_zero(&divisor)) {
        ms_big_divmod(&result, NULL, &a->value, &divisor);
        ms_big_mul(&result, &result, &other->value);
        ms_big_abs(&result, &result);
    }
    ms_big_free(&divisor);
    return cell_new(&result);
}

uint8_t msstd_bigint_sqrt(const MsBigCell *a, MsBigCell **out) {
    if (ms_big_sign(&a->value) < 0) {
        return MS_STATUS_INVALID_INPUT;
    }
    MsBig root = MS_BIG_ZERO;
    ms_big_sqrt(&root, &a->value);
    return cell_ok(&root, out);
}

uint8_t msstd_bigint_pow_mod(const MsBigCell *a, const MsBigCell *exponent, const MsBigCell *modulus,
                             MsBigCell **out) {
    if (ms_big_sign(&exponent->value) < 0 || ms_big_sign(&modulus->value) <= 0) {
        return MS_STATUS_INVALID_INPUT;
    }
    MsBig result = MS_BIG_ZERO;
    ms_big_pow_mod(&result, &a->value, &exponent->value, &modulus->value);
    return cell_ok(&result, out);
}

/* The only residue modulo one is zero, including for negative receivers. */
uint8_t msstd_bigint_inverse_mod(const MsBigCell *a, const MsBigCell *modulus, MsBigCell **out) {
    if (ms_big_sign(&modulus->value) <= 0) {
        return 0;
    }
    MsBig result = MS_BIG_ZERO;
    const bool is_one = ms_big_bit_length(&modulus->value) == 1; /* the modulus is positive */
    if (!is_one && !ms_big_inverse_mod(&result, &a->value, &modulus->value)) {
        return 0;
    }
    *out = cell_new(&result);
    return 1;
}

MsBigCell *msstd_bigint_bit_and(const MsBigCell *a, const MsBigCell *other) {
    MsBig result = MS_BIG_ZERO;
    ms_big_and(&result, &a->value, &other->value);
    return cell_new(&result);
}

MsBigCell *msstd_bigint_bit_or(const MsBigCell *a, const MsBigCell *other) {
    MsBig result = MS_BIG_ZERO;
    ms_big_or(&result, &a->value, &other->value);
    return cell_new(&result);
}

MsBigCell *msstd_bigint_bit_xor(const MsBigCell *a, const MsBigCell *other) {
    MsBig result = MS_BIG_ZERO;
    ms_big_xor(&result, &a->value, &other->value);
    return cell_new(&result);
}

MsBigCell *msstd_bigint_bit_not(const MsBigCell *a) {
    MsBig result = MS_BIG_ZERO;
    ms_big_not(&result, &a->value);
    return cell_new(&result);
}

/* ---- division ---- */

uint8_t msstd_bigint_divide(const MsBigCell *a, const MsBigCell *other, MsBigCell **out) {
    if (ms_big_is_zero(&other->value)) {
        return MS_STATUS_INVALID_INPUT;
    }
    MsBig quotient = MS_BIG_ZERO;
    ms_big_divmod(&quotient, NULL, &a->value, &other->value);
    return cell_ok(&quotient, out);
}

uint8_t msstd_bigint_remainder(const MsBigCell *a, const MsBigCell *other, MsBigCell **out) {
    if (ms_big_is_zero(&other->value)) {
        return MS_STATUS_INVALID_INPUT;
    }
    MsBig remainder = MS_BIG_ZERO;
    ms_big_divmod(NULL, &remainder, &a->value, &other->value);
    return cell_ok(&remainder, out);
}

/* The / operator: a zero divisor is a fault. */
MsBigCell *msstd_bigint_quotient(const MsBigCell *a, const MsBigCell *other) {
    static const char message[] = "BigInt./: division by zero; right must be nonzero, found 0";
    if (ms_big_is_zero(&other->value)) {
        msfault_raise(MS_FAULT_DIVISION_BY_ZERO, message, sizeof message - 1);
    }
    MsBig quotient = MS_BIG_ZERO;
    ms_big_divmod(&quotient, NULL, &a->value, &other->value);
    return cell_new(&quotient);
}

/* The % operator: a zero divisor is a fault. */
MsBigCell *msstd_bigint_modulo(const MsBigCell *a, const MsBigCell *other) {
    static const char message[] = "BigInt.%: division by zero; right must be nonzero, found 0";
    if (ms_big_is_zero(&other->value)) {
        msfault_raise(MS_FAULT_DIVISION_BY_ZERO, message, sizeof message - 1);
    }
    MsBig remainder = MS_BIG_ZERO;
    ms_big_divmod(NULL, &remainder, &a->value, &other->value);
    return cell_new(&remainder);
}

/* ---- comparison and sign ---- */

int64_t msstd_bigint_compare(const MsBigCell *a, const MsBigCell *other) { return ms_big_cmp(&a->value, &other->value); }

uint8_t msstd_bigint_equal(const MsBigCell *a, const MsBigCell *other) {
    return ms_big_cmp(&a->value, &other->value) == 0;
}

int64_t msstd_bigint_sign(const MsBigCell *a) { return ms_big_sign(&a->value); }

MsBigCell *msstd_bigint_negate(const MsBigCell *a) {
    MsBig result = MS_BIG_ZERO;
    ms_big_negate(&result, &a->value);
    return cell_new(&result);
}

MsBigCell *msstd_bigint_abs(const MsBigCell *a) {
    MsBig result = MS_BIG_ZERO;
    ms_big_abs(&result, &a->value);
    return cell_new(&result);
}

/* ---- powers and shifts ---- */

/* Whether a * b >= limit, without overflow (both positive). */
static bool product_reaches(int64_t a, int64_t b, int64_t limit) {
    int64_t product = 0;
    return __builtin_mul_overflow(a, b, &product) || product >= limit;
}

/* Whether |a|^exponent certainly has more than MS_BIGINT_MAX_BITS bits, judged from log2 of the top 64 bits so that
 * an oversized power is refused without computing it. The estimate errs by far less than the 0.001 margin. */
static bool power_certainly_exceeds(const MsBig *a, size_t length, int64_t exponent) {
    const size_t shift = length > 64 ? length - 64 : 0;
    MsBig top = MS_BIG_ZERO;
    ms_big_abs(&top, a);
    ms_big_shift_right(&top, &top, shift);
    uint64_t high = 0;
    uint64_t low = 0;
    const bool fits = ms_big_to_u128(&top, &high, &low);
    ms_big_free(&top);
    if (!fits) {
        return false;
    }
    const double log2_value = log2((double)low) + (double)shift;
    /* The result has floor(exponent * log2) + 1 bits. */
    return (double)exponent * log2_value > (double)MS_BIGINT_MAX_BITS + 1.001;
}

uint8_t msstd_bigint_pow(const MsBigCell *a, int64_t exponent, MsBigCell **out) {
    if (exponent < 0) {
        return MS_STATUS_INVALID_INPUT;
    }
    const size_t length = ms_big_bit_length(&a->value);
    const int64_t bits = length > (size_t)INT64_MAX ? INT64_MAX : (int64_t)length;
    if (exponent > 1 && bits > 1 && product_reaches(bits - 1, exponent, MS_BIGINT_MAX_BITS)) {
        return MS_STATUS_LIMIT_EXCEEDED;
    }
    if (exponent > 1 && power_certainly_exceeds(&a->value, length, exponent)) {
        return MS_STATUS_LIMIT_EXCEEDED;
    }
    MsBig result = MS_BIG_ZERO;
    ms_big_pow(&result, &a->value, (uint64_t)exponent);
    if (ms_big_bit_length(&result) > (size_t)MS_BIGINT_MAX_BITS) {
        ms_big_free(&result);
        return MS_STATUS_LIMIT_EXCEEDED;
    }
    return cell_ok(&result, out);
}

uint8_t msstd_bigint_shift_left(const MsBigCell *a, int64_t count, MsBigCell **out) {
    if (count < 0) {
        return MS_STATUS_INVALID_INPUT;
    }
    MsBig result = MS_BIG_ZERO;
    if (ms_big_is_zero(&a->value)) {
        return cell_ok(&result, out);
    }
    const int64_t bits = (int64_t)ms_big_bit_length(&a->value);
    if (count > MS_BIGINT_MAX_BITS || bits + count > MS_BIGINT_MAX_BITS) {
        return MS_STATUS_LIMIT_EXCEEDED;
    }
    ms_big_shift_left(&result, &a->value, (size_t)count);
    return cell_ok(&result, out);
}

/* Shifting by more than the width gives 0 or -1 (floor semantics). */
uint8_t msstd_bigint_shift_right(const MsBigCell *a, int64_t count, MsBigCell **out) {
    if (count < 0) {
        return MS_STATUS_INVALID_INPUT;
    }
    const int64_t bits = (int64_t)ms_big_bit_length(&a->value);
    const int64_t clamped = count < bits + 1 ? count : bits + 1;
    MsBig result = MS_BIG_ZERO;
    ms_big_shift_right(&result, &a->value, (size_t)clamped);
    return cell_ok(&result, out);
}

/* ---- conversion ---- */

double msstd_bigint_to_float(const MsBigCell *a) { return ms_big_to_double(&a->value); }

/* Writes *out and returns 1 when the value fits an Int. */
uint8_t msstd_bigint_to_int(const MsBigCell *a, int64_t *out) { return ms_big_to_i64(&a->value, out); }

void msstd_bigint_to_string_radix(const MsBigCell *a, int64_t radix, MsStr *out) {
    if (radix < (int64_t)MS_BIG_MIN_RADIX || radix > (int64_t)MS_BIG_MAX_RADIX) {
        char message[128];
        const int length = snprintf(message, sizeof message,
                                    "BigInt.to_string_radix: radix must be between 2 and 36, found %lld", (long long)radix);
        ms_fault_text(message, length > 0 ? (size_t)length : 0);
    }
    size_t digit_count = 0;
    uint8_t *const digits = ms_big_digits_new(&a->value, (unsigned)radix, &digit_count);
    if (ms_big_sign(&a->value) >= 0) {
        msrt_string_from_bytes(digits, digit_count, out);
        msrt_free(digits);
        return;
    }
    uint8_t *const text = msrt_alloc(digit_count + 1);
    text[0] = '-';
    memcpy(text + 1, digits, digit_count);
    msrt_string_from_bytes(text, digit_count + 1, out);
    msrt_free(text);
    msrt_free(digits);
}

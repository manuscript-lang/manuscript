/* The @std/math Decimal natives (ms_rt/decimal.h). A value is coefficient * 10^exponent with at most 34 significant
 * digits; the coefficient fits a signed 128-bit integer, so the common cases (comparison, negation, conversion) use
 * plain 128-bit arithmetic and only the operators that need exact wide intermediates (a sum across very different
 * exponents, a product, a quotient, directed rounding) go through the bignum. Rounding is half to even unless a mode
 * says otherwise; the results are those of the Rust crate this replaces. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bignum.h"
#include "ms_rt/decimal.h"

typedef unsigned __int128 MsU128;
typedef __int128 MsI128;

enum {
    MS_DECIMAL_DIGITS = 34,
    MS_DECIMAL_WIDE_DIGITS = 38, /* the most digits dropped from a 128-bit value */
    MS_DECIMAL_MIN_QUANTUM = -6176,
    MS_DECIMAL_MAX_EXPONENT = 6144,
    /* The most digits a rendering can hold: sign, 34 digits, a point, `e+6144`. */
    MS_DECIMAL_RENDER_MAX = 48,
};

/* How round and to_fixed discard digits: the declaration order of RoundingMode. */
typedef enum MsRounding {
    MS_ROUND_HALF_EVEN,
    MS_ROUND_HALF_AWAY,
    MS_ROUND_TOWARD_ZERO,
    MS_ROUND_FLOOR,
    MS_ROUND_CEIL,
} MsRounding;

/* ---- 128-bit helpers ---- */

enum { POW10_WORD_MAX = 19 }; /* 10^19 is the largest power of ten in 64 bits */

/* 10^exponent for an exponent up to 38 (the largest power of ten in 128 bits): two table lookups. */
static MsU128 power_of_ten(unsigned exponent) {
    static const uint64_t words[POW10_WORD_MAX + 1] = {
        1ULL,
        10ULL,
        100ULL,
        1000ULL,
        10000ULL,
        100000ULL,
        1000000ULL,
        10000000ULL,
        100000000ULL,
        1000000000ULL,
        10000000000ULL,
        100000000000ULL,
        1000000000000ULL,
        10000000000000ULL,
        100000000000000ULL,
        1000000000000000ULL,
        10000000000000000ULL,
        100000000000000000ULL,
        1000000000000000000ULL,
        10000000000000000000ULL,
    };
    if (exponent <= POW10_WORD_MAX) {
        return words[exponent];
    }
    return (MsU128)words[POW10_WORD_MAX] * words[exponent - POW10_WORD_MAX];
}

/* Decimal digits of a nonzero 128-bit value (1 for zero). */
static unsigned digits_of(MsU128 value) {
    if (value == 0) {
        return 1;
    }
    const unsigned long long high = (unsigned long long)(value >> 64);
    const unsigned bits = high != 0 ? 128 - (unsigned)__builtin_clzll(high)
                                    : 64 - (unsigned)__builtin_clzll((unsigned long long)value);
    const unsigned guess = (bits * 1233) >> 12; /* floor(bits * log10(2)) */
    return guess + 1 - (value < power_of_ten(guess) ? 1 : 0);
}

static MsI128 coefficient_of(const MsDecimal *d) {
    return (MsI128)(((MsU128)(uint64_t)d->high << 64) | d->low);
}

static MsDecimal pack(MsI128 coefficient, int64_t exponent) {
    const MsU128 bits = (MsU128)coefficient;
    return (MsDecimal){.low = (uint64_t)bits,
                       .high = (int64_t)(uint64_t)(bits >> 64),
                       .exponent = coefficient == 0 ? 0 : exponent};
}

static bool is_zero(const MsDecimal *d) { return d->low == 0 && d->high == 0; }

static MsU128 magnitude_of(MsI128 value) { return value < 0 ? (MsU128)0 - (MsU128)value : (MsU128)value; }

/* Strips trailing zeros of a coefficient into the exponent. */
static void normalize(MsU128 *magnitude, int64_t *exponent) {
    while (*magnitude >> 64 != 0) { /* wide values go down to 64 bits first */
        const MsU128 tenth = *magnitude / 10;
        if (*magnitude != tenth * 10) {
            return;
        }
        *magnitude = tenth;
        (*exponent)++;
    }
    uint64_t narrow = (uint64_t)*magnitude;
    while (narrow != 0 && narrow % 10 == 0) {
        narrow /= 10;
        (*exponent)++;
    }
    *magnitude = narrow;
}

/* ---- the bignum bridge ---- */

static void big_from_coefficient(MsBig *out, const MsDecimal *d) {
    const MsI128 value = coefficient_of(d);
    const MsU128 magnitude = magnitude_of(value);
    ms_big_set_u128(out, (uint64_t)(magnitude >> 64), (uint64_t)magnitude, value < 0);
}

/* Decimal digits of the magnitude of a bignum. Up to 128 bits they are counted directly; beyond that by an
 * estimate from the bit length that never overshoots (1233 / 4096 is just below log10(2)), raised while the
 * value reaches the next power of ten. */
static int64_t big_digits(const MsBig *a) {
    uint64_t high, low;
    if (ms_big_to_u128(a, &high, &low)) {
        return (int64_t)digits_of(((MsU128)high << 64) | low);
    }
    size_t digits = (ms_big_bit_length(a) - 1) * 1233 / 4096 + 1;
    MsBig power = MS_BIG_ZERO;
    for (;;) {
        ms_big_pow10(&power, digits);
        if (ms_big_cmp_abs(a, &power) < 0) {
            break;
        }
        digits++;
    }
    ms_big_free(&power);
    return (int64_t)digits;
}

/* The magnitude of `a` as a 128-bit integer; callers know it fits. */
static MsU128 big_magnitude(const MsBig *a) {
    uint64_t high = 0;
    uint64_t low = 0;
    if (!ms_big_to_u128(a, &high, &low)) {
        ms_fault_text("Decimal: internal coefficient wider than 128 bits", 49);
    }
    return ((MsU128)high << 64) | low;
}

/* Divides |coefficient| by 10^drop, rounds the discarded part half to even, and stores the result in `out`. */
static void drop_digits_half_even(MsBig *out, const MsBig *coefficient, int64_t drop) {
    MsBig denominator = MS_BIG_ZERO;
    MsBig remainder = MS_BIG_ZERO;
    MsBig twice = MS_BIG_ZERO;
    MsBig one = MS_BIG_ZERO;
    ms_big_pow10(&denominator, (size_t)drop);
    ms_big_abs(out, coefficient);
    ms_big_divmod(out, &remainder, out, &denominator);
    ms_big_shift_left(&twice, &remainder, 1);
    const int comparison = ms_big_cmp(&twice, &denominator);
    if (comparison > 0 || (comparison == 0 && ms_big_is_odd(out))) {
        ms_big_set_u64(&one, 1);
        ms_big_add(out, out, &one);
    }
    ms_big_free(&denominator);
    ms_big_free(&remainder);
    ms_big_free(&twice);
    ms_big_free(&one);
}

/* Rounds the exact value +-magnitude * 10^exponent half to even at 34 digits. Returns false when the magnitude
 * exceeds the format. */
MS_NODISCARD static bool round_wide(MsU128 magnitude, bool negative, int64_t exponent, MsDecimal *out) {
    if (magnitude == 0) {
        *out = pack(0, 0);
        return true;
    }
    const int64_t digits = digits_of(magnitude);
    const int64_t leading = exponent + digits - 1;
    const int64_t quantum = leading - (MS_DECIMAL_DIGITS - 1) > MS_DECIMAL_MIN_QUANTUM
                                ? leading - (MS_DECIMAL_DIGITS - 1)
                                : MS_DECIMAL_MIN_QUANTUM;
    const int64_t drop = quantum - exponent;
    if (drop > 0) {
        exponent = quantum;
        if (drop > MS_DECIMAL_WIDE_DIGITS) { /* below half of one unit of the quantum */
            magnitude = 0;
        } else {
            const MsU128 unit = power_of_ten((unsigned)drop);
            const MsU128 remainder = magnitude % unit;
            magnitude /= unit;
            const MsU128 complement = unit - remainder;
            if (remainder > complement || (remainder == complement && (magnitude & 1) != 0)) {
                magnitude++;
            }
        }
    }
    normalize(&magnitude, &exponent);
    if (magnitude != 0 && exponent + (int64_t)digits_of(magnitude) - 1 > MS_DECIMAL_MAX_EXPONENT) {
        return false;
    }
    *out = pack(negative ? -(MsI128)magnitude : (MsI128)magnitude, exponent);
    return true;
}

/* Rounds the exact value coefficient * 10^exponent half to even at 34 digits. Returns false when the magnitude
 * exceeds the format. */
MS_NODISCARD static bool rounded(const MsBig *coefficient, int64_t exponent, MsDecimal *out) {
    if (ms_big_is_zero(coefficient)) {
        *out = pack(0, 0);
        return true;
    }
    uint64_t high = 0;
    uint64_t low = 0;
    if (ms_big_to_u128(coefficient, &high, &low)) {
        return round_wide(((MsU128)high << 64) | low, ms_big_sign(coefficient) < 0, exponent, out);
    }
    const int64_t digits = big_digits(coefficient);
    const int64_t leading = exponent + digits - 1;
    const int64_t quantum = leading - (MS_DECIMAL_DIGITS - 1) > MS_DECIMAL_MIN_QUANTUM
                                ? leading - (MS_DECIMAL_DIGITS - 1)
                                : MS_DECIMAL_MIN_QUANTUM;
    const int64_t drop = quantum - exponent;
    const bool negative = ms_big_sign(coefficient) < 0;
    MsBig kept = MS_BIG_ZERO;
    if (drop <= 0) {
        ms_big_abs(&kept, coefficient);
    } else {
        drop_digits_half_even(&kept, coefficient, drop);
        exponent = quantum;
    }
    MsU128 magnitude = big_magnitude(&kept);
    ms_big_free(&kept);
    normalize(&magnitude, &exponent);
    if (magnitude != 0 && exponent + (int64_t)digits_of(magnitude) - 1 > MS_DECIMAL_MAX_EXPONENT) {
        return false;
    }
    const MsI128 signed_value = negative ? -(MsI128)magnitude : (MsI128)magnitude;
    *out = pack(signed_value, exponent);
    return true;
}

/* ---- faults ---- */

/* The text of interpolation: at most 34 significant digits. Writes into `text` (MS_DECIMAL_RENDER_MAX + 1 bytes)
 * and returns the length. */
static size_t render_into(const MsDecimal *d, char *text) {
    if (is_zero(d)) {
        memcpy(text, "0", 2);
        return 1;
    }
    const MsI128 coefficient = coefficient_of(d);
    MsU128 magnitude = magnitude_of(coefficient);
    char digits[MS_DECIMAL_RENDER_MAX] = {0};
    size_t count = 0;
    for (; magnitude != 0; magnitude /= 10) {
        digits[count++] = (char)('0' + (int)(magnitude % 10));
    }
    for (size_t i = 0; i < count / 2; i++) { /* reverse in place */
        const char swap = digits[i];
        digits[i] = digits[count - 1 - i];
        digits[count - 1 - i] = swap;
    }
    const int64_t exponent = d->exponent + (int64_t)count - 1;
    while (count > 1 && digits[count - 1] == '0') {
        count--;
    }
    size_t length = 0;
    if (coefficient < 0) {
        text[length++] = '-';
    }
    if (exponent >= -6 && exponent <= 20) {
        const int64_t point = exponent + 1;
        if (point <= 0) {
            text[length++] = '0';
            text[length++] = '.';
            for (int64_t i = 0; i < -point; i++) {
                text[length++] = '0';
            }
            memcpy(text + length, digits, count);
            length += count;
        } else if ((size_t)point >= count) {
            memcpy(text + length, digits, count);
            length += count;
            for (size_t i = count; i < (size_t)point; i++) {
                text[length++] = '0';
            }
        } else {
            memcpy(text + length, digits, (size_t)point);
            length += (size_t)point;
            text[length++] = '.';
            memcpy(text + length, digits + point, count - (size_t)point);
            length += count - (size_t)point;
        }
        text[length] = 0;
        return length;
    }
    text[length++] = digits[0];
    if (count > 1) {
        text[length++] = '.';
        memcpy(text + length, digits + 1, count - 1);
        length += count - 1;
    }
    length += (size_t)snprintf(text + length, 12, "e%s%lld", exponent >= 0 ? "+" : "", (long long)exponent);
    return length;
}

/* Raises the overflow fault of an operator, naming both operands. */
MS_NORETURN static void overflow_fault(const char *operation, const MsDecimal *left, const MsDecimal *right) {
    char left_text[MS_DECIMAL_RENDER_MAX + 1];
    char right_text[MS_DECIMAL_RENDER_MAX + 1];
    char message[320];
    (void)render_into(left, left_text);
    (void)render_into(right, right_text);
    const int length = snprintf(message, sizeof message,
                                "Decimal.%s: overflow; found left %s and right %s; rounded magnitude must be at "
                                "most 9.999999999999999999999999999999999e6144 (34 significant digits)",
                                operation, left_text, right_text);
    msfault_raise(MS_FAULT_OVERFLOW, message, length > 0 ? (size_t)length : 0);
}

/* ---- arithmetic ---- */

/* The magnitude of d's coefficient scaled up by 10^shift; false when it does not fit 128 bits. */
static bool scaled_magnitude(const MsDecimal *d, int64_t shift, MsU128 *out) {
    if (shift > MS_DECIMAL_WIDE_DIGITS) {
        return false;
    }
    return !__builtin_mul_overflow(magnitude_of(coefficient_of(d)), power_of_ten((unsigned)shift), out);
}

/* The sum or difference when both aligned coefficients and their combination fit 128 bits (the common case). */
static bool combine_wide(const MsDecimal *a, const MsDecimal *b, bool subtract, int64_t exponent, MsDecimal *out) {
    MsU128 left = 0;
    MsU128 right = 0;
    if (!scaled_magnitude(a, a->exponent - exponent, &left) || !scaled_magnitude(b, b->exponent - exponent, &right)) {
        return false;
    }
    const bool left_negative = coefficient_of(a) < 0;
    const bool right_negative = (coefficient_of(b) < 0) != subtract;
    MsU128 magnitude = 0;
    bool negative = left_negative;
    if (left_negative == right_negative) {
        if (__builtin_add_overflow(left, right, &magnitude)) {
            return false;
        }
    } else if (left >= right) {
        magnitude = left - right;
    } else {
        magnitude = right - left;
        negative = right_negative;
    }
    if (!round_wide(magnitude, negative, exponent, out)) {
        overflow_fault(subtract ? "-" : "+", a, b);
    }
    return true;
}

/* The exact sum or difference shares one alignment: both coefficients are scaled to the smaller exponent. */
static void combine(const MsDecimal *a, const MsDecimal *b, bool subtract, MsDecimal *out) {
    if (is_zero(b)) {
        *out = *a;
        return;
    }
    if (is_zero(a)) {
        if (subtract) {
            msstd_decimal_negate(b, out);
        } else {
            *out = *b;
        }
        return;
    }
    const int64_t exponent = a->exponent < b->exponent ? a->exponent : b->exponent;
    if (combine_wide(a, b, subtract, exponent, out)) {
        return;
    }
    MsBig left = MS_BIG_ZERO;
    MsBig right = MS_BIG_ZERO;
    MsBig scale = MS_BIG_ZERO;
    big_from_coefficient(&left, a);
    big_from_coefficient(&right, b);
    ms_big_pow10(&scale, (size_t)(a->exponent - exponent));
    ms_big_mul(&left, &left, &scale);
    ms_big_pow10(&scale, (size_t)(b->exponent - exponent));
    ms_big_mul(&right, &right, &scale);
    if (subtract) {
        ms_big_sub(&left, &left, &right);
    } else {
        ms_big_add(&left, &left, &right);
    }
    const bool fits = rounded(&left, exponent, out);
    ms_big_free(&left);
    ms_big_free(&right);
    ms_big_free(&scale);
    if (!fits) {
        overflow_fault(subtract ? "-" : "+", a, b);
    }
}

void msstd_decimal_add(const MsDecimal *a, const MsDecimal *b, MsDecimal *out) { combine(a, b, false, out); }

void msstd_decimal_subtract(const MsDecimal *a, const MsDecimal *b, MsDecimal *out) { combine(a, b, true, out); }

void msstd_decimal_multiply(const MsDecimal *a, const MsDecimal *b, MsDecimal *out) {
    MsU128 product = 0;
    if (!__builtin_mul_overflow(magnitude_of(coefficient_of(a)), magnitude_of(coefficient_of(b)), &product)) {
        const bool negative = (coefficient_of(a) < 0) != (coefficient_of(b) < 0);
        if (!round_wide(product, negative, a->exponent + b->exponent, out)) {
            overflow_fault("*", a, b);
        }
        return;
    }
    MsBig left = MS_BIG_ZERO;
    MsBig right = MS_BIG_ZERO;
    big_from_coefficient(&left, a);
    big_from_coefficient(&right, b);
    ms_big_mul(&left, &left, &right);
    const bool fits = rounded(&left, a->exponent + b->exponent, out);
    ms_big_free(&left);
    ms_big_free(&right);
    if (!fits) {
        overflow_fault("*", a, b);
    }
}

/* The quotient to 36 or more digits plus a sticky digit, so rounding at 34 digits is exact. */
void msstd_decimal_divide(const MsDecimal *a, const MsDecimal *b, MsDecimal *out) {
    static const char zero_message[] = "Decimal./: division by zero; right must be nonzero, found 0";
    if (is_zero(b)) {
        msfault_raise(MS_FAULT_DIVISION_BY_ZERO, zero_message, sizeof zero_message - 1);
    }
    if (is_zero(a)) {
        *out = pack(0, 0);
        return;
    }
    const bool negative = (coefficient_of(a) < 0) != (coefficient_of(b) < 0);
    MsBig dividend = MS_BIG_ZERO;
    MsBig divisor = MS_BIG_ZERO;
    MsBig scale = MS_BIG_ZERO;
    MsBig remainder = MS_BIG_ZERO;
    big_from_coefficient(&dividend, a);
    big_from_coefficient(&divisor, b);
    ms_big_abs(&dividend, &dividend);
    ms_big_abs(&divisor, &divisor);
    int64_t shift = MS_DECIMAL_DIGITS + 2 + big_digits(&divisor) - big_digits(&dividend);
    shift = shift > 0 ? shift : 0;
    int64_t exponent = a->exponent - b->exponent - shift;
    ms_big_pow10(&scale, (size_t)shift);
    ms_big_mul(&dividend, &dividend, &scale);
    ms_big_divmod(&dividend, &remainder, &dividend, &divisor);
    if (!ms_big_is_zero(&remainder)) { /* a sticky digit: the quotient has at least 35 digits, so it only breaks ties */
        ms_big_set_u64(&scale, 10);
        ms_big_mul(&dividend, &dividend, &scale);
        ms_big_set_u64(&scale, 1);
        ms_big_add(&dividend, &dividend, &scale);
        exponent--;
    }
    if (negative) {
        ms_big_negate(&dividend, &dividend);
    }
    const bool fits = rounded(&dividend, exponent, out);
    ms_big_free(&dividend);
    ms_big_free(&divisor);
    ms_big_free(&scale);
    ms_big_free(&remainder);
    if (!fits) {
        overflow_fault("/", a, b);
    }
}

void msstd_decimal_negate(const MsDecimal *a, MsDecimal *out) {
    *out = pack(-coefficient_of(a), a->exponent); /* at most 34 digits, so the negation fits */
}

/* ---- comparison ---- */

static int compare_magnitudes(MsU128 a, int64_t a_exponent, MsU128 b, int64_t b_exponent) {
    const unsigned a_digits = digits_of(a) - 1;
    const unsigned b_digits = digits_of(b) - 1;
    const MsI128 a_lead = (MsI128)a_exponent + (MsI128)a_digits;
    const MsI128 b_lead = (MsI128)b_exponent + (MsI128)b_digits;
    if (a_lead != b_lead) {
        return a_lead < b_lead ? -1 : 1;
    }
    /* Equal leading exponents need at most 33 places of alignment; a wider product cannot be the smaller. */
    MsU128 scaled = 0;
    if (a_digits < b_digits) {
        if (__builtin_mul_overflow(a, power_of_ten(b_digits - a_digits), &scaled)) {
            return 1;
        }
        return (scaled > b) - (scaled < b);
    }
    if (__builtin_mul_overflow(b, power_of_ten(a_digits - b_digits), &scaled)) {
        return -1;
    }
    return (a > scaled) - (a < scaled);
}

int64_t msstd_decimal_compare(const MsDecimal *a, const MsDecimal *b) {
    const MsI128 x = coefficient_of(a);
    const MsI128 y = coefficient_of(b);
    if (a->exponent == b->exponent || (x < 0) != (y < 0) || x == 0 || y == 0) {
        return (x > y) - (x < y);
    }
    const int magnitude = compare_magnitudes(magnitude_of(x), a->exponent, magnitude_of(y), b->exponent);
    return x < 0 ? -magnitude : magnitude;
}

/* ---- construction and conversion ---- */

static MsDecimal from_integer(uint64_t magnitude, bool negative) {
    int64_t exponent = 0;
    MsU128 value = magnitude;
    normalize(&value, &exponent);
    return pack(negative ? -(MsI128)value : (MsI128)value, exponent);
}

void msstd_decimal_from_int(int64_t n, MsDecimal *out) {
    *out = from_integer(n < 0 ? 0 - (uint64_t)n : (uint64_t)n, n < 0);
}

void msstd_decimal_from_uint(int64_t n, MsDecimal *out) { *out = from_integer((uint64_t)n, false); }

void msstd_decimal_to_string(const MsDecimal *a, MsStr *out) {
    char text[MS_DECIMAL_RENDER_MAX + 1];
    const size_t length = render_into(a, text);
    msrt_string_from_bytes((const uint8_t *)text, length, out);
}

/* The nearest double of coefficient * 10^exponent, from the text `<coefficient>e<exponent>`, which the C library
 * rounds correctly and which has no decimal point to depend on the locale. */
double msstd_decimal_to_float(const MsDecimal *a) {
    if (is_zero(a)) {
        return 0.0;
    }
    char digits[MS_DECIMAL_RENDER_MAX];
    const MsI128 coefficient = coefficient_of(a);
    MsU128 magnitude = magnitude_of(coefficient);
    size_t start = sizeof digits;
    for (; magnitude != 0; magnitude /= 10) {
        digits[--start] = (char)('0' + (int)(magnitude % 10));
    }
    char text[MS_DECIMAL_RENDER_MAX + 16];
    const int length = snprintf(text, sizeof text, "%s%.*se%lld", coefficient < 0 ? "-" : "",
                                (int)(sizeof digits - start), digits + start, (long long)a->exponent);
    return length > 0 ? strtod(text, NULL) : 0.0;
}

/* The integer part toward zero, when it fits an int64_t. */
uint8_t msstd_decimal_truncate_to_int(const MsDecimal *a, int64_t *out) {
    const MsI128 coefficient = coefficient_of(a);
    MsI128 value = 0;
    if (a->exponent >= 0) {
        if (coefficient == 0) {
            *out = 0;
            return 1;
        }
        if (a->exponent > 19 || __builtin_mul_overflow(coefficient, (MsI128)power_of_ten((unsigned)a->exponent), &value)) {
            return 0;
        }
    } else if (-a->exponent > 38) {
        *out = 0; /* the coefficient has at most 34 digits */
        return 1;
    } else {
        value = coefficient / (MsI128)power_of_ten((unsigned)-a->exponent);
    }
    if (value < INT64_MIN || value > INT64_MAX) {
        return 0;
    }
    *out = (int64_t)value;
    return 1;
}

/* ---- parsing ---- */

/* An exponent written with an optional sign, in the range of an int32_t; false when it is not. */
MS_NODISCARD static bool parse_exponent(MsBytes text, int64_t *out) {
    size_t at = 0;
    const bool negative = text.len > 0 && text.ptr[0] == '-';
    if (text.len > 0 && (text.ptr[0] == '-' || text.ptr[0] == '+')) {
        at = 1;
    }
    int64_t value = 0;
    for (; at < text.len; at++) {
        value = value * 10 + (text.ptr[at] - '0');
        if (value > (int64_t)INT32_MAX + 1) {
            return false;
        }
    }
    if (value > INT32_MAX && !(negative && value == (int64_t)INT32_MAX + 1)) {
        return false;
    }
    *out = negative ? -value : value;
    return true;
}

static bool is_digit(uint8_t byte) { return byte >= '0' && byte <= '9'; }

/* The digits of a mantissa with at most one point inside it, point removed; false for anything else. Stores
 * the digit count and the number of fraction digits. */
typedef struct MsMantissa {
    size_t leading_zeros;
    size_t trailing_zeros;
    size_t count;
    size_t fraction;
    MsU128 trimmed; /* the digits without leading or trailing zeros, when there are at most 34 of them */
    bool too_wide;
} MsMantissa;

MS_NODISCARD static bool scan_mantissa(MsBytes text, MsMantissa *out) {
    MsMantissa m = {0};
    size_t point = text.len;
    for (size_t i = 0; i < text.len; i++) {
        if (text.ptr[i] == '.' && point == text.len) {
            point = i;
        } else if (!is_digit(text.ptr[i])) {
            return false;
        }
    }
    if (point != text.len && (point == 0 || point == text.len - 1)) {
        return false;
    }
    bool seen_nonzero = false;
    size_t zeros = 0;
    for (size_t i = 0; i < text.len; i++) {
        if (i == point) {
            continue;
        }
        const uint8_t digit = (uint8_t)(text.ptr[i] - '0');
        m.count++;
        if (digit == 0 && !seen_nonzero) {
            m.leading_zeros++;
        } else {
            seen_nonzero = true;
            zeros = digit == 0 ? zeros + 1 : 0;
            m.too_wide = m.too_wide || m.count - m.leading_zeros - zeros > MS_DECIMAL_DIGITS;
        }
    }
    m.trailing_zeros = seen_nonzero ? zeros : 0;
    m.fraction = point == text.len ? 0 : text.len - point - 1;
    *out = m;
    return true;
}

/* Accumulates the significant digits (all but leading and trailing zeros); there are at most 34. */
static MsU128 significant_digits(MsBytes text, const MsMantissa *m) {
    MsU128 value = 0;
    size_t seen = 0;
    const size_t end = m->count - m->trailing_zeros;
    for (size_t i = 0; i < text.len; i++) {
        if (!is_digit(text.ptr[i])) {
            continue; /* the point */
        }
        if (seen >= m->leading_zeros && seen < end) {
            value = value * 10 + (MsU128)(text.ptr[i] - '0');
        }
        seen++;
    }
    return value;
}

/* The literal grammar of Decimal: an optional sign, digits with at most one inner point, an optional exponent
 * (`e` or `E`, signed digits) and an optional trailing `d`. */
MS_NODISCARD static bool parse_literal(MsBytes text, MsDecimal *out) {
    size_t end = text.len;
    size_t start = 0;
    if (end > 0 && text.ptr[end - 1] == 'd') {
        end--;
    }
    const bool negative = end > 0 && text.ptr[0] == '-';
    if (end > 0 && (text.ptr[0] == '-' || text.ptr[0] == '+')) {
        start = 1;
    }
    size_t marker = end;
    for (size_t i = start; i < end && marker == end; i++) {
        if (text.ptr[i] == 'e' || text.ptr[i] == 'E') {
            marker = i;
        }
    }
    const MsBytes mantissa_text = ms_bytes_of(text.ptr + start, marker - start);
    const MsBytes exponent_text = marker == end ? ms_bytes_of((const uint8_t *)"0", 1) : ms_bytes_of(text.ptr + marker + 1, end - marker - 1);
    size_t sign = exponent_text.len > 0 && (exponent_text.ptr[0] == '-' || exponent_text.ptr[0] == '+') ? 1 : 0;
    MsMantissa m = {0};
    if (exponent_text.len == sign || mantissa_text.len == 0) {
        return false;
    }
    for (; sign < exponent_text.len; sign++) {
        if (!is_digit(exponent_text.ptr[sign])) {
            return false;
        }
    }
    if (!scan_mantissa(mantissa_text, &m)) {
        return false;
    }
    int64_t exponent = 0;
    if (m.leading_zeros == m.count) {
        *out = pack(0, 0);
        return true;
    }
    if (!parse_exponent(exponent_text, &exponent)) {
        return false;
    }
    const int64_t quantum = exponent - (int64_t)m.fraction + (int64_t)m.trailing_zeros;
    const int64_t width = (int64_t)(m.count - m.leading_zeros - m.trailing_zeros);
    if (m.too_wide || quantum < MS_DECIMAL_MIN_QUANTUM || quantum + width - 1 > MS_DECIMAL_MAX_EXPONENT) {
        return false;
    }
    const MsI128 value = (MsI128)significant_digits(mantissa_text, &m);
    *out = pack(negative ? -value : value, quantum);
    return true;
}

uint8_t msstd_decimal_parse(const MsStr *text, MsDecimal *out) {
    MsDecimal parsed = {0};
    if (!parse_literal(ms_bytes_of(ms_str_data(text), ms_str_len(text)), &parsed)) {
        return MS_STATUS_INVALID_INPUT;
    }
    *out = parsed;
    return MS_STATUS_OK;
}

/* ---- rounding ---- */

MS_NODISCARD static bool rounding_of(HasRaw has_mode, int64_t index, MsRounding *mode) {
    if (has_mode == 0) {
        *mode = MS_ROUND_HALF_EVEN;
        return true;
    }
    if (index < MS_ROUND_HALF_EVEN || index > MS_ROUND_CEIL) {
        return false;
    }
    *mode = (MsRounding)index;
    return true;
}

/* Whether discarding a nonzero remainder moves the kept magnitude up by one. */
static bool rounds_up(MsRounding mode, int comparison_with_half, bool kept_is_odd, bool negative) {
    switch (mode) {
    case MS_ROUND_HALF_EVEN: return comparison_with_half > 0 || (comparison_with_half == 0 && kept_is_odd);
    case MS_ROUND_HALF_AWAY: return comparison_with_half >= 0;
    case MS_ROUND_TOWARD_ZERO: return false;
    case MS_ROUND_FLOOR: return negative;
    case MS_ROUND_CEIL: return !negative;
    }
    return false;
}

/* The coefficient of `d` rounded to a multiple of 10^-places. */
static void scaled_coefficient(MsBig *out, const MsDecimal *d, int64_t places, MsRounding mode) {
    big_from_coefficient(out, d);
    if (ms_big_is_zero(out)) {
        return;
    }
    const int64_t shift = d->exponent + places;
    MsBig scale = MS_BIG_ZERO;
    if (shift >= 0) {
        ms_big_pow10(&scale, (size_t)shift);
        ms_big_mul(out, out, &scale);
        ms_big_free(&scale);
        return;
    }
    const bool negative = ms_big_sign(out) < 0;
    if (-shift > MS_DECIMAL_DIGITS) {
        /* The coefficient has at most 34 digits, so twice it is below the divisor: nearest rounding and
         * truncation give zero and only a directed mode moves one unit away. */
        const bool away = (mode == MS_ROUND_FLOOR && negative) || (mode == MS_ROUND_CEIL && !negative);
        const int unit = negative ? -1 : 1;
        ms_big_set_i64(out, away ? unit : 0);
        return;
    }
    MsBig remainder = MS_BIG_ZERO;
    MsBig twice = MS_BIG_ZERO;
    ms_big_pow10(&scale, (size_t)-shift);
    ms_big_abs(out, out);
    ms_big_divmod(out, &remainder, out, &scale);
    if (!ms_big_is_zero(&remainder)) {
        ms_big_shift_left(&twice, &remainder, 1);
        if (rounds_up(mode, ms_big_cmp(&twice, &scale), ms_big_is_odd(out), negative)) {
            ms_big_set_u64(&twice, 1);
            ms_big_add(out, out, &twice);
        }
    }
    if (negative) {
        ms_big_negate(out, out);
    }
    ms_big_free(&scale);
    ms_big_free(&remainder);
    ms_big_free(&twice);
}

/* |coefficient| / 10^drop rounded by `mode`, for a drop of at least one digit. A 34-digit coefficient is below
 * 10^34, so a drop beyond 34 digits leaves less than half a unit: nearest rounding and truncation give zero and only
 * a directed mode moves one unit away. */
static MsU128 rounded_magnitude(MsU128 magnitude, bool negative, int64_t drop, MsRounding mode) {
    if (drop > MS_DECIMAL_DIGITS) {
        const bool away = (mode == MS_ROUND_FLOOR && negative) || (mode == MS_ROUND_CEIL && !negative);
        return away ? 1 : 0;
    }
    const MsU128 unit = power_of_ten((unsigned)drop);
    const MsU128 remainder = magnitude % unit;
    MsU128 quotient = magnitude / unit;
    if (remainder != 0) {
        const MsU128 complement = unit - remainder;
        const int comparison_with_half = (remainder > complement) - (remainder < complement);
        if (rounds_up(mode, comparison_with_half, (quotient & 1) != 0, negative)) {
            quotient++;
        }
    }
    return quotient;
}

uint8_t msstd_decimal_round(const MsDecimal *value, int64_t places, HasRaw has_mode, int64_t mode, MsDecimal *out) {
    MsRounding rounding = MS_ROUND_HALF_EVEN;
    if (!rounding_of(has_mode, mode, &rounding) || places < -6144 || places > 6176) {
        return MS_STATUS_INVALID_INPUT;
    }
    if (is_zero(value) || value->exponent + places >= 0) { /* already an exact multiple of this quantum */
        *out = *value;
        return MS_STATUS_OK;
    }
    const bool negative = coefficient_of(value) < 0;
    const int64_t drop = -(value->exponent + places);
    MsU128 magnitude = rounded_magnitude(magnitude_of(coefficient_of(value)), negative, drop, rounding);
    int64_t exponent = -places;
    normalize(&magnitude, &exponent);
    if (magnitude != 0) {
        const int64_t digits = digits_of(magnitude);
        if (digits > MS_DECIMAL_DIGITS || exponent < MS_DECIMAL_MIN_QUANTUM ||
            exponent + digits - 1 > MS_DECIMAL_MAX_EXPONENT) {
            return MS_STATUS_OUT_OF_RANGE;
        }
    }
    *out = pack(negative ? -(MsI128)magnitude : (MsI128)magnitude, exponent);
    return MS_STATUS_OK;
}

/* Plain notation with exactly `places` fractional digits, built from the digits of the scaled coefficient. */
static void format_fixed(const MsBig *scaled, int64_t places, MsStr *out) {
    size_t count = 0;
    uint8_t *const digits = ms_big_digits_new(scaled, 10, &count);
    const size_t fraction = (size_t)places;
    const size_t padded = count > fraction ? count : fraction + 1; /* an integer digit before the point */
    uint8_t *const text = msrt_alloc(padded + 3);
    size_t length = 0;
    if (ms_big_sign(scaled) < 0) {
        text[length++] = '-';
    }
    for (size_t i = 0; i < padded; i++) {
        if (i == padded - fraction && fraction > 0) {
            text[length++] = '.';
        }
        const size_t from_end = padded - i; /* position counted from the last digit */
        text[length++] = from_end > count ? '0' : digits[count - from_end];
    }
    msrt_string_from_bytes(text, length, out);
    msrt_free(text);
    msrt_free(digits);
}

uint8_t msstd_decimal_to_fixed(const MsDecimal *value, int64_t digits, HasRaw has_mode, int64_t mode, MsStr *out) {
    MsRounding rounding = MS_ROUND_HALF_EVEN;
    if (!rounding_of(has_mode, mode, &rounding) || digits < 0 || digits > 6176) {
        return MS_STATUS_INVALID_INPUT;
    }
    MsBig scaled = MS_BIG_ZERO;
    scaled_coefficient(&scaled, value, digits, rounding);
    format_fixed(&scaled, digits, out);
    ms_big_free(&scaled);
    return MS_STATUS_OK;
}

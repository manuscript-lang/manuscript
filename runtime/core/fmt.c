/* Number to text: decimal and radix integers, shortest round-trip floats, and the precision forms.
 *
 * Everything writes through a MsFmtSink into a buffer the caller owns and sizes; nothing allocates and nothing
 * can write past the end. One copy serves interpolation, to_string and the JSON encoder. Ported from
 * crates/ms-rt/src/num.rs and float_digits.rs; the output is byte-identical to that code.
 */
#include "ms_rt/fmt.h"
#include "fmt_fixed.h"

#include "float_table.h"

typedef unsigned __int128 MsU128;

/* ---- the output sink ---- */

/* Bytes are appended until the buffer is full. A write that does not fit sets `overflowed` and every later write
 * does nothing, so a formatter writes straight through and the entry point checks once at the end. */
typedef struct MsFmtSink {
    MsBytesMut buffer; /* borrowed from the caller */
    size_t length;     /* bytes written so far, at most buffer.len */
    bool overflowed;
} MsFmtSink;

static MsFmtSink sink_new(uint8_t *out, size_t capacity) {
    return (MsFmtSink){.buffer = ms_bytes_mut(out, capacity), .length = 0, .overflowed = false};
}

static void sink_put(MsFmtSink *sink, MsBytes bytes) {
    if (sink->overflowed) {
        return;
    }
    MsBytesMut room = {0};
    if (!ms_bytes_mut_slice(sink->buffer, sink->length, sink->buffer.len, &room) || !ms_bytes_copy(room, bytes)) {
        sink->overflowed = true;
        return;
    }
    sink->length += bytes.len; /* the copy fit, so this stays within buffer.len */
}

static void sink_put_byte(MsFmtSink *sink, uint8_t byte) {
    if (sink->overflowed || sink->length >= sink->buffer.len) {
        sink->overflowed = true;
        return;
    }
    sink->buffer.ptr[sink->length] = byte;
    sink->length++;
}

static void sink_put_text(MsFmtSink *sink, const char *text) {
    for (const char *c = text; *c != '\0'; c++) {
        sink_put_byte(sink, (uint8_t)*c);
    }
}

static void sink_put_zeros(MsFmtSink *sink, size_t count) {
    for (size_t i = 0; i < count; i++) {
        sink_put_byte(sink, '0');
    }
}

/* Reports the sink as the entry points do: true with the length written, or false when anything overflowed. */
MS_NODISCARD static bool sink_finish(const MsFmtSink *sink, size_t *length) {
    if (sink->overflowed) {
        return false;
    }
    *length = sink->length;
    return true;
}

/* ---- integers ---- */

#define MS_U64_DIGITS 20

static const char decimal_pairs[] =
    "0001020304050607080910111213141516171819"
    "2021222324252627282930313233343536373839"
    "4041424344454647484950515253545556575859"
    "6061626364656667686970717273747576777879"
    "8081828384858687888990919293949596979899";
_Static_assert(sizeof decimal_pairs == 201, "two digits for each of 0..99 and the terminator");

static const uint64_t powers_of_ten[MS_U64_DIGITS] = {
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

/* How many decimal digits `value` has, 1..=20. A value with `bits` significant bits has about bits * log10(2)
 * digits; `estimate` is that rounded down, so it is the digit count minus one, or equal to it when the value is
 * below 10^estimate (Hacker's Delight, "Integer Log"). `estimate` is at most 19 for 64 bits, inside the table. */
static size_t decimal_length(uint64_t value) {
    const uint64_t nonzero = value | 1; /* clz of 0 is undefined; 0 and 1 both have one digit, and the powers are even */
    const unsigned bits = 64 - (unsigned)__builtin_clzll(nonzero);
    const size_t estimate = ((size_t)bits * 1233) >> 12;
    return estimate + (nonzero >= powers_of_ten[estimate] ? 1 : 0);
}

/* Writes the decimal digits of `value` at the start of `room`, two digits at a time from the end, and returns
 * how many. The length is checked against the room once; `position` then stays inside it because it starts at the
 * digit count and each step removes the digits it writes. */
MS_NODISCARD static bool write_decimal(MsBytesMut room, uint64_t value, size_t *written) {
    const size_t length = decimal_length(value);
    if (room.ptr == NULL || length > room.len) {
        return false;
    }
    size_t position = length;
    while (value >= 100) {
        const size_t pair = (size_t)(value % 100) * 2;
        value /= 100;
        position -= 2;
        room.ptr[position] = (uint8_t)decimal_pairs[pair];
        room.ptr[position + 1] = (uint8_t)decimal_pairs[pair + 1];
    }
    if (value >= 10) {
        const size_t pair = (size_t)value * 2;
        room.ptr[0] = (uint8_t)decimal_pairs[pair];
        room.ptr[1] = (uint8_t)decimal_pairs[pair + 1];
    } else {
        room.ptr[0] = (uint8_t)('0' + value);
    }
    *written = length;
    return true;
}

/* The room left in the sink's buffer. */
static MsBytesMut sink_room(const MsFmtSink *sink) {
    MsBytesMut room = {0};
    if (!ms_bytes_mut_slice(sink->buffer, sink->length, sink->buffer.len, &room)) {
        return ms_bytes_mut(NULL, 0);
    }
    return room;
}

static void sink_put_unsigned(MsFmtSink *sink, uint64_t value) {
    size_t written = 0;
    if (sink->overflowed || !write_decimal(sink_room(sink), value, &written)) {
        sink->overflowed = true;
        return;
    }
    sink->length += written; /* write_decimal stayed within the room */
}

static void sink_put_signed(MsFmtSink *sink, int64_t value) {
    if (value < 0) {
        sink_put_byte(sink, '-');
    }
    /* The magnitude of INT64_MIN is 2^63, which only the unsigned negation represents. */
    sink_put_unsigned(sink, value < 0 ? UINT64_C(0) - (uint64_t)value : (uint64_t)value);
}

bool msrt_fmt_u64(uint64_t value, uint8_t *out, size_t capacity, size_t *length) {
    MsFmtSink sink = sink_new(out, capacity);
    sink_put_unsigned(&sink, value);
    return sink_finish(&sink, length);
}

size_t ms_fmt_i64_fixed(int64_t value, uint8_t out[static MS_FMT_INTEGER_CAPACITY]) {
    const bool negative = value < 0;
    out[0] = '-'; /* overwritten by the first digit of a value that is not negative */
    /* The magnitude of INT64_MIN is 2^63, which only the unsigned negation represents. */
    const uint64_t magnitude = negative ? UINT64_C(0) - (uint64_t)value : (uint64_t)value;
    size_t written = 0;
    /* The room is the capacity less the sign, which holds the 19 digits of a magnitude below 2^63 and the 20 of a
     * UInt64 never written here. */
    const MsBytesMut room = ms_bytes_mut(out + (negative ? 1 : 0), MS_FMT_INTEGER_CAPACITY - (negative ? 1 : 0));
    const bool fitted = write_decimal(room, magnitude, &written);
    (void)fitted; /* a magnitude of at most 2^63 has at most 19 digits */
    return written + (negative ? 1 : 0);
}

bool msrt_fmt_i64(int64_t value, uint8_t *out, size_t capacity, size_t *length) {
    MsFmtSink sink = sink_new(out, capacity);
    sink_put_signed(&sink, value);
    return sink_finish(&sink, length);
}

#define MS_RADIX_MIN 2
#define MS_RADIX_MAX 36
#define MS_RADIX_DIGITS 64

bool msrt_fmt_radix(uint64_t magnitude, uint32_t radix, uint8_t negative, uint8_t *out, size_t capacity, size_t *length) {
    if (radix < MS_RADIX_MIN || radix > MS_RADIX_MAX) {
        return false;
    }
    uint8_t reversed[MS_RADIX_DIGITS] = {0}; /* a UInt64 has at most 64 binary digits */
    size_t count = 0;
    do {
        const uint32_t digit = (uint32_t)(magnitude % radix);
        reversed[count] = (uint8_t)(digit < 10 ? '0' + digit : 'a' + (digit - 10));
        count++;
        magnitude /= radix;
    } while (magnitude != 0 && count < MS_COUNT_OF(reversed));
    MsFmtSink sink = sink_new(out, capacity);
    if (negative != 0) {
        sink_put_byte(&sink, '-');
    }
    while (count > 0) {
        count--;
        sink_put_byte(&sink, reversed[count]);
    }
    return sink_finish(&sink, length);
}

/* ---- shortest digits: Schubfach (Giulietti, 2020), as crates/ms-rt/src/float_digits.rs ---- */

#define MASK63 ((UINT64_C(1) << 63) - 1)

/* The layout of an IEEE 754 binary format. */
typedef struct MsFloatFormat {
    int mantissa_bits;
    int bias;
} MsFloatFormat;

static const MsFloatFormat binary64_format = {.mantissa_bits = 52, .bias = 1023};
static const MsFloatFormat binary32_format = {.mantissa_bits = 23, .bias = 127};

/* Floor of a scaled product, by a shift of a signed value: the compilers we build with shift arithmetically. */
static int floor_log10_pow2(int e) {
    return (int)(((int64_t)e * INT64_C(677859288149821)) >> 51);
}

static int floor_log10_three_quarters_pow2(int e) {
    return (int)(((int64_t)e * INT64_C(677859288149821) - INT64_C(281337023816645)) >> 51);
}

static int floor_log2_pow10(int e) {
    return (int)(((int64_t)e * INT64_C(935039633142891)) >> 48);
}

/* g * cp / 2^127 rounded to odd, where g = g1 * 2^63 + g0. */
static uint64_t round_to_odd(uint64_t g1, uint64_t g0, uint64_t cp) {
    const uint64_t x1 = (uint64_t)(((MsU128)g0 * cp) >> 64);
    const MsU128 y = (MsU128)g1 * cp;
    const uint64_t y1 = (uint64_t)(y >> 64);
    const uint64_t y0 = (uint64_t)y;
    const uint64_t z = (y0 >> 1) + x1;
    const uint64_t high = y1 + (z >> 63);
    return high | (((z & MASK63) + MASK63) >> 63);
}

/* A finite positive value as c * 2^q, with the format's smallest exponent and implicit bit. */
typedef struct MsBinaryValue {
    int q;
    uint64_t c;
    int q_min;
    uint64_t c_min;
} MsBinaryValue;

static MsBinaryValue split_binary(uint64_t bits, MsFloatFormat format) {
    const uint64_t c_min = UINT64_C(1) << format.mantissa_bits;
    const int biased = (int)((bits >> format.mantissa_bits) & 0x7ff); /* the sign bit is already clear */
    const uint64_t fraction = bits & (c_min - 1);
    const int q_min = 1 - format.bias - format.mantissa_bits;
    if (biased == 0) {
        return (MsBinaryValue){.q = q_min, .c = fraction, .q_min = q_min, .c_min = c_min};
    }
    return (MsBinaryValue){
        .q = biased - format.bias - format.mantissa_bits, .c = fraction | c_min, .q_min = q_min, .c_min = c_min};
}

/* The decimal d * 10^exponent nearest to the value among the shortest ones that round to it (an exact tie takes
 * the even digit); d may still end in zeros. False if the power-of-ten table has no entry, which no finite
 * value reaches. */
MS_NODISCARD static bool schubfach(MsBinaryValue value, uint64_t *digits, int *exponent) {
    const uint64_t out = value.c & 1;
    const uint64_t cb = value.c << 2;
    const uint64_t cbr = cb + 2;
    const bool lower_gap_is_half = value.c == value.c_min && value.q != value.q_min;
    const uint64_t cbl = lower_gap_is_half ? cb - 1 : cb - 2;
    const int k = lower_gap_is_half ? floor_log10_three_quarters_pow2(value.q) : floor_log10_pow2(value.q);
    const int shift = value.q + floor_log2_pow10(-k) + 2;
    const int table_index = k - MS_FLOAT_K_MIN;
    if (table_index < 0 || (size_t)table_index >= MS_COUNT_OF(ms_float_g) || shift < 0 || shift > 8) {
        return false;
    }
    const uint64_t g1 = ms_float_g[table_index][0];
    const uint64_t g0 = ms_float_g[table_index][1];
    const uint64_t vb = round_to_odd(g1, g0, cb << shift);
    const uint64_t vbl = round_to_odd(g1, g0, cbl << shift);
    const uint64_t vbr = round_to_odd(g1, g0, cbr << shift);
    *exponent = k;

    const uint64_t s = vb >> 2;
    if (s >= 10) {
        /* A multiple of ten inside the interval gives one digit fewer than `s` does. */
        const uint64_t s_tens = 10 * (s / 10);
        const uint64_t t_tens = s_tens + 10;
        const bool lower_in = vbl + out <= s_tens << 2;
        const bool upper_in = (t_tens << 2) + out <= vbr;
        if (lower_in != upper_in) {
            *digits = lower_in ? s_tens : t_tens;
            return true;
        }
    }
    const uint64_t t = s + 1;
    const bool s_in = vbl + out <= s << 2;
    const bool t_in = (t << 2) + out <= vbr;
    if (s_in != t_in) {
        *digits = s_in ? s : t;
        return true;
    }
    /* Both or neither is inside: the one nearer the value, an exact tie going to the even one. */
    const int64_t cmp = (int64_t)vb - (int64_t)((s + t) << 1);
    *digits = (cmp < 0 || (cmp == 0 && (s & 1) == 0)) ? s : t;
    return true;
}

/* Decimal digits with the decimal exponent of the first one: 12.5 is "125" with exponent 1. A shortest form has at
 * most 17 digits and an integer 20. */
#define MS_DIGITS_CAPACITY 24

typedef struct MsDigits {
    uint8_t text[MS_DIGITS_CAPACITY];
    size_t length;
    int exponent;
} MsDigits;

static MsDigits digits_of_unsigned(uint64_t value, int exponent_of_last_digit) {
    MsDigits digits = {.text = {0}, .length = 0, .exponent = 0};
    if (!write_decimal(ms_bytes_mut(digits.text, MS_DIGITS_CAPACITY), value, &digits.length)) {
        return digits; /* unreachable: a UInt64 has at most 20 digits */
    }
    /* `length` is at most 20, so the conversion is exact. */
    digits.exponent = exponent_of_last_digit + (int)digits.length - 1;
    return digits;
}

/* The shortest digits of the finite positive value with the given sign-cleared bits. */
MS_NODISCARD static bool shortest_digits(uint64_t bits, MsFloatFormat format, MsDigits *out) {
    uint64_t scaled = 0;
    int exponent = 0;
    if (!schubfach(split_binary(bits, format), &scaled, &exponent)) {
        return false;
    }
    while (scaled % 10 == 0) {
        scaled /= 10;
        exponent++;
    }
    *out = digits_of_unsigned(scaled, exponent);
    return true;
}

/* ---- float text ---- */

/* Plain notation for exponents in -6..=20, else scientific. */
#define MS_PLAIN_EXPONENT_MIN (-6)
#define MS_PLAIN_EXPONENT_MAX 20

/* digits[start..end], or an overflow when the range is wrong (which no caller's arithmetic produces). */
static void sink_put_slice(MsFmtSink *sink, MsBytes digits, size_t start, size_t end) {
    MsBytes piece = {0};
    if (ms_bytes_slice(digits, start, end, &piece)) {
        sink_put(sink, piece);
    } else {
        sink->overflowed = true;
    }
}

/* Plain notation: the digits with the decimal point placed by `exponent`, the exponent of the first digit. */
static void sink_put_plain(MsFmtSink *sink, MsBytes digits, int exponent) {
    const int point = exponent + 1; /* digits before the decimal point */
    if (point <= 0) {
        sink_put_text(sink, "0.");
        sink_put_zeros(sink, (size_t)-point);
        sink_put(sink, digits);
    } else if ((size_t)point >= digits.len) {
        sink_put(sink, digits);
        sink_put_zeros(sink, (size_t)point - digits.len);
    } else {
        sink_put_slice(sink, digits, 0, (size_t)point);
        sink_put_byte(sink, '.');
        sink_put_slice(sink, digits, (size_t)point, digits.len);
    }
}

static void sink_put_scientific(MsFmtSink *sink, MsBytes digits, int exponent) {
    sink_put_slice(sink, digits, 0, 1);
    if (digits.len > 1) {
        sink_put_byte(sink, '.');
        sink_put_slice(sink, digits, 1, digits.len);
    }
    sink_put_byte(sink, 'e');
    if (exponent >= 0) {
        sink_put_byte(sink, '+');
    }
    sink_put_signed(sink, exponent);
}

/* The digits as the shortest float text, trailing zeros dropped first. */
static void sink_put_decimal_text(MsFmtSink *sink, const MsDigits *digits, bool negative) {
    size_t length = digits->length;
    while (length > 1 && digits->text[length - 1] == '0') {
        length--;
    }
    const MsBytes significant = ms_bytes_of(digits->text, length);
    if (negative) {
        sink_put_byte(sink, '-');
    }
    if (digits->exponent >= MS_PLAIN_EXPONENT_MIN && digits->exponent <= MS_PLAIN_EXPONENT_MAX) {
        sink_put_plain(sink, significant, digits->exponent);
    } else {
        sink_put_scientific(sink, significant, digits->exponent);
    }
}

static uint64_t double_bits(double value) {
    uint64_t bits = 0;
    __builtin_memcpy(&bits, &value, sizeof bits);
    return bits;
}

static uint32_t float_bits(float value) {
    uint32_t bits = 0;
    __builtin_memcpy(&bits, &value, sizeof bits);
    return bits;
}

#define SIGN_BIT_64 (UINT64_C(1) << 63)

/* NaN, an infinity or a zero: the values with fixed text. Returns whether `value` was one of them. */
static bool sink_put_special(MsFmtSink *sink, double value) {
    const bool negative = (double_bits(value) & SIGN_BIT_64) != 0;
    if (__builtin_isnan(value)) {
        sink_put_text(sink, "NaN");
    } else if (__builtin_isinf(value)) {
        sink_put_text(sink, negative ? "-Infinity" : "Infinity");
    } else if (value == 0.0) {
        sink_put_text(sink, negative ? "-0" : "0");
    } else {
        return false;
    }
    return true;
}

/* An integral magnitude below 2^53 is exactly representable: its digits are the integer itself. */
#define MS_EXACT_INTEGER_LIMIT 9007199254740992.0

static bool float_digits(double magnitude, MsDigits *digits) {
    if (magnitude < MS_EXACT_INTEGER_LIMIT && magnitude == (double)(int64_t)magnitude) {
        *digits = digits_of_unsigned((uint64_t)magnitude, 0);
        return true;
    }
    return shortest_digits(double_bits(magnitude), binary64_format, digits);
}

static bool sink_put_float(MsFmtSink *sink, double value) {
    if (sink_put_special(sink, value)) {
        return true;
    }
    const bool negative = value < 0.0;
    MsDigits digits = {.text = {0}, .length = 0, .exponent = 0};
    if (!float_digits(negative ? -value : value, &digits)) {
        return false;
    }
    sink_put_decimal_text(sink, &digits, negative);
    return true;
}

bool msrt_fmt_float(double value, uint8_t *out, size_t capacity, size_t *length) {
    MsFmtSink sink = sink_new(out, capacity);
    return sink_put_float(&sink, value) && sink_finish(&sink, length);
}

bool msrt_fmt_float32(double value, uint8_t *out, size_t capacity, size_t *length) {
    const float narrowed = (float)value;
    MsFmtSink sink = sink_new(out, capacity);
    if (sink_put_special(&sink, (double)narrowed)) {
        return sink_finish(&sink, length);
    }
    MsDigits digits = {.text = {0}, .length = 0, .exponent = 0};
    const uint32_t bits = float_bits(narrowed);
    if (!shortest_digits(bits & 0x7fffffffu, binary32_format, &digits)) {
        return false;
    }
    sink_put_decimal_text(&sink, &digits, (bits >> 31) != 0);
    return sink_finish(&sink, length);
}

/* ---- precision forms: the exact decimal expansion, rounded half to even ---- */

#define MS_LIMB_BASE 1000000000u
#define MS_LIMB_DIGITS 9
/* c * 5^1074 is below 10^768; the limbs also hold c * 2^971. */
#define MS_LIMB_CAPACITY 96
#define MS_EXACT_DIGITS_CAPACITY ((size_t)MS_LIMB_CAPACITY * MS_LIMB_DIGITS)
/* The most digits any precision form keeps: 22 before the point and 100 after, plus a carry. */
#define MS_KEPT_CAPACITY 128
#define MS_PRECISION_MAX 100

/* A non-negative integer in base 10^9, least significant limb first. */
typedef struct MsBigNumber {
    uint32_t limbs[MS_LIMB_CAPACITY];
    size_t count;
} MsBigNumber;

static MsBigNumber big_from_unsigned(uint64_t value) {
    MsBigNumber number = {.limbs = {0}, .count = 0};
    for (; value != 0; value /= MS_LIMB_BASE) {
        number.limbs[number.count++] = (uint32_t)(value % MS_LIMB_BASE); /* a UInt64 has at most 3 limbs */
    }
    return number;
}

/* number *= multiplier; false when the result needs more limbs than there are. */
MS_NODISCARD static bool big_multiply(MsBigNumber *number, uint32_t multiplier) {
    uint64_t carry = 0;
    for (size_t i = 0; i < number->count; i++) {
        const MsU128 product = (MsU128)number->limbs[i] * multiplier + carry;
        number->limbs[i] = (uint32_t)(product % MS_LIMB_BASE);
        carry = (uint64_t)(product / MS_LIMB_BASE);
    }
    for (; carry != 0; carry /= MS_LIMB_BASE) {
        if (number->count >= MS_LIMB_CAPACITY) {
            return false;
        }
        number->limbs[number->count++] = (uint32_t)(carry % MS_LIMB_BASE);
    }
    return true;
}

/* number *= base^exponent, in steps whose multiplier fits 32 bits. */
MS_NODISCARD static bool big_multiply_power(MsBigNumber *number, uint32_t base, int exponent, int step_limit) {
    for (int left = exponent; left > 0;) {
        const int step = left < step_limit ? left : step_limit;
        uint32_t multiplier = 1;
        for (int i = 0; i < step; i++) {
            multiplier *= base;
        }
        if (!big_multiply(number, multiplier)) {
            return false;
        }
        left -= step;
    }
    return true;
}

/* Decimal digits, most significant first without leading zeros, and the exponent of the first. */
typedef struct MsExactDigits {
    uint8_t text[MS_EXACT_DIGITS_CAPACITY];
    size_t length;
    int point;
} MsExactDigits;

static void exact_push_limb(MsExactDigits *digits, uint32_t limb) {
    uint8_t text[MS_LIMB_DIGITS] = {0};
    for (size_t i = MS_LIMB_DIGITS; i > 0; i--) {
        text[i - 1] = (uint8_t)('0' + limb % 10);
        limb /= 10;
    }
    size_t first = 0;
    while (digits->length == 0 && first < MS_LIMB_DIGITS - 1 && text[first] == '0') {
        first++; /* no leading zeros in the number */
    }
    for (size_t i = first; i < MS_LIMB_DIGITS && digits->length < MS_EXACT_DIGITS_CAPACITY; i++) {
        digits->text[digits->length++] = text[i];
    }
}

/* The exact decimal expansion of the positive value c * 2^q. A negative q is c * 5^-q divided by 10^-q, so the
 * digits are those of an integer and only the exponent moves. */
MS_NODISCARD static bool exact_expansion(uint64_t c, int q, MsExactDigits *digits) {
    MsBigNumber number = big_from_unsigned(c);
    const bool grown = q >= 0 ? big_multiply_power(&number, 2, q, 29) : big_multiply_power(&number, 5, -q, 13);
    if (!grown) {
        return false;
    }
    digits->length = 0;
    for (size_t i = number.count; i > 0; i--) {
        exact_push_limb(digits, number.limbs[i - 1]);
    }
    const int decimal_shift = q < 0 ? q : 0;
    digits->point = (int)digits->length - 1 + decimal_shift; /* length is at most 864 */
    return true;
}

/* The leading `keep` digits of the expansion (zero-padded when it is shorter) rounded half to even, and the
 * exponent of the first kept digit, which grows by one when the rounding carries out. */
typedef struct MsKept {
    uint8_t text[MS_KEPT_CAPACITY];
    size_t length;
    int point;
} MsKept;

static bool any_nonzero(const MsExactDigits *digits, size_t from) {
    for (size_t i = from; i < digits->length; i++) {
        if (digits->text[i] != '0') {
            return true;
        }
    }
    return false;
}

static uint8_t exact_digit(const MsExactDigits *digits, size_t index) {
    return index < digits->length ? digits->text[index] : '0';
}

/* Whether the digits after the first `keep` are above half a unit, or exactly half with an odd last kept digit. */
static bool rounds_up(const MsExactDigits *digits, const MsKept *kept) {
    const size_t keep = kept->length;
    const uint8_t next = exact_digit(digits, keep);
    if (next != '5') {
        return next > '5';
    }
    if (any_nonzero(digits, keep + 1)) {
        return true;
    }
    return keep > 0 && ((kept->text[keep - 1] - '0') & 1) != 0;
}

/* Rounds to `keep` digits, 1..=MS_KEPT_CAPACITY. */
MS_NODISCARD static bool round_digits(const MsExactDigits *digits, size_t keep, MsKept *kept) {
    if (keep == 0 || keep > MS_KEPT_CAPACITY) {
        return false;
    }
    kept->length = keep;
    kept->point = digits->point;
    for (size_t i = 0; i < keep; i++) {
        kept->text[i] = exact_digit(digits, i);
    }
    if (!rounds_up(digits, kept)) {
        return true;
    }
    size_t i = keep;
    while (i > 0 && kept->text[i - 1] == '9') {
        i--;
        kept->text[i] = '0';
    }
    if (i == 0) {
        kept->text[0] = '1'; /* 99.9 rounded up is 100: the leading digit and the exponent move */
        kept->point++;
    } else {
        kept->text[i - 1]++;
    }
    return true;
}

static uint8_t kept_digit_at(const MsKept *kept, int exponent) {
    const int index = kept->point - exponent;
    return index >= 0 && (size_t)index < kept->length ? kept->text[index] : '0';
}

/* The fast path of to_fixed: up to 15 fractional digits of a value below 2^53, where c * 2^q * 10^digits is an
 * integer product that fits 128 bits. It is divided by a power of two, the remainder deciding the rounding (a
 * tie goes to the even last digit). */
#define MS_FIXED_FAST_DIGITS 15

typedef struct MsFixedRequest {
    bool negative;
    uint64_t c;
    int q;
    size_t digits;
} MsFixedRequest;

/* The value scaled to an integer count of 10^-digits, rounded; false when it does not fit 64 bits or the
 * request is out of this path's range. */
MS_NODISCARD static bool fixed_scaled(MsFixedRequest request, uint64_t scale, uint64_t *scaled) {
    if (request.q > 0) {
        return false;
    }
    const MsU128 product = (MsU128)request.c * scale;
    const unsigned shift = (unsigned)-request.q;
    MsU128 rounded = product;
    if (shift >= 128) {
        rounded = 0;
    } else if (shift > 0) {
        const MsU128 whole = product >> shift;
        const MsU128 rest = product & (((MsU128)1 << shift) - 1);
        const MsU128 half = (MsU128)1 << (shift - 1);
        rounded = whole + ((rest > half || (rest == half && (whole & 1) != 0)) ? 1 : 0);
    }
    if ((rounded >> 64) != 0) {
        return false;
    }
    *scaled = (uint64_t)rounded;
    return true;
}

static bool sink_put_fixed_fast(MsFmtSink *sink, MsFixedRequest request) {
    if (request.digits > MS_FIXED_FAST_DIGITS) {
        return false;
    }
    uint64_t scale = 1;
    for (size_t i = 0; i < request.digits; i++) {
        scale *= 10;
    }
    uint64_t scaled = 0;
    if (!fixed_scaled(request, scale, &scaled)) {
        return false;
    }
    if (request.negative) {
        sink_put_byte(sink, '-');
    }
    sink_put_unsigned(sink, scaled / scale);
    if (request.digits > 0) {
        const uint64_t fraction = scaled % scale;
        sink_put_byte(sink, '.');
        sink_put_zeros(sink, request.digits - decimal_length(fraction));
        sink_put_unsigned(sink, fraction);
    }
    return true;
}

/* A value split for the precision forms. */
typedef struct MsPrecisionValue {
    bool negative;
    uint64_t c; /* zero for 0.0 */
    int q;
} MsPrecisionValue;

static MsPrecisionValue split_precision(double value) {
    const uint64_t bits = double_bits(value);
    const int biased = (int)((bits >> 52) & 0x7ff);
    const uint64_t fraction = bits & ((UINT64_C(1) << 52) - 1);
    const bool normal = biased != 0;
    return (MsPrecisionValue){.negative = (bits & SIGN_BIT_64) != 0,
                              .c = normal ? (fraction | (UINT64_C(1) << 52)) : fraction,
                              .q = normal ? biased - 1075 : -1074};
}

/* to_fixed through the exact expansion: digits are kept down to 10^-want. */
static bool sink_put_fixed_exact(MsFmtSink *sink, MsPrecisionValue value, size_t want) {
    MsExactDigits exact = {.text = {0}, .length = 0, .point = 0};
    MsKept kept = {.text = {0}, .length = 0, .point = 0};
    if (value.c != 0) {
        if (!exact_expansion(value.c, value.q, &exact)) {
            return false;
        }
        const int keep = exact.point + 1 + (int)want;
        if (keep > 0 && !round_digits(&exact, (size_t)keep, &kept)) {
            return false;
        }
        if (keep == 0 && (exact.text[0] > '5' || (exact.text[0] == '5' && any_nonzero(&exact, 1)))) {
            /* Below one unit of the last place but above half of it: rounds up to that unit. */
            kept = (MsKept){.text = {'1'}, .length = 1, .point = -(int)want};
        }
    }
    if (value.negative) {
        sink_put_byte(sink, '-');
    }
    if (kept.length == 0 || kept.point < 0) {
        sink_put_byte(sink, '0');
    } else {
        for (int e = kept.point; e >= 0; e--) {
            sink_put_byte(sink, kept_digit_at(&kept, e));
        }
    }
    if (want > 0) {
        sink_put_byte(sink, '.');
        for (size_t i = 0; i < want; i++) {
            sink_put_byte(sink, kept_digit_at(&kept, -1 - (int)i));
        }
    }
    return true;
}

typedef enum MsPrecisionForm {
    MS_FORM_FIXED,       /* 'f': digits after the point */
    MS_FORM_EXPONENTIAL, /* 'e': digits after the first digit */
    MS_FORM_PRECISION,   /* 'g': significant digits, plain notation for exponents -6..digits */
} MsPrecisionForm;

static bool parse_form(uint8_t letter, MsPrecisionForm *form) {
    switch (letter) {
    case 'f': *form = MS_FORM_FIXED; return true;
    case 'e': *form = MS_FORM_EXPONENTIAL; return true;
    case 'g': *form = MS_FORM_PRECISION; return true;
    default: return false;
    }
}

/* The scientific forms: `after` digits follow the first, rounded from the exact expansion. */
static bool sink_put_significant(MsFmtSink *sink, MsPrecisionValue value, MsPrecisionForm form, size_t digits) {
    const size_t after = form == MS_FORM_PRECISION ? digits - 1 : digits;
    MsKept kept = {.text = {0}, .length = after + 1, .point = 0}; /* 0.0 keeps zeros at exponent 0 */
    for (size_t i = 0; i < kept.length && i < MS_KEPT_CAPACITY; i++) {
        kept.text[i] = '0';
    }
    if (value.c != 0) {
        MsExactDigits exact = {.text = {0}, .length = 0, .point = 0};
        if (!exact_expansion(value.c, value.q, &exact) || !round_digits(&exact, after + 1, &kept)) {
            return false;
        }
    }
    if (value.negative) {
        sink_put_byte(sink, '-');
    }
    const int exponent = kept.point;
    if (form == MS_FORM_PRECISION && exponent >= MS_PLAIN_EXPONENT_MIN && exponent < (int)digits) {
        sink_put_plain(sink, ms_bytes_of(kept.text, kept.length), exponent);
        return true;
    }
    sink_put_byte(sink, kept.text[0]);
    if (after > 0) {
        sink_put_byte(sink, '.');
        for (size_t i = 1; i <= after; i++) {
            sink_put_byte(sink, kept.text[i]);
        }
    }
    sink_put_byte(sink, 'e');
    if (exponent >= 0) {
        sink_put_byte(sink, '+');
    }
    sink_put_signed(sink, exponent);
    return true;
}

bool msrt_fmt_float_precision(double value, uint8_t format, int64_t digits, uint8_t *out, size_t capacity, size_t *length) {
    MsPrecisionForm form = MS_FORM_FIXED;
    const int64_t minimum = format == 'g' ? 1 : 0;
    if (!parse_form(format, &form) || digits < minimum || digits > MS_PRECISION_MAX) {
        return false;
    }
    MsFmtSink sink = sink_new(out, capacity);
    const bool fixed_overflows_precision = form == MS_FORM_FIXED && (value >= 1e21 || value <= -1e21);
    if (__builtin_isnan(value) || __builtin_isinf(value) || fixed_overflows_precision) {
        return sink_put_float(&sink, value) && sink_finish(&sink, length);
    }
    const MsPrecisionValue split = split_precision(value);
    bool written = false;
    if (form == MS_FORM_FIXED) {
        const MsFixedRequest request = {.negative = split.negative, .c = split.c, .q = split.q, .digits = (size_t)digits};
        written = sink_put_fixed_fast(&sink, request) || sink_put_fixed_exact(&sink, split, (size_t)digits);
    } else {
        written = sink_put_significant(&sink, split, form, (size_t)digits);
    }
    return written && sink_finish(&sink, length);
}

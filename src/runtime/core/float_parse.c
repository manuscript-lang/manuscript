/* `Numbers.parse_float` and `String.parse_float`: decimal and exponent syntax only,
 * `^[+-]?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$`, plus the spellings NaN, Infinity, +Infinity and -Infinity.
 * Ported from crates/ms-rt/src/num.rs. One pass checks the syntax and collects what the fast path needs; a
 * literal with at most 19 digits, a mantissa of at most 2^53 and a power of ten within 22 is two exact binary64
 * operands and one correctly rounded multiplication or division (Clinger). Every other literal goes to the C
 * library's strtod through ms_sys_parse_decimal. */
#include "ms_rt/num.h"
#include "ms_rt/safe.h"
#include "ms_rt/strbuild.h"
#include "ms_rt/sys.h"

/* The fast path's limits: digits that fit a uint64, a mantissa binary64 holds exactly, powers of ten it holds. */
#define MS_FAST_DIGITS 19
#define MS_FAST_MANTISSA (UINT64_C(1) << 53)
#define MS_FAST_POWER 22
/* An exponent written with more digits than this is far beyond any double; it stops growing here. */
#define MS_EXPONENT_CAP 100000

static const double powers_of_ten[MS_FAST_POWER + 1] = {
    1e0,  1e1,  1e2,  1e3,  1e4,  1e5,  1e6,  1e7,  1e8,  1e9,  1e10, 1e11,
    1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22,
};

/* What one pass over a valid literal found. */
typedef struct Literal {
    bool negative;
    uint64_t mantissa; /* all digits as an integer; meaningful when digits <= MS_FAST_DIGITS */
    size_t digits;
    int64_t exponent; /* the written exponent less the fraction digits */
} Literal;

static bool is_digit(uint8_t byte) {
    return byte >= '0' && byte <= '9';
}

/* The number of digits in the run that starts at `at`. */
static size_t digit_run(MsBytes text, size_t at) {
    size_t end = at;
    while (end < text.len && is_digit(text.ptr[end])) {
        end++;
    }
    return end - at;
}

static void add_digits(Literal *literal, MsBytes text, size_t at, size_t count) {
    for (size_t i = 0; i < count; i++) {
        literal->digits++;
        if (literal->digits <= MS_FAST_DIGITS) {
            literal->mantissa = literal->mantissa * 10 + (uint64_t)(text.ptr[at + i] - '0');
        }
    }
}

/* Checks the syntax of the whole text and fills `literal`; false for anything else. */
static bool scan(MsBytes text, Literal *literal) {
    size_t at = 0;
    if (at < text.len && (text.ptr[at] == '+' || text.ptr[at] == '-')) {
        literal->negative = text.ptr[at] == '-';
        at++;
    }
    size_t count = digit_run(text, at);
    if (count == 0) {
        return false;
    }
    add_digits(literal, text, at, count);
    at += count;
    if (at < text.len && text.ptr[at] == '.') {
        at++;
        count = digit_run(text, at);
        if (count == 0) {
            return false;
        }
        add_digits(literal, text, at, count);
        literal->exponent -= (int64_t)count;
        at += count;
    }
    if (at < text.len && (text.ptr[at] == 'e' || text.ptr[at] == 'E')) {
        at++;
        const bool down = at < text.len && text.ptr[at] == '-';
        if (at < text.len && (text.ptr[at] == '+' || text.ptr[at] == '-')) {
            at++;
        }
        count = digit_run(text, at);
        if (count == 0) {
            return false;
        }
        int64_t written = 0;
        for (size_t i = 0; i < count && written < MS_EXPONENT_CAP; i++) {
            written = written * 10 + (text.ptr[at + i] - '0');
        }
        literal->exponent += down ? -written : written;
        at += count;
    }
    return at == text.len;
}

/* Whether the literal is exactly two binary64 operands and a power of ten the table holds. */
static bool fast_path(const Literal *literal) {
    return literal->digits <= MS_FAST_DIGITS && literal->mantissa <= MS_FAST_MANTISSA &&
           literal->exponent >= -MS_FAST_POWER && literal->exponent <= MS_FAST_POWER;
}

static double fast_value(const Literal *literal) {
    const double mantissa = (double)literal->mantissa;
    const double value = literal->exponent < 0 ? mantissa / powers_of_ten[-literal->exponent]
                                               : mantissa * powers_of_ten[literal->exponent];
    return literal->negative ? -value : value;
}

static bool is_spelling(MsBytes text, const char *spelling, size_t length) {
    return text.len == length && __builtin_memcmp(text.ptr, spelling, length) == 0;
}

/* NaN, Infinity, +Infinity and -Infinity; false for any other text. */
static bool named_value(MsBytes text, double *value) {
    if (is_spelling(text, "NaN", 3)) {
        *value = __builtin_nan("");
    } else if (is_spelling(text, "Infinity", 8) || is_spelling(text, "+Infinity", 9)) {
        *value = __builtin_inf();
    } else if (is_spelling(text, "-Infinity", 9)) {
        *value = -__builtin_inf();
    } else {
        return false;
    }
    return true;
}

uint8_t msrt_numbers_parse_float(const MsStr *text, double *out) {
    const MsBytes bytes = ms_str_bytes(text);
    if (named_value(bytes, out)) {
        return MS_STATUS_OK;
    }
    Literal literal = {0};
    if (!scan(bytes, &literal)) {
        return MS_STATUS_INVALID_DATA;
    }
    if (fast_path(&literal)) {
        *out = fast_value(&literal);
        return MS_STATUS_OK;
    }
    double value = 0;
    if (!ms_sys_parse_decimal(bytes.ptr, bytes.len, &value)) {
        ms_limit_fault();
    }
    if (__builtin_isinf(value)) {
        return MS_STATUS_OUT_OF_RANGE;
    }
    *out = value;
    return MS_STATUS_OK;
}

uint8_t msrt_string_parse_float(const MsStr *s, double *out) {
    return msrt_numbers_parse_float(s, out) == MS_STATUS_OK;
}

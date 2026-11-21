/* The scalar decoders of @std/data/json: the text of a number node (or an object key) as an integer or a float.
 * Each answers MS_STATUS_OK, or MS_STATUS_INVALID_INPUT for text that is not an in-range number. */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "ms_rt/chars.h"
#include "ms_rt/json.h"
#include "ms_rt/safe.h"

/* The digits of `text` after an optional sign, as the 64-bit magnitude; false for no digits or an overflow. */
MS_NODISCARD static bool parse_magnitude(MsBytes text, bool *negative, uint64_t *magnitude) {
    size_t at = 0;
    *negative = false;
    if (at < text.len && (text.ptr[at] == '+' || text.ptr[at] == '-')) {
        *negative = text.ptr[at] == '-';
        at++;
    }
    if (at == text.len) {
        return false;
    }
    uint64_t value = 0;
    for (; at < text.len; at++) {
        const uint8_t c = text.ptr[at];
        if (!ms_ascii_is_digit(c) || value > (UINT64_MAX - (uint64_t)(c - '0')) / 10) {
            return false;
        }
        value = value * 10 + (uint64_t)(c - '0');
    }
    *magnitude = value;
    return true;
}

/* A decimal Int: an optional sign and digits, nothing else, within 64 bits. */
MS_NODISCARD static bool parse_i64(MsBytes text, int64_t *out) {
    bool negative = false;
    uint64_t magnitude = 0;
    if (!parse_magnitude(text, &negative, &magnitude)) {
        return false;
    }
    const uint64_t limit = negative ? (uint64_t)INT64_MAX + 1 : (uint64_t)INT64_MAX;
    if (magnitude > limit) {
        return false;
    }
    *out = negative ? (int64_t)(0 - magnitude) : (int64_t)magnitude;
    return true;
}

static MsBytes bytes_of(const MsStr *text) { return ms_bytes_of(ms_str_data(text), ms_str_len(text)); }

uint8_t msstd_json_dec_int(const MsStr *text, int64_t *out) {
    return parse_i64(bytes_of(text), out) ? MS_STATUS_OK : MS_STATUS_INVALID_INPUT;
}

/* An integer in lo..=hi, for the sized signed and narrower unsigned types. */
uint8_t msstd_json_dec_int_in(const MsStr *text, int64_t lo, int64_t hi, int64_t *out) {
    int64_t value = 0;
    if (!parse_i64(bytes_of(text), &value) || value < lo || value > hi) {
        return MS_STATUS_INVALID_INPUT;
    }
    *out = value;
    return MS_STATUS_OK;
}

/* A UInt64 as its bit pattern. */
uint8_t msstd_json_dec_uint(const MsStr *text, int64_t *out) {
    bool negative = false;
    uint64_t magnitude = 0;
    const MsBytes bytes = bytes_of(text);
    if (bytes.len > 0 && bytes.ptr[0] == '-') {
        return MS_STATUS_INVALID_INPUT;
    }
    if (!parse_magnitude(bytes, &negative, &magnitude)) {
        return MS_STATUS_INVALID_INPUT;
    }
    *out = (int64_t)magnitude;
    return MS_STATUS_OK;
}

/* Whether `text` is a decimal float: a sign, digits with an optional fraction (or a fraction alone), and an
 * optional exponent. Words such as `inf` and `nan` are not. */
static bool is_decimal_float(MsBytes text) {
    size_t at = 0;
    if (at < text.len && (text.ptr[at] == '+' || text.ptr[at] == '-')) {
        at++;
    }
    size_t whole = 0;
    while (at < text.len && ms_ascii_is_digit(text.ptr[at])) {
        at++;
        whole++;
    }
    size_t fraction = 0;
    if (at < text.len && text.ptr[at] == '.') {
        at++;
        while (at < text.len && ms_ascii_is_digit(text.ptr[at])) {
            at++;
            fraction++;
        }
    }
    if (whole + fraction == 0) {
        return false;
    }
    if (at < text.len && (text.ptr[at] == 'e' || text.ptr[at] == 'E')) {
        at++;
        if (at < text.len && (text.ptr[at] == '+' || text.ptr[at] == '-')) {
            at++;
        }
        size_t exponent = 0;
        while (at < text.len && ms_ascii_is_digit(text.ptr[at])) {
            at++;
            exponent++;
        }
        if (exponent == 0) {
            return false;
        }
    }
    return at == text.len;
}

/* A finite float from the text, rounded once to a double (or, for `single`, to a float). */
static bool parse_float(const MsStr *text, bool single, double *out) {
    const MsBytes bytes = bytes_of(text);
    if (!is_decimal_float(bytes)) {
        return false;
    }
    char *copy = msrt_alloc(bytes.len + 1);
    memcpy(copy, bytes.ptr, bytes.len);
    copy[bytes.len] = '\0';
    /* The program never sets a locale, so the decimal point is '.'. */
    const double value = single ? (double)strtof(copy, NULL) : strtod(copy, NULL); /* NOLINT(cert-err34-c): the text was checked */
    msrt_free(copy);
    if (!isfinite(value)) {
        return false;
    }
    *out = value;
    return true;
}

/* A Float32 value as the double holding it; a finite number too large for a Float32 is not a number. */
uint8_t msstd_json_dec_float32(const MsStr *text, double *out) {
    return parse_float(text, true, out) ? MS_STATUS_OK : MS_STATUS_INVALID_INPUT;
}

uint8_t msstd_json_dec_float(const MsStr *text, double *out) {
    return parse_float(text, false, out) ? MS_STATUS_OK : MS_STATUS_INVALID_INPUT;
}

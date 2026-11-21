/* Text helpers over MsStr that follow Rust's `str` methods: `trim` removes Unicode White_Space, and
 * the rest are the prefix, suffix and slice operations the passes that port Rust code need. Strings
 * are valid UTF-8. */
#ifndef MS_TEXT_H
#define MS_TEXT_H

#include <string.h>

#include "ms/base.h"
#include "ms_rt/chars.h"

static inline bool ms_text_is_unicode_space(uint32_t scalar) {
    if (scalar == ' ' || (scalar >= 0x09 && scalar <= 0x0D)) {
        return true;
    }
    if (scalar < 0x85) {
        return false;
    }
    return scalar == 0x85 || scalar == 0xA0 || scalar == 0x1680 ||
           (scalar >= 0x2000 && scalar <= 0x200A) || scalar == 0x2028 || scalar == 0x2029 ||
           scalar == 0x202F || scalar == 0x205F || scalar == 0x3000;
}

/* The scalar that starts at text[at], and its length in bytes. `text` is valid UTF-8. */
static inline uint32_t ms_text_scalar_at(MsStr text, uint32_t at, int *length) {
    uint32_t scalar = 0;
    *length = ms_utf8_decode(text.ptr + at, text.len - at, &scalar);
    return scalar;
}

/* The start of the last scalar that ends at text[end]. */
static inline uint32_t ms_text_last_scalar_start(MsStr text, uint32_t end) {
    uint32_t start = end - 1;
    while (start > 0 && ms_utf8_is_continuation((uint8_t)text.ptr[start])) {
        start--;
    }
    return start;
}

static inline MsStr ms_text_trim_start(MsStr text) {
    uint32_t at = 0;
    while (at < text.len) {
        int length = 0;
        if (!ms_text_is_unicode_space(ms_text_scalar_at(text, at, &length))) {
            break;
        }
        at += (uint32_t)length;
    }
    return (MsStr){text.ptr + at, text.len - at};
}

static inline MsStr ms_text_trim_end(MsStr text) {
    uint32_t end = text.len;
    while (end > 0) {
        uint32_t start = ms_text_last_scalar_start(text, end);
        int length = 0;
        if (!ms_text_is_unicode_space(ms_text_scalar_at(text, start, &length))) {
            break;
        }
        end = start;
    }
    return (MsStr){text.ptr, end};
}

static inline MsStr ms_text_trim(MsStr text) { return ms_text_trim_end(ms_text_trim_start(text)); }

static inline bool ms_text_starts_with(MsStr text, const char *prefix) {
    size_t length = strlen(prefix);
    return text.len >= length && memcmp(text.ptr, prefix, length) == 0;
}

static inline bool ms_text_ends_with(MsStr text, const char *suffix) {
    size_t length = strlen(suffix);
    return text.len >= length && memcmp(text.ptr + text.len - length, suffix, length) == 0;
}

static inline bool ms_text_is(MsStr text, const char *literal) {
    const size_t length = strlen(literal);
    return text.len == length && memcmp(text.ptr, literal, length) == 0;
}

static inline bool ms_text_contains(MsStr text, const char *needle) {
    const size_t length = strlen(needle);
    for (size_t at = 0; at + length <= text.len; at++) {
        if (memcmp(text.ptr + at, needle, length) == 0) {
            return true;
        }
    }
    return false;
}

/* The value of a hexadecimal digit, or -1 for any other character. */
static inline int ms_text_digit_value(char c) {
    uint32_t value = 0;
    return ms_hex_digit_value((uint8_t)c, &value) ? (int)value : -1;
}

/* A character of a bare TOML key: a letter, digit, underscore or dash. */
static inline bool ms_text_is_bare_key_char(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-';
}

static inline MsStr ms_text_drop_front(MsStr text, size_t count) {
    return (MsStr){text.ptr + count, (uint32_t)(text.len - count)};
}

static inline MsStr ms_text_drop_back(MsStr text, size_t count) {
    return (MsStr){text.ptr, (uint32_t)(text.len - count)};
}

static inline bool ms_text_equal(MsStr a, MsStr b) { return a.len == b.len && memcmp(a.ptr, b.ptr, a.len) == 0; }

#endif

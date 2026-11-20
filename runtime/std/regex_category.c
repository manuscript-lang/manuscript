/* Whether a scalar has a Unicode general category: the three `unicode.ms` asks for (punctuation, symbol, mark),
 * answered by PCRE2's tables through one compiled pattern per category. */
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>
#include <stdatomic.h>

#include "ms_rt/regex.h"
#include "ms_rt/safe.h"
#include "regex_internal.h"

enum { CATEGORY_COUNT = 3 };

/* The category letters, in the order of `compiled`. */
static const char category_letters[CATEGORY_COUNT] = {'P', 'S', 'M'};

/* One compiled pattern per category, shared by every thread: a pattern is immutable once compiled, so a thread that
 * loses the race to publish one frees its own. */
static _Atomic(pcre2_code *) compiled[CATEGORY_COUNT];

static pcre2_code *compile_category(char letter) {
    const char pattern[] = {'^', '\\', 'p', '{', letter, '}', '$', '\0'};
    int error = 0;
    PCRE2_SIZE offset = 0;
    return pcre2_compile((PCRE2_SPTR)pattern, PCRE2_ZERO_TERMINATED, PCRE2_UTF | PCRE2_UCP, &error, &offset, NULL);
}

static pcre2_code *category_code(size_t slot) {
    pcre2_code *code = atomic_load(&compiled[slot]);
    if (code != NULL) {
        return code;
    }
    pcre2_code *fresh = compile_category(category_letters[slot]);
    if (fresh == NULL) {
        return NULL;
    }
    pcre2_code *expected = NULL;
    if (atomic_compare_exchange_strong(&compiled[slot], &expected, fresh)) {
        return fresh;
    }
    pcre2_code_free(fresh);
    return expected;
}

/* The slot of "P", "S" or "M"; CATEGORY_COUNT for anything else. */
static size_t slot_of(const MsStr *category) {
    if (ms_str_len(category) != 1) {
        return CATEGORY_COUNT;
    }
    for (size_t slot = 0; slot < CATEGORY_COUNT; slot++) {
        if (ms_str_data(category)[0] == (uint8_t)category_letters[slot]) {
            return slot;
        }
    }
    return CATEGORY_COUNT;
}

/* The UTF-8 encoding of a scalar; 0 bytes for a value that is not one. */
static size_t encode_scalar(int64_t value, uint8_t out[4]) {
    if (value < 0 || value > 0x10FFFF || (value >= 0xD800 && value <= 0xDFFF)) {
        return 0;
    }
    const uint32_t scalar = (uint32_t)value;
    if (scalar < 0x80) {
        out[0] = (uint8_t)scalar;
        return 1;
    }
    if (scalar < 0x800) {
        out[0] = (uint8_t)(0xC0 | (scalar >> 6));
        out[1] = (uint8_t)(0x80 | (scalar & 0x3F));
        return 2;
    }
    if (scalar < 0x10000) {
        out[0] = (uint8_t)(0xE0 | (scalar >> 12));
        out[1] = (uint8_t)(0x80 | ((scalar >> 6) & 0x3F));
        out[2] = (uint8_t)(0x80 | (scalar & 0x3F));
        return 3;
    }
    out[0] = (uint8_t)(0xF0 | (scalar >> 18));
    out[1] = (uint8_t)(0x80 | ((scalar >> 12) & 0x3F));
    out[2] = (uint8_t)(0x80 | ((scalar >> 6) & 0x3F));
    out[3] = (uint8_t)(0x80 | (scalar & 0x3F));
    return 4;
}

uint8_t msstd_unicode_in_category(int64_t value, const MsStr *category) {
    uint8_t encoded[4];
    const size_t slot = slot_of(category);
    const size_t length = encode_scalar(value, encoded);
    if (slot == CATEGORY_COUNT || length == 0) {
        return 0;
    }
    pcre2_code *code = category_code(slot);
    pcre2_match_data *data = code ? pcre2_match_data_create_from_pattern(code, NULL) : NULL;
    const int result = data ? pcre2_match(code, encoded, length, 0, 0, data, NULL) : PCRE2_ERROR_NOMEMORY;
    pcre2_match_data_free(data);
    return result >= 0;
}

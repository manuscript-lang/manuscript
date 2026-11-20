/* A fixed-size text buffer for messages. See text.h. */
#include "text.h"

#define DECIMAL_DIGITS_MAX 20

static void add_bytes(MsText *text, const char *bytes, size_t count) {
    const size_t room = MS_TEXT_CAPACITY - text->len;
    const size_t taken = count < room ? count : room;
    __builtin_memcpy(text->bytes + text->len, bytes, taken);
    text->len += taken;
}

void ms_text_add(MsText *text, const char *literal) {
    add_bytes(text, literal, __builtin_strlen(literal));
}

void ms_text_add_i64(MsText *text, int64_t value) {
    char digits[DECIMAL_DIGITS_MAX];
    size_t start = DECIMAL_DIGITS_MAX;
    /* Negate in unsigned arithmetic so that INT64_MIN has a magnitude. */
    uint64_t magnitude = value < 0 ? (uint64_t)0 - (uint64_t)value : (uint64_t)value;
    do {
        start--;
        digits[start] = (char)('0' + magnitude % 10);
        magnitude /= 10;
    } while (magnitude != 0);
    if (value < 0) {
        add_bytes(text, "-", 1);
    }
    add_bytes(text, digits + start, DECIMAL_DIGITS_MAX - start);
}

void ms_text_fault(const MsText *text, MsFaultKind kind) {
    msfault_raise((uint8_t)kind, (const uint8_t *)text->bytes, text->len);
}

void ms_text_to_string(const MsText *text, MsStr *out) {
    msrt_string_from_bytes((const uint8_t *)text->bytes, text->len, out);
}

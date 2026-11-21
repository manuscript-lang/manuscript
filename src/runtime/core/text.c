/* A fixed-size text buffer for messages. See text.h. */
#include "text.h"

#include "ms_rt/fmt.h"

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
    uint8_t digits[MS_FMT_INTEGER_CAPACITY];
    size_t count = 0;
    if (msrt_fmt_i64(value, digits, sizeof digits, &count)) {
        add_bytes(text, (const char *)digits, count);
    }
}

void ms_text_fault(const MsText *text, MsFaultKind kind) {
    msfault_raise((uint8_t)kind, (const uint8_t *)text->bytes, text->len);
}

void ms_text_to_string(const MsText *text, MsStr *out) {
    msrt_string_from_bytes((const uint8_t *)text->bytes, text->len, out);
}

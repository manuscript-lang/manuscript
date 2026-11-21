/* `String.quote`: the double-quoted, escaped spelling of a string, as `%q` writes it. Ported from
 * crates/ms-rt/src/string.rs. Quote, backslash, line feed, tab and carriage return take a two-byte escape; every
 * other control byte and DEL take `\x` and two lower-case hex digits; all other bytes, whole UTF-8 sequences
 * included, are copied. The output length is counted first, so the result is one exact allocation. */
#include "ms_rt/safe.h"
#include "ms_rt/strbuild.h"

#define MS_DEL 0x7Fu
#define MS_FIRST_PRINTABLE 0x20u
#define MS_HEX_ESCAPE_WIDTH 4u /* \xNN */
#define MS_PAIR_ESCAPE_WIDTH 2u

/* The letter that follows the backslash of a two-byte escape for `byte`, or 0 when the byte has none. */
static uint8_t pair_escape(uint8_t byte) {
    switch (byte) {
    case '"':
        return '"';
    case '\\':
        return '\\';
    case '\n':
        return 'n';
    case '\t':
        return 't';
    case '\r':
        return 'r';
    default:
        return 0;
    }
}

/* The lower-case hex digit of a value below 16. */
static uint8_t hex_digit(unsigned nibble) {
    static const uint8_t digits[] = "0123456789abcdef";
    return digits[nibble & 0xFu];
}

static bool needs_hex_escape(uint8_t byte) {
    return byte < MS_FIRST_PRINTABLE || byte == MS_DEL;
}

static size_t quoted_width(uint8_t byte) {
    if (pair_escape(byte) != 0) {
        return MS_PAIR_ESCAPE_WIDTH;
    }
    return needs_hex_escape(byte) ? MS_HEX_ESCAPE_WIDTH : 1;
}

/* The bytes of the quoted text, quotes included. */
static size_t quoted_length(MsBytes text) {
    size_t length = 2;
    for (size_t i = 0; i < text.len; i++) {
        if (!ms_size_add(length, quoted_width(text.ptr[i]), &length)) {
            ms_limit_fault();
        }
    }
    return length;
}

/* Writes into a block whose size the length count fixed, through checked spans. */
typedef struct Writer {
    MsBytesMut block;
    size_t used;
} Writer;

static void put(Writer *writer, uint8_t byte) {
    MsBytesMut room = {0};
    if (!ms_bytes_mut_slice(writer->block, writer->used, writer->block.len, &room) || room.len == 0) {
        ms_limit_fault();
    }
    room.ptr[0] = byte;
    writer->used++;
}

static void put_escaped(Writer *writer, uint8_t byte) {
    const uint8_t letter = pair_escape(byte);
    if (letter != 0) {
        put(writer, '\\');
        put(writer, letter);
    } else if (needs_hex_escape(byte)) {
        put(writer, '\\');
        put(writer, 'x');
        put(writer, hex_digit(byte >> 4u));
        put(writer, hex_digit(byte));
    } else {
        put(writer, byte);
    }
}

static void write_quoted(Writer *writer, MsBytes text) {
    put(writer, '"');
    for (size_t i = 0; i < text.len; i++) {
        put_escaped(writer, text.ptr[i]);
    }
    put(writer, '"');
}

void msrt_string_quote(const MsStr *s, MsStr *out) {
    const MsBytes text = ms_str_bytes(s);
    const size_t length = quoted_length(text);
    if (length <= MS_STR_INLINE_MAX) {
        uint8_t small[MS_STR_INLINE_MAX];
        Writer writer = {.block = ms_bytes_mut(small, length), .used = 0};
        write_quoted(&writer, text);
        *out = ms_str_from_bytes(small, length);
        return;
    }
    MsStr result = ms_str_alloc(length);
    Writer writer = {.block = ms_bytes_mut(result.ptr_word, length), .used = 0};
    write_quoted(&writer, text);
    *out = ms_bytes_ascii(text.ptr, text.len) ? ms_str_with_ascii(result) : result;
}

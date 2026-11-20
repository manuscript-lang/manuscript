/* Strings as lists: the runtime's chars, lines, fields, scalar_values, from_scalars, to_bytes and view_bytes.
 * Ported from crates/ms-rt/src/string.rs. Results are written through `out`, which the caller owns from then on.
 * Text is read through spans (MsBytes), sizes are multiplied with the checked helpers of ms_rt/safe.h, and a
 * list or string past the 1 GiB limit faults like `concat`. */
#include <string.h>
#include "ms_rt/alloc.h"
#include "ms_rt/chars.h"
#include "ms_rt/safe.h"
#include "ms_rt/search.h"
#include "ms_rt/strbuild.h"
#include "ms_rt/utf8.h"
#include "string_slice.h"

/* A list that grows starts with room for this many elements. */
#define MS_LIST_FIRST_CAPACITY 4
/* The highest Unicode scalar, and the surrogate range that is not a scalar. */
#define MS_SCALAR_MAX UINT32_C(0x10FFFF)
#define MS_SURROGATE_FIRST UINT32_C(0xD800)
#define MS_SURROGATE_LAST UINT32_C(0xDFFF)
/* U+FFFD, the replacement for a stray byte. */
static const uint8_t replacement_character[] = {0xEF, 0xBF, 0xBD};

/* Allocates room for `count` elements of `size` bytes; null for none. */
static void *alloc_elements(size_t count, size_t size) {
    size_t bytes = 0;
    if (!ms_size_mul(count, size, &bytes)) {
        ms_limit_fault();
    }
    return count == 0 ? NULL : msrt_alloc(bytes);
}

/* ---- Lists of strings ---- */

/* Makes room for at least one more string. */
static void strings_grow(MsVec *list) {
    const size_t capacity = list->cap == 0 ? MS_LIST_FIRST_CAPACITY : list->cap * 2;
    size_t bytes = 0;
    if (!ms_size_mul(capacity, sizeof(MsStr), &bytes)) {
        ms_limit_fault();
    }
    list->ptr = list->ptr == NULL ? msrt_alloc(bytes) : msrt_realloc(list->ptr, bytes);
    list->cap = capacity;
}

static void strings_push(MsVec *list, MsStr piece) {
    if (list->len == list->cap) {
        strings_grow(list);
    }
    MsStr *pieces = list->ptr;
    pieces[list->len] = piece;
    list->len++;
}

/* A list of `count` one-byte ASCII strings, one per byte of `text`; each is a shared static string. */
static MsVec ascii_characters(MsBytes text) {
    MsStr *characters = alloc_elements(text.len, sizeof(MsStr));
    for (size_t i = 0; i < text.len; i++) {
        characters[i] = ms_str_ascii_char(text.ptr[i]);
    }
    return (MsVec){.ptr = characters, .len = text.len, .cap = text.len};
}

/* The one-character string for the scalar at the start of `rest`; a stray byte reads as U+FFFD. */
static MsStr character_at(MsBytes rest, size_t *width) {
    MsRune rune = ms_utf8_decode(rest.ptr, rest.len);
    *width = rune.width;
    if (rune.rune == MS_RUNE_ERROR && rune.width == 1) {
        return ms_str_from_bytes(replacement_character, sizeof replacement_character);
    }
    MsBytes character = ms_string_slice(rest, 0, rune.width);
    return ms_str_from_bytes(character.ptr, character.len);
}

/* `String.chars`: one string per scalar. */
void msrt_string_chars(const MsStr *s, MsVec *out) {
    MsBytes text = ms_str_bytes(s);
    if (text.len > 0 && ms_bytes_ascii(text.ptr, text.len)) {
        *out = ascii_characters(text);
        return;
    }
    MsVec list = {0};
    size_t at = 0;
    while (at < text.len) {
        size_t width = 0;
        strings_push(&list, character_at(ms_string_slice(text, at, text.len), &width));
        at += width;
    }
    *out = list;
}

/* ---- Lines and fields ---- */

/* The offset of the first line feed in `text`, or SIZE_MAX. */
static size_t find_line_feed(MsBytes text) {
    static const uint8_t line_feed = '\n';
    return ms_find(text.ptr, text.len, &line_feed, 1);
}

/* `String.lines`: the text between line feeds; a carriage return before one is dropped, and a final line
 * without a line feed counts only when it is not empty. */
void msrt_string_lines(const MsStr *s, MsVec *out) {
    MsBytes text = ms_str_bytes(s);
    MsVec list = {0};
    size_t start = 0;
    for (;;) {
        size_t found = find_line_feed(ms_string_slice(text, start, text.len));
        if (found == SIZE_MAX) {
            break;
        }
        size_t end = start + found;
        if (end > start && text.ptr[end - 1] == '\r') {
            end--;
        }
        MsBytes line = ms_string_slice(text, start, end);
        strings_push(&list, ms_str_from_bytes(line.ptr, line.len));
        start += found + 1;
    }
    if (start < text.len) {
        MsBytes last = ms_string_slice(text, start, text.len);
        strings_push(&list, ms_str_from_bytes(last.ptr, last.len));
    }
    *out = list;
}

/* Whether the scalar at the start of `rest` is White_Space, and its width. A byte below 0x80 is tested
 * directly, so ordinary text is one byte loop. */
static bool space_at(MsBytes rest, size_t *width) {
    if (rest.ptr[0] < 0x80) {
        *width = 1;
        return ms_ascii_is_space(rest.ptr[0]);
    }
    MsRune rune = ms_utf8_decode(rest.ptr, rest.len);
    *width = rune.width;
    return ms_utf8_is_space(rune.rune);
}

/* `String.fields`: the runs of text between Unicode White_Space, none empty. */
void msrt_string_fields(const MsStr *s, MsVec *out) {
    MsBytes text = ms_str_bytes(s);
    MsVec list = {0};
    bool in_field = false;
    size_t field_start = 0;
    size_t at = 0;
    while (at < text.len) {
        size_t width = 0;
        const bool space = space_at(ms_string_slice(text, at, text.len), &width);
        if (space && in_field) {
            MsBytes field = ms_string_slice(text, field_start, at);
            strings_push(&list, ms_str_from_bytes(field.ptr, field.len));
            in_field = false;
        } else if (!space && !in_field) {
            in_field = true;
            field_start = at;
        }
        at += width;
    }
    if (in_field) {
        MsBytes field = ms_string_slice(text, field_start, text.len);
        strings_push(&list, ms_str_from_bytes(field.ptr, field.len));
    }
    *out = list;
}

/* ---- Scalars and bytes ---- */

/* `String.scalar_values`: the scalars as a list of Int. */
void msrt_string_scalar_values(const MsStr *s, MsVec *out) {
    MsBytes text = ms_str_bytes(s);
    const size_t count = ms_utf8_count(text.ptr, text.len);
    int64_t *values = alloc_elements(count, sizeof(int64_t));
    size_t at = 0;
    for (size_t k = 0; k < count; k++) {
        MsRune rune = ms_utf8_decode(text.ptr + at, text.len - at);
        values[k] = (int64_t)rune.rune;
        at += rune.width;
    }
    *out = (MsVec){.ptr = values, .len = count, .cap = count};
}

/* Whether `value` is a Unicode scalar. */
static bool is_scalar(int64_t value) {
    if (value < 0 || value > (int64_t)MS_SCALAR_MAX) {
        return false;
    }
    return value < (int64_t)MS_SURROGATE_FIRST || value > (int64_t)MS_SURROGATE_LAST;
}

/* The UTF-8 bytes of every value of `values` into a fresh buffer; false when a value is not a scalar. */
static bool encode_scalars(const int64_t *values, size_t count, MsBytesMut *buffer, size_t *length) {
    size_t used = 0;
    for (size_t k = 0; k < count; k++) {
        if (!is_scalar(values[k])) {
            return false;
        }
        uint8_t encoded[4] = {0};
        size_t width = ms_utf8_encode((uint32_t)values[k], encoded);
        MsBytesMut room = {0};
        if (!ms_bytes_mut_slice(*buffer, used, buffer->len, &room) || !ms_bytes_copy(room, ms_bytes_of(encoded, width))) {
            ms_string_internal_fault();
        }
        used += width;
    }
    *length = used;
    return true;
}

/* `String.from_scalars`: invalid input when a value is not a Unicode scalar. */
uint8_t msrt_string_from_scalars(const MsVec *values, MsStr *out) {
    const int64_t *scalars = values->ptr;
    size_t bound = 0;
    if (!ms_size_mul(values->len, 4, &bound) || bound > MS_STR_MAX_BYTES) {
        ms_limit_fault();
    }
    uint8_t *storage = bound == 0 ? NULL : msrt_alloc(bound);
    MsBytesMut buffer = ms_bytes_mut(storage, bound);
    size_t length = 0;
    const bool valid = encode_scalars(scalars, values->len, &buffer, &length);
    if (valid) {
        *out = ms_str_from_bytes(buffer.ptr, length);
    }
    if (storage != NULL) {
        msrt_free(storage);
    }
    return valid ? MS_STATUS_OK : MS_STATUS_INVALID_INPUT;
}

/* `String.to_bytes`: a copy of the UTF-8 bytes. An empty Bytes has a null pointer. */
void msrt_string_to_bytes(const MsStr *s, MsVec *out) {
    MsBytes text = ms_str_bytes(s);
    uint8_t *copy = text.len == 0 ? NULL : msrt_alloc(text.len);
    if (copy != NULL) {
        MsBytesMut destination = ms_bytes_mut(copy, text.len);
        if (!ms_bytes_copy(destination, text)) {
            ms_string_internal_fault();
        }
    }
    *out = (MsVec){.ptr = copy, .len = text.len, .cap = text.len};
}

/* The pointer a list value holds for a read-only view: a list's pointer is mutable, but a view (`cap == 0`) is
 * never written or freed. */
static void *view_pointer(const uint8_t *bytes) {
    void *pointer = NULL;
    memcpy(&pointer, &bytes, sizeof pointer);
    return pointer;
}

/* `String.view_bytes`: the bytes of the text borrowed from the receiver, nothing copied (`cap == 0` marks a view,
 * which is never freed). The bytes of an inline text are the receiver's own storage, so the receiver must stay
 * alive and unchanged while the view is read. */
void msrt_string_view_bytes(const MsStr *s, MsVec *out) {
    MsBytes text = ms_str_bytes(s);
    *out = (MsVec){.ptr = text.len == 0 ? NULL : view_pointer(text.ptr), .len = text.len, .cap = 0};
}

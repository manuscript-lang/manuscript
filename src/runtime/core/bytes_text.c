/* Bytes that become text, and the string builder that appends to a Bytes buffer. Ported from crates/ms-rt/src/vec.rs.
 * A builder is a MsList of bytes; a view (cap == 0) borrows its storage and is never written. */
#include "list_ops.h"
#include "ms_rt/alloc.h"
#include "ms_rt/bytes.h"
#include "ms_rt/desc.h"
#include "ms_rt/fmt.h"
#include "ms_rt/strbuild.h"
#include "ms_rt/utf8.h"
#include "ms_rt/list.h"
#include "ms_rt/num.h"
#include "rt_calls.h"
#include "text.h"

/* ---- decoding ---- */

/* Whether the bytes are valid UTF-8; ASCII is the common case and has its own fast scan. */
static bool valid_text(MsBytes bytes) {
    return ms_bytes_ascii(bytes.ptr, bytes.len) || ms_utf8_is_valid(bytes.ptr, bytes.len);
}

/* `Bytes.decode_utf8()`: presence flag (0 when the bytes are not valid UTF-8), the string through `out`. */
uint8_t msrt_bytes_decode_utf8(const MsList *b, MsStr *out) {
    if (!valid_text(ms_bytes_of(b->ptr, b->len))) {
        return 0;
    }
    ms_str_write(ms_str_from_bytes(b->ptr, b->len), out);
    return 1;
}

/* `decode_utf8` of a `Bytes` that dies at the call: the string reuses the buffer instead of copying it, and an
 * invalid or short input frees it. */
uint8_t msrt_bytes_decode_utf8_take(MsList *b, MsStr *out) {
    const MsBytes bytes = ms_bytes_of(b->ptr, b->len);
    const bool ascii = ms_bytes_ascii(bytes.ptr, bytes.len);
    if (!ascii && !ms_utf8_is_valid(bytes.ptr, bytes.len)) {
        msrt_bytes_drop(b);
        return 0;
    }
    /* A view (`cap == 0`) borrows its bytes, so there is no buffer to reuse. */
    if (b->cap == 0 || b->len <= MS_STR_INLINE_MAX) {
        ms_str_write(ms_str_from_bytes(b->ptr, b->len), out);
        msrt_bytes_drop(b);
        return 1;
    }
    /* The string is the same allocation plus a NUL terminator. */
    uint8_t *const data = b->cap > b->len ? b->ptr : msrt_realloc(b->ptr, b->len + 1);
    const MsStr text = ms_str_owned(data, b->len);
    ms_str_write(ascii ? ms_str_with_ascii(text) : text, out);
    *b = (MsList){0};
    return 1;
}

/* `decode_utf8_range(start, end)`: `decode_utf8` over `[start, end)` without copying the range first. */
uint8_t msrt_bytes_decode_utf8_range(const MsList *b, int64_t start, int64_t end, MsStr *out) {
    if (start < 0 || end < start || (uint64_t)end > b->len) {
        MsText text = {0};
        ms_text_add(&text, "Bytes.decode_utf8_range: bounds ");
        ms_text_add_i64(&text, start);
        ms_text_add(&text, "..");
        ms_text_add_i64(&text, end);
        ms_text_add(&text, " are outside 0..");
        ms_text_add_i64(&text, (int64_t)b->len);
        ms_text_fault(&text, MS_FAULT_GENERIC);
    }
    const uint8_t *part = b->ptr + start;
    const size_t length = (size_t)(end - start);
    if (!valid_text(ms_bytes_of(part, length))) {
        return 0;
    }
    ms_str_write(ms_str_from_bytes(part, length), out);
    return 1;
}

/* ---- the string builder ---- */

/* Appends a string past the builder's spare room: grows, then copies. */
void msrt_strbuilder_append_slow(MsList *b, const MsStr *s) {
    const size_t n = ms_str_len(s);
    if (b->len + n > b->cap) {
        ms_list_reserve(b, &msrt_desc_bool, n);
    }
    if (n != 0) {
        __builtin_memcpy(b->ptr + b->len, ms_str_data(s), n);
    }
    b->len += n;
}

/* Appends a string to a builder. Text that fits the spare room is copied here (short text as overlapping moves);
 * a full buffer takes the slow path. */
void msrt_strbuilder_append(MsList *b, const MsStr *s) {
    const size_t n = ms_str_len(s);
    if (b->cap - b->len < n) {
        msrt_strbuilder_append_slow(b, s);
        return;
    }
    uint8_t *const dst = b->ptr + b->len;
    b->len += n;
    if (n == 1) {
        *dst = ms_str_data(s)[0];
    } else {
        ms_copy_bytes(dst, ms_str_data(s), n);
    }
}

/* Appends the decimal text of `n`: the bytes of appending `n.to_string()` without the temporary string. */
void msrt_strbuilder_append_int(MsList *b, int64_t n) {
    uint8_t digits[MS_FMT_INTEGER_CAPACITY];
    size_t length = 0;
    if (!msrt_fmt_i64(n, digits, sizeof digits, &length)) {
        return; /* unreachable: the capacity covers every Int */
    }
    if (b->len + length > b->cap) {
        ms_list_reserve(b, &msrt_desc_bool, length);
    }
    __builtin_memcpy(b->ptr + b->len, digits, length);
    b->len += length;
}

/* Builds the string and moves the builder: its buffer is freed or becomes the string. */
void msrt_strbuilder_freeze(MsList *b, MsStr *out) {
    /* A long text takes over the builder's buffer (NUL terminated, trimmed when much of it is spare). */
    if (b->len > MS_STR_INLINE_MAX && b->len <= MS_STR_MAX_BYTES && b->cap != 0) {
        uint8_t *data = b->ptr;
        if (b->cap == b->len || b->cap > b->len + (b->len >> 2) + 1) {
            data = msrt_heap_trim(data, b->len + 1);
        }
        const MsStr text = ms_str_owned(data, b->len);
        ms_str_write(ms_bytes_ascii(data, b->len) ? ms_str_with_ascii(text) : text, out);
        *b = (MsList){0};
        return;
    }
    ms_str_write(ms_str_from_bytes(b->ptr, b->len), out);
    msrt_bytes_drop(b);
}

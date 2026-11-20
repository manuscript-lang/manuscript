/* The growable UTF-8 buffer behind String.upper, lower and normalize (ucd.h). It owns one allocation, which grows
 * by doubling and is handed to the result string when the text is complete. */
#include "ms_rt/alloc.h"
#include "ms_rt/chars.h"
#include "ms_rt/strbuild.h"
#include "ucd.h"

void ms_utf8_out_init(MsUtf8Out *out, size_t capacity, size_t limit) {
    size_t bounded_limit = limit < MS_STR_MAX_BYTES ? limit : MS_STR_MAX_BYTES;
    size_t bounded_capacity = capacity < bounded_limit ? capacity : bounded_limit;
    size_t allocation = 0;
    if (!ms_size_add(bounded_capacity, 1, &allocation)) {
        ms_limit_fault();
    }
    out->ptr = msrt_alloc(allocation);
    out->len = 0;
    out->cap = bounded_capacity;
    out->limit = bounded_limit;
}

/* Makes room for `extra` more bytes; false when the text would pass the limit. */
MS_NODISCARD static bool reserve(MsUtf8Out *out, size_t extra) {
    size_t needed = 0;
    if (!ms_size_add(out->len, extra, &needed) || needed > out->limit) {
        return false;
    }
    if (needed <= out->cap) {
        return true;
    }
    size_t grown = out->cap > out->limit / 2 ? out->limit : out->cap * 2;
    if (grown < needed) {
        grown = needed;
    }
    out->ptr = msrt_realloc(out->ptr, grown + 1);
    out->cap = grown;
    return true;
}

bool ms_utf8_out_scalar(MsUtf8Out *out, uint32_t scalar) {
    if (out->cap - out->len >= 4) { /* room for any scalar: encode in place */
        out->len += ms_utf8_encode(scalar, out->ptr + out->len);
        return true;
    }
    uint8_t encoded[4];
    const size_t width = ms_utf8_encode(scalar, encoded);
    return ms_utf8_out_bytes(out, encoded, width);
}

bool ms_utf8_out_bytes(MsUtf8Out *out, const uint8_t *bytes, size_t count) {
    if (!reserve(out, count)) {
        return false;
    }
    __builtin_memcpy(out->ptr + out->len, bytes, count);
    out->len += count;
    return true;
}

void ms_utf8_out_free(MsUtf8Out *out) {
    msrt_free(out->ptr);
    out->ptr = NULL;
    out->len = 0;
    out->cap = 0;
}

MsStr ms_utf8_out_finish(MsUtf8Out *out) {
    MsStr text;
    if (out->len <= MS_STR_INLINE_MAX) {
        text = ms_str_from_bytes(out->ptr, out->len);
        msrt_free(out->ptr);
    } else {
        uint8_t *trimmed = msrt_heap_trim(out->ptr, out->len + 1);
        text = ms_str_owned(trimmed, out->len);
    }
    out->ptr = NULL;
    out->len = 0;
    out->cap = 0;
    return text;
}

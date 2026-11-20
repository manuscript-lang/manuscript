/* The text builder the formatters append to (`msrt_strbuf_*`): a growing byte block that becomes the result string
 * without a copy. Ported from crates/ms-rt/src/string.rs. */
#include "ms_rt/alloc.h"
#include "ms_rt/safe.h"
#include "ms_rt/strbuild.h"

/* The first block holds this many bytes (plus the terminator the finished string carries). */
#define MS_STRBUF_FIRST_CAPACITY 32

/* `bytes` has room for `capacity` text bytes and a terminating zero. */
struct MsStrBuf {
    uint8_t *bytes;
    size_t length;
    size_t capacity;
};

MsStrBuf *msrt_strbuf_new(void) {
    MsStrBuf *buffer = msrt_alloc(sizeof *buffer);
    *buffer = (MsStrBuf){.bytes = NULL, .length = 0, .capacity = 0};
    return buffer;
}

/* Grows the block to hold `needed` text bytes; at least doubles, so appending is linear overall. */
static void reserve(MsStrBuf *buffer, size_t needed) {
    size_t capacity = buffer->capacity == 0 ? MS_STRBUF_FIRST_CAPACITY : buffer->capacity;
    while (capacity < needed) {
        if (!ms_size_mul(capacity, 2, &capacity)) {
            ms_limit_fault();
        }
    }
    size_t block = 0;
    if (!ms_size_add(capacity, 1, &block)) {
        ms_limit_fault();
    }
    buffer->bytes = buffer->bytes == NULL ? msrt_alloc(block) : msrt_realloc(buffer->bytes, block);
    buffer->capacity = capacity;
}

void msrt_strbuf_push(MsStrBuf *buffer, const MsStr *s) {
    MsBytes text = ms_str_bytes(s);
    size_t needed = 0;
    if (!ms_size_add(buffer->length, text.len, &needed) || needed > MS_STR_MAX_BYTES) {
        ms_limit_fault();
    }
    if (needed > buffer->capacity) {
        reserve(buffer, needed);
    }
    MsBytesMut room = {0};
    if (!ms_bytes_mut_slice(ms_bytes_mut(buffer->bytes, buffer->capacity), buffer->length, buffer->capacity, &room) ||
        !ms_bytes_copy(room, text)) {
        ms_limit_fault();
    }
    buffer->length = needed;
}

/* The result of an empty or short buffer: a static or inline string, and the block is released. */
static MsStr small_result(MsStrBuf *buffer) {
    MsStr result = buffer->length == 0 ? ms_str_empty() : ms_str_from_bytes(buffer->bytes, buffer->length);
    if (buffer->bytes != NULL) {
        msrt_free(buffer->bytes);
    }
    return result;
}

void msrt_strbuf_finish(MsStrBuf *buffer, MsStr *out) {
    if (buffer->length <= MS_STR_INLINE_MAX) {
        *out = small_result(buffer);
        msrt_free(buffer);
        return;
    }
    /* A buffer far larger than its text gives the slack back; the block then is the string. */
    if (buffer->capacity / 2 > buffer->length) {
        buffer->bytes = msrt_realloc(buffer->bytes, buffer->length + 1);
    }
    MsStr result = ms_str_owned(buffer->bytes, buffer->length);
    *out = ms_bytes_ascii(buffer->bytes, buffer->length) ? ms_str_with_ascii(result) : result;
    msrt_free(buffer);
}

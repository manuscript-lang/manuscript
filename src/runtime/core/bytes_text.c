/* runtime/core/bytes_text.c: Bytes that become text, and the string builder that appends to a byte buffer. A
 * builder is a byte list; a view (cap == 0) borrows its storage and is never written. */
#include "runtime/core/bytes.h"

#include "base/alloc.h"
#include "base/fmt.h"
#include "base/strbuild.h"
#include "base/utf8.h"
#include "runtime/core/fault.h"
#include "runtime/core/string_support.h"

/* ---- decoding ---- */

/* `Bytes.decode_utf8()`: presence flag (0 when the bytes are not valid UTF-8), the string through `out`. */
uint8_t msrt_bytes_decode_utf8(const MsBytes *b, MsString *out) {
  if (!ms_utf8_is_valid(b->ptr, b->len)) {
    return 0;
  }
  *out = msrt_string_make(ms_bytes_span(b));
  return 1;
}

/* `decode_utf8` of a `Bytes` that dies at the call: the string reuses the buffer instead of copying it, and
 * an invalid or short input frees it. */
uint8_t msrt_bytes_decode_utf8_take(MsBytes *b, MsString *out) {
  if (!ms_utf8_is_valid(b->ptr, b->len)) {
    ms_bytes_free(b);
    return 0;
  }
  /* A view (`cap == 0`) borrows its bytes, so there is no buffer to reuse. */
  if (b->cap == 0 || b->len <= MS_STRING_INLINE_MAX) {
    *out = msrt_string_make(ms_bytes_span(b));
    ms_bytes_free(b);
    return 1;
  }
  *out = msrt_string_from_block(b->ptr, b->len);
  *b = (MsBytes){0};
  return 1;
}

/* `decode_utf8_range(start, end)`: `decode_utf8` over `[start, end)` without copying the range first. */
uint8_t msrt_bytes_decode_utf8_range(const MsBytes *b, int64_t start, int64_t end, MsString *out) {
  if (start < 0 || end < start || (uint64_t)end > b->len) {
    MsStrBuild message = ms_strbuild_new();
    ms_strbuild_append_text(&message, "Bytes.decode_utf8_range: bounds ");
    ms_strbuild_append_i64(&message, start);
    ms_strbuild_append_text(&message, "..");
    ms_strbuild_append_i64(&message, end);
    ms_strbuild_append_text(&message, " are outside 0..");
    ms_strbuild_append_i64(&message, (int64_t)b->len);
    ms_fault_built(MS_FAULT_KIND_FAULT, &message);
  }
  const MsSpan part = ms_span_of(b->ptr + start, (size_t)(end - start));
  if (!ms_utf8_is_valid(part.ptr, part.len)) {
    return 0;
  }
  *out = msrt_string_make(part);
  return 1;
}

/* ---- the string builder ---- */

/* Appends a string past the builder's spare room: grows, then copies. */
void msrt_strbuilder_append_slow(MsBytes *b, const MsString *s) {
  const MsSpan text = msrt_text(s);
  if (text.len != 0) {
    __builtin_memcpy(ms_list_extend(b, 1, text.len), text.ptr, text.len);
  }
}

/* Appends a string to a builder. Text that fits the spare room is copied here; a full buffer takes the slow
 * path. */
void msrt_strbuilder_append(MsBytes *b, const MsString *s) {
  const MsSpan text = msrt_text(s);
  if (b->cap - b->len < text.len) {
    msrt_strbuilder_append_slow(b, s);
    return;
  }
  uint8_t *const destination = b->ptr + b->len;
  b->len += text.len;
  if (text.len == 1) {
    *destination = text.ptr[0];
  } else if (text.len != 0) {
    __builtin_memcpy(destination, text.ptr, text.len);
  }
}

/* Appends the decimal text of `n`: the bytes of appending `n.to_string()` without the temporary string. */
void msrt_strbuilder_append_int(MsBytes *b, int64_t n) {
  uint8_t digits[MS_FMT_INTEGER_CAPACITY];
  const size_t length = ms_fmt_i64_fixed(n, digits);
  __builtin_memcpy(ms_list_extend(b, 1, length), digits, length);
}

/* Builds the string and moves the builder: its buffer is freed or becomes the string. */
void msrt_strbuilder_freeze(MsBytes *b, MsString *out) {
  if (b->len > MS_STRING_INLINE_MAX && b->len < MSRT_STRING_LIMIT && b->cap != 0) {
    uint8_t *data = b->ptr;
    if (b->cap > b->len + (b->len >> 2) + 1) { /* trim a buffer that is mostly spare */
      data = ms_realloc(data, b->len);
    }
    *out = msrt_string_from_block(data, b->len);
    *b = (MsBytes){0};
    return;
  }
  *out = msrt_string_make(ms_bytes_span(b));
  ms_bytes_free(b);
}

/* `StringBuilder.drain()`: the text so far, leaving the builder empty and usable. */
void msrt_strbuilder_drain(MsBytes *b, MsString *out) {
  msrt_strbuilder_freeze(b, out);
  *b = (MsBytes){0};
}

/* `BytesBuilder.build()` and `drain()`: the buffer moves into the result, leaving the builder empty. */
void msrt_bytesbuilder_build(MsBytes *b, MsBytes *out) {
  *out = *b;
  *b = (MsBytes){0};
}

void msrt_bytesbuilder_drain(MsBytes *b, MsBytes *out) { msrt_bytesbuilder_build(b, out); }

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
    ms_fault_post_built(MS_FAULT_KIND_FAULT, &message);
    return 0;
  }
  const MsSpan part = ms_span_of(b->ptr + start, (size_t)(end - start));
  if (!ms_utf8_is_valid(part.ptr, part.len)) {
    return 0;
  }
  *out = msrt_string_make(part);
  return 1;
}

/* `BytesBuilder.build()` and `drain()`: the buffer moves into the result, leaving the builder empty. */
void msrt_bytesbuilder_build(MsBytes *b, MsBytes *out) {
  *out = *b;
  *b = (MsBytes){0};
}

void msrt_bytesbuilder_drain(MsBytes *b, MsBytes *out) { msrt_bytesbuilder_build(b, out); }

/* Owns Bytes construction (see bytes.h). */
#include "base/alloc.h"
#include "base/bytes.h"

MsBytes ms_bytes_from_span(MsSpan span) {
  MsBytes bytes = {0};
  if (span.len != 0) { /* an exact fit: a copy is not grown by doubling */
    bytes.ptr = ms_alloc(span.len);
    bytes.len = span.len;
    bytes.cap = span.len;
    __builtin_memcpy(bytes.ptr, span.ptr, span.len);
  }
  return bytes;
}

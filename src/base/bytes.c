/* Owns Bytes construction (see bytes.h). */
#include "base/bytes.h"

MsBytes ms_bytes_from_span(MsSpan span) {
  MsBytes bytes = {0};
  if (span.len != 0) {
    __builtin_memcpy(ms_list_extend(&bytes, 1, span.len), span.ptr, span.len);
  }
  return bytes;
}

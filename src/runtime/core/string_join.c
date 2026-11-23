/* runtime/core/string_join.c: the primitives behind f-strings (string_join.h). The compiler writes out the rest. */
#include "base/alloc.h"
#include "base/fmt.h"
#include "runtime/core/string.h"
#include "runtime/core/string_join.h"
#include "runtime/core/string_support.h"

uint8_t *msrt_string_open(size_t total, MsString *out) {
  if (total > MS_STRING_INLINE_MAX) {
    return msrt_string_block(total, out);
  }
  *out = ms_string_empty(); /* an inline string is filled in place: its bytes past the length stay zero */
  out->tagged |= (uint64_t)total << MS_STRING_INLINE_SHIFT;
  return out->inline_bytes;
}

void msrt_string_close(MsJoinFrame *frame) {
  if (frame->pending != NULL) {
    ms_free(frame->pending);
  }
}

size_t msrt_int_format(int64_t v, uint8_t *buffer) {
  return ms_fmt_i64_fixed(v, buffer);
}

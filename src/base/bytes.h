/* base/bytes.h: MsBytes, the owned byte buffer of Manuscript programs (the Bytes type).
 *
 * Same layout as every list: `{ptr, len, cap}`. It owns its buffer; a view has cap 0 with a ptr and
 * borrows. Borrowed reads go through MsSpan (base/safe.h). An empty buffer has a null ptr. */
#ifndef MS_BASE_BYTES_H
#define MS_BASE_BYTES_H

#include "base/list.h"

typedef MsList MsBytes;

/* A new buffer holding a copy of `span`; an empty span gives the empty buffer. */
MsBytes ms_bytes_from_span(MsSpan span);

/* The bytes of the buffer, valid until it changes or is freed. */
static inline MsSpan ms_bytes_span(const MsBytes *bytes) {
  return ms_span_of(bytes->ptr, bytes->len);
}

static inline MsBytes ms_bytes_view(MsSpan span) {
  return (MsBytes){.ptr = (uint8_t *)(uintptr_t)span.ptr, .len = span.len, .cap = 0};
}

static inline void ms_bytes_free(MsBytes *bytes) {
  ms_list_free(bytes);
}

#endif

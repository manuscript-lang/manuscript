/* runtime/core/string_join.h: the small primitives an f-string is built from. Lowering writes out the join itself
 * (mir_expand.c): it adds up the lengths of the parts, makes or grows the string once through these, and copies each
 * part. */
#ifndef MS_RUNTIME_CORE_STRING_JOIN_H
#define MS_RUNTIME_CORE_STRING_JOIN_H

#include "base/string.h"

/* The frame an append works in: the string being grown and the block it moved out of, which stays allocated until
 * `msrt_string_close` so a part that was a view into the old text can still be copied. */
typedef struct MsJoinFrame {
  MsString text;
  uint8_t *pending;
} MsJoinFrame;

/* Makes `*out` a string of `total` bytes, inline when it fits, and returns the address of its bytes to fill. */
uint8_t *msrt_string_open(size_t total, MsString *out);
/* Grows the string in `frame->text` by `extra` bytes (in place when it owns room for them, else into a new block with
 * spare room) and returns the address of the new bytes. */
uint8_t *msrt_string_extend(MsJoinFrame *frame, size_t extra);
/* Releases the block `msrt_string_extend` left behind. */
void msrt_string_close(MsJoinFrame *frame);
/* Writes `v` in decimal to `buffer` (at least 20 bytes) and returns its length. */
size_t msrt_int_format(int64_t v, uint8_t *buffer);

#endif

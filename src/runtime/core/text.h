/* text.h: a small fixed-size text buffer for fault and error messages, since src/runtime/core has no printf.
 * Text that does not fit is cut at the end; every message built here is far shorter than the buffer.
 */
#ifndef MS_TEXT_H
#define MS_TEXT_H

#include "ms_rt/safe.h"
#include "ms_rt/desc.h"
#include "rt_calls.h"

#define MS_TEXT_CAPACITY 384

typedef struct MsText {
    char bytes[MS_TEXT_CAPACITY];
    size_t len;
} MsText;

/* Appends a NUL-terminated literal. */
MS_NONNULL void ms_text_add(MsText *text, const char *literal);

/* Appends the decimal digits of `value`, with a minus sign when negative. */
MS_NONNULL void ms_text_add_i64(MsText *text, int64_t value);

/* Raises a fault of `kind` whose message is the text. */
MS_NONNULL MS_NORETURN void ms_text_fault(const MsText *text, MsFaultKind kind);

/* Writes the text as a string value to `out`. */
MS_NONNULL void ms_text_to_string(const MsText *text, MsStr *out);

#endif

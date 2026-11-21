/* runtime/core/string_support.h: what the string natives share. Every native that makes a string uses these
 * constructors, so the rules of a result are written once: an empty result and a one-character ASCII result
 * are static, up to 15 bytes are inline, anything longer is one owned allocation, and a view never points
 * into an inline string (it would point into a local copy). Strings past MSRT_STRING_LIMIT bytes fault. */
#ifndef MS_RUNTIME_CORE_STRING_SUPPORT_H
#define MS_RUNTIME_CORE_STRING_SUPPORT_H

#include "base/list.h"
#include "base/string.h"

#define MSRT_STRING_LIMIT ((size_t)1 << 30)

/* The one-byte ASCII strings, two bytes per entry (the byte and a zero). Generated code reads it by name. */
extern const uint8_t msrt_ascii_chars[128][2];

/* A growable list of strings (the layout of every List[String]). */
MS_LIST_DEFINE(MsStringList, ms_string_list, MsString)

/* Raises the fault "string: limit exceeded". */
MS_NORETURN void msrt_string_limit_fault(void);

/* a + b, faulting past the string limit. */
size_t msrt_string_total(size_t a, size_t b);

/* A new string holding a copy of `text`. */
MsString msrt_string_make(MsSpan text);

/* The bytes of a live string as a string: an inline copy when they fit, otherwise a view that borrows them.
 */
MsString msrt_string_view_of(MsSpan text);

/* The parts joined with one allocation (inline when they fit). */
MsString msrt_string_join(const MsSpan *parts, size_t count);

/* `a` and then the parts (at most 6), taking `a`: an owned `a` grows in place. */
MsString msrt_string_append_parts(const MsString *a, const MsSpan *parts, size_t count);

/* An owned string of `length` bytes, more than 15; returns the writable bytes, which the caller fills. */
uint8_t *msrt_string_block(size_t length, MsString *out);

/* The string made of the first `length` bytes of `block`, an allocation of ms_alloc whose ownership passes
 * here: kept as the owned string when long, copied and freed when it fits inline. */
MsString msrt_string_from_block(uint8_t *block, size_t length);

/* Whether the string owns an allocation. */
static inline bool msrt_string_owns(const MsString *string) {
  return (string->tagged >> MS_STRING_TAG_SHIFT) == 0;
}

/* The string as a span, for the natives' `*const StrVal` arguments. */
static inline MsSpan msrt_text(const MsString *string) {
  return ms_string_span(string);
}

#endif

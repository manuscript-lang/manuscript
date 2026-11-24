/* base/string.h: MsString, the string value of Manuscript programs, used by the compiler and tools too.
 *
 * Layout is the program ABI: two words. The top two bits of the second word say what the first word and
 * the rest are: 00 owned (first word is the allocation, bits 0..30 the length), 01 inline (the bytes are the
 * value, up to 15, length in bits 56..59), 10 static and 11 view (first word points at borrowed bytes).
 * Inline strings keep the bytes past their length zero. Strings of 2^31 bytes or more are not representable
 * and report MS_FATAL_OUT_OF_RANGE.
 *
 * Ownership: an owned string belongs to whoever holds the value and ends with ms_string_release. A static
 * string points at bytes that live forever; a view points at bytes the creator keeps alive. Copying an
 * MsString struct copies the ownership claim; use ms_string_clone for a second owner. */
#ifndef MS_BASE_STRING_H
#define MS_BASE_STRING_H

#include "base/hash.h"
#include "base/safe.h"

typedef struct MsString {
  union {
    struct {
      union {
        uint8_t *owned;        /* owned: the allocation, freed with ms_free */
        const uint8_t *borrow; /* static or view */
        uint64_t low_bits;
      };
      uint64_t tagged;
    };
    uint8_t inline_bytes[16];
  };
} MsString;

_Static_assert(sizeof(MsString) == 16, "a string value is two words");
_Static_assert(__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__, "inline strings assume a little-endian host");

#define MS_STRING_TAG_SHIFT 62
#define MS_STRING_INLINE_SHIFT 56
#define MS_STRING_INLINE_MAX 15
#define MS_STRING_LENGTH_MASK ((UINT64_C(1) << 31) - 1)
#define MS_STRING_MAX_LENGTH ((size_t)MS_STRING_LENGTH_MASK)

/* The empty string (an inline string of length 0; all zero bits). */
static inline MsString ms_string_empty(void) {
  return (MsString){.low_bits = 0, .tagged = UINT64_C(1) << MS_STRING_TAG_SHIFT};
}

/* An inline string holding the `span.len <= MS_STRING_INLINE_MAX` bytes of `span`. The bytes go into the two words
 * from overlapping loads, so there is no copy of a variable length. */
static inline MsString ms_string_make_inline(MsSpan span) {
  uint64_t low, high;
  ms_hash_words(span.ptr, span.len, &low, &high);
  return (MsString){.low_bits = low,
                    .tagged = high | ((uint64_t)span.len << MS_STRING_INLINE_SHIFT) | (UINT64_C(1) << MS_STRING_TAG_SHIFT)};
}

/* A new string holding a copy of `span`: inline when short, else an owned allocation. */
MsString ms_string_from_span(MsSpan span);

/* A string over bytes that live forever (a literal); never copies or frees. */
MsString ms_string_static(MsSpan span);

/* A string over bytes the caller keeps alive and unchanged for as long as the view is used. */
MsString ms_string_view(MsSpan span);

/* A second owner: a copy of `string`'s bytes (inline strings are copied by value). */
MsString ms_string_clone(const MsString *string);

/* Frees an owned string and leaves `string` empty; other strings own nothing. */
void ms_string_release(MsString *string);

static inline bool ms_string_is_inline(const MsString *string) {
  return (string->tagged >> MS_STRING_TAG_SHIFT) == 1;
}

static inline size_t ms_string_length(const MsString *string) {
  return ms_string_is_inline(string) ? (size_t)((string->tagged >> MS_STRING_INLINE_SHIFT) & 15)
                                     : (size_t)(string->tagged & MS_STRING_LENGTH_MASK);
}

/* The bytes of the string, valid while `string` is alive and not released. */
static inline MsSpan ms_string_span(const MsString *string) {
  const uint8_t *bytes = ms_string_is_inline(string) ? string->inline_bytes : string->borrow;
  return ms_span_of(bytes, ms_string_length(string));
}

static inline bool ms_string_is_empty(const MsString *string) {
  return ms_string_length(string) == 0;
}

bool ms_string_equal(const MsString *a, const MsString *b);

/* -1, 0 or 1: byte order, a shorter prefix first. */
int ms_string_compare(const MsString *a, const MsString *b);

uint64_t ms_string_hash(const MsString *string);

#endif

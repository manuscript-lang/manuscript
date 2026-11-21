/* runtime/core/string_query.c: the natives that read a string and allocate nothing: comparison, hashing,
 * length, prefix and suffix tests, search and scalar access. */
#include "base/chars.h"
#include "base/search.h"
#include "base/utf8.h"
#include "runtime/core/string.h"
#include "runtime/core/string_support.h"

int64_t msrt_string_hash(const MsString *s) {
  return (int64_t)ms_string_hash(s);
}

uint8_t msrt_string_eq(const MsString *a, const MsString *b) {
  return ms_string_equal(a, b);
}

int64_t msrt_string_compare(const MsString *a, const MsString *b) {
  return ms_string_compare(a, b);
}

uint8_t msrt_string_is_empty(const MsString *s) {
  return ms_string_is_empty(s);
}

int64_t msrt_string_length(const MsString *s) {
  return (int64_t)ms_string_length(s);
}

uint8_t msrt_string_starts_with(const MsString *a, const MsString *v) {
  return ms_span_starts_with(msrt_text(a), msrt_text(v));
}

uint8_t msrt_string_ends_with(const MsString *a, const MsString *v) {
  return ms_span_ends_with(msrt_text(a), msrt_text(v));
}

/* ---- scalars ---- */

int64_t msrt_string_scalar_length(const MsString *s) {
  const MsSpan text = msrt_text(s);
  return (int64_t)ms_utf8_count(text.ptr, text.len);
}

/* The scalar that starts at byte `at`; an offset outside the string reads as an invalid byte. */
static MsRune rune_at(const MsString *s, int64_t at) {
  const MsSpan text = msrt_text(s);
  if (at < 0 || (uint64_t)at >= text.len) {
    return (MsRune){MS_RUNE_ERROR, 1};
  }
  return ms_utf8_decode(text.ptr + at, text.len - (size_t)at);
}

/* Byte width of the character that starts at byte `at`. */
int64_t msrt_string_char_width(const MsString *s, int64_t at) {
  return rune_at(s, at).width;
}

/* The scalar value and byte width of the character at byte `at` in one decode, as scalar << 3 | width. */
int64_t msrt_string_scalar_step(const MsString *s, int64_t at) {
  const MsRune rune = rune_at(s, at);
  return (int64_t)(((uint64_t)rune.rune << 3) | rune.width);
}

int64_t msrt_string_scalar_at_byte(const MsString *s, int64_t at) {
  return rune_at(s, at).rune;
}

/* ---- search ---- */

uint8_t msrt_string_contains(const MsString *a, const MsString *v) {
  const MsSpan text = msrt_text(a);
  const MsSpan needle = msrt_text(v);
  return ms_find(text.ptr, text.len, needle.ptr, needle.len) != SIZE_MAX;
}

/* contains where the caller knows the needle has two or more bytes (a literal). */
uint8_t msrt_string_contains_multi(const MsString *a, const MsString *v) {
  return msrt_string_contains(a, v);
}

/* Non-overlapping occurrences of v in a; an empty v counts the scalars plus one. */
int64_t msrt_string_count(const MsString *a, const MsString *v) {
  const MsSpan text = msrt_text(a);
  const MsSpan needle = msrt_text(v);
  if (needle.len == 0) {
    return msrt_string_scalar_length(a) + 1;
  }
  return (int64_t)ms_count(text.ptr, text.len, needle.ptr, needle.len);
}

uint8_t msrt_string_index_of(const MsString *a, const MsString *v, int64_t *out) {
  const MsSpan text = msrt_text(a);
  const MsSpan needle = msrt_text(v);
  const size_t found = ms_find(text.ptr, text.len, needle.ptr, needle.len);
  if (found == SIZE_MAX) {
    return 0;
  }
  *out = (int64_t)found;
  return 1;
}

uint8_t msrt_string_last_index_of(const MsString *a, const MsString *v, int64_t *out) {
  const MsSpan text = msrt_text(a);
  const MsSpan needle = msrt_text(v);
  const size_t found = ms_rfind(text.ptr, text.len, needle.ptr, needle.len);
  if (found == SIZE_MAX) {
    return 0;
  }
  *out = (int64_t)found;
  return 1;
}

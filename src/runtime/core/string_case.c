/* runtime/core/string_case.c: String.upper and String.lower. ASCII text maps eight bytes at a time, other
 * text scalar by scalar through the case tables (ucd.h), with the full mappings of SpecialCasing (`ß` to
 * `SS`) and the final-sigma rule of lowercasing. A result is never shared with its input. */
#include "base/alloc.h"
#include "base/chars.h"
#include "base/strbuild.h"
#include "base/utf8.h"
#include "runtime/core/string.h"
#include "runtime/core/string_text.h"
#include "runtime/core/string_support.h"
#include "runtime/core/ucd.h"

#define SIGMA 0x3A3u

/* The high bit of each byte of `word` (all below 0x80) that is a letter to flip: a lowercase one when mapping
 * to upper case, an uppercase one otherwise. Adding (0x80 - first) sets a byte's high bit when it is at least
 * `first`, and adding (0x80 - last - 1) when it is above `last`; no byte carries into the next. */
static uint64_t letters_to_flip(uint64_t word, bool to_upper) {
  const uint64_t ones = UINT64_C(0x0101010101010101);
  const uint64_t high = UINT64_C(0x8080808080808080);
  const uint8_t first = to_upper ? 'a' : 'A';
  const uint8_t last = to_upper ? 'z' : 'Z';
  const uint64_t at_least = word + ones * (uint64_t)(0x80 - first);
  const uint64_t above = word + ones * (uint64_t)(0x80 - last - 1);
  return at_least & ~above & high;
}

static uint64_t flipped_word(uint64_t word, bool to_upper) {
  return word ^ (letters_to_flip(word, to_upper) >> 2);
}

/* The first eight bytes of the n bytes at p, or all of them zero padded when there are fewer. */
static uint64_t first_word(const uint8_t *p, size_t n) {
  uint64_t word = 0;
  __builtin_memcpy(&word, p, n < 8 ? n : 8);
  return word;
}

/* Whether the ASCII bytes hold a letter that the mapping changes, eight bytes per step. */
static bool has_letter_to_flip(MsSpan text, bool to_upper) {
  if (text.len < 8) {
    return letters_to_flip(first_word(text.ptr, text.len), to_upper) != 0;
  }
  for (size_t at = 0; at + 8 <= text.len; at += 8) {
    if (letters_to_flip(ms_load64(text.ptr + at), to_upper) != 0) {
      return true;
    }
  }
  return letters_to_flip(ms_load64(text.ptr + text.len - 8), to_upper) != 0;
}

/* Writes the mapped ASCII bytes to `dst` (`src` and `dst` may be the same bytes). */
static void flip_ascii_into(uint8_t *dst, const uint8_t *src, size_t length, bool to_upper) {
  if (length < 8) {
    const uint64_t word = flipped_word(first_word(src, length), to_upper);
    __builtin_memcpy(dst, &word, length);
    return;
  }
  const uint64_t tail = flipped_word(ms_load64(src + length - 8), to_upper);
  for (size_t at = 0; at + 8 <= length; at += 8) {
    const uint64_t word = flipped_word(ms_load64(src + at), to_upper);
    __builtin_memcpy(dst + at, &word, 8);
  }
  __builtin_memcpy(dst + length - 8, &tail, 8);
}

static MsString map_ascii(const MsString *s, bool to_upper) {
  const MsSpan text = msrt_text(s);
  if (!has_letter_to_flip(text, to_upper)) {
    return ms_string_clone(s); /* already in the requested case */
  }
  uint8_t small[MS_STRING_INLINE_MAX + 1];
  MsString result = ms_string_empty();
  uint8_t *destination = text.len <= MS_STRING_INLINE_MAX ? small : msrt_string_block(text.len, &result);
  flip_ascii_into(destination, text.ptr, text.len, to_upper);
  return text.len <= MS_STRING_INLINE_MAX ? msrt_string_make(ms_span_of(small, text.len)) : result;
}

/* ---- scalar mapping ---- */

/* Whether the Cased scalar, past any Case_Ignorable ones, ends (backward) the first `end` bytes. */
static bool cased_before(MsSpan text, size_t end) {
  while (end > 0) {
    const MsRune scalar = ms_utf8_decode_last(text.ptr, end);
    end -= scalar.width;
    const int32_t flags = ms_ucd_case_of(scalar.rune)[2];
    if ((flags & MS_UCD_CASE_IGNORABLE) == 0) {
      return (flags & MS_UCD_CASED) != 0;
    }
  }
  return false;
}

/* The same, forward from byte `start`. */
static bool cased_after(MsSpan text, size_t start) {
  while (start < text.len) {
    const MsRune scalar = ms_utf8_decode(text.ptr + start, text.len - start);
    start += scalar.width;
    const int32_t flags = ms_ucd_case_of(scalar.rune)[2];
    if ((flags & MS_UCD_CASE_IGNORABLE) == 0) {
      return (flags & MS_UCD_CASED) != 0;
    }
  }
  return false;
}

/* Capital sigma lowercases to the final form when a cased letter precedes it and none follows (case-ignorable
 * scalars aside). */
static uint32_t lower_sigma(MsSpan text, size_t at) {
  const bool final_form = cased_before(text, at) && !cased_after(text, at + 2);
  return final_form ? 0x3C2u : 0x3C3u;
}

/* Appends the mapping of one non-ASCII scalar. */
static void put_mapped(MsStrBuild *out, uint32_t scalar, int32_t field) {
  if (field < MS_UCD_CASE_SPECIAL) {
    ms_strbuild_append_utf8(out, (uint32_t)((int32_t)scalar + field));
    return;
  }
  const uint32_t count = ((uint32_t)field >> 16) & 0x3FFFu;
  const uint32_t offset = (uint32_t)field & 0xFFFFu;
  for (uint32_t index = 0; index < count; index++) {
    ms_strbuild_append_utf8(out, ms_ucd_case_pool[offset + index]);
  }
}

/* Appends the mapping of the non-ASCII scalar at `at`. */
static void map_scalar(MsStrBuild *out, MsSpan text, size_t at, MsRune scalar, bool to_upper) {
  const int32_t field = ms_ucd_case_of(scalar.rune)[to_upper ? 1 : 0];
  if (!to_upper && scalar.rune == SIGMA) {
    ms_strbuild_append_utf8(out, lower_sigma(text, at));
  } else if (field == 0) {
    ms_strbuild_append(out, ms_span_of(text.ptr + at, scalar.width));
  } else {
    put_mapped(out, scalar.rune, field);
  }
}

static MsString map_text(const MsString *s, bool to_upper) {
  const MsSpan text = msrt_text(s);
  MsStrBuild out = ms_strbuild_new();
  for (size_t at = 0; at < text.len;) {
    if (ms_strbuild_length(&out) > MSRT_STRING_LIMIT) {
      ms_strbuild_free(&out);
      msrt_string_limit_fault();
    }
    const uint8_t byte = text.ptr[at];
    if (byte < 0x80) {
      ms_strbuild_append_byte(&out, to_upper ? ms_ascii_to_upper(byte) : ms_ascii_to_lower(byte));
      at++;
      continue;
    }
    const MsRune scalar = ms_utf8_decode_multi(text.ptr + at, text.len - at);
    map_scalar(&out, text, at, scalar, to_upper);
    at += scalar.width;
  }
  const MsString result = msrt_string_make(ms_strbuild_span(&out));
  ms_strbuild_free(&out);
  return result;
}

static MsString map_case(const MsString *s, bool to_upper) {
  const MsSpan text = msrt_text(s);
  return ms_utf8_is_ascii(text.ptr, text.len) ? map_ascii(s, to_upper) : map_text(s, to_upper);
}

/* The string that dies at the call: owned ASCII text maps in place, anything else maps as above and is
 * released. */
static void map_case_take(MsString *s, bool to_upper, MsString *out) {
  const MsSpan text = msrt_text(s);
  if (msrt_string_owns(s) && ms_utf8_is_ascii(text.ptr, text.len)) {
    flip_ascii_into(s->owned, text.ptr, text.len, to_upper);
    *out = *s;
    return;
  }
  *out = map_case(s, to_upper);
  msrt_string_free(s);
}

void msrt_string_upper(const MsString *s, MsString *out) {
  *out = map_case(s, true);
}

void msrt_string_lower(const MsString *s, MsString *out) {
  *out = map_case(s, false);
}

void msrt_string_upper_take(MsString *s, MsString *out) {
  map_case_take(s, true, out);
}

void msrt_string_lower_take(MsString *s, MsString *out) {
  map_case_take(s, false, out);
}

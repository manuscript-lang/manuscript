/* base/chars.h: byte-level text helpers: ASCII classification and case, hex digits and UTF-8 encoding and
 * decoding of well-formed text. Header-only, stateless and locale-free, so every platform agrees (unlike
 * <ctype.h>). Validating decode and counting live in base/utf8.h. */
#ifndef MS_BASE_CHARS_H
#define MS_BASE_CHARS_H

#include "base/safe.h"

/* ---- ASCII ---- */

static inline bool ms_ascii_is_digit(uint8_t b) {
  return b >= '0' && b <= '9';
}
static inline bool ms_ascii_is_upper(uint8_t b) {
  return b >= 'A' && b <= 'Z';
}
static inline bool ms_ascii_is_lower(uint8_t b) {
  return b >= 'a' && b <= 'z';
}
static inline bool ms_ascii_is_alpha(uint8_t b) {
  return ms_ascii_is_upper(b) || ms_ascii_is_lower(b);
}
static inline bool ms_ascii_is_alnum(uint8_t b) {
  return ms_ascii_is_alpha(b) || ms_ascii_is_digit(b);
}
/* An ASCII letter or an underscore: the first byte of an identifier. */
static inline bool ms_ascii_is_ident_start(uint8_t b) {
  return ms_ascii_is_alpha(b) || b == '_';
}
/* An ASCII letter, digit or underscore: any byte of an identifier. */
static inline bool ms_ascii_is_ident(uint8_t b) {
  return ms_ascii_is_alnum(b) || b == '_';
}
/* Blank as C's isspace in the C locale: space, \t, \n, \v, \f, \r. */
static inline bool ms_ascii_is_space(uint8_t b) {
  return b == ' ' || (b >= '\t' && b <= '\r');
}
/* `s` without leading and trailing ASCII whitespace. */
static inline MsSpan ms_span_trim(MsSpan s) {
  while (s.len > 0 && ms_ascii_is_space(s.ptr[0])) {
    s = ms_span_of(s.ptr + 1, s.len - 1);
  }
  while (s.len > 0 && ms_ascii_is_space(s.ptr[s.len - 1])) {
    s.len--;
  }
  return s;
}
static inline bool ms_ascii_is_hex(uint8_t b) {
  return ms_ascii_is_digit(b) || (b >= 'a' && b <= 'f') || (b >= 'A' && b <= 'F');
}

static inline uint8_t ms_ascii_to_lower(uint8_t b) {
  return ms_ascii_is_upper(b) ? (uint8_t)(b + ('a' - 'A')) : b;
}
static inline uint8_t ms_ascii_to_upper(uint8_t b) {
  return ms_ascii_is_lower(b) ? (uint8_t)(b - ('a' - 'A')) : b;
}

/* Whether `span` equals the C text when ASCII case is ignored. */
static inline bool ms_ascii_is_text_fold(MsSpan span, const char *text);

/* Whether the two spans are equal when ASCII case is ignored. */
static inline bool ms_ascii_equal_fold(MsSpan a, MsSpan b) {
  if (a.len != b.len) {
    return false;
  }
  for (size_t i = 0; i < a.len; i++) {
    if (ms_ascii_to_lower(a.ptr[i]) != ms_ascii_to_lower(b.ptr[i])) {
      return false;
    }
  }
  return true;
}

static inline bool ms_ascii_is_text_fold(MsSpan span, const char *text) {
  return ms_ascii_equal_fold(span, ms_span_of_text(text));
}

/* The value 0..15 of a hex digit (either case). False, leaving `value` untouched, for any other byte. */
MS_NODISCARD static inline bool ms_hex_digit_value(uint8_t b, uint32_t *value) {
  if (ms_ascii_is_digit(b)) {
    *value = (uint32_t)(b - '0');
  } else if (b >= 'a' && b <= 'f') {
    *value = (uint32_t)(b - 'a') + 10;
  } else if (b >= 'A' && b <= 'F') {
    *value = (uint32_t)(b - 'A') + 10;
  } else {
    return false;
  }
  return true;
}

/* ---- UTF-8 ---- */

/* Whether the byte is a continuation byte (10xxxxxx), not the first byte of a scalar. */
static inline bool ms_utf8_is_continuation(uint8_t b) {
  return (b & 0xC0u) == 0x80u;
}

/* Writes the UTF-8 encoding of a scalar (up to 0x10FFFF) to `out` and returns its width, 1 to 4. */
static inline size_t ms_utf8_encode(uint32_t scalar, uint8_t out[4]) {
  if (scalar < 0x80) {
    out[0] = (uint8_t)scalar;
    return 1;
  }
  if (scalar < 0x800) {
    out[0] = (uint8_t)(0xC0u | (scalar >> 6));
    out[1] = (uint8_t)(0x80u | (scalar & 0x3Fu));
    return 2;
  }
  if (scalar < 0x10000) {
    out[0] = (uint8_t)(0xE0u | (scalar >> 12));
    out[1] = (uint8_t)(0x80u | ((scalar >> 6) & 0x3Fu));
    out[2] = (uint8_t)(0x80u | (scalar & 0x3Fu));
    return 3;
  }
  out[0] = (uint8_t)(0xF0u | (scalar >> 18));
  out[1] = (uint8_t)(0x80u | ((scalar >> 12) & 0x3Fu));
  out[2] = (uint8_t)(0x80u | ((scalar >> 6) & 0x3Fu));
  out[3] = (uint8_t)(0x80u | (scalar & 0x3Fu));
  return 4;
}

/* Decodes the scalar at the start of the n > 0 bytes at `s`, which hold well-formed UTF-8 (a string value),
 * and stores its width in `width`. A truncated sequence stops at the end of the bytes rather than reading
 * past it. */
static inline uint32_t ms_utf8_decode_valid(const uint8_t *s, size_t n, size_t *width) {
  const uint8_t lead = s[0];
  size_t length = 1;
  uint32_t scalar = lead;
  if (lead >= 0xF0) {
    length = 4;
    scalar = lead & 0x07u;
  } else if (lead >= 0xE0) {
    length = 3;
    scalar = lead & 0x0Fu;
  } else if (lead >= 0xC0) {
    length = 2;
    scalar = lead & 0x1Fu;
  }
  if (length > n) {
    length = n;
  }
  for (size_t i = 1; i < length; i++) {
    scalar = (scalar << 6) | (s[i] & 0x3Fu);
  }
  *width = length;
  return scalar;
}

#endif

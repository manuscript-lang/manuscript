/* base/utf8.h: UTF-8 decoding, counting and validation of text (utf8.c). An invalid byte decodes as U+FFFD
 * with width 1. Encoding is in base/chars.h. */
#ifndef MS_BASE_UTF8_H
#define MS_BASE_UTF8_H

#include "base/chars.h"
#include "base/safe.h"

#define MS_RUNE_ERROR 0xFFFDu

/* A decoded scalar and its byte width. An invalid sequence decodes as U+FFFD with width 1. */
typedef struct MsRune {
  uint32_t rune;
  uint32_t width;
} MsRune;

/* Decodes the scalar at the start of the n > 0 bytes at s. */
MsRune ms_utf8_decode_multi(const uint8_t *s, size_t n);

static inline MsRune ms_utf8_decode(const uint8_t *s, size_t n) {
  if (s[0] < 0x80) {
    return (MsRune){s[0], 1};
  }
  return ms_utf8_decode_multi(s, n);
}

/* Decodes the scalar that ends the n > 0 bytes at s. */
MsRune ms_utf8_decode_last(const uint8_t *s, size_t n);

/* Whether the scalar is Unicode White_Space. */
bool ms_utf8_is_space(uint32_t c);

/* The byte offset after moving `count` scalars forward from the start of the n bytes at s, or n when fewer
 * remain. */
size_t ms_utf8_offset_of(const uint8_t *s, size_t n, size_t count);

/* Number of scalars in valid UTF-8 (an invalid byte still counts for the scalar it starts). */
size_t ms_utf8_count(const uint8_t *s, size_t n);

/* Whether the n bytes at s are well-formed UTF-8: no overlong forms, surrogates or scalars above U+10FFFF. */
static inline bool ms_utf8_is_valid(const uint8_t *s, size_t n) {
  for (size_t at = 0; at < n;) {
    if (n - at >= 32) { /* thirty-two ASCII bytes at once */
      uint64_t words[4];
      __builtin_memcpy(words, s + at, sizeof words);
      if (((words[0] | words[1] | words[2] | words[3]) & UINT64_C(0x8080808080808080)) == 0) {
        at += 32;
        continue;
      }
    }
    if (n - at >= 8) { /* eight ASCII bytes at once */
      uint64_t word;
      __builtin_memcpy(&word, s + at, sizeof word);
      if ((word & UINT64_C(0x8080808080808080)) == 0) {
        at += 8;
        continue;
      }
    }
    const MsRune scalar = ms_utf8_decode(s + at, n - at);
    if (scalar.rune == MS_RUNE_ERROR && scalar.width == 1) {
      return false;
    }
    at += scalar.width;
  }
  return true;
}

/* Whether every byte is ASCII. */
bool ms_utf8_is_ascii(const uint8_t *s, size_t n);

#endif

/* base/utf8.c: UTF-8 decoding, counting and offsets. An invalid byte decodes as U+FFFD with width 1. */
#include "base/utf8.h"

static inline bool cont(const uint8_t *s, size_t n, size_t i, uint8_t lo, uint8_t hi, uint32_t *bits) {
  if (i >= n || s[i] < lo || s[i] > hi) {
    return false;
  }
  *bits = s[i] & 0x3Fu;
  return true;
}

MsRune ms_utf8_decode_multi(const uint8_t *s, size_t n) {
  uint8_t b0 = s[0];
  /* Two-byte and the unrestricted three-byte leads, which cover most text, decode with one length
   * check and no range tables; any other shape takes the general path below. */
  if (b0 >= 0xC2 && b0 <= 0xDF && n >= 2 && (s[1] & 0xC0) == 0x80) {
    return (MsRune){((b0 & 0x1Fu) << 6) | (s[1] & 0x3Fu), 2};
  }
  if (b0 >= 0xE1 && b0 <= 0xEF && b0 != 0xED && n >= 3 && (s[1] & 0xC0) == 0x80 && (s[2] & 0xC0) == 0x80) {
    return (MsRune){((b0 & 0x0Fu) << 12) | ((s[1] & 0x3Fu) << 6) | (s[2] & 0x3Fu), 3};
  }
  MsRune err = {MS_RUNE_ERROR, 1};
  uint32_t c1, c2, c3;
  if (b0 >= 0xC2 && b0 <= 0xDF) {
    if (!cont(s, n, 1, 0x80, 0xBF, &c1)) {
      return err;
    }
    return (MsRune){((b0 & 0x1Fu) << 6) | c1, 2};
  }
  if (b0 >= 0xE0 && b0 <= 0xEF) {
    uint8_t lo = b0 == 0xE0 ? 0xA0 : 0x80, hi = b0 == 0xED ? 0x9F : 0xBF;
    if (!cont(s, n, 1, lo, hi, &c1) || !cont(s, n, 2, 0x80, 0xBF, &c2)) {
      return err;
    }
    return (MsRune){((b0 & 0x0Fu) << 12) | (c1 << 6) | c2, 3};
  }
  if (b0 >= 0xF0 && b0 <= 0xF4) {
    uint8_t lo = b0 == 0xF0 ? 0x90 : 0x80, hi = b0 == 0xF4 ? 0x8F : 0xBF;
    if (!cont(s, n, 1, lo, hi, &c1) || !cont(s, n, 2, 0x80, 0xBF, &c2) || !cont(s, n, 3, 0x80, 0xBF, &c3)) {
      return err;
    }
    return (MsRune){((b0 & 0x07u) << 18) | (c1 << 12) | (c2 << 6) | c3, 4};
  }
  return err;
}

bool ms_utf8_is_ascii(const uint8_t *s, size_t n) {
  size_t i = 0;
  uint64_t acc = 0;
  for (; i + 8 <= n; i += 8) {
    acc |= ms_load64(s + i);
  }
  for (; i < n; i++) {
    acc |= s[i];
  }
  return (acc & UINT64_C(0x8080808080808080)) == 0;
}

size_t ms_utf8_count(const uint8_t *s, size_t n) {
  /* A String is valid UTF-8, so a scalar starts at every byte that is not a continuation byte
   * (10xxxxxx); counting those needs no validation pass. */
  const uint64_t low = UINT64_C(0x0101010101010101);
  size_t continuation = 0, i = 0;
  for (; i + 8 <= n; i += 8) {
    uint64_t w = ms_load64(s + i);
    continuation += (size_t)__builtin_popcountll((w >> 7) & ~(w >> 6) & low);
  }
  for (; i < n; i++) {
    continuation += (s[i] & 0xC0) == 0x80;
  }
  return n - continuation;
}

/* The scalar that ends the n > 0 bytes at s, with its width. A tail that is not a whole scalar decodes as one
 * invalid byte. */
MsRune ms_utf8_decode_last(const uint8_t *s, size_t n) {
  uint8_t b = s[n - 1];
  if (b < 0x80) {
    return (MsRune){b, 1};
  }
  size_t lim = n > 4 ? n - 4 : 0;
  size_t start = n - 1;
  while (start > lim) {
    start--;
    if ((s[start] & 0xC0) != 0x80) {
      break;
    }
  }
  MsRune r = ms_utf8_decode(s + start, n - start);
  if (start + r.width != n) {
    return (MsRune){MS_RUNE_ERROR, 1};
  }
  return r;
}

/* Unicode White_Space (what Rust's char::is_whitespace tests). */
bool ms_utf8_is_space(uint32_t c) {
  if (c < 0x80) {
    return c == ' ' || (c >= 9 && c <= 13);
  }
  return c == 0x85 || c == 0xA0 || c == 0x1680 || (c >= 0x2000 && c <= 0x200A) || c == 0x2028 ||
         c == 0x2029 || c == 0x202F || c == 0x205F || c == 0x3000;
}

/* The byte offset reached by moving `count` scalars forward from the start of the n bytes at s, or n when
 * fewer remain. */
size_t ms_utf8_offset_of(const uint8_t *s, size_t n, size_t count) {
  size_t offset = 0;
  while (count > 0 && offset < n) {
    offset += ms_utf8_decode(s + offset, n - offset).width;
    count--;
  }
  return offset;
}

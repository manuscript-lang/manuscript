/* ms_rt/utf8.h: UTF-8 decoding and counting for runtime/core (runtime/core/utf8.c). Not an ABI of generated
 * code, so no symbols are listed; the string primitives built on it are (ms_rt/string.h). */
#ifndef MS_RT_UTF8_H
#define MS_RT_UTF8_H

#include "ms_rt/base.h"

#define MS_RUNE_ERROR 0xFFFDu

/* A decoded scalar and its byte width. An invalid sequence decodes as U+FFFD with width 1. */
typedef struct ms_rune {
    uint32_t rune;
    uint32_t width;
} ms_rune;

/* Decodes the scalar at the start of the n > 0 bytes at s. */
ms_rune ms_utf8_decode_multi(const uint8_t *s, size_t n);

static inline ms_rune ms_utf8_decode(const uint8_t *s, size_t n) {
    if (s[0] < 0x80) {
        return (ms_rune){s[0], 1};
    }
    return ms_utf8_decode_multi(s, n);
}

/* Number of scalars in valid UTF-8 (an invalid byte still counts for the scalar it starts). */
size_t ms_utf8_count(const uint8_t *s, size_t n);

/* Whether every byte is ASCII. */
bool ms_utf8_is_ascii(const uint8_t *s, size_t n);

#endif

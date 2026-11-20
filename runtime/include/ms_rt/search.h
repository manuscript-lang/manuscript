/* ms_rt/search.h: substring search over bytes for runtime/core (runtime/core/search.c). */
#ifndef MS_RT_SEARCH_H
#define MS_RT_SEARCH_H

#include "ms_rt/base.h"

/* Haystacks shorter than this are scanned byte by byte: the vector searchers' setup costs more than the scan. */
#define MS_SHORT_HAY 32
/* Haystacks shorter than this are also scanned directly for a needle of two or more bytes. */
#define MS_MEDIUM_HAY 128

size_t ms_find_short(const uint8_t *hay, size_t n, const uint8_t *needle, size_t m);
size_t ms_find_big(const uint8_t *hay, size_t n, const uint8_t *needle, size_t m);

/* The first offset of the m bytes at needle in the n bytes at hay (an empty needle matches at 0), or SIZE_MAX.
 * The short-text test is inline so a caller pays one branch. */
static inline size_t ms_find(const uint8_t *hay, size_t n, const uint8_t *needle, size_t m) {
    if (m == 0) {
        return 0;
    }
    if (m > n) {
        return SIZE_MAX;
    }
    if (n < MS_SHORT_HAY || (m > 1 && n < MS_MEDIUM_HAY)) {
        return ms_find_short(hay, n, needle, m);
    }
    return ms_find_big(hay, n, needle, m);
}

/* Non-overlapping matches, left to right; an empty needle counts 0 (the caller decides that policy). */
size_t ms_count(const uint8_t *hay, size_t n, const uint8_t *needle, size_t m);

#endif

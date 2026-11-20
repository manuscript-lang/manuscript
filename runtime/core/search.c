/* Substring search over bytes. The short-text paths are ported from crates/ms-rt/src/string.rs; the long
 * path replaces the Rust memchr::memmem with a rare-byte memchr scan that falls back to Two-Way
 * (Crochemore-Perrin) once false candidates cost more than a few units per byte, so the worst case is
 * linear. Offsets are bytes; SIZE_MAX means absent. */
#include "ms_rt/search.h"


static inline uint64_t load64(const uint8_t *p) {
    uint64_t v;
    __builtin_memcpy(&v, p, sizeof v);
    return v;
}

/* memchr for a short haystack: eight bytes per step, testing each word for a byte equal to c with the
 * zero-byte trick. */
static inline size_t memchr_short(uint8_t c, const uint8_t *hay, size_t n) {
    const uint64_t lo = UINT64_C(0x0101010101010101), hi = UINT64_C(0x8080808080808080);
    uint64_t pat = lo * c;
    size_t at = 0;
    for (; at + 8 <= n; at += 8) {
        uint64_t x = load64(hay + at) ^ pat;
        uint64_t hit = (x - lo) & ~x & hi;
        if (hit != 0) {
            return at + (size_t)__builtin_ctzll(hit) / 8;
        }
    }
    for (; at < n; at++) {
        if (hay[at] == c) {
            return at;
        }
    }
    return SIZE_MAX;
}

/* Higher = more common. Branches, not a table: no data relocation or initialiser. */
static inline unsigned ms_rank(uint8_t b) {
    if (b == 0 || b == ' ') return 255;
    if (b >= 'a' && b <= 'z')
        return (b == 'e' || b == 't' || b == 'a' || b == 'o' || b == 'i' || b == 'n' ||
                b == 's' || b == 'r') ? 240 : 200;
    if (b >= '0' && b <= '9') return 180;
    if (b == '\n' || b == ',' || b == '.' || b == '"' || b == '/' || b == '_' || b == '-' ||
        b == '=') return 170;
    if (b >= 'A' && b <= 'Z') return 140;
    if (b >= 0x80) return b == 0xFF ? 230 : 150;
    return 100;
}

/* Maximal suffix of x under <= (rev=false) or >= (rev=true); returns its start, sets period. */
static size_t ms_max_suffix(const uint8_t *x, size_t m, bool rev, size_t *period) {
    size_t ms = SIZE_MAX, j = 0, k = 1, p = 1; /* ms is "index - 1"; unsigned wrap is intended */
    while (j + k < m) {
        uint8_t a = x[j + k], b = x[ms + k];
        if (rev ? (b < a) : (a < b)) { j += k; k = 1; p = j - ms; }
        else if (a == b) { if (k != p) k++; else { j += p; k = 1; } }
        else { ms = j++; k = p = 1; }
    }
    *period = p;
    return ms + 1;
}

/* Crochemore-Perrin Two-Way, O(n+m) time, O(1) space. Requires 1 <= m <= n. */
static size_t ms_two_way(const uint8_t *hay, size_t n, const uint8_t *nd, size_t m) {
    size_t p1, p2, period, i, j = 0, last = n - m;
    size_t s1 = ms_max_suffix(nd, m, false, &p1), s2 = ms_max_suffix(nd, m, true, &p2);
    size_t suffix = s1 > s2 ? s1 : s2;
    period = s1 > s2 ? p1 : p2;
    if (__builtin_memcmp(nd, nd + period, suffix) == 0) { /* periodic needle: keep memory */
        size_t memory = 0;
        while (j <= last) {
            i = suffix > memory ? suffix : memory;
            while (i < m && nd[i] == hay[i + j]) i++;
            if (i < m) { j += i - suffix + 1; memory = 0; continue; }
            i = suffix - 1; /* may wrap to SIZE_MAX; comparisons below are wrap-safe */
            while (memory < i + 1 && nd[i] == hay[i + j]) i--;
            if (i + 1 < memory + 1) return j;
            j += period;
            memory = m - period;
        }
    } else { /* non-periodic: shift is a lower bound on the true period */
        period = (suffix > m - suffix ? suffix : m - suffix) + 1;
        while (j <= last) {
            i = suffix;
            while (i < m && nd[i] == hay[i + j]) i++;
            if (i < m) { j += i - suffix + 1; continue; }
            i = suffix - 1;
            while (i != SIZE_MAX && nd[i] == hay[i + j]) i--;
            if (i == SIZE_MAX) return j;
            j += period;
        }
    }
    return SIZE_MAX;
}

/* The index of the rarest byte among the first 64 of a needle of m >= 2 bytes, by a fixed English-text ranking. */
static inline size_t rare_index(const uint8_t *nd, size_t m) {
    size_t r = 0, lim = m < 64 ? m : 64;
    unsigned best = ms_rank(nd[0]);
    for (size_t i = 1; i < lim; i++) {
        unsigned k = ms_rank(nd[i]);
        if (k < best) { best = k; r = i; }
    }
    return r;
}

typedef uint8_t v16 __attribute__((vector_size(16), aligned(1), may_alias));

/* hay holds n >= m >= 2 bytes; r is rare_index(nd, m). Sixteen candidate starts at a time are tested on two bytes
 * of the needle at once (the rare one and the last, or the first when the rare one is the last), with the
 * compiler's portable 16-byte vectors (SSE2, NEON): a candidate is a start where both match, so a text full of
 * the rare byte alone costs no call per hit. Candidates that fail the full compare are counted as work; once they
 * cost more than a few units per byte the rest is the linear Two-Way search. */
static size_t find_long(const uint8_t *hay, size_t n, const uint8_t *nd, size_t m, size_t r) {
    const uint64_t high = UINT64_C(0x8080808080808080);
    const size_t q = r == m - 1 ? 0 : m - 1, last = n - m; /* last valid start offset */
    const v16 zero = {0}, vr = zero + nd[r], vq = zero + nd[q];
    size_t i = 0, work = 0;
    while (i <= last) {
        uint64_t half[2] = {0, 0};
        size_t span;
        /* Long stretches without a candidate: thirty-two starts per step. */
        while (i <= last && last - i >= 31) {
            v16 a = (*(const v16 *)(hay + i + r) == vr) & (*(const v16 *)(hay + i + q) == vq);
            v16 b = (*(const v16 *)(hay + i + 16 + r) == vr) & (*(const v16 *)(hay + i + 16 + q) == vq);
            v16 any = a | b;
            uint64_t t[2];
            __builtin_memcpy(t, &any, 16);
            if ((t[0] | t[1]) != 0) {
                break;
            }
            i += 32;
        }
        if (i > last) {
            break;
        }
        if (last - i >= 15) {
            v16 a = (*(const v16 *)(hay + i + r) == vr) & (*(const v16 *)(hay + i + q) == vq); /* 0xff where both match */
            __builtin_memcpy(half, &a, 16);
            span = 16;
        } else { /* fewer than sixteen starts left */
            span = last - i + 1;
            for (size_t k = 0; k < span; k++) {
                if (hay[i + k + r] == nd[r] && hay[i + k + q] == nd[q]) half[k >> 3] |= UINT64_C(0x80) << (8 * (k & 7));
            }
        }
        for (size_t h = 0; h < 2; h++) {
            uint64_t mask = half[h] & high;
            while (mask != 0) {
                size_t c = i + 8 * h + (size_t)__builtin_ctzll(mask) / 8;
                mask &= mask - 1;
                if (__builtin_memcmp(hay + c, nd, m) == 0) return c;
                work += 4 + m; /* a false candidate: the compare, plus the loop's own cost */
                if ((work >> 2) > c + 64) { /* false candidates cost > ~4 units/byte: go linear */
                    size_t pos = c + 1;
                    if (pos > last) return SIZE_MAX;
                    size_t t = ms_two_way(hay + pos, n - pos, nd, m);
                    return t == SIZE_MAX ? t : t + pos;
                }
            }
        }
        i += span;
    }
    return SIZE_MAX;
}

/* The offset of the byte to scan for: the last one that is not a space or common punctuation, which text is
 * full of, or the last byte when it is all of those. */
static inline size_t rare_offset(const uint8_t *needle, size_t m) {
    for (size_t i = m; i > 0; i--) {
        uint8_t b = needle[i - 1];
        if (!(b == ' ' || b == '/' || b == '.' || b == ',' || b == '-' || b == ':' || b == '_')) {
            return i - 1;
        }
    }
    return m - 1;
}

/* find for a short haystack and a non-empty needle (m >= 1). */
static size_t find_short(const uint8_t *hay, size_t n, const uint8_t *needle, size_t m) {
    if (m > n) {
        return SIZE_MAX;
    }
    size_t last = n - m, k = rare_offset(needle, m), i = 0;
    uint8_t pivot = needle[k];
    while (i <= last) {
        /* hay[i + k] is the pivot byte of the candidate start i. */
        size_t step = memchr_short(pivot, hay + i + k, last - i + 1);
        if (step == SIZE_MAX) {
            return SIZE_MAX;
        }
        i += step;
        if (__builtin_memcmp(hay + i, needle, m) == 0) {
            return i;
        }
        i++;
    }
    return SIZE_MAX;
}

/* find_short for any needle: the entry the inline dispatch in ms_rt/search.h calls. */
size_t ms_find_short(const uint8_t *hay, size_t n, const uint8_t *needle, size_t m) {
    return find_short(hay, n, needle, m);
}

/* The search of a long text, or of a one-byte needle in text of MS_SHORT_HAY bytes or more (m <= n, m >= 1). */
size_t ms_find_big(const uint8_t *hay, size_t n, const uint8_t *needle, size_t m) {
    if (m == 1) {
        const uint8_t *p = (const uint8_t *)__builtin_memchr(hay, needle[0], n);
        return p ? (size_t)(p - hay) : SIZE_MAX;
    }
    return find_long(hay, n, needle, m, rare_index(needle, m));
}

/* Searches after the first NEAR bytes: matches in text are usually a few bytes apart (words, fields), where
 * the per-call setup of the long search costs more than scanning them directly. */
#define NEAR 16

ms_needle ms_needle_for(const uint8_t *needle, size_t m, size_t text_len) {
    ms_needle nd = {needle, m, 0, false};
    if (m >= 2 && text_len >= MS_MEDIUM_HAY) {
        nd.rare = rare_index(needle, m); /* chosen once for every search of this text */
        nd.prepared = true;
    }
    return nd;
}

size_t ms_needle_find(const ms_needle *nd, const uint8_t *h, size_t left) {
    const uint8_t *needle = nd->bytes;
    size_t m = nd->len;
    if (m == 1) {
        /* Matches are usually a few bytes apart: the first NEAR bytes are scanned as words before memchr's call. */
        if (left < MS_SHORT_HAY) {
            return memchr_short(needle[0], h, left);
        }
        size_t i = memchr_short(needle[0], h, NEAR);
        if (i != SIZE_MAX) {
            return i;
        }
        const uint8_t *p = (const uint8_t *)__builtin_memchr(h + NEAR, needle[0], left - NEAR);
        return p ? (size_t)(p - h) : SIZE_MAX;
    }
    if (!nd->prepared) {
        return ms_find(h, left, needle, m);
    }
    if (left < m) {
        return SIZE_MAX;
    }
    if (left >= MS_SHORT_HAY) {
        /* A match starting before NEAR ends inside this window. */
        size_t near = NEAR + m - 1 < left ? NEAR + m - 1 : left;
        size_t i = find_short(h, near, needle, m);
        if (i == SIZE_MAX && left - NEAR >= m) {
            i = find_long(h + NEAR, left - NEAR, needle, m, nd->rare);
            i = i == SIZE_MAX ? SIZE_MAX : i + NEAR;
        }
        return i;
    }
    return find_short(h, left, needle, m);
}

size_t ms_count(const uint8_t *hay, size_t n, const uint8_t *needle, size_t m) {
    size_t count = 0, pos = 0;
    if (m == 0) {
        return 0;
    }
    ms_needle nd = ms_needle_for(needle, m, n);
    while (n - pos >= m) {
        size_t i = ms_needle_find(&nd, hay + pos, n - pos);
        if (i == SIZE_MAX) {
            break;
        }
        count++;
        pos += i + m;
    }
    return count;
}

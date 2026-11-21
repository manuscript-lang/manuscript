/* Substring search over bytes. The short-text paths are ported from crates/ms-rt/src/string.rs; the long
 * path replaces the Rust memchr::memmem with a rare-byte memchr scan that falls back to Two-Way
 * (Crochemore-Perrin) once false candidates cost more than a few units per byte, so the worst case is
 * linear. Offsets are bytes; SIZE_MAX means absent. */
#include "ms_rt/search.h"


/* memchr for a short haystack: eight bytes per step, testing each word for a byte equal to c with the
 * zero-byte trick. */
static inline size_t memchr_short(uint8_t c, const uint8_t *hay, size_t n) {
    const uint64_t lo = UINT64_C(0x0101010101010101), hi = UINT64_C(0x8080808080808080);
    uint64_t pat = lo * c;
    size_t at = 0;
    for (; at + 8 <= n; at += 8) {
        uint64_t x = ms_load64(hay + at) ^ pat;
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

/* The Two-Way search of the text from `from` on, for the offset in the whole text or SIZE_MAX. */
static size_t two_way_from(const uint8_t *hay, size_t n, const uint8_t *nd, size_t m, size_t from) {
    if (from > n - m) {
        return SIZE_MAX;
    }
    const size_t found = ms_two_way(hay + from, n - from, nd, m);
    return found == SIZE_MAX ? SIZE_MAX : found + from;
}

typedef uint8_t MsByteVector __attribute__((vector_size(16)));
/* Loads through unaligned addresses. Kept apart from the value type: GCC 8 to 14 on aarch64 crash on a function
 * that takes or returns a vector declared aligned(1). */
typedef uint8_t MsByteVectorLoad __attribute__((vector_size(16), aligned(1), may_alias));

/* Two bytes of the needle, tested together at every start of a 16-byte window: the rare byte and the last one
 * (the first when the rare one is the last). A start where both match is a candidate. */
typedef struct PairProbe {
    size_t rare_offset;
    size_t last_offset;
    uint8_t rare_value;
    uint8_t last_value;
    MsByteVector rare_byte; /* the rare byte in every lane */
    MsByteVector last_byte;
} PairProbe;

static PairProbe pair_probe_new(const uint8_t *needle, size_t length, size_t rare_index) {
    const MsByteVector zero = {0};
    const size_t other = rare_index == length - 1 ? 0 : length - 1;
    return (PairProbe){.rare_offset = rare_index,
                       .last_offset = other,
                       .rare_value = needle[rare_index],
                       .last_value = needle[other],
                       .rare_byte = zero + needle[rare_index],
                       .last_byte = zero + needle[other]};
}

/* 0xff in lane k when the needle's two bytes sit at start + k; reads 16 bytes at each offset. */
static inline MsByteVector probe_window(const uint8_t *hay, size_t start, const PairProbe *probe) {
    const MsByteVector rare = *(const MsByteVectorLoad *)(hay + start + probe->rare_offset);
    const MsByteVector last = *(const MsByteVectorLoad *)(hay + start + probe->last_offset);
    return (rare == probe->rare_byte) & (last == probe->last_byte);
}

static inline bool any_lane_set(MsByteVector lanes) {
    uint64_t halves[2];
    __builtin_memcpy(halves, &lanes, sizeof halves);
    return (halves[0] | halves[1]) != 0;
}

/* The candidate mask of fewer than sixteen starts, one scalar test each: bit 7 of byte k of half k / 8. */
static void probe_tail(const uint8_t *hay, size_t start, size_t starts, const PairProbe *probe, uint64_t halves[2]) {
    const uint8_t *rare = hay + probe->rare_offset, *last = hay + probe->last_offset;
    for (size_t k = 0; k < starts; k++) {
        if (rare[start + k] == probe->rare_value && last[start + k] == probe->last_value) {
            halves[k / 8] |= UINT64_C(0x80) << (8 * (k % 8));
        }
    }
}

/* hay holds n >= m >= 2 bytes; r is rare_index(nd, m). Starts are tested sixteen at a time (thirty-two while no
 * candidate shows up) with the compiler's portable 16-byte vectors (SSE2, NEON), so a text full of the rare byte
 * alone costs no call per hit. Candidates that fail the full compare are counted as work; once they cost more
 * than a few units per byte the rest is the linear Two-Way search. */
static size_t find_long(const uint8_t *hay, size_t n, const uint8_t *nd, size_t m, size_t r) {
    const uint64_t high = UINT64_C(0x8080808080808080);
    const PairProbe probe = pair_probe_new(nd, m, r);
    const size_t last_start = n - m;
    size_t start = 0, work = 0;
    while (start <= last_start) {
        while (start <= last_start && last_start - start >= 31 &&
               !any_lane_set(probe_window(hay, start, &probe) | probe_window(hay, start + 16, &probe))) {
            start += 32;
        }
        if (start > last_start) {
            break;
        }
        uint64_t halves[2] = {0, 0};
        size_t starts = last_start - start + 1;
        if (starts >= 16) {
            const MsByteVector window = probe_window(hay, start, &probe);
            __builtin_memcpy(halves, &window, sizeof halves);
            starts = 16;
        } else {
            probe_tail(hay, start, starts, &probe, halves);
        }
        for (size_t half = 0; half < 2; half++) {
            uint64_t mask = halves[half] & high;
            while (mask != 0) {
                const size_t candidate = start + 8 * half + (size_t)__builtin_ctzll(mask) / 8;
                mask &= mask - 1;
                if (__builtin_memcmp(hay + candidate, nd, m) == 0) {
                    return candidate;
                }
                work += 4 + m; /* a false candidate: the compare, plus the loop's own cost */
                if ((work >> 2) > candidate + 64) { /* false candidates cost > ~4 units/byte: go linear */
                    return two_way_from(hay, n, nd, m, candidate + 1);
                }
            }
        }
        start += starts;
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

MsNeedle ms_needle_for(MsBytes pattern, size_t text_len) {
    MsNeedle needle = {.pattern = pattern, .rare_index = 0, .prepared = false};
    if (pattern.len >= 2 && text_len >= MS_MEDIUM_HAY) {
        needle.rare_index = rare_index(pattern.ptr, pattern.len); /* chosen once for every search of this text */
        needle.prepared = true;
    }
    return needle;
}

/* The search for a one-byte needle: matches are usually a few bytes apart, so the first NEAR bytes are scanned as
 * words before the call to memchr. */
static size_t find_byte(uint8_t byte, const uint8_t *hay, size_t n) {
    if (n < MS_SHORT_HAY) {
        return memchr_short(byte, hay, n);
    }
    size_t near_hit = memchr_short(byte, hay, NEAR);
    if (near_hit != SIZE_MAX) {
        return near_hit;
    }
    const uint8_t *hit = __builtin_memchr(hay + NEAR, byte, n - NEAR);
    return hit == NULL ? SIZE_MAX : (size_t)(hit - hay);
}

size_t ms_needle_find(const MsNeedle *needle, MsBytes haystack) {
    const uint8_t *pattern = needle->pattern.ptr, *hay = haystack.ptr;
    const size_t m = needle->pattern.len, n = haystack.len;
    if (m == 1) {
        return find_byte(pattern[0], hay, n);
    }
    if (!needle->prepared) {
        return ms_find(hay, n, pattern, m);
    }
    if (n < m) {
        return SIZE_MAX;
    }
    if (n < MS_SHORT_HAY) {
        return find_short(hay, n, pattern, m);
    }
    /* A match starting before NEAR ends inside this window. */
    const size_t window = NEAR + m - 1 < n ? NEAR + m - 1 : n;
    size_t found = find_short(hay, window, pattern, m);
    if (found == SIZE_MAX && n - NEAR >= m) {
        found = find_long(hay + NEAR, n - NEAR, pattern, m, needle->rare_index);
        found = found == SIZE_MAX ? SIZE_MAX : found + NEAR;
    }
    return found;
}

size_t ms_count(const uint8_t *hay, size_t n, const uint8_t *needle, size_t m) {
    size_t count = 0, pos = 0;
    if (m == 0) {
        return 0;
    }
    const MsNeedle prepared = ms_needle_for(ms_bytes_of(needle, m), n);
    while (n - pos >= m) {
        size_t i = ms_needle_find(&prepared, ms_bytes_of(hay + pos, n - pos));
        if (i == SIZE_MAX) {
            break;
        }
        count++;
        pos += i + m;
    }
    return count;
}

/* The last match of a needle: candidates are the positions of the needle's first byte, found from the end, and
 * each is compared whole. A text that repeats the needle's prefix thousands of times is the slow case (quadratic);
 * forward search has the Two-Way fallback, reverse search has not needed it yet. */
size_t ms_rfind(const uint8_t *hay, size_t n, const uint8_t *needle, size_t m) {
    if (m == 0) {
        return n;
    }
    if (m > n) {
        return SIZE_MAX;
    }
    for (size_t at = n - m + 1; at > 0; at--) {
        if (hay[at - 1] == needle[0] && __builtin_memcmp(hay + at - 1, needle, m) == 0) {
            return at - 1;
        }
    }
    return SIZE_MAX;
}

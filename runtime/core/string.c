/* String primitives that read strings and allocate nothing. Ported from crates/ms-rt/src/string.rs; the
 * hash is bit-identical to `hash_bytes` there, because the Rust maps and the compiler's inline map
 * probe still compute it themselves. */
#include "ms_rt/string.h"
#include "ms_rt/search.h"
#include "ms_rt/utf8.h"

#define K0 UINT64_C(0x9e3779b97f4a7c15)
#define K1 UINT64_C(0xff51afd7ed558ccd)

static inline uint64_t load64(const uint8_t *p) {
    uint64_t v;
    __builtin_memcpy(&v, p, sizeof v);
    return v;
}

static inline uint32_t load32(const uint8_t *p) {
    uint32_t v;
    __builtin_memcpy(&v, p, sizeof v);
    return v;
}

static inline uint64_t fold(uint64_t a, uint64_t b) {
    unsigned __int128 m = (unsigned __int128)a * b;
    return (uint64_t)m ^ (uint64_t)(m >> 64);
}

/* The hash of a string of n <= 15 bytes whose little-endian bits are lo (bytes 0..7) and hi (bytes 8..15). */
static inline uint64_t hash_inline(size_t n, uint64_t lo, uint64_t hi) {
    uint64_t h = K0 ^ ((uint64_t)n * K1);
    return fold(fold(h ^ lo, K1) ^ hi, K0);
}

int64_t msrt_string_hash(const ms_str *s) {
    size_t n = ms_str_len(s);
    if (ms_str_is_inline(s)) {
        uint64_t hi = s->tagged & ((UINT64_C(1) << MS_STR_INLINE_SHIFT) - 1);
        return (int64_t)hash_inline(n, (uint64_t)(uintptr_t)s->ptr_word, hi);
    }
    const uint8_t *b = s->ptr_word;
    if (n <= MS_STR_INLINE_MAX) {
        uint8_t pad[16] = {0};
        __builtin_memcpy(pad, b, n);
        return (int64_t)hash_inline(n, load64(pad), load64(pad + 8));
    }
    uint64_t h = K0 ^ ((uint64_t)n * K1);
    size_t i = 0;
    while (i + 8 <= n) {
        h = fold(h ^ load64(b + i), K1);
        i += 8;
    }
    /* Sixteen bytes or more: the last eight bytes, overlapping the words already folded in. */
    return (int64_t)fold(h ^ load64(b + n - 8), K0);
}

/* Whether two strings hold the same bytes: overlapping word compares for up to 16 bytes. */
static inline bool bytes_eq(const ms_str *a, const ms_str *b) {
    size_t n = ms_str_len(a);
    if (n != ms_str_len(b)) {
        return false;
    }
    const uint8_t *p = ms_str_data(a), *q = ms_str_data(b);
    if (n >= 8 && n <= 16) {
        return load64(p) == load64(q) && load64(p + n - 8) == load64(q + n - 8);
    }
    if (n >= 4 && n < 8) {
        return load32(p) == load32(q) && load32(p + n - 4) == load32(q + n - 4);
    }
    if (n < 4) {
        /* The first, middle and last bytes cover every byte of a string of up to three. */
        return n == 0 || (p[0] == q[0] && p[n >> 1] == q[n >> 1] && p[n - 1] == q[n - 1]);
    }
    return __builtin_memcmp(p, q, n) == 0;
}

uint8_t msrt_string_eq(const ms_str *a, const ms_str *b) {
    return (a->ptr_word == b->ptr_word && a->tagged == b->tagged) || bytes_eq(a, b);
}

static inline uint64_t bswap64(uint64_t v) { return __builtin_bswap64(v); }

/* Both strings hold their bytes elsewhere (or one does): memcmp, then the lengths. */
static inline int64_t compare_memory(const uint8_t *pa, size_t la, const uint8_t *pb, size_t lb) {
    size_t n = la < lb ? la : lb;
    int c = n ? __builtin_memcmp(pa, pb, n) : 0;
    if (c != 0) {
        return c < 0 ? -1 : 1;
    }
    return (int64_t)(la > lb) - (int64_t)(la < lb);
}

static __attribute__((noinline)) int64_t compare_mixed(const ms_str *a, const ms_str *b) {
    return compare_memory(ms_str_data(a), ms_str_len(a), ms_str_data(b), ms_str_len(b));
}

int64_t msrt_string_compare(const ms_str *a, const ms_str *b) {
    uint64_t ta = a->tagged, tb = b->tagged;
    if ((ta >> 62) != 1 && (tb >> 62) != 1) {
        /* Neither is inline: the address word and the length field are read directly. */
        return compare_memory(a->ptr_word, (size_t)(ta & MS_STR_LEN_MASK), b->ptr_word, (size_t)(tb & MS_STR_LEN_MASK));
    }
    if ((ta >> 62) != 1 || (tb >> 62) != 1) {
        return compare_mixed(a, b);
    }
    /* Both inline: the bits are zero past the length, so the first byte is the most significant after a
     * byte swap, and equal padded words differ at most in length (a prefix, or a string that continues
     * with NUL bytes); the shorter one is smaller. */
    uint64_t x = bswap64((uint64_t)(uintptr_t)a->ptr_word), y = bswap64((uint64_t)(uintptr_t)b->ptr_word);
    if (x == y) {
        const uint64_t mask = (UINT64_C(1) << MS_STR_INLINE_SHIFT) - 1;
        x = bswap64(ta & mask);
        y = bswap64(tb & mask);
        if (x == y) {
            uint64_t la = (ta >> MS_STR_INLINE_SHIFT) & 15, lb = (tb >> MS_STR_INLINE_SHIFT) & 15;
            return (int64_t)(la > lb) - (int64_t)(la < lb);
        }
    }
    return x < y ? -1 : 1;
}

uint8_t msrt_string_is_empty(const ms_str *s) { return ms_str_len(s) == 0; }

int64_t msrt_string_length(const ms_str *s) { return (int64_t)ms_str_len(s); }

uint8_t msrt_string_starts_with(const ms_str *a, const ms_str *v) {
    size_t n = ms_str_len(v);
    return n <= ms_str_len(a) && (n == 0 || __builtin_memcmp(ms_str_data(a), ms_str_data(v), n) == 0);
}

uint8_t msrt_string_ends_with(const ms_str *a, const ms_str *v) {
    size_t n = ms_str_len(v), m = ms_str_len(a);
    return n <= m && (n == 0 || __builtin_memcmp(ms_str_data(a) + (m - n), ms_str_data(v), n) == 0);
}

/* Whether s is known to be ASCII without scanning heap bytes: flagged, or inline with clear high bits. */
static inline bool known_ascii(const ms_str *s) {
    if (ms_str_is_inline(s)) {
        const uint64_t high = UINT64_C(0x8080808080808080);
        return ((uint64_t)(uintptr_t)s->ptr_word & high) == 0 && (s->tagged & (high >> 8)) == 0;
    }
    return (s->tagged & MS_STR_ASCII) != 0;
}

/* The scalar count: the byte length for a string known to be ASCII, else counted on each call. */
int64_t msrt_string_scalar_length(const ms_str *s) {
    size_t n = ms_str_len(s);
    if (known_ascii(s)) {
        return (int64_t)n;
    }
    return (int64_t)ms_utf8_count(ms_str_data(s), n);
}

/* The scalar that starts at byte `at`; an offset outside the string reads as an invalid byte. */
static inline ms_rune rune_at(const ms_str *s, int64_t at) {
    size_t n = ms_str_len(s);
    if (at < 0 || (uint64_t)at >= n) {
        return (ms_rune){MS_RUNE_ERROR, 1};
    }
    return ms_utf8_decode(ms_str_data(s) + at, n - (size_t)at);
}

/* Byte width of the character that starts at byte `at`. */
int64_t msrt_string_char_width(const ms_str *s, int64_t at) { return rune_at(s, at).width; }

/* The scalar value and byte width of the character at byte `at` in one decode, as scalar << 3 | width. */
int64_t msrt_string_scalar_step(const ms_str *s, int64_t at) {
    ms_rune r = rune_at(s, at);
    return (int64_t)(((uint64_t)r.rune << 3) | r.width);
}

/* The Unicode scalar value of the character that starts at byte `at`. */
int64_t msrt_string_scalar_at_byte(const ms_str *s, int64_t at) { return rune_at(s, at).rune; }

uint8_t msrt_string_contains(const ms_str *a, const ms_str *v) {
    return ms_find(ms_str_data(a), ms_str_len(a), ms_str_data(v), ms_str_len(v)) != SIZE_MAX;
}

/* contains where the caller knows the needle has two or more bytes (a literal). */
uint8_t msrt_string_contains_multi(const ms_str *a, const ms_str *v) { return msrt_string_contains(a, v); }

/* Non-overlapping occurrences of v in a; an empty v counts the scalars plus one. */
int64_t msrt_string_count(const ms_str *a, const ms_str *v) {
    size_t m = ms_str_len(v);
    if (m == 0) {
        return msrt_string_scalar_length(a) + 1;
    }
    return (int64_t)ms_count(ms_str_data(a), ms_str_len(a), ms_str_data(v), m);
}

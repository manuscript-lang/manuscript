/* ms_rt/strbuild.h: building string values in C (header only, for runtime/core). The rules are those of
 * crates/ms-rt/src/string.rs: results of 0 or 1 ASCII bytes are the shared statics, up to 15 bytes are
 * inline, longer ones are one allocation (bytes, NUL, no spare room recorded) flagged ASCII when they are. */
#ifndef MS_RT_STRBUILD_H
#define MS_RT_STRBUILD_H

#include "ms_rt/alloc.h"
#include "ms_rt/string.h"

/* The Rust runtime's table of one-byte ASCII strings: entry b is {b, 0}. */
extern uint8_t msrt_ascii_chars[][2];
/* Ends the program with a fault report; the one runtime fault path. */
void msrt_fault(const uint8_t *msg, size_t len) __attribute__((noreturn));
void msrt_index_fault(int64_t index, int64_t length) __attribute__((noreturn));

#define MS_STR_STATIC (UINT64_C(1) << 63)
#define MS_STR_INLINE (UINT64_C(1) << 62)
#define MS_STR_VIEW (UINT64_C(3) << 62)
/* Native allocation ceiling for built strings. */
#define MS_STR_MAX_BYTES ((size_t)1 << 30)

static inline void ms_limit_fault(void) {
    static const uint8_t msg[] = "string: limit exceeded";
    msrt_fault(msg, sizeof msg - 1);
}

static inline uint64_t ms_load64(const uint8_t *p) {
    uint64_t v;
    __builtin_memcpy(&v, p, sizeof v);
    return v;
}

static inline uint32_t ms_load32(const uint8_t *p) {
    uint32_t v;
    __builtin_memcpy(&v, p, sizeof v);
    return v;
}

/* Copies n non-overlapping bytes; up to 16 go through overlapping word moves instead of a call into memcpy,
 * which costs more than the copy for the short pieces words and fields split into. */
static inline void ms_copy_bytes(uint8_t *dst, const uint8_t *src, size_t n) {
    if (n == 0) {
        return;
    }
    if (n < 4) {
        uint8_t a = src[0], b = src[n / 2], c = src[n - 1];
        dst[0] = a;
        dst[n / 2] = b;
        dst[n - 1] = c;
    } else if (n < 8) {
        uint32_t a = ms_load32(src), b = ms_load32(src + n - 4);
        __builtin_memcpy(dst, &a, 4);
        __builtin_memcpy(dst + n - 4, &b, 4);
    } else if (n <= 16) {
        uint64_t a = ms_load64(src), b = ms_load64(src + n - 8);
        __builtin_memcpy(dst, &a, 8);
        __builtin_memcpy(dst + n - 8, &b, 8);
    } else {
        __builtin_memcpy(dst, src, n);
    }
}

/* An owned string over the allocation at p (len bytes, NUL written here). */
static inline ms_str ms_str_owned(uint8_t *p, size_t len) {
    p[len] = 0;
    return (ms_str){p, len};
}

/* A new owned allocation of len bytes plus the NUL; faults over the string limit. */
static inline ms_str ms_str_alloc(size_t len) {
    if (len > MS_STR_MAX_BYTES) {
        ms_limit_fault();
    }
    return ms_str_owned(msrt_alloc(len + 1), len);
}

/* The same string flagged as all ASCII; not for inline strings. */
static inline ms_str ms_str_with_ascii(ms_str s) {
    s.tagged |= MS_STR_ASCII;
    return s;
}

/* Whether the n bytes at p are all ASCII. */
static inline bool ms_bytes_ascii(const uint8_t *p, size_t n) {
    uint64_t acc = 0;
    size_t i = 0;
    for (; i + 8 <= n; i += 8) {
        acc |= ms_load64(p + i);
    }
    for (; i < n; i++) {
        acc |= p[i];
    }
    return (acc & UINT64_C(0x8080808080808080)) == 0;
}

/* Whether s is all ASCII, from its flag or inline bits when it has them. */
static inline bool ms_str_is_ascii(const ms_str *s) {
    if (ms_str_is_inline(s)) {
        const uint64_t high = UINT64_C(0x8080808080808080);
        return ((uint64_t)(uintptr_t)s->ptr_word & high) == 0 && (s->tagged & (high >> 8)) == 0;
    }
    return (s->tagged & MS_STR_ASCII) != 0 || ms_bytes_ascii(s->ptr_word, ms_str_len(s));
}

/* An inline string of n <= 15 bytes. */
static inline __attribute__((always_inline)) ms_str ms_str_inline(const uint8_t *p, size_t n) {
    uint64_t lo, hi = 0;
    if (n >= 8) {
        lo = ms_load64(p);
        if (n > 8) {
            hi = ms_load64(p + n - 8) >> (8 * (16 - n));
        }
    } else if (n >= 4) {
        lo = (uint64_t)ms_load32(p) | ((uint64_t)ms_load32(p + n - 4) << (8 * (n - 4)));
    } else if (n > 0) {
        lo = (uint64_t)p[0] | ((uint64_t)p[n / 2] << (8 * (n / 2))) | ((uint64_t)p[n - 1] << (8 * (n - 1)));
    } else {
        lo = 0;
    }
    ms_str s;
    s.ptr_word = (uint8_t *)(uintptr_t)lo;
    s.tagged = hi | MS_STR_INLINE | ((uint64_t)n << MS_STR_INLINE_SHIFT);
    return s;
}

/* The shared static string of one ASCII byte, or of none. */
static inline ms_str ms_str_ascii_char(uint8_t b) { return (ms_str){msrt_ascii_chars[b], MS_STR_STATIC | 1}; }
static inline ms_str ms_str_empty(void) { return (ms_str){msrt_ascii_chars[0], MS_STR_STATIC}; }

/* A heap copy of the bytes, whatever their number. */
static inline ms_str ms_str_heap_copy(const uint8_t *p, size_t n) {
    ms_str s = ms_str_alloc(n);
    __builtin_memcpy(s.ptr_word, p, n);
    return ms_bytes_ascii(p, n) ? ms_str_with_ascii(s) : s;
}

/* New string from bytes: the shared statics for none or one ASCII byte, inline up to 15, else a heap copy. */
static inline __attribute__((always_inline)) ms_str ms_str_from_bytes(const uint8_t *p, size_t n) {
    if (n == 0) {
        return ms_str_empty();
    }
    if (n == 1 && p[0] < 0x80) {
        return ms_str_ascii_char(p[0]);
    }
    if (n >= 2 && n <= MS_STR_INLINE_MAX) {
        return ms_str_inline(p, n);
    }
    return ms_str_heap_copy(p, n);
}

/* A string for n bytes at p inside another live string: an inline copy when it fits, else a view. */
static inline __attribute__((always_inline)) ms_str ms_str_view_of(const uint8_t *p, size_t n) {
    if (n <= MS_STR_INLINE_MAX) {
        return ms_str_inline(p, n);
    }
    return (ms_str){(uint8_t *)p, MS_STR_VIEW | n};
}

/* A copy of s the caller owns: static and inline strings are the same two words; owned strings and views are
 * duplicated (inline when short). */
static inline ms_str ms_str_cloned(const ms_str *s) {
    uint64_t kind = s->tagged >> 62;
    if (kind == 1 || kind == 2) {
        return *s;
    }
    size_t n = ms_str_len(s);
    return n <= MS_STR_INLINE_MAX ? ms_str_inline(s->ptr_word, n) : ms_str_heap_copy(s->ptr_word, n);
}

/* Writes the two words as separate stores: a struct copy may become one 16-byte vector move, which stalls
 * reading words a callee just stored separately. */
static inline void ms_str_write(ms_str s, ms_str *out) {
    *(uint8_t *volatile *)&out->ptr_word = s.ptr_word;
    *(volatile uint64_t *)&out->tagged = s.tagged;
}

/* Frees the bytes of s when it is owned. */
static inline void ms_str_release(const ms_str *s) {
    if (s->tagged < MS_STR_INLINE) {
        msrt_free(s->ptr_word);
    }
}

#endif

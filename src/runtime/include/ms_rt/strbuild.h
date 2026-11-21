/* ms_rt/strbuild.h: building string values in C (header only, for src/runtime/core). The rules are those of
 * crates/ms-rt/src/string.rs: results of 0 or 1 ASCII bytes are the shared statics, up to 15 bytes are
 * inline, longer ones are one allocation (bytes, NUL, no spare room recorded) flagged ASCII when they are. */
#ifndef MS_RT_STRBUILD_H
#define MS_RT_STRBUILD_H

#include "ms_rt/alloc.h"
#include "ms_rt/safe.h"
#include "ms_rt/fault.h"
#include "ms_rt/string.h"

/* The Rust runtime's table of one-byte ASCII strings: entry b is {b, 0}. */
extern uint8_t msrt_ascii_chars[][2];

#define MS_STR_STATIC (UINT64_C(1) << 63)
#define MS_STR_INLINE (UINT64_C(1) << 62)
#define MS_STR_VIEW (UINT64_C(3) << 62)
/* Native allocation ceiling for built strings. */
#define MS_STR_MAX_BYTES ((size_t)1 << 30)

static inline void ms_limit_fault(void) {
    static const uint8_t msg[] = "string: limit exceeded";
    msrt_fault(msg, sizeof msg - 1);
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
static inline MsStr ms_str_owned(uint8_t *p, size_t len) {
    p[len] = 0;
    return (MsStr){.ptr_word = p, .tagged = len};
}

/* A new owned allocation of len bytes plus the NUL; faults over the string limit. */
static inline MsStr ms_str_alloc(size_t len) {
    if (len > MS_STR_MAX_BYTES) {
        ms_limit_fault();
    }
    return ms_str_owned(msrt_alloc(len + 1), len);
}

/* The same string flagged as all ASCII; not for inline strings. */
static inline MsStr ms_str_with_ascii(MsStr s) {
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
static inline bool ms_str_is_ascii(const MsStr *s) {
    if (ms_str_is_inline(s)) {
        const uint64_t high = UINT64_C(0x8080808080808080);
        return ((uint64_t)(uintptr_t)s->ptr_word & high) == 0 && (s->tagged & (high >> 8)) == 0;
    }
    return (s->tagged & MS_STR_ASCII) != 0 || ms_bytes_ascii(s->ptr_word, ms_str_len(s));
}

/* The first 16 bytes of an inline string as two little-endian words, from n <= 16 bytes at p: overlapping loads,
 * so no call to memcpy and no byte loop. */
static inline void ms_pack16(const uint8_t *p, size_t n, uint64_t *low, uint64_t *high) {
    *low = 0;
    *high = 0;
    if (n >= 8) {
        *low = ms_load64(p);
        if (n > 8) {
            *high = ms_load64(p + n - 8) >> (8 * (16 - n));
        }
    } else if (n >= 4) {
        *low = (uint64_t)ms_load32(p) | ((uint64_t)ms_load32(p + n - 4) << (8 * (n - 4)));
    } else if (n > 0) {
        *low = (uint64_t)p[0] | ((uint64_t)p[n / 2] << (8 * (n / 2))) | ((uint64_t)p[n - 1] << (8 * (n - 1)));
    }
}

/* An inline string of n <= 15 bytes. */
static inline MS_ALWAYS_INLINE MsStr ms_str_inline(const uint8_t *p, size_t n) {
    uint64_t low = 0, high = 0;
    ms_pack16(p, n, &low, &high);
    MsStr s = {.ptr_word = NULL, .tagged = high | MS_STR_INLINE | ((uint64_t)n << MS_STR_INLINE_SHIFT)};
    __builtin_memcpy(&s.ptr_word, &low, sizeof low); /* the first word holds bytes, not an address */
    return s;
}

/* The shared static string of one ASCII byte, or of none. */
static inline MsStr ms_str_ascii_char(uint8_t b) { return (MsStr){.ptr_word = msrt_ascii_chars[b], .tagged = MS_STR_STATIC | 1}; }
static inline MsStr ms_str_empty(void) { return (MsStr){.ptr_word = msrt_ascii_chars[0], .tagged = MS_STR_STATIC}; }

/* A heap copy of the bytes, whatever their number. */
static inline MsStr ms_str_heap_copy(const uint8_t *p, size_t n) {
    MsStr s = ms_str_alloc(n);
    __builtin_memcpy(s.ptr_word, p, n);
    return ms_bytes_ascii(p, n) ? ms_str_with_ascii(s) : s;
}

/* New string from bytes: the shared statics for none or one ASCII byte, inline up to 15, else a heap copy. */
static inline MS_ALWAYS_INLINE MsStr ms_str_from_bytes(const uint8_t *p, size_t n) {
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
static inline MS_ALWAYS_INLINE MsStr ms_str_view_of(const uint8_t *p, size_t n) {
    if (n <= MS_STR_INLINE_MAX) {
        return ms_str_inline(p, n);
    }
    MsStr view = {.ptr_word = NULL, .tagged = MS_STR_VIEW | n};
    __builtin_memcpy(&view.ptr_word, &p, sizeof p); /* a view borrows bytes it never writes: no const in the field */
    return view;
}

/* A copy of s the caller owns: static and inline strings are the same two words; owned strings and views are
 * duplicated (inline when short). */
static inline MsStr ms_str_cloned(const MsStr *s) {
    uint64_t kind = s->tagged >> 62;
    if (kind == 1 || kind == 2) {
        return *s;
    }
    size_t n = ms_str_len(s);
    return n <= MS_STR_INLINE_MAX ? ms_str_inline(s->ptr_word, n) : ms_str_heap_copy(s->ptr_word, n);
}

/* The bytes of a string as a span. */
static inline MsBytes ms_str_bytes(const MsStr *s) { return ms_bytes_of(ms_str_data(s), ms_str_len(s)); }

/* Writes the two words as separate stores: a struct copy may become one 16-byte vector move, which stalls
 * reading words a callee just stored separately. */
static inline void ms_str_write(MsStr s, MsStr *out) {
    uint8_t *volatile *const pointer_word = &out->ptr_word;
    volatile uint64_t *const tag_word = &out->tagged;
    *pointer_word = s.ptr_word;
    *tag_word = s.tagged;
}

#endif

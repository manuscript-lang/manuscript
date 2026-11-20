/* String primitives that build strings: construction, copies, concatenation, trimmed views, slices and views.
 * Ported from crates/ms-rt/src/string.rs. Memory comes from the allocator's exported ABI (msrt_alloc,
 * msrt_free) until the allocator itself moves to C. */
#include "ms_rt/string.h"
#include "ms_rt/utf8.h"

extern uint8_t *msrt_alloc(size_t size);
extern void msrt_free(uint8_t *p);
extern _Noreturn void msrt_fault(const uint8_t *msg, size_t len);
/* Two bytes per ASCII character, the second a NUL: the one-character strings are static (defined with the
 * Rust string module for now). */
extern uint8_t msrt_ascii_chars[128][2];

#define STR_INLINE (UINT64_C(1) << 62)
#define STR_STATIC (UINT64_C(2) << 62)
#define STR_VIEW (UINT64_C(3) << 62)
#define MAX_BYTES ((size_t)1 << 30)

typedef unsigned __int128 u128;

static uint8_t empty_bytes[1] = {0};

static inline ms_str make_static(uint8_t *p, size_t len) { return (ms_str){p, len | STR_STATIC}; }

static inline ms_str make_empty(void) { return make_static(empty_bytes, 0); }

/* An inline string of len <= 15 bytes whose little-endian bits are `bits` (zero past len). */
static inline ms_str from_bits(u128 bits, size_t len) {
    return (ms_str){(uint8_t *)(uintptr_t)(uint64_t)bits, (uint64_t)(bits >> 64) | STR_INLINE | ((uint64_t)len << MS_STR_INLINE_SHIFT)};
}

static inline u128 pack(const uint8_t *p, size_t len) {
    uint8_t buf[16] = {0};
    __builtin_memcpy(buf, p, len);
    u128 v;
    __builtin_memcpy(&v, buf, sizeof v);
    return v;
}

static inline u128 bits_of(const ms_str *s) {
    if (ms_str_is_inline(s)) {
        return (u128)(uint64_t)(uintptr_t)s->ptr_word | ((u128)(s->tagged & ((UINT64_C(1) << MS_STR_INLINE_SHIFT) - 1)) << 64);
    }
    return pack(s->ptr_word, ms_str_len(s));
}

static inline bool owns(const ms_str *s) { return (s->tagged >> 62) == 0; }

static inline bool copies_bitwise(const ms_str *s) { return ((s->tagged >> 62) - 1) < 2; }

static bool bytes_ascii(const uint8_t *p, size_t n) { return ms_utf8_is_ascii(p, n); }

static bool str_ascii(const ms_str *s) {
    if (ms_str_is_inline(s)) {
        return (bits_of(s) & (((u128)UINT64_C(0x8080808080808080) << 64) | UINT64_C(0x8080808080808080))) == 0;
    }
    return (s->tagged & MS_STR_ASCII) != 0 || bytes_ascii(s->ptr_word, ms_str_len(s));
}

/* An owned, uninitialised string of len bytes, NUL terminated. */
static ms_str alloc_str(size_t len) {
    if (len > MAX_BYTES) {
        msrt_fault((const uint8_t *)"string: limit exceeded", 22);
    }
    uint8_t *p = msrt_alloc(len + 1);
    p[len] = 0;
    return (ms_str){p, len};
}

static inline ms_str with_ascii(ms_str s) {
    s.tagged |= MS_STR_ASCII;
    return s;
}

static ms_str heap_copy(const uint8_t *p, size_t n) {
    ms_str s = alloc_str(n);
    __builtin_memcpy(s.ptr_word, p, n);
    return bytes_ascii(p, n) ? with_ascii(s) : s;
}

static __attribute__((noinline)) ms_str owned_copy(const uint8_t *p, size_t n) {
    if (n <= MS_STR_INLINE_MAX) {
        return from_bits(pack(p, n), n);
    }
    return heap_copy(p, n);
}

static inline ms_str cloned(const ms_str *s) {
    if (copies_bitwise(s)) {
        return *s;
    }
    return owned_copy(ms_str_data(s), ms_str_len(s));
}

/* New string from bytes: empty and one-character ASCII results are static, up to 15 bytes inline. */
static inline ms_str from_bytes(const uint8_t *p, size_t n) {
    if (n == 0) {
        return make_empty();
    }
    if (n == 1 && p[0] < 0x80) {
        return make_static(msrt_ascii_chars[p[0]], 1);
    }
    return owned_copy(p, n);
}

/* len bytes at p inside another live string: an inline copy when they fit, otherwise a view. */
static inline ms_str view_of(const uint8_t *p, size_t len) {
    if (len <= MS_STR_INLINE_MAX) {
        return from_bits(pack(p, len), len);
    }
    return (ms_str){(uint8_t *)p, len | STR_VIEW};
}

void msrt_string_from_bytes(const uint8_t *ptr, size_t len, ms_str *out) { *out = from_bytes(ptr, len); }

void msrt_string_empty(ms_str *out) { *out = make_empty(); }

void msrt_string_clone(const ms_str *s, ms_str *out) { *out = cloned(s); }

void msrt_str_copy(const uint8_t *ptr, size_t tagged, ms_str *out) { *out = owned_copy(ptr, tagged & MS_STR_LEN_MASK); }

void msrt_str_free(uint8_t *ptr) { msrt_free(ptr); }

void msrt_string_free(const ms_str *s) {
    if (owns(s)) {
        msrt_free(s->ptr_word);
    }
}

void msrt_string_concat(const ms_str *a, const ms_str *b, ms_str *out) {
    size_t la = ms_str_len(a), lb = ms_str_len(b);
    if (lb == 0) {
        *out = cloned(a);
        return;
    }
    if (la == 0) {
        *out = cloned(b);
        return;
    }
    if (la + lb <= MS_STR_INLINE_MAX) {
        *out = from_bits(bits_of(a) | (bits_of(b) << (8 * la)), la + lb);
        return;
    }
    ms_str s = alloc_str(la + lb);
    __builtin_memcpy(s.ptr_word, ms_str_data(a), la);
    __builtin_memcpy(s.ptr_word + la, ms_str_data(b), lb);
    *out = (str_ascii(a) && str_ascii(b)) ? with_ascii(s) : s;
}

/* The parts joined with a single allocation. */
static void concat_parts(const ms_str *const *parts, size_t count, ms_str *out) {
    size_t total = 0;
    for (size_t i = 0; i < count; i++) {
        total += ms_str_len(parts[i]);
    }
    if (total <= MS_STR_INLINE_MAX) {
        u128 acc = 0;
        size_t at = 0;
        for (size_t i = 0; i < count; i++) {
            acc |= bits_of(parts[i]) << (8 * at);
            at += ms_str_len(parts[i]);
        }
        *out = from_bits(acc, total);
        return;
    }
    ms_str s = alloc_str(total);
    uint8_t *dst = s.ptr_word;
    for (size_t i = 0; i < count; i++) {
        size_t n = ms_str_len(parts[i]);
        __builtin_memcpy(dst, ms_str_data(parts[i]), n);
        dst += n;
    }
    *out = s;
}

void msrt_string_concat3(const ms_str *a, const ms_str *b, const ms_str *c, ms_str *out) {
    const ms_str *p[] = {a, b, c};
    concat_parts(p, 3, out);
}

void msrt_string_concat4(const ms_str *a, const ms_str *b, const ms_str *c, const ms_str *d, ms_str *out) {
    const ms_str *p[] = {a, b, c, d};
    concat_parts(p, 4, out);
}

void msrt_string_concat5(const ms_str *a, const ms_str *b, const ms_str *c, const ms_str *d, const ms_str *e, ms_str *out) {
    const ms_str *p[] = {a, b, c, d, e};
    concat_parts(p, 5, out);
}

void msrt_string_concat6(const ms_str *a, const ms_str *b, const ms_str *c, const ms_str *d, const ms_str *e, const ms_str *f,
                         ms_str *out) {
    const ms_str *p[] = {a, b, c, d, e, f};
    concat_parts(p, 6, out);
}

/* ---- trimmed views ---- */

static inline bool ascii_space(uint8_t b) { return b == ' ' || (b >= 9 && b <= 13); }

static void trim_range_scan(const uint8_t *t, size_t n, bool start, bool end, size_t *ra, size_t *rb) {
    size_t a = 0, b = n;
    if (start) {
        while (a < b) {
            if (t[a] < 0x80) {
                if (!ascii_space(t[a])) {
                    break;
                }
                a++;
                continue;
            }
            ms_rune r = ms_utf8_decode(t + a, b - a);
            if (!ms_utf8_is_space(r.rune)) {
                break;
            }
            a += r.width;
        }
    }
    if (end) {
        while (b > a) {
            if (t[b - 1] < 0x80) {
                if (!ascii_space(t[b - 1])) {
                    break;
                }
                b--;
                continue;
            }
            ms_rune r = ms_utf8_decode_last(t + a, b - a);
            if (!ms_utf8_is_space(r.rune)) {
                break;
            }
            b -= r.width;
        }
    }
    *ra = a;
    *rb = b;
}

/* Text whose first and last bytes (the ends asked for) are ASCII and not white space is decided by those two bytes. */
static inline void trim_view(const ms_str *s, bool start, bool end, ms_str *out) {
    const uint8_t *t = ms_str_data(s);
    size_t n = ms_str_len(s), a = 0, b = n;
    bool keeps = false;
    if (n != 0) {
        uint8_t first = t[0], last = t[n - 1];
        keeps = (!start || (first < 0x80 && !ascii_space(first))) && (!end || (last < 0x80 && !ascii_space(last)));
    }
    if (!keeps) {
        trim_range_scan(t, n, start, end, &a, &b);
    }
    if (a == b) {
        *out = make_empty(); /* an empty result borrows nothing */
    } else if (b - a == n && copies_bitwise(s)) {
        *out = *s;
    } else {
        *out = view_of(t + a, b - a);
    }
}

void msrt_string_trim_view(const ms_str *s, ms_str *out) { trim_view(s, true, true, out); }

void msrt_string_trim_start_view(const ms_str *s, ms_str *out) { trim_view(s, true, false, out); }

void msrt_string_trim_end_view(const ms_str *s, ms_str *out) { trim_view(s, false, true, out); }

/* ---- slices and views ---- */

static inline bool is_boundary(const uint8_t *t, size_t n, size_t i) { return i == n || (t[i] & 0xC0) != 0x80; }

void msrt_string_slice(const ms_str *s, int64_t start, int64_t end, ms_str *out) {
    const uint8_t *t = ms_str_data(s);
    int64_t n = (int64_t)ms_str_len(s);
    int64_t ra = start < 0 ? n + start : start;
    int64_t rb = end < 0 ? n + end : end;
    size_t a = (size_t)(ra < 0 ? 0 : ra > n ? n : ra);
    size_t b = (size_t)(rb < 0 ? 0 : rb > n ? n : rb);
    while (a < b && !is_boundary(t, (size_t)n, a)) {
        a++;
    }
    while (b > a && !is_boundary(t, (size_t)n, b)) {
        b--;
    }
    if (a >= b) {
        *out = make_empty();
    } else if (a == 0 && b == (size_t)n) {
        *out = cloned(s);
    } else {
        *out = from_bytes(t + a, b - a);
    }
}

/* Decimal digits of v at the end of buf; returns the start. */
static char *format_i64(int64_t v, char *end) {
    uint64_t u = v < 0 ? (uint64_t)0 - (uint64_t)v : (uint64_t)v;
    char *p = end;
    do {
        *--p = (char)('0' + u % 10);
        u /= 10;
    } while (u != 0);
    if (v < 0) {
        *--p = '-';
    }
    return p;
}

static _Noreturn void view_fault(int64_t start, int64_t end) {
    static const char head[] = "String.view: bounds ";
    static const char tail[] = " are outside the text or inside a scalar";
    char buf[sizeof head + sizeof tail + 48];
    size_t at = 0;
    __builtin_memcpy(buf, head, sizeof head - 1);
    at += sizeof head - 1;
    char num[24];
    char *p = format_i64(start, num + sizeof num);
    __builtin_memcpy(buf + at, p, (size_t)(num + sizeof num - p));
    at += (size_t)(num + sizeof num - p);
    buf[at++] = '.';
    buf[at++] = '.';
    p = format_i64(end, num + sizeof num);
    __builtin_memcpy(buf + at, p, (size_t)(num + sizeof num - p));
    at += (size_t)(num + sizeof num - p);
    __builtin_memcpy(buf + at, tail, sizeof tail - 1);
    at += sizeof tail - 1;
    msrt_fault((const uint8_t *)buf, at);
}

void msrt_string_view(const ms_str *s, int64_t start, int64_t end, ms_str *out) {
    const uint8_t *t = ms_str_data(s);
    int64_t n = (int64_t)ms_str_len(s);
    int64_t a = start < 0 ? n + start : start;
    int64_t b = end < 0 ? n + end : end;
    if (a < 0 || b < a || b > n || !is_boundary(t, (size_t)n, (size_t)a) || !is_boundary(t, (size_t)n, (size_t)b)) {
        view_fault(start, end);
    }
    *out = a == b ? make_empty() : view_of(t + a, (size_t)(b - a));
}

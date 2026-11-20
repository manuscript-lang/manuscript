/* Splitting and replacing strings. Ported from crates/ms-rt/src/string.rs (split, split_view, split_view_into,
 * split_first, replace, replace_first, replace_take); the search is ms_needle_find from runtime/core/search.c. */
#include "ms_rt/search.h"
#include "ms_rt/strbuild.h"
#include "ms_rt/utf8.h"
#include "ms_rt/vec.h"

#define ELEM sizeof(ms_str)
/* Texts up to this many bytes split at a one-byte separator in one pass over their words: a record's fields
 * are a few bytes apart, where a search per piece costs more than the scan. */
#define ONE_PASS_SPLIT 128
/* Room for the pieces of a split read in place (the frame buffer of msrt_string_split_view_into). */
#define SPLIT_BUF 8

/* How a piece is made: a copy (owned or inline), or a view of the text (only for texts that outlive it). */
typedef enum { PIECE_COPY, PIECE_VIEW } piece_mode;

static inline __attribute__((always_inline)) ms_str piece_of(piece_mode mode, const uint8_t *p, size_t n) {
    if (mode == PIECE_VIEW && n > 1) {
        return ms_str_view_of(p, n);
    }
    if (mode == PIECE_VIEW && n == 1 && p[0] >= 0x80) {
        return ms_str_view_of(p, n);
    }
    return ms_str_from_bytes(p, n);
}

static inline __attribute__((always_inline)) void push_str(ms_vec *v, ms_str s) {
    if (v->len == v->cap) {
        size_t cap = v->cap == 0 ? 4 : v->cap * 2;
        v->ptr = v->ptr ? msrt_realloc(v->ptr, cap * ELEM) : msrt_alloc(cap * ELEM);
        v->cap = cap;
    }
    ((ms_str *)v->ptr)[v->len++] = s;
}

/* push_str, or with `fixed` (the list is a caller's buffer) false when it is full. */
static inline __attribute__((always_inline)) bool put(ms_vec *v, ms_str s, bool fixed) {
    if (fixed && v->len == v->cap) {
        return false;
    }
    push_str(v, s);
    return true;
}

/* The pieces of text between bytes equal to sep, found eight bytes at a time and taken from each word's mask.
 * False when a fixed list fills. */
static inline __attribute__((always_inline)) bool split_bytes_once(const uint8_t *text, size_t n, uint8_t sep, ms_vec *v, piece_mode mode, bool fixed) {
    const uint64_t low = UINT64_C(0x7f7f7f7f7f7f7f7f), high = UINT64_C(0x8080808080808080);
    uint64_t pat = UINT64_C(0x0101010101010101) * sep;
    size_t start = 0, i = 0;
    for (; i + 8 <= n; i += 8) {
        uint64_t x = ms_load64(text + i) ^ pat;
        /* A byte of x is zero exactly where the text has sep; this mask has no false bytes above a match. */
        uint64_t mask = ~(((x & low) + low) | x) & high;
        while (mask != 0) {
            size_t at = i + (size_t)__builtin_ctzll(mask) / 8;
            if (!put(v, piece_of(mode, text + start, at - start), fixed)) {
                return false;
            }
            start = at + 1;
            mask &= mask - 1;
        }
    }
    for (; i < n; i++) {
        if (text[i] == sep) {
            if (!put(v, piece_of(mode, text + start, i - start), fixed)) {
                return false;
            }
            start = i + 1;
        }
    }
    return put(v, piece_of(mode, text + start, n - start), fixed);
}

static inline __attribute__((always_inline)) void split_into(const ms_str *s, const ms_str *sep, ms_vec *out, piece_mode mode) {
    const uint8_t *text = ms_str_data(s), *sp = ms_str_data(sep);
    size_t n = ms_str_len(s), m = ms_str_len(sep);
    ms_vec v = {0, 0, 0};
    if (m == 0) {
        /* Split after each scalar: the piece count is known, so the list is sized once. */
        size_t count = ms_utf8_count(text, n);
        if (count > 0) {
            v.ptr = msrt_alloc(count * ELEM);
            v.cap = count;
        }
        for (size_t i = 0; i < n;) {
            size_t w = ms_utf8_decode(text + i, n - i).width;
            push_str(&v, piece_of(mode, text + i, w));
            i += w;
        }
        *out = v;
        return;
    }
    /* Most splits are of records with several fields: room for eight pieces (never more than the text can hold)
     * saves the grow-and-copy of the usual seven, without sizing a two-piece split for eight. */
    size_t first = n / m + 1;
    if (first > 8) {
        first = 8;
    }
    v.ptr = msrt_alloc(first * ELEM);
    v.cap = first;
    if (m == 1 && n <= ONE_PASS_SPLIT) {
        split_bytes_once(text, n, sp[0], &v, mode, false);
        *out = v;
        return;
    }
    ms_needle nd = ms_needle_for(sp, m, n);
    size_t start = 0;
    for (;;) {
        size_t p = ms_needle_find(&nd, text + start, n - start);
        if (p == SIZE_MAX) {
            push_str(&v, piece_of(mode, text + start, n - start));
            break;
        }
        push_str(&v, piece_of(mode, text + start, p));
        start += p + m;
    }
    *out = v;
}

void msrt_string_split(const ms_str *s, const ms_str *sep, ms_vec *out) { split_into(s, sep, out, PIECE_COPY); }

void msrt_string_split_view(const ms_str *s, const ms_str *sep, ms_vec *out) { split_into(s, sep, out, PIECE_VIEW); }

void msrt_string_split_view_into(const ms_str *s, const ms_str *sep, ms_str *buf, ms_vec *out) {
    size_t n = ms_str_len(s);
    if (ms_str_len(sep) == 1 && n <= ONE_PASS_SPLIT) {
        ms_vec v = {(uint8_t *)buf, 0, SPLIT_BUF};
        if (split_bytes_once(ms_str_data(s), n, ms_str_data(sep)[0], &v, PIECE_VIEW, true)) {
            v.cap = 0;
            *out = v;
            return;
        }
    }
    split_into(s, sep, out, PIECE_VIEW);
}

void msrt_string_split_first(const ms_str *s, const ms_str *sep, ms_str *out) {
    const uint8_t *text = ms_str_data(s);
    size_t n = ms_str_len(s), m = ms_str_len(sep), end;
    if (m == 0) {
        /* Split after each scalar: the first piece is the first scalar. */
        if (n == 0) {
            msrt_index_fault(0, 0);
        }
        end = ms_utf8_decode(text, n).width;
    } else {
        ms_needle nd = ms_needle_for(ms_str_data(sep), m, n);
        end = ms_needle_find(&nd, text, n);
        if (end == SIZE_MAX) {
            end = n;
        }
    }
    ms_str_write(piece_of(PIECE_VIEW, text, end), out);
}

/* The string of len bytes written by fill: inline when it fits, otherwise one allocation. ascii says fill
 * writes only ASCII bytes. */
typedef void (*fill_fn)(uint8_t *dst, const void *ctx);

static ms_str build_exact(size_t len, bool ascii, fill_fn fill, const void *ctx) {
    if (len <= MS_STR_INLINE_MAX) {
        uint8_t small[MS_STR_INLINE_MAX + 1];
        fill(small, ctx);
        return ms_str_from_bytes(small, len);
    }
    ms_str r = ms_str_alloc(len);
    fill(r.ptr_word, ctx);
    return ascii ? ms_str_with_ascii(r) : r;
}

typedef struct replace_ctx {
    const uint8_t *text, *old, *new_;
    size_t n, old_len, new_len, matches;
    const ms_needle *nd;
} replace_ctx;

/* The text with its first `matches` occurrences of a non-empty old replaced. */
static void fill_replaced(uint8_t *dst, const void *c) {
    const replace_ctx *x = c;
    size_t i = 0;
    for (size_t k = 0; k < x->matches; k++) {
        size_t p = ms_needle_find(x->nd, x->text + i, x->n - i);
        if (p == SIZE_MAX) {
            p = 0;
        }
        ms_copy_bytes(dst, x->text + i, p);
        dst += p;
        ms_copy_bytes(dst, x->new_, x->new_len);
        dst += x->new_len;
        i += p + x->old_len;
    }
    __builtin_memcpy(dst, x->text + i, x->n - i);
}

/* The text with new inserted before every scalar and at the end. */
static void fill_inserted(uint8_t *dst, const void *c) {
    const replace_ctx *x = c;
    size_t i = 0;
    for (;;) {
        ms_copy_bytes(dst, x->new_, x->new_len);
        dst += x->new_len;
        if (i >= x->n) {
            return;
        }
        size_t w = ms_utf8_decode(x->text + i, x->n - i).width;
        ms_copy_bytes(dst, x->text + i, w);
        dst += w;
        i += w;
    }
}

static size_t count_matches(const ms_needle *nd, const uint8_t *text, size_t n) {
    size_t count = 0, i = 0;
    while (n - i >= nd->len) {
        size_t p = ms_needle_find(nd, text + i, n - i);
        if (p == SIZE_MAX) {
            break;
        }
        count++;
        i += p + nd->len;
    }
    return count;
}

void msrt_string_replace_first(const ms_str *s, const ms_str *old, const ms_str *new_, ms_str *out) {
    const uint8_t *text = ms_str_data(s), *o = ms_str_data(old), *r = ms_str_data(new_);
    size_t n = ms_str_len(s), m = ms_str_len(old), k = ms_str_len(new_), at = 0;
    /* The empty pattern matches at the first scalar boundary, before any input bytes. */
    if (m != 0) {
        at = ms_find(text, n, o, m);
        if (at == SIZE_MAX) {
            ms_str_write(ms_str_cloned(s), out);
            return;
        }
    }
    size_t total = n - m + k;
    uint8_t small[MS_STR_INLINE_MAX + 1];
    ms_str heap = {0, 0};
    uint8_t *start = small;
    if (total > MS_STR_INLINE_MAX) {
        heap = ms_str_alloc(total);
        start = heap.ptr_word;
    }
    ms_copy_bytes(start, text, at);
    ms_copy_bytes(start + at, r, k);
    ms_copy_bytes(start + at + k, text + at + m, n - at - m);
    ms_str_write(total > MS_STR_INLINE_MAX ? heap : ms_str_from_bytes(small, total), out);
}

/* Replaces every occurrence of a non-empty old by a new no longer than it, in one search pass: the result cannot
 * exceed the text, so it is written into a text-sized block and trimmed afterwards. */
static ms_str replace_shrinking(const ms_str *s, const uint8_t *o, size_t m, const uint8_t *r, size_t k) {
    const uint8_t *text = ms_str_data(s);
    size_t n = ms_str_len(s);
    ms_needle nd = ms_needle_for(o, m, n);
    size_t at = ms_needle_find(&nd, text, n);
    if (at == SIZE_MAX) {
        return ms_str_cloned(s); /* nothing to replace */
    }
    uint8_t *buf = msrt_alloc(n + 1), *dst = buf;
    size_t i = 0;
    for (;;) {
        ms_copy_bytes(dst, text + i, at);
        dst += at;
        ms_copy_bytes(dst, r, k);
        dst += k;
        i += at + m;
        at = ms_needle_find(&nd, text + i, n - i);
        if (at == SIZE_MAX) {
            break;
        }
    }
    size_t rest = n - i;
    __builtin_memcpy(dst, text + i, rest);
    size_t len = (size_t)(dst + rest - buf);
    if (len <= MS_STR_INLINE_MAX) {
        ms_str res = ms_str_from_bytes(buf, len);
        msrt_free(buf);
        return res;
    }
    /* Text known to be ASCII stays so when the replacement is. */
    bool ascii = (s->tagged & MS_STR_ASCII) != 0 && !ms_str_is_inline(s) && ms_bytes_ascii(r, k);
    ms_str res = ms_str_owned(msrt_realloc(buf, len + 1), len);
    return ascii ? ms_str_with_ascii(res) : res;
}

void msrt_string_replace(const ms_str *s, const ms_str *old, const ms_str *new_, ms_str *out) {
    const uint8_t *text = ms_str_data(s), *o = ms_str_data(old), *r = ms_str_data(new_);
    size_t n = ms_str_len(s), m = ms_str_len(old), k = ms_str_len(new_);
    if (m != 0 && k <= m) {
        ms_str_write(replace_shrinking(s, o, m, r, k), out);
        return;
    }
    ms_needle nd = {o, m, 0, false};
    size_t count;
    if (m == 0) {
        count = ms_utf8_count(text, n) + 1;
    } else {
        nd = ms_needle_for(o, m, n);
        count = count_matches(&nd, text, n);
    }
    unsigned __int128 total = (unsigned __int128)n + (unsigned __int128)count * k - (unsigned __int128)count * m;
    if (total > MS_STR_MAX_BYTES) {
        ms_limit_fault();
    }
    if (count == 0) {
        ms_str_write(ms_str_cloned(s), out); /* nothing to replace */
        return;
    }
    bool ascii = ms_str_is_ascii(s) && ms_str_is_ascii(new_);
    replace_ctx ctx = {text, o, r, n, m, k, count, &nd};
    ms_str_write(build_exact((size_t)total, ascii, m == 0 ? fill_inserted : fill_replaced, &ctx), out);
}

/* replace of a string that dies at the call: a replacement no longer than its match is written over the same
 * allocation, left to right, so the write position never passes the read position. Others build the result as
 * replace does and free the input. */
void msrt_string_replace_take(ms_str *s, const ms_str *old, const ms_str *new_, ms_str *out) {
    const uint8_t *o = ms_str_data(old), *r = ms_str_data(new_);
    size_t m = ms_str_len(old), k = ms_str_len(new_);
    if (!(s->tagged < MS_STR_INLINE && m != 0 && k <= m)) {
        msrt_string_replace(s, old, new_, out);
        ms_str_release(s);
        return;
    }
    uint8_t *ptr = s->ptr_word;
    size_t len = ms_str_len(s), rd = 0, w = 0;
    bool ascii = (s->tagged & MS_STR_ASCII) != 0 && ms_bytes_ascii(r, k);
    ms_needle nd = ms_needle_for(o, m, len);
    for (;;) {
        size_t p = ms_needle_find(&nd, ptr + rd, len - rd);
        if (p == SIZE_MAX) {
            break;
        }
        __builtin_memmove(ptr + w, ptr + rd, p);
        w += p;
        __builtin_memcpy(ptr + w, r, k);
        w += k;
        rd += p + m;
    }
    if (rd == 0) {
        ms_str_write(*s, out); /* nothing to replace: the input is the result */
        return;
    }
    __builtin_memmove(ptr + w, ptr + rd, len - rd);
    size_t total = w + len - rd;
    if (total <= MS_STR_INLINE_MAX) {
        ms_str res = ms_str_from_bytes(ptr, total);
        msrt_free(ptr);
        ms_str_write(res, out);
        return;
    }
    ms_str res = ms_str_owned(ptr, total);
    ms_str_write(ascii ? ms_str_with_ascii(res) : res, out);
}

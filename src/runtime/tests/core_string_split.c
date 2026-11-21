/* Unit test for src/runtime/core/string_split.c: split and replace against naive references on random text over a
 * small alphabet (ASCII and multi-byte), with strings of every kind (static, inline, owned, view).
 * `make c-test` builds it with ASan and UBSan. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ms_rt/safe.h"
#include "ms_rt/search.h"
#include "ms_rt/strbuild.h"
#include "ms_rt/utf8.h"

static void check(bool ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "core_string_split.c:%d: %s\n", line, text);
        abort();
    }
}
#define CHECK(cond) check((cond), __LINE__, #cond)

static uint64_t seed = 0x9E3779B97F4A7C15ULL;
static uint32_t rnd(void) {
    seed ^= seed << 13;
    seed ^= seed >> 7;
    seed ^= seed << 17;
    return (uint32_t)(seed >> 16);
}

static const char *ALPHA[] = {"a", "b", "ab", " ", "é", "\xe2\x82\xac", "\xff"};

static size_t random_text(uint8_t *buf, size_t max_pieces, size_t alpha) {
    size_t n = 0, pieces = rnd() % (max_pieces + 1);
    for (size_t i = 0; i < pieces; i++) {
        const char *p = ALPHA[rnd() % alpha];
        size_t l = strlen(p);
        memcpy(buf + n, p, l);
        n += l;
    }
    return n;
}

/* A string of the given bytes in a kind chosen by `kind` (heap-backed kinds own `*mem`). */
static MsStr make(const uint8_t *p, size_t n, int kind, uint8_t **mem) {
    *mem = NULL;
    if (kind == 0 || n == 0) {
        return ms_str_from_bytes(p, n);
    }
    if (kind == 1) { /* a view of a private copy */
        *mem = malloc(n + 1);
        memcpy(*mem, p, n);
        (*mem)[n] = 0;
        return (MsStr){.bytes = *mem, .tagged = MS_STR_VIEW | n};
    }
    return ms_str_heap_copy(p, n); /* owned, whatever its length */
}

static bool same(const MsStr *s, const uint8_t *p, size_t n) {
    return ms_str_len(s) == n && memcmp(ms_str_data(s), p, n) == 0;
}

/* Inline strings keep the bytes past their length zero, so equal inline strings have equal words. */
static void check_shape(const MsStr *s) {
    if (ms_str_is_inline(s)) {
        uint8_t raw[16];
        memcpy(raw, &s->ptr_word, 8);
        uint64_t hi = s->tagged & ((UINT64_C(1) << MS_STR_INLINE_SHIFT) - 1);
        memcpy(raw + 8, &hi, 8);
        for (size_t i = ms_str_len(s); i < 16; i++) {
            CHECK(raw[i] == 0);
        }
    }
    if (s->tagged < MS_STR_INLINE) {
        CHECK(ms_str_len(s) > MS_STR_INLINE_MAX);
        CHECK(ms_str_data(s)[ms_str_len(s)] == 0);
        if (s->tagged & MS_STR_ASCII) {
            CHECK(ms_bytes_ascii(ms_str_data(s), ms_str_len(s)));
        }
    }
}

static size_t naive_find(const uint8_t *h, size_t n, const uint8_t *x, size_t m) {
    for (size_t i = 0; i + m <= n; i++) {
        if (memcmp(h + i, x, m) == 0) {
            return i;
        }
    }
    return SIZE_MAX;
}

/* Reference split: pieces as (offset, length) pairs. */
static size_t naive_split(const uint8_t *t, size_t n, const uint8_t *sep, size_t m, size_t *off, size_t *len) {
    size_t k = 0, pos = 0;
    if (m == 0) {
        while (pos < n) {
            size_t w = ms_utf8_decode(t + pos, n - pos).width;
            off[k] = pos;
            len[k++] = w;
            pos += w;
        }
        return k;
    }
    for (;;) {
        size_t p = naive_find(t + pos, n - pos, sep, m);
        if (p == SIZE_MAX) {
            off[k] = pos;
            len[k++] = n - pos;
            return k;
        }
        off[k] = pos;
        len[k++] = p;
        pos += p + m;
    }
}

static void free_list(MsVec *v) {
    for (size_t i = 0; i < v->len; i++) {
        check_shape(&((MsStr *)v->ptr)[i]);
        ms_str_release(&((MsStr *)v->ptr)[i]);
    }
    if (v->cap) {
        msrt_free(v->ptr);
    }
}

static size_t naive_replace(const uint8_t *t, size_t n, const uint8_t *o, size_t m, const uint8_t *r, size_t k, uint8_t *out) {
    size_t w = 0, pos = 0;
    if (m == 0) {
        for (;;) {
            memcpy(out + w, r, k);
            w += k;
            if (pos >= n) {
                return w;
            }
            size_t c = ms_utf8_decode(t + pos, n - pos).width;
            memcpy(out + w, t + pos, c);
            w += c;
            pos += c;
        }
    }
    for (;;) {
        size_t p = naive_find(t + pos, n - pos, o, m);
        if (p == SIZE_MAX) {
            memcpy(out + w, t + pos, n - pos);
            return w + n - pos;
        }
        memcpy(out + w, t + pos, p);
        w += p;
        memcpy(out + w, r, k);
            w += k;
        pos += p + m;
    }
}

int main(void) {
    static uint8_t text[4096], sep[64], rep[64], want[16384];
    static size_t off[4096], len[4096];
    for (int iter = 0; iter < 60000; iter++) {
        size_t alpha = 2 + rnd() % 5;
        size_t n = random_text(text, iter % 7 == 0 ? 200 : 20, alpha);
        size_t m = random_text(sep, 3, alpha), k = random_text(rep, 3, alpha);
        uint8_t *m1, *m2, *m3;
        int kind = (int)(rnd() % 3);
        MsStr s = make(text, n, kind, &m1), sp = make(sep, m, (int)(rnd() % 3), &m2), rp = make(rep, k, (int)(rnd() % 3), &m3);

        size_t cnt = naive_split(text, n, sep, m, off, len);
        for (int mode = 0; mode < 3; mode++) {
            MsVec v;
            MsStr frame[8];
            if (mode == 0) {
                msrt_string_split(&s, &sp, &v);
            } else if (mode == 1) {
                msrt_string_split_view(&s, &sp, &v);
            } else {
                msrt_string_split_view_into(&s, &sp, frame, &v);
            }
            CHECK(v.len == cnt);
            for (size_t i = 0; i < cnt; i++) {
                CHECK(same(&((MsStr *)v.ptr)[i], text + off[i], len[i]));
            }
            if (mode == 2 && v.cap == 0 && v.ptr) {
                CHECK(v.ptr == (void *)frame && cnt <= 8);
                for (size_t i = 0; i < v.len; i++) {
                    check_shape(&((MsStr *)v.ptr)[i]);
                }
            } else {
                free_list(&v);
            }
        }
        if (n > 0 || m > 0) {
            MsStr first;
            if (n == 0 && m != 0) {
                /* the first piece of an empty text is the empty string */
            }
            if (!(n == 0 && m == 0)) {
                msrt_string_split_first(&s, &sp, &first);
                CHECK(same(&first, text + off[0], len[0]));
                check_shape(&first);
            }
        }

        size_t wn = naive_replace(text, n, sep, m, rep, k, want);
        MsStr out;
        msrt_string_replace(&s, &sp, &rp, &out);
        CHECK(same(&out, want, wn));
        check_shape(&out);
        ms_str_release(&out);

        /* replace_first: the first match, or the empty pattern before everything. */
        size_t at = m == 0 ? 0 : naive_find(text, n, sep, m);
        msrt_string_replace_first(&s, &sp, &rp, &out);
        if (at == SIZE_MAX) {
            CHECK(same(&out, text, n));
        } else {
            memcpy(want, text, at);
            memcpy(want + at, rep, k);
            memcpy(want + at + k, text + at + m, n - at - m);
            CHECK(same(&out, want, n - m + k));
        }
        check_shape(&out);
        ms_str_release(&out);

        /* replace_take consumes an owned copy. */
        MsStr own = ms_str_heap_copy(text, n);
        if (n <= MS_STR_INLINE_MAX) {
            ms_str_release(&own);
            own = ms_str_from_bytes(text, n);
        }
        msrt_string_replace_take(&own, &sp, &rp, &out);
        wn = naive_replace(text, n, sep, m, rep, k, want);
        CHECK(same(&out, want, wn));
        check_shape(&out);
        ms_str_release(&out);

        ms_str_release(&s);
        ms_str_release(&sp);
        ms_str_release(&rp);
        free(m1);
        free(m2);
        free(m3);
    }

    /* Long texts: the prepared search path (128 bytes or more) and a result over the inline size. */
    enum { BIG = 1 << 20 };
    uint8_t *big = malloc(BIG);
    for (size_t i = 0; i < BIG; i++) {
        big[i] = (uint8_t)("abcdefgh, \n"[rnd() % 11]);
    }
    const uint8_t pat[] = "abc, d";
    MsStr s = ms_str_heap_copy(big, BIG), sp = ms_str_from_bytes(pat, sizeof pat - 1), rp = ms_str_from_bytes((const uint8_t *)"XYZ12345", 8);
    MsVec v;
    msrt_string_split(&s, &sp, &v);
    CHECK(v.len == ms_count(big, BIG, pat, sizeof pat - 1) + 1);
    free_list(&v);
    uint8_t *ref = malloc(BIG * 2), *got_src = malloc(BIG);
    MsStr out;
    for (int shrink = 0; shrink < 2; shrink++) {
        MsStr r = shrink ? ms_str_from_bytes((const uint8_t *)"Q", 1) : rp;
        size_t rl = ms_str_len(&r), wn = naive_replace(big, BIG, pat, sizeof pat - 1, ms_str_data(&r), rl, ref);
        msrt_string_replace(&s, &sp, &r, &out);
        CHECK(same(&out, ref, wn));
        check_shape(&out);
        ms_str_release(&out);
        memcpy(got_src, big, BIG);
        MsStr own = ms_str_heap_copy(got_src, BIG);
        msrt_string_replace_take(&own, &sp, &r, &out);
        CHECK(same(&out, ref, wn));
        check_shape(&out);
        ms_str_release(&out);
    }
    free(ref);
    free(got_src);
    free(big);
    ms_str_release(&s);
    ms_str_release(&sp);
    puts("core_string_split: ok");
    return 0;
}

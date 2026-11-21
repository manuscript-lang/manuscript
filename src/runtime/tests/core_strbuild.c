/* Unit test for src/runtime/core/strbuild.c; `make c-test` builds it with ASan and UBSan. Fault and the ASCII table come from support/rt_stubs.c. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "append.h"
#include "ms_rt/string.h"
#include "support/rt_stubs.h"

static void check(bool ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "core_strbuild.c:%d: %s\n", line, text);
        abort();
    }
}
#define CHECK(cond) check((cond), __LINE__, #cond)

static MsStr mk(const char *t) {
    MsStr s;
    msrt_string_from_bytes((const uint8_t *)t, strlen(t), &s);
    return s;
}
static bool is(const MsStr *s, const char *t) {
    return ms_str_len(s) == strlen(t) && memcmp(ms_str_data(s), t, strlen(t)) == 0;
}
static void drop(MsStr *s) { msrt_string_free(s); }

int main(void) {
    const char *lens[] = {"", "a", "ab", "fifteen-bytes!!", "sixteen-bytes!!!", "a string well past the inline size, with é"};
    /* from_bytes / clone / copy keep the bytes at every size. */
    for (size_t i = 0; i < sizeof lens / sizeof *lens; i++) {
        MsStr s = mk(lens[i]), c;
        CHECK(is(&s, lens[i]));
        msrt_string_clone(&s, &c);
        CHECK(is(&c, lens[i]));
        MsStr d = c;
        if (!ms_str_is_inline(&s)) { /* msrt_str_copy takes an owned string or a view, never an inline one */
            msrt_str_copy(ms_str_data(&s), s.tagged, &d);
            CHECK(is(&d, lens[i]));
        }
        CHECK(ms_str_is_inline(&s) == (strlen(lens[i]) >= 2 && strlen(lens[i]) <= 15));
        drop(&s); drop(&c); drop(&d);
    }
    /* concat at every pair of sizes, 3 to 6 parts */
    for (size_t i = 0; i < sizeof lens / sizeof *lens; i++) {
        for (size_t j = 0; j < sizeof lens / sizeof *lens; j++) {
            MsStr a = mk(lens[i]), b = mk(lens[j]), r;
            char want[1024];
            snprintf(want, sizeof want, "%s%s", lens[i], lens[j]);
            msrt_string_concat(&a, &b, &r);
            CHECK(is(&r, want));
            drop(&r);
            msrt_string_concat3(&a, &b, &a, &r);
            snprintf(want, sizeof want, "%s%s%s", lens[i], lens[j], lens[i]);
            CHECK(is(&r, want));
            drop(&r);
            msrt_string_concat6(&a, &b, &a, &b, &a, &b, &r);
            snprintf(want, sizeof want, "%s%s%s%s%s%s", lens[i], lens[j], lens[i], lens[j], lens[i], lens[j]);
            CHECK(is(&r, want));
            drop(&r); drop(&a); drop(&b);
        }
    }
    /* trim views */
    struct { const char *in, *both, *start, *end; } trims[] = {
        {"", "", "", ""},
        {"  hi  ", "hi", "hi  ", "  hi"},
        {"\t\n x \r\v\f", "x", "x \r\v\f", "\t\n x"},
        {"   ", "", "", ""},
        {"\xc2\xa0\xe2\x80\x83 text with nbsp \xe3\x80\x80", "text with nbsp", "text with nbsp \xe3\x80\x80", "\xc2\xa0\xe2\x80\x83 text with nbsp"},
        {"no trimming needed here at all", "no trimming needed here at all", "no trimming needed here at all", "no trimming needed here at all"},
        {"\xff bad \xff", "\xff bad \xff", "\xff bad \xff", "\xff bad \xff"},
    };
    for (size_t i = 0; i < sizeof trims / sizeof *trims; i++) {
        MsStr s = mk(trims[i].in), v;
        msrt_string_trim_view(&s, &v);
        CHECK(is(&v, trims[i].both));
        msrt_string_trim_start_view(&s, &v);
        CHECK(is(&v, trims[i].start));
        msrt_string_trim_end_view(&s, &v);
        CHECK(is(&v, trims[i].end));
        drop(&s);
    }
    /* slice and view, with negative, clamped and mid-scalar bounds */
    MsStr s = mk("héllo, wörld of long text");
    MsStr r;
    msrt_string_slice(&s, 0, 100, &r);
    CHECK(is(&r, "héllo, wörld of long text"));
    drop(&r);
    msrt_string_slice(&s, 2, -1, &r); /* start inside é moves forward */
    CHECK(is(&r, "llo, wörld of long tex"));
    drop(&r);
    msrt_string_slice(&s, -4, INT64_MAX, &r);
    CHECK(is(&r, "text"));
    drop(&r);
    msrt_string_slice(&s, 5, 3, &r);
    CHECK(is(&r, ""));
    msrt_string_slice(&s, INT64_MIN, 1, &r);
    CHECK(is(&r, "h"));
    msrt_string_view(&s, 1, 3, &r);
    CHECK(is(&r, "é"));
    msrt_string_view(&s, 0, -1, &r);
    CHECK(is(&r, "héllo, wörld of long tex") && (r.tagged >> 62) == 3);
    msrt_string_view(&s, 4, 4, &r);
    CHECK(is(&r, ""));
    drop(&s);
    /* repeat and reverse */
    {
        MsStr unit = mk("ab");
        MsStr repeated;
        msrt_string_repeat(&unit, 0, &repeated);
        CHECK(is(&repeated, ""));
        msrt_string_repeat(&unit, 3, &repeated);
        CHECK(is(&repeated, "ababab"));
        drop(&repeated);
        MsStr wide = mk("é-");
        msrt_string_repeat(&wide, 9, &repeated);
        CHECK(is(&repeated, "é-é-é-é-é-é-é-é-é-"));
        drop(&repeated);
        MsStr one = mk("x");
        msrt_string_repeat(&one, 40, &repeated);
        CHECK(ms_str_len(&repeated) == 40 && is(&repeated, "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"));
        drop(&repeated);
        const char *texts[] = {"", "a", "ab", "héllo", "abcdefghijklmnopqrstuvwxyz", "日本語のテキストと text 😀 mixed"};
        const char *wants[] = {"", "a", "ba", "olléh", "zyxwvutsrqponmlkjihgfedcba", "dexim 😀 txet とトスキテの語本日"};
        for (size_t i = 0; i < sizeof texts / sizeof *texts; i++) {
            MsStr text = mk(texts[i]);
            msrt_string_reverse(&text, &repeated);
            CHECK(is(&repeated, wants[i]));
            drop(&repeated);
            drop(&text);
        }
        drop(&unit);
        drop(&wide);
        drop(&one);
    }
    /* append grows an owned string in place and copies everything else */
    {
        MsStr acc = mk("a string longer than fifteen bytes");
        MsStr piece = mk("-x");
        char want[1024] = "a string longer than fifteen bytes";
        for (int i = 0; i < 300; i++) {
            MsStr next;
            msrt_string_append(&acc, &piece, &next);
            acc = next;
            msx_append(want, sizeof want, "-x");
            CHECK(is(&acc, want));
        }
        MsStr self_tail = {.bytes = ms_str_data(&acc) + 5, .tagged = 10 | (UINT64_C(3) << 62)}; /* a view into acc */
        MsStr both;
        msrt_string_append(&acc, &self_tail, &both);
        CHECK(ms_str_len(&both) == strlen(want) + 10);
        drop(&both);
        MsStr small = mk("tiny"), joined;
        msrt_string_append(&small, &piece, &joined); /* inline: concatenated, nothing freed */
        CHECK(is(&joined, "tiny-x"));
        MsStr none = mk(""), empty_result;
        MsStr big = mk("another string past the inline limit");
        msrt_string_append(&big, &none, &empty_result);
        CHECK(is(&empty_result, "another string past the inline limit"));
        drop(&empty_result);
        drop(&piece);
    }
    MsStr t = mk("héllo");
    jmp_buf jb;
    ms_test_fault = &jb;
    if (setjmp(jb) == 0) {
        msrt_string_view(&t, 0, 2, &r); /* inside a scalar */
        CHECK(false);
    }
    CHECK(strcmp(ms_test_fault_message, "String.view: bounds 0..2 are outside the text or inside a scalar") == 0);
    if (setjmp(jb) == 0) {
        msrt_string_view(&t, -9, 2, &r);
        CHECK(false);
    }
    CHECK(strcmp(ms_test_fault_message, "String.view: bounds -9..2 are outside the text or inside a scalar") == 0);
    ms_test_fault = NULL;
    drop(&t);
    /* trims (borrowing and owned), at inline, heap and untouched sizes */
    const char *padded[] = {"", "  ", " a ", "\t\n hello world \r\n", "   a string well past the inline size, with é   ", "no-trim-needed-here-at-all"};
    const char *both[] = {"", "", "a", "hello world", "a string well past the inline size, with é", "no-trim-needed-here-at-all"};
    for (size_t i = 0; i < sizeof padded / sizeof *padded; i++) {
        MsStr in = mk(padded[i]), res;
        msrt_string_trim(&in, &res);
        CHECK(is(&res, both[i]));
        drop(&res);
        msrt_string_trim_start(&in, &res);
        CHECK(strncmp((const char *)ms_str_data(&res), both[i], strlen(both[i])) == 0 && ms_str_len(&res) >= strlen(both[i]));
        drop(&res);
        msrt_string_trim_end(&in, &res);
        CHECK(ms_str_len(&res) >= strlen(both[i]));
        drop(&res);
        MsStr owned = mk(padded[i]);
        msrt_string_trim_take(&owned, &res);
        CHECK(is(&res, both[i]));
        drop(&res);
        drop(&in);
    }
    {
        MsStr in = mk("   leading and a long enough tail to live on the heap"), res;
        msrt_string_trim_start_take(&in, &res);
        CHECK(is(&res, "leading and a long enough tail to live on the heap"));
        drop(&res);
        in = mk("a long enough head to live on the heap and then trailing   ");
        msrt_string_trim_end_take(&in, &res);
        CHECK(is(&res, "a long enough head to live on the heap and then trailing"));
        drop(&res);
    }
    /* index_of */
    {
        MsStr h = mk("a string well past the inline size, with é"), n = mk("inline"), none = mk("zzz"), empty = mk("");
        int64_t at = -1;
        CHECK(msrt_string_index_of(&h, &n, &at) == 1 && at == 23);
        CHECK(msrt_string_index_of(&h, &none, &at) == 0);
        CHECK(msrt_string_index_of(&h, &empty, &at) == 1 && at == 0);
        drop(&h); drop(&n); drop(&none);
    }
    /* char_at: ascii, two-byte, stray byte */
    {
        MsStr txt = mk("aé"), res;
        msrt_string_char_at(&txt, 0, &res);
        CHECK(is(&res, "a"));
        msrt_string_char_at(&txt, 1, &res);
        CHECK(is(&res, "\xc3\xa9"));
        drop(&txt);
        const uint8_t stray[] = {'x', 0xff};
        msrt_string_from_bytes(stray, 2, &txt);
        msrt_string_char_at(&txt, 1, &res);
        CHECK(is(&res, "\xef\xbf\xbd"));
        drop(&txt);
    }
    /* padding by scalars, inline and heap results, multi-byte padding, short target */
    {
        MsStr txt = mk("é"), dash = mk("-"), ab = mk("é-"), res;
        msrt_string_pad_start(&txt, 4, &dash, &res);
        CHECK(is(&res, "---\xc3\xa9"));
        msrt_string_pad_end(&txt, 4, &ab, &res);
        CHECK(is(&res, "\xc3\xa9\xc3\xa9-\xc3\xa9"));
        msrt_string_pad_end(&txt, 1, &dash, &res);
        CHECK(is(&res, "\xc3\xa9"));
        msrt_string_pad_start(&txt, 40, &ab, &res);
        CHECK(ms_str_len(&res) == 2 + 39 / 2 * 3 + (39 % 2) * 2 && memcmp(ms_str_data(&res) + ms_str_len(&res) - 2, "\xc3\xa9", 2) == 0);
        drop(&res);
        MsStr none = mk("");
        msrt_string_pad_start(&txt, 9, &none, &res);
        CHECK(is(&res, "\xc3\xa9"));
        drop(&txt); drop(&dash); drop(&ab);
    }
    puts("core_strbuild: ok");
    return 0;
}

/* Unit test for runtime/core/strbuild.c; `make c-test` builds it with ASan and UBSan. Fault and the ASCII table come from support/rt_stubs.c. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
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
    puts("core_strbuild: ok");
    return 0;
}

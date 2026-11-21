/* The @std/regex natives against a fake of the runtime's list functions: results, budgets and errors. */
#include "ms_rt/regex.h"
#include "fake_rt.h"
#include "../std/regex.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>


static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

/* A static string value over the literal: the top bits 10 mean borrowed bytes that outlive the value. */
static MsStr lit(const char *s) {
    return (MsStr){.bytes = (const uint8_t *)s, .tagged = strlen(s) | ((uint64_t)2 << MS_STR_TAG_SHIFT)};
}
static void *compile(const char *p) {
    void *h = NULL;
    MsStr pat = lit(p);
    CHECK(msstd_regex_compile(&pat, &h, NULL) == 0);
    return h;
}
static void drop(void *h) { ((MsObj *)h)->drop(h); }
static int vec_is(const MsVec *v, size_t n, const int64_t *want) {
    return v->len == n && (n == 0 || memcmp(v->ptr, want, n * 8) == 0);
}

int main(void) {
    MsVec v;
    MsStr text;

    void *re = compile("[0-9]+");
    text = lit("a12b3");
    CHECK(msstd_regex_matches(re, &text));
    CHECK(msstd_regex_find_all_spans(re, &text, 0, 0, &v) == 0 && vec_is(&v, 4, (int64_t[]){1, 3, 4, 5}));
    free(v.ptr);
    /* budgets: strict, zero with a match is an error, zero without is empty, negative is invalid */
    CHECK(msstd_regex_find_all_spans(re, &text, 1, 1, &v) == 3);
    CHECK(msstd_regex_find_all_spans(re, &text, 1, 2, &v) == 0);
    free(v.ptr);
    CHECK(msstd_regex_find_all_spans(re, &text, 1, 0, &v) == 3);
    text = lit("abc");
    CHECK(msstd_regex_find_all_spans(re, &text, 1, 0, &v) == 0 && v.len == 0);
    CHECK(msstd_regex_find_all_spans(re, &text, 1, -1, &v) == 1);
    CHECK(!msstd_regex_find_span(re, &text, &v));
    drop(re);

    re = compile("(?P<y>[0-9]{4})-(x)?(?P<m>[0-9]{2})");
    text = lit("on 2026-10 ok 2027-11");
    CHECK(msstd_regex_capture_spans(re, &text, 0, 0, &v) == 0);
    CHECK(vec_is(&v, 9, (int64_t[]){4, 3, 10, 3, 7, -1, -1, 8, 10}));
    free(v.ptr);
    CHECK(msstd_regex_capture_spans(re, &text, 1, 3, &v) == 3); /* four slots, budget three, a match exists */
    CHECK(msstd_regex_capture_all_spans(re, &text, 0, 0, 0, 0, &v) == 0 && v.len == 1 + 8 * 2);
    CHECK(((int64_t *)v.ptr)[0] == 4 && ((int64_t *)v.ptr)[1] == 3 && ((int64_t *)v.ptr)[9] == 14);
    free(v.ptr);
    CHECK(msstd_regex_capture_all_spans(re, &text, 1, 1, 0, 0, &v) == 3);
    CHECK(msstd_regex_capture_all_spans(re, &text, 0, 0, 1, 7, &v) == 3); /* 8 slots needed, 7 allowed */
    drop(re);

    /* compile errors come back as owned text */
    {
        void *h = NULL;
        MsStr bad = lit("(?=a)"), err = {.tagged = 0};
        CHECK(msstd_regex_compile(&bad, &h, &err) == 4 && h == NULL);
        CHECK(err.tagged == strlen("lookahead is not supported at column 1") && memcmp(err.ptr_word, "lookahead", 9) == 0);
        free(err.ptr_word);
    }

    /* a pattern that hits a limit is an error, and a plain match reports no match */
    re = compile("(a+)+$");
    {
        char t[64];
        memset(t, 'a', sizeof t - 1);
        t[sizeof t - 1] = 0;
        t[40] = 'b';
        text = lit(t);
        CHECK(msstd_regex_find_all_spans(re, &text, 0, 0, &v) == 3);
        CHECK(msstd_regex_capture_spans(re, &text, 0, 0, &v) == 3);
        CHECK(!msstd_regex_matches(re, &text));
    }
    drop(re);

    if (failures) return 1;
    printf("std_regex_abi ok\n");
    return 0;
}

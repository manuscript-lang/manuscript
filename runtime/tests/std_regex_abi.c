/* The @std/regex natives against a fake of the runtime's list functions: results, budgets and errors. */
#include "../std/regex.h"
#include "fake_rt.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { void *ptr; size_t tagged; } msrt_str;
typedef fake_vec msrt_vec;
typedef struct msrt_obj msrt_obj;
struct msrt_obj { msrt_obj *(*clone)(msrt_obj *); void (*drop)(msrt_obj *); };

uint8_t msstd_regex_compile(const msrt_str *, void **, msrt_str *);
uint8_t msstd_regex_matches(const void *, const msrt_str *);
uint8_t msstd_regex_find_span(const void *, const msrt_str *, msrt_vec *);
uint8_t msstd_regex_find_all_spans(const void *, const msrt_str *, uint8_t, int64_t, msrt_vec *);
uint8_t msstd_regex_capture_spans(const void *, const msrt_str *, uint8_t, int64_t, msrt_vec *);
uint8_t msstd_regex_capture_all_spans(const void *, const msrt_str *, uint8_t, int64_t, uint8_t, int64_t, msrt_vec *);

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

static msrt_str lit(const char *s) { msrt_str v = {(void *)s, strlen(s) | ((size_t)2 << 62)}; return v; }
static void *compile(const char *p) {
    void *h = NULL;
    msrt_str pat = lit(p);
    CHECK(msstd_regex_compile(&pat, &h, NULL) == 0);
    return h;
}
static void drop(void *h) { ((msrt_obj *)h)->drop(h); }
static int vec_is(const msrt_vec *v, size_t n, const int64_t *want) {
    return v->len == n && (n == 0 || memcmp(v->ptr, want, n * 8) == 0);
}

int main(void) {
    msrt_vec v;
    msrt_str text;

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
    CHECK(v.ptr[0] == 4 && v.ptr[1] == 3 && v.ptr[9] == 14);
    free(v.ptr);
    CHECK(msstd_regex_capture_all_spans(re, &text, 1, 1, 0, 0, &v) == 3);
    CHECK(msstd_regex_capture_all_spans(re, &text, 0, 0, 1, 7, &v) == 3); /* 8 slots needed, 7 allowed */
    drop(re);

    /* compile errors come back as owned text */
    {
        void *h = NULL;
        msrt_str bad = lit("(?=a)"), err = {0, 0};
        CHECK(msstd_regex_compile(&bad, &h, &err) == 4 && h == NULL);
        CHECK(err.tagged == strlen("lookahead is not supported at column 1") && memcmp(err.ptr, "lookahead", 9) == 0);
        free(err.ptr);
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

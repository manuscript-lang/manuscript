/* Unit tests of src/runtime/std/regex.c: the dialect, the limits and the empty-match rule. Built against the system PCRE2. */
#include "../std/regex.h"
#include "fake_rt.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>


static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

static MsRegex *compile(const char *p, char *msg) {
    msg[0] = 0;
    return ms_re_compile(p, strlen(p), msg, 160);
}
static int accepts(const char *p) {
    char msg[160];
    MsRegex *re = compile(p, msg);
    ms_re_free(re);
    return re != NULL;
}
static int find(const char *p, const char *text, int64_t *span) {
    char msg[160];
    MsRegex *re = compile(p, msg);
    int64_t slots[64];
    int rc = re ? ms_re_match(re, text, strlen(text), 0, slots) : -9;
    if (rc == MS_RE_MATCHED) {
        span[0] = slots[0];
        span[1] = slots[1];
    }
    ms_re_free(re);
    return rc;
}
/* The size of the buffers `all` fills. */
enum { MATCH_LIST_CAP = 256 };

/* All matches of p in text, as "a-b," pairs. */
static void all(const char *p, const char *text, char *out) {
    char msg[160];
    MsRegex *re = compile(p, msg);
    int64_t slots[64];
    MsRegexIter it;
    ms_re_iter_init(&it);
    out[0] = 0;
    while (ms_re_next(re, text, strlen(text), &it, slots) == MS_RE_MATCHED)
        snprintf(out + strlen(out), MATCH_LIST_CAP - strlen(out), "%lld-%lld,", (long long)slots[0], (long long)slots[1]);
    ms_re_iter_done(&it);
    ms_re_free(re);
}

int main(void) {
    char msg[160], buf[256];
    int64_t sp[2];

    /* Accepted: plain patterns and the PCRE2 spellings of what the old dialect allowed. */
    const char *good[] = {"a+", "(?P<n>a)(?P<m>b)", "(?i)a", "(?x)a b", "[[:alpha:]]", "[\\w-]", "\\B", "\\x{41}",
                          "\\p{Greek}", "\\p{L}+", "(a{100}){100}", "a*+", "(?>a)", "\\Qa.b\\E", "\\bx\\b", "(?#c)a",
                          "a{", "a{,2}"}; /* PCRE2 reads a malformed repeat as literal text */
    for (size_t i = 0; i < sizeof good / sizeof *good; i++)
        if (!accepts(good[i])) {
            printf("should compile: %s\n", good[i]);
            failures++;
        }

    /* Rejected: syntax errors, and features outside the dialect. */
    const char *bad[] = {"(?P<n>a)(?P<n>b)", "(a", "a)", "*a", "[a", "a\\", "(a)\\1", "\\g{1}(a)", "(?P<n>a)\\k<n>",
                         "(?P<n>a)(?P=n)", "(?=a)", "(?!a)", "(?<=a)b", "(?<!a)b", "(?R)", "(a)(?1)", "(?&n)(?P<n>a)",
                         "(?P>n)(?P<n>a)", "(?(1)a|b)", "a(?C1)", "(*FAIL)", "\\C"};
    for (size_t i = 0; i < sizeof bad / sizeof *bad; i++)
        if (accepts(bad[i])) {
            printf("should not compile: %s\n", bad[i]);
            failures++;
        }

    /* A pattern's text hides nothing: escaped parentheses, classes and \Q..\E are not constructs. */
    CHECK(accepts("\\(?=a"));
    CHECK(accepts("[(?=]"));
    CHECK(accepts("\\Q(?=\\E"));
    CHECK(accepts("[[:alpha:](?=]"));

    /* Error text: reason and the column in characters. */
    CHECK(!compile("é[", msg) && strstr(msg, "at column 3"));
    CHECK(!compile("(?=a)", msg) && strcmp(msg, "lookahead is not supported at column 1") == 0);

    /* Unicode-aware classes, byte offsets, case folding. */
    CHECK(find("\\w+", "héllo wörld", sp) == MS_RE_MATCHED && sp[0] == 0 && sp[1] == 6);
    CHECK(find("\\d", "x٣", sp) == MS_RE_MATCHED && sp[0] == 1 && sp[1] == 3);
    CHECK(find("(?i)É", "é", sp) == MS_RE_MATCHED);
    CHECK(find("a$", "a\n", sp) == MS_RE_NOMATCH); /* `$` is the end of the text only */
    CHECK(find("(?m)a$", "a\nb", sp) == MS_RE_MATCHED);
    CHECK(find("a.b", "a\nb", sp) == MS_RE_NOMATCH);

    /* Groups: slots of participating and absent groups, and names. */
    {
        MsRegex *re = compile("(?P<y>[0-9]{4})-(x)?(?P<m>[0-9]{2})", msg);
        int64_t slots[8];
        CHECK(re && ms_re_slots(re) == 4);
        CHECK(ms_re_match(re, "on 2026-10", 10, 0, slots) == MS_RE_MATCHED);
        CHECK(slots[0] == 3 && slots[1] == 10 && slots[2] == 3 && slots[3] == 7 && slots[4] == -1 && slots[5] == -1);
        size_t n = 0;
        const char *name = ms_re_group_name(re, 1, &n);
        CHECK(name && n == 1 && name[0] == 'y');
        CHECK(ms_re_group_name(re, 2, &n) == NULL);
        name = ms_re_group_name(re, 3, &n);
        CHECK(name && n == 1 && name[0] == 'm');
        ms_re_free(re);
    }

    /* Empty matches follow the adjacency rule: "a*" over "a🙂🙂a" is "a", "", "a" at these offsets. */
    all("a*", "a\xF0\x9F\x99\x82\xF0\x9F\x99\x82" "a", buf);
    CHECK(strcmp(buf, "0-1,5-5,9-10,") == 0);
    all("", "ab", buf);
    CHECK(strcmp(buf, "0-0,1-1,2-2,") == 0);
    all("[0-9]+", "a12b3", buf);
    CHECK(strcmp(buf, "1-3,4-5,") == 0);

    /* Limits: catastrophic patterns stop with MS_RE_LIMIT, in the interpreter and the JIT, and a pattern cannot
       raise the limit. */
    {
        char text[64];
        memset(text, 'a', sizeof text - 1);
        text[sizeof text - 1] = 0;
        text[40] = 'b'; /* the tail never matches `$` */
        CHECK(find("(a+)+$", text, sp) == MS_RE_LIMIT);
        CHECK(find("(*NO_JIT)(a+)+$", text, sp) == -9); /* verbs are refused, so a pattern cannot pick the engine */
        CHECK(find("(a|aa)+$", text, sp) == MS_RE_LIMIT);
    }

    /* Long text under the default JIT stack: a loop with a group needs stack per iteration. */
    {
        size_t n = 400000;
        char *text = malloc(n + 1);
        memset(text, 'a', n);
        text[n] = 0;
        CHECK(find("(?:a|b)*c?", text, sp) == MS_RE_MATCHED && sp[1] == (int64_t)n);
        CHECK(find("(a|b)*", text, sp) == MS_RE_MATCHED && sp[1] == (int64_t)n);
        free(text);
    }

    if (failures) return 1;
    printf("std_regex ok\n");
    return 0;
}

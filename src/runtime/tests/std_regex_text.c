/* The @std/regex natives that answer with text, against the recorded behavior of the Rust crate they replace:
 * texts, group rows, pieces, replacements, budgets and the Unicode categories. */
#include "ms_rt/regex.h"
#include "ms_rt/unicode.h"
#include "fake_rt.h"
#include "../std/regex.h"
#include "ms_rt/strbuild.h"
#include "support/append.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { STATUS_OK_ = 0, INVALID = 1, LIMIT = 3 };

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

static MsStr lit(const char *s) {
    return (MsStr){.bytes = (const uint8_t *)s, .tagged = strlen(s) | ((uint64_t)2 << MS_STR_TAG_SHIFT)};
}

static void *compile(const char *pattern) {
    void *handle = NULL;
    MsStr text = lit(pattern);
    CHECK(msstd_regex_compile(&text, &handle, NULL) == 0);
    return handle;
}

static void drop(void *handle) { ((MsObj *)handle)->drop(handle); }

/* The strings of a list joined with '|', in `out`. */
static void join(const MsVec *list, char *out, size_t cap) {
    out[0] = 0;
    for (size_t i = 0; i < list->len; i++) {
        const MsStr *s = (const MsStr *)list->ptr + i;
        msx_append(out, cap, "%s%.*s", i ? "|" : "", (int)ms_str_len(s), (const char *)ms_str_data(s));
    }
}

/* The rows of a list of lists, each joined with ',', the rows joined with ';'. */
static void join_rows(const MsVec *rows, char *out, size_t cap) {
    out[0] = 0;
    for (size_t r = 0; r < rows->len; r++) {
        char row[256];
        join((const MsVec *)rows->ptr + r, row, sizeof row);
        msx_append(out, cap, "%s%s", r ? ";" : "", row);
    }
}

static int strings_are(const char *pattern, const char *input, uint8_t has, int64_t max, int status, const char *want,
                       uint8_t (*native)(const void *, const MsStr *, uint8_t, int64_t, MsVec *)) {
    void *re = compile(pattern);
    MsStr text = lit(input);
    MsVec list = {0};
    char got[512] = "";
    const int result = native(re, &text, has, max, &list);
    if (result == 0) {
        join(&list, got, sizeof got);
        msrt_list_drop(&list, &msrt_desc_string);
    }
    drop(re);
    return result == status && (status != 0 || strcmp(got, want) == 0);
}

static int replaced_is(const char *pattern, const char *input, const char *with, int template_mode, uint8_t has, int64_t max,
                       int status, const char *want) {
    void *re = compile(pattern);
    MsStr text = lit(input);
    MsStr with_text = lit(with);
    MsStr out = {0};
    const int result = template_mode ? msstd_regex_replace_template(re, &text, &with_text, has, max, &out)
                                     : msstd_regex_replace_all(re, &text, &with_text, has, max, &out);
    const int same = result == status && (status != 0 || (ms_str_len(&out) == strlen(want) && memcmp(ms_str_data(&out), want, ms_str_len(&out)) == 0));
    if (result == 0) ms_str_release(&out);
    drop(re);
    return same;
}

static int rows_are(const char *pattern, const char *input, uint8_t has, int64_t max, int status, const char *want) {
    void *re = compile(pattern);
    MsStr text = lit(input);
    MsVec rows = {0};
    char got[512] = "";
    const int result = msstd_regex_captures_all(re, &text, has, max, &rows);
    if (result == 0) {
        join_rows(&rows, got, sizeof got);
        msrt_list_drop(&rows, &(MsTypeDesc){.size = sizeof(MsVec), .align = 8, .kind = MS_TYPE_KIND_LIST, .inner0 = &msrt_desc_string});
    }
    drop(re);
    return result == status && (status != 0 || strcmp(got, want) == 0);
}

static void test_find_all_and_split(void) {
    CHECK(strings_are("[0-9]+", "a12b3", 0, 0, 0, "12|3", msstd_regex_find_all));
    CHECK(strings_are("[0-9]+", "a12b3", 1, 2, 0, "12|3", msstd_regex_find_all));
    CHECK(strings_are("[0-9]+", "a12b3", 1, 1, LIMIT, "", msstd_regex_find_all));
    CHECK(strings_are("[0-9]+", "ab", 1, 0, 0, "", msstd_regex_find_all));
    CHECK(strings_are("[0-9]+", "a1", 1, 0, LIMIT, "", msstd_regex_find_all));
    CHECK(strings_are("[0-9]+", "a1", 1, -1, INVALID, "", msstd_regex_find_all));
    CHECK(strings_are(",", "a,b,c", 0, 0, 0, "a|b|c", msstd_regex_split));
    CHECK(strings_are(",", "a,b,c", 1, 3, 0, "a|b|c", msstd_regex_split));
    CHECK(strings_are(",", "a,b,c", 1, 2, LIMIT, "", msstd_regex_split));
    CHECK(strings_are(",", "a,b,c", 1, -1, INVALID, "", msstd_regex_split));
    CHECK(strings_are(",", "abc", 1, 1, 0, "abc", msstd_regex_split));
    CHECK(strings_are(",", "abc", 1, 0, LIMIT, "", msstd_regex_split));
    CHECK(strings_are("", "é🙂", 0, 0, 0, "|é|🙂|", msstd_regex_split));
    CHECK(strings_are("", "é🙂", 1, 4, 0, "|é|🙂|", msstd_regex_split));
    CHECK(strings_are("", "é🙂", 1, 3, LIMIT, "", msstd_regex_split));
    CHECK(strings_are("a*", "a🙂a", 0, 0, 0, "|🙂|", msstd_regex_split));
}

static void test_captures(void) {
    void *re = compile("(a)?b");
    MsStr text = lit("b");
    MsVec list = {0};
    char got[128];
    msstd_regex_captures(re, &text, &list);
    join(&list, got, sizeof got);
    CHECK(strcmp(got, "b|") == 0 && list.len == 2);
    msrt_list_drop(&list, &msrt_desc_string);
    text = lit("zzz");
    msstd_regex_captures(re, &text, &list);
    CHECK(list.len == 0);
    msrt_list_drop(&list, &msrt_desc_string);
    drop(re);
    CHECK(rows_are("(a)|(b+)", "a bbb a", 0, 0, 0, "a|a|;bbb||bbb;a|a|"));
    CHECK(rows_are("(a)|(b+)", "a bbb a", 1, 3, 0, "a|a|;bbb||bbb;a|a|"));
    CHECK(rows_are("(a)|(b+)", "a bbb a", 1, 2, LIMIT, ""));
    CHECK(rows_are("(a)|(b+)", "a", 1, 0, LIMIT, ""));
    CHECK(rows_are("(a)|(b+)", "", 1, 0, 0, ""));
    CHECK(rows_are("(a)|(b+)", "a", 1, -1, INVALID, ""));
    CHECK(rows_are("a+", "baab a", 0, 0, 0, "aa;a"));
    CHECK(rows_are("(a)?b", "b b", 0, 0, 0, "b|;b|"));
}

static void test_named_pairs(void) {
    void *re = compile("(a)?(?P<first>b)?(c)(?P<empty>d*)(?P<last>e)");
    MsStr text = lit("ce");
    MsVec list = {0};
    char got[128];
    msstd_regex_named_capture_pairs(re, &text, &list);
    join(&list, got, sizeof got);
    CHECK(strcmp(got, "empty||last|e") == 0);
    msrt_list_drop(&list, &msrt_desc_string);
    text = lit("abcde");
    msstd_regex_named_capture_pairs(re, &text, &list);
    join(&list, got, sizeof got);
    CHECK(strcmp(got, "first|b|empty|d|last|e") == 0);
    msrt_list_drop(&list, &msrt_desc_string);
    text = lit("xyz");
    msstd_regex_named_capture_pairs(re, &text, &list);
    CHECK(list.len == 0);
    msrt_list_drop(&list, &msrt_desc_string);
    drop(re);
}

static void test_replace_all(void) {
    CHECK(replaced_is("(?P<name>é)", "aéb", "$1", 0, 0, 0, 0, "a$1b"));
    CHECK(replaced_is("(?P<name>é)", "aéb", "🙂", 0, 1, 6, 0, "a🙂b"));
    CHECK(replaced_is("(?P<name>é)", "aéb", "🙂", 0, 1, 5, LIMIT, ""));
    CHECK(replaced_is("(?P<name>é)", "aéb", "🙂", 0, 1, -1, INVALID, ""));
    CHECK(replaced_is("(?P<name>é)", "", "🙂", 0, 1, 0, 0, ""));
    CHECK(replaced_is("(?P<name>é)", "é", "🙂", 0, 1, 1, LIMIT, ""));
    CHECK(replaced_is("", "é🙂", "x", 0, 1, 9, 0, "xéx🙂x"));
    CHECK(replaced_is("", "é🙂", "x", 0, 1, 8, LIMIT, ""));
}

static void test_replace_template(void) {
    const char *pattern = "(?P<a>a+)|(b+)";
    CHECK(replaced_is(pattern, "aaaaaaaa b a", "${a}:${2}$$", 1, 0, 0, 0, "aaaaaaaa:$ :b$ a:$"));
    CHECK(replaced_is(pattern, "a b", "${1}x:$1x:$missing", 1, 0, 0, 0, "ax:: x::"));
    CHECK(replaced_is(pattern, "a b", "", 1, 0, 0, 0, " "));
    CHECK(replaced_is(pattern, "a b", "xy", 1, 1, 5, 0, "xy xy"));
    CHECK(replaced_is(pattern, "a b", "xy", 1, 1, 4, LIMIT, ""));
    CHECK(replaced_is(pattern, "a b", "$$", 1, 1, 3, 0, "$ $"));
    CHECK(replaced_is(pattern, "a b", "$$", 1, 1, 2, LIMIT, ""));
    CHECK(replaced_is("(?P<name>é)", "aéb", "${name}$$", 1, 1, 5, 0, "aé$b"));
    CHECK(replaced_is("(?P<name>é)", "aéb", "${name}$$", 1, 1, 4, LIMIT, ""));
    CHECK(replaced_is("(?P<name>é)", "aéb", "${name}$$", 1, 1, -1, INVALID, ""));
    CHECK(replaced_is("", "é🙂", "x", 1, 1, 9, 0, "xéx🙂x"));
    CHECK(replaced_is("", "é🙂", "x", 1, 1, 8, LIMIT, ""));
    /* The reference syntax: a lone or unfinished dollar is literal, `${+1}` is group one, an unknown name is empty. */
    CHECK(replaced_is("(a)", "a", "$", 1, 0, 0, 0, "$"));
    CHECK(replaced_is("(a)", "a", "${a", 1, 0, 0, 0, "${a"));
    CHECK(replaced_is("(a)", "a", "${+1}${01}${0}$1_", 1, 0, 0, 0, "aaa"));
    CHECK(replaced_is("(a)", "a", "${}${ }${1 2}$9999999999999999999999999999", 1, 0, 0, 0, ""));
    CHECK(replaced_is("(a)", "a", "[$1x][${1}x]", 1, 0, 0, 0, "[][ax]"));
}

static void test_categories(void) {
    MsStr punctuation = lit("P"), symbol = lit("S"), mark = lit("M"), other = lit("L");
    CHECK(msstd_unicode_in_category('!', &punctuation) && !msstd_unicode_in_category('a', &punctuation));
    CHECK(msstd_unicode_in_category('+', &symbol) && msstd_unicode_in_category(0x1F642, &symbol));
    CHECK(msstd_unicode_in_category(0x0301, &mark) && !msstd_unicode_in_category('a', &mark));
    CHECK(!msstd_unicode_in_category('!', &other));
    CHECK(!msstd_unicode_in_category(-1, &punctuation) && !msstd_unicode_in_category(0xD800, &punctuation));
    CHECK(!msstd_unicode_in_category(0x110000, &punctuation));
}

int main(void) {
    test_find_all_and_split();
    test_captures();
    test_named_pairs();
    test_replace_all();
    test_replace_template();
    test_categories();
    if (failures) {
        printf("%d failures\n", failures);
        return 1;
    }
    puts("std_regex_text ok");
    return 0;
}

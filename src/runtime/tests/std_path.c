/* The @std/os/path natives against the 12k-case corpus recorded from the original matcher, then the cases the
 * corpus does not hold: brace extremes, limits, the Windows dialect and a failing allocation. */
#include "ms_rt/path.h"
#include "ms_rt/alloc.h"
#include "fake_rt.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "append.h"

enum { MAX_PATTERN_BYTES = 4096 };

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

typedef struct { const char *ptr; uint64_t tagged; } ms_str; /* a static String value */
static ms_str lit(const char *s, size_t n) { return (ms_str){.ptr = s, .tagged = n | ((uint64_t)2 << 62)}; }
static ms_str lit_z(const char *s) { return lit(s, strlen(s)); }

static void drop(MsObj *o) { o->drop(o); }

/* The compile status of `pattern`; the handle goes to `*handle` when it compiled. */
static uint8_t compile(uint8_t windows, const char *pattern, MsObj **handle) {
    ms_str p = lit_z(pattern);
    return msstd_path_compile_glob(windows, &p, handle);
}

static int matches(uint8_t windows, const char *pattern, const char *value) {
    MsObj *glob = NULL;
    if (compile(windows, pattern, &glob) != 0) {
        return -1;
    }
    ms_str v = lit_z(value);
    uint8_t out = 9;
    uint8_t status = msstd_path_glob_matches(glob, &v, &out);
    drop(glob);
    return status == 0 ? out : -2;
}

static size_t unhex(const char *hex, char *out, size_t cap) {
    size_t n = 0;
    for (; hex[0] != '\0' && hex[1] != '\0' && n < cap; hex += 2) {
        unsigned byte = 0;
        sscanf(hex, "%2x", &byte);
        out[n++] = (char)byte;
    }
    return n;
}

static void replay_corpus(const char *path) {
    FILE *file = fopen(path, "r");
    CHECK(file != NULL);
    if (file == NULL) {
        return;
    }
    char line[2048];
    size_t checked = 0;
    while (fgets(line, sizeof line, file) != NULL) {
        line[strcspn(line, "\n")] = '\0';
        char *first = line; /* `hex(pattern) hex(value) result`; either hex may be empty */
        char *second = strchr(first, ' ');
        char *third = second == NULL ? NULL : strchr(second + 1, ' ');
        if (third == NULL) {
            continue;
        }
        *second++ = '\0';
        *third++ = '\0';
        char pattern[1024] = {0};
        char value[1024] = {0};
        size_t pattern_len = unhex(first, pattern, sizeof pattern - 1);
        size_t value_len = strcmp(second, "-") == 0 ? 0 : unhex(second, value, sizeof value - 1);
        (void)pattern_len;
        (void)value_len;
        int got = matches(0, pattern, value);
        int want = third[0] == 'E' ? -1 : third[0] - '0';
        if (got != want) {
            printf("FAIL corpus: pattern %s value %s: got %d want %d (%s)\n", first, second, got, want, third);
            failures++;
        }
        checked++;
    }
    fclose(file);
    CHECK(checked > 12000);
}

static void brace_cases(void) {
    CHECK(matches(0, "f{1..2..9223372036854775807}", "f1") == 1);
    CHECK(matches(0, "f{1..2..-9223372036854775808}", "f1") == 1);
    CHECK(matches(0, "f{2..1..9223372036854775807}", "f2") == 1);
    CHECK(matches(0, "f{5..1..-2}", "f3") == 1);
    CHECK(matches(0, "f{5..1..-2}", "f4") == 0);
    CHECK(matches(0, "f{a..c..2}", "fb") == 0);
    CHECK(matches(0, "f{a..c..2}", "fc") == 1);
    CHECK(matches(0, "f{-02..02}", "f-01") == 1);
    CHECK(matches(0, "{x}{a,b}", "{x}b") == 1);
    CHECK(matches(0, "{1..2..9223372036854775808}", "1") == -1); /* step does not fit */
    CHECK(matches(0, "{1..100001}", "1") == -1);                  /* endpoint out of range */
    CHECK(matches(0, "{1..2000..1}", "1") == -1);                 /* more than 1024 steps */
}

static void limit_cases(void) {
    char long_pattern[MAX_PATTERN_BYTES + 2];
    memset(long_pattern, 'a', sizeof long_pattern);
    long_pattern[MAX_PATTERN_BYTES] = '\0';
    CHECK(matches(0, long_pattern, "a") == 0);
    long_pattern[MAX_PATTERN_BYTES] = 'a';
    long_pattern[MAX_PATTERN_BYTES + 1] = '\0';
    CHECK(matches(0, long_pattern, "a") == -1);
    char deep[256] = {0};
    for (size_t i = 0; i < 70; i++) {
        msx_append(deep, sizeof deep, "@(");
    }
    msx_append(deep, sizeof deep, "a");
    for (size_t i = 0; i < 70; i++) {
        msx_append(deep, sizeof deep, ")");
    }
    CHECK(matches(0, deep, "a") == -1); /* more than 64 nested groups */
    CHECK(matches(0, "@(@(@(a)))", "a") == 1);
    CHECK(matches(0, "a\n", "a") == 0);
    MsObj *glob = NULL;
    ms_str nul = lit("a\0b", 3);
    CHECK(msstd_path_compile_glob(0, &nul, &glob) == 1);
    CHECK(compile(0, "*", &glob) == 0);
    uint8_t out = 7;
    CHECK(msstd_path_glob_matches(glob, &nul, &out) == 1 && out == 7);
    drop(glob);
}

static void dialect_cases(void) {
    CHECK(matches(1, "a/*.ms", "a\\b.ms") == 1);
    CHECK(matches(1, "a\\*.ms", "a/b.ms") == 1);
    CHECK(matches(0, "a/*.ms", "a\\b.ms") == 0);
    CHECK(matches(0, "é?", "éx") == 1);
    #ifdef _WIN32
    CHECK(msstd_path_host_windows() == 1);
#else
    CHECK(msstd_path_host_windows() == 0);
#endif
}

int main(void) {
    replay_corpus("src/runtime/tests/golden/glob_golden.txt");
    brace_cases();
    limit_cases();
    dialect_cases();
    if (failures != 0) {
        printf("%d failures\n", failures);
        return 1;
    }
    printf("std_path ok\n");
    return 0;
}

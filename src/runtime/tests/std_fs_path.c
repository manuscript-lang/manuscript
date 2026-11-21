/* Unit tests of src/runtime/std/fs_pathname.c: the lexical path rules of both hosts, run on either one. */
#include <stdio.h>
#include <string.h>

#include "../std/fs_support.h"
#include "fake_rt.h"

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

static MsBytes text(const char *s) { return ms_bytes_of((const uint8_t *)s, strlen(s)); }

static int same(MsBytes got, const char *want) { return got.len == strlen(want) && memcmp(got.ptr, want, got.len) == 0; }

typedef bool (*Unary)(MsFsRules, MsBytes, MsFsBuffer *);

static void check_unary(Unary run, MsFsRules rules, const char *input, const char *want, int line) {
    MsFsBuffer out = {0};
    const bool built = run(rules, text(input), &out);
    if (!built || !same(ms_fs_buffer_view(&out), want)) {
        printf("FAIL line %d: %s -> %.*s, want %s\n", line, input, (int)out.length, out.data ? (const char *)out.data : "", want);
        failures++;
    }
    ms_fs_buffer_free(&out);
}

static void check_join(MsFsRules rules, const char *a, const char *b, const char *want, int line) {
    MsFsBuffer out = {0};
    const bool built = ms_fs_path_join_with(rules, text(a), text(b), &out);
    if (!built || !same(ms_fs_buffer_view(&out), want)) {
        printf("FAIL line %d: join(%s, %s) -> %.*s, want %s\n", line, a, b, (int)out.length, out.data ? (const char *)out.data : "", want);
        failures++;
    }
    ms_fs_buffer_free(&out);
}

#define CLEAN(r, in, want) check_unary(ms_fs_path_clean_with, r, in, want, __LINE__)
#define DIR(r, in, want) check_unary(ms_fs_path_dir_with, r, in, want, __LINE__)
#define BASE(r, in, want) CHECK(same(ms_fs_path_base_with(r, text(in)), want))
#define JOIN(r, a, b, want) check_join(r, a, b, want, __LINE__)

static void unix_rules(void) {
    const MsFsRules u = MS_FS_RULES_UNIX;
    CLEAN(u, "", ".");
    CLEAN(u, "a/c", "a/c");
    CLEAN(u, "a//c", "a/c");
    CLEAN(u, "a/c/.", "a/c");
    CLEAN(u, "a/c/b/..", "a/c");
    CLEAN(u, "/../a/c", "/a/c");
    CLEAN(u, "../../x", "../../x");
    CLEAN(u, "a/../..", "..");
    CLEAN(u, "/", "/");
    CLEAN(u, "//a", "/a");
    CLEAN(u, "a/./b/../../c/", "c");
    CLEAN(u, "../a/..", "..");
    CLEAN(u, "a\\b", "a\\b");
    BASE(u, "/a/b/", "b");
    BASE(u, "/", "/");
    BASE(u, "", ".");
    BASE(u, "./", ".");
    BASE(u, "a/b/..", "..");
    DIR(u, "/a/b", "/a");
    DIR(u, "a", ".");
    DIR(u, "/a", "/");
    DIR(u, "/", "/");
    DIR(u, "", ".");
    DIR(u, "a/b/", "a");
    JOIN(u, "/tmp", "x/../y", "/tmp/y");
    JOIN(u, "/tmp", "/etc", "/etc");
    JOIN(u, "", "a//b", "a/b");
    JOIN(u, "a", "", "a");
    CHECK(ms_fs_is_absolute_with(u, text("/a")) && !ms_fs_is_absolute_with(u, text("a")));
    CHECK(ms_fs_is_separator_with(u, '/') && !ms_fs_is_separator_with(u, '\\'));
}

static void windows_rules(void) {
    const MsFsRules w = MS_FS_RULES_WINDOWS;
    CLEAN(w, "", ".");
    CLEAN(w, "a/c", "a\\c");
    CLEAN(w, "c:/a//b/../c", "c:\\a\\c");
    CLEAN(w, "C:\\", "C:\\");
    CLEAN(w, "/../a", "\\a");
    CLEAN(w, "C:a/../b", "C:b");
    CLEAN(w, "C:..", "C:..");
    CLEAN(w, "\\\\h\\s\\x\\..\\y", "\\\\h\\s\\y");
    CLEAN(w, "\\\\h\\s\\..", "\\\\h\\s\\");
    CLEAN(w, "\\\\?\\C:\\a\\..\\b", "\\\\?\\C:\\b");
    BASE(w, "C:\\a\\b\\", "b");
    BASE(w, "C:\\", "\\");
    BASE(w, "C:", "C:");
    BASE(w, "\\\\h\\s", "\\\\h\\s");
    DIR(w, "C:\\a\\b", "C:\\a");
    DIR(w, "a", ".");
    DIR(w, "C:\\", "C:\\");
    JOIN(w, "C:\\tmp", "x/../y", "C:\\tmp\\y");
    JOIN(w, "C:\\tmp", "D:\\x", "D:\\x");
    JOIN(w, "C:\\tmp\\a", "\\x", "C:\\x");
    JOIN(w, "C:", "a", "C:a");
    CHECK(ms_fs_is_absolute_with(w, text("C:\\x")) && ms_fs_is_absolute_with(w, text("c:/x")));
    CHECK(ms_fs_is_absolute_with(w, text("\\\\h\\s\\x")));
    CHECK(!ms_fs_is_absolute_with(w, text("\\x")) && !ms_fs_is_absolute_with(w, text("C:x")) && !ms_fs_is_absolute_with(w, text("x")));
    CHECK(ms_fs_is_separator_with(w, '/') && ms_fs_is_separator_with(w, '\\'));
}

int main(void) {
    unix_rules();
    windows_rules();
    if (failures != 0) {
        printf("%d failures\n", failures);
        return 1;
    }
    puts("ok");
    return 0;
}

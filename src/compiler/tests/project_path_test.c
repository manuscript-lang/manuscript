/* Unit test of project paths (src/compiler/src/project/path.c), with the vectors of crates/ms-driver pathops tests. */
#define _XOPEN_SOURCE 700
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "ms/project.h"

static int failures;

#define CHECK(cond)                                                                                \
    do {                                                                                           \
        if (!(cond)) {                                                                             \
            fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, #cond);              \
            failures++;                                                                            \
        }                                                                                          \
    } while (0)

#define CHECK_STR(got, want)                                                                       \
    do {                                                                                           \
        const char *got_ = (got);                                                                  \
        if (strcmp(got_, (want)) != 0) {                                                           \
            fprintf(stderr, "%s:%d: got \"%s\", want \"%s\"\n", __FILE__, __LINE__, got_, (want)); \
            failures++;                                                                            \
        }                                                                                          \
    } while (0)

static void test_clean(MsArena *a) {
    static const char *const cases[][2] = {
        {"", "."},          {"abc", "abc"},       {"abc/def", "abc/def"}, {"a/b/c", "a/b/c"},
        {".", "."},         {"..", ".."},         {"../..", "../.."},     {"../../abc", "../../abc"},
        {"/abc", "/abc"},   {"/", "/"},           {"abc/", "abc"},        {"abc/def/", "abc/def"},
        {"a/./b", "a/b"},   {"a//b", "a/b"},      {"a/b/..", "a"},        {"a/b/../..", "."},
        {"a/b/../../..", ".."}, {"/..", "/"},     {"/../a", "/a"},        {"abc/../../x", "../x"},
        {"//a", "/a"},      {"a/../b", "b"},      {"./a", "a"},           {"../b", "../b"},
    };
    for (size_t i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        CHECK_STR(ms_path_clean(a, cases[i][0]), cases[i][1]);
    }
}

static void test_split(MsArena *a) {
    CHECK_STR(MS_PATH_JOIN(a, "a", "b"), "a/b");
    CHECK_STR(MS_PATH_JOIN(a, "a", "", "b"), "a/b");
    CHECK_STR(MS_PATH_JOIN(a, "", ""), "");
    CHECK_STR(MS_PATH_JOIN(a, "/a", "../b"), "/b");
    CHECK_STR(ms_path_dir(a, "a/b/c.ms"), "a/b");
    CHECK_STR(ms_path_dir(a, "c.ms"), ".");
    CHECK_STR(ms_path_dir(a, "/c.ms"), "/");
    CHECK_STR(ms_path_dir(a, ""), ".");
    CHECK_STR(ms_path_base(a, "a/b/c.ms"), "c.ms");
    CHECK_STR(ms_path_base(a, "a/b/"), "b");
    CHECK_STR(ms_path_base(a, "/"), "/");
    CHECK_STR(ms_path_base(a, ""), ".");
    CHECK_STR(ms_path_ext("a/b.c/d"), "");
    CHECK_STR(ms_path_ext("a/b.ms"), ".ms");
    CHECK_STR(ms_path_ext("a.tar.gz"), ".gz");
}

static void test_rel(MsArena *a) {
    static const char *const cases[][3] = {
        {"a/b", "a/b", "."},      {"a/b", "a/b/c", "c"},  {"a/b", "a/c", "../c"},
        {"a/b", "a", ".."},       {"/a", "/a/b/c", "b/c"}, {"/a/b", "/c", "../../c"},
        {".", "a", "a"},          {"a", ".", ".."},
    };
    for (size_t i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        const char *got;
        MsProjectError err = {0};
        CHECK(ms_path_rel(a, cases[i][0], cases[i][1], &got, &err));
        CHECK_STR(got, cases[i][2]);
    }
    const char *got;
    MsProjectError err = {0};
    CHECK(!ms_path_rel(a, "/a", "b", &got, &err));
    CHECK_STR(ms_project_error_text(a, &err), "Rel: can't make b relative to /a");
    CHECK(ms_path_escapes("..") && ms_path_escapes("../x") && !ms_path_escapes("..x") && !ms_path_escapes("a/.."));
}

static void test_symlinks(MsArena *a) {
    char root[] = "/tmp/ms_project_path_XXXXXX";
    CHECK(mkdtemp(root) != NULL);
    const char *dir = MS_PATH_JOIN(a, root, "real");
    CHECK(mkdir(dir, 0700) == 0);
    CHECK(symlink("real", MS_PATH_JOIN(a, root, "link")) == 0);
    CHECK(symlink("link", MS_PATH_JOIN(a, root, "chain")) == 0);
    CHECK(symlink("loop", MS_PATH_JOIN(a, root, "loop")) == 0);
    const char *file = MS_PATH_JOIN(a, dir, "f");
    FILE *f = fopen(file, "w");
    CHECK(f != NULL);
    if (f != NULL) {
        fclose(f);
    }
    const char *real_root;
    MsProjectError err = {0};
    CHECK(ms_path_eval_symlinks(a, root, &real_root, &err));

    const char *got;
    CHECK(ms_path_eval_symlinks(a, MS_PATH_JOIN(a, root, "chain", "f"), &got, &err));
    CHECK_STR(got, MS_PATH_JOIN(a, real_root, "real", "f"));
    CHECK(ms_path_eval_symlinks(a, MS_PATH_JOIN(a, root, "link", "..", "real"), &got, &err));
    CHECK_STR(got, MS_PATH_JOIN(a, real_root, "real"));

    CHECK(!ms_path_eval_symlinks(a, MS_PATH_JOIN(a, root, "missing"), &got, &err));
    CHECK(ms_project_error_not_exist(&err));
    CHECK_STR(ms_project_error_text(a, &err), ms_arena_fmt(a, "lstat %s: no such file or directory", MS_PATH_JOIN(a, real_root, "missing")).ptr);
    CHECK(!ms_path_eval_symlinks(a, MS_PATH_JOIN(a, root, "loop"), &got, &err));
    CHECK_STR(ms_project_error_text(a, &err), "EvalSymlinks: too many links");
    CHECK(!ms_path_eval_symlinks(a, MS_PATH_JOIN(a, file, "x"), &got, &err));
    CHECK_STR(ms_project_error_text(a, &err), "not a directory");

    const char *abs;
    CHECK(ms_path_abs(a, "x/../y", &abs, &err));
    CHECK(ms_path_is_abs(abs));
    unlink(file);
    unlink(MS_PATH_JOIN(a, root, "chain"));
    unlink(MS_PATH_JOIN(a, root, "link"));
    unlink(MS_PATH_JOIN(a, root, "loop"));
    rmdir(dir);
    rmdir(root);
}

int main(void) {
    MsArena a = {0};
    test_clean(&a);
    test_split(&a);
    test_rel(&a);
    test_symlinks(&a);
    ms_arena_free(&a);
    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    return 0;
}

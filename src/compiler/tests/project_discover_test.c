/* Unit test of source discovery (src/compiler/src/project/discover.c), with the rules of crates/ms-driver discovery.rs. */
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

static MsArena arena;
static char root[64];

static void write_file(const char *name, const char *text) {
    const char *path = MS_PATH_JOIN(&arena, root, name);
    char *copy = ms_arena_strndup(&arena, path, strlen(path));
    for (char *slash = strchr(copy + strlen(root) + 1, '/'); slash != NULL; slash = strchr(slash + 1, '/')) {
        *slash = 0;
        mkdir(copy, 0700);
        *slash = '/';
    }
    FILE *f = fopen(path, "w");
    CHECK(f != NULL);
    if (f != NULL) {
        fputs(text, f);
        fclose(f);
    }
}

/* The relative paths found, joined by spaces. */
static const char *relative(const char *const *paths, uint32_t count, const char *base) {
    MsBuf text = {0};
    for (uint32_t i = 0; i < count; i++) {
        const char *rel;
        MsProjectError err = {0};
        CHECK(ms_path_rel(&arena, base, paths[i], &rel, &err));
        ms_buf_printf(&text, "%s%s", i > 0 ? " " : "", rel);
    }
    const char *result = ms_arena_strndup(&arena, text.data == NULL ? "" : text.data, text.len);
    ms_buf_free(&text);
    return result;
}

static void expect_paths(const char *target, const char *want) {
    const char **paths;
    uint32_t count;
    MsProjectError err = {0};
    if (!ms_project_format_paths(&arena, target, &paths, &count, &err)) {
        fprintf(stderr, "%s: %s\n", target, ms_project_error_text(&arena, &err));
        failures++;
        return;
    }
    const char *real;
    CHECK(ms_path_eval_symlinks(&arena, root, &real, &err));
    const char *got = relative(paths, count, real);
    if (strcmp(got, want) != 0) {
        fprintf(stderr, "%s: got \"%s\", want \"%s\"\n", target, got, want);
        failures++;
    }
}

int main(void) {
    snprintf(root, sizeof root, "%s", "/tmp/ms_discover_XXXXXX");
    CHECK(mkdtemp(root) != NULL);
    write_file("ms.toml", "[project]\nname = \"p\"\nsource = \"src\"\nentry = \"src/main.ms\"\n");
    write_file("src/main.ms", "");
    write_file("src/b.ms", "");
    write_file("src/sub/a.ms", "");
    write_file("src/sub/a_test.ms", "");
    write_file("src/sub/notes.txt", "");
    write_file("src/vendor/v.ms", "");
    write_file("src/.hidden/h.ms", "");
    write_file("src/nested/ms.toml", "[project]\nname = \"n\"\nsource = \".\"\n");
    write_file("src/nested/n.ms", "");
    write_file("tests/x_bench.ms", "");
    write_file("tests/helper.ms", "");
    write_file("test.ms", "");
    write_file("node_modules/dep_test.ms", "");
    CHECK(symlink("sub", MS_PATH_JOIN(&arena, root, "src/linkdir.ms")) == 0);
    CHECK(symlink("b.ms", MS_PATH_JOIN(&arena, root, "src/alias.ms")) == 0);

    /* A manifest: source modules, tests elsewhere under the root, then the entry (a duplicate is not collapsed). */
    expect_paths(MS_PATH_JOIN(&arena, root, "ms.toml"),
                 "src/b.ms src/b.ms src/main.ms src/sub/a.ms src/sub/a_test.ms test.ms tests/x_bench.ms src/main.ms");
    /* A directory is its own source tree; the nested project and directory links are skipped. */
    expect_paths(root, "src/b.ms src/b.ms src/main.ms src/sub/a.ms src/sub/a_test.ms test.ms tests/helper.ms tests/x_bench.ms");
    expect_paths(MS_PATH_JOIN(&arena, root, "src/b.ms"), "src/b.ms");

    /* Formatting reads only a project's own modules: dependencies and a missing ms.lock do not matter. */
    write_file("dep/ms.toml", "[project]\nname = \"d\"\nsource = \"src\"\n\n[dependencies]\n\"@a\" = { url = \"file:///x\", tag = \"v1\" }\n");
    write_file("dep/src/z.ms", "");
    expect_paths(MS_PATH_JOIN(&arena, root, "dep/ms.toml"), "dep/src/z.ms");

    const char **paths;
    uint32_t count;
    MsProjectError err = {0};
    CHECK(!ms_project_format_paths(&arena, MS_PATH_JOIN(&arena, root, "missing"), &paths, &count, &err));
    CHECK(strncmp(ms_project_error_text(&arena, &err), "stat ", 5) == 0);

    char command[160];
    snprintf(command, sizeof command, "rm -rf %s", root);
    CHECK(system(command) == 0);
    ms_arena_free(&arena);
    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    return 0;
}

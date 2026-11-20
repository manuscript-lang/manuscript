/* Unit test of ms.toml reading and import resolution (compiler/src/project/{manifest,resolve}.c), with the cases of
 * crates/ms-driver/tests/project_project.rs. */
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

#define MANIFEST "[project]\nname = \"sample\"\nsource = \"src\"\nentry = \"src/main.ms\"\n"

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

static void new_project(void) {
    snprintf(root, sizeof root, "%s", "/tmp/ms_project_XXXXXX");
    CHECK(mkdtemp(root) != NULL);
    write_file("src/main.ms", "");
    write_file("src/value.ms", "");
    write_file("src/main.txt", "");
    mkdir(MS_PATH_JOIN(&arena, root, "src/directory.ms"), 0700);
}

static void remove_tree(void) {
    char command[160];
    snprintf(command, sizeof command, "rm -rf %s", root);
    CHECK(system(command) == 0);
}

typedef enum Outcome { OK, FAILS, UNSUPPORTED } Outcome;

/* Reads `manifest`; for a failure, `want` must be a substring of the error text. */
static bool read_manifest(const char *manifest, MsProject *p, MsProjectError *err, const char **text) {
    write_file("ms.toml", manifest);
    const bool ok = ms_project_read(&arena, MS_PATH_JOIN(&arena, root, "ms.toml"), p, err);
    *text = ok ? "" : ms_project_error_text(&arena, err);
    return ok;
}

static void expect_error(const char *name, const char *manifest, const char *want) {
    MsProject p;
    MsProjectError err = {0};
    const char *text;
    if (read_manifest(manifest, &p, &err, &text) || strstr(text, want) == NULL) {
        fprintf(stderr, "%s: got \"%s\", want \"%s\"\n", name, text, want);
        failures++;
    }
}

static void expect_unsupported(const char *name, const char *manifest) {
    MsProject p;
    MsProjectError err = {0};
    const char *text;
    if (read_manifest(manifest, &p, &err, &text) || !ms_project_error_is_unsupported(&err)) {
        fprintf(stderr, "%s: want unsupported, got \"%s\"\n", name, text);
        failures++;
    }
}

static void test_read(void) {
    MsProject p;
    MsProjectError err = {0};
    const char *text;
    const char *source = "[project]\nname = \"sample # \\\"quoted\\\"\" # c\nsource = 'src'\nentry = \"src/main.ms\"\n"
                         "[aliases]\n\"@values\" = \"src\" # directory\n\"@one\" = \"src/value.ms\"\n";
    CHECK(read_manifest(source, &p, &err, &text));
    CHECK(strcmp(p.name, "sample # \"quoted\"") == 0);
    CHECK(strcmp(p.configuration, source) == 0);
    CHECK(strcmp(p.source, MS_PATH_JOIN(&arena, p.root, "src")) == 0);
    CHECK(strcmp(p.entry, MS_PATH_JOIN(&arena, p.source, "main.ms")) == 0);
    CHECK(p.alias_count == 2 && strcmp(p.aliases[0].name, "@one") == 0 && strcmp(p.aliases[1].name, "@values") == 0);
    const char *want = MS_PATH_JOIN(&arena, p.source, "value.ms");
    static const char *const imports[] = {"./value.ms", "@values/value.ms", "@one"};
    for (size_t i = 0; i < sizeof imports / sizeof imports[0]; i++) {
        const char *got;
        CHECK(ms_project_resolve_import(&arena, &p, p.entry, imports[i], &got, &err));
        CHECK(strcmp(got, want) == 0);
    }
    CHECK(read_manifest("\xef\xbb\xbf[ project ]\nname = \"sample\"\nsource = \"src\"\n[ aliases ]\n\"@a\" = \"src\"\n", &p, &err, &text));
    CHECK(p.alias_count == 1 && p.entry[0] == 0);
}

static void test_errors(void) {
    expect_error("no table", "name = \"sample\"\n", "ms.toml:1:1: invalid manifest assignment");
    expect_error("unknown table", MANIFEST "[adapters]\n", "ms.toml:5:1: unsupported manifest table [adapters]");
    expect_error("package table", "[package]\n", "rename it to [project]");
    expect_error("unknown key", MANIFEST "license = \"MIT\"\n", "ms.toml:5:1: unknown project key license");
    expect_error("unknown number key", MANIFEST "retries = 3\n", "unknown project key retries");
    expect_error("missing name", "[project]\nsource = \"src\"\n", "ms.toml:1:1: [project] requires name and source; missing: name,");
    expect_error("missing both", "[project]\n", "missing: name, source,");
    expect_error("source is file", "[project]\nname = \"s\"\nsource = \"src/main.ms\"\n", "existing directory");
    expect_error("missing source", "[project]\nname = \"s\"\nsource = \"missing\"\n", "ms.toml:3:10: lstat");
    expect_error("entry extension", "[project]\nname = \"s\"\nsource = \"src\"\nentry = \"src/main.txt\"\n", "entry requires .ms extension");
    expect_error("entry is directory", "[project]\nname = \"s\"\nsource = \"src\"\nentry = \"src/directory.ms\"\n", "regular file");
    expect_error("empty entry", "[project]\nname = \"s\"\nsource = \"src\"\nentry = \"\"\n", "project entry cannot be empty");
    expect_error("reserved alias", MANIFEST "[aliases]\n\"@std\" = \"src\"\n", "invalid or reserved alias @std");
    expect_error("invalid alias", MANIFEST "[aliases]\n\"@2bad\" = \"src\"\n", "invalid or reserved alias");
    expect_error("alias hint", MANIFEST "[aliases]\nlib = \"src\"\n", "(did you mean @lib?)");
    expect_error("alias chaining", MANIFEST "[aliases]\n\"@one\" = \"@two\"\n", "ms.toml:6:10: invalid alias target @two");
    expect_error("NUL in value", "[project]\nname = \"s\"\nsource = \"src\"\nentry = \"src/ma\\u0000in.ms\"\n", "ms.toml:4:9: manifest value for entry contains a NUL");
    expect_error("escape", "[project]\nname = \"s\"\nsource = \"..\"\n", "escapes project root");
    expect_error("alias escape", MANIFEST "[aliases]\n\"@up\" = \"/\"\n", "alias @up target cannot be resolved");

    MsProject p;
    MsProjectError err = {0};
    const char *text;
    expect_error("std alias", "[project]\nname = \"s\"\nsource = \"src\"\n[aliases]\nstd = \"src\"\n", "invalid or reserved alias std;");
    CHECK(!read_manifest("[project]\nname = \"s\"\nsource = \"src\"\n[aliases]\nstd = \"src\"\n", &p, &err, &text) && strstr(text, "did you mean") == NULL);

    char *long_line = malloc(70100);
    CHECK(long_line != NULL);
    if (long_line != NULL) {
        const size_t head = strlen(MANIFEST "# ");
        memcpy(long_line, MANIFEST "# ", head);
        memset(long_line + head, 'x', 70000);
        memcpy(long_line + head + 70000, "\n", 2);
        expect_error("line too long", long_line, "ms.toml:5:1: line too long");
        free(long_line);
    }
}

static void test_unsupported(void) {
    expect_unsupported("duplicate table", MANIFEST "[project]\n");
    expect_unsupported("duplicate key", MANIFEST "name = \"other\"\n");
    expect_unsupported("missing value", "[project]\nname\n");
    expect_unsupported("bare word", "[project]\nname = sample\n");
    expect_unsupported("version", MANIFEST "version = \"1.0.0\"\n");
    expect_unsupported("embed", MANIFEST "[embed]\n\"@assets\" = \"src\"\n");
    expect_unsupported("dependencies", MANIFEST "[dependencies]\n");
    expect_unsupported("array", MANIFEST "[aliases]\n\"@a\" = [\"x\"]\n");
    expect_unsupported("name as number", "[project]\nname = 3\nsource = \"src\"\n");
}

static void test_imports(void) {
    MsProject p;
    MsProjectError err = {0};
    const char *text;
    CHECK(read_manifest(MANIFEST "[aliases]\n\"@dir\" = \"src\"\n\"@file\" = \"src/value.ms\"\n", &p, &err, &text));
    static const char *const bad[] = {"value.ms", "/value.ms", ".\\dir\\value.ms", "./value", "@missing/value.ms", "@dir_extra/value.ms",
                                      "@dir", "@dir/value", "@file/suffix.ms", "@std/value.ms", "./", "../.."};
    for (size_t i = 0; i < sizeof bad / sizeof bad[0]; i++) {
        const char *got;
        if (ms_project_resolve_import(&arena, &p, p.entry, bad[i], &got, &err)) {
            fprintf(stderr, "accepted invalid import %s\n", bad[i]);
            failures++;
        }
    }
    const char *got;
    CHECK(!ms_project_resolve_import(&arena, &p, p.entry, "/abs/money.ms", &got, &err));
    CHECK(strstr(ms_project_error_text(&arena, &err), "absolute import paths are not supported") != NULL);
    CHECK(!ms_project_resolve_import(&arena, &p, p.entry, "@missing/x.ms", &got, &err));
    CHECK(strstr(ms_project_error_text(&arena, &err), "unknown import alias @missing; declared aliases: @dir, @file") != NULL);
    CHECK(!ms_project_resolve_import(&arena, &p, p.entry, "./value", &got, &err));
    CHECK(strcmp(ms_project_error_text(&arena, &err), "import path requires .ms extension; write \"./value.ms\"") == 0);
    CHECK(!ms_project_resolve_import(&arena, &p, p.entry, "../../escape.ms", &got, &err));
    CHECK(strstr(ms_project_error_text(&arena, &err), "lstat") != NULL || strstr(ms_project_error_text(&arena, &err), "escapes project root") != NULL);
    CHECK(!ms_project_resolve_import(&arena, &p, p.entry, "./", &got, &err));
    CHECK(strstr(ms_project_error_text(&arena, &err), "names a directory, not a module") != NULL);

    CHECK(symlink("/etc/hostname", MS_PATH_JOIN(&arena, p.source, "out.ms")) == 0);
    CHECK(!ms_project_resolve_import(&arena, &p, p.entry, "./out.ms", &got, &err));
    CHECK(strstr(ms_project_error_text(&arena, &err), "path escapes project root") != NULL);
    CHECK(symlink(MS_PATH_JOIN(&arena, p.source, "value.ms"), MS_PATH_JOIN(&arena, p.source, "link.ms")) == 0);
    CHECK(ms_project_resolve_import(&arena, &p, p.entry, "./link.ms", &got, &err));
    CHECK(strcmp(got, MS_PATH_JOIN(&arena, p.source, "value.ms")) == 0);

    const char *found = ms_project_find_manifest(&arena, MS_PATH_JOIN(&arena, root, "src/main.ms"));
    CHECK(found != NULL && strcmp(found, MS_PATH_JOIN(&arena, root, "ms.toml")) == 0);
    write_file("nested/src/main.ms", "");
    write_file("nested/ms.toml", "invalid configuration");
    found = ms_project_find_manifest(&arena, MS_PATH_JOIN(&arena, root, "nested/src/main.ms"));
    CHECK(found != NULL && strcmp(found, MS_PATH_JOIN(&arena, root, "nested/ms.toml")) == 0);
}

static void test_quote(void) {
    CHECK(strcmp(ms_project_quote(&arena, "a\"b\\c\n"), "\"a\\\"b\\\\c\\n\"") == 0);
    CHECK(strcmp(ms_project_quote(&arena, "/tmp/x y"), "\"/tmp/x y\"") == 0);
    CHECK(strcmp(ms_project_quote(&arena, "\x01\x7f"), "\"\\x01\\x7f\"") == 0);
}

int main(void) {
    new_project();
    test_read();
    test_errors();
    test_unsupported();
    test_imports();
    test_quote();
    remove_tree();
    ms_arena_free(&arena);
    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    return 0;
}

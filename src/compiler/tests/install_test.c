/* Unit test of `ms install` (src/compiler/src/project/install.c) against local git repositories: the fetch, the cache, the
 * lock, and the checks a download must pass. Needs `git` on PATH. */
#define _XOPEN_SOURCE 700
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "ms/packages.h"

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

static void run(const char *format, ...) __attribute__((format(printf, 1, 2)));
static void run(const char *format, ...) {
    char command[1024];
    va_list args;
    va_start(args, format);
    vsnprintf(command, sizeof command, format, args);
    va_end(args);
    if (system(command) != 0) {
        fprintf(stderr, "command failed: %s\n", command);
        failures++;
    }
}

static const char *path(const char *name) {
    return MS_PATH_JOIN(&arena, root, name);
}

static void write_file(const char *name, const char *text) {
    char *copy = ms_arena_strndup(&arena, path(name), strlen(path(name)));
    for (char *slash = strchr(copy + strlen(root) + 1, '/'); slash != NULL; slash = strchr(slash + 1, '/')) {
        *slash = 0;
        mkdir(copy, 0700);
        *slash = '/';
    }
    FILE *f = fopen(copy, "w");
    CHECK(f != NULL);
    if (f != NULL) {
        fputs(text, f);
        fclose(f);
    }
}

static const char *read_text(const char *name) {
    size_t length;
    MsProjectError err = {0};
    const char *text = ms_project_read_file(&arena, path(name), &length, &err);
    return text != NULL ? text : "";
}

/* A package repository `name` at `version` (ms.toml and one source file), committed and tagged `tag`. */
static void commit_package(const char *name, const char *version, const char *tag) {
    write_file(MS_PATH_JOIN(&arena, name, "ms.toml"),
               ms_arena_fmt(&arena, "[project]\nname = \"%s\"\nsource = \"src\"\nversion = \"%s\"\neffects = [\"std.fs.read\"]\n", name, version).ptr);
    write_file(MS_PATH_JOIN(&arena, name, "src/lib.ms"), ms_arena_fmt(&arena, "// %s\n", version).ptr);
    run("cd %s/%s && git add -A && git commit -q -m %s && git tag %s", root, name, tag, tag);
}

static void make_repository(const char *name) {
    run("mkdir -p %s/%s && cd %s/%s && git init -q -b main && git config user.email t@example.com && git config user.name t",
        root, name, root, name);
}

/* `ms install` of the project at root/project, its report joined by newlines, or the error text prefixed `error: `. */
static const char *install(const char *const *update, uint32_t count, bool locked, bool frozen) {
    MsInstallReport report;
    MsProjectError err = {0};
    const MsInstallOptions options = {.manifest = path("project/ms.toml"), .update = update, .update_count = count, .locked = locked, .frozen = frozen};
    if (!ms_install(&arena, &options, &report, &err)) {
        return ms_arena_fmt(&arena, "error: %s", ms_project_error_text(&arena, &err)).ptr;
    }
    MsBuf text = {0};
    static const char *const states[] = {"fetched", "cached", "kept"};
    for (uint32_t i = 0; i < report.count; i++) {
        const MsInstalledCopy *c = &report.copies[i];
        ms_buf_printf(&text, "%s %s %s %s\n", c->name, c->copy.entry.spec + strlen(root) + 7, states[c->state], c->effects);
    }
    const char *result = ms_arena_strndup(&arena, text.data == NULL ? "" : text.data, text.len);
    ms_buf_free(&text);
    return result;
}

static void write_project(const char *dependency) {
    write_file("project/ms.toml", ms_arena_fmt(&arena, "[project]\nname = \"app\"\nsource = \"src\"\nentry = \"src/main.ms\"\n[dependencies]\n%s\n", dependency).ptr);
    write_file("project/src/main.ms", "fn main() {}\n");
}

int main(void) {
    snprintf(root, sizeof root, "/tmp/ms-install-test-XXXXXX");
    if (mkdtemp(root) == NULL) {
        return 1;
    }
    setenv("MS_PACKAGE_CACHE", path("cache"), 1);
    setenv("GIT_CONFIG_GLOBAL", "/dev/null", 1);
    setenv("GIT_CONFIG_SYSTEM", "/dev/null", 1);

    make_repository("wire");
    commit_package("wire", "1.0.0", "v1.0.0");
    commit_package("wire", "1.1.0", "v1.1.0");
    const char *url = ms_arena_fmt(&arena, "file://%s/wire", root).ptr;
    write_project(ms_arena_fmt(&arena, "\"@wire\" = { url = \"%s\", version = \"^1.0\" }", url).ptr);

    /* The highest tag that satisfies the requirement is fetched, pinned and reported. */
    const char *first = install(NULL, 0, false, false);
    CHECK(strstr(first, "@wire ") == first);
    CHECK(strstr(first, "/wire#v1.1.0 fetched std.fs.read\n") != NULL);
    const char *lock = read_text("project/ms.lock");
    CHECK(strstr(lock, "# Written by `ms install`.") == lock);
    CHECK(strstr(lock, "wire@v1.1.0\" = \"") != NULL && strstr(lock, "#v1.1.0 ") != NULL && strstr(lock, " sha256:") != NULL);

    /* A second install keeps the locked copy from the cache and leaves ms.lock alone. */
    CHECK(strstr(install(NULL, 0, true, false), "kept std.fs.read") != NULL);
    CHECK(strcmp(read_text("project/ms.lock"), lock) == 0);

    /* The cache is read-only and a removed copy is downloaded again at the locked revision, to the same hash. */
    run("chmod -R u+w %s && rm -rf %s", path("cache"), path("cache"));
    CHECK(strstr(install(NULL, 0, true, false), "fetched std.fs.read") != NULL);
    CHECK(strcmp(read_text("project/ms.lock"), lock) == 0);

    /* A copy edited in the cache is noticed and restored. */
    run("cd %s && for d in */; do chmod -R u+w \"$d\"; echo tampered > \"$d/src/lib.ms\"; done", path("cache"));
    CHECK(strstr(install(NULL, 0, true, false), "fetched std.fs.read") != NULL);

    /* A new requirement changes the lock: --locked refuses, --frozen leaves it, a plain install writes it. */
    write_project(ms_arena_fmt(&arena, "\"@wire\" = { url = \"%s\", tag = \"v1.0.0\" }", url).ptr);
    CHECK(strncmp(install(NULL, 0, true, false), "error: ms.lock needs to be updated but --locked was passed", 58) == 0);
    CHECK(strcmp(read_text("project/ms.lock"), lock) == 0);
    CHECK(strstr(install(NULL, 0, false, true), "/wire#v1.0.0") != NULL);
    CHECK(strcmp(read_text("project/ms.lock"), lock) == 0);
    CHECK(strstr(install(NULL, 0, false, false), "/wire#v1.0.0") != NULL);
    CHECK(strstr(read_text("project/ms.lock"), "wire@v1.0.0\"") != NULL);

    /* No dependencies removes ms.lock. */
    write_file("project/ms.toml", "[project]\nname = \"app\"\nsource = \"src\"\nentry = \"src/main.ms\"\n");
    CHECK(strcmp(install(NULL, 0, false, false), "") == 0);
    CHECK(access(path("project/ms.lock"), F_OK) != 0);

    /* A tag the repository lacks. */
    write_project(ms_arena_fmt(&arena, "\"@wire\" = { url = \"%s\", tag = \"v9.9.9\" }", url).ptr);
    CHECK(strstr(install(NULL, 0, false, false), "error: package ") != NULL);
    CHECK(strstr(install(NULL, 0, false, false), "v9.9.9 is not a tag of") != NULL);

    /* A package may not hold a link, an entry, [embed], a Windows-hostile name or names differing by case. */
    make_repository("bad");
    commit_package("bad", "1.0.0", "v1.0.0");
    write_file("bad/link-target", "x\n");
    run("cd %s/bad && ln -s link-target link && git add -A && git commit -q -m link && git tag v1.1.0", root);
    const char *bad = ms_arena_fmt(&arena, "file://%s/bad", root).ptr;
    write_project(ms_arena_fmt(&arena, "\"@bad\" = { url = \"%s\", tag = \"v1.1.0\" }", bad).ptr);
    CHECK(strstr(install(NULL, 0, false, false), "contains the symbolic link link; a package holds regular files only") != NULL);
    run("cd %s/bad && git rm -q -f link && printf x > aux.txt && git add -A && git commit -q -m aux && git tag v1.2.0", root);
    write_project(ms_arena_fmt(&arena, "\"@bad\" = { url = \"%s\", tag = \"v1.2.0\" }", bad).ptr);
    CHECK(strstr(install(NULL, 0, false, false), "aux.txt has the name \"aux.txt\", which Windows cannot create; rename it") != NULL);
    run("cd %s/bad && git rm -q -f aux.txt && printf x > Readme && printf y > README && git add -A && git commit -q -m case && git tag v1.3.0", root);
    write_project(ms_arena_fmt(&arena, "\"@bad\" = { url = \"%s\", tag = \"v1.3.0\" }", bad).ptr);
    CHECK(strstr(install(NULL, 0, false, false), "differ only by letter case") != NULL);

    run("chmod -R u+w %s; rm -rf %s", root, root);
    ms_arena_free(&arena);
    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    return 0;
}

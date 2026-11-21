/* Unit test of `ms install` (src/compiler/src/project/install.c) against local git repositories: the fetch, the cache, the
 * lock, and the checks a download must pass. Needs `git` on PATH. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "host_test.h"
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
static char root[256];

static const char *path(const char *name) {
    return MS_PATH_JOIN(&arena, root, name);
}

static void write_file(const char *name, const char *text) {
    char *copy = ms_arena_strndup(&arena, path(name), strlen(path(name)));
    for (char *slash = strchr(copy + strlen(root) + 1, '/'); slash != NULL; slash = strchr(slash + 1, '/')) {
        *slash = 0;
        host_mkdir(copy);
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

/* The `file://` URL of the repository `name`. */
static const char *repository_url(const char *name) {
    const char *directory = path(name);
    return ms_arena_fmt(&arena, "file://%s%s", directory[0] == '/' ? "" : "/", directory).ptr;
}

/* A package repository `name` at `version` (ms.toml and one source file), committed and tagged `tag`, plus `extra`. */
static void commit_files(const char *name, const char *version, const char *tag, const HostFile *extra, size_t extra_count) {
    HostFile files[8] = {
        {"ms.toml",
         ms_arena_fmt(&arena, "[project]\nname = \"%s\"\nsource = \"src\"\nversion = \"%s\"\neffects = [\"std.fs.read\"]\n", name, version).ptr,
         "100644"},
        {"src/lib.ms", ms_arena_fmt(&arena, "// %s\n", version).ptr, "100644"},
    };
    for (size_t i = 0; i < extra_count; i++) {
        files[2 + i] = extra[i];
    }
    CHECK(host_git_commit(&arena, path(name), path("scratch"), files, 2 + extra_count, tag));
}

static void commit_package(const char *name, const char *version, const char *tag) { commit_files(name, version, tag, NULL, 0); }

/* Makes every copy in the cache writable and edits its source. */
static void tamper_cache(void) {
    const char *const *names;
    uint32_t count;
    MsProjectError err = {0};
    CHECK(ms_path_list_dir(&arena, path("cache"), "open", &names, &count, &err));
    for (uint32_t i = 0; i < count; i++) {
        const char *file = MS_PATH_JOIN(&arena, path("cache"), names[i], "src/lib.ms");
        if (host_exists(file)) {
            const MsSysError writable = ms_sys_fs_chmod(file, 0644);
            CHECK(writable == 0);
            FILE *f = fopen(file, "w");
            CHECK(f != NULL);
            if (f != NULL) {
                fputs("tampered\n", f);
                fclose(f);
            }
        }
    }
}

static void make_repository(const char *name) { CHECK(host_git_init(&arena, path(name))); }

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
    if (!host_make_root(root, sizeof root, "ms-install-test")) {
        return 1;
    }
    host_mkdir(path("scratch"));
    host_set_env("MS_PACKAGE_CACHE", path("cache"));
    host_set_env("GIT_CONFIG_GLOBAL", "/dev/null");
    host_set_env("GIT_CONFIG_SYSTEM", "/dev/null");

    make_repository("wire");
    commit_package("wire", "1.0.0", "v1.0.0");
    commit_package("wire", "1.1.0", "v1.1.0");
    const char *url = repository_url("wire");
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
    host_remove_tree(path("cache"));
    CHECK(strstr(install(NULL, 0, true, false), "fetched std.fs.read") != NULL);
    CHECK(strcmp(read_text("project/ms.lock"), lock) == 0);

    /* A copy edited in the cache is noticed and restored. */
    tamper_cache();
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
    CHECK(!host_exists(path("project/ms.lock")));

    /* A tag the repository lacks. */
    write_project(ms_arena_fmt(&arena, "\"@wire\" = { url = \"%s\", tag = \"v9.9.9\" }", url).ptr);
    CHECK(strstr(install(NULL, 0, false, false), "error: package ") != NULL);
    CHECK(strstr(install(NULL, 0, false, false), "v9.9.9 is not a tag of") != NULL);

    /* A package may not hold a link, an entry, [embed], a Windows-hostile name or names differing by case. */
    make_repository("bad");
    commit_package("bad", "1.0.0", "v1.0.0");
    const HostFile target = {"link-target", "x\n", "100644"};
    const HostFile link = {"link", "link-target", "120000"};
    const HostFile with_link[] = {target, link};
    commit_files("bad", "1.0.0", "v1.1.0", with_link, 2);
    const char *bad = repository_url("bad");
    write_project(ms_arena_fmt(&arena, "\"@bad\" = { url = \"%s\", tag = \"v1.1.0\" }", bad).ptr);
    CHECK(strstr(install(NULL, 0, false, false), "contains the symbolic link link; a package holds regular files only") != NULL);
    const HostFile aux = {"aux.txt", "x", "100644"};
    const HostFile with_aux[] = {target, aux};
    commit_files("bad", "1.0.0", "v1.2.0", with_aux, 2);
    write_project(ms_arena_fmt(&arena, "\"@bad\" = { url = \"%s\", tag = \"v1.2.0\" }", bad).ptr);
    CHECK(strstr(install(NULL, 0, false, false), "aux.txt has the name \"aux.txt\", which Windows cannot create; rename it") != NULL);
    const HostFile lower = {"Readme", "x", "100644"};
    const HostFile upper = {"README", "y", "100644"};
    const HostFile with_case[] = {target, lower, upper};
    commit_files("bad", "1.0.0", "v1.3.0", with_case, 3);
    write_project(ms_arena_fmt(&arena, "\"@bad\" = { url = \"%s\", tag = \"v1.3.0\" }", bad).ptr);
    CHECK(strstr(install(NULL, 0, false, false), "differ only by letter case") != NULL);

    host_remove_tree(root);
    ms_arena_free(&arena);
    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    return 0;
}

/* Unit test of package dependencies in the module graph (compiler/src/project/attach.c): a project installed from a
 * local git repository loads with its package modules, and the lock, the cache and the effect rules are enforced.
 * Needs `git` on PATH. */
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

static void write_project(const char *effects) {
    write_file("project/ms.toml", ms_arena_fmt(&arena, "[project]\nname = \"app\"\nsource = \"src\"\nentry = \"src/main.ms\"\n[dependencies]\n\"@wire\" = { url = \"%s\", tag = \"v1.1.0\" }\n%s", repository_url("wire"), effects).ptr);
    write_file("project/src/main.ms", "import (\n\tx from \"@wire/lib.ms\",\n)\nfn main() Int:\n\treturn 0\n");
}

/* The modules `entry` loads (names joined by spaces and the package count), or the first diagnostic's message prefixed
 * `error: `, or `unsupported: ` and why. */
static const char *load_entry(const char *entry, bool with_packages);

static const char *load(bool with_packages) { return load_entry(path("project/src/main.ms"), with_packages); }

static const char *load_entry(const char *entry, bool with_packages) {
    MsNames names;
    ms_names_init(&names);
    MsGraph graph;
    MsProjectError err = {0};
    const bool ok = with_packages ? ms_project_load_packages(&arena, &names, entry, &graph, &err) : ms_project_load(&arena, &names, entry, &graph, &err);
    if (!ok) {
        return ms_arena_fmt(&arena, "unsupported: %s", ms_project_error_text(&arena, &err)).ptr;
    }
    if (graph.ndiagnostics > 0) {
        return ms_arena_fmt(&arena, "error: %.*s", (int)graph.diagnostics[0].diag.message.len, graph.diagnostics[0].diag.message.ptr).ptr;
    }
    MsBuf text = {0};
    for (uint32_t i = 0; i < graph.count; i++) {
        ms_buf_printf(&text, "%s%s", i > 0 ? " " : "", graph.modules[i].name);
    }
    ms_buf_printf(&text, " |%u", graph.package_count);
    const char *result = ms_arena_strndup(&arena, text.data, text.len);
    ms_buf_free(&text);
    return result;
}

int main(void) {
    if (!host_make_root(root, sizeof root, "ms-attach-test")) {
        return 1;
    }
    host_mkdir(path("scratch"));
    host_set_env("MS_PACKAGE_CACHE", path("cache"));
    host_set_env("GIT_CONFIG_GLOBAL", "/dev/null");
    host_set_env("GIT_CONFIG_SYSTEM", "/dev/null");

    make_repository("wire");
    commit_package("wire", "1.1.0", "v1.1.0");
    write_project("");

    /* Without a lock nothing is pinned. */
    CHECK(strstr(load(true), "error: ms.lock has no copy of ") != NULL);

    const MsInstallOptions options = {.manifest = path("project/ms.toml")};
    MsInstallReport report;
    MsProjectError err = {0};
    CHECK(ms_install(&arena, &options, &report, &err));

    /* The package declares an effect the project has not allowed. */
    CHECK(strstr(load(true), "error: package ") != NULL && strstr(load(true), "may use std.fs.read, which this project does not allow; add `@wire = [\"std.fs.read\"]`") != NULL);

    write_project("[effects]\n\"@wire\" = [\"std.fs.read\"]\n");
    const char *loaded = load(true);
    CHECK(strstr(loaded, "@file") == loaded && strstr(loaded, "wire@v1.1.0/src/lib.ms src/main.ms") != NULL && strstr(loaded, "src/main.ms") != NULL && strstr(loaded, " |1") != NULL);

    /* The checker must enforce package rules, so the plain loader hands the project to the Rust driver. */
    CHECK(strncmp(load(false), "unsupported: ", 13) == 0);

    /* A copy edited in the cache is refused as it is read. */
    tamper_cache();
    CHECK(strstr(load(true), "error: @") != NULL && strstr(load(true), "does not match ms.lock; run `ms install` to restore it") != NULL);

    /* A workspace: the app imports the lib through a path dependency, and both share the root's lock. */
    write_file("ws/ms.toml", "[workspace]\nmembers = [\"app\", \"libs/*\"]\n");
    write_file("ws/app/ms.toml", "[project]\nname = \"app\"\nsource = \"src\"\nentry = \"src/main.ms\"\n[dependencies]\n\"@util\" = { path = \"../libs/util\" }\n");
    write_file("ws/app/src/main.ms", "import (\n\tx from \"@util/util.ms\",\n)\nfn main() Int:\n\treturn 0\n");
    write_file("ws/libs/util/ms.toml", "[project]\nname = \"util\"\nsource = \"src\"\n");
    write_file("ws/libs/util/src/util.ms", "export fn one() Int:\n\treturn 1\n");
    const char *shared = load_entry(path("ws/app/src/main.ms"), true);
    CHECK(strstr(shared, "@workspace/util/src/util.ms app/src/main.ms") == NULL && strstr(shared, "@workspace/util/src/util.ms") != NULL && strstr(shared, " |1") != NULL);

    /* A path dependency on a directory the workspace does not list, and one without any workspace. */
    write_file("ws/app/ms.toml", "[project]\nname = \"app\"\nsource = \"src\"\nentry = \"src/main.ms\"\n[dependencies]\n\"@util\" = { path = \"../other\" }\n");
    write_file("ws/other/ms.toml", "[project]\nname = \"other\"\nsource = \"src\"\n");
    write_file("ws/other/src/x.ms", "// x\n");
    CHECK(strstr(load_entry(path("ws/app/src/main.ms"), true), "which is not a workspace member; list it under [workspace] members in ") != NULL);
    write_file("alone/ms.toml", "[project]\nname = \"a\"\nsource = \"src\"\nentry = \"src/main.ms\"\n[dependencies]\n\"@util\" = { path = \"../ws/libs/util\" }\n");
    write_file("alone/src/main.ms", "fn main() Int:\n\treturn 0\n");
    CHECK(strstr(load_entry(path("alone/src/main.ms"), true), "is a path dependency, but no ancestor ms.toml has [workspace] members") != NULL);

    /* The workspace rules: a member with its own lock, and two members with one name. */
    write_file("ws/app/ms.toml", "[project]\nname = \"app\"\nsource = \"src\"\nentry = \"src/main.ms\"\n[dependencies]\n\"@util\" = { path = \"../libs/util\" }\n");
    write_file("ws/libs/util/ms.lock", "");
    CHECK(strstr(load_entry(path("ws/app/src/main.ms"), true), "error: workspace member libs/util has its own ms.lock") != NULL);
    CHECK(ms_sys_fs_unlink(path("ws/libs/util/ms.lock")) == 0);
    write_file("ws/libs/dup/ms.toml", "[project]\nname = \"util\"\nsource = \"src\"\n");
    write_file("ws/libs/dup/src/x.ms", "// x\n");
    CHECK(strstr(load_entry(path("ws/app/src/main.ms"), true), "error: workspace members libs/dup and libs/util are both named \"util\"; rename one in [project]") != NULL);

    host_remove_tree(root);
    if (failures == 0) {
        puts("attach_test: ok");
    }
    return failures == 0 ? 0 : 1;
}

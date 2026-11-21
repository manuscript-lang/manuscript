/* Unit test of package dependencies in the module graph (compiler/src/project/attach.c): a project installed from a
 * local git repository loads with its package modules, and the lock, the cache and the effect rules are enforced.
 * Needs `git` on PATH. */
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

static void write_project(const char *effects) {
    write_file("project/ms.toml", ms_arena_fmt(&arena, "[project]\nname = \"app\"\nsource = \"src\"\nentry = \"src/main.ms\"\n[dependencies]\n\"@wire\" = { url = \"file://%s/wire\", tag = \"v1.1.0\" }\n%s", root, effects).ptr);
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
    snprintf(root, sizeof root, "/tmp/ms-attach-test-XXXXXX");
    if (mkdtemp(root) == NULL) {
        return 1;
    }
    setenv("MS_PACKAGE_CACHE", path("cache"), 1);
    setenv("GIT_CONFIG_GLOBAL", "/dev/null", 1);
    setenv("GIT_CONFIG_SYSTEM", "/dev/null", 1);

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
    run("cd %s && for d in */; do chmod -R u+w \"$d\"; echo tampered > \"$d/src/lib.ms\"; done", path("cache"));
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
    run("rm %s", path("ws/libs/util/ms.lock"));
    write_file("ws/libs/dup/ms.toml", "[project]\nname = \"util\"\nsource = \"src\"\n");
    write_file("ws/libs/dup/src/x.ms", "// x\n");
    CHECK(strstr(load_entry(path("ws/app/src/main.ms"), true), "error: workspace members libs/dup and libs/util are both named \"util\"; rename one in [project]") != NULL);

    run("chmod -R u+w %s && rm -rf %s", root, root);
    if (failures == 0) {
        puts("attach_test: ok");
    }
    return failures == 0 ? 0 : 1;
}

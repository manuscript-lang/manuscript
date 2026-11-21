/* Unit test of the rules a build owes its fetched packages (src/compiler/src/project/graph_check.c): no native declarations,
 * and no effect their manifest does not declare.
 * Needs `git` on PATH. */
#define _XOPEN_SOURCE 700
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "ms/packages.h"
#include "ms/std_embed.h"

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

static void make_repository(const char *name) {
    run("mkdir -p %s/%s && cd %s/%s && git init -q -b main && git config user.email t@example.com && git config user.name t",
        root, name, root, name);
}

/* Commits `lib.ms` of package `wire` with the manifest effects `effects` (a TOML array body), tagged `tag`. */
static void commit_wire(const char *effects, const char *lib, const char *tag) {
    write_file("wire/ms.toml", ms_arena_fmt(&arena, "[project]\nname = \"wire\"\nsource = \"src\"\neffects = [%s]\n", effects).ptr);
    write_file("wire/src/lib.ms", lib);
    run("cd %s/wire && git add -A && git commit -q -m %s && git tag %s", root, tag, tag);
}

static void write_project(const char *tag) {
    write_file("project/ms.toml", ms_arena_fmt(&arena, "[project]\nname = \"app\"\nsource = \"src\"\nentry = \"src/main.ms\"\n[dependencies]\n\"@wire\" = { url = \"file://%s/wire\", tag = \"%s\" }\n[effects]\n\"@wire\" = [\"std.net.connect\"]\n", root, tag).ptr);
    write_file("project/src/main.ms", "import (\n\tgo from \"@wire/lib.ms\",\n)\nfn main() Int:\n\treturn go()\n");
}

/* The errors owed the packages of the project, one per line, `+` when the scan saw through every package callable. */
static const char *owed(void) {
    MsNames names;
    ms_names_init(&names);
    MsGraph graph;
    MsProjectError err = {0};
    if (!ms_project_load_packages(&arena, &names, path("project/src/main.ms"), &graph, &err) || graph.ndiagnostics > 0) {
        return "load failed";
    }
    MsCheck check;
    ms_check_init(&check, &names);
    MsArena syntax = {0};
    uint32_t nfiles;
    const MsStdFile *files = ms_std_embedded(&nfiles);
    MsStr failure;
    CHECK(ms_std_load(&check, &syntax, files, nfiles, &failure));
    MsModId *ids = MS_NEW_N(&arena, MsModId, graph.count);
    bool *unchecked = MS_NEW_N(&arena, bool, graph.count);
    ms_graph_add_modules(&check, &names, &arena, &graph, ids);
    (void)ms_graph_check(&check, &graph, ids, unchecked);
    MsGraphDiag *found;
    uint32_t count;
    bool complete;
    CHECK(ms_graph_check_packages(&check, &arena, &graph, ids, &found, &count, &complete));
    MsBuf text = {0};
    for (uint32_t i = 0; i < count; i++) {
        ms_buf_printf(&text, "%s:%u: %.*s\n", found[i].file, found[i].diag.pos.line, (int)found[i].diag.message.len, found[i].diag.message.ptr);
    }
    ms_buf_puts(&text, complete ? "+" : "-");
    const char *result = ms_arena_strndup(&arena, text.data, text.len);
    ms_buf_free(&text);
    ms_check_free(&check);
    ms_names_free(&names);
    ms_arena_free(&syntax);
    return result;
}

static void install(void) {
    const MsInstallOptions options = {.manifest = path("project/ms.toml")};
    MsInstallReport report;
    MsProjectError err = {0};
    CHECK(ms_install(&arena, &options, &report, &err));
}

static const char *const calls_the_network = "import fetcher from \"@std/net/fetch.ms\"\nexport fn go() Int:\n    _f := fetcher()\n    return 1\n";

int main(void) {
    snprintf(root, sizeof root, "/tmp/ms-package-check-XXXXXX");
    if (mkdtemp(root) == NULL) {
        return 1;
    }
    setenv("MS_PACKAGE_CACHE", path("cache"), 1);
    setenv("GIT_CONFIG_GLOBAL", "/dev/null", 1);
    setenv("GIT_CONFIG_SYSTEM", "/dev/null", 1);
    make_repository("wire");

    /* A package that declares what it reaches is clean. */
    commit_wire("\"std.net.connect\"", calls_the_network, "v1.0.0");
    write_project("v1.0.0");
    install();
    const char *clean = owed();
    CHECK(strcmp(clean, "+") == 0);

    /* One that does not is an error at the call, naming the path. */
    commit_wire("", calls_the_network, "v1.1.0");
    write_project("v1.1.0");
    install();
    const char *reaches = owed();
    CHECK(strstr(reaches, ".ms:3: package @") != NULL && strstr(reaches, "reaches std.net.connect through go -> fetcher, which its ms.toml does not declare; add it to effects under [project], or stop calling it") != NULL);

    /* A native declaration in a package is refused. */
    commit_wire("", "export extern fn clock_now() Int\n", "v1.2.0");
    write_project("v1.2.0");
    install();
    CHECK(strstr(owed(), ".ms:1: package @") != NULL && strstr(owed(), "declares native `clock_now`; packages hold Manuscript source only, so call the standard library instead") != NULL);

    run("chmod -R u+w %s && rm -rf %s", root, root);
    if (failures == 0) {
        puts("package_check_test: ok");
    }
    return failures == 0 ? 0 : 1;
}

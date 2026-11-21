/* Unit test of the module graph loader (compiler/src/project/load.c), with the cases of crates/ms-driver/src/load.rs
 * and tests/load.rs. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "host_test.h"
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

static MsArena arena;
static MsNames names;
static char root[256];

static const char *path_of(const char *name) { return MS_PATH_JOIN(&arena, root, name); }

static void write_file(const char *name, const char *text) {
    const char *path = path_of(name);
    char *copy = ms_arena_strndup(&arena, path, strlen(path));
    for (char *slash = strchr(copy + strlen(root) + 1, '/'); slash != NULL; slash = strchr(slash + 1, '/')) {
        *slash = 0;
        host_mkdir(copy);
        *slash = '/';
    }
    FILE *f = fopen(path, "w");
    CHECK(f != NULL);
    if (f != NULL) {
        fputs(text, f);
        fclose(f);
    }
}

static MsGraph load(const char *name) {
    MsGraph graph;
    MsProjectError err = {0};
    CHECK(ms_project_load(&arena, &names, path_of(name), &graph, &err));
    return graph;
}

static const char *diag_text(const MsGraph *g, uint32_t i) {
    const MsGraphDiag *d = &g->diagnostics[i];
    return ms_arena_fmt(&arena, "%s:%u:%u: %.*s", d->file, d->diag.pos.line, d->diag.pos.column, (int)d->diag.message.len, d->diag.message.ptr).ptr;
}

static void test_chain(void) {
    write_file("a.ms", "import value from \"./b.ms\"\nimport also from \"./sub/c.ms\"\nimport fmt from \"@std/fmt\"\nexport fn main() Int: return 1\n");
    write_file("b.ms", "import value from \"./sub/c.ms\"\nexport fn value() Int: return 1\n");
    write_file("sub/c.ms", "export fn value() Int: return 1\n");
    MsGraph g = load("a.ms");
    CHECK(g.ndiagnostics == 0);
    CHECK(g.count == 3);
    CHECK_STR(g.entry, "a.ms");
    CHECK(g.project_root == NULL);
    if (g.count == 3) {
        CHECK_STR(g.modules[0].name, "sub/c.ms");
        CHECK_STR(g.modules[1].name, "b.ms");
        CHECK_STR(g.modules[2].name, "a.ms");
        CHECK(g.modules[2].syntax.nimports == 3);
        CHECK(g.modules[2].targets[0] == 1 && g.modules[2].targets[1] == 0 && g.modules[2].targets[2] == -1);
        CHECK(g.modules[1].targets[0] == 0);
    }
}

static void test_cycle(void) {
    write_file("x.ms", "import y from \"./y.ms\"\n");
    write_file("y.ms", "import x from \"./x.ms\"\n");
    MsGraph g = load("x.ms");
    CHECK(g.count == 0 && g.ndiagnostics == 1);
    if (g.ndiagnostics == 1) {
        CHECK_STR(diag_text(&g, 0), "y.ms:1:1: cyclic module dependency x.ms -> y.ms -> x.ms; modules cannot import each other in a loop, so move the shared declarations into a third module that both import");
    }
    g = load("y.ms");
    CHECK(g.ndiagnostics == 1);
    if (g.ndiagnostics == 1) {
        CHECK(strncmp(diag_text(&g, 0), "x.ms:1:1: cyclic module dependency y.ms -> x.ms -> y.ms;", 56) == 0);
    }
}

static void test_missing(void) {
    write_file("m.ms", "import value from \"./new.ms\"\n");
    MsGraph g = load("m.ms");
    CHECK(g.ndiagnostics == 1 && g.count == 0);
    if (g.ndiagnostics == 1) {
        CHECK(strncmp(diag_text(&g, 0), "m.ms:1:1: cannot find module ./new.ms (looked for ", 50) == 0);
    }
    write_file("bad.ms", "import value from \"value.ms\"\n");
    g = load("bad.ms");
    CHECK(g.ndiagnostics == 1);
    if (g.ndiagnostics == 1) {
        CHECK(strstr(diag_text(&g, 0), "imports require a relative path or alias") != NULL);
    }
    g = load("absent.ms");
    CHECK(g.ndiagnostics == 1);
    if (g.ndiagnostics == 1) {
        CHECK(strstr(diag_text(&g, 0), "file not found: ") != NULL);
    }
}

static void test_parse_errors(void) {
    write_file("p.ms", "import value from \"./q.ms\"\n");
    write_file("q.ms", "fn first() Int:\n    return +\n\nfn second() Int:\n    return +\n");
    MsGraph g = load("p.ms");
    CHECK(g.count == 0);
    CHECK(g.ndiagnostics >= 2);
    if (g.ndiagnostics >= 2) {
        CHECK(g.diagnostics[g.ndiagnostics - 1].phase == MS_GRAPH_PARSE);
        CHECK_STR(g.diagnostics[0].file, "q.ms");
        CHECK(g.diagnostics[0].diag.pos.line == 5);
        CHECK(g.diagnostics[g.ndiagnostics - 1].diag.pos.line == 2);
    }
    write_file("u.ms", "\xff\xfe\n");
    g = load("u.ms");
    CHECK(g.ndiagnostics == 1);
    if (g.ndiagnostics == 1) {
        CHECK_STR(diag_text(&g, 0), "u.ms:1:1: source must be valid UTF-8; re-save the file with UTF-8 encoding");
    }
}

static void test_project(void) {
    write_file("proj/ms.toml", "[project]\nname = \"app\"\nsource = \"src\"\nentry = \"src/main.ms\"\n[aliases]\n\"@lib\" = \"src/lib\"\n");
    write_file("proj/src/main.ms", "import a from \"@lib/a.ms\"\nexport fn main() Int: return 1\n");
    write_file("proj/src/lib/a.ms", "import b from \"../b.ms\"\n");
    write_file("proj/src/b.ms", "export fn b() Int: return 1\n");
    MsGraph g = load("proj/ms.toml");
    CHECK(g.ndiagnostics == 0);
    CHECK(g.count == 3);
    CHECK_STR(g.entry, "src/main.ms");
    CHECK_STR(g.manifest_file, "ms.toml");
    CHECK(g.manifest_pos.line == 1 && g.project_root != NULL);
    if (g.count == 3) {
        CHECK_STR(g.modules[0].name, "src/b.ms");
        CHECK_STR(g.modules[1].name, "src/lib/a.ms");
        CHECK_STR(g.modules[2].name, "src/main.ms");
    }
    /* A file below the manifest uses its aliases, and stays the sole entry. */
    write_file("proj/src/other.ms", "import a from \"@lib/a.ms\"\n");
    g = load("proj/src/other.ms");
    CHECK(g.ndiagnostics == 0 && g.count == 3 && g.project_root == NULL);
    CHECK_STR(g.entry, "src/other.ms");
    /* Escaping the project root. */
    write_file("proj/src/escape.ms", "import a from \"../../a.ms\"\n");
    g = load("proj/src/escape.ms");
    CHECK(g.ndiagnostics == 1);
    if (g.ndiagnostics == 1) {
        CHECK(strstr(diag_text(&g, 0), "path escapes project root") != NULL);
    }
    /* A broken manifest. */
    write_file("broken/ms.toml", "[project]\nname = \"app\"\nsource = \"missing\"\n");
    g = load("broken/ms.toml");
    CHECK(g.ndiagnostics == 1);
    if (g.ndiagnostics == 1) {
        CHECK(strncmp(diag_text(&g, 0), "ms.toml:3:10: path does not exist:", 34) == 0);
    }
    /* Anything the C reader lacks is handed back. */
    write_file("lib/ms.toml", "[project]\nname = \"app\"\nsource = \"src\"\n");
    write_file("lib/src/main.ms", "");
    MsProjectError err = {0};
    CHECK(!ms_project_load(&arena, &names, path_of("lib/ms.toml"), &g, &err) && ms_project_error_is_unsupported(&err));
    /* Packages are loaded by ms_project_load_packages; this entry point hands them back. */
    write_file("ws/ms.toml", "[workspace]\nmembers = [\"app\", \"pg\"]\n");
    write_file("ws/app/ms.toml", "[project]\nname = \"app\"\nsource = \"src\"\n[dependencies]\n\"@pg\" = { path = \"../pg\" }\n");
    write_file("ws/app/src/main.ms", "");
    write_file("ws/pg/ms.toml", "[project]\nname = \"pg\"\nsource = \"src\"\n");
    write_file("ws/pg/src/lib.ms", "");
    CHECK(!ms_project_load(&arena, &names, path_of("ws/app/src/main.ms"), &g, &err) && ms_project_error_is_unsupported(&err));
}


static MsGraph load_with(const char *name, const MsOverlayFile *files, uint32_t count) {
    MsGraph graph;
    MsProjectError err = {0};
    const MsOverlay overlay = {.files = files, .count = count};
    CHECK(ms_project_load_overlay(&arena, &names, path_of(name), &overlay, &graph, &err));
    return graph;
}

/* Unsaved buffers replace files on disk and add files that are not there. */
static void test_overlay(void) {
    write_file("ov/a.ms", "import b from \"./b.ms\"\nexport fn a() Int: return 1\n");
    write_file("ov/b.ms", "export fn b() Int: return 1\n");
    MsOverlayFile broken[] = {{.path = path_of("ov/b.ms"), .text = "export fn b(", .length = 12}};
    MsGraph g = load_with("ov/a.ms", broken, 1);
    CHECK(g.ndiagnostics >= 1);
    /* A new file only the editor has, imported by the entry, which may itself be unsaved. */
    const char *entry = "import c from \"./c.ms\"\nexport fn a() Int: return 1\n";
    const char *c = "export fn c() Int: return 1\n";
    MsOverlayFile added[] = {{.path = path_of("ov/a.ms"), .text = entry, .length = strlen(entry)},
                             {.path = path_of("ov/c.ms"), .text = c, .length = strlen(c)}};
    g = load_with("ov/a.ms", added, 2);
    CHECK(g.ndiagnostics == 0 && g.count == 2);
    g = load("ov/a.ms");
    CHECK(g.ndiagnostics == 0 && g.count == 2); /* the disk is unchanged and still imports b.ms */
    /* Without the buffer, the missing file is the usual error. */
    MsOverlayFile only_entry[] = {{.path = path_of("ov/a.ms"), .text = entry, .length = strlen(entry)}};
    g = load_with("ov/a.ms", only_entry, 1);
    CHECK(g.ndiagnostics == 1);
    /* Two spellings of one file with different text conflict; a file outside the root is left out. */
    const char *one = "export fn b() Int: return 1\n", *two = "export fn b() Int: return 2\n";
    MsOverlayFile spellings[] = {{.path = path_of("ov/b.ms"), .text = one, .length = strlen(one)},
                                 {.path = path_of("ov/./b.ms"), .text = two, .length = strlen(two)}};
    g = load_with("ov/a.ms", spellings, 2);
    CHECK(g.ndiagnostics == 1);
    if (g.ndiagnostics == 1) {
        CHECK(strstr(diag_text(&g, 0), "conflicting editor overlays") != NULL);
    }
    MsOverlayFile outside[] = {{.path = "/nonexistent-dir/x.ms", .text = one, .length = strlen(one)}};
    g = load_with("ov/a.ms", outside, 1);
    CHECK(g.ndiagnostics == 0);
}

int main(void) {
    CHECK(host_make_root(root, sizeof root, "ms_load"));
    ms_names_init(&names);
    test_chain();
    test_cycle();
    test_missing();
    test_parse_errors();
    test_project();
    test_overlay();
    host_remove_tree(root);
    ms_names_free(&names);
    ms_arena_free(&arena);
    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    return 0;
}

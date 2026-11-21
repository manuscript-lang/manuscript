/* Unit test of checking a loaded graph (src/compiler/src/project/graph_check.c): the project loader's modules reach the
 * checker with their imports resolved, so a call into another module is type-checked. */
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

static MsArena arena;
static char root[256];

static void write_file(const char *name, const char *text) {
    const char *path = MS_PATH_JOIN(&arena, root, name);
    FILE *f = fopen(path, "we");
    CHECK(f != NULL);
    if (f != NULL) {
        fputs(text, f);
        fclose(f);
    }
}

int main(void) {
    CHECK(host_make_root(root, sizeof root, "ms_graph"));
    write_file("lib.ms", "export fn double(x: Int) Int: return x * 2\n");
    write_file("main.ms", "import double from \"./lib.ms\"\nfn main() Void:\n    ok: Int := double(2)\n    bad: String := double(2)\n");
    MsNames names;
    ms_names_init(&names);
    MsGraph graph;
    MsProjectError err = {0};
    CHECK(ms_project_load(&arena, &names, MS_PATH_JOIN(&arena, root, "main.ms"), &graph, &err));
    for (uint32_t i = 0; i < graph.ndiagnostics; i++) {
        fprintf(stderr, "%s:%u:%u: %.*s\n", graph.diagnostics[i].file, graph.diagnostics[i].diag.pos.line, graph.diagnostics[i].diag.pos.column, (int)graph.diagnostics[i].diag.message.len, graph.diagnostics[i].diag.message.ptr);
    }
    CHECK(graph.ndiagnostics == 0 && graph.count == 2);
    if (graph.count != 2) {
        return 1;
    }
    MsCheck check;
    ms_check_init(&check, &names);
    MsModId ids[2] = {0};
    bool unchecked[2] = {false, false};
    ms_graph_add_modules(&check, &names, &arena, &graph, ids);
    CHECK(check.mods[ids[1]].import_targets[0] == ids[0]);
    CHECK(ms_graph_check(&check, &graph, ids, unchecked) == 0);
    uint32_t type_errors = 0;
    for (uint32_t i = 0; i < check.mods[ids[1]].ndiags; i++) {
        type_errors += check.mods[ids[1]].diags[i].phase == MS_PHASE_TYPE;
    }
    CHECK(type_errors > 0);
    CHECK(check.mods[ids[0]].ndiags == 0);
    ms_check_free(&check);
    ms_names_free(&names);
    host_remove_tree(root);
    ms_arena_free(&arena);
    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    return 0;
}

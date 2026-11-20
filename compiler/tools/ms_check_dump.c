#define _POSIX_C_SOURCE 200809L
/* ms_check_dump STDLIB_DIR: loads the standard library into the checker tables and prints them in
 * the form crates/ms-check/examples/c_oracle.rs prints, so the two can be diffed. The files are
 * chosen as crates/ms-check/build.rs chooses them: the top-level and one-level-down `.ms` files of the directory, with the
 * files of `stdlib/core/` named flat. */
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "ms/check.h"
#include "ms/desugar.h"
#include "ms/methods.h"
#include "ms/dump.h"
#include "ms/ownership.h"
#include "ms/parse.h"
#include "ms/program.h"
#include "ms/project.h"
#include "ms/stdlib.h"
#include "dump_io.h"

static MsStdFile *files;
static uint32_t nfiles, cap;

static void add_file(const char *dir, const char *rel, const char *name) {
    char path[4096];
    snprintf(path, sizeof path, "%s/%s", dir, rel);
    FILE *f = fopen(path, "rb");
    if (f == NULL) {
        fprintf(stderr, "cannot read %s\n", path);
        exit(1);
    }
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *text = malloc((size_t)n + 1);
    if (fread(text, 1, (size_t)n, f) != (size_t)n) {
        exit(1);
    }
    fclose(f);
    if (nfiles == cap) {
        cap = cap ? cap * 2 : 128;
        files = realloc(files, cap * sizeof *files);
    }
    files[nfiles++] = (MsStdFile){strdup(name), text, (size_t)n};
}

static bool only_std_imports(const MsModule *module) {
    for (uint32_t i = 0; i < module->nimports; i++) {
        if (module->imports[i].path.len < 5 || memcmp(module->imports[i].path.ptr, "@std/", 5) != 0) {
            return false;
        }
    }
    return true;
}

/* Checks the bodies of module `id` against a fresh program: the library's method table, with the
 * bundled modules' and the imports' impls (ms_program_check_module). */
static void check_bodies_with_methods(MsCheck *check, MsModId id, const char *text, size_t length) {
    ms_program_begin(check);
    (void)ms_program_check_module(check, id, (MsStr){text, (uint32_t)length});
}

/* Loads `path` with the project modules it imports (ms_project_load) and adds them to the checker,
 * dependencies first, each importing through its graph targets. The entry is the last module, named
 * `main.ms`. False when the graph has diagnostics or the loader does not cover the request. */
static bool add_project(MsCheck *check, MsNames *names, const char *path, MsModId *entry, MsStr *entry_text) {
    static MsArena arena;
    MsGraph graph;
    MsProjectError error = {0};
    if (!ms_project_load(&arena, names, path, &graph, &error) || graph.ndiagnostics != 0 || graph.count < 2) {
        return false;
    }
    MsModId *rows = MS_NEW_N(&arena, MsModId, graph.count);
    for (uint32_t m = 0; m < graph.count; m++) {
        const bool last = m + 1 == graph.count;
        const MsSym row_path = ms_intern_cstr(names, last ? "main.ms" : graph.modules[m].path);
        rows[m] = ms_module_add(check, row_path, &graph.modules[m].syntax);
        MsModId *targets = MS_NEW_N(&arena, MsModId, graph.modules[m].syntax.nimports + 1);
        for (uint32_t i = 0; i < graph.modules[m].syntax.nimports; i++) {
            const int32_t target = graph.modules[m].targets[i];
            targets[i] = target < 0 ? MS_NONE : rows[target];
        }
        ms_module_set_imports(check, rows[m], targets);
        if (!last) {
            MsInherentError *errors = NULL;
            uint32_t nerrors = 0;
            ms_module_desugar(check, rows[m], (MsStr){graph.modules[m].source, (uint32_t)graph.modules[m].length}, NULL,
                              0, &errors, &nerrors);
        }
    }
    *entry = rows[graph.count - 1];
    *entry_text = (MsStr){graph.modules[graph.count - 1].source, (uint32_t)graph.modules[graph.count - 1].length};
    return true;
}

/* Prints the name-resolution diagnostics of each file as `path:line:col: message`, the form
 * `c_oracle --scope` prints. Files that fail to parse or import project modules print nothing. */
static bool project_mode;

/* 1 for --facts, 2 for --nodes: the modes that print one JSON document per file. */
static int json_mode_of(const char *flag) {
    if (strcmp(flag, "--facts") == 0) {
        return 1;
    }
    return strcmp(flag, "--nodes") == 0 ? 2 : 0;
}

static void print_scope_diagnostics(MsCheck *check, MsArena *syntax, MsNames *names, int nfiles_in, char **paths,
                                    bool bodies, bool ownership, bool effects, int json_mode) {
    for (int i = 0; i < nfiles_in; i++) {
        FILE *f = fopen(paths[i], "rb");
        if (f == NULL) {
            continue;
        }
        fseek(f, 0, SEEK_END);
        long n = ftell(f);
        fseek(f, 0, SEEK_SET);
        char *text = malloc((size_t)n + 1);
        const bool read = text != NULL && fread(text, 1, (size_t)n, f) == (size_t)n;
        char *owned = text;
        fclose(f);
        MsModule *module = MS_NEW(syntax, MsModule);
        MsDiag diag;
        const bool parsed = read && ms_parse(syntax, names, text, (size_t)n, module, &diag);
        MsModId id = MS_NONE;
        MsStr project_text = {0};
        const char *check_text = text;
        const bool project = project_mode && parsed && !only_std_imports(module) && bodies && !ownership && !effects && json_mode == 0 &&
                             add_project(check, names, paths[i], &id, &project_text);
        if (project) {
            check_text = project_text.ptr;
            n = (long)project_text.len;
        }
        if ((parsed && only_std_imports(module) && !project_mode) || project) {
            if (!project) {
                id = ms_module_add(check, ms_intern_cstr(names, "main.ms"), module);
            }
            MsBuf dump = {0};
            if (json_mode != 0) {
                if (json_mode == 1) {
                    ms_dump_module_facts(&dump, check, id);
                } else {
                    check_bodies_with_methods(check, id, check_text, (size_t)n);
                    ms_dump_module_nodes(&dump, check, id);
                }
                printf("%.*s", (int)dump.len, (const char *)dump.data);
                ms_buf_free(&dump);
                free(owned);
                continue;
            }
            printf("== %s\n", paths[i]);
            if (bodies) {
                check_bodies_with_methods(check, id, check_text, (size_t)n);
                for (uint32_t k = 0; project && k < check->mods[id].ndiags; k++) {
                    const MsCheckDiag *d = &check->mods[id].diags[k];
                    if (d->phase == MS_PHASE_RESOLUTION) {
                        printf("import %u:%u: %.*s\n", d->diag.pos.line, d->diag.pos.column, (int)d->diag.message.len,
                               d->diag.message.ptr);
                    }
                }
                if (effects) {
                    // The effect scan reads the facts of every function the body pass checked.
                    ms_dump_module_effects(&dump, check, id, (MsStr){check_text, (uint32_t)n});
                    printf("%.*s", (int)dump.len, (const char *)dump.data);
                    ms_buf_free(&dump);
                    free(owned);
                    continue;
                }
                // The ownership walk narrows `body_checked` to the functions it handles. The body
                // comparison keeps every claim but still sees the ownership diagnostics of the
                // functions the walk handled, as the Rust diagnostics include them.
                MsFacts *facts = check->mods[id].facts;
                const size_t claims = facts == NULL ? 0 : (size_t)facts->node_count + 1;
                const bool keep = !ownership && facts != NULL && facts->body_checked != NULL;
                bool *claimed = keep ? malloc(claims * sizeof *claimed) : NULL;
                if (claimed != NULL) {
                    memcpy(claimed, facts->body_checked, claims * sizeof *claimed);
                }
                ms_module_check_ownership(check, id);
                if (ownership) {
                    ms_module_check_unused(check, id);
                    ms_dump_module_ownership(&dump, check, id);
                } else {
                    // Functions the ownership walk handed back keep the checker's claim; the dump
                    // marks them, because Rust's ownership diagnostics inside them have no C twin yet.
                    bool *declined = claimed == NULL ? NULL : malloc(claims * sizeof *declined);
                    for (size_t k = 0; declined != NULL && k < claims; k++) {
                        declined[k] = claimed[k] && !facts->body_checked[k];
                    }
                    if (claimed != NULL) {
                        memcpy(facts->body_checked, claimed, claims * sizeof *claimed);
                    }
                    free(claimed);
                    ms_module_check_unused(check, id);
                    ms_dump_module_bodies(&dump, check, id, declined);
                    free(declined);
                }
                printf("%.*s", (int)dump.len, (const char *)dump.data);
            } else {
                ms_module_resolve_types(check, id);
                for (uint32_t k = 0; k < check->mods[id].ndiags; k++) {
                    const MsDiag *d = &check->mods[id].diags[k].diag;
                    printf("%u:%u: %.*s\n", d->pos.line, d->pos.column, (int)d->message.len, d->message.ptr);
                }
                ms_dump_module_types(&dump, check, id);
                printf("--\n%.*s", (int)dump.len, (const char *)dump.data);
            }
            ms_buf_free(&dump);
        }
        free(owned);
    }
}

int main(int argc, char **argv) {
    const bool ownership = argc >= 3 && strcmp(argv[2], "--ownership") == 0;
    const bool effects = argc >= 3 && strcmp(argv[2], "--effects") == 0;
    const int json_mode = json_mode_of(argc >= 3 ? argv[2] : "");
    project_mode = argc >= 3 && strcmp(argv[2], "--project") == 0;
    const bool bodies = ownership || effects || project_mode || (argc >= 3 && strcmp(argv[2], "--bodies") == 0);
    const bool scope = bodies || json_mode != 0 || (argc >= 3 && strcmp(argv[2], "--scope") == 0);
    if (argc != 2 && !scope) {
        fputs("usage: ms_check_dump STDLIB_DIR [--scope|--bodies|--ownership|--effects|--facts|--nodes FILE...]\n", stderr);
        return 2;
    }
    const char *root = argv[1];
    DIR *d = opendir(root);
    if (d == NULL) {
        fprintf(stderr, "cannot open %s\n", root);
        return 1;
    }
    for (struct dirent *e; (e = readdir(d)) != NULL;) {
        if (e->d_name[0] == '.') {
            continue;
        }
        char path[4096];
        snprintf(path, sizeof path, "%s/%s", root, e->d_name);
        struct stat st;
        if (stat(path, &st) != 0) {
            continue;
        }
        if (S_ISDIR(st.st_mode)) {
            DIR *sub = opendir(path);
            for (struct dirent *s; sub != NULL && (s = readdir(sub)) != NULL;) {
                if (!ends_with(s->d_name, ".ms")) {
                    continue;
                }
                char rel[4096], name[4096];
                snprintf(rel, sizeof rel, "%s/%s", e->d_name, s->d_name);
                snprintf(name, sizeof name, "%s", strcmp(e->d_name, "core") == 0 ? s->d_name : rel);
                add_file(root, rel, name);
            }
            if (sub != NULL) {
                closedir(sub);
            }
        } else if (ends_with(e->d_name, ".ms")) {
            add_file(root, e->d_name, e->d_name);
        }
    }
    closedir(d);

    MsNames names;
    ms_names_init(&names);
    MsArena syntax = {0};
    MsCheck check;
    ms_check_init(&check, &names);
    MsStr err = {0};
    if (!ms_std_load(&check, &syntax, files, nfiles, &err)) {
        fprintf(stderr, "standard declarations: %.*s\n", (int)err.len, err.ptr);
        return 1;
    }
    if (scope) {
        print_scope_diagnostics(&check, &syntax, &names, argc - 3, argv + 3, bodies, ownership, effects, json_mode);
    } else {
        MsBuf out = {0};
        ms_dump_std_tables(&out, &check);
        fwrite(out.data, 1, out.len, stdout);
        ms_buf_free(&out);
    }
    ms_check_free(&check);
    ms_arena_free(&syntax);
    ms_names_free(&names);
    return 0;
}

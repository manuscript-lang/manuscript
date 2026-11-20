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

/* Checks the bodies of module `id` with the program's method table: the inherent methods desugared
 * to impls, the interface operations and the implementations resolved first, as the Rust checker
 * does. A module with an inherent error is left unchecked. */
static void check_bodies_with_methods(MsCheck *check, MsModId id, const char *text, size_t length) {
    MsInherentError *errors = NULL;
    uint32_t nerrors = 0;
    ms_module_desugar(check, id, (MsStr){text, (uint32_t)length}, NULL, 0, &errors, &nerrors);
    if (nerrors > 0) {
        return;
    }
    ms_module_resolve_types(check, id);
    MsMethodTable table;
    ms_methods_init(&table);
    ms_module_ensure_operations(check, id, &table);
    ms_module_add_implementations(check, id, &table);
    ms_module_check_bodies_with(check, id, &table);
    ms_methods_free(&table);
}

/* Prints the name-resolution diagnostics of each file as `path:line:col: message`, the form
 * `c_oracle --scope` prints. Files that fail to parse or import project modules print nothing. */
static void print_scope_diagnostics(MsCheck *check, MsArena *syntax, MsNames *names, int nfiles_in, char **paths,
                                    bool bodies, bool ownership) {
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
        fclose(f);
        MsModule *module = MS_NEW(syntax, MsModule);
        MsDiag diag;
        if (read && ms_parse(syntax, names, text, (size_t)n, module, &diag) && only_std_imports(module)) {
            printf("== %s\n", paths[i]);
            MsModId id = ms_module_add(check, ms_intern_cstr(names, "main.ms"), module);
            MsBuf dump = {0};
            if (bodies) {
                check_bodies_with_methods(check, id, text, (size_t)n);
                if (ownership) {
                    // The ownership walk narrows `body_checked` to the functions it handles, so it
                    // runs only for its own comparison; the body comparison sees every claim.
                    ms_module_check_ownership(check, id);
                    ms_dump_module_ownership(&dump, check, id);
                } else {
                    ms_dump_module_bodies(&dump, check, id);
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
        free(text);
    }
}

int main(int argc, char **argv) {
    const bool ownership = argc >= 3 && strcmp(argv[2], "--ownership") == 0;
    const bool bodies = ownership || (argc >= 3 && strcmp(argv[2], "--bodies") == 0);
    const bool scope = bodies || (argc >= 3 && strcmp(argv[2], "--scope") == 0);
    if (argc != 2 && !scope) {
        fputs("usage: ms_check_dump STDLIB_DIR [--scope|--bodies|--ownership FILE...]\n", stderr);
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
        print_scope_diagnostics(&check, &syntax, &names, argc - 3, argv + 3, bodies, ownership);
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

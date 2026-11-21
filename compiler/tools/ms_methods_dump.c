#define _POSIX_C_SOURCE 200809L
/* ms_methods_dump STDLIB_DIR FILE...: prints the operations of the interfaces each file declares
 * in the form crates/ms-check/examples/c_oracle_methods.rs prints, so the two can be diffed. Files
 * that fail to parse or import project modules print nothing. */
#include <stdio.h>
#include <string.h>

#include "ms/desugar.h"
#include "ms/methods.h"
#include "ms/parse.h"
#include "ms/stdlib.h"
#include "read_file.h"
#include "std_files.h"

/* The diagnostics about operations the C checker implements so far. */
static const char *const families[] = {
    "implementation receiver must be nominal source data",
    "implementation target must be an interface",
    "duplicate implementation operation ",
    "has the same name as a field of ",
    "shadows a type parameter of the impl",
    "is opaque outside ",
    "is declared var fn but ",
    "is Data when its parts are",
    "duplicate operation ",
    "shadows a type parameter of the receiver",
    "Self can only be a whole parameter or result type",
};

static bool is_listed(const MsDiag *d) {
    char text[1024];
    snprintf(text, sizeof text, "%.*s", (int)d->message.len, d->message.ptr);
    for (size_t i = 0; i < sizeof families / sizeof *families; i++) {
        if (strstr(text, families[i]) != NULL) {
            return true;
        }
    }
    return false;
}

static void print_file(MsCheck *check, MsArena *syntax, MsNames *names, const char *path) {
    size_t length = 0;
    char *text = read_whole_file(path, &length);
    MsModule *module = MS_NEW(syntax, MsModule);
    MsDiag diag;
    if (text != NULL && ms_parse(syntax, names, text, length, module, &diag) && ms_module_only_std_imports(module)) {
        printf("== %s\n", path);
        const MsModId id = ms_module_add(check, ms_intern_cstr(names, "main.ms"), module);
        MsInherentError *errors = NULL;
        uint32_t nerrors = 0;
        ms_module_desugar(check, id, (MsStr){text, (uint32_t)length}, NULL, 0, &errors, &nerrors);
        if (nerrors > 0) { /* the Rust checker stops at the first inherent error */
            puts("--");
            free(text);
            return;
        }
        ms_module_resolve_types(check, id);
        MsMethodTable table;
        ms_methods_init(&table);
        ms_module_ensure_operations(check, id, &table);
        ms_module_add_implementations(check, id, &table);
        for (uint32_t k = 0; k < check->mods[id].ndiags; k++) {
            const MsDiag *d = &check->mods[id].diags[k].diag;
            if (is_listed(d)) {
                printf("%u:%u: %.*s\n", d->pos.line, d->pos.column, (int)d->message.len, d->message.ptr);
            }
        }
        MsBuf out = {0};
        ms_dump_operations(&out, check, id, &table);
        ms_dump_methods(&out, check, id, &table);
        printf("--\n%.*s", (int)out.len, out.data == NULL ? "" : out.data);
        ms_buf_free(&out);
        ms_methods_free(&table);
    }
    free(text);
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fputs("usage: ms_methods_dump STDLIB_DIR FILE...\n", stderr);
        return 2;
    }
    StdFiles files = {0};
    if (!read_std_files(&files, argv[1])) {
        return 1;
    }
    MsNames names;
    ms_names_init(&names);
    MsArena syntax = {0};
    MsCheck check;
    ms_check_init(&check, &names);
    MsStr err = {0};
    if (!ms_std_load(&check, &syntax, files.items, files.count, &err)) {
        fprintf(stderr, "standard declarations: %.*s\n", (int)err.len, err.ptr);
        return 1;
    }
    for (int i = 2; i < argc; i++) {
        print_file(&check, &syntax, &names, argv[i]);
    }
    ms_check_free(&check);
    ms_arena_free(&syntax);
    ms_names_free(&names);
    free_std_files(&files);
    return 0;
}

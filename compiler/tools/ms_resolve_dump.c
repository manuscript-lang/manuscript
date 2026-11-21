#define _POSIX_C_SOURCE 200809L
/* ms_resolve_dump STDLIB_DIR FILE...: checks each single-module file (standard imports only) as `ms check`
 * does and prints the diagnostics of its module as the `--json` document, named by the file's base name;
 * `file: skipped` for a file that does not parse or imports a project module. The differential scripts
 * compare this with the Rust CLI. */
#include <stdio.h>
#include <string.h>

#include "ms/check.h"
#include "ms/diag_render.h"
#include "ms/parse.h"
#include "ms/program.h"
#include "ms/stdlib.h"
#include "std_files.h"

static const char *phase_name(MsPhase phase) {
    switch (phase) {
    case MS_PHASE_RESOLUTION: return "resolution";
    case MS_PHASE_TYPE: return "type";
    case MS_PHASE_OWNERSHIP: return "ownership";
    }
    return "type";
}

static void print_report(const MsModuleRow *row, const char *base) {
    MsReport *reports = calloc(row->ndiags + 1, sizeof *reports);
    for (uint32_t i = 0; i < row->ndiags; i++) {
        reports[i] = (MsReport){.diag = row->diags[i].diag, .file = base, .phase = phase_name(row->diags[i].phase)};
    }
    MsBuf out = {0};
    ms_render_json(&out, reports, row->ndiags);
    fwrite(out.data, 1, out.len, stdout);
    ms_buf_free(&out);
    free(reports);
}

static void dump_file(MsCheck *check, MsArena *syntax, MsNames *names, const char *path) {
    size_t length = 0;
    char *text = read_whole_file(path, &length);
    if (text == NULL) {
        return;
    }
    MsModule *module = MS_NEW(syntax, MsModule);
    MsDiag diag;
    printf("== %s\n", path);
    if (ms_parse(syntax, names, text, length, module, &diag) && ms_module_only_std_imports(module)) {
        MsModId id = ms_module_add(check, ms_intern_cstr(names, "main.ms"), module);
        ms_program_begin(check);
        if (ms_program_check_module(check, id, (MsStr){text, (uint32_t)length})) {
            const char *slash = strrchr(path, '/');
            print_report(&check->mods[id], slash != NULL ? slash + 1 : path);
        } else {
            puts("skipped");
        }
    } else {
        puts("skipped");
    }
    free(text);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fputs("usage: ms_resolve_dump STDLIB_DIR FILE...\n", stderr);
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
        dump_file(&check, &syntax, &names, argv[i]);
    }
    ms_check_free(&check);
    ms_arena_free(&syntax);
    ms_names_free(&names);
    free_std_files(&files);
    return 0;
}

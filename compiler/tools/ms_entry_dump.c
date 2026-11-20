#define _POSIX_C_SOURCE 200809L
/* ms_entry_dump STDLIB_DIR FILE...: for each single-module file (standard imports only) that checks
 * without a diagnostic, prints the entry diagnostic `ms check` gives it as `path:line:col: type:
 * message`, or `path: ok`. The differential script compares this with the Rust CLI. */
#include <stdio.h>
#include <string.h>

#include "ms/check.h"
#include "ms/entry.h"
#include "ms/parse.h"
#include "ms/stdlib.h"
#include "std_files.h"

static void dump_file(MsCheck *check, MsArena *syntax, MsNames *names, const char *path) {
    size_t length = 0;
    char *text = read_whole_file(path, &length);
    if (text == NULL) {
        return;
    }
    MsModule *module = MS_NEW(syntax, MsModule);
    MsDiag diag;
    if (ms_parse(syntax, names, text, length, module, &diag) && ms_module_only_std_imports(module)) {
        MsModId id = ms_module_add(check, ms_intern_cstr(names, "main.ms"), module);
        ms_module_resolve_types(check, id);
        MsCheckDiag entry;
        if (check->mods[id].ndiags != 0) {
            printf("%s: skipped\n", path);
        } else if (ms_check_entry(check, id, true, &entry)) {
            printf("%s:%u:%u: type: %.*s\n", path, entry.diag.pos.line, entry.diag.pos.column,
                   (int)entry.diag.message.len, entry.diag.message.ptr);
        } else {
            printf("%s: ok\n", path);
        }
    }
    free(text);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fputs("usage: ms_entry_dump STDLIB_DIR FILE...\n", stderr);
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

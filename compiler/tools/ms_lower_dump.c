#define _POSIX_C_SOURCE 200809L
/* ms_lower_dump STDLIB_DIR FILE...: checks each single-file program with the C checker, lowers
 * the functions the C lowering handles, and prints each as the Rust lowering's text, so the two
 * can be compared function by function (compiler/tests/lower-diff.sh). Files that fail to parse
 * or import project modules print nothing. Output: `=== path`, then one `fn` block per function. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/check.h"
#include "ms/lower.h"
#include "ms/parse.h"
#include "ms/stdlib.h"
#include "read_file.h"
#include "std_files.h"

static bool only_std_imports(const MsModule *module) {
    for (uint32_t i = 0; i < module->nimports; i++) {
        if (module->imports[i].path.len < 5 || memcmp(module->imports[i].path.ptr, "@std/", 5) != 0) {
            return false;
        }
    }
    return true;
}

static void lower_file(MsCheck *check, MsArena *syntax, MsNames *names, const char *path) {
    size_t length = 0;
    char *text = read_whole_file(path, &length);
    if (text == NULL) {
        return;
    }
    MsModule *module = MS_NEW(syntax, MsModule);
    MsDiag diag;
    if (ms_parse(syntax, names, text, length, module, &diag) && only_std_imports(module)) {
        printf("=== %s\n", path);
        const MsModId id = ms_module_add(check, ms_intern_cstr(names, "main.ms"), module);
        ms_module_check_bodies(check, id);
        MirModule mir;
        mir_module_init(&mir);
        (void)ms_lower_module(check, id, &mir);
        for (uint32_t i = 0; i < mir.nfuncs; i++) {
            MsBuf out = {0};
            mir_print_func(&mir, &mir.funcs[i], &out);
            printf("%.*s\n", (int)out.len, (const char *)out.data);
            ms_buf_free(&out);
        }
        mir_module_free(&mir);
    }
    free(text);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fputs("usage: ms_lower_dump STDLIB_DIR FILE...\n", stderr);
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
        lower_file(&check, &syntax, &names, argv[i]);
    }
    ms_check_free(&check);
    ms_arena_free(&syntax);
    ms_names_free(&names);
    free_std_files(&files);
    return 0;
}

/* ms_import_hints_dump STDLIB_DIR: answers the queries crates/ms-check/examples/c_import_oracle.rs
 * answers (`import`, `typeimport`, `export`, one per stdin line) from the C tables, so the two can
 * be diffed. */
#include "std_files.h"

#include "ms/import_hints.h"
#include "dump_io.h"

static void answer_export(MsArena *arena, const MsCheck *c, MsNames *names, char *path, char *name) {
    MsImport item = {0};
    item.path = str_of(path);
    item.name = ms_intern_cstr(names, name);
    if (ms_standard_import_ok(arena, c, item.path, str_of(name))) {
        fputs("-", stdout);
        return;
    }
    put_text(ms_export_message(arena, c, &item, false, NULL));
}

MS_NODISCARD static bool answer(MsCheck *c, MsNames *names, char **f, size_t nfields) {
    MsArena arena = {0};
    bool known = true;
    if (strcmp(f[0], "import") == 0 && nfields == 2) {
        put_text(ms_import_hint(&arena, c, str_of(f[1]), false));
    } else if (strcmp(f[0], "typeimport") == 0 && nfields == 2) {
        put_text(ms_type_import_hint(&arena, c, str_of(f[1]), false));
    } else if (strcmp(f[0], "export") == 0 && nfields == 3) {
        answer_export(&arena, c, names, f[1], f[2]);
    } else {
        fprintf(stderr, "bad query %s\n", f[0]);
        known = false;
    }
    ms_arena_free(&arena);
    return known;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fputs("usage: ms_import_hints_dump STDLIB_DIR\n", stderr);
        return 2;
    }
    StdFiles files = {0};
    if (!read_std_files(&files, argv[1])) {
        free_std_files(&files);
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
        free_std_files(&files);
        return 1;
    }
    static char empty[] = "";
    MsBuf line = {0};
    int status = 0;
    while (status == 0 && read_line(&line)) {
        char *fields[4] = {empty, empty, empty, empty};
        size_t n = split_fields(line.data, fields, MS_COUNT_OF(fields));
        status = answer(&check, &names, fields, n) ? 0 : 2;
        fputc('\n', stdout);
    }
    ms_buf_free(&line);
    free_std_files(&files);
    ms_check_free(&check);
    ms_arena_free(&syntax);
    ms_names_free(&names);
    return status;
}

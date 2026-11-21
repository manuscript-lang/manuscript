#define _POSIX_C_SOURCE 200809L
/* ms_api_model STDLIB_DIR: prints the standard library's API model as JSON, in the form the Rust
 * `ms-tooling` example `api_model` prints, so the two can be diffed. */
#include <stdio.h>

#include "ms/api_model.h"
#include "std_files.h"

int main(int argc, char **argv) {
    if (argc != 2) {
        fputs("usage: ms_api_model STDLIB_DIR\n", stderr);
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
    MsBuf out = {0};
    ms_api_model_json(&out, &check, files.items, files.count);
    fwrite(out.data, 1, out.len, stdout);
    fputc('\n', stdout); /* the Rust example's println! */
    ms_buf_free(&out);
    ms_check_free(&check);
    ms_arena_free(&syntax);
    ms_names_free(&names);
    free_std_files(&files);
    return 0;
}

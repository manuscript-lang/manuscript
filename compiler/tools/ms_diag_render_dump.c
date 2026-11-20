/* ms_diag_render_dump text|json FILE SHOWN NAME: parses FILE and, when the parse fails, renders the
 * diagnostic as `ms check` does (SHOWN is the path the terminal report prints, NAME the one JSON shows).
 * Exits 0 and prints nothing when FILE parses; the differential script compares the rest with the
 * Rust CLI. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/diag_render.h"
#include "ms/parse.h"
#include "read_file.h"

int main(int argc, char **argv) {
    if (argc != 5) {
        fprintf(stderr, "usage: ms_diag_render_dump text|json FILE SHOWN NAME\n");
        return 2;
    }
    size_t len = 0;
    char *text = read_whole_file(argv[2], &len);
    if (text == NULL) {
        fprintf(stderr, "cannot read %s\n", argv[2]);
        return 2;
    }
    MsArena arena = {0};
    MsNames names;
    ms_names_init(&names);
    MsModule module;
    MsDiag first;
    MsDiagList list = {&first, 0};
    if (!ms_parse(&arena, &names, text, len, &module, &first)) {
        list.len = 1;
    }
    if (list.len > 0) {
        MsReport *reports = calloc(list.len, sizeof *reports);
        for (uint32_t i = 0; i < list.len; i++) {
            reports[i] = (MsReport){.diag = list.items[i], .file = argv[4], .shown = argv[3], .phase = "parse"};
        }
        MsBuf out = {0};
        if (strcmp(argv[1], "json") == 0) {
            ms_render_json(&out, reports, list.len);
        } else {
            ms_render_text(&out, reports, list.len);
        }
        fwrite(out.data, 1, out.len, stdout);
        ms_buf_free(&out);
        free(reports);
    }
    ms_names_free(&names);
    ms_arena_free(&arena);
    free(text);
    return 0;
}

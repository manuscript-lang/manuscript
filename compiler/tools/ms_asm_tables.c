/* ms_asm_tables META ASM [--prefix _] [--strip-lines]: reads the description `ms_mir_build --tables-meta` wrote and the
 * assembly clang wrote, and prints the assembly with the fault tables appended (mir_asm_tables); `--strip-lines` leaves out
 * the `.loc` lines, for builds that carry no line tables. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/mir_asm_tables.h"
#include "read_file.h"

int main(int argc, char **argv) {
    const char *prefix = "";
    bool strip = false;
    for (int i = 3; i < argc; i++) {
        if (strcmp(argv[i], "--prefix") == 0 && i + 1 < argc) {
            prefix = argv[++i];
        } else if (strcmp(argv[i], "--strip-lines") == 0) {
            strip = true;
        } else {
            argc = 0;
        }
    }
    if (argc < 3) {
        fputs("usage: ms_asm_tables META ASM [--prefix _] [--strip-lines]\n", stderr);
        return 2;
    }
    size_t meta_len = 0, asm_len = 0;
    char *meta = read_whole_file(argv[1], &meta_len);
    char *text = read_whole_file(argv[2], &asm_len);
    if (meta == NULL || text == NULL) {
        fputs("ms_asm_tables: cannot read an input\n", stderr);
        return 1;
    }
    MsBuf out = {0}, why = {0};
    const bool ok = mir_asm_tables(meta, meta_len, text, asm_len, prefix, strip, &out, &why);
    if (ok) {
        fwrite(out.data, 1, out.len, stdout);
    } else {
        fprintf(stderr, "ms_asm_tables: %.*s", (int)why.len, why.data);
    }
    ms_buf_free(&out);
    ms_buf_free(&why);
    free(meta);
    free(text);
    return ok ? 0 : 1;
}

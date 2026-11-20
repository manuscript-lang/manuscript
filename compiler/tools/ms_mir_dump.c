/* ms_mir_dump MODE FILE...: reads MIR text files and prints, per file, what
 * crates/ms-mir/examples/c_oracle.rs prints, so the two can be diffed byte for byte.
 * MODE: print (canonical text, or `error line N`), ops (the opcode table). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/mir.h"

static bool read_file(const char *path, char **data, size_t *len) {
    FILE *f = fopen(path, "rb");
    if (f == NULL) return false;
    size_t cap = 4096, n = 0;
    char *buf = malloc(cap);
    for (;;) {
        n += fread(buf + n, 1, cap - n, f);
        if (n < cap) break;
        cap *= 2;
        buf = realloc(buf, cap);
    }
    fclose(f);
    *data = buf;
    *len = n;
    return true;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fputs("usage: ms_mir_dump print|ops FILE...\n", stderr);
        return 2;
    }
    MsBuf out = {0};
    if (strcmp(argv[1], "ops") == 0) {
        for (int i = 0; i < MOP_COUNT; i++) {
            const MirOpInfo *o = &mir_op_info[i];
            ms_buf_printf(&out, "%s imm=%d res=%d fx=%d\n", o->name, o->imm, o->has_result, o->effects);
        }
    }
    for (int i = 2; i < argc && strcmp(argv[1], "print") == 0; i++) {
        char *src;
        size_t len;
        if (!read_file(argv[i], &src, &len)) {
            fprintf(stderr, "cannot read %s\n", argv[i]);
            return 1;
        }
        ms_buf_printf(&out, "=== %s\n", argv[i]);
        if (!ms_utf8_valid(src, len)) {
            ms_buf_puts(&out, "error invalid-utf8\n");
            free(src);
            continue;
        }
        MirModule m;
        mir_module_init(&m);
        uint32_t line;
        MsStr msg;
        if (mir_parse(&m, src, len, &line, &msg)) {
            mir_print_module(&m, &out);
        } else {
            ms_buf_printf(&out, "error line %u\n", line);
        }
        mir_module_free(&m);
        free(src);
    }
    if (out.len > 0) {
        fwrite(out.data, 1, out.len, stdout);
    }
    ms_buf_free(&out);
    return 0;
}

/* ms_mir_qbe FILE: reads MIR text and prints QBE SSA text. Exit 1 and a list on stderr when
 * something cannot be written yet. */
#include <stdio.h>
#include <stdlib.h>

#include "ms/emit_qbe.h"

int main(int argc, char **argv) {
    if (argc != 2) {
        fputs("usage: ms_mir_qbe FILE\n", stderr);
        return 2;
    }
    FILE *f = fopen(argv[1], "rb");
    if (f == NULL) {
        fprintf(stderr, "cannot read %s\n", argv[1]);
        return 1;
    }
    size_t cap = 4096, n = 0;
    char *src = malloc(cap);
    for (;;) {
        n += fread(src + n, 1, cap - n, f);
        if (n < cap) break;
        cap *= 2;
        src = realloc(src, cap);
    }
    fclose(f);
    MirModule m;
    mir_module_init(&m);
    uint32_t line;
    MsStr message;
    if (!mir_parse(&m, src, n, &line, &message)) {
        fprintf(stderr, "%s:%u: %.*s\n", argv[1], line, (int)message.len, message.ptr);
        mir_module_free(&m);
        free(src);
        return 1;
    }
    MsBuf out = {0}, why = {0};
    bool ok = mir_emit_qbe(&m, &out, &why);
    if (!ok) fprintf(stderr, "the QBE emitter cannot write:\n%.*s", (int)why.len, why.data);
    else fwrite(out.data, 1, out.len, stdout);
    ms_buf_free(&out);
    ms_buf_free(&why);
    free(src);
    mir_module_free(&m);
    return ok ? 0 : 1;
}

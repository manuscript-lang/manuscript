/* ms_mir_llvm FILE: reads MIR text and prints LLVM IR text. Exit 1 and a list on stderr when
 * something cannot be written yet. */
#include <stdio.h>
#include <stdlib.h>

#include "ms/emit_llvm.h"
#include "read_file.h"

int main(int argc, char **argv) {
    if (argc != 2) {
        fputs("usage: ms_mir_llvm FILE\n", stderr);
        return 2;
    }
    size_t n = 0;
    char *src = read_whole_file(argv[1], &n);
    if (src == NULL) {
        fprintf(stderr, "cannot read %s\n", argv[1]);
        return 1;
    }
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
    bool ok = mir_emit_llvm(&m, &out, &why);
    if (!ok) fprintf(stderr, "the LLVM emitter cannot write:\n%.*s", (int)why.len, why.data);
    else fwrite(out.data, 1, out.len, stdout);
    ms_buf_free(&out);
    ms_buf_free(&why);
    free(src);
    mir_module_free(&m);
    return ok ? 0 : 1;
}

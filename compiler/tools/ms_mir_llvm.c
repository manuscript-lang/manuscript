/* ms_mir_llvm FILE [--main OUT]: reads MIR text and prints LLVM IR text. Exit 1 and a list on stderr
 * when something cannot be written yet. With --main, every function is external and OUT receives the
 * unit with `main` and the fault tables of one synthetic code range per instruction (tests). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/emit_llvm.h"
#include "read_file.h"
#include "synthetic_tables.h"

int main(int argc, char **argv) {
    if (argc != 2 && !(argc == 4 && strcmp(argv[2], "--main") == 0)) {
        fputs("usage: ms_mir_llvm FILE [--main OUT]\n", stderr);
        return 2;
    }
    const char *main_out = argc == 4 ? argv[3] : NULL;
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
    MirGlue glue = {0};
    MsBuf failure = {0};
    const MirPipelineOptions pipeline = {.checks = true, .verify = false};
    if (!mir_pipeline_finish(&m, &pipeline, &glue, &failure)) {
        fprintf(stderr, "%s: %.*s\n", argv[1], (int)failure.len, failure.data);
        ms_buf_free(&failure);
        mir_module_free(&m);
        free(src);
        return 1;
    }
    ms_buf_free(&failure);
    mir_lower_ops(&m, &glue);
    MirData data;
    mir_data_build(&m, &glue, &data);
    MsBuf out = {0}, why = {0};
    bool ok = mir_emit_llvm_with(&m, &data, &glue, main_out != NULL, &out, &why);
    if (!ok) fprintf(stderr, "the LLVM emitter cannot write:\n%.*s", (int)why.len, why.data);
    else fwrite(out.data, 1, out.len, stdout);
    if (ok && main_out != NULL) {
        MsArena arena = {0};
        MirTables tables;
        synthetic_tables(&arena, &m, &tables);
        MsBuf unit = {0};
        FILE *file = mir_emit_llvm_main(&m, &tables, &unit) ? fopen(main_out, "wb") : NULL;
        ok = file != NULL;
        if (ok) {
            fwrite(unit.data, 1, unit.len, file);
            fclose(file);
        } else {
            fprintf(stderr, "cannot write the main unit %s\n", main_out);
        }
        ms_buf_free(&unit);
        ms_arena_free(&arena);
    }
    ms_buf_free(&out);
    ms_buf_free(&why);
    free(src);
    mir_module_free(&m);
    return ok ? 0 : 1;
}

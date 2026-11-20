/* ms_mir_build FILE [--backend qbe|llvm] [--opt none|speed] [--no-checks] [--no-verify] [--tables-meta PATH]
 *
 * The C back end as one step: reads the MIR text of a lowered, elaborated module (what `ms emit`
 * prints), runs the optimizer and the finishing passes (`mir_optimize`, `mir_pipeline_finish`) and
 * prints QBE SSA text (debug builds) or LLVM IR text (release builds) on standard output. Exit 1
 * with the reason on stderr when a pass fails or the emitter cannot write something yet. With
 * `--tables-meta` (QBE) the program passes `ms_tables` to the runtime and PATH gets the description
 * `ms_asm_tables` turns into fault tables once the assembly exists. The Rust
 * `ms` runs this when `MS_BACKEND=c` is set (crates/ms-build/src/c_backend.rs). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/emit_entry.h"
#include "ms/emit_llvm.h"
#include "ms/emit_qbe.h"
#include "ms/mir_asm_tables.h"
#include "ms/mir_opt.h"
#include "read_file.h"

static int fail(const char *what, const MsBuf *text) {
    fprintf(stderr, "%s%.*s\n", what, (int)text->len, text->data != NULL ? text->data : "");
    return 1;
}

/* The description of the functions and scopes that ms_asm_tables needs to build the fault tables. */
static bool write_meta(const MirModule *m, const char *path) {
    MsBuf meta = {0};
    mir_qbe_tables_meta(m, &meta);
    FILE *f = fopen(path, "wb");
    const bool ok = f != NULL && fwrite(meta.data, 1, meta.len, f) == meta.len && fclose(f) == 0;
    if (!ok) {
        fprintf(stderr, "cannot write %s\n", path);
    }
    ms_buf_free(&meta);
    return ok;
}

int main(int argc, char **argv) {
    const char *file = NULL, *tables_meta = NULL;
    bool llvm = false, speed = false, checks = true, verify = true;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--backend") == 0 && i + 1 < argc) {
            llvm = strcmp(argv[++i], "llvm") == 0;
        } else if (strcmp(argv[i], "--opt") == 0 && i + 1 < argc) {
            speed = strcmp(argv[++i], "speed") == 0;
        } else if (strcmp(argv[i], "--tables-meta") == 0 && i + 1 < argc) {
            tables_meta = argv[++i];
        } else if (strcmp(argv[i], "--no-checks") == 0) {
            checks = false;
        } else if (strcmp(argv[i], "--no-verify") == 0) {
            verify = false;
        } else if (file == NULL) {
            file = argv[i];
        } else {
            file = NULL;
            break;
        }
    }
    if (file == NULL) {
        fputs("usage: ms_mir_build FILE [--backend qbe|llvm] [--opt none|speed] [--no-checks] [--no-verify]\n",
              stderr);
        return 2;
    }
    size_t n = 0;
    char *src = read_whole_file(file, &n);
    if (src == NULL) {
        fprintf(stderr, "cannot read %s\n", file);
        return 1;
    }
    MirModule m;
    mir_module_init(&m);
    uint32_t line;
    MsStr message;
    if (!mir_parse(&m, src, n, &line, &message)) {
        fprintf(stderr, "%s:%u: %.*s\n", file, line, (int)message.len, message.ptr);
        mir_module_free(&m);
        free(src);
        return 1;
    }
    free(src);
    MsBuf error = {0};
    if (!mir_optimize(&m, speed ? MIR_OPT_SPEED : MIR_OPT_NONE, verify, &error)) {
        return fail("", &error);
    }
    MirGlue glue = {0};
    const MirPipelineOptions pipeline = {.checks = checks, .verify = verify};
    if (!mir_pipeline_finish(&m, &pipeline, &glue, &error)) {
        return fail("", &error);
    }
    MsBuf out = {0}, why = {0};
    bool ok;
    mir_name_symbols(&m);
    if (llvm) {
        mir_lower_ops(&m, &glue);
        MirData data;
        mir_data_build(&m, &glue, &data);
        ok = mir_emit_llvm(&m, &data, &glue, &out, &why);
    } else {
        ok = mir_emit_qbe_glued(&m, &glue, &out, &why);
    }
    if (!ok) {
        return fail("the C back end cannot write:\n", &why);
    }
    mir_emit_entry_main(&m, llvm, tables_meta != NULL && !llvm, &out);
    if (tables_meta != NULL && !llvm && !write_meta(&m, tables_meta)) {
        return 1;
    }
    fwrite(out.data, 1, out.len, stdout);
    return 0;
}

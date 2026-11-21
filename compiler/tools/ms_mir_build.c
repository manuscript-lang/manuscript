/* ms_mir_build FILE [--opt none|speed] [--no-checks] [--no-verify] [--tables-meta PATH] [--display-names PATH]
 *
 * The C back end as one step: reads the MIR text of a lowered, elaborated module (what `ms emit`
 * prints), runs the optimizer and the finishing passes (`mir_optimize`, `mir_pipeline_finish`) and
 * prints LLVM IR text on standard output. Exit 1
 * with the reason on stderr when a pass fails or the emitter cannot write something yet. With
 * `--tables-meta` the program passes `ms_tables` to the runtime and PATH gets the description
 * `ms_asm_tables` turns into fault tables once the assembly exists. The Rust
 * `ms` runs this when `MS_BACKEND=c` is set (crates/ms-build/src/c_backend.rs). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/emit_program.h"
#include "read_file.h"

static bool write_file(const char *path, const MsBackendText *text) {
    FILE *f = fopen(path, "wb");
    const bool ok = f != NULL && fwrite(text->ptr, 1, text->len, f) == text->len && fclose(f) == 0;
    if (!ok) {
        fprintf(stderr, "cannot write %s\n", path);
    }
    return ok;
}

int main(int argc, char **argv) {
    const char *file = NULL, *tables_meta = NULL, *display_names = NULL;
    MsBackendOptions options = {.checks = true, .verify = true};
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--opt") == 0 && i + 1 < argc) {
            options.speed = strcmp(argv[++i], "speed") == 0;
        } else if (strcmp(argv[i], "--tables-meta") == 0 && i + 1 < argc) {
            tables_meta = argv[++i];
        } else if (strcmp(argv[i], "--display-names") == 0 && i + 1 < argc) {
            display_names = argv[++i];
        } else if (strcmp(argv[i], "--no-checks") == 0) {
            options.checks = false;
        } else if (strcmp(argv[i], "--no-verify") == 0) {
            options.verify = false;
        } else if (file == NULL) {
            file = argv[i];
        } else {
            file = NULL;
            break;
        }
    }
    if (file == NULL) {
        fputs("usage: ms_mir_build FILE [--opt none|speed] [--no-checks] [--no-verify] [--tables-meta PATH]\n",
              stderr);
        return 2;
    }
    options.tables = tables_meta != NULL;
    size_t n = 0;
    char *src = read_whole_file(file, &n);
    if (src == NULL) {
        fprintf(stderr, "cannot read %s\n", file);
        return 1;
    }
    /* `printed<TAB>name` lines: the names a fault trace shows (ms/emit_program.h). */
    size_t shown_len = 0;
    char *shown = display_names != NULL ? read_whole_file(display_names, &shown_len) : NULL;
    if (display_names != NULL && shown == NULL) {
        fprintf(stderr, "cannot read %s\n", display_names);
        free(src);
        return 1;
    }
    MsBackendText ir = {0}, meta = {0}, why = {0};
    const bool built = ms_backend_ir(src, n, file, shown != NULL ? shown : "", shown_len, &options, &ir, &meta, &why);
    free(src);
    free(shown);
    if (!built) {
        fprintf(stderr, "%.*s\n", (int)why.len, why.ptr != NULL ? why.ptr : "");
        ms_backend_free(&why);
        return 1;
    }
    const bool ok = (tables_meta == NULL || write_file(tables_meta, &meta)) &&
                    fwrite(ir.ptr, 1, ir.len, stdout) == ir.len;
    ms_backend_free(&ir);
    ms_backend_free(&meta);
    return ok ? 0 : 1;
}

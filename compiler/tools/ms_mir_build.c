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

static bool name_is(const MirModule *m, MsSym sym, const char *text, size_t n) {
    const MsStr own = ms_name(&m->names, sym);
    return own.len == n && memcmp(own.ptr, text, n) == 0;
}

/* The file `--display-names` names: `printed<TAB>name` lines. A function whose printed name is `printed` shows
 * `name` in a trace (the text form sanitizes a test's name and numbers duplicates; lowering in C keeps the name). */
static bool apply_display_names(MirModule *m, MsSym *display, uint32_t ndisplay, const char *path) {
    size_t n = 0;
    char *text = read_whole_file(path, &n);
    if (text == NULL) {
        fprintf(stderr, "cannot read %s\n", path);
        return false;
    }
    for (char *line = text; *line != '\0';) {
        char *end = strchr(line, '\n');
        if (end == NULL) {
            end = line + strlen(line);
        }
        char *tab = memchr(line, '\t', (size_t)(end - line));
        if (tab != NULL) {
            const MsSym shown = mir_name(m, tab + 1, (size_t)(end - tab - 1));
            for (uint32_t i = 0; i < m->nfuncs; i++) {
                if (name_is(m, m->funcs[i].name, line, (size_t)(tab - line)) && i < ndisplay) {
                    display[i] = shown;
                }
                for (uint32_t k = 0; k < m->funcs[i].nscopes; k++) { /* an inlined callee names its scope */
                    if (name_is(m, m->funcs[i].scopes[k].name, line, (size_t)(tab - line))) {
                        m->funcs[i].scopes[k].name = shown;
                    }
                }
            }
        }
        line = *end == '\n' ? end + 1 : end;
    }
    free(text);
    return true;
}

int main(int argc, char **argv) {
<<<<<<< HEAD
    const char *file = NULL, *tables_meta = NULL;
    MsBackendOptions options = {.checks = true, .verify = true};
=======
    const char *file = NULL, *tables_meta = NULL, *display_names = NULL;
    bool speed = false, checks = true, verify = true;
>>>>>>> origin/main
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
    MsBackendText ir = {0}, meta = {0}, why = {0};
    const bool built = ms_backend_ir(src, n, file, &options, &ir, &meta, &why);
    free(src);
<<<<<<< HEAD
    if (!built) {
        fprintf(stderr, "%.*s\n", (int)why.len, why.ptr != NULL ? why.ptr : "");
        ms_backend_free(&why);
=======
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
    const uint32_t ndisplay = m.nfuncs; // the emitter may add glue after this
    MsSym *display = MS_NEW_N(&m.arena, MsSym, (size_t)ndisplay + 1); // names the fault tables show
    for (uint32_t i = 0; i < ndisplay; i++) {
        display[i] = m.funcs[i].name;
    }
    if (display_names != NULL && !apply_display_names(&m, display, ndisplay, display_names)) {
        return 1;
    }
    mir_name_symbols(&m);
    mir_lower_ops(&m, &glue);
    MirData data;
    mir_data_build(&m, &glue, &data);
    const bool ok = tables_meta != NULL ? mir_emit_llvm_places(&m, &data, &glue, &out, &why)
                                        : mir_emit_llvm(&m, &data, &glue, &out, &why);
    if (!ok) {
        return fail("the C back end cannot write:\n", &why);
    }
    mir_emit_entry_main(&m, tables_meta != NULL, &out);
    if (tables_meta != NULL && !write_meta(&m, display, ndisplay, tables_meta)) {
>>>>>>> origin/main
        return 1;
    }
    const bool ok = (tables_meta == NULL || write_file(tables_meta, &meta)) &&
                    fwrite(ir.ptr, 1, ir.len, stdout) == ir.len;
    ms_backend_free(&ir);
    ms_backend_free(&meta);
    return ok ? 0 : 1;
}

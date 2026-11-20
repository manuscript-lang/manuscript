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

#include "ms/emit_entry.h"
#include "ms/emit_llvm.h"
#include "ms/mir_asm_tables.h"
#include "ms/mir_opt.h"
#include "read_file.h"

static int fail(const char *what, const MsBuf *text) {
    fprintf(stderr, "%s%.*s\n", what, (int)text->len, text->data != NULL ? text->data : "");
    return 1;
}

/* The description of the functions and scopes that ms_asm_tables needs to build the fault tables. */
static bool write_meta(const MirModule *m, const MsSym *display, uint32_t ndisplay, const char *path) {
    MsBuf meta = {0};
    mir_tables_meta(m, display, ndisplay, &meta);
    FILE *f = fopen(path, "wb");
    const bool ok = f != NULL && fwrite(meta.data, 1, meta.len, f) == meta.len && fclose(f) == 0;
    if (!ok) {
        fprintf(stderr, "cannot write %s\n", path);
    }
    ms_buf_free(&meta);
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
    const char *file = NULL, *tables_meta = NULL, *display_names = NULL;
    bool speed = false, checks = true, verify = true;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--opt") == 0 && i + 1 < argc) {
            speed = strcmp(argv[++i], "speed") == 0;
        } else if (strcmp(argv[i], "--tables-meta") == 0 && i + 1 < argc) {
            tables_meta = argv[++i];
        } else if (strcmp(argv[i], "--display-names") == 0 && i + 1 < argc) {
            display_names = argv[++i];
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
        fputs("usage: ms_mir_build FILE [--opt none|speed] [--no-checks] [--no-verify] [--tables-meta PATH]\n",
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
        return 1;
    }
    fwrite(out.data, 1, out.len, stdout);
    return 0;
}

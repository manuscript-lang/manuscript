/* The C back end in process (ms/emit_program.h): parse the MIR text, optimize, finish, emit. Owns
 * nothing between calls; each call frees the module it built. */
#include "ms/emit_program.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/emit_entry.h"
#include "ms/emit_llvm.h"
#include "ms/mir_asm_tables.h"
#include "ms/mir_opt.h"

/* Hands the bytes of `buf` to the caller and leaves `buf` empty. */
static MsBackendText be_take(MsBuf *buf) {
    const MsBackendText text = {buf->len != 0 ? buf->data : NULL, buf->len};
    if (buf->len == 0) {
        ms_buf_free(buf);
    }
    *buf = (MsBuf){0};
    return text;
}

static bool be_name_is(const MirModule *m, MsSym sym, MsBytes text) {
    const MsStr own = ms_name(&m->names, sym);
    return own.len == text.len && memcmp(own.ptr, text.ptr, text.len) == 0;
}

/* Gives every function and inlined scope whose name in the text is `printed` the name `shown`. */
static void be_show_as(MirModule *m, MsSym *display, uint32_t ndisplay, MsBytes printed, MsSym shown) {
    for (uint32_t i = 0; i < m->nfuncs; i++) {
        if (i < ndisplay && be_name_is(m, m->funcs[i].name, printed)) {
            display[i] = shown;
        }
        for (uint32_t k = 0; k < m->funcs[i].nscopes; k++) { /* an inlined callee names its scope */
            if (be_name_is(m, m->funcs[i].scopes[k].name, printed)) {
                m->funcs[i].scopes[k].name = shown;
            }
        }
    }
}

/* Applies the `printed<TAB>name` lines of `shown` to the names the fault tables show. */
static void be_apply_shown(MirModule *m, MsSym *display, uint32_t ndisplay, MsBytes shown) {
    size_t start = 0;
    while (start < shown.len) {
        const uint8_t *newline = memchr(shown.ptr + start, '\n', shown.len - start);
        const size_t end = newline != NULL ? (size_t)(newline - shown.ptr) : shown.len;
        const uint8_t *tab = memchr(shown.ptr + start, '\t', end - start);
        if (tab != NULL) {
            const size_t split = (size_t)(tab - shown.ptr);
            const MsBytes printed = ms_bytes_of(shown.ptr + start, split - start);
            const MsSym name = mir_name(m, (const char *)shown.ptr + split + 1, end - split - 1);
            be_show_as(m, display, ndisplay, printed, name);
        }
        start = end + 1;
    }
}

/* The passes and the emitter over a parsed module. The IR goes to `ir`, the tables meta to `meta`
 * when asked for, and the reason for a failure to `why`. */
static bool be_emit(MirModule *m, MsBytes shown, const MsBackendOptions *options, MsBuf *ir, MsBuf *meta,
                    MsBuf *why) {
    if (!mir_optimize(m, options->speed ? MIR_OPT_SPEED : MIR_OPT_NONE, options->verify, why)) {
        return false;
    }
    MirGlue glue = {0};
    const MirPipelineOptions pipeline = {.checks = options->checks, .verify = options->verify, .count_ops = options->count_ops};
    if (!mir_pipeline_finish(m, &pipeline, &glue, why)) {
        return false;
    }
    /* The names the fault tables show: the emitter may add glue after these, and `mir_name_symbols`
     * makes the symbols unique. */
    const uint32_t ndisplay = m->nfuncs;
    MsSym *display = MS_NEW_N(&m->arena, MsSym, (size_t)ndisplay + 1);
    for (uint32_t i = 0; i < ndisplay; i++) {
        display[i] = m->funcs[i].name;
    }
    be_apply_shown(m, display, ndisplay, shown);
    mir_name_symbols(m);
    mir_lower_ops(m, &glue);
    MirData data;
    mir_data_build(m, &glue, &data);
    MsBuf cannot = {0};
    const bool ok = options->tables ? mir_emit_llvm_places(m, &data, &glue, ir, &cannot)
                                    : mir_emit_llvm(m, &data, &glue, ir, &cannot);
    if (!ok) {
        ms_buf_printf(why, "the C back end cannot write:\n%.*s", (int)cannot.len, cannot.data != NULL ? cannot.data : "");
        ms_buf_free(&cannot);
        return false;
    }
    ms_buf_free(&cannot);
    mir_emit_entry_main(m, options->tables, ir);
    if (options->tables) {
        mir_tables_meta(m, display, ndisplay, meta);
    }
    return true;
}

bool ms_backend_ir(const char *mir, size_t mir_len, const char *name, const char *shown, size_t shown_len,
                   const MsBackendOptions *options, MsBackendText *ir, MsBackendText *meta, MsBackendText *why) {
    MirModule m;
    mir_module_init(&m);
    MsBuf ir_buf = {0}, meta_buf = {0}, why_buf = {0};
    uint32_t line = 0;
    MsStr message = {0};
    bool ok = mir_parse(&m, mir, mir_len, &line, &message);
    if (!ok) {
        ms_buf_printf(&why_buf, "%s:%u: %.*s", name, line, (int)message.len, message.ptr);
    } else {
        ok = be_emit(&m, ms_bytes_of((const uint8_t *)shown, shown_len), options, &ir_buf, &meta_buf, &why_buf);
    }
    mir_module_free(&m);
    if (!ok) {
        ms_buf_free(&ir_buf);
        ms_buf_free(&meta_buf);
        *why = be_take(&why_buf);
        return false;
    }
    ms_buf_free(&why_buf);
    *ir = be_take(&ir_buf);
    *meta = be_take(&meta_buf);
    return true;
}

bool ms_backend_tables(const char *meta, size_t meta_len, const char *asm_text, size_t asm_len,
                       const char *prefix, MsBackendText *out, MsBackendText *why) {
    MsBuf out_buf = {0}, why_buf = {0};
    if (!mir_asm_tables(meta, meta_len, asm_text, asm_len, prefix, true, &out_buf, &why_buf)) {
        ms_buf_free(&out_buf);
        *why = be_take(&why_buf);
        return false;
    }
    ms_buf_free(&why_buf);
    *out = be_take(&out_buf);
    return true;
}

void ms_backend_free(MsBackendText *text) {
    free(text->ptr);
    *text = (MsBackendText){0};
}

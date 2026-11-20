/* The C back end in process (ms/emit_program.h): parse the MIR text, optimize, finish, emit. Owns
 * nothing between calls; each call frees the module it built. */
#include "ms/emit_program.h"

#include <stdio.h>
#include <stdlib.h>

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

/* The passes and the emitter over a parsed module. The IR goes to `ir`, the tables meta to `meta`
 * when asked for, and the reason for a failure to `why`. */
static bool be_emit(MirModule *m, const MsBackendOptions *options, MsBuf *ir, MsBuf *meta, MsBuf *why) {
    if (!mir_optimize(m, options->speed ? MIR_OPT_SPEED : MIR_OPT_NONE, options->verify, why)) {
        return false;
    }
    MirGlue glue = {0};
    const MirPipelineOptions pipeline = {.checks = options->checks, .verify = options->verify};
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

bool ms_backend_ir(const char *mir, size_t mir_len, const char *name, const MsBackendOptions *options,
                   MsBackendText *ir, MsBackendText *meta, MsBackendText *why) {
    MirModule m;
    mir_module_init(&m);
    MsBuf ir_buf = {0}, meta_buf = {0}, why_buf = {0};
    uint32_t line = 0;
    MsStr message = {0};
    bool ok = mir_parse(&m, mir, mir_len, &line, &message);
    if (!ok) {
        ms_buf_printf(&why_buf, "%s:%u: %.*s", name, line, (int)message.len, message.ptr);
    } else {
        ok = be_emit(&m, options, &ir_buf, &meta_buf, &why_buf);
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

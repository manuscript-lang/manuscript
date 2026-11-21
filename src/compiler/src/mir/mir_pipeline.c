/* pipeline: the passes between lowering and the backends, in the order the Rust build runs them
 * (func.rs, native.rs). `mir_pipeline_prepare` runs right after lowering; `mir_pipeline_optimize`
 * then runs the optimizer (opt_pipeline.c); `mir_pipeline_finish` runs the ownership and expansion passes.
 *
 *   prepare: elaborate (with cancel exits when edges are on), verify
 *   finish:  count_ops (when on), unwind, cancel_edges (when on), depth, expand, glue + expand_owned
 *
 * Each step verifies the module afterwards when `verify` is set, as the Rust debug build does. */
#include <string.h>

#include "ms/mir_pass.h"
#include "ms/mir_verify.h"

/* Verifies the module and reports `after <pass>: ...` on failure. */
static bool pl_verify(const MirModule *m, const char *pass, MsBuf *error) {
    MirVerifyErrors errors = {0};
    if (mir_verify_module(m, false, &errors)) {
        mir_verify_errors_free(&errors);
        return true;
    }
    ms_buf_printf(error, "module does not verify after %s:", pass);
    for (uint32_t i = 0; i < errors.count; i++) {
        ms_buf_printf(error, "\n");
        mir_verify_error_text(&errors.errors[i], error);
    }
    mir_verify_errors_free(&errors);
    return false;
}

bool mir_pipeline_prepare(MirModule *m, const MirPipelineOptions *o, MsBuf *error) {
    if (!mir_elaborate_with(m, o->cancel_edges, error)) {
        return false;
    }
    return !o->verify || pl_verify(m, "elaborate", error);
}

bool mir_pipeline_optimize(MirModule *m, MirOptLevel level, const MirPipelineOptions *o, MsBuf *error) {
    return mir_optimize(m, level, o->verify, error);
}

bool mir_pipeline_finish(MirModule *m, const MirPipelineOptions *o, MirGlue *glue, MsBuf *error) {
    if (o->count_ops) {
        mir_count_ops(m);
    }
    /* Not an optimization: it keeps cancellation from leaking, so every profile runs it. */
    if (mir_unwind(m) && o->verify && !pl_verify(m, "unwind", error)) {
        return false;
    }
    /* The hybrid cancel exits run the cleanups `unwind` registered, so they go in after it: its
     * discard after a parking call must not sit between the call and the check. */
    if (o->cancel_edges && mir_cancel_edges(m) && o->verify && !pl_verify(m, "cancel_edges", error)) {
        return false;
    }
    /* After `unwind`, which looks for the check as the first instruction of a function. */
    if (mir_depth_lower(m) && o->verify && !pl_verify(m, "depth", error)) {
        return false;
    }
    /* The checks and list growth the backends lower are explicit MIR from here on. */
    (void)mir_expand(m, o->checks);
    if (o->verify && !pl_verify(m, "expand", error)) {
        return false;
    }
    /* Drop and clone functions are made here; the backends lower only primitives. */
    mir_glue_run_and_expand(m, glue);
    return true;
}

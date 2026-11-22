/* compiler/mir/mir_pipeline.c: see mir_pipeline.h. */
#include "compiler/mir/mir_pipeline.h"
#include "compiler/mir/mir_desc_glue.h"

#include "compiler/mir/mir_cancel_edges.h"
#include "compiler/mir/mir_count_ops.h"
#include "compiler/mir/mir_depth.h"
#include "compiler/mir/mir_elab.h"
#include "compiler/mir/mir_expand.h"
#include "compiler/mir/mir_lower_ops.h"
#include "compiler/mir/mir_unwind.h"
#include "compiler/mir/mir_verify.h"

/* Verifies the module and reports `module does not verify after <pass>: ...` on failure. */
static bool verified(const MirModule *module, const char *pass, MsStrBuild *error) {
  MirVerifyErrors errors = {0};
  const bool ok = mir_verify_module(module, false, &errors);
  if (!ok) {
    ms_strbuild_printf(error, "module does not verify after %s:", pass);
    for (size_t index = 0; index < errors.errors.len; index++) {
      ms_strbuild_append_byte(error, '\n');
      mir_verify_error_text(&errors.errors.ptr[index], error);
    }
  }
  mir_verify_errors_free(&errors);
  return ok;
}

bool mir_pipeline_prepare(MirModule *module, const MirPipelineOptions *options, MsStrBuild *error) {
  (void)mir_depth_mark(module);
  return mir_elaborate(module, error) && (!options->verify || verified(module, "elaborate", error));
}

bool mir_pipeline_finish(MirModule *module, const MirPipelineOptions *options, MirGlue *glue, MsStrBuild *error) {
  if (options->count_ops) {
    mir_count_ops(module);
  }
  /* Not an optimization: it keeps cancellation from leaking, so every profile runs it. */
  if (mir_unwind(module) && options->verify && !verified(module, "unwind", error)) {
    return false;
  }
  /* The hybrid cancel exits run the cleanups unwind registered, so they go in after it. */
  if (options->cancel_edges && mir_cancel_edges(module) && options->verify && !verified(module, "cancel_edges", error)) {
    return false;
  }
  /* After unwind, which looks for the check as the first instruction of a function. */
  if (mir_depth_lower(module) && options->verify && !verified(module, "depth", error)) {
    return false;
  }
  /* The checks and list growth the emitter prints are explicit MIR from here on. */
  (void)mir_expand(module, options->checks);
  if (options->verify && !verified(module, "expand", error)) {
    return false;
  }
  /* Drop and clone functions are made here; the emitter prints only primitives. */
  mir_desc_glue(module); /* its functions only call the runtime, so glue and lowering need nothing more */
  mir_glue_run_and_expand(module, glue);
  return true;
}

void mir_pipeline_backend(MirModule *module, const MirGlue *glue, MirData *data) {
  mir_lower_ops(module, glue);
  mir_data_build(module, glue, data);
}

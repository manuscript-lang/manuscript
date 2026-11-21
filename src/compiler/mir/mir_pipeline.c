/* compiler/mir/mir_pipeline.c: see mir_pipeline.h. */
#include "compiler/mir/mir_pipeline.h"

#include "compiler/mir/mir_elab.h"
#include "compiler/mir/mir_expand.h"
#include "compiler/mir/mir_lower_ops.h"

bool mir_pipeline_prepare(MirModule *module, MsStrBuild *error) {
  return mir_elaborate(module, error);
}

bool mir_pipeline_finish(MirModule *module, bool checks, MirGlue *glue, MsStrBuild *error) {
  (void)error;
  /* The checks and list growth the emitter prints are explicit MIR from here on. */
  (void)mir_expand(module, checks);
  /* Drop and clone functions are made here; the emitter prints only primitives. */
  mir_glue_run_and_expand(module, glue);
  return true;
}

void mir_pipeline_backend(MirModule *module, const MirGlue *glue, MirData *data) {
  mir_lower_ops(module, glue);
  mir_data_build(module, glue, data);
}

/* compiler/mir/mir_pipeline.h: the passes between lowering and the emitter, in the order they run, over the
 * in-memory module (no text between passes).
 *
 *   prepare: drop elaboration, then verify
 *   finish:  count ops (profiling), unwind, cancel edges, depth guard, list checks and growth expanded, glue
 *            made and expanded; each step verifies the module afterwards when asked
 *   backend: ownership ops lowered to plain calls; the module's static data built
 *
 * The optimizer runs between prepare and finish. */
#ifndef MS_COMPILER_MIR_MIR_PIPELINE_H
#define MS_COMPILER_MIR_MIR_PIPELINE_H

#include "base/strbuild.h"
#include "compiler/mir/mir_data.h"
#include "compiler/mir/mir_glue.h"

typedef struct MirPipelineOptions {
  bool verify;       /* verify after every pass */
  bool count_ops;    /* profile builds */
  bool checks;       /* keep list bounds checks */
} MirPipelineOptions;

/* Runs right after lowering. On failure `error` names the function and the reason. */
bool mir_pipeline_prepare(MirModule *module, const MirPipelineOptions *options, MsStrBuild *error);

/* Fills `glue`, which the caller frees with mir_glue_free. */
bool mir_pipeline_finish(MirModule *module, const MirPipelineOptions *options, MirGlue *glue, MsStrBuild *error);

/* The last MIR step before the emitter. Fills `data`, which the caller frees with mir_data_free. */
void mir_pipeline_backend(MirModule *module, const MirGlue *glue, MirData *data);

#endif

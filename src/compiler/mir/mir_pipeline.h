/* compiler/mir/mir_pipeline.h: the passes between lowering and the emitter, in the order they run, over the
 * in-memory module (no text between passes).
 *
 *   prepare: drop elaboration
 *   finish:  list checks and growth expand; glue made and expanded
 *   backend: ownership ops lowered to plain calls; the module's static data built
 *
 * The optimizer runs between prepare and finish. */
#ifndef MS_COMPILER_MIR_MIR_PIPELINE_H
#define MS_COMPILER_MIR_MIR_PIPELINE_H

#include "base/strbuild.h"
#include "compiler/mir/mir_data.h"
#include "compiler/mir/mir_glue.h"

/* Runs right after lowering. On failure `error` names the function and the reason. */
bool mir_pipeline_prepare(MirModule *module, MsStrBuild *error);

/* `checks` keeps the list bounds checks. Fills `glue`, which the caller frees with mir_glue_free. */
bool mir_pipeline_finish(MirModule *module, bool checks, MirGlue *glue, MsStrBuild *error);

/* The last MIR step before the emitter. Fills `data`, which the caller frees with mir_data_free. */
void mir_pipeline_backend(MirModule *module, const MirGlue *glue, MirData *data);

#endif

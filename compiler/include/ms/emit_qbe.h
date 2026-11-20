/* libms QBE emitter: writes QBE's SSA text from MIR, for debug builds. The caller runs QBE on the
 * text, assembles its output and links. Covers the scalar subset so far; the rest is reported. */
#ifndef MS_EMIT_QBE_H
#define MS_EMIT_QBE_H

#include "ms/mir.h"
#include "ms/mir_pass.h"

/* Runs glue on `m`, then appends the QBE text of its static data and every function to `out`. Returns false when something cannot be
 * written yet, with one line per function and reason appended to `why` (`out` is then partial). */
bool mir_emit_qbe(MirModule *m, MsBuf *out, MsBuf *why);

/* The same for a module the pipeline has finished (`mir_pipeline_finish`), whose glue is `glue`. */
bool mir_emit_qbe_glued(MirModule *m, MirGlue *glue, MsBuf *out, MsBuf *why);

#endif

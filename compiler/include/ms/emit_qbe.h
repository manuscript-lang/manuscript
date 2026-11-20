/* libms QBE emitter: writes QBE's SSA text from MIR, for debug builds. The caller runs QBE on the
 * text, assembles its output and links. Covers the scalar subset so far; the rest is reported. */
#ifndef MS_EMIT_QBE_H
#define MS_EMIT_QBE_H

#include "ms/mir.h"

/* Appends the QBE text of every function of `m` to `out`. Returns false when something cannot be
 * written yet, with one line per function and reason appended to `why` (`out` is then partial). */
bool mir_emit_qbe(const MirModule *m, MsBuf *out, MsBuf *why);

#endif

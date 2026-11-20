/* libms LLVM emitter: writes LLVM IR text from MIR, for release builds. The caller runs the LLVM
 * tools on the text and links. Covers the scalar subset so far (the one `emit_qbe.h` covers); the
 * rest is reported. */
#ifndef MS_EMIT_LLVM_H
#define MS_EMIT_LLVM_H

#include "ms/mir.h"
#include "ms/mir_data.h"
#include "ms/mir_pass.h"

/* Appends one LLVM module holding every function of `m` to `out`, with the static data of `data`
 * (`mir_data_build` after glue; NULL for a module with none) and the glue the closure objects
 * point at (`mir_glue_run_and_expand`; NULL for a module with no closures). Returns false when something
 * cannot be written yet, with one line per function and reason appended to `why` (`out` is then
 * partial). */
bool mir_emit_llvm(const MirModule *m, const MirData *data, const MirGlue *glue, MsBuf *out, MsBuf *why);

#endif

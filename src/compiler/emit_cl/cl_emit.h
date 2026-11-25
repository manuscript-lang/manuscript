/* compiler/emit_cl/cl_emit.h: MIR to a Cranelift object, the Debug back end.
 *
 * The lowering reads a finished MirModule and has the Cranelift library (cranelift_inproc.h, loaded first) write one
 * object file. A function it cannot lower is reported by name and reason in `why`; the build then falls back to the
 * LLVM route. Symbols, calling convention and the runtime interface are those of compiler/emit, so the object links
 * with the runtime the same way. */
#ifndef MS_COMPILER_EMIT_CL_CL_EMIT_H
#define MS_COMPILER_EMIT_CL_CL_EMIT_H

#include "base/strbuild.h"
#include "compiler/mir/mir.h"
#include "compiler/mir/mir_data.h"
#include "compiler/mir/mir_glue.h"

typedef struct ClOptions {
  bool export_all; /* every function gets an external symbol (needed when fault tables name them) */
  bool places;     /* record each instruction's source line (DWARF line table and ranges for the fault tables) */
} ClOptions;

/* Lowers `module` (after emit_name_symbols) and appends the object file's bytes to `object`. False when some function
 * could not be lowered or the library refused; `why` then lists one `name: reason` line per function. */
bool cl_emit_module(const MirModule *module, const MirData *data, const MirGlue *glue, const ClOptions *options,
                    MsStrBuild *object, MsStrBuild *why);

#endif

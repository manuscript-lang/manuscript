/* compiler/emit_cl/cranelift_inproc.h: the Cranelift shared library (manuscript-lang/cranelift-bundle), loaded by path when
 * first used. Its API is the table `cl_fns` of cranelift.h, filled by `cranelift_load`; the Debug emitter
 * (compiler/emit_cl) calls the `cl_*` functions through it. */
#ifndef MS_COMPILER_LINK_CRANELIFT_INPROC_H
#define MS_COMPILER_LINK_CRANELIFT_INPROC_H

#define CL_DYNAMIC
#include "compiler/emit_cl/cranelift.h"

#include "base/strbuild.h"

/* Loads the library at `path` (once) and binds every function; on failure `why` holds the reason (the library cannot
 * be opened, or the first function it lacks). */
MS_NODISCARD MS_NONNULL bool cranelift_load(MsSpan path, MsStrBuild *why);

/* Whether the library at `path` loads and has the whole API; it stays loaded. */
MS_NODISCARD bool cranelift_usable(MsSpan path);

#endif

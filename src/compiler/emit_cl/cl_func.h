/* compiler/emit_cl/cl_func.h: how one function is lowered to Cranelift IR. */
#ifndef MS_COMPILER_EMIT_CL_CL_FUNC_H
#define MS_COMPILER_EMIT_CL_CL_FUNC_H

#include "compiler/emit_cl/cl_cx.h"

/* Lowers `cx->func` (function `cx->index`) with the builder `cx->fb` and queues it for the library's workers; false with
 * `cx->why` set when it cannot. */
bool cl_lower_function(ClCx *cx);

#endif

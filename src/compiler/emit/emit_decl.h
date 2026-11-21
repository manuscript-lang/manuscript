/* compiler/emit/emit_decl.h: the declarations that close a module. */
#ifndef MS_COMPILER_EMIT_EMIT_DECL_H
#define MS_COMPILER_EMIT_EMIT_DECL_H

#include "compiler/emit/emit_cx.h"

/* Declares the runtime functions the module lists, the allocator and fault functions the emitter calls itself,
 * and the LLVM intrinsics it uses. `cx->func` is NULL. */
void emit_declarations(EmitCx *cx);

#endif

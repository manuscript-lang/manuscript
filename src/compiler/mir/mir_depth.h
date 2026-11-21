/* compiler/mir/mir_depth.h: lowers the stack-depth check of recursive functions. */
#ifndef MS_COMPILER_MIR_MIR_DEPTH_H
#define MS_COMPILER_MIR_MIR_DEPTH_H

#include "compiler/mir/mir.h"

/* Lowers every `depth.enter` at the head of a function's entry block to ordinary operations (see mir_depth.c);
 * true when it changed anything. Runs last, after unwind. */
bool mir_depth_lower(MirModule *module);

#endif

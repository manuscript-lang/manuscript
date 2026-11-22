/* compiler/mir/mir_depth.h: lowers the stack-depth check of recursive functions. */
#ifndef MS_COMPILER_MIR_MIR_DEPTH_H
#define MS_COMPILER_MIR_MIR_DEPTH_H

#include "compiler/mir/mir.h"

/* Lowers every `depth.enter` at the head of a function's entry block to ordinary operations (see mir_depth.c);
 * true when it changed anything. Runs last, after unwind. */
bool mir_depth_lower(MirModule *module);

/* Puts `depth.enter` first in the entry block of every function that can recurse: one in a cycle of direct
 * calls, or one that calls through a pointer (a closure or interface method may lead back to it). Runs before
 * elaboration; true when it changed anything. */
bool mir_depth_mark(MirModule *module);

#endif

/* compiler/mir/mir_cancel_edges.h: makes a delivered cancel leave a task by ordinary returns. */
#ifndef MS_COMPILER_MIR_MIR_CANCEL_EDGES_H
#define MS_COMPILER_MIR_MIR_CANCEL_EDGES_H

#include "compiler/mir/mir.h"

/* After every call that can park, tests the task's `unwinding` byte and leaves the function through a cancel
 * exit (see mir_cancel_edges.c). True when it changed anything; false without task-starting externs. */
bool mir_cancel_edges(MirModule *module);

#endif

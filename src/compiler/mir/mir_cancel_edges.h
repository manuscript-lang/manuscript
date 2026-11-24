/* compiler/mir/mir_cancel_edges.h: announces that a delivered cancel leaves a task by ordinary returns. */
#ifndef MS_COMPILER_MIR_MIR_CANCEL_EDGES_H
#define MS_COMPILER_MIR_MIR_CANCEL_EDGES_H

#include "compiler/mir/mir.h"

/* Calls `msrt_cancel_edges` first in the entry of a program that starts tasks (see mir_cancel_edges.c). True when
 * it changed anything. */
bool mir_cancel_edges(MirModule *module);

#endif

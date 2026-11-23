/* compiler/mir/mir_shed.h: drops the cleanup entries that only free memory when no task can outlive a fault. */
#ifndef MS_COMPILER_MIR_MIR_SHED_H
#define MS_COMPILER_MIR_MIR_SHED_H

#include "compiler/mir/mir.h"

/* True when it removed anything; false in a program that starts tasks (see mir_shed.c). */
bool mir_shed(MirModule *module);

#endif

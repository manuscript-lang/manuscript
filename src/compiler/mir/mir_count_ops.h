/* compiler/mir/mir_count_ops.h: the pass that counts executed operations (`ms run --ops`). */
#ifndef MS_COMPILER_MIR_MIR_COUNT_OPS_H
#define MS_COMPILER_MIR_MIR_COUNT_OPS_H

#include "compiler/mir/mir.h"

/* Calls `msrt_ops_add(n)` at the head of every block, n being its instruction count plus one. */
void mir_count_ops(MirModule *module);

#endif

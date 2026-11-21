/* compiler/mir/mir_lower_ops.h: rewrites the ownership ops a back end would otherwise write itself (`clone`,
 * `drop`, `move.out`, `forget`, `str.len`, and the list, record, cleanup and fault-message ops) into plain calls
 * and copies, so every emitter prints scalars, memory, calls and data only.
 *
 * A value that needs no drop is its own clone, so its uses are renamed to the operand. A string is cloned and
 * freed by the runtime, which tests the tag itself, so no block is split. Any other owned type calls its glue
 * function. Runs last, after every pass that reads the ownership ops. */
#ifndef MS_COMPILER_MIR_MIR_LOWER_OPS_H
#define MS_COMPILER_MIR_MIR_LOWER_OPS_H

#include "compiler/mir/mir_glue.h"

void mir_lower_ops(MirModule *module, const MirGlue *glue);

#endif

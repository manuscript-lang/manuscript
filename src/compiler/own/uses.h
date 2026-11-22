/* compiler/own/uses.h: the `uses` fact column, which uses of a local move, borrow or clone it.
 *
 * A use of a local is the NAME node; a field of a local that moves out alone is the MEMBER node (a partial move,
 * the root NAME stays a borrow). A use is MOVE only where the language hands the value to a new owner and the
 * value is not Copy: the operand of `return`, of `var x = ...` and of a store, an argument for a `move`
 * parameter, an element of a list or map, an argument of a record or case constructor. `.clone()` on a local
 * marks its receiver CLONE. Every other use of a local is BORROW. Whether a move is the last use, and
 * conditional drops, are decided by lowering. */
#ifndef MS_COMPILER_OWN_USES_H
#define MS_COMPILER_OWN_USES_H

#include "compiler/check/program.h"

/* Fills the `uses` column of each user module whose facts the checker produced. */
void ms_own_uses(MsCheckProgram *program);

/* Whether the callee is a method declared `move fn`, which takes its receiver. */
bool ms_own_consuming_method(const MsCheckProgram *program, const MsRef *callee);

#endif

/* compiler/own/moves.h: reports a value that is used again after a move.
 *
 * A moving use (see uses.h) hands the value to a new owner; the binding may not be used after it on any path,
 * because a copy is made only where the source says `.clone()`. Runs when checking found nothing else. */
#ifndef MS_COMPILER_OWN_MOVES_H
#define MS_COMPILER_OWN_MOVES_H

#include "compiler/check/program.h"

void ms_own_moves(MsCheckProgram *program);

/* One instance of a generic body, its type variables `vars` bound to `args`: whether a plain parameter, or a view of one,
 * whose type is a type variable that became a resource is handed on (returned, a constructor argument, a `move`
 * argument). The copy that needs would fault; `at` and `who` name the use. */
bool ms_own_moves_instance(MsCheckProgram *program, uint32_t module, const MsFunc *func, const MsTy *vars,
                           const MsTy *args, uint32_t count, MsPos *at, MsName *who);

#endif

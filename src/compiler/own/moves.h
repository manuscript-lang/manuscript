/* compiler/own/moves.h: reports a value that is used again after a move.
 *
 * A moving use (see uses.h) hands the value to a new owner; the binding may not be used after it on any path,
 * because a copy is made only where the source says `.clone()`. Runs when checking found nothing else. */
#ifndef MS_COMPILER_OWN_MOVES_H
#define MS_COMPILER_OWN_MOVES_H

#include "compiler/check/program.h"

void ms_own_moves(MsCheckProgram *program);

#endif

/* compiler/own/overlaps.h: reports a call whose operands overlap one another.
 *
 * The receiver, the called value and the arguments of one call are all in use while it runs. An operand that moves
 * or changes a place in place (a `var` or `move` argument, a receiver a callback changes, a nested assignment or
 * `var` call that runs while the others are held) may not overlap a place another operand reads or changes. Runs
 * when checking found nothing else. */
#ifndef MS_COMPILER_OWN_OVERLAPS_H
#define MS_COMPILER_OWN_OVERLAPS_H

#include "compiler/check/program.h"

void ms_own_overlaps(MsCheckProgram *program);

#endif

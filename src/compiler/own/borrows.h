/* compiler/own/borrows.h: reports a value changed while a binding that borrows it is still used.
 *
 * A call result borrows what it was computed from unless the callee's signature says `move` before the result
 * type. A binding initialised with such a borrow keeps its source alive and unchanged until its last use: a
 * change of the source (a reassignment, or a call that takes it as `var`) before that use is rejected. Runs
 * when checking found nothing else. */
#ifndef MS_COMPILER_OWN_BORROWS_H
#define MS_COMPILER_OWN_BORROWS_H

#include "compiler/check/program.h"

void ms_own_borrows(MsCheckProgram *program);

#endif

/* compiler/own/relays.h: borrowed results that would leave as owned ones.
 *
 * `.clone()` is the only copy. A `?` that relays the error of a borrowed `Result` hands out an owner of memory the
 * borrow does not own, and so does a function that returns a borrow of its arguments used as a function value whose result
 * is owned. Both must say `.clone()` (or start from an owner). Runs when checking found nothing else. */
#ifndef MS_COMPILER_OWN_RELAYS_H
#define MS_COMPILER_OWN_RELAYS_H

#include "compiler/check/program.h"

void ms_own_relays(MsCheckProgram *program);

#endif

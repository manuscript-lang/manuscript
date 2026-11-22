/* compiler/own/unused.h: local and match-payload bindings that are never read.
 *
 * Runs only on a program with no other diagnostics, as the oracle does. A name starting with `_` is exempt. A
 * read inside the right-hand side of an assignment to the same binding (`total = total + 2`) only feeds that
 * binding's next value and does not count; the message says so. */
#ifndef MS_COMPILER_OWN_UNUSED_H
#define MS_COMPILER_OWN_UNUSED_H

#include "compiler/check/program.h"

void ms_own_unused(MsCheckProgram *program);

#endif

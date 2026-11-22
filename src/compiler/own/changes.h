/* compiler/own/changes.h: reports a value changed through a binding that is not `var`.
 *
 * A call whose receiver or argument is a `var` position changes the place it names; a place rooted at a
 * parameter that is not `var`, a `:=` binding or a loop variable cannot be changed. Runs when checking found
 * nothing else. */
#ifndef MS_COMPILER_OWN_CHANGES_H
#define MS_COMPILER_OWN_CHANGES_H

#include "compiler/check/program.h"

void ms_own_changes(MsCheckProgram *program);

#endif

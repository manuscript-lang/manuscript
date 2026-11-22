/* compiler/own/escapes.h: which closures outlive the statement that makes them.
 *
 * A closure is non-escaping when it is only called, or passed to a parameter its callee does not keep (a
 * parameter not declared `move` whose function only calls it or hands it to such parameters); then it borrows
 * what it captures. Any other closure (returned, stored, passed to a keeping parameter, started as a promise)
 * escapes and owns its captures. The result is the `uses` column of the lambda: MS_USE_MOVE when it escapes,
 * MS_USE_BORROW when it does not. Runs over every module after ms_own_uses. */
#ifndef MS_COMPILER_OWN_ESCAPES_H
#define MS_COMPILER_OWN_ESCAPES_H

#include "compiler/check/program.h"

void ms_own_escapes(MsCheckProgram *program);

#endif

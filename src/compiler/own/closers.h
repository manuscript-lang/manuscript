/* compiler/own/closers.h: the `closers` fact table, which local bindings are closed where their scope ends.
 *
 * A local `:=` or `var` binding whose type implements Closeable is closed by its `close` method on every exit of
 * its scope. The fact names that method and says whether it can fail, consumes the value, or changes it in
 * place, and whether the body also closes the binding by hand. Lowering turns each fact into a scope owner. */
#ifndef MS_COMPILER_OWN_CLOSERS_H
#define MS_COMPILER_OWN_CLOSERS_H

#include "compiler/check/program.h"

/* Fills the `closers` table of each user module whose facts the checker produced. */
void ms_own_closers(MsCheckProgram *program);

#endif

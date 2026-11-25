/* compiler/check/lazy_std.h: bundled standard bodies checked on demand (see lazy_std.c). */
#ifndef MS_COMPILER_CHECK_LAZY_STD_H
#define MS_COMPILER_CHECK_LAZY_STD_H

#include "compiler/check/program.h"

/* A copy of a parsed standard module whose functions and methods are the program's own, so deferring and restoring
 * their bodies leaves the shared tree (a parse cache's) whole for the next program. Nodes below them are shared. */
const MsModule *ms_check_clone_for_deferral(MsCheckProgram *program, const MsModule *tree);

/* Sets the bodies of the bundled standard functions and methods aside. Runs once the standard modules are loaded. */
void ms_check_defer_std_bodies(MsCheckProgram *program);

/* Gives back and checks the body of every standard function or method a checked body names, transitively. */
void ms_check_restore_reached(MsCheckProgram *program);

void ms_check_lazy_std_free(MsCheckProgram *program);

#endif

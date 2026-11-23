/* compiler/check/lazy_std.h: bundled standard bodies checked on demand (see lazy_std.c). */
#ifndef MS_COMPILER_CHECK_LAZY_STD_H
#define MS_COMPILER_CHECK_LAZY_STD_H

#include "compiler/check/program.h"

/* Sets the bodies of the bundled standard functions and methods aside. Runs once the standard modules are loaded. */
void ms_check_defer_std_bodies(MsCheckProgram *program);

/* Gives back and checks the body of every standard function or method a checked body names, transitively. */
void ms_check_restore_reached(MsCheckProgram *program);

void ms_check_lazy_std_free(MsCheckProgram *program);

#endif

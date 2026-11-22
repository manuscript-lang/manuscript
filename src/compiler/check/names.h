/* compiler/check/names.h: the name-resolution pass over function bodies.
 *
 * A syntax-only walk that reports each name read that nothing in scope gives a meaning: not a local, a
 * parameter, `self`, a declaration of the module, an import, a case of any enum, or the prelude function. The
 * walk errs toward silence: a name it cannot rule out is left alone. */
#ifndef MS_COMPILER_CHECK_NAMES_H
#define MS_COMPILER_CHECK_NAMES_H

#include "compiler/check/program.h"

void ms_check_names(MsCheckProgram *program, uint32_t module);

/* Whether any enum of any loaded module has a case called `name`. */
bool ms_check_is_case_name(const MsCheckProgram *program, MsName name);

#endif

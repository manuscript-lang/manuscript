/* compiler/check/constants.h: the rules for module-level constants that need no types.
 *
 * A constant takes literals, operators, collections and other constants only; anything else needs a function.
 * One diagnostic per constant (a failed part stops the walk), and a constant that reaches itself through
 * other constants is reported once. */
#ifndef MS_COMPILER_CHECK_CONSTANTS_H
#define MS_COMPILER_CHECK_CONSTANTS_H

#include "compiler/check/program.h"

void ms_check_constants(MsCheckProgram *program, uint32_t module);

#endif

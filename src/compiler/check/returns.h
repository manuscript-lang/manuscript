/* compiler/check/returns.h: the return-statement pass.
 *
 * A bare `return` ends a function whose result is Void or Void!; in any other function it is an error that
 * names the result type. Lambdas return to their own result type and are not entered. */
#ifndef MS_COMPILER_CHECK_RETURNS_H
#define MS_COMPILER_CHECK_RETURNS_H

#include "compiler/check/program.h"

void ms_check_returns(MsCheckProgram *program, uint32_t module);

#endif

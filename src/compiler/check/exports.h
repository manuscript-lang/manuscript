/* compiler/check/exports.h: a public declaration may not expose a private type of its own module. */
#ifndef MS_COMPILER_CHECK_EXPORTS_H
#define MS_COMPILER_CHECK_EXPORTS_H

#include "compiler/check/program.h"

void ms_check_exports(MsCheckProgram *program, uint32_t module);

#endif

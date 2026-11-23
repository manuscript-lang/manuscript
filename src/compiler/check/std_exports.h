/* compiler/check/std_exports.h: which bundled standard module exports a name.
 *
 * Backs the "add: import NAME from MODULE" hint of an unknown name. The first exporter in name order wins
 * (internal ones excluded); the first call parses them all and indexes their exports for the process. */
#ifndef MS_COMPILER_CHECK_STD_EXPORTS_H
#define MS_COMPILER_CHECK_STD_EXPORTS_H

#include "compiler/check/program.h"

/* The first module, as `@std/<file>`, that exports `name` (a type, when `types_only`); appended to `out`. False when none does. */
bool ms_std_exporter(MsCheckProgram *program, MsSpan name, bool types_only, MsStrBuild *out);

#endif

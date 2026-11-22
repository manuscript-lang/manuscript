/* compiler/check/std_exports.h: which bundled standard module exports a name.
 *
 * Backs the "add: import NAME from MODULE" hint of an unknown name. Modules are searched in name order
 * (internal ones excluded), each parsed on demand, so call it only when a diagnostic is being written. */
#ifndef MS_COMPILER_CHECK_STD_EXPORTS_H
#define MS_COMPILER_CHECK_STD_EXPORTS_H

#include "compiler/check/program.h"

/* The first module, as `@std/<file>`, that exports `name`; appended to `out`. False when none does. */
bool ms_std_exporter(MsCheckProgram *program, MsSpan name, MsStrBuild *out);

#endif

/* compiler/own/own.h: the ownership check, the entry point of the own layer.
 *
 * Runs after the checker over the same program: reports move and borrow diagnostics through
 * ms_check_report (type phase) and fills each module's `uses` fact column. The driver calls it after
 * ms_check_graph. */
#ifndef MS_COMPILER_OWN_OWN_H
#define MS_COMPILER_OWN_OWN_H

#include "compiler/check/program.h"

void ms_own_check(MsCheckProgram *program);

#endif

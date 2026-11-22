/* compiler/check/order.h: the order diagnostics are listed in.
 *
 * The oracle checks one declaration at a time, so its diagnostics come declaration by declaration: what precedes
 * the first declaration (imports), then each declaration's in the order found. The C checker runs whole-module
 * passes (imports, names, bodies), so the list is sorted afterwards: imports, the declaration passes, then each
 * declaration's body diagnostics, which keep the order the body walk found them in with the other passes' slipped
 * in by position, and what is found at the end of a body last. */
#ifndef MS_COMPILER_CHECK_ORDER_H
#define MS_COMPILER_CHECK_ORDER_H

#include "compiler/check/program.h"

void ms_check_order_diagnostics(MsCheckProgram *program);

#endif

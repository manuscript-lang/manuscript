/* compiler/check/shadow.h: a binding that hides one of an enclosing scope.
 *
 * A `:=` or `var` binding, loop variable, narrowed name, match payload or lambda parameter named like a binding
 * of an enclosing block of the same function (a parameter included) is reported: "binding x shadows an outer
 * binding of the same name". Names starting with `_` and `self` may be reused. Bindings of one scope and the
 * parameters among themselves are not compared. */
#ifndef MS_COMPILER_CHECK_SHADOW_H
#define MS_COMPILER_CHECK_SHADOW_H

#include "compiler/check/program.h"

void ms_check_shadowing(MsCheckProgram *program, uint32_t module);

#endif

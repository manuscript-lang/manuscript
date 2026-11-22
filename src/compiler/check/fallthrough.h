/* compiler/check/fallthrough.h: the reachable-fallthrough pass.
 *
 * A function whose result is not Void (or Void!) must end every path with `return`. The walk follows the
 * statement rules of the oracle: return, break and continue do not fall through; an `if` falls through when
 * either branch does; a `while true` only when its body breaks; a match when an arm does. A call statement may
 * be a call that never returns, which the pass cannot tell before call resolution, so a path through one is
 * "maybe" and is not reported. */
#ifndef MS_COMPILER_CHECK_FALLTHROUGH_H
#define MS_COMPILER_CHECK_FALLTHROUGH_H

#include "compiler/check/program.h"

/* Reports `decl` when it is a function of a user module whose body can fall off its end, in the type phase. Runs
 * right after the declaration's body is checked, so the diagnostics come in the oracle's order. */
void ms_check_fallthrough(MsCheckProgram *program, uint32_t module, const MsDecl *decl);

/* Printing of a written result type (fallthrough_type.c); false when its display is not certain yet. */
bool ms_fall_type_text(const MsCheckProgram *program, uint32_t module, const MsFunc *func, const MsTypeRef *type,
                       MsStrBuild *out);

/* True for `Void` and `Void!`, which may end without a `return`. */
bool ms_fall_is_unit(const MsCheckProgram *program, const MsTypeRef *type);

#endif

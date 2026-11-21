/* compiler/check/mutate_fix.h: the edit that turns an immutable binding into a `var` one. */
#ifndef MS_COMPILER_CHECK_MUTATE_FIX_H
#define MS_COMPILER_CHECK_MUTATE_FIX_H

#include "base/strbuild.h"
#include "compiler/syntax/pos.h"

typedef struct MsVarFix {
  MsPos pos, end;
  MsString replacement; /* owned */
} MsVarFix;

/* The edit rewriting the binding `name := v` or `name: T := v` declared at `decl` into the `var` form; a
 * parameter `x: T` only gains `var`. False unless the source reads a plain name there, so patterns and loop
 * variables get no edit. */
bool ms_var_fix(MsSpan source, MsPos decl, MsVarFix *fix);

#endif

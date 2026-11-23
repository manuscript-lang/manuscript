/* compiler/own/expr_text.h: how a diagnostic names an expression: a name, a field path, a call as `f(..)`, an element as
 * `xs[..]`, and `this value` for anything else. */
#ifndef MS_COMPILER_OWN_EXPR_TEXT_H
#define MS_COMPILER_OWN_EXPR_TEXT_H

#include "base/strbuild.h"
#include "compiler/syntax/ast.h"

void ms_own_expr_text(MsStrBuild *out, const MsNames *names, const MsExpr *expr);

#endif

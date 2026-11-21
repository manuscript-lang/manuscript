/* syntax/format.h: the source formatter, the port of crates/ms-syntax/src/format.rs. */
#ifndef MS_SYNTAX_FORMAT_H
#define MS_SYNTAX_FORMAT_H

#include "base/strbuild.h"
#include "compiler/syntax/pos.h"

/* Formats `source` (UTF-8, any line ends). On success appends the formatted text to `out` and returns true.
 * Invalid syntax never produces output: the first syntax error fills *diag, with its message allocated in
 * `arena`, and the function returns false. */
bool ms_format(MsArena *arena, MsSpan source, MsStrBuild *out, MsDiag *diag);

#endif

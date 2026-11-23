/* tooling/snippet.h: the source excerpt printed under a terminal diagnostic: the offending line with a caret
 * underline beneath its span, as crates/ms-cli/src/snippet.rs prints it. */
#ifndef MS_CLI_SNIPPET_H
#define MS_CLI_SNIPPET_H

#include "base/strbuild.h"
#include "compiler/syntax/pos.h"

/* Appends the excerpt for the span `pos` (to `end` when `has_end`) of `source`: a newline, then the gutter, the
 * line and the carets, with no final newline. Appends nothing when the line does not exist. */
void ms_snippet_excerpt(MsStrBuild *out, MsSpan source, MsPos pos, bool has_end, MsPos end);

#endif

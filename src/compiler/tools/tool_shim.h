/* The entry points Manuscript tools call over libms with `extern fn` (see src/compiler/README.md).
 * Strings cross as `ms_str`, per crates/ms-rt-abi/include/ms_abi.h. */
#ifndef MS_TOOL_SHIM_H
#define MS_TOOL_SHIM_H

#include "ms_abi.h"

/* Writes to `out` the canonical syntax-tree dump of `text` (what `ms_syntax_dump ast` prints below the
 * file header), or the one-line "error ..." diagnostic when it does not parse. `out` is left empty
 * when `text` is not valid UTF-8. `path` is only recorded in positions. All three are borrowed. */
void ms_tool_syntax_dump(const ms_str *path, const ms_str *text, ms_str *out);

#endif

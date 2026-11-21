/* Documentation comments: the `//` lines and block comments above a declaration, and the effect
 * directives among them. Port of crates/ms-syntax/src/doc.rs and the comment lookups of
 * crates/ms-tooling/src/guide/source.rs. Offsets are byte offsets into `source`. */
#ifndef MS_DOC_H
#define MS_DOC_H

#include "ms/base.h"

/* The columns of leading whitespace in `line`, a tab counting four. */
size_t ms_doc_indent_columns(MsStr line);

/* The comment text of the declaration whose name starts at `offset`: the comments directly above its
 * line (at its indentation), else a trailing `//` on the line. Appended to `out`; markers are removed
 * and the text is otherwise preserved. A name after other tokens on its line (a payload field, a
 * parameter) has none. */
void ms_doc_leading_comment(MsBuf *out, MsStr source, size_t offset);

/* The comment lines above `line_start` (the start of a line) to `out`; when `has_indent`, only those
 * at column `indent`. */
void ms_doc_comments_above(MsBuf *out, MsStr source, size_t line_start, bool has_indent, size_t indent);

/* The names on `// ms: effect NAME` lines in the comment block above the declaration at `offset`, in
 * source order, as slices of `source`; returns how many there are, writing at most `max`. */
/* The length of the text literal that starts at `s[0]` (`"` or `f"`), or 0 when it is not closed. */
size_t ms_doc_text_end(MsStr s);

size_t ms_doc_effect_lines(MsStr source, size_t offset, MsStr *names, size_t max);

/* Whether a `// ms: MARKER` line is in the comment block above the declaration at `offset`: a bundled
 * declaration states a property there that has nothing else to be written as. */
bool ms_doc_has_marker(MsStr source, size_t offset, const char *marker);

#endif

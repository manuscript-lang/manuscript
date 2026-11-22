/* tooling/doc_comment.h: the doc comments of a declaration: the `//` lines and block comments directly above it, or a
 * trailing `//` on its line. Port of crates/ms-syntax/src/doc.rs and the leading_comment helpers of
 * crates/ms-tooling/src/guide/source.rs. Texts live in the arena. */
#ifndef MS_TOOLING_DOC_COMMENT_H
#define MS_TOOLING_DOC_COMMENT_H

#include "tooling/avec.h"

/* The comment text above the declaration containing `offset`, or empty. */
MsSpan ms_leading_comment(MsArena *arena, MsSpan source, size_t offset);

/* The names on `// ms: effect NAME` lines in the comment block directly above the declaration at `offset`. */
void ms_declared_effects(MsArena *arena, MsSpan source, size_t offset, MsSpans *out);

/* The documentation of the declaration that starts at `offset` (on `line`, 1-based): the comment block directly above its line
 * at any indentation, else its trailing comment; trimmed. */
MsSpan ms_declaration_comment(MsArena *arena, MsSpan source, size_t offset, uint32_t line);

#endif

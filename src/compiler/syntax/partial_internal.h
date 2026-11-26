/* syntax/partial_internal.h: what the editor-recovery parser's files share. Private to the syntax library. */
#ifndef MS_SYNTAX_PARTIAL_INTERNAL_H
#define MS_SYNTAX_PARTIAL_INTERNAL_H

#include "base/list.h"
#include "compiler/syntax/parse.h"

MS_LIST_DEFINE(DiagList, diag_list, MsDiag)

typedef struct Partial {
  MsArena *arena;
  MsNames *names;
} Partial;

/* ---- text helpers shared by the files ---- */

MsSpan partial_trim(MsSpan text);
MsSpan partial_trim_end(MsSpan text);
size_t partial_leading_space(MsSpan line);

/* ---- declaration starts ---- */

/* Whether a column-zero line starts an independent recovery declaration. */
bool partial_is_declaration_line(MsSpan line);
/* Whether a column-zero line can start a chunk at all: not indented, blank or a comment. */
bool partial_is_candidate_line(MsSpan line);
/* Whether `source` begins with a declaration start, by token boundary. */
bool partial_root_start(MsSpan source);
/* Whether a parsed chunk holds the nodes of one written root. */
bool partial_single_root(const MsModule *module);

/* ---- statement recovery ---- */

/* Retries a failed chunk with each offending statement blanked; on success `*out` is the text to parse and
 * the diagnostics of the blanked statements are appended to `issues`. */
bool partial_recover_statements(Partial *partial, MsSpan chunk, MsChunk where, const MsDiag *first,
                                MsSpan *out, DiagList *issues);

#endif

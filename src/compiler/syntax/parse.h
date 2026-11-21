/* syntax/parse.h: the strict parser. */
#ifndef MS_SYNTAX_PARSE_H
#define MS_SYNTAX_PARSE_H

#include "compiler/syntax/ast.h"
#include "compiler/syntax/lex.h"

enum { MS_MAX_NESTING = 1000, MS_MAX_CHAIN = 10000 };

/* The member name of an index assignment; no source name can spell it. */
#define MS_INDEX_SET "[]="

/* Whether `call` is an index assignment, `place[key] = value` written as `place.[]=(key, value)`. */
bool ms_is_index_store(const MsNames *names, const MsExpr *call);

/* Whether `left[index] op= value` is accepted: both parts can be evaluated twice without effect. */
bool ms_plain_index_target(const MsExpr *left, const MsExpr *index);

/* Parses a whole file strictly: the first error aborts the parse, fills *diag and returns false. Nodes and
 * texts come from `arena`; names are interned in `names`. */
bool ms_parse(MsArena *arena, MsNames *names, MsSpan source, MsModule *module, MsDiag *diag);

/* Where a slice of a larger file sits: its first byte is at original offset `base_offset` on line
 * `base_line + 1`, and its nodes are numbered from `first_id`. */
typedef struct MsChunk {
  uint32_t base_offset, base_line, first_id;
} MsChunk;

/* Parses a slice of a larger file strictly, reporting positions in the larger file. Editor recovery only. */
bool ms_parse_chunk(MsArena *arena, MsNames *names, MsSpan source, MsChunk chunk, MsModule *module,
                    MsDiag *diag);

/* Parses `source` retaining every declaration that parses on its own (or after blanking invalid statements). True when the
 * whole file parses; otherwise `module` holds what was kept and `diags` the problems of the rest, from `arena`. */
bool ms_parse_partial(MsArena *arena, MsNames *names, MsSpan source, MsModule *module, MsDiag **diags,
                      size_t *ndiags);

#endif

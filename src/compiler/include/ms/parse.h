#ifndef MS_PARSE_H
#define MS_PARSE_H

#include "ms/ast.h"
#include "ms/base.h"

#define MS_MAX_NESTING 1000
#define MS_MAX_CHAIN 10000

/* The member name of an index assignment; no source name can spell it. */
#define MS_INDEX_SET "[]="
/* Whether `call` is an index assignment, `place[key] = value` written as `place.[]=(key, value)`. */
bool ms_is_index_store(const MsNames *names, const MsExpr *call);
/* Whether `left[index] op= value` is accepted: both parts can be evaluated twice without effect. */
bool ms_plain_index_target(const MsExpr *left, const MsExpr *index);

/* Parses a whole file strictly: the first error aborts the parse, fills *diag and returns false.
 * Nodes and texts come from `arena`; names are interned in `names`. */
bool ms_parse(MsArena *arena, MsNames *names, const char *src, size_t len, MsModule *module,
              MsDiag *diag);

/* Parses a slice of a larger file whose first byte is at original offset base_offset on line
 * base_line + 1, numbering nodes from first_id. Used by editor recovery. */
bool ms_parse_chunk(MsArena *arena, MsNames *names, const char *src, size_t len, uint32_t base_offset,
                    uint32_t base_line, uint32_t first_id, MsModule *out, MsDiag *diag);

typedef struct MsDiagList {
    MsDiag *items;
    uint32_t len;
} MsDiagList;

/* Editor recovery: the module of every declaration that parsed (or parsed after blanking invalid
 * statements) and the diagnostics of everything that did not. A file that parses strictly yields
 * the same module and no diagnostics. */
void ms_parse_partial(MsArena *arena, MsNames *names, const char *src, size_t len, MsModule *module,
                      MsDiagList *diagnostics);

#endif

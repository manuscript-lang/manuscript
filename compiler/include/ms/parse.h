#ifndef MS_PARSE_H
#define MS_PARSE_H

#include "ms/ast.h"
#include "ms/base.h"

#define MS_MAX_NESTING 1000
#define MS_MAX_CHAIN 10000

/* Parses a whole file strictly: the first error aborts the parse, fills *diag and returns false.
 * Nodes and texts come from `arena`; names are interned in `names`. */
bool ms_parse(MsArena *arena, MsNames *names, const char *src, size_t len, MsModule *out,
              MsDiag *diag);

#endif

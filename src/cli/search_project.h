/* cli/search_project.h: the project half of `ms search_symbol`: the declarations of the project in the working
 * directory whose names match, with their type, documentation, effects and uses. */
#ifndef MS_CLI_SEARCH_PROJECT_H
#define MS_CLI_SEARCH_PROJECT_H

#include "base/arena.h"
#include "base/safe.h"
#include "tooling/avec.h"

typedef struct MsSymbolMatch {
  MsSpan name, kind, definition, type, doc, effects;
  MsSpans uses; /* `file:line:column` of each use, the definition left out; only a project match has them */
  size_t rank;
  bool project;
} MsSymbolMatch;

MS_AVEC(MsSymbolMatches, ms_symbol_matches, MsSymbolMatch)

/* How well `name` fits `query`: 0 exact, 1 prefix, 2 substring, 3 ordered subsequence, 4 near miss; -1 for no match. */
int ms_symbol_name_rank(MsArena *arena, MsSpan name, MsSpan query);

/* The best `limit` project declarations matching `query`, best first; `*total` counts every match. */
MsSymbolMatches ms_search_project(MsArena *arena, MsSpan query, size_t limit, size_t *total);

#endif

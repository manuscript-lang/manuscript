/* compiler/check/facts_build.h: filling a module's MsFacts (facts.h) while its bodies are checked. */
#ifndef MS_COMPILER_CHECK_FACTS_BUILD_H
#define MS_COMPILER_CHECK_FACTS_BUILD_H

#include "base/arena.h"
#include "compiler/check/facts.h"

/* Allocates the node columns of `facts` (all zero) from `arena` for a tree of `node_count` nodes. */
void ms_facts_init(MsFacts *facts, MsArena *arena, uint32_t module, uint32_t node_count);

/* Records one sparse fact; a later record for the same node replaces the earlier one at ms_facts_finish. */
void ms_facts_add_call(MsFacts *facts, const MsCall *call);
void ms_facts_add_conversion(MsFacts *facts, const MsConversion *conversion);

/* Sorts the sparse tables by node so the lookups can search them. */
void ms_facts_finish(MsFacts *facts);

#endif

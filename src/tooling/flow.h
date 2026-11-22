/* tooling/flow.h: one callable body as ordered significant steps: calls, branches, loops, match arms, try sites,
 * cleanup scopes and exits. Bindings and arithmetic are elided; labels are the source lines themselves.
 * Port of crates/ms-tooling/src/flow.rs. Internal to the fact model. */
#ifndef MS_TOOLING_FLOW_H
#define MS_TOOLING_FLOW_H

#include "tooling/facts.h"

typedef struct MsFlow {
  MsArena *arena;
  MsSpan file;
  const MsSpan *lines; /* the source lines of the module, without their line ends */
  size_t line_count;
  const MsInspection *inspection;
  const MsSpan *keys; /* the fact key of each inspection entity, in order */
  const MsFacts *facts; /* the checked facts of the module */
} MsFlow;

/* The steps of a statement list. */
void ms_flow_body(const MsFlow *flow, MsStmts body, MsViewNodes *out);

/* The steps of a module-level constant's initializer, a synthetic `return`. */
void ms_flow_constant(const MsFlow *flow, MsPos init_pos, const MsExpr *value, MsViewNodes *out);

/* Whether the binding with pattern `id` is closed where its scope ends. */
bool ms_flow_scoped(const MsFacts *facts, uint32_t pattern);

#endif

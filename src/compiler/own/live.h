/* compiler/own/live.h: backward liveness of local bindings, which uses are the last on every path.
 *
 * The ownership walk asks whether a move is the final use of a binding. A use is last when no later use of
 * the same value can run on any path: reassigning a binding ends the old value's life, a loop keeps reads
 * alive until the final iteration, and a closure's captured variables stay live to the end of the closure.
 * Liveness is kept per place, a binding and a path of fields: `uses` answers for the whole binding and
 * `places` for the place a field-path read names (is it, a prefix of it or an extension of it used later).
 *
 * Bindings are identified by the node id of their binding site (the `decl` of a MsRef). Results are keyed by
 * ms_live_key(node, binding).
 *
 * Ownership: MsLiveness owns its maps (ms_liveness_free); path arrays live in the arena given to compute. */
#ifndef MS_COMPILER_OWN_LIVE_H
#define MS_COMPILER_OWN_LIVE_H

#include "base/map.h"
#include "compiler/own/live_set.h"
#include "compiler/syntax/ast.h"

typedef struct MsUseLive {
  MsNode next; /* the earliest later use, or MS_NO_NODE */
  bool last;   /* no later use of the value can run */
} MsUseLive;

MS_MAP_DEFINE(MsLiveMap, ms_live_map, uint64_t, MsUseLive, ms_hash_u64_key, ms_equal_u64_key)
MS_MAP_DEFINE(MsNodeMap, ms_node_map, uint64_t, MsNode, ms_hash_u64_key, ms_equal_u64_key)

typedef struct MsLiveness {
  MsLiveMap uses;   /* name uses, and lambda creations for captures, by (node, binding) */
  MsLiveMap places; /* field-path reads by the outermost member node and the root binding */
  /* Lambda creations (node, captured binding) after which the binding is assigned again on some path, with
   * the node of the assigned value. */
  MsNodeMap assigned_after;
} MsLiveness;

static inline uint64_t ms_live_key(MsNode node, uint32_t binding) {
  return ((uint64_t)node << 32) | binding;
}

/* The liveness of a callable body. */
MsLiveness ms_live_compute(const MsFacts *facts, const MsNames *names, MsArena *arena, MsStmts body);

void ms_liveness_free(MsLiveness *liveness);

#endif

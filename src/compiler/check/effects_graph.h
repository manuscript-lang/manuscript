/* compiler/check/effects_graph.h: the dense graph behind effect propagation, shared by effects_reach.c and
 * effects_paths.c. */
#ifndef MS_COMPILER_CHECK_EFFECTS_GRAPH_H
#define MS_COMPILER_CHECK_EFFECTS_GRAPH_H

#include "base/map.h"
#include "compiler/check/effects_reach.h"

#define MS_REACH_NONE UINT32_MAX

MS_MAP_DEFINE(MsReachIndex, ms_reach_index, uint32_t, uint32_t, ms_hash_u32_key, ms_equal_u32_key)

/* A matrix of bits: one row per node, `words` 64-bit words each. Arena-owned. */
typedef struct MsBitRows {
  uint64_t *data;
  uint32_t words;
} MsBitRows;

static inline bool ms_bits_has(const MsBitRows *rows, uint32_t row, uint32_t bit) {
  return (rows->data[(size_t)row * rows->words + bit / 64] >> (bit % 64)) & 1;
}

static inline void ms_bits_set(MsBitRows *rows, uint32_t row, uint32_t bit) {
  rows->data[(size_t)row * rows->words + bit / 64] |= UINT64_C(1) << (bit % 64);
}

typedef struct MsReachGraph {
  const MsReachNode *nodes;
  uint32_t count;
  const MsSpan *names; /* the distinct declared effect names, sorted: a name's position is its bit */
  uint32_t name_count;
  MsReachIndex index;  /* owned: callable id -> node */
  MsBitRows declared;  /* the effects each node declares */
  MsBitRows inner;     /* the effects reaching each node from its callees */
  MsBitRows out;       /* the effects callers see */
} MsReachGraph;

/* The node a reference to `callee` names, or MS_REACH_NONE. */
static inline uint32_t ms_reach_target(const MsReachGraph *graph, MsName callee) {
  const uint32_t *found = ms_reach_index_get(&graph->index, callee);
  return found == NULL ? MS_REACH_NONE : *found;
}

/* The shortest chain of references from `start` to a node that declares effect `bit`, as node indices from
 * `start` to that node, ties broken by label; a lone `start` when none is found. Allocated in `arena`. */
uint32_t ms_reach_path(MsReachGraph *graph, uint32_t start, uint32_t bit, MsArena *arena,
                       const uint32_t **path);

/* Byte-wise order of two texts: negative when `a` sorts first. */
int64_t ms_span_order(MsSpan a, MsSpan b);

#endif

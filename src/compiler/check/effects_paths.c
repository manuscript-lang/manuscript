/* compiler/check/effects_paths.c: the shortest chain from a callable to the one that declares an effect. */
#include "base/sort.h"
#include "compiler/check/effects_graph.h"

int64_t ms_span_order(MsSpan a, MsSpan b) {
  const size_t shared = a.len < b.len ? a.len : b.len;
  for (size_t index = 0; index < shared; index++) {
    if (a.ptr[index] != b.ptr[index]) {
      return (int64_t)a.ptr[index] - (int64_t)b.ptr[index];
    }
  }
  return a.len < b.len ? -1 : (a.len > b.len ? 1 : 0);
}

static int64_t compare_by_label(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  const MsReachGraph *graph = (const MsReachGraph *)(void *)env;
  uint32_t left = 0;
  uint32_t right = 0;
  __builtin_memcpy(&left, a, sizeof left);
  __builtin_memcpy(&right, b, sizeof right);
  return ms_span_order(graph->nodes[left].label, graph->nodes[right].label);
}

/* Scratch for one search: who reached each node, and the queue. */
typedef struct Search {
  uint32_t *parent; /* MS_REACH_NONE until reached */
  uint32_t *queue;
  uint32_t *next; /* the callees to visit from the node being expanded */
} Search;

/* The callees of `at` that carry the effect, are not yet reached and are not the start, sorted by label. */
static uint32_t collect_next(MsReachGraph *graph, const Search *search, uint32_t at, uint32_t bit,
                             uint32_t start) {
  const MsReachNode *node = &graph->nodes[at];
  uint32_t count = 0;
  for (uint32_t edge = 0; edge < node->edge_count; edge++) {
    const uint32_t callee = ms_reach_target(graph, node->edges[edge].callee);
    if (callee != MS_REACH_NONE && ms_bits_has(&graph->out, callee, bit) && callee != start &&
        search->parent[callee] == MS_REACH_NONE) {
      search->next[count++] = callee;
    }
  }
  ms_sort((uint8_t *)search->next, count, sizeof(uint32_t), compare_by_label, (uint8_t *)(void *)graph);
  return count;
}

static uint32_t build_path(const Search *search, uint32_t start, uint32_t found, MsArena *arena,
                           const uint32_t **path) {
  uint32_t length = 1;
  for (uint32_t at = found; at != start; at = search->parent[at]) {
    length++;
  }
  uint32_t *nodes = MS_ARENA_NEW_ARRAY(arena, uint32_t, length);
  uint32_t at = found;
  for (uint32_t index = length; index > 0; index--) {
    nodes[index - 1] = at;
    at = search->parent[at];
  }
  *path = nodes;
  return length;
}

uint32_t ms_reach_path(MsReachGraph *graph, uint32_t start, uint32_t bit, MsArena *arena,
                       const uint32_t **path) {
  Search search = {.parent = MS_ARENA_NEW_ARRAY(arena, uint32_t, graph->count),
                   .queue = MS_ARENA_NEW_ARRAY(arena, uint32_t, graph->count),
                   .next = MS_ARENA_NEW_ARRAY(arena, uint32_t, graph->count)};
  for (uint32_t index = 0; index < graph->count; index++) {
    search.parent[index] = MS_REACH_NONE;
  }
  uint32_t head = 0;
  uint32_t tail = 0;
  search.queue[tail++] = start;
  while (head < tail) {
    const uint32_t at = search.queue[head++];
    const uint32_t count = collect_next(graph, &search, at, bit, start);
    for (uint32_t index = 0; index < count; index++) {
      const uint32_t callee = search.next[index];
      if (search.parent[callee] != MS_REACH_NONE) {
        continue;
      }
      search.parent[callee] = at;
      if (ms_bits_has(&graph->declared, callee, bit)) {
        return build_path(&search, start, callee, arena, path);
      }
      search.queue[tail++] = callee;
    }
  }
  uint32_t *alone = MS_ARENA_NEW_ARRAY(arena, uint32_t, 1);
  alone[0] = start;
  *path = alone;
  return 1;
}

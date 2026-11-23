/* compiler/check/effects_reach.c: effect propagation over the callable graph and the unpermitted-reach
 * check. */
#include "base/sort.h"
#include "compiler/check/effects_directives.h"
#include "compiler/check/effects_graph.h"

/* The distinct declared effect names of all nodes, sorted. */
static uint32_t collect_names(const MsReachNode *nodes, uint32_t count, MsArena *arena, const MsSpan **names) {
  size_t total = 0;
  for (uint32_t index = 0; index < count; index++) {
    total += nodes[index].declared_count;
  }
  MsSpan *all = MS_ARENA_NEW_ARRAY(arena, MsSpan, total + 1);
  size_t filled = 0;
  for (uint32_t index = 0; index < count; index++) {
    for (uint32_t at = 0; at < nodes[index].declared_count; at++) {
      all[filled++] = nodes[index].declared[at];
    }
  }
  ms_sort((uint8_t *)all, filled, sizeof(MsSpan), ms_sort_compare_spans, NULL);
  size_t distinct = 0;
  for (size_t index = 0; index < filled; index++) {
    if (distinct == 0 || ms_span_compare(all[distinct - 1], all[index]) != 0) {
      all[distinct++] = all[index];
    }
  }
  *names = all;
  return (uint32_t)distinct;
}

static uint32_t slot_of(const MsReachGraph *graph, MsSpan name) {
  uint32_t low = 0;
  uint32_t high = graph->name_count;
  while (low < high) {
    const uint32_t middle = low + (high - low) / 2;
    const int64_t order = ms_span_compare(graph->names[middle], name);
    if (order == 0) {
      return middle;
    }
    if (order < 0) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return MS_REACH_NONE;
}

static MsBitRows new_rows(MsArena *arena, uint32_t count, uint32_t words) {
  return (MsBitRows){.data = MS_ARENA_NEW_ARRAY(arena, uint64_t, (size_t)count * words + 1), .words = words};
}

static bool row_any(const MsBitRows *rows, uint32_t row) {
  for (uint32_t word = 0; word < rows->words; word++) {
    if (rows->data[(size_t)row * rows->words + word] != 0) {
      return true;
    }
  }
  return false;
}

/* The callers of each node, as compressed rows: callers of node n are list[start[n] .. start[n + 1]). */
typedef struct Callers {
  uint32_t *start;
  uint32_t *list;
} Callers;

static Callers build_callers(const MsReachGraph *graph, MsArena *arena) {
  Callers callers = {.start = MS_ARENA_NEW_ARRAY(arena, uint32_t, (size_t)graph->count + 2)};
  size_t edges = 0;
  for (uint32_t node = 0; node < graph->count; node++) {
    for (uint32_t edge = 0; edge < graph->nodes[node].edge_count; edge++) {
      const uint32_t callee = ms_reach_target(graph, graph->nodes[node].edges[edge].callee);
      if (callee != MS_REACH_NONE) {
        callers.start[callee + 1]++;
        edges++;
      }
    }
  }
  for (uint32_t node = 0; node < graph->count; node++) {
    callers.start[node + 1] += callers.start[node];
  }
  callers.list = MS_ARENA_NEW_ARRAY(arena, uint32_t, edges + 1);
  uint32_t *fill = MS_ARENA_NEW_ARRAY(arena, uint32_t, (size_t)graph->count + 1);
  for (uint32_t node = 0; node < graph->count; node++) {
    for (uint32_t edge = 0; edge < graph->nodes[node].edge_count; edge++) {
      const uint32_t callee = ms_reach_target(graph, graph->nodes[node].edges[edge].callee);
      if (callee != MS_REACH_NONE) {
        callers.list[callers.start[callee] + fill[callee]++] = node;
      }
    }
  }
  return callers;
}

/* Hands the effects `callee` shows to one caller; true when the caller shows more than before. */
static bool pass_up(MsReachGraph *graph, uint32_t callee, uint32_t caller) {
  const bool keeps_own = row_any(&graph->declared, caller);
  const uint32_t words = graph->out.words;
  bool grew = false;
  for (uint32_t word = 0; word < words; word++) {
    const uint64_t incoming = graph->out.data[(size_t)callee * words + word];
    const uint64_t fresh = incoming & ~graph->inner.data[(size_t)caller * words + word];
    if (fresh == 0) {
      continue;
    }
    graph->inner.data[(size_t)caller * words + word] |= fresh;
    if (!keeps_own) {
      graph->out.data[(size_t)caller * words + word] |= fresh;
      grew = true;
    }
  }
  return grew;
}

static void propagate(MsReachGraph *graph, const Callers *callers, MsArena *arena) {
  uint32_t *work = MS_ARENA_NEW_ARRAY(arena, uint32_t, (size_t)graph->count + 1);
  bool *queued = MS_ARENA_NEW_ARRAY(arena, bool, (size_t)graph->count + 1);
  uint32_t top = 0;
  for (uint32_t node = 0; node < graph->count; node++) {
    if (row_any(&graph->declared, node)) {
      work[top++] = node;
      queued[node] = true;
    }
  }
  while (top > 0) {
    const uint32_t callee = work[--top];
    queued[callee] = false;
    for (uint32_t at = callers->start[callee]; at < callers->start[callee + 1]; at++) {
      const uint32_t caller = callers->list[at];
      if (pass_up(graph, callee, caller) && !queued[caller]) {
        queued[caller] = true;
        work[top++] = caller;
      }
    }
  }
}

static bool permitted(const MsEffectScope *scope, MsSpan effect) {
  if (!scope->present) {
    return true;
  }
  for (uint32_t index = 0; index < scope->count; index++) {
    if (ms_effect_matches(scope->patterns[index], effect)) {
      return true;
    }
  }
  return false;
}

/* Whether the reach of `effect` into `node` is outside every scope that applies to it. */
static bool unpermitted(const MsReachNode *node, MsSpan effect) {
  if (!node->allow_fn.present && !node->allow_file.present) {
    return true;
  }
  return !(permitted(&node->cap, effect) && permitted(&node->allow_fn, effect) &&
           permitted(&node->allow_file, effect));
}

static MsEffectNames names_of_row(const MsReachGraph *graph, uint32_t row, MsArena *arena) {
  uint32_t total = 0;
  for (uint32_t bit = 0; bit < graph->name_count; bit++) {
    total += ms_bits_has(&graph->out, row, bit) ? 1 : 0;
  }
  MsSpan *names = MS_ARENA_NEW_ARRAY(arena, MsSpan, (size_t)total + 1);
  uint32_t filled = 0;
  for (uint32_t bit = 0; bit < graph->name_count; bit++) {
    if (ms_bits_has(&graph->out, row, bit)) {
      names[filled++] = graph->names[bit];
    }
  }
  return (MsEffectNames){.names = names, .count = total};
}

static MsPos reference_pos(const MsReachGraph *graph, uint32_t node, uint32_t first) {
  const MsReachNode *callable = &graph->nodes[node];
  for (uint32_t edge = 0; edge < callable->edge_count; edge++) {
    if (ms_reach_target(graph, callable->edges[edge].callee) == first) {
      return callable->edges[edge].pos;
    }
  }
  return callable->pos;
}

static MsReachViolation make_violation(MsReachGraph *graph, uint32_t node, uint32_t bit, MsArena *arena) {
  const uint32_t *path = NULL;
  const uint32_t length = ms_reach_path(graph, node, bit, arena, &path);
  MsSpan *labels = MS_ARENA_NEW_ARRAY(arena, MsSpan, length);
  for (uint32_t index = 0; index < length; index++) {
    labels[index] = graph->nodes[path[index]].label;
  }
  const uint32_t first = length > 1 ? path[1] : node;
  return (MsReachViolation){.file = graph->nodes[node].file,
                            .pos = reference_pos(graph, node, first),
                            .effect = graph->names[bit],
                            .path = labels,
                            .path_count = length};
}

/* The violations in node order, then effect order. */
static void find_violations(MsReachGraph *graph, MsArena *arena, MsReach *reach) {
  MsReachViolation *found = NULL;
  uint32_t count = 0;
  uint32_t capacity = 0;
  for (uint32_t node = 0; node < graph->count; node++) {
    const MsReachNode *callable = &graph->nodes[node];
    if (!callable->project || callable->entry) {
      continue;
    }
    for (uint32_t bit = 0; bit < graph->name_count; bit++) {
      if (!ms_bits_has(&graph->inner, node, bit) || !unpermitted(callable, graph->names[bit])) {
        continue;
      }
      if (count == capacity) {
        MsReachViolation *grown = MS_ARENA_NEW_ARRAY(arena, MsReachViolation, capacity == 0 ? 8 : capacity * 2);
        for (uint32_t index = 0; index < count; index++) {
          grown[index] = found[index];
        }
        found = grown;
        capacity = capacity == 0 ? 8 : capacity * 2;
      }
      found[count++] = make_violation(graph, node, bit, arena);
    }
  }
  reach->violations = found;
  reach->violation_count = count;
}

static MsReachGraph build_graph(const MsReachNode *nodes, uint32_t count, MsArena *arena) {
  MsReachGraph graph = {.nodes = nodes, .count = count};
  graph.name_count = collect_names(nodes, count, arena, &graph.names);
  const uint32_t words = (graph.name_count + 63) / 64;
  graph.declared = new_rows(arena, count, words);
  graph.inner = new_rows(arena, count, words);
  graph.out = new_rows(arena, count, words);
  for (uint32_t node = 0; node < count; node++) {
    ms_reach_index_put(&graph.index, nodes[node].id, node);
    for (uint32_t at = 0; at < nodes[node].declared_count; at++) {
      const uint32_t bit = slot_of(&graph, nodes[node].declared[at]);
      ms_bits_set(&graph.declared, node, bit);
      ms_bits_set(&graph.out, node, bit);
    }
  }
  return graph;
}

MsReach ms_effects_resolve(const MsReachNode *nodes, uint32_t count, MsArena *arena) {
  MsReach reach = {0};
  reach.declared = MS_ARENA_NEW_ARRAY(arena, MsEffectNames, (size_t)count + 1);
  reach.permits = MS_ARENA_NEW_ARRAY(arena, MsEffectNames, (size_t)count + 1);
  for (uint32_t node = 0; node < count; node++) {
    const MsEffectScope *scope = nodes[node].allow_fn.present ? &nodes[node].allow_fn
                                 : nodes[node].allow_file.present ? &nodes[node].allow_file : NULL;
    if (nodes[node].project && scope != NULL) {
      reach.permits[node] = (MsEffectNames){.names = scope->patterns, .count = scope->count};
    }
  }
  MsReachGraph graph = build_graph(nodes, count, arena);
  if (graph.name_count == 0) {
    ms_reach_index_free(&graph.index);
    return reach;
  }
  const Callers callers = build_callers(&graph, arena);
  propagate(&graph, &callers, arena);
  for (uint32_t node = 0; node < count; node++) {
    reach.declared[node] = names_of_row(&graph, node, arena);
  }
  find_violations(&graph, arena, &reach);
  ms_reach_index_free(&graph.index);
  return reach;
}

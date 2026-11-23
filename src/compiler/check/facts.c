/* compiler/check/facts.c: building and reading a module's facts (see facts.h and facts_build.h). */
#include "compiler/check/facts_build.h"

#include "base/sort.h"

void ms_facts_init(MsFacts *facts, MsArena *arena, uint32_t module, uint32_t node_count) {
  *facts = (MsFacts){.module = module, .node_count = node_count};
  if (node_count == 0) {
    return;
  }
  facts->types = MS_ARENA_NEW_ARRAY(arena, MsTy, node_count);
  facts->refs = MS_ARENA_NEW_ARRAY(arena, MsRef, node_count);
  facts->uses = MS_ARENA_NEW_ARRAY(arena, uint8_t, node_count);
  facts->last = MS_ARENA_NEW_ARRAY(arena, uint8_t, node_count);
  facts->local_counts = MS_ARENA_NEW_ARRAY(arena, uint32_t, node_count);
  facts->taken = MS_ARENA_NEW_ARRAY(arena, uint32_t, node_count);
  facts->result_borrows = MS_ARENA_NEW_ARRAY(arena, uint32_t, node_count);
}

void ms_facts_add_call(MsFacts *facts, const MsCall *call) {
  ms_call_list_push(&facts->calls, *call);
}

void ms_facts_add_conversion(MsFacts *facts, const MsConversion *conversion) {
  ms_conversion_list_push(&facts->conversions, *conversion);
}

void ms_facts_add_constant(MsFacts *facts, const MsConstant *constant) {
  ms_constant_list_push(&facts->constants, *constant);
}

static int64_t by_node(uint32_t left, uint32_t right) {
  return left < right ? -1 : left > right;
}

static int64_t compare_calls(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  return by_node(((const MsCall *)(const void *)a)->node, ((const MsCall *)(const void *)b)->node);
}

static int64_t compare_conversions(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  return by_node(((const MsConversion *)(const void *)a)->node, ((const MsConversion *)(const void *)b)->node);
}

static int64_t compare_constants(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  return by_node(((const MsConstant *)(const void *)a)->node, ((const MsConstant *)(const void *)b)->node);
}

void ms_facts_finish(MsFacts *facts) {
  ms_sort((uint8_t *)(void *)facts->calls.ptr, facts->calls.len, sizeof(MsCall), compare_calls, NULL);
  size_t kept = 0; /* a call recorded again (its expression read a second time) keeps its last record */
  for (size_t at = 0; at < facts->calls.len; at++) {
    if (at + 1 < facts->calls.len && facts->calls.ptr[at + 1].node == facts->calls.ptr[at].node) {
      continue;
    }
    facts->calls.ptr[kept++] = facts->calls.ptr[at];
  }
  facts->calls.len = kept;
  ms_sort((uint8_t *)(void *)facts->conversions.ptr, facts->conversions.len, sizeof(MsConversion),
          compare_conversions, NULL);
  ms_sort((uint8_t *)(void *)facts->constants.ptr, facts->constants.len, sizeof(MsConstant), compare_constants,
          NULL);
}

/* The last entry for `node` in a table sorted by node (a later record replaces an earlier one). */
#define FIND_BY_NODE(list, node)                                                                             \
  do {                                                                                                       \
    size_t lo = 0;                                                                                           \
    size_t hi = (list)->len;                                                                                 \
    while (lo < hi) {                                                                                        \
      const size_t mid = lo + (hi - lo) / 2;                                                                 \
      if ((list)->ptr[mid].node <= (node)) {                                                                 \
        lo = mid + 1;                                                                                        \
      } else {                                                                                               \
        hi = mid;                                                                                            \
      }                                                                                                      \
    }                                                                                                        \
    return lo > 0 && (list)->ptr[lo - 1].node == (node) ? &(list)->ptr[lo - 1] : NULL;                     \
  } while (0)

const MsCall *ms_facts_call(const MsFacts *facts, MsNode node) {
  FIND_BY_NODE(&facts->calls, node);
}

const MsConversion *ms_facts_conversion(const MsFacts *facts, MsNode node) {
  FIND_BY_NODE(&facts->conversions, node);
}

const MsConstant *ms_facts_constant(const MsFacts *facts, MsNode node) {
  FIND_BY_NODE(&facts->constants, node);
}

const MsCloser *ms_facts_closer(const MsFacts *facts, MsNode node) {
  FIND_BY_NODE(&facts->closers, node);
}

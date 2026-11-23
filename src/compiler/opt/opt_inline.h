/* Shared by opt_inline.c (calls, call graph, dead functions) and opt_inline_closure.c (closures,
 * specialisation): the size thresholds, the call graph and the inliner both halves of the
 * `inline` port use. */
#ifndef MS_COMPILER_OPT_OPT_INLINE_H
#define MS_COMPILER_OPT_OPT_INLINE_H

#include "compiler/opt/opt_util.h"
#include "compiler/opt/opt_pass.h"

/* Instruction count up to which an `Auto` callee is inlined. */
#define OPT_INLINE_BASE_THRESHOLD 60u
/* The same for a compact build (Debug): most of the module size LLVM then compiles comes from inlined copies. */
#define OPT_INLINE_COMPACT_THRESHOLD 15u
/* Cap on growth of one caller, as a multiple of its original size plus the slack. */
#define OPT_INLINE_GROWTH_FACTOR 4u
#define OPT_INLINE_GROWTH_SLACK 200u
/* Largest callee copied by closure-argument specialisation, and the instructions the whole module
 * may gain from it. */
#define OPT_INLINE_SPECIALIZE_MAX_SIZE 400u
#define OPT_INLINE_SPECIALIZE_BUDGET 2000u

/* A directed graph over `n` nodes in compressed rows. A node flagged `indirect` also has an edge
 * to every one of `itargets`, after its own. */
typedef struct OptInlineGraph {
  uint32_t n;
  uint32_t *off; /* n + 1 row starts into `to` */
  uint32_t *to;
  const bool *indirect; /* or NULL */
  const uint32_t *itargets;
  uint32_t nit;
} OptInlineGraph;

uint32_t opt_inline_degree(const OptInlineGraph *g, uint32_t v);
uint32_t opt_inline_edge(const OptInlineGraph *g, uint32_t v, uint32_t k);
/* The direct-call graph of the module (`call` only). */
OptInlineGraph opt_inline_direct_graph(MsArena *arena, const MirModule *m);
/* Per node: whether it lies on a cycle. */
bool *opt_inline_cyclic(MsArena *arena, const OptInlineGraph *g);
/* Per block: whether it lies on a cycle of the control-flow graph. */
bool *opt_blocks_in_loops(MsArena *arena, const MirFunc *f);

/* Whether inlining `callee` into `caller` would mix explicit-cancel states unsoundly. */
bool opt_inline_cancel_mismatch(const MirFunc *caller, const MirFunc *callee);
/* Replaces the call at instruction `ii` of block `bi` with a copy of `callee`; returns the
 * continuation block holding everything after the call. */
uint32_t opt_inline_at(MirModule *m, MirFunc *f, uint32_t bi, uint32_t ii, const MirFunc *callee,
           bool ret_own);
/* opt_inline_dead.c: removes the functions no root can reach; whether it removed any. */
bool opt_inline_remove_dead(MirModule *m);
bool opt_inline_specialize_sort_thunks(MirModule *m);
bool opt_inline_specialize_closure_args(MirModule *m);
bool opt_inline_closures(MirModule *m);

#endif

/* Shared by opt_inline.c (calls, call graph, dead functions) and opt_inline_closure.c (closures,
 * specialisation): the size thresholds, the call graph and the inliner both halves of the
 * `inline` port use. */
#ifndef MS_OPT_INLINE_H
#define MS_OPT_INLINE_H

#include "ms/mir_analysis.h"
#include "ms/mir_opt.h"

/* Instruction count up to which an `Auto` callee is inlined. */
#define MIR_INLINE_BASE_THRESHOLD 60u
/* Cap on growth of one caller, as a multiple of its original size plus the slack. */
#define MIR_INLINE_GROWTH_FACTOR 4u
#define MIR_INLINE_GROWTH_SLACK 200u
/* Largest callee copied by closure-argument specialisation, and the instructions the whole module
 * may gain from it. */
#define MIR_INLINE_SPECIALIZE_MAX_SIZE 400u
#define MIR_INLINE_SPECIALIZE_BUDGET 2000u

/* A directed graph over `n` nodes in compressed rows. A node flagged `indirect` also has an edge
 * to every one of `itargets`, after its own. */
typedef struct MirInlineGraph {
    uint32_t n;
    uint32_t *off; /* n + 1 row starts into `to` */
    uint32_t *to;
    const bool *indirect; /* or NULL */
    const uint32_t *itargets;
    uint32_t nit;
} MirInlineGraph;

uint32_t mir_inline_degree(const MirInlineGraph *g, uint32_t v);
uint32_t mir_inline_edge(const MirInlineGraph *g, uint32_t v, uint32_t k);
/* The direct-call graph of the module (`call` only). */
MirInlineGraph mir_inline_direct_graph(MsArena *arena, const MirModule *m);
/* Per node: whether it lies on a cycle. */
bool *mir_inline_cyclic(MsArena *arena, const MirInlineGraph *g);
/* Per block: whether it lies on a cycle of the control-flow graph. */
bool *mir_blocks_in_loops(MsArena *arena, const MirFunc *f);

/* Whether inlining `callee` into `caller` would mix explicit-cancel states unsoundly. */
bool mir_inline_cancel_mismatch(const MirFunc *caller, const MirFunc *callee);
/* A copy of `f` that shares nothing mutable with it. */
void mir_func_deep_clone(MirModule *m, const MirFunc *f, MirFunc *out);
/* Replaces the call at instruction `ii` of block `bi` with a copy of `callee`; returns the
 * continuation block holding everything after the call. */
uint32_t mir_inline_at(MirModule *m, MirFunc *f, uint32_t bi, uint32_t ii, const MirFunc *callee,
                       bool ret_own);
bool mir_inline_specialize_sort_thunks(MirModule *m);
bool mir_inline_specialize_closure_args(MirModule *m);
bool mir_inline_closures(MirModule *m);

#endif

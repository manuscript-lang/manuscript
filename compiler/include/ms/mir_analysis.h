/* libms MIR analysis: the facts every pass and the verifier read about a function. A port of the
 * helpers in crates/ms-mir (`verify.rs`: arg_modes, dominators; `ir.rs`: result_mode, result_views,
 * predecessors, rpo, Term iteration). Nothing here allocates except into an arena the caller
 * passes, so a pass keeps its scratch in one arena and drops it whole. */
#ifndef MS_MIR_ANALYSIS_H
#define MS_MIR_ANALYSIS_H

#include "ms/mir.h"

/* ---- ownership modes ---- */

/* Whether `inst` has an owned result, and how the result is held: a borrow of something that
 * outlives it, or an owned value (`MM_MOVE`). False when there is no result or it needs no drop. */
bool mir_result_mode(const MirModule *m, const MirFunc *f, const MirInst *inst, MirMode *mode);

/* Writes how each of the `inst->nargs` arguments is taken (`MM_MOVE` for an owned position) to
 * `out`, which has room for that many entries. */
void mir_arg_modes(const MirModule *m, const MirFunc *f, const MirInst *inst, MirMode *out);

/* The arguments a `call.ind` (from the closure's type) or `call.method` (from the interface
 * method) passes owned, as a bit set (see `mir_owns`). */
uint64_t mir_indirect_owned(const MirModule *m, const MirFunc *f, const MirInst *inst);

/* Whether the owned result of `inst` points into its operands (an interface view, a call to a
 * view returner, a borrowing variant). Passes that move drops treat it as a borrow. */
bool mir_result_views(const MirModule *m, const MirFunc *f, const MirInst *inst);

/* ---- terminators ---- */

/* The number of successor targets, in order: BR 1, CONDBR 2, SWITCH cases then the default. */
uint32_t mir_term_ntargets(const MirTerm *t);
MirTarget *mir_term_target(MirTerm *t, uint32_t index); /* borrowed from `t`; index < ntargets */
const MirTarget *mir_term_target_const(const MirTerm *t, uint32_t index);

/* Calls `fn(ctx, &value)` for every value operand of the terminator (condition, scrutinee, return
 * value, then block arguments of each target), so `fn` may rewrite it. */
typedef void (*MirUseFn)(void *ctx, MirValue *value);
void mir_term_each_use(MirTerm *t, MirUseFn fn, void *ctx);

/* ---- control flow ---- */

/* Predecessor lists in one array: block b's predecessors are `list[start[b]..start[b + 1]]`, in
 * block order, without duplicates. */
typedef struct MirPreds {
    const uint32_t *start; /* nblocks + 1 entries */
    const MirBlock *list;
} MirPreds;

static inline uint32_t mir_preds_count(const MirPreds *p, MirBlock b) {
    return p->start[b + 1] - p->start[b];
}
static inline MirBlock mir_pred(const MirPreds *p, MirBlock b, uint32_t i) {
    return p->list[p->start[b] + i];
}

/* Builds the predecessor lists of `f` in `arena`. */
MirPreds mir_preds(MsArena *arena, const MirFunc *f);

/* Reachable blocks in reverse post-order from the entry (the walk visits the last successor of a
 * terminator first). Returns the count; `*order` is in `arena`. */
uint32_t mir_rpo(MsArena *arena, const MirFunc *f, MirBlock **order);

/* The immediate dominator of every block (`MIR_NONE` when unreachable; the entry's is itself).
 * `order` is `mir_rpo`'s result of `count` blocks. */
MirBlock *mir_dominators(MsArena *arena, const MirFunc *f, const MirBlock *order, uint32_t count,
                         const MirPreds *preds);

/* ---- value sets ---- */

typedef struct MirBits {
    uint64_t *words; /* in the arena it was made in */
    uint32_t nbits;
} MirBits;

MirBits mir_bits_new(MsArena *arena, uint32_t nbits); /* all clear */
static inline bool mir_bits_test(const MirBits *s, uint32_t i) {
    return i < s->nbits && (s->words[i >> 6] >> (i & 63) & 1) != 0;
}
static inline void mir_bits_set(MirBits *s, uint32_t i) {
    if (i < s->nbits) {
        s->words[i >> 6] |= UINT64_C(1) << (i & 63);
    }
}
static inline void mir_bits_clear(MirBits *s, uint32_t i) {
    if (i < s->nbits) {
        s->words[i >> 6] &= ~(UINT64_C(1) << (i & 63));
    }
}

/* ---- editing ---- */

/* Inserts `inst` before position `at` of `block` (`at == ninsts` appends). */
void mir_block_insert(MirModule *m, MirBlockData *block, uint32_t at, const MirInst *inst);

/* Removes the instructions at the (ascending) positions in `dead`. */
void mir_block_remove(MirBlockData *block, const uint32_t *dead, uint32_t ndead);

#endif

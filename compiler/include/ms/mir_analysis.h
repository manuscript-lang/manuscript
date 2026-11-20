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

/* The same walk for a reader: `fn(ctx, value)` gets each operand by value. */
typedef void (*MirValueFn)(void *ctx, MirValue value);
void mir_term_each_value(const MirTerm *t, MirValueFn fn, void *ctx);

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

/* The number of instructions in `f`, excluding terminators. */
uint32_t mir_inst_count(const MirFunc *f);

/* Use counts per value over the whole function: instruction operands, conditions and block
 * arguments. `nvalues + 1` entries, in `arena`. */
uint32_t *mir_use_counts(MsArena *arena, const MirFunc *f);

/* Whether `ty` is a number or a boolean, which are stored inline. */
bool mir_is_scalar(const MirModule *m, MirTy ty);

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

/* The values of `f` that hold an owned value: block parameters taken by move (the entry block's
 * only when `entry_params`) and results `mir_result_mode` calls owned. */
MirBits mir_owned_values(MsArena *arena, const MirModule *m, const MirFunc *f, bool entry_params);

/* ---- editing ---- */

/* The interned name `<base><suffix>` (`suffix` is `suffix_len` bytes). */
MsSym mir_name_suffixed(MirModule *m, MsSym base, const char *suffix, size_t suffix_len);

/* The id of a runtime function equal to `def` in name, result and parameter types, declaring it
 * when the module has none (`Module::add_extern`). `def`'s parameter array is copied. */
uint32_t mir_extern_intern(MirModule *m, const MirExtern *def);

/* Inserts `inst` before position `at` of `block` (`at == ninsts` appends). */
void mir_block_insert(MirModule *m, MirBlockData *block, uint32_t at, const MirInst *inst);

/* Copies `f` into `out`: its own arrays of values, blocks, parameters, instructions, scopes and names (the
 * operand arrays are shared, so a pass edits a clone only by replacing them). */
void mir_func_clone(MirModule *m, const MirFunc *f, MirFunc *out);

/* Removes unreachable blocks and renumbers the rest in reverse post-order. */
void mir_func_compact_blocks(MirFunc *f);

/* Where a pass inserts at the start of the entry block: after the recursion check
 * (`depth.enter`), which stays first. */
uint32_t mir_entry_insert_at(const MirFunc *f);

/* Removes the instructions at the (ascending) positions in `dead`. */
void mir_block_remove(MirBlockData *block, const uint32_t *dead, uint32_t ndead);

/* The values an integer of type `from` can take in the sized integer type `to`, for `inarrow.opt`:
 * its range, clamped to what a signed 64-bit register holds, and from zero up for a UInt64 source. */
void mir_narrow_range(const MirModule *m, MirTy from, MirTy to, int64_t *lo, int64_t *hi);
/* Whether `inst` is a checked integer operation whose result is a sized integer (Int8 to UInt32), and
 * its range. Such a result faults as out of range when it leaves it, whatever the 64-bit check said. */
bool mir_sized_result_range(const MirModule *m, const MirFunc *f, const MirInst *inst, int64_t *lo, int64_t *hi);

#endif

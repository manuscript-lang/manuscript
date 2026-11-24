/* compiler/mir/mir_analysis.h: the facts every pass and the verifier read about a function: ownership modes
 * of operands and results, terminator walks, predecessors, reverse post-order, dominators, value sets, and
 * block editing. Nothing here allocates except into an arena the caller passes, so a pass keeps its scratch in
 * one arena and drops it whole. */
#ifndef MS_COMPILER_MIR_MIR_ANALYSIS_H
#define MS_COMPILER_MIR_MIR_ANALYSIS_H

#include "compiler/mir/mir.h"

/* ---- ownership modes ---- */

/* Whether `inst` has an owned result, and how the result is held: a borrow of something that outlives it, or
 * an owned value (MM_MOVE). False when there is no result or it needs no drop. */
/* Whether the result of `inst` is a view of a value something else owns, for a result of any type. */
MS_NODISCARD MS_NONNULL bool mir_result_borrowed(const MirModule *module, const MirFunc *func, const MirInst *inst);
MS_NODISCARD MS_NONNULL bool mir_result_mode(const MirModule *module, const MirFunc *func, const MirInst *inst,
                                             MirMode *mode);

/* Writes how each of the `inst->nargs` arguments is taken (MM_MOVE for an owned position) to `out`, which has
 * room for that many entries. */
void mir_arg_modes(const MirModule *module, const MirFunc *func, const MirInst *inst, MirMode *out);

/* The arguments a `call.ind` (from the closure's type) or `call.method` (from the interface method) passes
 * owned, as a bit set (see mir_owns). */
uint64_t mir_indirect_owned(const MirModule *module, const MirFunc *func, const MirInst *inst);

/* Whether the owned result of `inst` points into its operands (an interface view, a call to a view returner,
 * a borrowing variant). Passes that move drops treat it as a borrow. */
bool mir_result_views(const MirModule *module, const MirFunc *func, const MirInst *inst);

/* ---- terminators ---- */

static inline const MirTarget *mir_term_target_const(const MirTerm *term, uint32_t index) {
  if (term->kind == MT_SWITCH && index < term->ncases) {
    return &term->cases[index].target;
  }
  if (term->kind == MT_SWITCH) {
    return &term->b; /* a switch keeps its default in `b`, even when it has no cases */
  }
  return index == 0 ? &term->a : &term->b;
}

/* Calls `visit(context, &value)` for every value operand of the terminator (condition, scrutinee, return
 * value, then block arguments of each target), so `visit` may rewrite it. */
typedef void (*MirUseFn)(void *context, MirValue *value);
void mir_term_each_use(MirTerm *term, MirUseFn visit, void *context);

/* The same walk for a reader: `visit(context, value)` gets each operand by value. */
typedef void (*MirValueFn)(void *context, MirValue value);
void mir_term_each_value(const MirTerm *term, MirValueFn visit, void *context);

/* ---- control flow ---- */

/* Predecessor lists in one array: block b's predecessors are `list[start[b]..start[b + 1]]`, in block order,
 * without duplicates. */
typedef struct MirPreds {
  const uint32_t *start; /* nblocks + 1 entries */
  const MirBlock *list;
} MirPreds;

static inline uint32_t mir_preds_count(const MirPreds *preds, MirBlock block) {
  return preds->start[block + 1] - preds->start[block];
}

static inline MirBlock mir_pred(const MirPreds *preds, MirBlock block, uint32_t index) {
  return preds->list[preds->start[block] + index];
}

/* Builds the predecessor lists of `func` in `arena`. */
MirPreds mir_preds(MsArena *arena, const MirFunc *func);

/* Reachable blocks in reverse post-order from the entry (the walk visits the last successor of a terminator
 * first). Returns the count; `*order` is in `arena`. */
uint32_t mir_rpo(MsArena *arena, const MirFunc *func, MirBlock **order);

/* The immediate dominator of every block (MIR_NONE when unreachable; the entry's is itself). `order` is
 * mir_rpo's result of `count` blocks. */
MirBlock *mir_dominators(MsArena *arena, const MirFunc *func, const MirBlock *order, uint32_t count,
                         const MirPreds *preds);

/* The number of instructions in `func`, excluding terminators. */
uint32_t mir_inst_count(const MirFunc *func);

/* Use counts per value over the whole function: instruction operands, conditions and block arguments.
 * `values + 1` entries, in `arena`. */
uint32_t *mir_use_counts(MsArena *arena, const MirFunc *func);

/* Whether `ty` is a number or a boolean, which are stored inline. */
bool mir_is_scalar(const MirModule *module, MirTy ty);

/* ---- value sets ---- */

typedef struct MirBits {
  uint64_t *words; /* in the arena it was made in */
  uint32_t nbits;
} MirBits;

MirBits mir_bits_new(MsArena *arena, uint32_t nbits); /* all clear */

static inline bool mir_bits_test(const MirBits *set, uint32_t index) {
  return index < set->nbits && ((set->words[index >> 6] >> (index & 63)) & 1) != 0;
}

static inline void mir_bits_set(MirBits *set, uint32_t index) {
  if (index < set->nbits) {
    set->words[index >> 6] |= UINT64_C(1) << (index & 63);
  }
}

static inline void mir_bits_clear(MirBits *set, uint32_t index) {
  if (index < set->nbits) {
    set->words[index >> 6] &= ~(UINT64_C(1) << (index & 63));
  }
}

/* The values of `func` that hold an owned value: block parameters taken by move (the entry block's only when
 * `entry_params`) and results mir_result_mode calls owned. */
MirBits mir_owned_values(MsArena *arena, const MirModule *module, const MirFunc *func, bool entry_params);

/* ---- ranges ---- */

/* The values an integer of type `from` can take in the sized integer type `to`, for `inarrow.opt`: its range,
 * clamped to what a signed 64-bit register holds, and from zero up for a UInt64 source. */
void mir_narrow_range(const MirModule *module, MirTy from, MirTy to, int64_t *lo, int64_t *hi);

/* Whether `inst` is a checked integer operation whose result is a sized integer (Int8 to UInt32), and its
 * range. Such a result faults as out of range when it leaves it, whatever the 64-bit check said. */
MS_NODISCARD MS_NONNULL bool mir_sized_result_range(const MirModule *module, const MirFunc *func,
                                                    const MirInst *inst, int64_t *lo, int64_t *hi);

/* ---- editing (mir_edit.c) ---- */

/* The interned name `<base><suffix>`. */
MsName mir_name_suffixed(MirModule *module, MsName base, MsSpan suffix);

/* The id of a runtime function equal to `def` in name, result and parameter types, declaring it when the
 * module has none. `def`'s parameter array is copied. */
uint32_t mir_extern_intern(MirModule *module, const MirExtern *def);

/* Inserts `inst` before position `at` of `block` (`at == insts.len` appends). */
void mir_block_insert(MirBlockData *block, uint32_t at, const MirInst *inst);

/* Removes the instructions at the (ascending) positions in `dead`. */
void mir_block_remove(MirBlockData *block, const uint32_t *dead, uint32_t ndead);

/* Copies `func` into `out`: its own lists of values, blocks, parameters, instructions, scopes and names (the
 * operand arrays are shared, so a pass edits a clone only by replacing them). */
void mir_func_clone(const MirFunc *func, MirFunc *out);

/* Releases the lists of a function that is not in a module (a clone, or one taken out of it). */
void mir_func_release(MirFunc *func);

/* Removes unreachable blocks and renumbers the rest in reverse post-order. */
void mir_func_compact_blocks(MirFunc *func);

/* Where a pass inserts at the start of the entry block: after the recursion check (`depth.enter`), which
 * stays first. */
uint32_t mir_entry_insert_at(const MirFunc *func);

#endif

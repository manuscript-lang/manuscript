/* Shared by the optimiser's passes: the value substitution, instruction vectors and the editing helpers. */
#ifndef MS_COMPILER_OPT_OPT_UTIL_H
#define MS_COMPILER_OPT_OPT_UTIL_H

#include "compiler/mir/mir_analysis.h"
#include "compiler/mir/mir_pass.h"
#include "compiler/opt/opt.h"

/* A substitution of values: `to[v]` is what `v` becomes, MIR_NONE when it stays. Values at or above `n` (made
 * after the table) are never substituted. */
typedef struct OptSubst {
  MirValue *to;
  uint32_t n, count;
} OptSubst;

OptSubst opt_subst_new(MsArena *arena, uint32_t nvalues);
void opt_subst_set(OptSubst *s, MirValue from, MirValue to);
void opt_subst_apply(MirFunc *f, OptSubst *s); /* rewrites every use */

static inline MirValue opt_subst_resolve(const OptSubst *s, MirValue v) {
  while (v < s->n && s->to[v] != MIR_NONE) {
    v = s->to[v];
  }
  return v;
}

/* A growable vector of instructions in a scratch arena. */
typedef struct OptInstVec {
  MirInst *v;
  uint32_t n, cap;
} OptInstVec;

void opt_inst_vec_push(MsArena *arena, OptInstVec *vec, const MirInst *inst);

/* A growable list of block or value ids in a scratch arena. */
typedef struct OptIdList {
  uint32_t *v;
  uint32_t n, cap;
} OptIdList;

void opt_id_push(MsArena *a, OptIdList *l, uint32_t x);

/* Makes `src[0..n]` the instructions of `b`. */
void opt_block_set_insts(MirBlockData *b, const MirInst *src, uint32_t n);
/* Appends `src[0..n]` to the instructions of `b`. */
void opt_block_append(MirBlockData *b, const MirInst *src, uint32_t n);

bool **opt_dead_flags(MsArena *arena, const MirFunc *f);
void opt_sweep_dead(MirFunc *f, bool *const *dead, MsArena *arena);

bool opt_imm_eq(const MirImm *a, const MirImm *b);
bool opt_op_commutative(uint8_t op, const MirImm *imm);
/* The target with its own copy of the arguments. */
MirTarget opt_target_clone(MirModule *m, const MirTarget *t);
bool opt_target_eq(const MirTarget *a, const MirTarget *b);
/* Replaces `t` with a branch to `target`. */
void opt_term_set_br(MirTerm *t, MirTarget target);
/* An instruction with a fresh operand array of `nargs` values. */
MirInst opt_inst_make(MirModule *m, MirOp op, const MirValue *args, uint32_t nargs, MirImm imm, MirValue res,
                      MirLoc loc);
/* A copy of `f` that shares nothing mutable with it: operand arrays and targets are copied too. */
void opt_func_deep_clone(MirModule *m, const MirFunc *f, MirFunc *out);

#endif

/* Shared by opt_simplify.c (folding and the small rewrites) and opt_simplify_cfg.c (control flow,
 * value numbering and map probes): the value substitution, instruction vectors and the editing
 * helpers both halves of the `simplify` port use. */
#ifndef MS_OPT_SIMPLIFY_H
#define MS_OPT_SIMPLIFY_H

#include <string.h>

#include "ms/mir_analysis.h"
#include "ms/mir_opt.h"

/* A substitution of values: `to[v]` is what `v` becomes, MIR_NONE when it stays. Values at or
 * above `n` (made after the table) are never substituted. */
typedef struct MirSubst {
    MirValue *to;
    uint32_t n, count;
} MirSubst;

MirSubst mir_subst_new(MsArena *arena, uint32_t nvalues);
void mir_subst_set(MirSubst *s, MirValue from, MirValue to);
void mir_subst_apply(MirFunc *f, MirSubst *s); /* rewrites every use */

static inline MirValue mir_subst_resolve(const MirSubst *s, MirValue v) {
    while (v < s->n && s->to[v] != MIR_NONE) {
        v = s->to[v];
    }
    return v;
}

/* A growable vector of instructions in a scratch arena. */
typedef struct MirInstVec {
    MirInst *v;
    uint32_t n, cap;
} MirInstVec;

void mir_inst_vec_push(MsArena *arena, MirInstVec *vec, const MirInst *inst);

/* Makes `src[0..n]` the instructions of `b`, in place when they fit. */
void mir_block_set_insts(MirModule *m, MirBlockData *b, const MirInst *src, uint32_t n);
/* Appends `src[0..n]` to the instructions of `b`. */
void mir_block_append(MirModule *m, MirBlockData *b, const MirInst *src, uint32_t n);

bool **mir_dead_flags(MsArena *arena, const MirFunc *f);
void mir_sweep_dead(MirFunc *f, bool *const *dead, MsArena *arena);

bool mir_imm_eq(const MirImm *a, const MirImm *b);
bool mir_op_commutative(uint8_t op, const MirImm *imm);
/* The target with its own copy of the arguments. */
MirTarget mir_target_clone(MirModule *m, const MirTarget *t);
bool mir_target_eq(const MirTarget *a, const MirTarget *b);
/* Replaces `t` with a branch to `target`. */
void mir_term_set_br(MirTerm *t, MirTarget target);
/* An instruction with a fresh operand array of `nargs` values. */
MirInst mir_inst_make(MirModule *m, MirOp op, const MirValue *args, uint32_t nargs, MirImm imm,
                      MirValue res, MirLoc loc);

/* opt_simplify_fold.c. */
bool mir_simplify_fold(MirModule *m, MirFunc *f);
bool mir_simplify_phis(MirModule *m, MirFunc *f);

/* opt_simplify_cfg.c. Each returns whether it changed the function. */
bool mir_simplify_branches(MirModule *m, MirFunc *f);
bool mir_simplify_cse(MirModule *m, MirFunc *f);
bool mir_simplify_map_probes(MirModule *m, MirFunc *f);
bool mir_simplify_fuse_contains(MirModule *m, MirFunc *f);

#endif

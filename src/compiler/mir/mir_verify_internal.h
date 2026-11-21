/* compiler/mir/mir_verify_internal.h: what mir_verify.c and mir_verify_own.c share. */
#ifndef MS_COMPILER_MIR_MIR_VERIFY_INTERNAL_H
#define MS_COMPILER_MIR_MIR_VERIFY_INTERNAL_H

#include "compiler/mir/mir_analysis.h"
#include "compiler/mir/mir_verify.h"

/* A sorted set of value ids without duplicates. */
typedef struct MvSet {
  uint32_t *ids;
  uint32_t count, cap;
} MvSet;

/* The verifier of one function. */
typedef struct Mv {
  MirVerifyErrors *errs;
  MirVerifyCx cx;
  MsArena scratch; /* the analyses and sets of this function */
  bool require_locs;
  uint32_t first; /* errs->errors.len when this function started */
} Mv;

static inline bool mv_clean(const Mv *v) {
  return v->errs->errors.len == v->first;
}

uint32_t mvs_lower_bound(const MvSet *s, uint32_t id);
bool mvs_has(const MvSet *s, uint32_t id);
void mvs_reserve(MsArena *arena, MvSet *s, uint32_t extra);
void mvs_add(MsArena *arena, MvSet *s, uint32_t id);
bool mvs_remove(MvSet *s, uint32_t id);
MvSet mvs_clone(MsArena *arena, const MvSet *s);
bool mvs_equal(const MvSet *a, const MvSet *b);
MsSpan mvs_difference_text(MsArena *arena, const MvSet *a, const MvSet *b);

void mv_err(Mv *v, MirBlock block, const char *fmt, ...);
const char *mv_op_name(const MirInst *in);
MirTy mv_ty(const Mv *v, MirValue x);
bool mv_rc(const Mv *v, MirValue x);
bool mv_is_raw(const MirFunc *f);
MirMode *mv_modes(Mv *v, const MirInst *in);

/* Closures that borrow their maker's frame must not outlive it (mir_verify_own.c). */
void mv_scoped_closures(Mv *v);
/* Linear ownership over the reachable blocks in reverse post-order. */
void mv_check_ownership(Mv *v, const MirBlock *rpo, uint32_t count);

#endif

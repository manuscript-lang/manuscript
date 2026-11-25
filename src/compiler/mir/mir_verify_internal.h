/* compiler/mir/mir_verify_internal.h: what mir_verify.c and mir_verify_own.c share. */
#ifndef MS_COMPILER_MIR_MIR_VERIFY_INTERNAL_H
#define MS_COMPILER_MIR_MIR_VERIFY_INTERNAL_H

#include "base/message.h"
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

void mv_err_(Mv *v, MirBlock block, const char *fmt, ...);
#define mv_err(v, block, ...) mv_err_((v), (block), MS_FMT_ARGS(__VA_ARGS__))
const char *mv_op_name(const MirInst *in);
MirTy mv_ty(const Mv *v, MirValue x);
bool mv_rc(const Mv *v, MirValue x);
MirMode *mv_modes(Mv *v, const MirInst *in);

/* Closures that borrow their maker's frame must not outlive it (mir_verify_own.c). */
void mv_scoped_closures(Mv *v);
/* Linear ownership over the reachable blocks in reverse post-order. */
void mv_check_ownership(Mv *v, const MirBlock *rpo, uint32_t count);

#endif

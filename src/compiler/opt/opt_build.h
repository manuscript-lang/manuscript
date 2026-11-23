/* Builder helpers for the passes that generate a function (appendfast, probe): an offset pointer, a
 * load at an offset, an unaligned load and a binary operation with a constant. */
#ifndef MS_COMPILER_OPT_OPT_BUILD_H
#define MS_COMPILER_OPT_OPT_BUILD_H

#include "compiler/mir/mir_builder.h"

static inline MirValue ob_past(MirBuilder *b, MirValue p, MirValue by) {
  const MirValue args[2] = {p, by};
  return mir_b_emit(b, MOP_PtrAdd, args, 2, (MirImm){0}, MIR_PTR);
}

static inline MirValue ob_add(MirBuilder *b, MirValue p, int64_t at) {
  return at == 0 ? p : ob_past(b, p, mir_b_iconst(b, at));
}

static inline MirValue ob_load(MirBuilder *b, MirValue base, int64_t at, MirTy ty) {
  const MirValue p = ob_add(b, base, at);
  return mir_b_emit(b, MOP_Load, &p, 1, (MirImm){.tag = MI_TY, .a = ty}, ty);
}

static inline MirValue ob_loadu(MirBuilder *b, MirValue p, int64_t width) {
  return mir_b_emit(b, MOP_PtrLoadU, &p, 1, (MirImm){.tag = MI_INT, .i = width}, MIR_INT);
}

static inline MirValue ob_int(MirBuilder *b, MirOp op, MirValue x, int64_t y) {
  return mir_b_binop(b, op, x, mir_b_iconst(b, y));
}

static inline MirValue ob_and(MirBuilder *b, MirValue x, MirValue y) {
  return mir_b_binop(b, MOP_And, x, y);
}

/* Copies `n` (1 to 16) bytes from `src` to `dst` with overlapping fixed-width moves (opt_appendfast.c). */
void opt_copy_short(MirBuilder *b, MirValue src, MirValue dst, MirValue n);

/* Branches to `then` or `other`, both of whose predecessors are then emitted: both are sealed. */
static inline void ob_br_if(MirBuilder *b, MirValue cond, MirBlock then, MirBlock other) {
  mir_b_br_if(b, cond, then, NULL, 0, other, NULL, 0);
  mir_b_seal_block(b, then);
  mir_b_seal_block(b, other);
}

#endif

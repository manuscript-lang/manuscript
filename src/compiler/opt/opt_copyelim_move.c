/* opt_copyelim_move.c: see opt_copyelim.h. */
#include "compiler/opt/opt_copyelim.h"

/* ---- a copy of a source that dies right after ---- */

/* Whether some instruction in `(i, j)` of `b` reads, other than through `v`, what was borrowed out
 * of `v` before the copy (a projection another pass merged into an earlier one): the copy's drop
 * would free `v` under it. */
static bool cpe_reads_held(const MirBlockData *b, uint32_t i, uint32_t j, MirValue v,
             const bool *held) {
  for (uint32_t k = i + 1; k < j; k++) {
    for (uint32_t a = 0; a < b->insts.ptr[k].nargs; a++) {
      const MirValue arg = b->insts.ptr[k].args[a];
      if (arg != v && held[arg]) {
        return true;
      }
    }
  }
  return false;
}

/* Turns `c = clone v; ...; drop v` into a move when `v` is not touched in between: the copy and
 * the drop cancel, and `c` is `v`. This is the shape of `l = More(l)` in a loop, which would
 * otherwise deep-copy the old value on every iteration. */
bool cpe_move_dead_sources(MsArena *arena, const MirModule *m, MirFunc *f) {
  const CpeBorrows borrows = cpe_borrows_of(arena, m, f, false);
  bool *tainted = cpe_view_tainted(arena, m, f);
  MirValue *rename = cpe_new_values(arena, f, MIR_NONE);
  bool *touched = cpe_new_flags(arena, f);
  bool *held = cpe_new_flags(arena, f);
  MirValue *stack = MS_ARENA_NEW_ARRAY(arena, MirValue, (size_t)f->values.len + (size_t)borrows.start[f->values.len + 1] + 2);
  CpeDead dead = {0};
  const CpeUses at = cpe_operand_uses(arena, f);
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    const MirBlockData *b = &f->blocks.ptr[bi];
    for (uint32_t i = 0; i < b->insts.len; i++) {
      const MirInst *inst = &b->insts.ptr[i];
      if (inst->op != MOP_Clone || inst->res == MIR_NONE) {
        continue;
      }
      const MirValue c = inst->res, v = inst->args[0];
      CpePos next = {0, 0};
      if (touched[c] || touched[v] || tainted[v] || !cpe_next_use(&at, v, bi, i, &next) ||
        next.block != bi || b->insts.ptr[next.index].op != MOP_Drop) {
        continue;
      }
      cpe_hold(&borrows, v, (uint32_t)f->values.len, held, stack);
      if (cpe_reads_held(b, i, next.index, v, held)) {
        continue;
      }
      touched[c] = true;
      touched[v] = true;
      rename[c] = v;
      cpe_dead_push(arena, &dead, bi, i);
      cpe_dead_push(arena, &dead, bi, next.index);
    }
  }
  if (dead.n == 0) {
    return false;
  }
  cpe_remove_insts(arena, f, &dead);
  cpe_apply_rename(f, rename, true);
  return true;
}

/* ---- a copy that is the last use of its source on every path ---- */


static CpeScan cpe_scan(const MirBlockData *blk, uint32_t from, MirValue v, const bool *held,
           uint32_t *drop_at) {
  for (uint32_t k = from; k < blk->insts.len; k++) {
    const MirInst *n = &blk->insts.ptr[k];
    if (n->op == MOP_Drop && n->args[0] == v) {
      *drop_at = k;
      return CE_SCAN_DROP;
    }
    for (uint32_t a = 0; a < n->nargs; a++) {
      if (held[n->args[a]]) {
        return CE_SCAN_READ;
      }
    }
  }
  return CE_SCAN_PASSES;
}


static void cpe_term_reads(void *ctx, MirValue v) {
  CpeHeld *h = ctx;
  h->used |= h->held[v];
}


/* The owned values of `f`, where each is defined, and what borrows from each (an owned result
 * that is a view borrows from its operands too). */
CpeFlow cpe_flow(MsArena *arena, const MirModule *m, const MirFunc *f) {
  CpeFlow fl = {cpe_new_flags(arena, f), MS_ARENA_NEW_ARRAY(arena, uint32_t, (size_t)f->values.len + 1), {0},
        NULL, {0}};
  for (uint32_t v = 0; v <= f->values.len; v++) {
    fl.home[v] = UINT32_MAX;
  }
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    const MirBlockData *b = &f->blocks.ptr[bi];
    for (uint32_t p = 0; p < b->params.len; p++) {
      fl.home[b->params.ptr[p].value] = bi;
      fl.owned[b->params.ptr[p].value] = b->params.ptr[p].mode == MM_MOVE;
    }
    for (uint32_t i = 0; i < b->insts.len; i++) {
      if (b->insts.ptr[i].res != MIR_NONE) {
        fl.home[b->insts.ptr[i].res] = bi;
        MirMode mode = MM_BORROW;
        if (mir_result_mode(m, f, &b->insts.ptr[i], &mode) && mode == MM_MOVE) {
          fl.owned[b->insts.ptr[i].res] = true;
        }
      }
    }
  }
  fl.borrows = cpe_borrows_of(arena, m, f, true);
  fl.tainted = cpe_view_tainted(arena, m, f);
  fl.preds = mir_preds(arena, f);
  return fl;
}

/* The paths from the copy `(bc, i)` of `v`: each ends in a drop of `v` and reads nothing borrowed
 * from it. Collects the drops; `*seen` marks the blocks reached. False when a path is not clean. */
bool cpe_paths(MsArena *arena, const MirFunc *f, const CpeFlow *fl, uint32_t bc, uint32_t i,
          MirValue v, const bool *held, bool *seen, CpeDead *drops) {
  CpePos *work = MS_ARENA_NEW_ARRAY(arena, CpePos, (size_t)f->blocks.len * 2 + 2);
  uint32_t top = 0;
  work[top++] = (CpePos){bc, i + 1};
  while (top > 0) {
    const CpePos w = work[--top];
    const MirBlockData *blk = &f->blocks.ptr[w.block];
    uint32_t drop_at = 0;
    const CpeScan scan = cpe_scan(blk, w.index, v, held, &drop_at);
    if (scan == CE_SCAN_READ) {
      return false;
    }
    if (scan == CE_SCAN_DROP) {
      cpe_dead_push(arena, drops, w.block, drop_at);
      continue;
    }
    CpeHeld h = {held, false};
    mir_term_each_value(&blk->term, cpe_term_reads, &h);
    if (h.used || blk->term.kind == MT_RET) {
      return false;
    }
    for (uint32_t t = 0; t < mir_term_ntargets(&blk->term); t++) {
      const uint32_t s = mir_term_target_const(&blk->term, t)->block;
      if (s == bc || s == fl->home[v]) {
        return false;
      }
      if (!seen[s]) {
        seen[s] = true;
        work[top++] = (CpePos){s, 0};
      }
    }
  }
  return true;
}

/* Whether a block reached by the paths is also entered from outside them. */
bool cpe_entered_elsewhere(const MirFunc *f, const CpeFlow *fl, uint32_t bc,
                const bool *seen) {
  for (uint32_t x = 0; x < f->blocks.len; x++) {
    if (!seen[x]) {
      continue;
    }
    for (uint32_t k = 0; k < mir_preds_count(&fl->preds, x); k++) {
      const MirBlock p = mir_pred(&fl->preds, x, k);
      if (p != bc && !seen[p]) {
        return true;
      }
    }
  }
  return false;
}

/* Turns `c = clone v` into a move when every path from the copy reaches `v` again only to drop
 * it: the copy is `v`'s last use, like `keys.append(key)` before a loop body ends or returns. The
 * copy and the drops cancel, and `c` is `v`. Nothing borrowed out of `v` may be read after the
 * copy, and each block on those paths is entered only from them, so a path that skipped the copy
 * keeps its drop. */
bool cpe_move_across(MsArena *arena, const MirModule *m, MirFunc *f) {
  const CpeFlow fl = cpe_flow(arena, m, f);
  bool *touched = cpe_new_flags(arena, f), *held = cpe_new_flags(arena, f);
  MirValue *rename = cpe_new_values(arena, f, MIR_NONE);
  MirValue *stack = MS_ARENA_NEW_ARRAY(arena, MirValue, (size_t)f->values.len + (size_t)fl.borrows.start[f->values.len + 1] + 2);
  bool *seen = MS_ARENA_NEW_ARRAY(arena, bool, (size_t)f->blocks.len + 1);
  CpeDead dead = {0};
  for (uint32_t bc = 0; bc < f->blocks.len; bc++) {
    for (uint32_t i = 0; i < f->blocks.ptr[bc].insts.len; i++) {
      const MirInst *inst = &f->blocks.ptr[bc].insts.ptr[i];
      if (inst->op != MOP_Clone || inst->res == MIR_NONE) {
        continue;
      }
      const MirValue c = inst->res, v = inst->args[0];
      if (!fl.owned[v] || fl.tainted[v] || touched[v] || touched[c]) {
        continue;
      }
      cpe_hold(&fl.borrows, v, (uint32_t)f->values.len, held, stack);
      __builtin_memset(seen, 0, sizeof(bool) * f->blocks.len);
      CpeDead drops = {0};
      if (!cpe_paths(arena, f, &fl, bc, i, v, held, seen, &drops) || drops.n == 0 ||
        cpe_entered_elsewhere(f, &fl, bc, seen)) {
        continue;
      }
      touched[v] = true;
      touched[c] = true;
      rename[c] = v;
      cpe_dead_push(arena, &dead, bc, i);
      for (uint32_t k = 0; k < drops.n; k++) {
        cpe_dead_push(arena, &dead, drops.at[k].block, drops.at[k].index);
      }
    }
  }
  if (dead.n == 0) {
    return false;
  }
  cpe_remove_insts(arena, f, &dead);
  cpe_apply_rename(f, rename, true);
  return true;
}

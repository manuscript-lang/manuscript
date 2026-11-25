/* The `copyelim` pass: removes deep copies that only feed read-only uses.
 *
 * Lowering copies a value when it binds a pattern payload or a field out of a borrowed parameter,
 * then drops the copy at scope end. When every use of the copy is a borrowing operand, the copy is
 * the same value as its source for the whole function, provided the source cannot change or die
 * before the copy would: a borrowed parameter is neither mutated nor released by its callee, and
 * neither is anything projected out of one. The pass also turns a copy of a dying source into a
 * move, and a copy of a payload of a dying alternative, option or type into a move out of it. */

#include "compiler/opt/opt_copyelim.h"

#include "base/sort.h"

/* ---- shared facts ---- */



CpeUses cpe_operand_uses(MsArena *arena, const MirFunc *f) {
  CpeUses u = {MS_ARENA_NEW_ARRAY(arena, uint32_t, (size_t)f->values.len + 2), NULL};
  __builtin_memset(u.start, 0, sizeof(uint32_t) * ((size_t)f->values.len + 2));
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      const MirInst *inst = &f->blocks.ptr[b].insts.ptr[i];
      for (uint32_t k = 0; k < inst->nargs; k++) {
        u.start[inst->args[k] + 1]++;
      }
    }
  }
  for (uint32_t v = 0; v <= f->values.len; v++) {
    u.start[v + 1] += u.start[v];
  }
  u.at = MS_ARENA_NEW_ARRAY(arena, CpePos, (size_t)u.start[f->values.len + 1] + 1);
  uint32_t *fill = MS_ARENA_NEW_ARRAY(arena, uint32_t, (size_t)f->values.len + 1);
  __builtin_memcpy(fill, u.start, sizeof(uint32_t) * ((size_t)f->values.len + 1));
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      const MirInst *inst = &f->blocks.ptr[b].insts.ptr[i];
      for (uint32_t k = 0; k < inst->nargs; k++) {
        u.at[fill[inst->args[k]]++] = (CpePos){b, i};
      }
    }
  }
  return u;
}


/* The first use of `v` after instruction `i` of block `bi`; false when there is none. */
bool cpe_next_use(const CpeUses *u, MirValue v, uint32_t bi, uint32_t i, CpePos *out) {
  for (uint32_t k = 0; k < cpe_nuses(u, v); k++) {
    const CpePos p = cpe_use(u, v, k);
    if (p.block > bi || (p.block == bi && p.index > i)) {
      *out = p;
      return true;
    }
  }
  return false;
}


static int64_t cpe_cmp_key(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  const uint64_t x = *(const uint64_t *)(const void *)a, y = *(const uint64_t *)(const void *)b;
  if (x == y) {
    return 0;
  }
  return x < y ? -1 : 1;
}

CpeBlockUses cpe_block_uses(MsArena *arena, const MirBlockData *b) {
  uint32_t n = 0;
  for (uint32_t i = 0; i < b->insts.len; i++) {
    n += b->insts.ptr[i].nargs;
  }
  CpeBlockUses u = {MS_ARENA_NEW_ARRAY(arena, uint64_t, (size_t)n + 1), 0};
  for (uint32_t i = 0; i < b->insts.len; i++) {
    for (uint32_t k = 0; k < b->insts.ptr[i].nargs; k++) {
      u.keys[u.n++] = ((uint64_t)b->insts.ptr[i].args[k] << 32) | i;
    }
  }
  if (u.n > 1) {
    ms_sort((uint8_t *)u.keys, u.n, sizeof(uint64_t), cpe_cmp_key, NULL);
  }
  return u;
}

/* The index of the first key above `(v, i)`. */
uint32_t cpe_after_start(const CpeBlockUses *u, MirValue v, uint32_t i) {
  const uint64_t key = ((uint64_t)v << 32) | i;
  uint32_t lo = 0, hi = u->n;
  while (lo < hi) {
    const uint32_t mid = lo + (hi - lo) / 2;
    if (u->keys[mid] <= key) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/* The next position after `*cursor` that uses `v`, advancing it. */
bool cpe_after_next(const CpeBlockUses *u, MirValue v, uint32_t *cursor, uint32_t *at) {
  if (*cursor >= u->n || (MirValue)(u->keys[*cursor] >> 32) != v) {
    return false;
  }
  *at = (uint32_t)(u->keys[*cursor] & 0xFFFFFFFFu);
  (*cursor)++;
  return true;
}

/* The first use of `v` after instruction `i` that is an `op`; false when there is none. */
bool cpe_first_after(const CpeBlockUses *u, const MirBlockData *b, MirValue v, uint32_t i,
             MirOp op, uint32_t *out) {
  uint32_t cursor = cpe_after_start(u, v, i), at = 0;
  while (cpe_after_next(u, v, &cursor, &at)) {
    if (b->insts.ptr[at].op == op) {
      *out = at;
      return true;
    }
  }
  return false;
}


CpeBorrows cpe_borrows_of(MsArena *arena, const MirModule *m, const MirFunc *f,
               bool strict) {
  CpeBorrows br = {MS_ARENA_NEW_ARRAY(arena, uint32_t, (size_t)f->values.len + 2), NULL};
  __builtin_memset(br.start, 0, sizeof(uint32_t) * ((size_t)f->values.len + 2));
  for (int pass = 0; pass < 2; pass++) {
    uint32_t *fill = NULL;
    if (pass == 1) {
      for (uint32_t v = 0; v <= f->values.len; v++) {
        br.start[v + 1] += br.start[v];
      }
      br.list = MS_ARENA_NEW_ARRAY(arena, MirValue, (size_t)br.start[f->values.len + 1] + 1);
      fill = MS_ARENA_NEW_ARRAY(arena, uint32_t, (size_t)f->values.len + 1);
      __builtin_memcpy(fill, br.start, sizeof(uint32_t) * ((size_t)f->values.len + 1));
    }
    for (uint32_t b = 0; b < f->blocks.len; b++) {
      for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
        const MirInst *inst = &f->blocks.ptr[b].insts.ptr[i];
        MirMode mode = MM_BORROW;
        const bool has = mir_result_mode(m, f, inst, &mode);
        /* A result that borrows, or (loosely) an owned view; strictly, only an owned one that
         * has a result mode at all. */
        const bool borrows = strict ? has && (mode != MM_MOVE || mir_result_views(m, f, inst))
                      : (has && mode != MM_MOVE) || mir_result_views(m, f, inst);
        if (inst->res == MIR_NONE || !borrows) {
          continue;
        }
        for (uint32_t k = 0; k < inst->nargs; k++) {
          if (pass == 0) {
            br.start[inst->args[k] + 1]++;
          } else {
            br.list[fill[inst->args[k]]++] = inst->res;
          }
        }
      }
    }
  }
  return br;
}

/* Marks `v` and everything transitively borrowed out of it in `held` (cleared first). */
void cpe_hold(const CpeBorrows *br, MirValue v, uint32_t nvalues, bool *held,
          MirValue *stack) {
  __builtin_memset(held, 0, sizeof(bool) * ((size_t)nvalues + 1));
  uint32_t top = 0;
  stack[top++] = v;
  while (top > 0) {
    const MirValue x = stack[--top];
    if (held[x]) {
      continue;
    }
    held[x] = true;
    for (uint32_t k = br->start[x]; k < br->start[x + 1]; k++) {
      stack[top++] = br->list[k];
    }
  }
}

/* Values that may be interface views (`iface.borrow`, `iface.view`, a view returner's result) or
 * hold one: an owned value whose payload is borrowed from elsewhere. A copy of such a value owns
 * its payload, so the copy is never turned into a move or a take of the source. */
static void cpe_taint_view_returners(const MirModule *m, const MirFunc *f, bool *tainted) {
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      const MirInst *inst = &f->blocks.ptr[b].insts.ptr[i];
      if (inst->op != MOP_CallRt || inst->imm.tag != MI_EXT ||
        m->externs.ptr[inst->imm.a].role != MR_VIEW_RESULT) {
        continue;
      }
      for (uint32_t k = 0; k < inst->nargs; k++) {
        if (mir_value_ty(f, inst->args[k]) == MIR_PTR) {
          tainted[inst->args[k]] = true;
        }
      }
    }
  }
}

static bool cpe_taint_inst(const MirModule *m, const MirFunc *f, const MirInst *inst, bool *tainted) {
  bool changed = false;
  if ((inst->op == MOP_Put || inst->op == MOP_Store) && inst->nargs >= 2 &&
    tainted[inst->args[1]] && !tainted[inst->args[0]]) {
    tainted[inst->args[0]] = true;
    changed = true;
  }
  if (inst->res == MIR_NONE || tainted[inst->res]) {
    return changed;
  }
  bool hit = mir_result_views(m, f, inst);
  if (!hit && inst->op != MOP_Clone && !mir_op_is_call((MirOp)inst->op)) {
    for (uint32_t k = 0; k < inst->nargs && !hit; k++) {
      hit = tainted[inst->args[k]];
    }
  }
  if (hit) {
    tainted[inst->res] = true;
    changed = true;
  }
  return changed;
}

static bool cpe_taint_block(const MirModule *m, const MirFunc *f, const MirBlockData *blk,
             bool *tainted) {
  bool changed = false;
  for (uint32_t i = 0; i < blk->insts.len; i++) {
    changed |= cpe_taint_inst(m, f, &blk->insts.ptr[i], tainted);
  }
  for (uint32_t t = 0; t < mir_term_ntargets(&blk->term); t++) {
    const MirTarget *target = mir_term_target_const(&blk->term, t);
    const MirBlockData *dest = &f->blocks.ptr[target->block];
    for (uint32_t k = 0; k < target->nargs && k < dest->params.len; k++) {
      if (tainted[target->args[k]] && !tainted[dest->params.ptr[k].value]) {
        tainted[dest->params.ptr[k].value] = true;
        changed = true;
      }
    }
  }
  return changed;
}

bool *cpe_view_tainted(MsArena *arena, const MirModule *m, const MirFunc *f) {
  bool *tainted = MS_ARENA_NEW_ARRAY(arena, bool, (size_t)f->values.len + 1);
  __builtin_memset(tainted, 0, sizeof(bool) * ((size_t)f->values.len + 1));
  cpe_taint_view_returners(m, f, tainted);
  bool changed = true;
  while (changed) {
    changed = false;
    for (uint32_t b = 0; b < f->blocks.len; b++) {
      changed |= cpe_taint_block(m, f, &f->blocks.ptr[b], tainted);
    }
  }
  return tainted;
}

/* ---- editing ---- */

static int64_t cpe_cmp_pos(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  const CpePos *x = (const void *)a, *y = (const void *)b;
  if (x->block != y->block) {
    return x->block < y->block ? -1 : 1;
  }
  if (x->index == y->index) {
    return 0;
  }
  return x->index < y->index ? -1 : 1;
}


void cpe_dead_push(MsArena *arena, CpeDead *d, uint32_t block, uint32_t index) {
  if (d->n == d->cap) {
    const uint32_t next = d->cap ? d->cap * 2 : 16;
    CpePos *grown = MS_ARENA_NEW_ARRAY(arena, CpePos, next);
    if (d->n > 0) {
      __builtin_memcpy(grown, d->at, sizeof(CpePos) * d->n);
    }
    d->at = grown;
    d->cap = next;
  }
  d->at[d->n++] = (CpePos){block, index};
}

/* Removes the instructions at the positions in `dead`. */
void cpe_remove_insts(MsArena *arena, MirFunc *f, CpeDead *dead) {
  if (dead->n > 1) {
    ms_sort((uint8_t *)dead->at, dead->n, sizeof(CpePos), cpe_cmp_pos, NULL);
  }
  uint32_t *ks = MS_ARENA_NEW_ARRAY(arena, uint32_t, (size_t)dead->n + 1);
  uint32_t k = 0;
  while (k < dead->n) {
    const uint32_t block = dead->at[k].block;
    uint32_t n = 0;
    for (; k < dead->n && dead->at[k].block == block; k++) {
      if (n == 0 || ks[n - 1] != dead->at[k].index) {
        ks[n++] = dead->at[k].index;
      }
    }
    mir_block_remove(&f->blocks.ptr[block], ks, n);
  }
}

static void cpe_rename_term(void *ctx, MirValue *v) {
  const MirValue *rename = ctx;
  if (rename[*v] != MIR_NONE) {
    *v = rename[*v];
  }
}

/* Rewrites every operand with a rename (and, with `terms`, the terminators' too). */
void cpe_apply_rename(MirFunc *f, MirValue *rename, bool terms) {
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    MirBlockData *blk = &f->blocks.ptr[b];
    for (uint32_t i = 0; i < blk->insts.len; i++) {
      for (uint32_t k = 0; k < blk->insts.ptr[i].nargs; k++) {
        const MirValue s = rename[blk->insts.ptr[i].args[k]];
        if (s != MIR_NONE) {
          blk->insts.ptr[i].args[k] = s;
        }
      }
    }
    if (terms) {
      mir_term_each_use(&blk->term, cpe_rename_term, rename);
    }
  }
}

MirValue *cpe_new_values(MsArena *arena, const MirFunc *f, MirValue fill) {
  MirValue *v = MS_ARENA_NEW_ARRAY(arena, MirValue, (size_t)f->values.len + 1);
  for (uint32_t i = 0; i <= f->values.len; i++) {
    v[i] = fill;
  }
  return v;
}

bool *cpe_new_flags(MsArena *arena, const MirFunc *f) {
  bool *v = MS_ARENA_NEW_ARRAY(arena, bool, (size_t)f->values.len + 1);
  __builtin_memset(v, 0, sizeof(bool) * ((size_t)f->values.len + 1));
  return v;
}

/* ---- the pass ---- */

bool opt_copyelim_func(MirModule *m, MirFunc *f) {
  MsArena arena = ms_arena_new();
  bool changed = cpe_alias_stable(&arena, m, f);
  changed |= cpe_move_dead_sources(&arena, m, f);
  changed |= cpe_move_across(&arena, m, f);
  changed |= cpe_borrow_local_copies(&arena, m, f);
  changed |= cpe_unbox_dead_sources(&arena, m, f);
  changed |= cpe_unbox_dead_options(&arena, m, f);
  changed |= cpe_unbox_across(&arena, m, f);
  ms_arena_free(&arena);
  return changed;
}

bool opt_copyelim(MirModule *m) {
  return opt_each_func(m, opt_copyelim_func);
}

bool opt_copyelim_takes(MirModule *m) {
  bool changed = false;
  for (uint32_t fi = 0; fi < m->funcs.len; fi++) {
    for (;;) {
      MsArena arena = ms_arena_new();
      const bool took = cpe_take_type_fields(&arena, m, &m->funcs.ptr[fi]);
      ms_arena_free(&arena);
      if (!took) {
        break;
      }
      changed = true;
    }
  }
  return changed;
}

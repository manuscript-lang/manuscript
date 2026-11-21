/* The `lastuse` pass: drops a plain-memory owned value right after its last use instead of where
 * lowering put the drop (the end of the enclosing scope).
 *
 * A candidate `v` is a value of a type whose drop only frees memory (strings, lists, maps, sets and
 * types, alternatives and optionals of those) that is dropped with `drop v`. Everything that may
 * point into `v` forms its family: results of instructions that take a family member (string views,
 * interior pointers, projections, runtime calls), out-pointers of calls that take one, and block
 * parameters that receive one. `v` lives until the last use of any family member on every path; the
 * drop moves there (a new block on an edge that leaves the family's live range, e.g. a loop exit).
 *
 * The family only ever extends `v`'s life, never past its original drop. A candidate is left alone
 * when a family member is stored to memory, captured, kept by a cleanup, or when `v` takes part in a
 * conditional drop. */

#include "compiler/opt/opt_lastuse.h"

#include "base/sort.h"

/* ---- small growable arrays in the pass arena ---- */


static void *lu_regrow(MsArena *a, void *old, uint32_t oldn, uint32_t newcap, size_t elem) {
  void *p = ms_arena_alloc_zeroed(a, elem * ((size_t)newcap + 1), 16);
  __builtin_memset(p, 0, elem * ((size_t)newcap + 1));
  if (oldn > 0) {
    __builtin_memcpy(p, old, elem * oldn);
  }
  return p;
}

/* Zeroed storage for `n` elements of `elem` bytes (an arena returns it as it was). */
void *lu_zeroed(MsArena *a, size_t n, size_t elem) {
  return lu_regrow(a, NULL, 0, (uint32_t)n, elem);
}

static void lu_push(MsArena *a, LuList *l, uint64_t x) {
  if (l->n == l->cap) {
    const uint32_t cap = l->cap ? l->cap * 2 : 4;
    l->v = lu_regrow(a, l->v, l->n, cap, sizeof(uint64_t));
    l->cap = cap;
  }
  l->v[l->n++] = x;
}

static bool lu_has(const LuList *l, uint64_t x) {
  for (uint32_t i = 0; i < l->n; i++) {
    if (l->v[i] == x) {
      return true;
    }
  }
  return false;
}


LuPos lu_at(uint32_t i) { return (LuPos){(uint64_t)i + 1, 0}; }
LuPos lu_start(void) { return (LuPos){0, 0}; }
LuPos lu_end(void) { return (LuPos){UINT64_MAX, UINT32_MAX}; }

int lu_cmp(LuPos a, LuPos b) {
  if (a.idx != b.idx) {
    return a.idx < b.idx ? -1 : 1;
  }
  if (a.after == b.after) {
    return 0;
  }
  return a.after < b.after ? -1 : 1;
}




void lu_fit(LuCtx *x) {
  const MirFunc *f = x->f;
  if (f->values.len > x->nvcap) {
    const uint32_t cap = (uint32_t)(f->values.len + f->values.len / 2 + 8);
    x->uses = lu_regrow(x->arena, x->uses, x->nvcap, cap, sizeof(LuList));
    x->term_uses = lu_regrow(x->arena, x->term_uses, x->nvcap, cap, sizeof(LuList));
    x->pending_blocks = lu_regrow(x->arena, x->pending_blocks, x->nvcap, cap, sizeof(LuList));
    x->slots = lu_regrow(x->arena, x->slots, x->nvcap, cap, sizeof(bool));
    x->fam_gen = lu_regrow(x->arena, x->fam_gen, x->nvcap, cap, sizeof(uint32_t));
    x->nvcap = cap;
  }
  if (f->blocks.len > x->nbcap) {
    const uint32_t cap = (uint32_t)(f->blocks.len + f->blocks.len / 2 + 8);
    x->removed = lu_regrow(x->arena, x->removed, x->nbcap, cap, sizeof(bool *));
    x->pending = lu_regrow(x->arena, x->pending, x->nbcap, cap, sizeof(LuPending));
    x->preds = lu_regrow(x->arena, x->preds, x->nbcap, cap, sizeof(LuList));
    x->lid_gen = lu_regrow(x->arena, x->lid_gen, x->nbcap, cap, sizeof(uint32_t));
    x->lid = lu_regrow(x->arena, x->lid, x->nbcap, cap, sizeof(uint32_t));
    x->drop_gen = lu_regrow(x->arena, x->drop_gen, x->nbcap, cap, sizeof(uint32_t));
    x->drop_at = lu_regrow(x->arena, x->drop_at, x->nbcap, cap, sizeof(uint32_t));
    x->cons_gen = lu_regrow(x->arena, x->cons_gen, x->nbcap, cap, sizeof(uint32_t));
    x->cons_at = lu_regrow(x->arena, x->cons_at, x->nbcap, cap, sizeof(uint32_t));
    x->nbcap = cap;
  }
}


static void lu_note_term_use(void *ctx, MirValue v) {
  LuTermCtx *t = ctx;
  lu_push(t->x->arena, &t->x->term_uses[v], t->block);
}

static void lu_index(LuCtx *x) {
  MirFunc *f = x->f;
  uint32_t maxargs = 1;
  lu_fit(x);
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    const MirBlockData *b = &f->blocks.ptr[bi];
    x->removed[bi] = lu_regrow(x->arena, NULL, 0, (uint32_t)b->insts.len, sizeof(bool));
    for (uint32_t ii = 0; ii < b->insts.len; ii++) {
      const MirInst *inst = &b->insts.ptr[ii];
      if (inst->nargs > maxargs) {
        maxargs = inst->nargs;
      }
      if (inst->op == MOP_Slot && inst->res != MIR_NONE) {
        x->slots[inst->res] = true;
      }
      for (uint32_t k = 0; k < inst->nargs; k++) {
        lu_push(x->arena, &x->uses[inst->args[k]], ((uint64_t)bi << 32) | ii);
      }
    }
    LuTermCtx tc = {x, bi};
    mir_term_each_value(&b->term, lu_note_term_use, &tc);
    for (uint32_t s = 0; s < mir_term_ntargets(&b->term); s++) {
      lu_push(x->arena, &x->preds[mir_term_target_const(&b->term, s)->block], bi);
    }
  }
  x->modes = MS_ARENA_NEW_ARRAY(x->arena, MirMode, maxargs);
}

bool lu_live(const LuCtx *x, uint32_t bi, uint32_t ii) { return !x->removed[bi][ii]; }
uint32_t lu_use_block(uint64_t u) { return (uint32_t)(u >> 32); }
uint32_t lu_use_inst(uint64_t u) { return (uint32_t)u; }

/* The group of `anchor` in `p`, creating it when `create`; NULL when absent. */
static LuGroup *lu_group(MsArena *a, LuPending *p, uint64_t anchor, bool create) {
  uint32_t lo = 0, hi = p->n;
  while (lo < hi) {
    const uint32_t mid = lo + (hi - lo) / 2;
    if (p->g[mid].anchor < anchor) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  if (lo < p->n && p->g[lo].anchor == anchor) {
    return &p->g[lo];
  }
  if (!create) {
    return NULL;
  }
  if (p->n == p->cap) {
    const uint32_t cap = p->cap ? p->cap * 2 : 2;
    p->g = lu_regrow(a, p->g, p->n, cap, sizeof(LuGroup));
    p->cap = cap;
  }
  __builtin_memmove(&p->g[lo + 1], &p->g[lo], sizeof(LuGroup) * (p->n - lo));
  p->g[lo] = (LuGroup){anchor, NULL, 0, 0};
  p->n++;
  return &p->g[lo];
}

/* Types a drop of `v` directly behind `pos`: behind the instruction, ahead of the drops already
 * placed there, or behind the pending drop `pos` names. */
void lu_insert_pending(LuCtx *x, uint32_t bi, LuPos pos, MirValue v) {
  LuGroup *g = lu_group(x->arena, &x->pending[bi], pos.idx, true);
  if (g->n == g->cap) {
    const uint32_t cap = g->cap ? g->cap * 2 : 2;
    g->v = lu_regrow(x->arena, g->v, g->n, cap, sizeof(MirValue));
    g->cap = cap;
  }
  const uint32_t at = pos.after < g->n ? pos.after : g->n;
  __builtin_memmove(&g->v[at + 1], &g->v[at], sizeof(MirValue) * (g->n - at));
  g->v[at] = v;
  g->n++;
  if (!lu_has(&x->pending_blocks[v], bi)) {
    lu_push(x->arena, &x->pending_blocks[v], bi);
  }
}

/* Writes the recorded removals and insertions into the function. */
static MirInst lu_drop_inst(MirModule *m, MirValue v, MirLoc loc) {
  MirInst d = {.op = MOP_Drop, .res = MIR_NONE, .loc = loc, .nargs = 1};
  d.args = MS_ARENA_NEW_ARRAY(&m->arena, MirValue, 1);
  d.args[0] = v;
  return d;
}

static void lu_apply(LuCtx *x) {
  MirModule *m = x->m;
  MirFunc *f = x->f;
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    MirBlockData *b = &f->blocks.ptr[bi];
    const LuPending *p = &x->pending[bi];
    bool any_removed = false;
    for (uint32_t k = 0; k < b->insts.len; k++) {
      any_removed |= x->removed[bi][k];
    }
    if (p->n == 0 && !any_removed) {
      continue;
    }
    uint32_t total = (uint32_t)b->insts.len;
    for (uint32_t gi = 0; gi < p->n; gi++) {
      total += p->g[gi].n;
    }
    MirInst *out = MS_ARENA_NEW_ARRAY(&m->arena, MirInst, total);
    uint32_t n = 0, gi = 0;
    if (gi < p->n && p->g[gi].anchor == 0) {
      for (uint32_t d = 0; d < p->g[gi].n; d++) {
        out[n++] = lu_drop_inst(m, p->g[gi].v[d], b->term_loc);
      }
      gi++;
    }
    for (uint32_t k = 0; k < b->insts.len; k++) {
      const MirInst inst = b->insts.ptr[k];
      if (!x->removed[bi][k]) {
        out[n++] = inst;
      }
      if (gi < p->n && p->g[gi].anchor == (uint64_t)k + 1) {
        for (uint32_t d = 0; d < p->g[gi].n; d++) {
          out[n++] = lu_drop_inst(m, p->g[gi].v[d], inst.loc);
        }
        gi++;
      }
    }
    opt_block_set_insts(b, out, n);
  }
}

/* ---- classification ---- */

/* Whether dropping a value of `t` only frees memory. `seen` holds every type and alternative
 * already entered (stamped with `gen`): revisiting one counts as plain, so each is classified once. */
static bool lu_plain(const MirModule *m, MirTy t, uint32_t *seen, uint32_t gen) {
  const MirTyData *d = mir_ty_data(m, t);
  switch ((MirTyKind)d->kind) {
  case MK_VOID: case MK_BOOL: case MK_INT: case MK_INT8: case MK_INT16: case MK_INT32:
  case MK_UINT8: case MK_UINT16: case MK_UINT32: case MK_UINT64: case MK_FLOAT:
  case MK_FLOAT32: case MK_STR: case MK_BYTES:
    return true;
  case MK_PTR: case MK_FN: case MK_IFACE:
    return false;
  case MK_LIST: case MK_OPT:
    return lu_plain(m, d->elem, seen, gen);
  case MK_OBJ: {
    if (d->obj_class != MIR_OBJ_COLLECTION) {
      return false;
    }
    for (uint32_t i = 0; i < d->nargs; i++) {
      if (!lu_plain(m, d->args[i], seen, gen)) {
        return false;
      }
    }
    return true;
  }
  case MK_TYPE: {
    if (seen[t] == gen) {
      return true;
    }
    seen[t] = gen;
    const MirTypeDef *def = &m->type_defs.ptr[d->id];
    for (uint32_t i = 0; i < def->nfields; i++) {
      if (!lu_plain(m, def->fields[i].ty, seen, gen)) {
        return false;
      }
    }
    return true;
  }
  case MK_ALT: {
    if (seen[t] == gen) {
      return true;
    }
    seen[t] = gen;
    const MirAltDef *def = &m->alts.ptr[d->id];
    for (uint32_t c = 0; c < def->ncases; c++) {
      for (uint32_t i = 0; i < def->cases[c].nfields; i++) {
        if (!lu_plain(m, def->cases[c].fields[i].ty, seen, gen)) {
          return false;
        }
      }
    }
    return true;
  }
  }
  return false;
}

static bool lu_is_scalar(const MirModule *m, MirTy t) {
  return mir_ty_data(m, t)->kind == MK_VOID || mir_is_scalar(m, t);
}

/* ---- the family of a candidate ---- */


bool lu_in_family(const LuCtx *x, MirValue w) { return x->fam_gen[w] == x->gen; }

static void lu_add(LuCtx *x, LuFamily *fam, MirValue r) {
  if (x->fam_gen[r] == x->gen) {
    return;
  }
  x->fam_gen[r] = x->gen;
  fam->v[fam->n++] = r;
  fam->work[fam->nwork++] = r;
}

/* A call extends the family by the arguments it may keep and by a result that views into them. */
static void lu_family_call(LuCtx *x, LuFamily *fam, const MirInst *i) {
  const MirModule *m = x->m;
  const MirFunc *f = x->f;
  /* A fresh result, through the return value or an out-pointer, points into no borrowed argument, so it does
   * not extend the family. */
  const bool fresh = i->imm.tag == MI_EXT && m->externs.ptr[i->imm.a].fresh;
  if (!fresh) {
    for (uint32_t a = 0; a < i->nargs; a++) {
      if (x->slots[i->args[a]]) {
        lu_add(x, fam, i->args[a]);
      }
    }
  }
  MirMode mode = MM_MOVE;
  const bool has_mode = mir_result_mode(m, f, i, &mode);
  const bool borrowed = (has_mode && mode == MM_BORROW && (i->op == MOP_Call || i->op == MOP_CallMethod)) ||
                        mir_result_views(m, f, i);
  if (((i->op == MOP_CallRt && !fresh) || borrowed) && i->res != MIR_NONE &&
      !lu_is_scalar(m, f->values.ptr[i->res])) {
    lu_add(x, fam, i->res);
  }
}

/* Grows the family of `v` (everything that may point into it) to a fixed point over the use
 * index. `param_of` is the block `v` is a parameter of (MIR_NONE otherwise): its sibling
 * parameters may be views into it that the predecessors derived from the value they passed (an
 * owned optional passed beside its payload), so they join the family. */
void lu_family(LuCtx *x, MsArena *ca, LuFamily *fam, MirValue v, uint32_t param_of) {
  const MirModule *m = x->m;
  const MirFunc *f = x->f;
  fam->v = MS_ARENA_NEW_ARRAY(ca, MirValue, f->values.len);
  fam->work = MS_ARENA_NEW_ARRAY(ca, MirValue, f->values.len);
  fam->n = fam->nwork = 0;
  lu_add(x, fam, v);
  if (param_of != MIR_NONE) {
    const MirBlockData *pb = &f->blocks.ptr[param_of];
    for (uint32_t k = 0; k < pb->params.len; k++) {
      const MirValue pv = pb->params.ptr[k].value;
      if (pv != v && !lu_is_scalar(m, f->values.ptr[pv])) {
        lu_add(x, fam, pv);
      }
    }
  }
  while (fam->nwork > 0) {
    const MirValue w = fam->work[--fam->nwork];
    for (uint32_t k = 0; k < x->uses[w].n; k++) {
      const uint32_t bi = lu_use_block(x->uses[w].v[k]), ii = lu_use_inst(x->uses[w].v[k]);
      if (!lu_live(x, bi, ii)) {
        continue;
      }
      const MirInst *i = &f->blocks.ptr[bi].insts.ptr[ii];
      if (i->op == MOP_Drop || i->op == MOP_Clone) {
        continue;
      }
      if (mir_op_is_call(i->op)) {
        lu_family_call(x, fam, i);
        continue;
      }
      if (i->res != MIR_NONE && !lu_is_scalar(m, f->values.ptr[i->res])) {
        lu_add(x, fam, i->res);
      }
    }
    for (uint32_t k = 0; k < x->term_uses[w].n; k++) {
      const MirTerm *t = &f->blocks.ptr[x->term_uses[w].v[k]].term;
      for (uint32_t s = 0; s < mir_term_ntargets(t); s++) {
        const MirTarget *tg = mir_term_target_const(t, s);
        for (uint32_t a = 0; a < tg->nargs; a++) {
          if (tg->args[a] == w) {
            lu_add(x, fam, f->blocks.ptr[tg->block].params.ptr[a].value);
          }
        }
      }
    }
  }
}

/* ---- edges ---- */

/* Whether the `slot`-th edge of `bi` hands `v` to an owning block parameter. */
bool lu_edge_consumes(const MirFunc *f, uint32_t bi, uint32_t slot, MirValue v) {
  const MirTarget *tg = mir_term_target_const(&f->blocks.ptr[bi].term, slot);
  for (uint32_t k = 0; k < tg->nargs; k++) {
    if (tg->args[k] == v && f->blocks.ptr[tg->block].params.ptr[k].mode == MM_MOVE) {
      return true;
    }
  }
  return false;
}

/* A new block holding the drop of `v`, forwarding the edge's arguments. */
void lu_add_edge(LuCtx *x, MirValue v, uint32_t pred, uint32_t slot) {
  MirModule *m = x->m;
  MirFunc *f = x->f;
  const MirBlock dest = mir_term_target(&f->blocks.ptr[pred].term, slot)->block;
  const MirLoc loc = f->blocks.ptr[pred].term_loc;
  const uint32_t np = (uint32_t)f->blocks.ptr[dest].params.len;
  MirTy *tys = MS_ARENA_NEW_ARRAY(x->arena, MirTy, np + 1);
  uint8_t *modes = MS_ARENA_NEW_ARRAY(x->arena, uint8_t, np + 1);
  for (uint32_t k = 0; k < np; k++) {
    tys[k] = f->values.ptr[f->blocks.ptr[dest].params.ptr[k].value];
    modes[k] = f->blocks.ptr[dest].params.ptr[k].mode;
  }
  const MirBlock nbk = mir_new_block(f);
  lu_fit(x); /* the new block's rows; values are fitted as they are added */
  /* The edge now runs from `pred` through `nbk` to `dest`. */
  lu_push(x->arena, &x->preds[nbk], pred);
  for (uint32_t k = 0; k < x->preds[dest].n; k++) {
    if (x->preds[dest].v[k] == pred) {
      x->preds[dest].v[k] = nbk;
      break;
    }
  }
  MirValue *fwd = MS_ARENA_NEW_ARRAY(&m->arena, MirValue, np + 1);
  for (uint32_t k = 0; k < np; k++) {
    const MirValue val = mir_new_value(f, tys[k]);
    lu_fit(x);
    lu_push(x->arena, &x->term_uses[val], nbk);
    MirBlockData *nb = &f->blocks.ptr[nbk];
    const MirBlockParam bp = {val, modes[k]};
    mir_block_param_list_push(&nb->params, bp);
    fwd[k] = val;
  }
  MirBlockData *nb = &f->blocks.ptr[nbk];
  const MirInst drop = lu_drop_inst(m, v, loc);
  mir_inst_list_push(&nb->insts, drop);
  x->removed[nbk] = lu_regrow(x->arena, NULL, 0, 1, sizeof(bool));
  lu_push(x->arena, &x->uses[v], ((uint64_t)nbk << 32) | 0);
  nb->term.kind = MT_BR;
  nb->term.value = MIR_NONE;
  nb->term.a = (MirTarget){dest, fwd, np};
  nb->term_loc = loc;
  mir_term_target(&f->blocks.ptr[pred].term, slot)->block = nbk;
}

/* ---- the pass ---- */


bool opt_lastuse_func(MirModule *m, MirFunc *f) {
  if (f->blocks.len == 0) {
    return false;
  }
  MsArena arena = ms_arena_new();
  bool changed = false;
  bool *dropped = lu_zeroed(&arena, (size_t)f->values.len + 1, sizeof(bool));
  uint32_t ncands = 0;
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    for (uint32_t ii = 0; ii < f->blocks.ptr[bi].insts.len; ii++) {
      const MirInst *inst = &f->blocks.ptr[bi].insts.ptr[ii];
      if (inst->op == MOP_Drop) {
        dropped[inst->args[0]] = true;
      }
      ncands += inst->res != MIR_NONE;
    }
    ncands += f->blocks.ptr[bi].params.len;
  }
  LuCand *cands = MS_ARENA_NEW_ARRAY(&arena, LuCand, (size_t)ncands + 1);
  uint32_t *seen = lu_zeroed(&arena, (size_t)m->types.kinds.len + 1, sizeof(uint32_t));
  uint32_t stamp = 0, n = 0;
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    const MirBlockData *b = &f->blocks.ptr[bi];
    for (uint32_t k = 0; k < b->params.len; k++) {
      const MirValue p = b->params.ptr[k].value;
      const MirTy t = f->values.ptr[p];
      if (b->params.ptr[k].mode == MM_MOVE && dropped[p] && lu_plain(m, t, seen, ++stamp) &&
        mir_needs_drop(m, t)) {
        cands[n++] = (LuCand){p, bi, MIR_NONE};
      }
    }
    for (uint32_t ii = 0; ii < b->insts.len; ii++) {
      const MirInst *inst = &b->insts.ptr[ii];
      MirMode mode = MM_BORROW;
      if (inst->res == MIR_NONE || !dropped[inst->res] ||
        !mir_result_mode(m, f, inst, &mode) || mode != MM_MOVE) {
        continue;
      }
      const MirTy t = f->values.ptr[inst->res];
      if (lu_plain(m, t, seen, ++stamp) && mir_needs_drop(m, t)) {
        cands[n++] = (LuCand){inst->res, bi, ii};
      }
    }
  }
  if (n > 0) {
    LuCtx x = {.m = m, .f = f, .arena = &arena};
    lu_index(&x);
    /* Latest definitions first: a family member's own drop has moved before its source's is
     * placed. */
    for (uint32_t k = n; k-- > 0;) {
      changed |= lu_candidate(&x, cands[k].v, cands[k].block, cands[k].inst);
    }
    lu_apply(&x);
  }
  ms_arena_free(&arena);
  return changed;
}

bool opt_lastuse(MirModule *m) {
  bool changed = false;
  for (uint32_t fi = 0; fi < m->funcs.len; fi++) {
    changed |= opt_lastuse_func(m, &m->funcs.ptr[fi]);
  }
  return changed;
}

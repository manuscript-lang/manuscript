/* opt_lastuse_region.c: see opt_lastuse.h. */
#include "compiler/opt/opt_lastuse.h"

#include "base/sort.h"

/* ---- one candidate ---- */


static int64_t lu_cmp_u32(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  const uint32_t x = *(const uint32_t *)(const void *)a, y = *(const uint32_t *)(const void *)b;
  if (x == y) {
    return 0;
  }
  return x < y ? -1 : 1;
}

static uint32_t lu_local(const LuCtx *x, uint32_t b) {
  return x->lid_gen[b] == x->gen ? x->lid[b] : MIR_NONE;
}

static bool lu_ret_of(const MirFunc *f, uint32_t bi, MirValue v) {
  return f->blocks.ptr[bi].term.kind == MT_RET && f->blocks.ptr[bi].term.value == v;
}


static void lu_note_use(LuRegion *r, uint32_t l, LuPos p) {
  if (lu_cmp(p, r->end[l]) >= 0) {
    return;
  }
  r->any[l] = true;
  if (lu_cmp(p, r->lo[l]) >= 0 && (!r->has_last[l] || lu_cmp(p, r->last[l]) > 0)) {
    r->last[l] = p;
    r->has_last[l] = true;
  }
}

static bool lu_passes(const LuCtx *x, uint32_t bi) {
  const MirTerm *t = &x->f->blocks.ptr[bi].term;
  for (uint32_t s = 0; s < mir_term_ntargets(t); s++) {
    const MirTarget *tg = mir_term_target_const(t, s);
    for (uint32_t a = 0; a < tg->nargs; a++) {
      if (lu_in_family(x, tg->args[a])) {
        return true;
      }
    }
  }
  return false;
}


/* Whether a family member leaks into memory the pass cannot follow. */
static bool lu_leaks(const LuRun *run) {
  const LuCtx *x = run->x;
  for (uint32_t fi = 0; fi < run->fam.n; fi++) {
    const MirValue w = run->fam.v[fi];
    for (uint32_t k = 0; k < x->uses[w].n; k++) {
      const uint32_t bi = lu_use_block(x->uses[w].v[k]), ii = lu_use_inst(x->uses[w].v[k]);
      if (!lu_live(x, bi, ii)) {
        continue;
      }
      const MirInst *i = &x->f->blocks.ptr[bi].insts.ptr[ii];
      switch ((MirOp)i->op) {
      case MOP_Store: case MOP_Put:
        if (i->nargs > 1 && i->args[1] == w && (w != run->v || i->op == MOP_Store)) {
          return true;
        }
        break;
      case MOP_GlobalSet: case MOP_DropIf: case MOP_ClosureNew:
      case MOP_IfaceNew:
        return true;
      default:
        break;
      }
    }
  }
  return false;
}

/* Records where the original drops of `v` sit in each block (nothing after one counts) and the
 * earliest real consumption of `v` (not its drops) per block. */
static void lu_scan_drops(LuRun *run) {
  LuCtx *x = run->x;
  const MirValue v = run->v;
  run->existing = MS_ARENA_NEW_ARRAY(run->ca, uint64_t, x->uses[v].n + 1);
  for (uint32_t k = 0; k < x->uses[v].n; k++) {
    const uint32_t bi = lu_use_block(x->uses[v].v[k]), ii = lu_use_inst(x->uses[v].v[k]);
    if (!lu_live(x, bi, ii)) {
      continue;
    }
    const MirInst *i = &x->f->blocks.ptr[bi].insts.ptr[ii];
    if (i->op == MOP_Drop) {
      run->existing[run->nexisting++] = x->uses[v].v[k];
      if (x->drop_gen[bi] != x->gen || ii < x->drop_at[bi]) {
        x->drop_gen[bi] = x->gen;
        x->drop_at[bi] = ii;
      }
      continue;
    }
    mir_arg_modes(x->m, x->f, i, x->modes);
    bool consumes = false;
    for (uint32_t a = 0; a < i->nargs; a++) {
      consumes |= i->args[a] == v && x->modes[a] == MM_MOVE;
    }
    if (consumes && (x->cons_gen[bi] != x->gen || ii < x->cons_at[bi])) {
      x->cons_gen[bi] = x->gen;
      x->cons_at[bi] = ii;
    }
  }
}

/* Adds block `b` to the region, and to the walk's stack, unless it is already in. */
static void lu_enter(LuRun *run, uint32_t *stack, uint32_t *nstack, uint32_t b) {
  LuCtx *x = run->x;
  if (x->lid_gen[b] != x->gen) {
    x->lid_gen[b] = x->gen;
    run->r.order[run->r.nb++] = b;
    stack[(*nstack)++] = b;
  }
}

/* The region the analysis needs: the blocks on a path from the definition to a place the family
 * is used or passed on, not through a block that holds the original drop or consumes `v`. Found
 * by walking back from those places: the definition dominates them, so the walk stops at it. A
 * value used only near its definition costs those few blocks, not the rest of the function. */
static void lu_walk_region(LuRun *run) {
  LuCtx *x = run->x;
  const MirFunc *f = x->f;
  LuRegion *r = &run->r;
  r->order = MS_ARENA_NEW_ARRAY(run->ca, uint32_t, f->blocks.len);
  uint32_t *stack = MS_ARENA_NEW_ARRAY(run->ca, uint32_t, f->blocks.len);
  uint32_t nstack = 0;
  r->order[r->nb++] = run->db;
  x->lid_gen[run->db] = x->gen;
  for (uint32_t fi = 0; fi < run->fam.n; fi++) {
    const MirValue w = run->fam.v[fi];
    for (uint32_t k = 0; k < x->uses[w].n; k++) {
      const uint32_t bi = lu_use_block(x->uses[w].v[k]), ii = lu_use_inst(x->uses[w].v[k]);
      const MirInst *i = &f->blocks.ptr[bi].insts.ptr[ii];
      if (lu_live(x, bi, ii) && !(i->op == MOP_Drop && i->args[0] == run->v)) {
        lu_enter(run, stack, &nstack, bi);
      }
    }
    for (uint32_t k = 0; k < x->pending_blocks[w].n; k++) {
      lu_enter(run, stack, &nstack, (uint32_t)x->pending_blocks[w].v[k]);
    }
    for (uint32_t k = 0; k < x->term_uses[w].n; k++) {
      lu_enter(run, stack, &nstack, (uint32_t)x->term_uses[w].v[k]);
    }
  }
  while (nstack > 0) {
    const uint32_t b = stack[--nstack];
    for (uint32_t k = 0; k < x->preds[b].n; k++) {
      const uint32_t p = (uint32_t)x->preds[b].v[k];
      if (p != run->db && x->drop_gen[p] != x->gen && x->cons_gen[p] != x->gen) {
        lu_enter(run, stack, &nstack, p);
      }
    }
  }
  ms_sort((uint8_t *)r->order, r->nb, sizeof(uint32_t), lu_cmp_u32, NULL);
  for (uint32_t l = 0; l < r->nb; l++) {
    x->lid[r->order[l]] = l;
  }
  run->dl = x->lid[run->db];
}

/* Per block of the region: where the original drop cuts the uses off, where the definition lets
 * them start, and the last family use between; including drops of family members this pass has
 * already placed. */
static void lu_fill_uses(LuRun *run) {
  LuCtx *x = run->x;
  LuRegion *r = &run->r;
  const uint32_t nb = r->nb;
  r->end = MS_ARENA_NEW_ARRAY(run->ca, LuPos, nb);
  r->lo = MS_ARENA_NEW_ARRAY(run->ca, LuPos, nb);
  r->last = MS_ARENA_NEW_ARRAY(run->ca, LuPos, nb);
  r->any = lu_zeroed(run->ca, nb, sizeof(bool));
  r->has_last = lu_zeroed(run->ca, nb, sizeof(bool));
  for (uint32_t l = 0; l < nb; l++) {
    const uint32_t bi = r->order[l];
    r->end[l] = x->drop_gen[bi] == x->gen ? lu_at(x->drop_at[bi]) : lu_end();
    r->lo[l] = bi == run->db ? lu_at(run->di == MIR_NONE ? 0 : run->di + 1) : lu_start();
    r->last[l] = lu_start();
  }
  for (uint32_t fi = 0; fi < run->fam.n; fi++) {
    const MirValue w = run->fam.v[fi];
    for (uint32_t k = 0; k < x->uses[w].n; k++) {
      const uint32_t bi = lu_use_block(x->uses[w].v[k]), ii = lu_use_inst(x->uses[w].v[k]);
      const uint32_t l = lu_local(x, bi);
      if (!lu_live(x, bi, ii) || l == MIR_NONE) {
        continue;
      }
      const MirInst *i = &x->f->blocks.ptr[bi].insts.ptr[ii];
      if (!(i->op == MOP_Drop && i->args[0] == run->v)) {
        lu_note_use(r, l, lu_at(ii));
      }
    }
    for (uint32_t k = 0; k < x->pending_blocks[w].n; k++) {
      const uint32_t bi = (uint32_t)x->pending_blocks[w].v[k];
      const uint32_t l = lu_local(x, bi);
      const LuPending *p = &x->pending[bi];
      for (uint32_t gi = 0; l != MIR_NONE && gi < p->n; gi++) {
        for (uint32_t d = 0; d < p->g[gi].n; d++) {
          if (p->g[gi].v[d] == w) {
            lu_note_use(r, l, (LuPos){p->g[gi].anchor, d + 1});
          }
        }
      }
    }
  }
}

/* Backward liveness of the family over the region. */
static void lu_liveness(LuRun *run) {
  const LuCtx *x = run->x;
  const uint32_t nb = run->r.nb;
  run->live_in = lu_zeroed(run->ca, nb, sizeof(bool));
  run->live_out = lu_zeroed(run->ca, nb, sizeof(bool));
  for (bool again = true; again;) {
    again = false;
    for (uint32_t l = nb; l-- > 0;) {
      const uint32_t bi = run->r.order[l];
      bool out = false;
      if (x->drop_gen[bi] != x->gen) {
        out = lu_passes(x, bi);
        const MirTerm *t = &x->f->blocks.ptr[bi].term;
        for (uint32_t s = 0; s < mir_term_ntargets(t) && !out; s++) {
          const uint32_t sl = lu_local(x, mir_term_target_const(t, s)->block);
          out = sl != MIR_NONE && run->live_in[sl];
        }
      }
      /* Nothing of the family is live before `v` is defined. */
      const bool used = run->r.any[l] || lu_ret_of(x->f, run->r.order[l], run->v);
      const bool inn = l != run->dl && (out || used);
      if (out != run->live_out[l] || inn != run->live_in[l]) {
        run->live_out[l] = out;
        run->live_in[l] = inn;
        again = true;
      }
    }
  }
}

/* Incoming edges of the region per block, as (predecessor, successor slot): `start` has nb + 1
 * entries, the edges of block l are `edge[start[l]..start[l + 1]]`. */
static void lu_incoming(LuRun *run, uint32_t **start, uint64_t **edge) {
  const LuCtx *x = run->x;
  const uint32_t nb = run->r.nb;
  uint32_t *st = lu_zeroed(run->ca, (size_t)nb + 2, sizeof(uint32_t));
  for (uint32_t p = 0; p < nb; p++) {
    const MirTerm *t = &x->f->blocks.ptr[run->r.order[p]].term;
    for (uint32_t s = 0; s < mir_term_ntargets(t); s++) {
      const uint32_t sl = lu_local(x, mir_term_target_const(t, s)->block);
      if (sl != MIR_NONE) {
        st[sl + 1]++;
      }
    }
  }
  for (uint32_t l = 0; l < nb; l++) {
    st[l + 1] += st[l];
  }
  uint32_t *fill = lu_zeroed(run->ca, (size_t)nb + 1, sizeof(uint32_t));
  __builtin_memcpy(fill, st, sizeof(uint32_t) * nb);
  uint64_t *e = lu_zeroed(run->ca, (size_t)st[nb] + 1, sizeof(uint64_t));
  for (uint32_t p = 0; p < nb; p++) {
    const MirTerm *t = &x->f->blocks.ptr[run->r.order[p]].term;
    for (uint32_t s = 0; s < mir_term_ntargets(t); s++) {
      const uint32_t sl = lu_local(x, mir_term_target_const(t, s)->block);
      if (sl != MIR_NONE) {
        e[fill[sl]++] = ((uint64_t)p << 32) | s;
      }
    }
  }
  *start = st;
  *edge = e;
}

/* Forward: blocks where `v` is owned on entry and not consumed. */
static void lu_ownership(LuRun *run) {
  const LuCtx *x = run->x;
  const uint32_t nb = run->r.nb;
  run->owned_in = lu_zeroed(run->ca, nb, sizeof(bool));
  run->owned_out = lu_zeroed(run->ca, nb, sizeof(bool));
  run->consumed = lu_zeroed(run->ca, nb, sizeof(bool));
  for (uint32_t l = 0; l < nb; l++) {
    const uint32_t bi = run->r.order[l];
    run->consumed[l] = x->cons_gen[bi] == x->gen || lu_ret_of(x->f, bi, run->v);
  }
  run->owned_out[run->dl] = !run->consumed[run->dl] && x->drop_gen[run->db] != x->gen;
  uint32_t *start;
  uint64_t *edge;
  lu_incoming(run, &start, &edge);
  for (bool again = true; again;) {
    again = false;
    for (uint32_t l = 0; l < nb; l++) {
      bool inn = false;
      for (uint32_t k = start[l]; l != run->dl && !inn && k < start[l + 1]; k++) {
        const uint32_t p = (uint32_t)(edge[k] >> 32), si = (uint32_t)edge[k];
        inn = run->owned_out[p] && !lu_edge_consumes(x->f, run->r.order[p], si, run->v);
      }
      const bool out = (inn || l == run->dl) && !run->consumed[l] &&
              x->drop_gen[run->r.order[l]] != x->gen;
      if (inn != run->owned_in[l] || out != run->owned_out[l]) {
        run->owned_in[l] = inn;
        run->owned_out[l] = out;
        again = true;
      }
    }
  }
}


/* Where block `l` of the region ends the life of `v`; false when it needs no drop in the block. */
static bool lu_place_in_block(const LuRun *run, uint32_t l, LuPlace *out) {
  const uint32_t bi = run->r.order[l];
  const uint8_t tk = run->x->f->blocks.ptr[bi].term.kind;
  if (tk == MT_FAULT || tk == MT_UNREACHABLE) {
    return false;
  }
  /* After the last use (or the definition) in this block. A block with no use and no
   * definition is entered with `v` owned only from predecessors that left it live; their
   * edges place the drop. */
  if (run->r.has_last[l]) {
    *out = (LuPlace){bi, run->r.last[l]};
    return true;
  }
  if (bi != run->db) {
    return false;
  }
  *out = (LuPlace){bi, run->di == MIR_NONE ? lu_start() : lu_at(run->di)};
  return true;
}

static void lu_plan(const LuRun *run, LuPlan *plan) {
  const LuCtx *x = run->x;
  uint32_t total_succ = 0;
  for (uint32_t l = 0; l < run->r.nb; l++) {
    total_succ += mir_term_ntargets(&x->f->blocks.ptr[run->r.order[l]].term);
  }
  plan->place = MS_ARENA_NEW_ARRAY(run->ca, LuPlace, (size_t)run->r.nb + 1);
  plan->edges = MS_ARENA_NEW_ARRAY(run->ca, uint64_t, (size_t)total_succ + 1);
  for (uint32_t l = 0; l < run->r.nb; l++) {
    const uint32_t bi = run->r.order[l];
    const bool in_region = l == run->dl || (run->owned_in[l] && run->live_in[l]);
    if (!in_region || run->consumed[l]) {
      continue;
    }
    if (!run->live_out[l]) {
      LuPlace at;
      if (lu_place_in_block(run, l, &at)) {
        plan->place[plan->nplace++] = at;
      }
      continue;
    }
    const MirTerm *t = &x->f->blocks.ptr[bi].term;
    for (uint32_t s = 0; s < mir_term_ntargets(t); s++) {
      /* A successor outside the region reaches no use of the family. */
      const uint32_t sl = lu_local(x, mir_term_target_const(t, s)->block);
      const bool live_next = sl != MIR_NONE && run->live_in[sl];
      if (!live_next && !lu_edge_consumes(x->f, bi, s, run->v)) {
        plan->edges[plan->nedges++] = ((uint64_t)bi << 32) | s;
      }
    }
  }
}

/* Moves the drops of `v`; false when the candidate is left as it was. `di` is the defining
 * instruction, MIR_NONE for a block parameter. */
bool lu_candidate(LuCtx *x, MirValue v, uint32_t db, uint32_t di) {
  MsArena ca = ms_arena_new();
  LuRun run = {.x = x, .ca = &ca, .v = v, .db = db, .di = di};
  bool result = false;
  x->gen++;
  lu_fit(x);
  lu_family(x, &ca, &run.fam, v, di == MIR_NONE ? db : MIR_NONE);
  if (!lu_leaks(&run)) {
    lu_scan_drops(&run);
  }
  if (run.nexisting > 0) {
    LuPlan plan = {0};
    lu_walk_region(&run);
    lu_fill_uses(&run);
    lu_liveness(&run);
    lu_ownership(&run);
    lu_plan(&run, &plan);
    /* Apply: type the removed drops and the new ones. */
    for (uint32_t k = 0; k < run.nexisting; k++) {
      x->removed[lu_use_block(run.existing[k])][lu_use_inst(run.existing[k])] = true;
    }
    for (uint32_t k = 0; k < plan.nplace; k++) {
      lu_insert_pending(x, plan.place[k].block, plan.place[k].pos, v);
    }
    for (uint32_t k = 0; k < plan.nedges; k++) {
      lu_add_edge(x, v, (uint32_t)(plan.edges[k] >> 32), (uint32_t)plan.edges[k]);
    }
    result = true;
  }
  ms_arena_free(&ca);
  return result;
}

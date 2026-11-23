/* unwind: the liveness walk that plans where registrations go. Port of `analyze` and the hole
 * helpers in unwind.rs. */
#include "compiler/mir/mir_unwind.h"

static bool uw_leaf_extern(const MirModule *m, uint32_t e) {
  return m->externs.ptr[e].noreturn || m->externs.ptr[e].leaf;
}

/* Whether `inst` can reach a cancellation point. */
static bool uw_parks_at(const UwCx *cx, const MirInst *inst) {
  switch ((MirOp)inst->op) {
  case MOP_Poll:
  case MOP_CallInd:
  case MOP_CallMethod:
    return true;
  case MOP_CallRt:
    return inst->imm.tag == MI_EXT && !uw_leaf_extern(cx->m, inst->imm.a);
  case MOP_Call:
    return inst->imm.tag != MI_FUNC || inst->imm.a >= cx->nfuncs0 || cx->parks[inst->imm.a];
  default:
    return false;
  }
}

/* Whether `inst` can reach a cancellation point or fault. */
bool uw_exits_at(const UwCx *cx, const MirInst *inst) {
  if (uw_parks_at(cx, inst)) {
    return true;
  }
  if (inst->op == MOP_Call) {
    return inst->imm.tag != MI_FUNC || inst->imm.a >= cx->nfuncs0 || cx->faults[inst->imm.a];
  }
  return (mir_op_info[inst->op].effects & MIR_E_FAULTS) != 0;
}

uint32_t uw_hole_step(uint32_t open, MirOp op, const MirInst *next) {
  switch (op) {
  case MOP_MoveOut:
    if (next != NULL && next->op == MOP_TypeRelease) {
      return open;
    }
    return open + 1 < 8 ? open + 1 : 8;
  case MOP_AltTake: /* the payload leaves its alternative; `alt.release` frees what is left */
    return open + 1 < 8 ? open + 1 : 8;
  case MOP_TypeFill:
  case MOP_ListFill:
  case MOP_AltRelease:
    return open > 0 ? open - 1 : 0;
  default:
    return open;
  }
}

static const MirInst *uw_next_inst(const MirBlockData *blk, uint32_t k) {
  return k + 1 < blk->insts.len ? &blk->insts.ptr[k + 1] : NULL;
}

/* Moves-out of a projection that are not yet filled back, at the start of each block. The count
 * only matters as zero or not, and a merge keeps the larger one. */
uint32_t *uw_hole_states(UwCx *cx, const MirFunc *f) {
  uint32_t *at = MS_ARENA_NEW_ARRAY(&cx->fn, uint32_t, f->blocks.len);
  __builtin_memset(at, 0, sizeof(uint32_t) * f->blocks.len);
  for (bool changed = true; changed;) {
    changed = false;
    MirBlock *order = NULL;
    const uint32_t norder = mir_rpo(&cx->fn, f, &order);
    for (uint32_t oi = 0; oi < norder; oi++) {
      const MirBlockData *blk = &f->blocks.ptr[order[oi]];
      uint32_t open = at[order[oi]];
      for (uint32_t k = 0; k < blk->insts.len; k++) {
        open = uw_hole_step(open, (MirOp)blk->insts.ptr[k].op, uw_next_inst(blk, k));
      }
      for (uint32_t t = 0; t < mir_term_ntargets(&blk->term); t++) {
        const MirBlock to = mir_term_target_const(&blk->term, t)->block;
        if (at[to] < open) {
          at[to] = open;
          changed = true;
        }
      }
    }
  }
  return at;
}

/* The blocks the cleanup stack may stay open across: no scope open or close, no discard and no
 * moved-out projection, which a registration across would break. */
bool *uw_plain_blocks(UwCx *cx, const MirFunc *f, const uint32_t *holes) {
  bool *plain = MS_ARENA_NEW_ARRAY(&cx->fn, bool, f->blocks.len);
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    plain[bi] = holes[bi] == 0;
    for (uint32_t k = 0; k < f->blocks.ptr[bi].insts.len && plain[bi]; k++) {
      const MirInst *i = &f->blocks.ptr[bi].insts.ptr[k];
      plain[bi] = !(i->op == MOP_CleanupPush || i->op == MOP_CleanupRun ||
             i->op == MOP_MoveOut ||
             (i->op == MOP_CallRt && i->imm.tag == MI_EXT && i->imm.a == cx->discard));
    }
  }
  return plain;
}

/* ---- hole owners ---- */

typedef struct UwHoleIn {
  UwHash named; /* the owners named by the moves-out still open */
  bool unnamed; /* some open one is not named, so no live value may be covered */
  uint32_t open;
} UwHoleIn;

/* The owner each projection value (`type.get`, `alt.get`) was read from. */
static UwHash uw_field_defs(MsArena *a, const MirFunc *f) {
  UwHash defs = {0};
  UW_INSTS(f, b, i, inst) {
    if ((inst->op == MOP_TypeGet || inst->op == MOP_AltGet) && inst->res != MIR_NONE &&
      inst->nargs > 0) {
      (void)uh_put(a, &defs, inst->res, inst->args[0]);
    }
  }
  return defs;
}

static bool uw_hole_base(const UwHash *defs, const MirInst *inst, uint32_t *base) {
  uint64_t v = 0;
  if (inst->op == MOP_AltTake && inst->nargs > 0) { /* the alternative itself is the owner */
    *base = inst->args[0];
    return true;
  }
  if (inst->nargs == 0 || !uh_get(defs, inst->args[0], &v)) {
    return false;
  }
  *base = (uint32_t)v;
  return true;
}

static bool uw_hole_block(MsArena *a, const MirFunc *f, const UwHash *defs, uint32_t b,
             UwHoleIn *at) {
  const MirBlockData *blk = &f->blocks.ptr[b];
  UwHash named = uh_clone(a, &at[b].named);
  bool unnamed = at[b].unnamed, grew_any = false;
  uint32_t open = at[b].open;
  for (uint32_t k = 0; k < blk->insts.len; k++) {
    const uint32_t before = open;
    open = uw_hole_step(open, (MirOp)blk->insts.ptr[k].op, uw_next_inst(blk, k));
    uint32_t base = 0;
    if (open > before) {
      if (uw_hole_base(defs, &blk->insts.ptr[k], &base)) {
        (void)uh_put(a, &named, base, 0);
      } else {
        unnamed = true;
      }
    }
    if (open == 0) {
      named = (UwHash){0};
      unnamed = false;
    }
  }
  for (uint32_t t = 0; t < mir_term_ntargets(&blk->term); t++) {
    UwHoleIn *slot = &at[mir_term_target_const(&blk->term, t)->block];
    bool grew = (unnamed && !slot->unnamed) || open > slot->open;
    for (uint32_t i = 0; i < named.cap && !grew; i++) {
      grew = named.used[i] && !uh_has(&slot->named, named.key[i]);
    }
    if (grew) {
      for (uint32_t i = 0; i < named.cap; i++) {
        if (named.used[i]) {
          (void)uh_put(a, &slot->named, named.key[i], 0);
        }
      }
      slot->unnamed = slot->unnamed || unnamed;
      slot->open = open > slot->open ? open : slot->open;
      grew_any = true;
    }
  }
  return grew_any;
}

/* At the start of each block: the owners named by the moves-out still open, and whether some open
 * one is not named (so no live value may be covered). */
static UwHoleIn *uw_hole_owners(UwCx *cx, const MirFunc *f) {
  MsArena *a = &cx->fn;
  UwHoleIn *at = MS_ARENA_NEW_ARRAY(a, UwHoleIn, f->blocks.len);
  __builtin_memset(at, 0, sizeof(UwHoleIn) * f->blocks.len);
  const UwHash defs = uw_field_defs(a, f);
  for (bool changed = true; changed;) {
    changed = false;
    MirBlock *order = NULL;
    const uint32_t norder = mir_rpo(a, f, &order);
    for (uint32_t oi = 0; oi < norder; oi++) {
      changed = uw_hole_block(a, f, &defs, order[oi], at) || changed;
    }
  }
  return at;
}

/* ---- analyze ---- */

typedef struct UwBlk {
  const UwFacts *fa;
  UwWalk *w;
  uint32_t bi;
  const MirBlockData *blk;
  OwnerSet live;
  bool has_reach;
  OwnerSet reach;
  bool opened_by_discard;
  uint32_t open;
  UwHash holed;
  bool unnamed;
  const UwHash *defs;
} UwBlk;

static MsArena *uw_an_arena(const UwBlk *s) { return &s->fa->cx->fn; }

/* A live set with the values a loop registration already covers left out. */
static OwnerSet uw_coverable(const UwBlk *s, const OwnerSet *live) {
  OwnerSet out = *live;
  const UwHash *hoisted = &s->fa->hoisted[s->bi];
  for (uint32_t i = 0; i < hoisted->cap; i++) {
    if (hoisted->used[i]) {
      (void)owner_remove(uw_an_arena(s), &out, (uint32_t)hoisted->key[i]);
    }
  }
  return out;
}

static void uw_born(const UwBlk *s, OwnerSet *live, uint32_t v) {
  if (!uh_has(s->fa->closed_by_with, v)) {
    owner_insert(uw_an_arena(s), live, v);
  }
}

static bool uw_owned_def(const UwFacts *fa, MirValue v) { return v < fa->nowned && fa->owned_def[v]; }

static bool uw_is_cell(const UwBlk *s, MirValue v) { return uh_has(&s->fa->cx->cells, v); }

static bool uw_drops_nonplain(const UwBlk *s, const MirInst *inst) {
  return inst->op == MOP_Drop && inst->nargs > 0 &&
     !mir_drops_plain_memory(s->fa->cx->m, mir_value_ty(s->fa->f, inst->args[0]));
}

/* A call that ends its block in `unreachable` (a noreturn runtime call). */
static bool uw_noreturn_tail(const UwBlk *s, const MirInst *inst, uint32_t k) {
  return inst->op == MOP_CallRt && k + 1 == s->blk->insts.len && s->blk->term.kind == MT_UNREACHABLE;
}

/* Removes what `inst` consumes or hands to a callee that covers it itself. */
static void uw_an_consume(UwBlk *s, const MirInst *inst) {
  const UwFacts *fa = s->fa;
  MsArena *a = uw_an_arena(s);
  MirMode *modes = MS_ARENA_NEW_ARRAY(a, MirMode, inst->nargs ? inst->nargs : 1);
  mir_arg_modes(fa->cx->m, fa->f, inst, modes);
  for (uint32_t i = 0; i < inst->nargs; i++) {
    if (modes[i] != MM_MOVE || !uw_owned_def(fa, inst->args[i])) {
      continue;
    }
    (void)owner_remove(a, &s->live, inst->args[i]);
    /* The owner is gone, and with it the stand-in for its other fields. */
    for (uint32_t fk = 0; fk < 33; fk++) {
      uint64_t p = 0;
      if (uh_get(&fa->cx->holes, (uint64_t)inst->args[i] << 32 | fk, &p)) {
        (void)owner_remove(a, &s->live, (uint32_t)p);
      }
    }
  }
  uint64_t p = 0;
  if (inst->op == MOP_TypeFill && inst->imm.tag == MI_FIELD && inst->nargs > 0 &&
    uh_get(&fa->cx->holes, (uint64_t)inst->args[0] << 32 | inst->imm.b, &p)) {
    (void)owner_remove(a, &s->live, (uint32_t)p);
  }
  if (inst->op == MOP_AltTake && inst->nargs > 0) {
    /* The payload left the value: dropping the shell whole would free it a second time, so the shell
     * is not covered from here (it is only released, which an unwind may skip). */
    (void)owner_remove(a, &s->live, inst->args[0]);
  }
  if (inst->op == MOP_Take && inst->nargs > 0 && uw_is_cell(s, inst->args[0])) {
    (void)owner_remove(a, &s->live, inst->args[0]);
  }
  for (uint32_t i = 0; i < inst->nargs; i++) {
    if (uw_is_cell(s, inst->args[i]) && uw_hands_off(fa->cx, inst, i)) {
      (void)owner_remove(a, &s->live, inst->args[i]);
    }
  }
}

static void uw_event_push(UwBlk *s, uint32_t at, const OwnerSet *target) {
  UwWalk *w = s->w;
  const uint32_t bi = s->bi;
  if (w->nevents[bi] == w->cevents[bi]) {
    const uint32_t cap = w->cevents[bi] ? w->cevents[bi] * 2 : 4;
    UwEvent *grown = MS_ARENA_NEW_ARRAY(uw_an_arena(s), UwEvent, cap);
    if (w->nevents[bi] > 0) {
      __builtin_memcpy(grown, w->events[bi], sizeof(UwEvent) * w->nevents[bi]);
    }
    w->events[bi] = grown;
    w->cevents[bi] = cap;
  }
  w->events[bi][w->nevents[bi]++] = (UwEvent){at, *target};
}

static UwWindow *uw_plan_push(UwBlk *s, UwWindow win) {
  UwWalk *w = s->w;
  const uint32_t bi = s->bi;
  if (w->nplans[bi] == w->cplans[bi]) {
    const uint32_t cap = w->cplans[bi] ? w->cplans[bi] * 2 : 4;
    UwWindow *grown = MS_ARENA_NEW_ARRAY(uw_an_arena(s), UwWindow, cap);
    if (w->nplans[bi] > 0) {
      __builtin_memcpy(grown, w->plans[bi], sizeof(UwWindow) * w->nplans[bi]);
    }
    w->plans[bi] = grown;
    w->cplans[bi] = cap;
  }
  w->plans[bi][w->nplans[bi]] = win;
  return &w->plans[bi][w->nplans[bi]++];
}

static void uw_step_push(UwBlk *s, UwWindow *win, uint32_t at, const OwnerSet *target) {
  if (win->nsteps == win->csteps) {
    const uint32_t cap = win->csteps ? win->csteps * 2 : 4;
    UwStep *grown = MS_ARENA_NEW_ARRAY(uw_an_arena(s), UwStep, cap);
    if (win->nsteps > 0) {
      __builtin_memcpy(grown, win->steps, sizeof(UwStep) * win->nsteps);
    }
    win->steps = grown;
    win->csteps = cap;
  }
  win->steps[win->nsteps++] = (UwStep){at, *target};
}

/* Plans the registration around instruction `k`: extends the window that is open, or starts one. */
static void uw_an_window(UwBlk *s, const MirInst *inst, uint32_t k, bool discards) {
  MsArena *a = uw_an_arena(s);
  OwnerSet under = s->live;
  if (s->open > 0) {
    if (s->unnamed) {
      under = (OwnerSet){0};
    }
    for (uint32_t i = 0; i < s->holed.cap; i++) {
      if (s->holed.used[i]) {
        (void)owner_remove(a, &under, (uint32_t)s->holed.key[i]);
      }
    }
  }
  if (inst->op == MOP_CleanupPush || inst->op == MOP_CleanupRun) {
    /* A window across a hole would drop a half-emptied owner, and one across a scope open or
     * close would discard an entry that is not its own. */
    s->has_reach = false;
    return;
  }
  if ((owner_is_empty(&under) && !s->has_reach) ||
    !(uw_exits_at(s->fa->cx, inst) || uw_drops_nonplain(s, inst) ||
     uw_noreturn_tail(s, inst, k))) {
    return;
  }
  const OwnerSet drops = uw_coverable(s, &under);
  UwWindow *last = s->w->nplans[s->bi] ? &s->w->plans[s->bi][s->w->nplans[s->bi] - 1] : NULL;
  if (s->has_reach && last != NULL && owner_equal(&s->reach, &drops)) {
    last->last = k;
  } else if (s->has_reach && last != NULL && !s->opened_by_discard) {
    /* The live owners changed: the window follows them, so a value that died is discarded and
     * one born since is registered, and the owners that stay are not registered again. */
    last->last = k;
    uw_step_push(s, last, k, &drops);
    s->reach = drops;
  } else {
    s->has_reach = false;
    s->opened_by_discard = discards;
    if (!owner_is_empty(&drops)) {
      s->has_reach = true;
      s->reach = drops;
      (void)uw_plan_push(s, (UwWindow){.first = k, .last = k, .values = drops});
    }
  }
}

/* An instruction that moved a field out opens a hole in its owner: the owner's other fields stay
 * covered through their stand-in. */
static void uw_an_open_hole(UwBlk *s, const MirInst *inst) {
  uint32_t base = 0;
  if (!uw_hole_base(s->defs, inst, &base)) {
    s->unnamed = true;
    s->has_reach = false;
    return;
  }
  (void)uh_put(uw_an_arena(s), &s->holed, base, 0);
  uint64_t named = 0, pseudo = 0;
  if (inst->nargs > 0 && uh_get(&s->fa->cx->proj, inst->args[0], &named) &&
    uh_get(&s->fa->cx->holes, (uint64_t)base << 32 | (uint32_t)named, &pseudo) &&
    owner_contains(&s->live, base)) {
    owner_insert(uw_an_arena(s), &s->live, (uint32_t)pseudo);
  }
  s->has_reach = false;
}

static void uw_an_births(UwBlk *s, const MirInst *inst) {
  const UwFacts *fa = s->fa;
  if (inst->op == MOP_Put && inst->nargs > 0 && uw_is_cell(s, inst->args[0])) {
    uw_born(s, &s->live, inst->args[0]);
  }
  for (uint32_t i = 0; i < inst->nargs; i++) {
    if (uw_is_cell(s, inst->args[i]) && uw_hands_off(fa->cx, inst, i)) {
      uw_born(s, &s->live, inst->args[i]);
    }
  }
  if (inst->res != MIR_NONE && uw_owned_def(fa, inst->res)) {
    uw_born(s, &s->live, inst->res);
  }
}

static void uw_an_inst(UwBlk *s, uint32_t k) {
  const MirInst *inst = &s->blk->insts.ptr[k];
  const bool discards = inst->op == MOP_CallRt && inst->imm.tag == MI_EXT &&
             inst->imm.a == s->fa->cx->discard;
  if (discards) {
    s->has_reach = false; /* the discard may pop entries the window pushed */
  }
  uw_an_consume(s, inst);
  if (s->w->plain[s->bi] && (uw_exits_at(s->fa->cx, inst) || uw_drops_nonplain(s, inst) ||
               uw_noreturn_tail(s, inst, k))) {
    const OwnerSet target = uw_coverable(s, &s->live);
    const uint32_t n = s->w->nevents[s->bi];
    if (n == 0 || !owner_equal(&s->w->events[s->bi][n - 1].owners, &target)) {
      uw_event_push(s, k, &target);
    }
  }
  uw_an_window(s, inst, k, discards);
  const uint32_t before = s->open;
  s->open = uw_hole_step(s->open, (MirOp)inst->op, uw_next_inst(s->blk, k));
  if (s->open > before) {
    uw_an_open_hole(s, inst);
  }
  if (s->open == 0) {
    s->holed = (UwHash){0};
    s->unnamed = false;
  }
  uw_an_births(s, inst);
}

/* The end of a block: values to register before a terminating fault, and the entry sets of its
 * successors. */
static void uw_an_edges(UwBlk *s) {
  const UwFacts *fa = s->fa;
  MsArena *a = uw_an_arena(s);
  UwWalk *w = s->w;
  if (s->open == 0 && s->blk->term.kind == MT_FAULT) {
    const OwnerSet target = uw_coverable(s, &s->live);
    w->at_fault[s->bi] = (MirValue *)owner_to_vec(a, &target, &w->nat_fault[s->bi]);
    if (w->plain[s->bi]) {
      uw_event_push(s, (uint32_t)s->blk->insts.len, &target);
    }
  }
  for (uint32_t k = 0; k < mir_term_ntargets(&s->blk->term); k++) {
    const MirTarget *t = mir_term_target_const(&s->blk->term, k);
    const MirBlockData *dest = &fa->f->blocks.ptr[t->block];
    OwnerSet after = s->live;
    for (uint32_t j = 0; j < t->nargs && j < dest->params.len; j++) {
      if (dest->params.ptr[j].mode == MM_MOVE && uw_owned_def(fa, t->args[j])) {
        (void)owner_remove(a, &after, t->args[j]);
      }
    }
    if (!w->has[t->block]) {
      w->entry[t->block] = after;
      w->has[t->block] = true;
    } else if (!w->done[t->block]) {
      /* Edges that disagree on what is owned (a value one path made): only what every path owns is
       * covered, since a value made on one path is not defined where they meet. */
      uint32_t count = 0;
      const uint32_t *held = owner_to_vec(a, &w->entry[t->block], &count);
      for (uint32_t i = 0; i < count; i++) {
        if (!owner_contains(&after, held[i])) {
          (void)owner_remove(a, &w->entry[t->block], held[i]);
        }
      }
    }
  }
}

static bool uw_an_start(UwBlk *s) {
  const UwFacts *fa = s->fa;
  if (s->w->has[s->bi]) {
    s->live = s->w->entry[s->bi];
  } else if (s->bi == 0) {
    s->live = (OwnerSet){0};
  } else {
    return false;
  }
  for (uint32_t i = 0; i < s->blk->params.len; i++) {
    const MirValue v = s->blk->params.ptr[i].value;
    if (uw_owned_def(fa, v) || (s->bi == 0 && uw_is_cell(s, v))) {
      uw_born(s, &s->live, v);
    }
  }
  return true;
}

/* Walks `f` in reverse post-order tracking which owned values are live, and plans a registration
 * around each instruction that can park or fault. */
UwWalk uw_analyze(const UwFacts *fa) {
  UwCx *cx = fa->cx;
  const MirFunc *f = fa->f;
  MsArena *a = &cx->fn;
  const uint32_t n = (uint32_t)f->blocks.len;
  UwWalk w = {.entry = MS_ARENA_NEW_ARRAY(a, OwnerSet, n), .has = MS_ARENA_NEW_ARRAY(a, bool, n),
        .done = MS_ARENA_NEW_ARRAY(a, bool, n),
        .plans = MS_ARENA_NEW_ARRAY(a, UwWindow *, n), .nplans = MS_ARENA_NEW_ARRAY(a, uint32_t, n),
        .cplans = MS_ARENA_NEW_ARRAY(a, uint32_t, n), .at_fault = MS_ARENA_NEW_ARRAY(a, MirValue *, n),
        .nat_fault = MS_ARENA_NEW_ARRAY(a, uint32_t, n), .events = MS_ARENA_NEW_ARRAY(a, UwEvent *, n),
        .nevents = MS_ARENA_NEW_ARRAY(a, uint32_t, n), .cevents = MS_ARENA_NEW_ARRAY(a, uint32_t, n)};
  __builtin_memset(w.entry, 0, sizeof(OwnerSet) * n);
  __builtin_memset(w.has, 0, n);
  __builtin_memset(w.done, 0, n);
  __builtin_memset(w.plans, 0, sizeof(UwWindow *) * n);
  __builtin_memset(w.nplans, 0, sizeof(uint32_t) * n);
  __builtin_memset(w.cplans, 0, sizeof(uint32_t) * n);
  __builtin_memset(w.at_fault, 0, sizeof(MirValue *) * n);
  __builtin_memset(w.nat_fault, 0, sizeof(uint32_t) * n);
  __builtin_memset(w.events, 0, sizeof(UwEvent *) * n);
  __builtin_memset(w.nevents, 0, sizeof(uint32_t) * n);
  __builtin_memset(w.cevents, 0, sizeof(uint32_t) * n);
  w.plain = uw_plain_blocks(cx, f, fa->holes);
  const UwHoleIn *hole_in = uw_hole_owners(cx, f);
  const UwHash defs = uw_field_defs(a, f);
  MirBlock *order = NULL;
  const uint32_t norder = mir_rpo(a, f, &order);
  for (uint32_t oi = 0; oi < norder; oi++) {
    UwBlk s = {.fa = fa, .w = &w, .bi = order[oi], .blk = &f->blocks.ptr[order[oi]], .defs = &defs};
    if (!uw_an_start(&s)) {
      continue;
    }
    w.done[s.bi] = true;
    s.open = fa->holes[s.bi];
    s.holed = uh_clone(a, &hole_in[s.bi].named);
    s.unnamed = hole_in[s.bi].unnamed;
    for (uint32_t k = 0; k < s.blk->insts.len; k++) {
      uw_an_inst(&s, k);
    }
    uw_an_edges(&s);
  }
  return w;
}

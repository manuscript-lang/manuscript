/* Twin merging: two blocks that run the same operations merge into one, and a `select` picks what
 * differs.
 *
 *     A: br_if c, B1(), B2()                      A: s = select c, x, y;  br M(s)
 *     B1: r = list.set.u l, k, x ; br J(r)   =>   M(v): r = list.set.u l, k, v ; br J(r)
 *     B2: r = list.set.u l, k, y ; br J(r)
 *
 * Arms that differ only in an operand (`if a < b { dst[k] = b; j += 1 } else { dst[k] = a; i += 1 }`) stay
 * two branches even when each holds checked stores, so a data-dependent condition mispredicts where C
 * would use a conditional move. Two blocks are twins when they have the same parameters, operations,
 * terminator kind and successors. Each operand pair is the same value, the same position in each
 * block, or a scalar that differs: external scalars become block parameters filled on each side's
 * edges, and a scalar internal to one side is chosen by a `side` flag. Merging runs bottom-up: fault
 * blocks first, then the checks that lead to them, then the arms. A branch whose two targets became
 * one block turns its differing arguments into selects. Blocks with a back edge into them, or whose
 * successor dominates them (loops), are left alone. */

#include "compiler/mir/mir_analysis.h"
#include "compiler/opt/opt_pass.h"
#include "base/safe.h"
#include "base/sort.h"

enum { TW_MAX_INSTS = 48, TW_MAX_VARS = 16, TW_MAX_PLANS = 8, TW_MAX_DEPTH = 3 };

/* A parameter added to a merged block, with what each side's edges pass. */
typedef struct TwExtra {
  MirValue param, on_x, on_y;
} TwExtra;

/* A resolved differing operand pair. */
typedef struct TwVar {
  MirValue x, y, value;
} TwVar;

/* How one pair of twin blocks merges: X's block keeps the merged operations, Y's block dies. */
typedef struct TwPlan {
  MirBlock x, y;
  MirBlock xpred, ypred;           /* the one block that branches to X, and to Y */
  const MirBlock *xpreds, *ypreds; /* the same as lists */
  uint32_t nxpreds, nypreds;
  OptInstVec out;
  MirTerm term;
  TwExtra extras[TW_MAX_VARS];
  uint32_t nextras;
  TwVar vars[TW_MAX_VARS];
  uint32_t nvars;
  MirValue side; /* the flag parameter (true on X's edges), MIR_NONE until needed */
  int child[2];  /* per terminator target: the plan of the twin successors, -1 for a shared one */
} TwPlan;

typedef struct Twins {
  MirModule *m;
  MirFunc *f;
  MsArena *arena;
  const MirBlock *owner; /* per value: the block defining it, MIR_NONE for the entry's parameters */
  const uint32_t *pos;   /* per value: parameter index, or parameters + instruction index */
  uint32_t nvalues;
  const MirDomTree *dom;
  const uint32_t *uses;
  uint32_t *inside; /* scratch per value */
  const uint32_t *npreds;
  TwPlan plans[TW_MAX_PLANS];
  uint32_t nplans;
} Twins;

static bool dominates(const Twins *t, MirBlock a, MirBlock b) {
  return a == b || mir_tree_dominates(t->dom, a, b);
}

static MirBlock tw_owner(const Twins *t, MirValue v) {
  return v < t->nvalues ? t->owner[v] : MIR_NONE - 1;
}

static bool tw_internal(const Twins *t, MirValue v, MirBlock b) {
  return v < t->nvalues && t->owner[v] == b;
}

/* The value at position `p` of block X. */
static MirValue x_at(const Twins *t, const TwPlan *p, uint32_t at) {
  const MirBlockData *b = &t->f->blocks.ptr[p->x];
  const uint32_t np = (uint32_t)b->params.len;
  return at < np ? b->params.ptr[at].value : b->insts.ptr[at - np].res;
}

static bool tw_const(const Twins *t, MirValue v) {
  if (v >= t->nvalues || t->owner[v] == MIR_NONE) {
    return false;
  }
  const MirBlockData *b = &t->f->blocks.ptr[t->owner[v]];
  const uint32_t np = (uint32_t)b->params.len;
  if (t->pos[v] < np) {
    return false;
  }
  const uint8_t op = b->insts.ptr[t->pos[v] - np].op;
  return op == MOP_IConst || op == MOP_FConst || op == MOP_BConst;
}

/* Whether `v` (outside both blocks) reaches every block of `preds`. */
static bool tw_reaches(const Twins *t, MirValue v, const MirBlock *preds, uint32_t n) {
  const MirBlock def = tw_owner(t, v);
  for (uint32_t i = 0; i < n; i++) {
    if (t->dom->idom[preds[i]] == MIR_NONE || (def != MIR_NONE && !dominates(t, def, preds[i]))) {
      return false;
    }
  }
  return true;
}

static MirValue new_param(Twins *t, TwPlan *p, MirTy ty, MirValue on_x, MirValue on_y) {
  const MirValue v = mir_new_value(t->f, ty);
  p->extras[p->nextras++] = (TwExtra){v, on_x, on_y};
  return v;
}

static MirValue ensure_side(Twins *t, TwPlan *p) {
  if (p->side == MIR_NONE) {
    p->side = mir_new_value(t->f, MIR_BOOL);
  }
  return p->side;
}

/* The merged block's value for a pair of operands; MIR_NONE when the pair cannot be merged. `at` is
 * the position the use takes in the block, `operand` false for a branch argument. */
static MirValue resolve(Twins *t, TwPlan *p, MirValue x, MirValue y, uint32_t at, bool operand) {
  const bool ix = tw_internal(t, x, p->x), iy = tw_internal(t, y, p->y);
  if (ix && iy && t->pos[x] == t->pos[y]) {
    return x;
  }
  if (!ix && !iy && x == y) {
    return x;
  }
  const MirTy ty = mir_value_ty(t->f, x);
  if (ty != mir_value_ty(t->f, y) || !mir_is_scalar(t->m, ty) || p->nvars == TW_MAX_VARS ||
    p->nextras + 2 > TW_MAX_VARS || (operand && (tw_const(t, x) || tw_const(t, y)))) {
    return MIR_NONE;
  }
  for (uint32_t i = 0; i < p->nvars; i++) {
    if (p->vars[i].x == x && p->vars[i].y == y) {
      return p->vars[i].value;
    }
  }
  MirValue value;
  if (!ix && !iy) {
    if (tw_owner(t, x) == p->y || tw_owner(t, y) == p->x) {
      return MIR_NONE;
    }
    value = new_param(t, p, ty, x, y);
  } else {
    /* A value of one block mixed with another: choose by the side flag. */
    MirValue xm = x, ym = y;
    if (iy) {
      if (t->pos[y] >= at) {
        return MIR_NONE;
      }
      ym = x_at(t, p, t->pos[y]);
    } else if (tw_owner(t, y) == p->x || !tw_reaches(t, y, p->xpreds, p->nxpreds)) {
      return MIR_NONE;
    } else {
      ym = new_param(t, p, ty, y, y);
    }
    if (!ix) {
      if (tw_owner(t, x) == p->y || !tw_reaches(t, x, p->ypreds, p->nypreds)) {
        return MIR_NONE;
      }
      xm = new_param(t, p, ty, x, x);
    }
    value = mir_new_value(t->f, ty);
    const MirValue args[3] = {ensure_side(t, p), xm, ym};
    const MirBlockData *bx = &t->f->blocks.ptr[p->x];
    opt_inst_vec_push(t->arena, &p->out,
              &(MirInst){.args = mir_args_copy(t->m, args, 3), .op = MOP_Select, .res = value, .nargs = 3,
                   .loc = bx->insts.len ? bx->insts.ptr[0].loc : bx->term_loc});
  }
  p->vars[p->nvars++] = (TwVar){x, y, value};
  return value;
}

static bool exact_bit(const MirFunc *f, MirValue v) {
  return (v >> 6) < f->nexact && ((f->exact[v >> 6] >> (v & 63)) & 1) != 0;
}

/* Whether the two blocks have the same parameters, operations and terminator kind. */
static bool same_shape(const Twins *t, MirBlock x, MirBlock y) {
  const MirBlockData *bx = &t->f->blocks.ptr[x], *by = &t->f->blocks.ptr[y];
  if (bx->params.len != by->params.len || bx->insts.len != by->insts.len || bx->insts.len > TW_MAX_INSTS ||
    bx->term.kind != by->term.kind || bx->term.kind == MT_SWITCH) {
    return false;
  }
  for (uint32_t i = 0; i < bx->params.len; i++) {
    if (bx->params.ptr[i].mode != by->params.ptr[i].mode ||
      mir_value_ty(t->f, bx->params.ptr[i].value) != mir_value_ty(t->f, by->params.ptr[i].value)) {
      return false;
    }
  }
  for (uint32_t i = 0; i < bx->insts.len; i++) {
    const MirInst *a = &bx->insts.ptr[i], *b = &by->insts.ptr[i];
    if (a->op != b->op || a->nargs != b->nargs || (a->res == MIR_NONE) != (b->res == MIR_NONE) ||
      !opt_imm_eq(&a->imm, &b->imm)) {
      return false;
    }
    if (a->res != MIR_NONE && (mir_value_ty(t->f, a->res) != mir_value_ty(t->f, b->res) ||
                  exact_bit(t->f, a->res) != exact_bit(t->f, b->res))) {
      return false;
    }
  }
  const MirTerm *ta = &bx->term, *tb = &by->term;
  return ta->fault == tb->fault && (ta->value == MIR_NONE) == (tb->value == MIR_NONE) &&
       mir_term_ntargets(ta) == mir_term_ntargets(tb);
}

/* Plans the merge of twin blocks X and Y, reached only from `xpred` and `ypred`; the index of the plan, or -1.
 * A successor that only X (or only Y) reaches merges with its twin; any other successor must be
 * shared. */
static int plan_pair(Twins *t, MirBlock x, MirBlock y, MirBlock xpred, MirBlock ypred, uint32_t depth) {
  if (x == y || x == 0 || y == 0 || t->nplans == TW_MAX_PLANS || !same_shape(t, x, y)) {
    return -1;
  }
  const MirBlockData *bx = &t->f->blocks.ptr[x], *by = &t->f->blocks.ptr[y];
  int child[2] = {-1, -1};
  const uint32_t ntargets = mir_term_ntargets(&bx->term);
  for (uint32_t k = 0; k < ntargets; k++) {
    const MirTarget *a = mir_term_target_const(&bx->term, k), *b = mir_term_target_const(&by->term, k);
    if (a->nargs != b->nargs || a->block == x || a->block == y || b->block == x || b->block == y) {
      return -1;
    }
    if (a->block == b->block) {
      if (dominates(t, a->block, x) || dominates(t, a->block, y)) {
        return -1;
      }
      continue;
    }
    if (depth >= TW_MAX_DEPTH || t->npreds[a->block] != 1 || t->npreds[b->block] != 1) {
      return -1;
    }
    child[k] = plan_pair(t, a->block, b->block, x, y, depth + 1);
    if (child[k] < 0) {
      return -1;
    }
  }
  const uint32_t id = t->nplans++;
  TwPlan *p = &t->plans[id];
  *p = (TwPlan){.x = x, .y = y, .xpred = xpred, .ypred = ypred, .nxpreds = 1, .nypreds = 1, .side = MIR_NONE,
         .child = {child[0], child[1]}};
  p->xpreds = &p->xpred;
  p->ypreds = &p->ypred;
  return (int)id;
}

/* Builds the operations, terminator and parameters of plan `id`; false when an operand pair cannot
 * be merged. Children are built first: the parent passes their extra parameters on its edges. */
static bool build_plan(Twins *t, uint32_t id) {
  TwPlan *p = &t->plans[id];
  const MirBlockData *bx = &t->f->blocks.ptr[p->x], *by = &t->f->blocks.ptr[p->y];
  const uint32_t np = (uint32_t)bx->params.len;
  for (uint32_t k = 0; k < 2; k++) {
    if (p->child[k] >= 0 && !build_plan(t, (uint32_t)p->child[k])) {
      return false;
    }
  }
  for (uint32_t i = 0; i < bx->insts.len; i++) {
    MirInst inst = bx->insts.ptr[i];
    inst.args = MS_ARENA_NEW_ARRAY(&t->m->arena, MirValue, (size_t)inst.nargs + 1);
    for (uint32_t k = 0; k < inst.nargs; k++) {
      inst.args[k] = resolve(t, p, bx->insts.ptr[i].args[k], by->insts.ptr[i].args[k], np + i, true);
      if (inst.args[k] == MIR_NONE) {
        return false;
      }
    }
    opt_inst_vec_push(t->arena, &p->out, &inst);
  }
  const uint32_t at = np + (uint32_t)bx->insts.len;
  p->term = bx->term;
  if (p->term.value != MIR_NONE && (p->term.kind == MT_CONDBR || p->term.kind == MT_RET)) {
    p->term.value = resolve(t, p, bx->term.value, by->term.value, at, true);
    if (p->term.value == MIR_NONE) {
      return false;
    }
  }
  for (uint32_t k = 0; k < mir_term_ntargets(&p->term); k++) {
    const MirTarget *a = mir_term_target_const(&bx->term, k), *b = mir_term_target_const(&by->term, k);
    const TwPlan *c = p->child[k] >= 0 ? &t->plans[p->child[k]] : NULL;
    const uint32_t extra = c ? c->nextras + (c->side != MIR_NONE ? 1u : 0u) : 0u;
    MirTarget *tg = mir_term_target(&p->term, k);
    tg->args = MS_ARENA_NEW_ARRAY(&t->m->arena, MirValue, (size_t)a->nargs + extra + 1);
    tg->nargs = a->nargs;
    for (uint32_t i = 0; i < a->nargs; i++) {
      tg->args[i] = resolve(t, p, a->args[i], b->args[i], at, false);
      if (tg->args[i] == MIR_NONE) {
        return false;
      }
    }
    for (uint32_t e = 0; c && e < c->nextras; e++) {
      tg->args[tg->nargs] = resolve(t, p, c->extras[e].on_x, c->extras[e].on_y, at, false);
      if (tg->args[tg->nargs++] == MIR_NONE) {
        return false;
      }
    }
    if (c && c->side != MIR_NONE) {
      tg->args[tg->nargs++] = ensure_side(t, p);
    }
    tg->block = a->block;
  }
  return true;
}

/* Whether `v` is defined in one of the plans' blocks. */
static bool in_region(const Twins *t, MirValue v) {
  if (v >= t->nvalues) {
    return false;
  }
  for (uint32_t q = 0; q < t->nplans; q++) {
    if (t->owner[v] == t->plans[q].x || t->owner[v] == t->plans[q].y) {
      return true;
    }
  }
  return false;
}

static void count_use(void *context, MirValue v) {
  Twins *t = context;
  t->inside[v] += in_region(t, v) ? 1u : 0u;
}

/* Every value the merged blocks define is used only inside them. */
static bool region_is_local(Twins *t) {
  for (uint32_t s = 0; s < t->nplans * 2; s++) {
    const TwPlan *p = &t->plans[s / 2];
    const MirBlockData *b = &t->f->blocks.ptr[(s & 1) ? p->y : p->x];
    for (uint32_t i = 0; i < b->insts.len; i++) {
      for (uint32_t k = 0; k < b->insts.ptr[i].nargs; k++) {
        count_use(t, b->insts.ptr[i].args[k]);
      }
    }
    mir_term_each_value(&b->term, count_use, t);
  }
  bool ok = true;
  for (uint32_t s = 0; s < t->nplans * 2; s++) {
    const TwPlan *p = &t->plans[s / 2];
    const MirBlockData *b = &t->f->blocks.ptr[(s & 1) ? p->y : p->x];
    for (uint32_t i = 0; i < b->params.len; i++) {
      const MirValue v = b->params.ptr[i].value;
      ok = ok && t->inside[v] == t->uses[v];
      t->inside[v] = 0;
    }
    for (uint32_t i = 0; i < b->insts.len; i++) {
      const MirValue v = b->insts.ptr[i].res;
      if (v != MIR_NONE) {
        ok = ok && t->inside[v] == t->uses[v];
        t->inside[v] = 0;
      }
    }
  }
  return ok;
}

static MirValue flag_in(Twins *t, MirBlock pred, bool value) {
  const MirValue c = mir_new_value(t->f, MIR_BOOL);
  const MirInst inst = opt_inst_make(t->m, MOP_BConst, NULL, 0, (MirImm){.tag = MI_BOOL, .a = value ? 1u : 0u}, c,
                     t->f->blocks.ptr[pred].term_loc);
  mir_block_insert(&t->f->blocks.ptr[pred], (uint32_t)t->f->blocks.ptr[pred].insts.len, &inst);
  return c;
}

/* Sends `pred`'s edges to `from` to the merged block, with what that side passes for the new parameters. */
static void retarget(Twins *t, const TwPlan *p, MirBlock pred, MirBlock from, bool is_x) {
  const MirValue flag = p->side != MIR_NONE ? flag_in(t, pred, is_x) : MIR_NONE;
  MirTerm *term = &t->f->blocks.ptr[pred].term;
  for (uint32_t k = 0; k < mir_term_ntargets(term); k++) {
    MirTarget *tg = mir_term_target(term, k);
    if (tg->block != from) {
      continue;
    }
    MirValue *args = MS_ARENA_NEW_ARRAY(&t->m->arena, MirValue, (size_t)tg->nargs + p->nextras + 2);
    if (tg->nargs > 0) {
      __builtin_memcpy(args, tg->args, sizeof(MirValue) * tg->nargs);
    }
    uint32_t n = tg->nargs;
    for (uint32_t e = 0; e < p->nextras; e++) {
      args[n++] = is_x ? p->extras[e].on_x : p->extras[e].on_y;
    }
    if (flag != MIR_NONE) {
      args[n++] = flag;
    }
    *tg = (MirTarget){p->x, args, n};
  }
}

/* Merges the arms under the branch at the end of `a`; false (with nothing changed) when they are not twins. */
static bool merge_arms(Twins *t, MirBlock a) {
  MirFunc *f = t->f;
  const MirBlock x = f->blocks.ptr[a].term.a.block, y = f->blocks.ptr[a].term.b.block;
  if (x == a || y == a || t->npreds[x] != 1 || t->npreds[y] != 1) {
    return false;
  }
  /* Parameters carry scalars only, so both arms start with the same owned values. */
  for (uint32_t s = 0; s < 2; s++) {
    const MirBlockData *b = &f->blocks.ptr[s ? y : x];
    for (uint32_t i = 0; i < b->params.len; i++) {
      if (!mir_is_scalar(t->m, mir_value_ty(f, b->params.ptr[i].value))) {
        return false;
      }
    }
  }
  t->nplans = 0;
  const int root = plan_pair(t, x, y, a, a, 0);
  if (root < 0 || !region_is_local(t) || !build_plan(t, (uint32_t)root)) {
    return false;
  }
  /* Commit, children first (plans are numbered child before parent). */
  for (uint32_t id = 0; id < t->nplans; id++) {
    const TwPlan *p = &t->plans[id];
    MirBlockData *m = &f->blocks.ptr[p->x];
    const MirBlockData *by = &f->blocks.ptr[p->y];
    for (uint32_t e = 0; e < p->nextras; e++) {
      mir_block_param_list_push(&m->params, (MirBlockParam){p->extras[e].param, MM_BORROW});
    }
    if (p->side != MIR_NONE) {
      mir_block_param_list_push(&m->params, (MirBlockParam){p->side, MM_BORROW});
    }
    opt_block_set_insts(m, p->out.v, p->out.n);
    m->term = p->term;
    m->cold = m->cold && by->cold;
  }
  const TwPlan *p = &t->plans[root];
  retarget(t, p, a, x, true);
  retarget(t, p, a, y, false);
  for (uint32_t id = 0; id < t->nplans; id++) {
    MirBlockData *dead = &f->blocks.ptr[t->plans[id].y];
    dead->insts.len = 0;
    dead->params.len = 0;
    dead->term.kind = MT_UNREACHABLE;
  }
  return true;
}

/* A branch whose targets are one block selects the differing arguments. */
static bool join_same_target(MirModule *m, MirFunc *f) {
  bool changed = false;
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    MirTerm *term = &f->blocks.ptr[b].term;
    if (term->kind != MT_CONDBR || term->a.block != term->b.block || term->a.nargs != term->b.nargs) {
      continue;
    }
    bool ok = true;
    for (uint32_t a = 0; a < term->a.nargs; a++) {
      ok = ok && (term->a.args[a] == term->b.args[a] || mir_is_scalar(m, mir_value_ty(f, term->a.args[a])));
    }
    if (!ok) {
      continue;
    }
    MirValue *args = MS_ARENA_NEW_ARRAY(&m->arena, MirValue, (size_t)term->a.nargs + 1);
    for (uint32_t a = 0; a < term->a.nargs; a++) {
      const MirValue x = term->a.args[a], y = term->b.args[a];
      if (x == y) {
        args[a] = x;
        continue;
      }
      const MirValue sel = mir_new_value(f, mir_value_ty(f, x));
      const MirValue sargs[3] = {term->value, x, y};
      const MirInst inst = opt_inst_make(m, MOP_Select, sargs, 3, mir_imm_none(), sel, f->blocks.ptr[b].term_loc);
      mir_block_insert(&f->blocks.ptr[b], (uint32_t)f->blocks.ptr[b].insts.len, &inst);
      args[a] = sel;
    }
    term = &f->blocks.ptr[b].term;
    const uint32_t n = term->a.nargs;
    const MirBlock target = term->a.block;
    term->kind = MT_BR;
    term->value = MIR_NONE;
    term->a = (MirTarget){target, args, n};
    term->b = (MirTarget){0, NULL, 0};
    changed = true;
  }
  return changed;
}

/* One sweep over the branches; true when an arm pair merged. */
static bool sweep(MirModule *m, MirFunc *f) {
  MsArena arena = ms_arena_new();
  const uint32_t nblocks = (uint32_t)f->blocks.len;
  MirBlock *order = NULL;
  const uint32_t reachable = mir_rpo(&arena, f, &order);
  const MirPreds preds = mir_preds(&arena, f);
  MirBlock *idom = mir_dominators(&arena, f, order, reachable, &preds);
  const MirDomTree dom = mir_dom_tree(&arena, f, order, reachable, idom);
  const uint32_t nvalues = (uint32_t)f->values.len;
  MirBlock *owner = MS_ARENA_NEW_ARRAY(&arena, MirBlock, (size_t)nvalues + 1);
  uint32_t *pos = MS_ARENA_NEW_ARRAY(&arena, uint32_t, (size_t)nvalues + 1);
  uint32_t *inside = MS_ARENA_NEW_ARRAY(&arena, uint32_t, (size_t)nvalues + 1);
  __builtin_memset(inside, 0, sizeof(uint32_t) * ((size_t)nvalues + 1));
  for (uint32_t v = 0; v < nvalues; v++) {
    owner[v] = MIR_NONE;
    pos[v] = 0;
  }
  uint32_t *npreds = MS_ARENA_NEW_ARRAY(&arena, uint32_t, (size_t)nblocks + 1);
  for (uint32_t b = 0; b < nblocks; b++) {
    npreds[b] = 0;
  }
  for (uint32_t b = 0; b < nblocks; b++) {
    const MirBlockData *blk = &f->blocks.ptr[b];
    for (uint32_t i = 0; i < blk->params.len; i++) {
      owner[blk->params.ptr[i].value] = b;
      pos[blk->params.ptr[i].value] = i;
    }
    for (uint32_t i = 0; i < blk->insts.len; i++) {
      if (blk->insts.ptr[i].res != MIR_NONE) {
        owner[blk->insts.ptr[i].res] = b;
        pos[blk->insts.ptr[i].res] = (uint32_t)blk->params.len + i;
      }
    }
    for (uint32_t k = 0; k < mir_term_ntargets(&blk->term); k++) {
      npreds[mir_term_target_const(&blk->term, k)->block]++;
    }
  }
  const uint32_t *uses = mir_use_counts(&arena, f);
  bool *dirty = MS_ARENA_NEW_ARRAY(&arena, bool, (size_t)nblocks + 1);
  __builtin_memset(dirty, 0, sizeof(bool) * ((size_t)nblocks + 1));
  Twins *t = MS_ARENA_NEW(&arena, Twins);
  *t = (Twins){.m = m, .f = f, .arena = &arena, .owner = owner, .pos = pos, .nvalues = nvalues, .dom = &dom,
         .uses = uses, .inside = inside, .npreds = npreds};
  bool changed = false;
  for (uint32_t i = 0; i < reachable; i++) {
    const MirBlock a = order[i];
    const MirTerm *term = &f->blocks.ptr[a].term;
    if (term->kind != MT_CONDBR || dirty[a] || dirty[term->a.block] || dirty[term->b.block] || idom[a] == MIR_NONE) {
      continue;
    }
    const MirBlock x = term->a.block, y = term->b.block;
    if (x != y && merge_arms(t, a)) {
      changed = true;
      /* Everything the merge touched keeps its analysis for this sweep only if untouched. */
      dirty[a] = dirty[x] = dirty[y] = true;
      for (uint32_t q = 0; q < t->nplans; q++) {
        dirty[t->plans[q].x] = dirty[t->plans[q].y] = true;
      }
    }
  }
  ms_arena_free(&arena);
  return changed;
}

bool opt_twins_func(MirModule *m, MirFunc *f) {
  bool changed = false;
  while (sweep(m, f)) {
    changed = true;
    mir_func_compact_blocks(f);
  }
  if (changed) {
    join_same_target(m, f);
  }
  return changed;
}

/* range: environments and the facts a branch gives.
 *
 * A conditional edge into a block with a single incoming edge refines the compared values
 * (`br_if (icmp.lt a, b)` gives `a < hi(b)` in the taken block). Refinements are inherited down
 * the dominator tree, which is sound because values are immutable. The same comparisons record
 * relations `a < b` and `a <= b` between values. */
#include "base/sort.h"
#include "compiler/opt/opt_range.h"

void rg_corners(RgArith op, RgItv x, RgItv y, RgWide *lo, RgWide *hi) {
  const RgWide xs[2] = {x.lo, x.hi}, ys[2] = {y.lo, y.hi};
  RgWide mn = 0, mx = 0;
  for (int k = 0; k < 4; k++) {
    const RgWide a = xs[k >> 1], b = ys[k & 1];
    const RgWide r = op == RG_MUL ? a * b : a / b;
    if (k == 0 || r < mn) {
      mn = r;
    }
    if (k == 0 || r > mx) {
      mx = r;
    }
  }
  *lo = mn;
  *hi = mx;
}

/* ---- environments ---- */

/* The first entry whose value is not below `v`. */
static uint32_t rg_env_find(const RgEnv *e, MirValue v) {
  uint32_t lo = 0, hi = e->nent;
  while (lo < hi) {
    const uint32_t mid = lo + (hi - lo) / 2;
    if (e->ent[mid].v < v) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

static bool rg_env_lookup(const RgEnv *e, MirValue v, RgItv *out) {
  const uint32_t at = rg_env_find(e, v);
  if (at < e->nent && e->ent[at].v == v) {
    *out = e->ent[at].itv;
    return true;
  }
  return false;
}

/* Narrows `v` to `lo..=hi`. Disjoint intervals mean the path is dead, or that the old one is still
 * an early approximation that will grow: take the refinement, not a stale interval it contradicts. */
void rg_env_narrow(RgEnv *e, MirValue v, RgWide lo, RgWide hi) {
  const RgItv fresh = rg_clamp(lo, hi);
  const uint32_t at = rg_env_find(e, v);
  if (at < e->nent && e->ent[at].v == v) {
    RgItv met;
    e->ent[at].itv = rg_meet(e->ent[at].itv, fresh, &met) ? met : fresh;
    return;
  }
  RgItv met;
  const RgItv itv = rg_meet(RG_TOP, fresh, &met) ? met : fresh;
  if (e->nent == e->cent) {
    e->ent = (RgEnt *)opt_grow(e->arena, e->ent, e->nent, &e->cent, sizeof(RgEnt));
  }
  __builtin_memmove(&e->ent[at + 1], &e->ent[at], (size_t)(e->nent - at) * sizeof(RgEnt));
  e->ent[at] = (RgEnt){v, itv};
  e->nent++;
}

static void rg_env_add_rel(RgEnv *e, MirValue a, MirValue b, bool strict) {
  RgRel r = {a, b, strict};
  OPT_PUSH(e->arena, e->rel, e->nrel, e->crel, RgRel, r);
}

static bool rg_env_has_rel(const RgEnv *e, const RgRel *r) {
  for (uint32_t i = 0; i < e->nrel; i++) {
    if (e->rel[i].a == r->a && e->rel[i].b == r->b && e->rel[i].strict == r->strict) {
      return true;
    }
  }
  return false;
}

static RgEnv rg_env_clone(MsArena *arena, const RgEnv *src) {
  RgEnv e = {.arena = arena};
  if (src->nent != 0) {
    e.ent = RG_NEW(arena, RgEnt, src->nent);
    __builtin_memcpy(e.ent, src->ent, (size_t)src->nent * sizeof(RgEnt));
    e.nent = e.cent = src->nent;
  }
  if (src->nrel != 0) {
    e.rel = RG_NEW(arena, RgRel, src->nrel);
    __builtin_memcpy(e.rel, src->rel, (size_t)src->nrel * sizeof(RgRel));
    e.nrel = e.crel = src->nrel;
  }
  return e;
}

/* ---- facts about values ---- */

const MirInst *rg_def_inst(const RgFa *fa, MirValue v) {
  if (v >= fa->nv || fa->def_blk[v] == MIR_NONE) {
    return NULL;
  }
  return &fa->f->blocks.ptr[fa->def_blk[v]].insts.ptr[fa->def_idx[v]];
}

bool rg_constant(const RgFa *fa, MirValue v, int64_t *out) {
  const MirInst *i = rg_def_inst(fa, v);
  if (i == NULL || i->op != MOP_IConst || i->imm.tag != MI_INT) {
    return false;
  }
  *out = i->imm.i;
  return true;
}

static bool rg_bconst(const RgFa *fa, MirValue v, bool *out) {
  const MirInst *i = rg_def_inst(fa, v);
  if (i == NULL || i->op != MOP_BConst || i->imm.tag != MI_BOOL) {
    return false;
  }
  *out = i->imm.a != 0;
  return true;
}

/* The key facts about `v` are kept under: its length origin. */
uint32_t rg_class(const RgFa *fa, MirValue v) {
  return fa->lenof[v] != MIR_NONE ? fa->lenof[v] : fa->lengths[v];
}

/* `UInt64` values are tracked as the unsigned range they provably lie in when it stays within
 * `0..=i64::MAX`; any interval that dips below zero stands for "every `u64`". */
bool rg_tracked(MirTy ty) { return ty == MIR_INT || ty == MIR_BOOL || ty == MIR_UINT64; }

static RgItv rg_unsigned(MirTy ty, RgItv itv) { return ty == MIR_UINT64 && itv.lo < 0 ? RG_TOP : itv; }

/* The interval of `v` under `env`; false when nothing is known (the value is not tracked yet). */
bool rg_get(const RgFa *fa, MirValue v, const RgEnv *env, RgItv *out) {
  if (!fa->has_base[v]) {
    return false;
  }
  const MirTy ty = fa->f->values.ptr[v];
  RgItv b = rg_unsigned(ty, fa->base[v]), r, met;
  if (rg_env_lookup(env, v, &r) && rg_meet(b, rg_unsigned(ty, r), &met)) {
    b = met;
  }
  *out = b;
  return true;
}

/* ---- pruning ---- */

static bool rg_prune_live(const RgFa *fa, MirValue v, uint32_t pos) {
  return fa->last_read[rg_class(fa, v)] >= pos;
}

/* `b = x - c` (or `x + c`) with `x` live also counts as live: the proof steps through the offset to
 * `x` (`i <= len - 2` is how a child index is known to be in range). */
static bool rg_prune_reach(const RgFa *fa, MirValue v, uint32_t pos) {
  if (rg_prune_live(fa, v, pos)) {
    return true;
  }
  const MirInst *d = rg_def_inst(fa, v);
  int64_t c = 0;
  return d != NULL && (d->op == MOP_IAdd || d->op == MOP_IAddChk || d->op == MOP_ISub ||
            d->op == MOP_ISubChk) &&
     rg_constant(fa, d->args[1], &c) && rg_prune_live(fa, d->args[0], pos);
}

/* Whether the sorted `v[0..n]` holds `x`. */
static bool rg_has_u32(const uint32_t *v, uint32_t n, uint32_t x) {
  uint32_t lo = 0, hi = n;
  while (lo < hi) {
    const uint32_t mid = lo + (hi - lo) / 2;
    if (v[mid] == x) {
      return true;
    }
    if (v[mid] < x) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return false;
}

static int64_t rg_cmp_u32(uint8_t *env, const uint8_t *x, const uint8_t *y) {
  (void)env;
  const uint32_t a = *(const uint32_t *)(const void *)x, b = *(const uint32_t *)(const void *)y;
  return (a > b) - (a < b);
}

/* Drops what `env` knows about values that no block from `bi` on reads, so environments stay as
 * large as what is live, not as large as the dominating code. `a < b` serves a proof that reaches
 * `b` from a live value and goes on from there, so it stays when `b` is live or when `b` starts
 * another kept relation. */
static void rg_prune(RgFa *fa, RgEnv *env, uint32_t bi) {
  const uint32_t pos = fa->rpo_pos[bi];
  uint32_t kept = 0;
  for (uint32_t i = 0; i < env->nent; i++) {
    if (rg_prune_live(fa, env->ent[i].v, pos)) {
      env->ent[kept++] = env->ent[i];
    }
  }
  env->nent = kept;
  uint32_t *starts = RG_NEW(rg_tmp(fa), uint32_t, (size_t)env->nrel + 1);
  uint32_t nstarts = 0;
  for (uint32_t i = 0; i < env->nrel; i++) {
    if (rg_prune_reach(fa, env->rel[i].b, pos)) {
      starts[nstarts++] = rg_class(fa, env->rel[i].a);
    }
  }
  ms_sort((uint8_t *)starts, nstarts, sizeof *starts, rg_cmp_u32, NULL);
  kept = 0;
  for (uint32_t i = 0; i < env->nrel; i++) {
    const RgRel *r = &env->rel[i];
    const uint32_t cb = rg_class(fa, r->b);
    const bool start =
      rg_has_u32(starts, nstarts, cb);
    if (rg_prune_reach(fa, r->b, pos) || (rg_prune_live(fa, r->a, pos) && start)) {
      env->rel[kept++] = *r;
    }
  }
  env->nrel = kept;
}

/* ---- edges ---- */

static void rg_apply_edge(RgFa *fa, RgEnv *env, uint32_t p, const RgEdge *e) {
  const MirTerm *t = &fa->f->blocks.ptr[p].term;
  if (t->kind == MT_CONDBR && (e->kind == RG_THEN || e->kind == RG_ELSE)) {
    rg_refine_cond(fa, t->value, e->kind == RG_THEN, env);
  } else if (t->kind == MT_SWITCH && e->kind == RG_CASE && fa->f->values.ptr[t->value] == MIR_INT) {
    rg_env_narrow(env, t->value, e->key, e->key);
  }
}

RgEnv rg_edge_env(RgFa *fa, MsArena *arena, const RgEdge *e) {
  RgEnv env = rg_env_clone(arena, &fa->envs[e->pred]);
  rg_apply_edge(fa, &env, e->pred, e);
  return env;
}

/* The single edge that enters the loop headed by `bi` from outside, when every other incoming edge
 * comes from inside it. Every path to the header runs through that edge first, and values are
 * immutable, so what it refines about earlier values holds in the whole loop. */
static const RgEdge *rg_entry_edge(const RgFa *fa, uint32_t bi) {
  const RgEdge *entry = NULL;
  for (uint32_t k = fa->in_start[bi]; k < fa->in_start[bi + 1]; k++) {
    if (mir_tree_dominates(&fa->dom, bi, fa->in[k].pred)) {
      continue;
    }
    if (entry != NULL) {
      return NULL;
    }
    entry = &fa->in[k];
  }
  return entry;
}

void rg_build_env(RgFa *fa, uint32_t bi, RgEnv *out) {
  MsArena *arena = &fa->gen[fa->round & 1];
  if (bi == 0) {
    *out = (RgEnv){.arena = arena};
    return;
  }
  *out = rg_env_clone(arena, &fa->envs[fa->idom[bi]]);
  rg_prune(fa, out, bi);
  const RgEdge *edge = NULL;
  if (fa->in_start[bi + 1] - fa->in_start[bi] == 1) {
    edge = &fa->in[fa->in_start[bi]];
  } else {
    edge = rg_entry_edge(fa, bi);
  }
  if (edge != NULL) {
    rg_apply_edge(fa, out, edge->pred, edge);
  }
}

/* ---- conditions ---- */

/* A Boolean block parameter (the merge of a short-circuit `and`/`or`) that is `truth` only on one
 * forward incoming edge: that edge's facts hold. Returns whether `cond` was such a parameter. */
static bool rg_refine_param(RgFa *fa, MirValue cond, bool truth, RgEnv *env) {
  if (fa->param_blk[cond] == MIR_NONE) {
    return false;
  }
  const uint32_t bi = fa->param_blk[cond], pi = fa->param_idx[cond];
  const uint32_t n = fa->in_start[bi + 1] - fa->in_start[bi];
  for (uint32_t k = fa->in_start[bi]; k < fa->in_start[bi + 1]; k++) {
    if (fa->rpo_pos[fa->in[k].pred] >= fa->rpo_pos[bi]) {
      return true;
    }
  }
  if (n == 0) {
    return true;
  }
  const RgEdge *viable = NULL;
  uint32_t nviable = 0;
  for (uint32_t k = fa->in_start[bi]; k < fa->in_start[bi + 1]; k++) {
    bool b = false;
    if (!rg_bconst(fa, fa->in[k].args[pi], &b) || b == truth) {
      viable = viable != NULL ? viable : &fa->in[k];
      nviable++;
    }
  }
  if (nviable != 1) {
    return true;
  }
  RgEnv e = rg_edge_env(fa, rg_tmp(fa), viable);
  rg_refine_cond(fa, viable->args[pi], truth, &e);
  for (uint32_t i = 0; i < e.nent; i++) {
    rg_env_narrow(env, e.ent[i].v, e.ent[i].itv.lo, e.ent[i].itv.hi);
  }
  for (uint32_t i = 0; i < e.nrel; i++) {
    if (!rg_env_has_rel(env, &e.rel[i])) {
      rg_env_add_rel(env, e.rel[i].a, e.rel[i].b, e.rel[i].strict);
    }
  }
  return true;
}

/* Whether the select tree `v` can yield a value `r` with `(r cc k) == truth`. */
static bool rg_arm_can(const RgFa *fa, MirValue v, MirCc cc, int64_t k, bool truth, uint32_t depth) {
  int64_t c = 0;
  if (rg_constant(fa, v, &c)) {
    return mir_cc_holds(cc, c, k) == truth;
  }
  const MirInst *d = rg_def_inst(fa, v);
  if (d != NULL && d->op == MOP_Select && depth > 0) {
    return rg_arm_can(fa, d->args[1], cc, k, truth, depth - 1) ||
       rg_arm_can(fa, d->args[2], cc, k, truth, depth - 1);
  }
  return true;
}

/* `v cc k` is `truth` where `v` selects between constants (the three-way compare of
 * `min`/`max`/`compare`): a condition whose arm cannot satisfy it is known to be false. */
static void rg_refine_select(RgFa *fa, MirValue v, MirCc cc, int64_t k, bool truth, RgEnv *env,
             uint32_t depth) {
  const MirInst *d = rg_def_inst(fa, v);
  if (d == NULL || d->op != MOP_Select || depth == 0) {
    return;
  }
  const MirValue c = d->args[0], x = d->args[1], y = d->args[2];
  const bool cx = rg_arm_can(fa, x, cc, k, truth, 3), cy = rg_arm_can(fa, y, cc, k, truth, 3);
  if (cx && !cy) {
    rg_refine_cond(fa, c, true, env);
    rg_refine_select(fa, x, cc, k, truth, env, depth - 1);
  } else if (cy && !cx) {
    rg_refine_cond(fa, c, false, env);
    rg_refine_select(fa, y, cc, k, truth, env, depth - 1);
  }
}

/* `a or b` and `a and b` lower to a select with a constant arm. */
static void rg_refine_select_cond(RgFa *fa, const MirInst *inst, bool truth, RgEnv *env) {
  const MirValue c = inst->args[0], x = inst->args[1], y = inst->args[2];
  bool bx = false, by = false;
  const bool hx = rg_bconst(fa, x, &bx), hy = rg_bconst(fa, y, &by);
  if (hx && bx && !truth) {
    rg_refine_cond(fa, c, false, env);
    rg_refine_cond(fa, y, false, env);
  } else if (hy && !by && truth) {
    rg_refine_cond(fa, c, true, env);
    rg_refine_cond(fa, x, true, env);
  } else if (hx && !bx && truth) {
    rg_refine_cond(fa, c, false, env);
    rg_refine_cond(fa, y, true, env);
  } else if (hy && by && !truth) {
    rg_refine_cond(fa, c, true, env);
    rg_refine_cond(fa, x, false, env);
  }
}

/* Unsigned `a cc b`: the smaller side is bounded by the larger side's known upper bound. The
 * larger side gains no usable lower bound, as its upper end may pass `i64::MAX`. */
static void rg_refine_ucmp(RgFa *fa, MirCc cc, MirValue a, MirValue b, RgEnv *env) {
  RgItv ia, ib;
  if (!rg_get(fa, a, env, &ia) || !rg_get(fa, b, env, &ib)) {
    return;
  }
  switch (cc) {
  case MCC_LT:
    if (ib.lo >= 0) rg_env_narrow(env, a, 0, (RgWide)ib.hi - 1);
    break;
  case MCC_LE:
    if (ib.lo >= 0) rg_env_narrow(env, a, 0, ib.hi);
    break;
  case MCC_GT:
    if (ia.lo >= 0) rg_env_narrow(env, b, 0, (RgWide)ia.hi - 1);
    break;
  case MCC_GE:
    if (ia.lo >= 0) rg_env_narrow(env, b, 0, ia.hi);
    break;
  case MCC_EQ: case MCC_NE:
    break;
  }
}

/* One step back through `p + k` or `p - k` computed by a checked operation: the check succeeded,
 * so the arithmetic was exact and the operand lies in the shifted interval. */
static bool rg_narrow_step(const RgFa *fa, MirValue *v, RgWide *lo, RgWide *hi, RgEnv *env) {
  const MirInst *i = rg_def_inst(fa, *v);
  if (i == NULL || (i->op != MOP_IAddChk && i->op != MOP_ISubChk)) {
    return false;
  }
  int64_t k0 = 0, k1 = 0;
  const bool c0 = rg_constant(fa, i->args[0], &k0), c1 = rg_constant(fa, i->args[1], &k1);
  MirValue p = 0;
  RgWide plo = 0, phi = 0;
  if (c0 == c1) {
    return false;
  }
  if (i->op == MOP_IAddChk) {
    p = c1 ? i->args[0] : i->args[1];
    plo = *lo - (c1 ? k1 : k0);
    phi = *hi - (c1 ? k1 : k0);
  } else if (c1) {
    p = i->args[0];
    plo = *lo + k1;
    phi = *hi + k1;
  } else {
    p = i->args[1];
    plo = (RgWide)k0 - *hi;
    phi = (RgWide)k0 - *lo;
  }
  rg_env_narrow(env, p, plo, phi);
  *v = p;
  *lo = plo;
  *hi = phi;
  return true;
}

/* Narrows `v` and, when `v` is `p + c` or `p - c` computed by a checked operation, the operand `p`
 * too: `x < n - 1` then gives `n > x + 1`. */
static void rg_narrow_back(const RgFa *fa, RgEnv *env, MirValue v, RgWide lo, RgWide hi) {
  rg_env_narrow(env, v, lo, hi);
  for (int step = 0; step < 3 && rg_narrow_step(fa, &v, &lo, &hi, env); step++) {
  }
}

static void rg_refine_ne(const RgFa *fa, RgEnv *env, MirValue a, RgItv ia, RgItv ib) {
  if (!rg_is_point(ib)) {
    return;
  }
  if (ia.lo == ib.lo) {
    rg_narrow_back(fa, env, a, (RgWide)ia.lo + 1, INT64_MAX);
  } else if (ia.hi == ib.lo) {
    rg_narrow_back(fa, env, a, INT64_MIN, (RgWide)ia.hi - 1);
  }
}

static void rg_refine_cmp(RgFa *fa, MirCc cc, MirValue a, MirValue b, RgEnv *env) {
  RgItv ia, ib;
  if (!rg_get(fa, a, env, &ia) || !rg_get(fa, b, env, &ib)) {
    return;
  }
  const RgWide al = ia.lo, ah = ia.hi, bl = ib.lo, bh = ib.hi;
  const RgWide min = INT64_MIN, max = INT64_MAX;
  switch (cc) {
  case MCC_LT:
    rg_narrow_back(fa, env, a, min, bh - 1);
    rg_narrow_back(fa, env, b, al + 1, max);
    rg_env_add_rel(env, a, b, true);
    break;
  case MCC_LE:
    rg_narrow_back(fa, env, a, min, bh);
    rg_narrow_back(fa, env, b, al, max);
    rg_env_add_rel(env, a, b, false);
    break;
  case MCC_GT:
    rg_narrow_back(fa, env, a, bl + 1, max);
    rg_narrow_back(fa, env, b, min, ah - 1);
    rg_env_add_rel(env, b, a, true);
    break;
  case MCC_GE:
    rg_narrow_back(fa, env, a, bl, max);
    rg_narrow_back(fa, env, b, min, ah);
    rg_env_add_rel(env, b, a, false);
    break;
  case MCC_EQ:
    rg_narrow_back(fa, env, a, bl, bh);
    rg_narrow_back(fa, env, b, al, ah);
    rg_env_add_rel(env, a, b, false);
    rg_env_add_rel(env, b, a, false);
    break;
  case MCC_NE:
    rg_refine_ne(fa, env, a, ia, ib);
    rg_refine_ne(fa, env, b, ib, ia);
    break;
  }
}

static void rg_refine_icmp(RgFa *fa, const MirInst *inst, bool truth, RgEnv *env) {
  if (inst->imm.tag != MI_CC) {
    return;
  }
  const MirCc cc = (MirCc)inst->imm.a;
  int64_t k = 0;
  if (rg_constant(fa, inst->args[1], &k)) {
    rg_refine_select(fa, inst->args[0], cc, k, truth, env, 4);
  }
  rg_refine_cmp(fa, truth ? cc : mir_cc_negated(cc), inst->args[0], inst->args[1], env);
}

void rg_refine_cond(RgFa *fa, MirValue cond, bool truth, RgEnv *env) {
  if (rg_refine_param(fa, cond, truth, env)) {
    return;
  }
  const MirInst *inst = rg_def_inst(fa, cond);
  if (inst == NULL) {
    return;
  }
  switch ((MirOp)inst->op) {
  case MOP_ICmp:
    rg_refine_icmp(fa, inst, truth, env);
    break;
  case MOP_Select:
    rg_refine_select_cond(fa, inst, truth, env);
    break;
  case MOP_UICmp:
    if (inst->imm.tag == MI_CC) {
      const MirCc cc = (MirCc)inst->imm.a;
      rg_refine_ucmp(fa, truth ? cc : mir_cc_negated(cc), inst->args[0], inst->args[1], env);
    }
    break;
  case MOP_Not:
    rg_refine_cond(fa, inst->args[0], !truth, env);
    break;
  case MOP_And:
    if (truth) {
      rg_refine_cond(fa, inst->args[0], true, env);
      rg_refine_cond(fa, inst->args[1], true, env);
    }
    break;
  case MOP_Or:
    if (!truth) {
      rg_refine_cond(fa, inst->args[0], false, env);
      rg_refine_cond(fa, inst->args[1], false, env);
    }
    break;
  default:
    break;
  }
}

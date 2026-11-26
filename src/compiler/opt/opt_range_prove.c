/* range: proofs over the analysis results, and the edits they justify.
 *
 * `idx < list.len l` is proved by a goal-directed search (`prove_le`) over the recorded relations
 * and the definitions of the values involved: constant and ranged offsets (`a[i + 1]` under
 * `i < len - 1`, `a[len - 1 - i]`), division and scaling (`a[i * 3 + 2]` under `i < len / 3`),
 * and loop parameters by induction (a binary search whose `hi` starts at `len - 1`). */
#include "compiler/opt/opt_range.h"

/* Proof-search budget per query, and the most assumptions one search can hold. */
enum { RGP_FUEL = 200, RGP_ASSUMED = 256 };

/* What a proved upper bound is measured against: the length of lists with an origin, or a value. */
typedef struct RgGoal {
  bool is_len;
  MirValue v;
} RgGoal;

typedef struct RgAssumed {
  MirValue v;
  RgGoal goal;
  RgWide d;
} RgAssumed;

typedef struct RgProof {
  RgFa *fa;
  uint32_t fuel, nassumed;
  RgAssumed assumed[RGP_ASSUMED];
} RgProof;

static bool rg_goal_eq(RgGoal a, RgGoal b) { return a.is_len == b.is_len && a.v == b.v; }

static bool rg_same_value(const RgFa *fa, MirValue a, MirValue b) {
  return a == b || (fa->lenof[a] != MIR_NONE && fa->lenof[b] == fa->lenof[a]);
}

/* `(a < b, a <= b)` as far as recorded relations and identity prove. */
static void rg_rel_known(const RgFa *fa, MirValue a, MirValue b, const RgEnv *env, bool *lt, bool *le) {
  *lt = false;
  *le = rg_same_value(fa, a, b);
  for (uint32_t i = 0; i < env->nrel; i++) {
    const RgRel *r = &env->rel[i];
    if (rg_same_value(fa, r->a, a) && rg_same_value(fa, r->b, b)) {
      *lt = *lt || r->strict;
      *le = true;
    }
  }
}

/* Whether `a cc b` is decided; the answer is in `*result`. */
bool rg_decide(const RgFa *fa, MirCc cc, MirValue a, MirValue b, RgItv x, RgItv y,
       const RgEnv *env, bool *result) {
  bool lt, le, gt, ge;
  rg_rel_known(fa, a, b, env, &lt, &le);
  rg_rel_known(fa, b, a, env, &gt, &ge);
  const bool ilt = x.hi < y.lo, ile = x.hi <= y.lo, igt = x.lo > y.hi, ige = x.lo >= y.hi;
  const bool eq_true = (rg_is_point(x) && rg_is_point(y) && x.lo == y.lo) || rg_same_value(fa, a, b);
  const bool ne_true = ilt || igt || lt || gt;
  switch (cc) {
  case MCC_LT:
    *result = ilt || lt;
    return *result || ige || ge;
  case MCC_LE:
    *result = ile || le;
    return *result || igt || gt;
  case MCC_GT:
    *result = igt || gt;
    return *result || ile || le;
  case MCC_GE:
    *result = ige || ge;
    return *result || ilt || lt;
  case MCC_EQ:
    *result = eq_true;
    return eq_true || ne_true;
  case MCC_NE:
    *result = ne_true;
    return ne_true || eq_true;
  }
  return false;
}

/* The length of a list whose origin is a literal, a constant or a new list. */
bool rg_list_length(const RgFa *fa, MirValue v, int64_t *out) {
  const MirInst *d = rg_def_inst(fa, fa->lengths[v]);
  if (d == NULL) {
    return false;
  }
  switch ((MirOp)d->op) {
  case MOP_ListLit:
    *out = d->nargs;
    return true;
  case MOP_ListConst: case MOP_ListConstView:
    if (d->imm.tag != MI_INT) {
      return false;
    }
    *out = fa->m->list_consts.ptr[d->imm.i].count;
    return true;
  case MOP_ListNew: /* capacity does not change a new list's initially empty length */
    *out = 0;
    return true;
  default:
    return false;
  }
}

/* Whether the add, subtract or multiply `d` computes the exact integer result. */
static bool rg_no_wrap(const RgFa *fa, const MirInst *d, const RgEnv *env) {
  if (d->op == MOP_IAddChk || d->op == MOP_ISubChk || d->op == MOP_IMulChk) {
    return true;
  }
  RgItv x, y;
  if (!rg_get(fa, d->args[0], env, &x) || !rg_get(fa, d->args[1], env, &y)) {
    return false;
  }
  RgWide lo, hi;
  if (d->op == MOP_IAdd) {
    lo = (RgWide)x.lo + y.lo;
    hi = (RgWide)x.hi + y.hi;
  } else if (d->op == MOP_ISub) {
    lo = (RgWide)x.lo - y.hi;
    hi = (RgWide)x.hi - y.lo;
  } else if (d->op == MOP_IMul) {
    rg_corners(RG_MUL, x, y, &lo, &hi);
  } else {
    return false;
  }
  return rg_fits(lo, hi);
}

static bool rg_goal_matches(const RgFa *fa, MirValue v, RgGoal goal) {
  return goal.is_len ? fa->lenof[v] == goal.v : (v == goal.v || rg_same_value(fa, v, goal.v));
}

/* The `x + c` or `c + x` form of an add (or `x - c`, with `sub`): the other operand and the offset. */
static bool rg_offset_of(const RgFa *fa, const MirInst *def, bool sub, MirValue *x, RgWide *c) {
  int64_t k = 0;
  if (rg_constant(fa, def->args[1], &k)) {
    *x = def->args[0];
    *c = sub ? -(RgWide)k : (RgWide)k;
    return true;
  }
  if (!sub && rg_constant(fa, def->args[0], &k)) {
    *x = def->args[1];
    *c = k;
    return true;
  }
  return false;
}

/* Folds a constant offset in the goal value into `d`: `v <= (x + c) + d` is `v <= x + (c + d)`. */
static void rg_normalize_goal(const RgFa *fa, RgGoal *goal, RgWide *d, const RgEnv *env) {
  for (int step = 0; step < 4 && !goal->is_len; step++) {
    const MirInst *def = rg_def_inst(fa, goal->v);
    if (def == NULL || (def->op != MOP_IAdd && def->op != MOP_IAddChk && def->op != MOP_ISub &&
              def->op != MOP_ISubChk) ||
      !rg_no_wrap(fa, def, env)) {
      return;
    }
    MirValue x = 0;
    RgWide c = 0;
    if (!rg_offset_of(fa, def, def->op == MOP_ISub || def->op == MOP_ISubChk, &x, &c)) {
      return;
    }
    goal->v = x;
    *d += c;
  }
}

static bool rg_prove_le(RgProof *p, MirValue v, RgGoal goal, RgWide d, const RgEnv *env);

/* Copies what `env` knows about the goal's value into an incoming-edge environment of block `bi`.
 * The value is defined above `bi`, so it is the same on every iteration: a lower bound that holds
 * at the use holds on the edge that fed the use. */
static void rg_carry_goal_facts(const RgFa *fa, RgGoal goal, uint32_t bi, const RgEnv *env,
              RgEnv *edge) {
  for (uint32_t i = 0; i < env->nent; i++) {
    const MirValue v = env->ent[i].v;
    if (!rg_goal_matches(fa, v, goal)) {
      continue;
    }
    const uint32_t def = fa->def_blk[v] != MIR_NONE ? fa->def_blk[v] : fa->param_blk[v];
    if (def == MIR_NONE) {
      continue;
    }
    if (mir_tree_dominates(&fa->dom, def, bi)) {
      rg_env_narrow(edge, v, env->ent[i].itv.lo, env->ent[i].itv.hi);
    }
  }
}

/* A loop parameter is proved by induction: assuming the bound, every incoming argument must meet
 * it too. */
static bool rg_prove_param(RgProof *p, MirValue v, RgGoal goal, RgWide d, const RgEnv *env) {
  RgFa *fa = p->fa;
  const uint32_t bi = fa->param_blk[v], pi = fa->param_idx[v];
  if (bi == MIR_NONE || fa->in_start[bi] == fa->in_start[bi + 1] || p->nassumed == RGP_ASSUMED) {
    return false;
  }
  p->assumed[p->nassumed++] = (RgAssumed){v, goal, d};
  bool all = true;
  for (uint32_t k = fa->in_start[bi]; all && k < fa->in_start[bi + 1]; k++) {
    RgEnv edge = rg_edge_env(fa, rg_tmp(fa), &fa->in[k]);
    rg_carry_goal_facts(fa, goal, bi, env, &edge);
    all = rg_prove_le(p, fa->in[k].args[pi], goal, d, &edge);
  }
  p->nassumed--;
  return all;
}

/* `x <= goal + d - hi(y)` or `y <= ...`: a sum is bounded by bounding one operand and the other's
 * upper end. */
static bool rg_prove_sum(RgProof *p, const MirInst *def, RgGoal goal, RgWide d, const RgEnv *env) {
  RgItv hx, hy;
  const MirValue x = def->args[0], y = def->args[1];
  return (rg_get(p->fa, y, env, &hy) && rg_prove_le(p, x, goal, d - hy.hi, env)) ||
     (rg_get(p->fa, x, env, &hx) && rg_prove_le(p, y, goal, d - hx.hi, env));
}

static bool rg_lo_at_least(const RgFa *fa, MirValue v, int64_t least, const RgEnv *env) {
  RgItv i;
  return rg_get(fa, v, env, &i) && i.lo >= least;
}

/* `u * c <= goal + d` from `u < goal / c` (or `<=`): `(goal / c) * c <= goal` for `goal >= 0`. */
static bool rg_prove_scaled(RgProof *p, const MirInst *def, RgGoal goal, RgWide d, const RgEnv *env) {
  const RgFa *fa = p->fa;
  int64_t c = 0;
  MirValue u = 0;
  if (rg_constant(fa, def->args[1], &c)) {
    u = def->args[0];
  } else if (rg_constant(fa, def->args[0], &c)) {
    u = def->args[1];
  } else {
    return false;
  }
  if (c < 1) {
    return false;
  }
  for (uint32_t i = 0; i < env->nrel; i++) {
    const RgRel *r = &env->rel[i];
    const MirInst *q = rg_def_inst(fa, r->b);
    int64_t qc = 0;
    if (!rg_same_value(fa, r->a, u) || q == NULL ||
      (q->op != MOP_SDiv && q->op != MOP_SDivChk) || !rg_constant(fa, q->args[1], &qc) ||
      qc != c) {
      continue;
    }
    const MirValue x = q->args[0];
    const bool same = goal.is_len ? fa->lenof[x] == goal.v : x == goal.v;
    if (same && rg_lo_at_least(fa, x, 0, env) && -(RgWide)(r->strict ? 1 : 0) * c <= d) {
      return true;
    }
  }
  return false;
}

/* The bound through the definition of `v`. */
static bool rg_prove_def(RgProof *p, MirValue v, RgGoal goal, RgWide d, const RgEnv *env) {
  const RgFa *fa = p->fa;
  const MirInst *def = rg_def_inst(fa, v);
  if (def == NULL) {
    return false;
  }
  const MirValue x = def->nargs > 0 ? def->args[0] : MIR_NONE;
  const MirValue y = def->nargs > 1 ? def->args[1] : MIR_NONE;
  RgItv ly;
  int64_t c = 0;
  switch ((MirOp)def->op) {
  case MOP_IAdd: case MOP_IAddChk:
    return rg_no_wrap(fa, def, env) && rg_prove_sum(p, def, goal, d, env);
  case MOP_ISub: case MOP_ISubChk:
    return rg_no_wrap(fa, def, env) && rg_get(fa, y, env, &ly) &&
       rg_prove_le(p, x, goal, d + ly.lo, env);
  case MOP_SDiv: case MOP_SDivChk:
    return rg_constant(fa, y, &c) && c >= 1 && rg_lo_at_least(fa, x, 0, env) &&
       rg_prove_le(p, x, goal, d, env);
  case MOP_SRem: case MOP_SRemChk:
    return rg_lo_at_least(fa, x, 0, env) && rg_lo_at_least(fa, y, 1, env) &&
       (rg_prove_le(p, x, goal, d, env) || rg_prove_le(p, y, goal, d + 1, env));
  case MOP_And:
    return (rg_lo_at_least(fa, x, 0, env) && rg_prove_le(p, x, goal, d, env)) ||
       (rg_lo_at_least(fa, y, 0, env) && rg_prove_le(p, y, goal, d, env));
  case MOP_Select:
    return rg_prove_le(p, def->args[1], goal, d, env) && rg_prove_le(p, def->args[2], goal, d, env);
  case MOP_IMul: case MOP_IMulChk:
    return rg_no_wrap(fa, def, env) && rg_prove_scaled(p, def, goal, d, env);
  default:
    return false;
  }
}

/* Whether `v <= goal + d` follows from the interval of `v` and of the goal. */
static bool rg_prove_by_interval(const RgProof *p, MirValue v, RgGoal goal, RgWide d, const RgEnv *env) {
  const RgFa *fa = p->fa;
  RgItv i;
  if (!rg_get(fa, v, env, &i)) {
    return false;
  }
  RgWide floor = 0;
  if (goal.is_len) {
    for (uint32_t k = 0; k < env->nent; k++) {
      if (rg_goal_matches(fa, env->ent[k].v, goal)) {
        const RgWide lo = env->ent[k].itv.lo > 0 ? env->ent[k].itv.lo : 0;
        floor = lo > floor ? lo : floor;
      }
    }
  } else {
    RgItv g;
    if (!rg_get(fa, goal.v, env, &g)) {
      return false;
    }
    floor = g.lo;
  }
  return (RgWide)i.hi <= floor + d;
}

/* A relation `x + c <= b` (the guard of a block of `c` accesses) also bounds `x`: `x <= b - c`. */
static bool rg_prove_shifted(RgProof *p, MirValue v, RgGoal goal, RgWide d, const RgEnv *env) {
  for (uint32_t i = 0; i < env->nrel; i++) {
    const RgRel *r = &env->rel[i];
    const MirInst *shifted = rg_def_inst(p->fa, r->a);
    MirValue x = 0;
    RgWide c = 0;
    if (shifted == NULL || (shifted->op != MOP_IAdd && shifted->op != MOP_IAddChk) ||
      !rg_no_wrap(p->fa, shifted, env) || !rg_offset_of(p->fa, shifted, false, &x, &c)) {
      continue;
    }
    if (rg_same_value(p->fa, x, v) &&
      rg_prove_le(p, r->b, goal, d + (r->strict ? 1 : 0) + c, env)) {
      return true;
    }
  }
  return false;
}

/* Proves `v <= goal + d` from intervals, recorded relations and the definitions of the values
 * involved. */
static bool rg_prove_le(RgProof *p, MirValue v, RgGoal goal, RgWide d, const RgEnv *env) {
  const RgFa *fa = p->fa;
  if (p->fuel == 0) {
    return false;
  }
  p->fuel--;
  rg_normalize_goal(fa, &goal, &d, env);
  if (rg_goal_matches(fa, v, goal) && d >= 0) {
    return true;
  }
  if (rg_prove_by_interval(p, v, goal, d, env)) {
    return true;
  }
  for (uint32_t i = 0; i < p->nassumed; i++) {
    if (p->assumed[i].v == v && rg_goal_eq(p->assumed[i].goal, goal) && p->assumed[i].d <= d) {
      return true;
    }
  }
  for (uint32_t i = 0; i < env->nrel; i++) {
    const RgRel *r = &env->rel[i];
    if (rg_same_value(fa, r->a, v) && rg_prove_le(p, r->b, goal, d + (r->strict ? 1 : 0), env)) {
      return true;
    }
  }
  return rg_prove_shifted(p, v, goal, d, env) || rg_prove_param(p, v, goal, d, env) ||
     rg_prove_def(p, v, goal, d, env);
}

static bool rg_prove(RgFa *fa, MirValue v, RgGoal goal, RgWide d, const RgEnv *env) {
  RgProof *p = RG_ZNEW(rg_tmp(fa), RgProof, 1);
  p->fa = fa;
  p->fuel = RGP_FUEL;
  return rg_prove_le(p, v, goal, d, env);
}

/* Proves `idx < list.len l` from recorded relations. */
static bool rg_below_len(RgFa *fa, MirValue idx, MirValue l, const RgEnv *env) {
  RgItv i;
  int64_t n = 0;
  if (rg_get(fa, idx, env, &i) && rg_list_length(fa, l, &n) && i.hi < n) {
    return true;
  }
  return rg_prove(fa, idx, (RgGoal){true, fa->lengths[l]}, -1, env);
}

/* Whether an access to a list of the same length as `l` at index value `idx` comes before instruction `ii` of
 * block `bi` on every path. It either went through (so `idx` is below that length) or faulted (so this one is
 * never reached), whatever it checked. A list's length origin stands for every list of one length, so the
 * access need not be on `l` itself. */
static bool rg_access_before(const RgFa *fa, MirValue idx, MirValue l, uint32_t bi, uint32_t ii) {
  const MirValue origin = fa->lengths[l];
  if (origin == MIR_NONE) {
    return false;
  }
  for (uint32_t a = fa->acc_head[idx]; a != MIR_NONE; a = fa->accesses[a].next) {
    const RgAccess *access = &fa->accesses[a];
    if (access->origin != origin) {
      continue;
    }
    if (access->block == bi) {
      if (access->index < ii) {
        return true;
      }
      continue;
    }
    if (mir_tree_dominates(&fa->dom, access->block, bi)) {
      return true;
    }
  }
  return false;
}

/* Proves `idx >= 0` where the interval alone cannot, for `idx = x - y` with `y <= x`. */
static bool rg_nonneg(RgFa *fa, MirValue idx, const RgEnv *env) {
  if (rg_lo_at_least(fa, idx, 0, env)) {
    return true;
  }
  const MirInst *d = rg_def_inst(fa, idx);
  if (d == NULL || (d->op != MOP_ISub && d->op != MOP_ISubChk) || !rg_no_wrap(fa, d, env)) {
    return false;
  }
  return rg_prove(fa, d->args[1], (RgGoal){false, d->args[0]}, 0, env);
}

/* ---- the row-major index idiom ---- */

/* Whether `y * y` was computed without overflow on every path to instruction `ii` of block `bi`. */
static bool rg_square_fits(const RgFa *fa, MirValue y, uint32_t bi, uint32_t ii) {
  for (uint32_t s = fa->sq_head[y]; s != MIR_NONE; s = fa->squares[s].next) {
    const uint32_t sb = fa->squares[s].block;
    if (sb == bi) {
      if (fa->squares[s].index < ii) {
        return true;
      }
      continue;
    }
    if (mir_tree_dominates(&fa->dom, sb, bi)) {
      return true;
    }
  }
  return false;
}

/* `0 <= v < n`, by relation or by interval. */
static bool rg_index_below(const RgFa *fa, MirValue v, MirValue n, const RgEnv *env) {
  RgItv iv, in;
  bool lt, le;
  if (!rg_get(fa, v, env, &iv) || iv.lo < 0) {
    return false;
  }
  rg_rel_known(fa, v, n, env, &lt, &le);
  return lt || (rg_get(fa, n, env, &in) && iv.hi < in.lo);
}

static bool rg_flat_row(const RgFa *fa, MirValue x, MirValue n, uint32_t bi, uint32_t ii,
          const RgEnv *env) {
  return rg_index_below(fa, x, n, env) && rg_square_fits(fa, n, bi, ii);
}

/* `q = x * n` with `0 <= x < n`, and `j < n` when given. */
static bool rg_flat_product(const RgFa *fa, MirValue q, const MirValue *j, uint32_t bi, uint32_t ii,
            const RgEnv *env) {
  const MirInst *d = rg_def_inst(fa, q);
  if (d == NULL || (d->op != MOP_IMul && d->op != MOP_IMulChk) || !rg_no_wrap(fa, d, env)) {
    return false;
  }
  for (int k = 0; k < 2; k++) {
    const MirValue x = d->args[k], n = d->args[1 - k];
    if (rg_flat_row(fa, x, n, bi, ii, env) && (j == NULL || rg_index_below(fa, *j, n, env))) {
      return true;
    }
  }
  return false;
}

/* With a checked square `n * n`, `x * n` and `x * n + j` for `0 <= x, j < n` stay below `n * n`,
 * so they cannot overflow. */
static bool rg_flat_index_fits(const RgFa *fa, const MirInst *inst, uint32_t bi, uint32_t ii,
              const RgEnv *env) {
  if (inst->op == MOP_IMulChk) {
    return rg_flat_row(fa, inst->args[0], inst->args[1], bi, ii, env) ||
       rg_flat_row(fa, inst->args[1], inst->args[0], bi, ii, env);
  }
  if (inst->op == MOP_IAddChk) {
    return rg_flat_product(fa, inst->args[0], &inst->args[1], bi, ii, env) ||
       rg_flat_product(fa, inst->args[1], &inst->args[0], bi, ii, env);
  }
  return false;
}

/* ---- edits ---- */

static void rg_push_edit(RgFa *fa, RgEdits *out, RgEdit e) {
  OPT_PUSH(&fa->arena, out->v, out->n, out->cap, RgEdit, e);
}

static void rg_edit_op(RgFa *fa, RgEdits *out, uint32_t bi, uint32_t ii, MirOp op) {
  rg_push_edit(fa, out, (RgEdit){.kind = RG_EDIT_OP, .op = (uint8_t)op, .block = bi, .index = ii});
}

typedef struct RgSite {
  RgFa *fa;
  RgEdits *out;
  uint32_t bi, ii;
  const MirInst *inst;
  const RgEnv *env;
} RgSite;

static bool rg_site_args(const RgSite *s, RgItv *x, RgItv *y) {
  return rg_get(s->fa, s->inst->args[0], s->env, x) && rg_get(s->fa, s->inst->args[1], s->env, y);
}

static void rg_sum_range(MirOp op, RgItv x, RgItv y, RgWide *lo, RgWide *hi) {
  if (op == MOP_IAddChk || op == MOP_UAddChk || op == MOP_IAddOverflow) {
    *lo = (RgWide)x.lo + y.lo;
    *hi = (RgWide)x.hi + y.hi;
  } else if (op == MOP_ISubChk) {
    *lo = (RgWide)x.lo - y.hi;
    *hi = (RgWide)x.hi - y.lo;
  } else {
    rg_corners(RG_MUL, x, y, lo, hi);
  }
}

/* A checked integer operation whose exact result fits becomes the unchecked one. */
static void rg_edit_signed_arith(const RgSite *s) {
  RgItv x, y;
  RgWide lo, hi;
  if (!rg_site_args(s, &x, &y)) {
    return;
  }
  rg_sum_range((MirOp)s->inst->op, x, y, &lo, &hi);
  if (rg_fits(lo, hi) || rg_flat_index_fits(s->fa, s->inst, s->bi, s->ii, s->env)) {
    MirOp op = MOP_IMul;
    if (s->inst->op == MOP_IAddChk) {
      op = MOP_IAdd;
    } else if (s->inst->op == MOP_ISubChk) {
      op = MOP_ISub;
    }
    rg_edit_op(s->fa, s->out, s->bi, s->ii, op);
  }
}

static void rg_edit_unsigned_arith(const RgSite *s) {
  RgItv x, y;
  if (!rg_site_args(s, &x, &y) || x.lo < 0 || y.lo < 0) {
    return;
  }
  RgWide lo, hi;
  bool safe = false;
  MirOp op = MOP_IMul;
  if (s->inst->op == MOP_UAddChk) {
    rg_sum_range(MOP_UAddChk, x, y, &lo, &hi);
    safe = rg_fits(lo, hi);
    op = MOP_IAdd;
  } else if (s->inst->op == MOP_USubChk) {
    safe = x.lo >= y.hi;
    op = MOP_ISub;
  } else {
    rg_corners(RG_MUL, x, y, &lo, &hi);
    safe = rg_fits(lo, hi);
  }
  if (safe) {
    rg_edit_op(s->fa, s->out, s->bi, s->ii, op);
  }
}

static void rg_edit_overflow_flag(const RgSite *s) {
  RgItv x, y;
  RgWide lo, hi;
  if (!rg_site_args(s, &x, &y)) {
    return;
  }
  rg_sum_range((MirOp)s->inst->op, x, y, &lo, &hi);
  if (rg_fits(lo, hi)) {
    rg_push_edit(s->fa, s->out,
         (RgEdit){.kind = RG_EDIT_BOOL, .op = 0, .block = s->bi, .index = s->ii});
  }
}

static void rg_edit_div(const RgSite *s) {
  RgItv x, y;
  if (!rg_site_args(s, &x, &y)) {
    return;
  }
  const bool nonzero = y.lo > 0 || y.hi < 0;
  const bool minus_one = y.lo <= -1 && -1 <= y.hi;
  if (nonzero && (!minus_one || x.lo > INT64_MIN)) {
    rg_edit_op(s->fa, s->out, s->bi, s->ii, s->inst->op == MOP_SDivChk ? MOP_SDiv : MOP_SRem);
  }
}

/* Element access with an index proved non-negative (and below the length) skips its checks. */
static void rg_edit_list_access(const RgSite *s) {
  RgFa *fa = s->fa;
  const MirOp op = (MirOp)s->inst->op;
  RgItv i;
  if (!rg_get(fa, s->inst->args[1], s->env, &i)) {
    return;
  }
  const bool nn = rg_nonneg(fa, s->inst->args[1], s->env);
  const bool inside = nn && (rg_below_len(fa, s->inst->args[1], s->inst->args[0], s->env) ||
                rg_access_before(fa, s->inst->args[1], s->inst->args[0], s->bi, s->ii));
  const bool set = op == MOP_ListSet || op == MOP_ListSetNn;
  if (op == MOP_ListAddr) {
    if (inside) {
      rg_edit_op(fa, s->out, s->bi, s->ii, MOP_ListAddrU);
    }
  } else if (inside) {
    rg_edit_op(fa, s->out, s->bi, s->ii, set ? MOP_ListSetU : MOP_ListGetU);
  } else if (nn && (op == MOP_ListGet || op == MOP_ListSet)) {
    rg_edit_op(fa, s->out, s->bi, s->ii, set ? MOP_ListSetNn : MOP_ListGetNn);
  }
}

static void rg_edit_inst(const RgSite *s) {
  switch ((MirOp)s->inst->op) {
  case MOP_ListLen: {
    int64_t n = 0;
    if (rg_list_length(s->fa, s->inst->args[0], &n)) {
      rg_push_edit(s->fa, s->out,
           (RgEdit){.kind = RG_EDIT_INT, .block = s->bi, .index = s->ii, .value = n});
    }
    break;
  }
  case MOP_IAddChk: case MOP_ISubChk: case MOP_IMulChk:
    rg_edit_signed_arith(s);
    break;
  case MOP_UAddChk: case MOP_USubChk: case MOP_UMulChk:
    rg_edit_unsigned_arith(s);
    break;
  case MOP_IAddOverflow: case MOP_IMulOverflow:
    rg_edit_overflow_flag(s);
    break;
  case MOP_INegChk: {
    RgItv x;
    if (rg_get(s->fa, s->inst->args[0], s->env, &x) && x.lo != INT64_MIN) {
      rg_edit_op(s->fa, s->out, s->bi, s->ii, MOP_INeg);
    }
    break;
  }
  case MOP_SDivChk: case MOP_SRemChk:
    rg_edit_div(s);
    break;
  case MOP_ListGet: case MOP_ListGetNn: case MOP_ListSet: case MOP_ListSetNn: case MOP_ListAddr:
    rg_edit_list_access(s);
    break;
  case MOP_ICmp:
    if (s->inst->res != MIR_NONE && s->fa->has_base[s->inst->res] &&
      rg_is_point(s->fa->base[s->inst->res])) {
      rg_push_edit(s->fa, s->out,
           (RgEdit){.kind = RG_EDIT_BOOL,
               .op = s->fa->base[s->inst->res].lo != 0,
               .block = s->bi,
               .index = s->ii});
    }
    break;
  default:
    break;
  }
}

/* A switch on a known value goes to one target; cases outside the scrutinee's interval are dropped
 * (this also removes impossible `alt.tag` cases). */
static bool rg_fold_switch(RgFa *fa, const MirTerm *t, RgItv v, MirTerm *out) {
  if (rg_is_point(v)) {
    const MirTarget *hit = &t->b;
    for (uint32_t k = 0; k < t->ncases; k++) {
      if (t->cases[k].value == v.lo) {
        hit = &t->cases[k].target;
        break;
      }
    }
    *out = (MirTerm){.kind = MT_BR, .value = MIR_NONE, .a = *hit};
    return true;
  }
  MirCase *kept = RG_ZNEW(&fa->arena, MirCase, t->ncases + 1);
  uint32_t n = 0;
  for (uint32_t k = 0; k < t->ncases; k++) {
    if (v.lo <= t->cases[k].value && t->cases[k].value <= v.hi) {
      kept[n++] = t->cases[k];
    }
  }
  if (n == t->ncases) {
    return false;
  }
  *out = *t;
  if (n == 0) {
    *out = (MirTerm){.kind = MT_BR, .value = MIR_NONE, .a = t->b};
  } else {
    out->cases = kept;
    out->ncases = n;
  }
  return true;
}

/* A branch on a decided condition becomes a jump. */
static bool rg_fold_term(RgFa *fa, const MirTerm *t, const RgEnv *env, MirTerm *out) {
  RgItv v;
  if (t->kind == MT_CONDBR && rg_get(fa, t->value, env, &v) && rg_is_point(v)) {
    *out = (MirTerm){.kind = MT_BR, .value = MIR_NONE, .a = v.lo != 0 ? t->a : t->b};
    return true;
  }
  if (t->kind == MT_SWITCH && rg_get(fa, t->value, env, &v)) {
    return rg_fold_switch(fa, t, v, out);
  }
  return false;
}

void rg_collect_edits(RgFa *fa, RgEdits *out) {
  for (uint32_t r = 0; r < fa->nrpo; r++) {
    const uint32_t bi = fa->rpo[r];
    const MirBlockData *blk = &fa->f->blocks.ptr[bi];
    const RgEnv *env = &fa->envs[bi];
    for (uint32_t ii = 0; ii < blk->insts.len; ii++) {
      rg_tmp_reset(fa);
      const RgSite site = {fa, out, bi, ii, &blk->insts.ptr[ii], env};
      rg_edit_inst(&site);
    }
    rg_tmp_reset(fa);
    MirTerm folded;
    if (rg_fold_term(fa, &blk->term, env, &folded)) {
      RgEdit e = {.kind = RG_EDIT_TERM, .block = bi, .term = folded};
      rg_push_edit(fa, out, e);
    }
  }
  rg_tmp_reset(fa);
}

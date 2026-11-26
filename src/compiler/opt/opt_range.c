/* Range analysis and check elimination.
 *
 * A sparse interval analysis over `Int` and `Bool` SSA values (i64 intervals, Booleans as `0..=1`)
 * followed by rewrites that remove checks the analysis proves redundant:
 *
 *  - `iadd.chk`/`isub.chk`/`imul.chk`/`ineg.chk` become the unchecked forms when the exact result
 *    interval fits in `i64`;
 *  - `sdiv.chk`/`srem.chk` become `sdiv`/`srem` when the divisor is provably nonzero and not `-1`
 *    (or the dividend is provably not `i64::MIN`);
 *  - `list.get`/`list.set` become their `.nn` forms when the index is provably non-negative, and
 *    the `.u` forms when it is also provably below the length;
 *  - `icmp` with a decided result becomes `bconst`, a `br_if` on a decided condition becomes `br`,
 *    and `switch` cases outside the scrutinee's interval are dropped.
 *
 * How facts are found: block parameters join the intervals passed on every incoming edge; at loop
 * headers the join widens to a large threshold and then the type bound after a few growing rounds,
 * and a few narrowing rounds recover precision. Conditional edges refine the compared values
 * (opt_range_refine.c); `idx < list.len l` is proved by a goal-directed search (opt_range_prove.c).
 * An element access that has run proves its index below the length for every later access at the same index value
 * of a list with the same length origin (`rg_access_before`): the first one checks, the rest do not.
 * An induction variable is bounded by the upper bound of the value it is guarded by, because the
 * guard refines the value that feeds the back edge. `list.len` results lie in `0..=2^47`.
 *
 * Bounded counters: a loop-carried `Int` that starts in a small range (`|v| <= 2^40`) and
 * otherwise changes only by one constant step of size at most `2^16` in one direction per
 * iteration is assumed to stay within `i64::MAX/2` (or `i64::MIN/2`). Reaching that bound takes
 * more than `2^46` iterations, so no physically possible run overflows such a counter. This is the
 * one assumption beyond a pure proof.
 *
 * Environments are sorted arrays in two arenas: the round being built and the one before it,
 * which back edges still read.  */
#include "compiler/opt/opt_range.h"

enum {
  RG_COUNTER_STEP_MAX = 1 << 16,
  RG_WIDEN_AFTER = 3,
  RG_MAX_ROUNDS = 60,
  RG_NARROW_ROUNDS = 3,
};
#define RG_COUNTER_INIT_MAX ((int64_t)1 << 40)
/* The bound a growing interval widens to before the type bound (`2^56`). */
#define RG_WIDEN_LIMIT ((int64_t)1 << 56)

/* ---- setup ---- */

static void rg_init_defs(RgFa *fa) {
  const MirFunc *f = fa->f;
  fa->def_blk = RG_ZNEW(&fa->arena, uint32_t, fa->nv + 1);
  fa->def_idx = RG_ZNEW(&fa->arena, uint32_t, fa->nv + 1);
  fa->param_blk = RG_ZNEW(&fa->arena, uint32_t, fa->nv + 1);
  fa->param_idx = RG_ZNEW(&fa->arena, uint32_t, fa->nv + 1);
  fa->lenof = RG_ZNEW(&fa->arena, MirValue, fa->nv + 1);
  __builtin_memset(fa->def_blk, 0xFF, ((size_t)fa->nv + 1) * sizeof(uint32_t));
  __builtin_memset(fa->param_blk, 0xFF, ((size_t)fa->nv + 1) * sizeof(uint32_t));
  __builtin_memset(fa->lenof, 0xFF, ((size_t)fa->nv + 1) * sizeof(MirValue));
  for (uint32_t bi = 0; bi < fa->nb; bi++) {
    const MirBlockData *b = &f->blocks.ptr[bi];
    for (uint32_t ii = 0; ii < b->insts.len; ii++) {
      const MirInst *i = &b->insts.ptr[ii];
      if (i->res == MIR_NONE) {
        continue;
      }
      fa->def_blk[i->res] = bi;
      fa->def_idx[i->res] = ii;
      if (i->op == MOP_ListLen) {
        fa->lenof[i->res] = fa->lengths[i->args[0]];
      }
    }
    for (uint32_t pi = 0; bi != 0 && pi < b->params.len; pi++) {
      fa->param_blk[b->params.ptr[pi].value] = bi;
      fa->param_idx[b->params.ptr[pi].value] = pi;
    }
  }
}

/* Calls `visit(ctx, kind, key, target)` for each edge out of block `bi`. */
typedef void (*RgEdgeFn)(RgFa *fa, uint32_t bi, uint8_t kind, int64_t key, const MirTarget *t,
           uint32_t *fill);

static void rg_for_each_edge(RgFa *fa, uint32_t bi, RgEdgeFn fn, uint32_t *fill) {
  const MirTerm *t = &fa->f->blocks.ptr[bi].term;
  if (t->kind == MT_BR) {
    fn(fa, bi, RG_PLAIN, 0, &t->a, fill);
  } else if (t->kind == MT_CONDBR) {
    fn(fa, bi, RG_THEN, 0, &t->a, fill);
    fn(fa, bi, RG_ELSE, 0, &t->b, fill);
  } else if (t->kind == MT_SWITCH) {
    for (uint32_t k = 0; k < t->ncases; k++) {
      fn(fa, bi, RG_CASE, t->cases[k].value, &t->cases[k].target, fill);
    }
    fn(fa, bi, RG_DEFAULT, 0, &t->b, fill);
  }
}

/* Counts the edge into its target block, or, given the fill cursors, stores it. */
static void rg_record_edge(RgFa *fa, uint32_t bi, uint8_t kind, int64_t key, const MirTarget *t,
            uint32_t *fill) {
  if (fill == NULL) {
    fa->in_start[t->block + 1]++;
    return;
  }
  RgEdge *e = &fa->in[fa->in_start[t->block] + fill[t->block]++];
  *e = (RgEdge){bi, kind, key, t->args, t->nargs};
}

/* The edges into each block, in reverse post-order of the blocks they leave. */
static void rg_init_edges(RgFa *fa) {
  fa->in_start = RG_ZNEW(&fa->arena, uint32_t, (size_t)fa->nb + 2);
  for (uint32_t r = 0; r < fa->nrpo; r++) {
    rg_for_each_edge(fa, fa->rpo[r], rg_record_edge, NULL);
  }
  for (uint32_t b = 0; b < fa->nb; b++) {
    fa->in_start[b + 1] += fa->in_start[b];
  }
  fa->in = RG_ZNEW(&fa->arena, RgEdge, (size_t)fa->in_start[fa->nb] + 1);
  uint32_t *fill = RG_ZNEW(&fa->arena, uint32_t, (size_t)fa->nb + 1);
  for (uint32_t r = 0; r < fa->nrpo; r++) {
    rg_for_each_edge(fa, fa->rpo[r], rg_record_edge, fill);
  }
}

typedef struct RgReadCx {
  RgFa *fa;
  uint32_t pos;
} RgReadCx;

static void rg_note_read(RgFa *fa, MirValue v, uint32_t pos) {
  uint32_t *slot = &fa->last_read[rg_class(fa, v)];
  *slot = *slot > pos ? *slot : pos;
}

static void rg_term_read(void *ctx, MirValue v) {
  const RgReadCx *c = ctx;
  rg_note_read(c->fa, v, c->pos);
}

/* The reverse-postorder position of the last block that reads each value, by length class. A fact
 * about a value no block at or after a position reads is dropped from the environments built
 * there, so they stay as large as what is live (a chain of many loops would otherwise make the
 * pass quadratic). */
static void rg_init_last_read(RgFa *fa) {
  fa->last_read = RG_ZNEW(&fa->arena, uint32_t, fa->nv + 1);
  for (uint32_t r = 0; r < fa->nrpo; r++) {
    const MirBlockData *blk = &fa->f->blocks.ptr[fa->rpo[r]];
    for (uint32_t ii = 0; ii < blk->insts.len; ii++) {
      for (uint32_t k = 0; k < blk->insts.ptr[ii].nargs; k++) {
        rg_note_read(fa, blk->insts.ptr[ii].args[k], r);
      }
    }
    RgReadCx cx = {fa, r};
    mir_term_each_value(&blk->term, rg_term_read, &cx);
  }
}

static void rg_init_squares(RgFa *fa) {
  fa->sq_head = RG_ZNEW(&fa->arena, uint32_t, fa->nv + 1);
  __builtin_memset(fa->sq_head, 0xFF, ((size_t)fa->nv + 1) * sizeof(uint32_t));
  for (uint32_t bi = 0; bi < fa->nb; bi++) {
    for (uint32_t ii = 0; ii < fa->f->blocks.ptr[bi].insts.len; ii++) {
      const MirInst *i = &fa->f->blocks.ptr[bi].insts.ptr[ii];
      if (i->op == MOP_IMulChk && i->args[0] == i->args[1]) {
        const RgSquare sq = {bi, ii, fa->sq_head[i->args[0]]};
        fa->sq_head[i->args[0]] = fa->nsq;
        OPT_PUSH(&fa->arena, fa->squares, fa->nsq, fa->csq, RgSquare, sq);
      }
    }
  }
}

static bool rg_is_element_access(MirOp op) {
  switch (op) {
  case MOP_ListGet: case MOP_ListGetNn: case MOP_ListGetU: case MOP_ListSet: case MOP_ListSetNn:
  case MOP_ListSetU: case MOP_ListAddr: case MOP_ListAddrU:
    return true;
  default:
    return false;
  }
}

static void rg_init_accesses(RgFa *fa) {
  fa->acc_head = RG_ZNEW(&fa->arena, uint32_t, fa->nv + 1);
  __builtin_memset(fa->acc_head, 0xFF, ((size_t)fa->nv + 1) * sizeof(uint32_t));
  for (uint32_t bi = 0; bi < fa->nb; bi++) {
    for (uint32_t ii = 0; ii < fa->f->blocks.ptr[bi].insts.len; ii++) {
      const MirInst *i = &fa->f->blocks.ptr[bi].insts.ptr[ii];
      if (!rg_is_element_access((MirOp)i->op) || i->nargs < 2 || fa->lengths[i->args[0]] == MIR_NONE) {
        continue;
      }
      const RgAccess access = {bi, ii, fa->acc_head[i->args[1]], fa->lengths[i->args[0]]};
      fa->acc_head[i->args[1]] = fa->nacc;
      OPT_PUSH(&fa->arena, fa->accesses, fa->nacc, fa->cacc, RgAccess, access);
    }
  }
}

void rg_fa_init(RgFa *fa, const MirModule *m, const MirFunc *f) {
  *fa = (RgFa){.m = m, .f = f, .nv = (uint32_t)f->values.len, .nb = (uint32_t)f->blocks.len};
  fa->lengths = rg_length_origins(&fa->arena, m, f);
  rg_alias_loop_lists(&fa->tmp, m, f, fa->lengths);
  rg_tmp_reset(fa);
  fa->byte_lists = rg_byte_lists(&fa->arena, m, f);
  rg_init_defs(fa);
  MirPreds preds = mir_preds(&fa->arena, f);
  fa->nrpo = mir_rpo(&fa->arena, f, &fa->rpo);
  fa->idom = mir_dominators(&fa->arena, f, fa->rpo, fa->nrpo, &preds);
  fa->dom = mir_dom_tree(&fa->arena, f, fa->rpo, fa->nrpo, fa->idom);
  fa->rpo_pos = RG_ZNEW(&fa->arena, uint32_t, (size_t)fa->nb + 1);
  for (uint32_t r = 0; r < fa->nrpo; r++) {
    fa->rpo_pos[fa->rpo[r]] = r;
  }
  rg_init_edges(fa);
  rg_counted_lists(fa, fa->lenof);
  rg_init_last_read(fa);
  fa->base = RG_ZNEW(&fa->arena, RgItv, fa->nv + 1);
  fa->has_base = RG_ZNEW(&fa->arena, uint8_t, fa->nv + 1);
  for (uint32_t p = 0; p < f->blocks.ptr[0].params.len; p++) {
    const MirValue v = f->blocks.ptr[0].params.ptr[p].value;
    if (rg_tracked(f->values.ptr[v])) {
      fa->has_base[v] = 1;
      fa->base[v] = f->values.ptr[v] == MIR_BOOL ? RG_BOOL : RG_TOP;
      if (f->entry != NULL && p < f->nentry && p < f->nparams) {
        fa->base[v] = (RgItv){f->entry[2 * p], f->entry[2 * p + 1]};
      }
    }
  }
  rg_init_squares(fa);
  rg_init_accesses(fa);
  fa->envs = RG_ZNEW(&fa->arena, RgEnv, fa->nb + 1);
  fa->widen = RG_ZNEW(&fa->arena, uint32_t, fa->nv + 1);
}

void rg_fa_free(RgFa *fa) {
  ms_arena_free(&fa->arena);
  ms_arena_free(&fa->gen[0]);
  ms_arena_free(&fa->gen[1]);
  ms_arena_free(&fa->tmp);
}

/* ---- block parameters ---- */

/* The constant `c` for which `a = p + c`, if `a` is such an add or subtract (or a select between
 * such a step and no step). */
static bool rg_step_of(const RgFa *fa, MirValue a, MirValue p, int64_t *out) {
  const MirInst *i = rg_def_inst(fa, a);
  if (i == NULL) {
    return false;
  }
  if (i->op == MOP_IAdd || i->op == MOP_IAddChk) {
    if (i->args[0] == p) {
      return rg_constant(fa, i->args[1], out);
    }
    return i->args[1] == p && rg_constant(fa, i->args[0], out);
  }
  if ((i->op == MOP_ISub || i->op == MOP_ISubChk) && i->args[0] == p) {
    int64_t c = 0;
    if (!rg_constant(fa, i->args[1], &c) || c == INT64_MIN) {
      return false;
    }
    *out = -c;
    return true;
  }
  if (i->op != MOP_Select) {
    return false;
  }
  /* A conditional step (`if c { p += k }` after if-conversion) steps by `k` or not at all. */
  int64_t x = 0, y = 0;
  if ((i->args[1] != p && !rg_step_of(fa, i->args[1], p, &x)) ||
    (i->args[2] != p && !rg_step_of(fa, i->args[2], p, &y))) {
    return false;
  }
  if (x == 0 && y != 0) {
    *out = y;
    return true;
  }
  if ((y == 0 || x == y) && x != 0) {
    *out = x;
    return true;
  }
  return false;
}

/* The interval of the amount `a` adds to or subtracts from `p`, when `a` is `p + q` or `p - q` with
 * `q` a value whose range is known (a widened byte, a bounded index). */
static bool rg_step_range(const RgFa *fa, MirValue a, MirValue p, const RgEnv *env, RgItv *out) {
  const MirInst *i = rg_def_inst(fa, a);
  if (i == NULL) {
    return false;
  }
  MirValue q = 0;
  bool neg = false;
  if ((i->op == MOP_IAdd || i->op == MOP_IAddChk) && i->args[0] == p) {
    q = i->args[1];
  } else if ((i->op == MOP_IAdd || i->op == MOP_IAddChk) && i->args[1] == p) {
    q = i->args[0];
  } else if ((i->op == MOP_ISub || i->op == MOP_ISubChk) && i->args[0] == p) {
    q = i->args[1];
    neg = true;
  } else {
    return false;
  }
  RgItv r;
  if (!rg_get(fa, q, env, &r)) {
    return false;
  }
  if (!neg) {
    *out = r;
    return true;
  }
  if (r.hi == INT64_MIN || r.lo == INT64_MIN) {
    return false;
  }
  *out = (RgItv){-r.hi, -r.lo};
  return true;
}

static uint64_t rg_abs_u64(int64_t v) { return v < 0 ? 0 - (uint64_t)v : (uint64_t)v; }

/* How the incoming arguments of a parameter step it: counts per direction, whether every argument
 * is a bounded step or a small initial value, and the join of the initial values. */
typedef struct RgCounter {
  int ups, downs, mixed;
  bool ok, has_others;
  RgItv others;
} RgCounter;

static void rg_note_step(RgCounter *c, RgItv s) {
  if (s.lo >= 0) {
    c->ups++;
  } else if (s.hi <= 0) {
    c->downs++;
  } else {
    c->mixed++;
  }
}

/* One incoming edge's contribution to the counter shape of parameter `p`. */
static void rg_note_edge(const RgFa *fa, RgCounter *c, MirValue p, MirValue a, const RgEnv *env,
           bool has_itv, RgItv itv) {
  int64_t k = 0;
  RgItv s = RG_TOP;
  bool has_step = rg_step_of(fa, a, p, &k);
  if (has_step) {
    s = rg_point(k);
  } else {
    has_step = rg_step_range(fa, a, p, env, &s);
  }
  if (!has_step) {
    if (has_itv && itv.lo >= -RG_COUNTER_INIT_MAX && itv.hi <= RG_COUNTER_INIT_MAX) {
      c->others = c->has_others ? rg_join(c->others, itv) : itv;
      c->has_others = true;
    } else {
      c->ok = false;
    }
  } else if ((s.lo != 0 || s.hi != 0) && rg_abs_u64(s.lo) <= RG_COUNTER_STEP_MAX &&
       rg_abs_u64(s.hi) <= RG_COUNTER_STEP_MAX) {
    rg_note_step(c, s);
  } else {
    c->ok = false;
  }
}

/* The interval of block parameter `pi` of block `bi`: the join of what its incoming edges pass, or
 * for a bounded counter the half range it stays in. False when no edge passes a known interval. */
static bool rg_param_itv(RgFa *fa, uint32_t bi, uint32_t pi, RgItv *out) {
  const MirValue p = fa->f->blocks.ptr[bi].params.ptr[pi].value;
  RgItv acc = RG_TOP;
  bool has_acc = false;
  RgCounter c = {.ok = true};
  for (uint32_t k = fa->in_start[bi]; k < fa->in_start[bi + 1]; k++) {
    const MirValue a = fa->in[k].args[pi];
    RgEnv env = rg_edge_env(fa, rg_tmp(fa), &fa->in[k]);
    RgItv itv;
    const bool has_itv = rg_get(fa, a, &env, &itv);
    if (has_itv) {
      acc = has_acc ? rg_join(acc, itv) : itv;
      has_acc = true;
    }
    if (a != p) {
      rg_note_edge(fa, &c, p, a, &env, has_itv, itv);
    }
  }
  if (c.ok && c.ups + c.downs + c.mixed > 0 && c.has_others && has_acc) {
    RgItv bound = {c.others.lo, INT64_MAX / 2};
    if (c.mixed > 0 || (c.ups > 0 && c.downs > 0)) {
      bound = (RgItv){INT64_MIN / 2, INT64_MAX / 2};
    } else if (c.ups == 0) {
      bound = (RgItv){INT64_MIN / 2, c.others.hi};
    }
    RgItv met;
    *out = rg_meet(acc, bound, &met) ? met : bound;
    return true;
  }
  *out = acc;
  return has_acc;
}

/* A bound that keeps growing jumps to a large threshold that arithmetic on it cannot wrap
 * (`2 * x + 1`), and only to the type bound if it outgrows that. Jumping straight to the type
 * bound makes such a step wrap to top, and the other bound is lost with it in a cycle that
 * narrowing cannot repair. */
static RgItv rg_widen_step(RgFa *fa, MirValue v, RgItv old, RgItv fresh) {
  const RgItv joined = rg_join(old, fresh);
  if (rg_itv_eq(joined, old)) {
    return old;
  }
  if (++fa->widen[v] <= RG_WIDEN_AFTER) {
    return joined;
  }
  RgItv r = old;
  if (joined.lo < old.lo) {
    r.lo = joined.lo >= -RG_WIDEN_LIMIT ? -RG_WIDEN_LIMIT : INT64_MIN;
  }
  if (joined.hi > old.hi) {
    r.hi = joined.hi <= RG_WIDEN_LIMIT ? RG_WIDEN_LIMIT : INT64_MAX;
  }
  return r;
}

/* ---- the fixpoint ---- */

static bool rg_set_base(RgFa *fa, MirValue v, RgItv next) {
  if (fa->has_base[v] && rg_itv_eq(fa->base[v], next)) {
    return false;
  }
  fa->has_base[v] = 1;
  fa->base[v] = next;
  return true;
}

static bool rg_pass_params(RgFa *fa, uint32_t bi, bool narrow) {
  bool changed = false;
  const MirBlockData *blk = &fa->f->blocks.ptr[bi];
  for (uint32_t pi = 0; bi != 0 && pi < blk->params.len; pi++) {
    const MirValue v = blk->params.ptr[pi].value;
    RgItv fresh, next, met;
    rg_tmp_reset(fa);
    if (!rg_tracked(fa->f->values.ptr[v]) || !rg_param_itv(fa, bi, pi, &fresh)) {
      continue;
    }
    if (!fa->has_base[v]) {
      next = fresh;
    } else if (narrow) {
      next = rg_meet(fa->base[v], fresh, &met) ? met : fresh;
    } else {
      next = rg_widen_step(fa, v, fa->base[v], fresh);
    }
    changed = rg_set_base(fa, v, next) || changed;
  }
  return changed;
}

/* One round over the blocks in reverse post-order; returns whether any interval changed. */
static bool rg_fa_pass(RgFa *fa, bool narrow) {
  bool changed = false;
  ms_arena_reset(&fa->gen[fa->round & 1]);
  for (uint32_t r = 0; r < fa->nrpo; r++) {
    const uint32_t bi = fa->rpo[r];
    rg_tmp_reset(fa);
    rg_build_env(fa, bi, &fa->envs[bi]);
    rg_tmp_reset(fa);
    changed = rg_pass_params(fa, bi, narrow) || changed;
    const MirBlockData *blk = &fa->f->blocks.ptr[bi];
    for (uint32_t ii = 0; ii < blk->insts.len; ii++) {
      RgItv fresh;
      if (blk->insts.ptr[ii].res != MIR_NONE && rg_eval(fa, &blk->insts.ptr[ii], &fa->envs[bi], &fresh)) {
        changed = rg_set_base(fa, blk->insts.ptr[ii].res, fresh) || changed;
      }
    }
  }
  fa->round++;
  return changed;
}

/* Computes the fixpoint; false when it did not converge (no facts may be used). */
bool rg_fa_solve(RgFa *fa) {
  bool converged = false;
  for (int i = 0; i < RG_MAX_ROUNDS && !converged; i++) {
    converged = !rg_fa_pass(fa, false);
  }
  if (!converged) {
    return false;
  }
  for (int i = 0; i < RG_NARROW_ROUNDS; i++) {
    if (!rg_fa_pass(fa, true)) {
      break;
    }
  }
  /* Make envs and bases mutually consistent after the last narrowing round. */
  rg_fa_pass(fa, true);
  return true;
}

/* ---- rewriting ---- */

static void rg_apply_edit(MirModule *m, MirFunc *f, uint64_t *exact, const RgEdit *e) {
  if (e->kind == RG_EDIT_TERM) {
    MirTerm t = e->term;
    if (t.kind == MT_SWITCH) {
      t.cases = MS_ARENA_NEW_ARRAY(&m->arena, MirCase, t.ncases);
      __builtin_memcpy(t.cases, e->term.cases, (size_t)t.ncases * sizeof(MirCase));
    }
    f->blocks.ptr[e->block].term = t;
    return;
  }
  MirInst *inst = &f->blocks.ptr[e->block].insts.ptr[e->index];
  if (e->kind == RG_EDIT_OP) {
    inst->op = e->op;
    const bool unchecked = e->op == MOP_IAdd || e->op == MOP_ISub || e->op == MOP_IMul || e->op == MOP_INeg;
    if (unchecked && inst->res != MIR_NONE) {
      exact[inst->res >> 6] |= UINT64_C(1) << (inst->res & 63);
    }
  } else if (e->kind == RG_EDIT_BOOL) {
    inst->op = MOP_BConst;
    inst->nargs = 0;
    inst->imm = (MirImm){.tag = MI_BOOL, .a = e->op};
  } else {
    inst->op = MOP_IConst;
    inst->nargs = 0;
    inst->imm = (MirImm){.tag = MI_INT, .i = e->value};
  }
}

/* Applies the edits and records the values proved not to wrap (in a fresh set: the old one may be
 * shared with a copy of the function). */
static void rg_apply_edits(MirModule *m, MirFunc *f, const RgEdits *edits) {
  const uint32_t words = (uint32_t)((f->values.len + 63) / 64 + 1);
  uint64_t *exact = MS_ARENA_NEW_ARRAY(&m->arena, uint64_t, words);
  __builtin_memset(exact, 0, (size_t)words * sizeof *exact);
  if (f->nexact != 0) {
    __builtin_memcpy(exact, f->exact, (size_t)f->nexact * sizeof *exact);
  }
  bool terms = false;
  for (uint32_t i = 0; i < edits->n; i++) {
    rg_apply_edit(m, f, exact, &edits->v[i]);
    terms = terms || edits->v[i].kind == RG_EDIT_TERM;
  }
  f->exact = exact;
  f->nexact = words;
  if (terms) {
    mir_func_compact_blocks(f);
  }
}

/* Records the interval of each loop and join parameter the analysis bounded, for the emitter to hand to LLVM:
 * a test the pass folded away was the only way LLVM could see the bound. Returns whether the list changed. */
static bool rg_record_facts(RgFa *fa, MirModule *m, MirFunc *f) {
  uint32_t n = 0;
  MirFact *facts = MS_ARENA_NEW_ARRAY(&m->arena, MirFact, (size_t)fa->nv + 1);
  for (uint32_t v = 0; v < fa->nv; v++) {
    if (f->values.ptr[v] != MIR_INT || !fa->has_base[v] || fa->param_blk[v] == 0xFFFFFFFFu) {
      continue;
    }
    /* A bound at the widening limit is where the analysis gave up, not a fact. */
    RgItv x = fa->base[v];
    x.lo = x.lo <= -RG_WIDEN_LIMIT ? INT64_MIN : x.lo;
    x.hi = x.hi >= RG_WIDEN_LIMIT ? INT64_MAX : x.hi;
    if (x.lo != INT64_MIN || x.hi != INT64_MAX) {
      facts[n++] = (MirFact){v, x.lo, x.hi};
    }
  }
  bool same = n == f->nfacts;
  for (uint32_t i = 0; same && i < n; i++) {
    same = facts[i].value == f->facts[i].value && facts[i].lo == f->facts[i].lo && facts[i].hi == f->facts[i].hi;
  }
  if (same) {
    return false;
  }
  f->facts = n != 0 ? facts : NULL;
  f->nfacts = n;
  return true;
}

/* Runs the pass over one function; returns whether it changed. */
bool opt_range_func(MirModule *m, MirFunc *f) {
  RgFa fa;
  rg_fa_init(&fa, m, f);
  RgEdits edits = {0};
  const bool solved = rg_fa_solve(&fa);
  if (solved) {
    rg_collect_edits(&fa, &edits);
  }
  bool changed = edits.n != 0;
  if (changed) {
    rg_apply_edits(m, f, &edits);
  }
  if (solved && f->entry != NULL) { /* seeding is what folds a guard LLVM would have used */
    changed = rg_record_facts(&fa, m, f) || changed;
  }
  rg_fa_free(&fa);
  return changed;
}

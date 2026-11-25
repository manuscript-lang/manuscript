/* opt_unwind_thread: an edge that knows the `unwinding` byte skips the test of it.
 *
 * After a call is inlined, its exit and the caller's site test meet:
 *
 *     P: s = fault.site r ; br_if s, X(), C(r)        X: pause ; resume ; u = undef ; br C(u)
 *     C(m): t = unwinding ; br_if t, E(), N()         E: <the caller's exit>      N: <uses m>
 *
 * The edge from `fault.site` false means no check posted, and the byte is clear (every earlier call that can post was
 * tested, and every check runs with the byte clear); the exit `X` ends in `resume`, which leaves it set. Each such edge
 * goes straight to the target the byte selects, so the hot path never loads it. A parameter of `C` that a target uses
 * becomes a parameter of that target, which has no other predecessor. Cold exits repeat, one per threaded edge. */
#include "compiler/mir/mir_analysis.h"
#include "compiler/opt/opt_pass.h"
#include "compiler/opt/opt_util.h"
#include "base/safe.h"

enum { UT_ROUNDS = 256, UT_CHAIN = 8 };

/* Whether `in` may run code that posts: a call, a drop or clone that closes, a check (a refused allocation ends the
 * process instead). */
static bool may_post(const MirInst *in) {
  const uint8_t fx = mir_op_info[in->op].effects;
  return (fx & (MIR_E_OWNERSHIP | MIR_E_IO)) != 0 || ((fx & MIR_E_FAULTS) != 0 && (fx & MIR_E_OOM) == 0);
}

typedef enum UtState { UT_UNKNOWN, UT_CLEAR, UT_SET } UtState;

typedef struct Ut {
  MirModule *m;
  MirFunc *f;
  MsName resume; /* the name of `msrt_unwinding_resume`, or MS_NAME_EMPTY */
} Ut;

static bool is_unwinding_call(const MirModule *m, const MirInst *in) {
  return in->op == MOP_CallRt && in->imm.tag == MI_EXT && m->externs.ptr[in->imm.a].role == MR_UNWINDING;
}

static bool is_call(const MirInst *in) {
  return in->op == MOP_Call || in->op == MOP_CallRt || in->op == MOP_CallInd || in->op == MOP_CallMethod;
}

/* The last instruction of `b` when it defines `value`, or NULL: nothing runs between the test and the branch. */
static const MirInst *def_in(const MirBlockData *b, MirValue value) {
  if (b->insts.len > 0 && b->insts.ptr[b->insts.len - 1].res == value) {
    return &b->insts.ptr[b->insts.len - 1];
  }
  return NULL;
}

/* What the branch of `p` says about the byte on its `slot`'th edge (0 then, 1 else). */
static UtState branch_state(const Ut *t, const MirBlockData *p, uint32_t slot) {
  if (p->term.kind != MT_CONDBR) {
    return UT_UNKNOWN;
  }
  const MirInst *def = def_in(p, p->term.value);
  if (def == NULL) {
    return UT_UNKNOWN;
  }
  if (def->op == MOP_FaultSite || is_unwinding_call(t->m, def)) {
    return slot == 0 ? UT_SET : UT_CLEAR;
  }
  return UT_UNKNOWN;
}

static UtState state_in(const Ut *t, const MirPreds *preds, MirBlock p, uint32_t depth);

/* The state of the byte at the end of `p`: the last call in it is `resume`, or nothing in it posts and the state is
 * what it was on entry. */
static UtState state_out(const Ut *t, const MirPreds *preds, MirBlock p, uint32_t depth) {
  const MirBlockData *b = &t->f->blocks.ptr[p];
  for (size_t i = b->insts.len; i > 0; i--) {
    const MirInst *in = &b->insts.ptr[i - 1];
    if (in->op == MOP_CallRt && in->imm.tag == MI_EXT && t->resume != MS_NAME_EMPTY &&
      t->m->externs.ptr[in->imm.a].name == t->resume) {
      return UT_SET;
    }
    if (is_call(in) || may_post(in)) {
      return UT_UNKNOWN;
    }
  }
  return state_in(t, preds, p, depth);
}

/* The state of the byte on entry to `p`: it has one predecessor, whose branch decided it or which leaves it as it was. */
static UtState state_in(const Ut *t, const MirPreds *preds, MirBlock p, uint32_t depth) {
  if (depth == 0 || mir_preds_count(preds, p) != 1) {
    return UT_UNKNOWN;
  }
  const MirBlock q = mir_pred(preds, p, 0);
  const MirTerm *qt = &t->f->blocks.ptr[q].term;
  if (qt->kind == MT_CONDBR) {
    if (qt->a.block == p && qt->b.block == p) {
      return UT_UNKNOWN;
    }
    const UtState decided = branch_state(t, &t->f->blocks.ptr[q], qt->a.block == p ? 0 : 1);
    if (decided != UT_UNKNOWN) {
      return decided;
    }
  } else if (qt->kind != MT_BR) {
    return UT_UNKNOWN;
  }
  return state_out(t, preds, q, depth - 1);
}

/* The state of the byte on `p`'s `slot`'th edge. */
static UtState edge_state(const Ut *t, const MirPreds *preds, MirBlock p, uint32_t slot) {
  const MirBlockData *b = &t->f->blocks.ptr[p];
  const UtState decided = branch_state(t, b, slot);
  return decided != UT_UNKNOWN ? decided : state_out(t, preds, p, UT_CHAIN);
}

/* The dominator tree as preorder intervals: `a` dominates `b` when `b`'s number lies in `a`'s interval, so a query costs
 * two compares however deep the tree is. */
typedef struct UtDom {
  const MirBlock *idom;
  uint32_t *pre;  /* preorder number in the tree of a reachable block */
  uint32_t *size; /* blocks in the subtree */
} UtDom;

static UtDom ut_dom(MsArena *arena, const MirFunc *f, const MirBlock *order, uint32_t reachable, const MirBlock *idom) {
  const size_t n = f->blocks.len;
  UtDom d = {.idom = idom, .pre = MS_ARENA_NEW_ARRAY(arena, uint32_t, n + 1), .size = MS_ARENA_NEW_ARRAY(arena, uint32_t, n + 1)};
  uint32_t *next = MS_ARENA_NEW_ARRAY(arena, uint32_t, n + 1);
  for (uint32_t i = 0; i < reachable; i++) {
    d.size[order[i]] = 1;
  }
  for (uint32_t i = reachable; i > 1; i--) { /* the entry is first, and a block follows its dominator */
    d.size[idom[order[i - 1]]] += d.size[order[i - 1]];
  }
  for (uint32_t i = 0; i < reachable; i++) {
    const MirBlock b = order[i];
    d.pre[b] = i == 0 ? 0 : next[idom[b]];
    if (i != 0) {
      next[idom[b]] += d.size[b];
    }
    next[b] = d.pre[b] + 1;
  }
  return d;
}

static bool dominates(const UtDom *d, MirBlock a, MirBlock b) {
  return d->idom[a] != MIR_NONE && d->idom[b] != MIR_NONE && d->pre[b] >= d->pre[a] && d->pre[b] - d->pre[a] < d->size[a];
}

typedef struct UtReplace {
  MirValue from, to;
} UtReplace;

static void replace_use(void *context, MirValue *v) {
  const UtReplace *r = context;
  if (*v == r->from) {
    *v = r->to;
  }
}

static void replace_in(MirBlockData *b, UtReplace r) {
  for (size_t i = 0; i < b->insts.len; i++) {
    MirInst *in = &b->insts.ptr[i];
    for (uint32_t k = 0; k < in->nargs; k++) {
      if (in->args[k] == r.from) {
        in->args[k] = r.to;
      }
    }
  }
  mir_term_each_use(&b->term, replace_use, &r);
}

typedef struct UtFind {
  MirValue value;
  bool found;
} UtFind;

static void find_use(void *context, MirValue v) {
  UtFind *find = context;
  find->found = find->found || v == find->value;
}

static bool uses_value(const MirBlockData *b, MirValue v) {
  for (size_t i = 0; i < b->insts.len; i++) {
    for (uint32_t k = 0; k < b->insts.ptr[i].nargs; k++) {
      if (b->insts.ptr[i].args[k] == v) {
        return true;
      }
    }
  }
  UtFind find = {.value = v};
  mir_term_each_value(&b->term, find_use, &find);
  return find.found;
}

/* Whether `c` is `[t = unwinding ; br_if t, T(..), F(..)]` whose targets have no other predecessor. */
static bool candidate(const Ut *t, MirBlock c) {
  const MirBlockData *cb = &t->f->blocks.ptr[c];
  if (cb->insts.len != 1 || !is_unwinding_call(t->m, &cb->insts.ptr[0]) || cb->term.kind != MT_CONDBR ||
    cb->term.value != cb->insts.ptr[0].res) {
    return false;
  }
  const MirBlock yes = cb->term.a.block, no = cb->term.b.block;
  return yes != no && yes != c && no != c;
}

/* The target's region: what a parameter of `c` may be replaced in. A target with other predecessors has none, since the
 * other edges could not fill a parameter added to it. */
static bool in_region(const MirPreds *preds, const UtDom *dom, MirBlock target, MirBlock b) {
  return mir_preds_count(preds, target) == 1 && dominates(dom, target, b);
}

/* Whether every use of a parameter of `c` outside it is in the region of one target. */
static bool params_local(const Ut *t, const MirPreds *preds, const UtDom *dom, MirBlock c) {
  const MirBlockData *cb = &t->f->blocks.ptr[c];
  const MirBlock yes = cb->term.a.block, no = cb->term.b.block;
  for (uint32_t i = 0; i < cb->params.len; i++) {
    for (uint32_t b = 0; b < t->f->blocks.len; b++) {
      if (b != c && dom->idom[b] != MIR_NONE && !in_region(preds, dom, yes, b) && !in_region(preds, dom, no, b) &&
        uses_value(&t->f->blocks.ptr[b], cb->params.ptr[i].value)) {
        return false;
      }
    }
  }
  return true;
}

/* The parameters of one target of `c` that a threaded edge must also fill: each parameter of `c` its region reads. */
typedef struct UtSide {
  MirBlock target;
  uint32_t n;
  uint32_t *index; /* the parameter of `c` */
  MirValue *fresh; /* the new parameter of the target */
} UtSide;

static UtSide side_of(Ut *t, const MirPreds *preds, const UtDom *dom, MirBlock c, MirBlock target) {
  MirFunc *f = t->f;
  const MirBlockData *cb = &f->blocks.ptr[c];
  UtSide side = {.target = target};
  side.index = MS_ARENA_NEW_ARRAY(&t->m->arena, uint32_t, (size_t)cb->params.len + 1);
  side.fresh = MS_ARENA_NEW_ARRAY(&t->m->arena, MirValue, (size_t)cb->params.len + 1);
  for (uint32_t i = 0; i < cb->params.len; i++) {
    const MirValue q = cb->params.ptr[i].value;
    bool used = false;
    for (uint32_t b = 0; b < f->blocks.len && !used; b++) {
      used = b != c && dom->idom[b] != MIR_NONE && in_region(preds, dom, target, b) && uses_value(&f->blocks.ptr[b], q);
    }
    if (!used) {
      continue;
    }
    const MirValue v = mir_new_value(f, mir_value_ty(f, q));
    mir_block_param_list_push(&f->blocks.ptr[target].params, (MirBlockParam){.value = v, .mode = cb->params.ptr[i].mode});
    side.index[side.n] = i;
    side.fresh[side.n++] = v;
  }
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    if (b == c || dom->idom[b] == MIR_NONE || !in_region(preds, dom, target, b)) {
      continue;
    }
    for (uint32_t k = 0; k < side.n; k++) {
      replace_in(&f->blocks.ptr[b], (UtReplace){.from = cb->params.ptr[side.index[k]].value, .to = side.fresh[k]});
    }
  }
  return side;
}

/* The arguments `c` passes to a target, then the values for the parameters `side` added. `from` is what `c`'s own
 * parameters hold: its own (when NULL) or those an edge passes. */
static MirTarget target_args(Ut *t, const MirBlockData *cb, const MirTarget *base, const UtSide *side, const MirValue *from) {
  MirValue *args = MS_ARENA_NEW_ARRAY(&t->m->arena, MirValue, (size_t)base->nargs + side->n + 1);
  for (uint32_t a = 0; a < base->nargs; a++) {
    args[a] = base->args[a];
    for (uint32_t i = 0; from != NULL && i < cb->params.len; i++) {
      if (base->args[a] == cb->params.ptr[i].value) {
        args[a] = from[i];
      }
    }
  }
  for (uint32_t k = 0; k < side->n; k++) {
    args[base->nargs + k] = from != NULL ? from[side->index[k]] : cb->params.ptr[side->index[k]].value;
  }
  return (MirTarget){.block = side->target, .args = args, .nargs = base->nargs + side->n};
}

/* Retargets every edge into `c` whose byte state is known; returns whether one was. */
static bool thread_into(Ut *t, const MirPreds *preds, const UtDom *dom, MirBlock c) {
  MirFunc *f = t->f;
  bool any = false;
  /* The edges first: nothing changes unless one is known. */
  for (uint32_t pi = 0; pi < mir_preds_count(preds, c) && !any; pi++) {
    const MirBlock p = mir_pred(preds, c, pi);
    const MirTerm *pt = &f->blocks.ptr[p].term;
    for (uint32_t s = 0; p != c && s < mir_term_ntargets(pt); s++) {
      any = any || (mir_term_target_const(pt, s)->block == c && edge_state(t, preds, p, s) != UT_UNKNOWN);
    }
  }
  if (!any || !params_local(t, preds, dom, c)) {
    return false;
  }
  const MirBlockData cb = f->blocks.ptr[c];
  const MirTarget base_yes = cb.term.a, base_no = cb.term.b;
  const UtSide yes = side_of(t, preds, dom, c, base_yes.block), no = side_of(t, preds, dom, c, base_no.block);
  /* The edges are read from the predecessors as they were: the states are decided before any edge moves. */
  for (uint32_t pi = 0; pi < mir_preds_count(preds, c); pi++) {
    const MirBlock p = mir_pred(preds, c, pi);
    if (p == c) {
      continue;
    }
    for (uint32_t s = 0; s < mir_term_ntargets(&f->blocks.ptr[p].term); s++) {
      MirTarget *e = mir_term_target(&f->blocks.ptr[p].term, s);
      if (e->block != c) {
        continue;
      }
      const UtState st = edge_state(t, preds, p, s);
      if (st == UT_UNKNOWN) {
        continue;
      }
      const bool to_yes = st == UT_SET;
      *e = target_args(t, &cb, to_yes ? &base_yes : &base_no, to_yes ? &yes : &no, e->args);
    }
  }
  /* `c` keeps feeding its own targets. */
  f->blocks.ptr[c].term.a = target_args(t, &cb, &base_yes, &yes, NULL);
  f->blocks.ptr[c].term.b = target_args(t, &cb, &base_no, &no, NULL);
  return true;
}

static bool thread_func(Ut *t) {
  bool changed = false;
  for (uint32_t round = 0; round < UT_ROUNDS; round++) {
    MsArena arena = ms_arena_new();
    MirBlock *order = NULL;
    const uint32_t reachable = mir_rpo(&arena, t->f, &order);
    const MirPreds preds = mir_preds(&arena, t->f);
    const MirBlock *idom = mir_dominators(&arena, t->f, order, reachable, &preds);
    const UtDom dom = ut_dom(&arena, t->f, order, reachable, idom);
    bool did = false;
    for (uint32_t i = 0; i < reachable && !did; i++) {
      const MirBlock c = order[i];
      did = candidate(t, c) && thread_into(t, &preds, &dom, c);
    }
    ms_arena_free(&arena);
    if (!did) {
      break;
    }
    changed = true;
  }
  return changed;
}

static bool thread_one(MirModule *m, MirFunc *f) {
  Ut t = {.m = m, .f = f, .resume = MS_NAME_EMPTY};
  return ms_names_find(&m->names, ms_span_of_text("msrt_unwinding_resume"), &t.resume) && thread_func(&t);
}

bool opt_unwind_thread(MirModule *m) {
  return opt_each_func(m, thread_one);
}

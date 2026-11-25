/* Jump threading: a branch whose condition one predecessor already knows is taken by that predecessor.
 *
 *     P: r = alt.new ok x ; br J(r)               P: r = alt.new ok x ; t = alt.tag r ; c = icmp.eq t, 0
 *     J(m): t = alt.tag m ; c = icmp.eq t, 0  =>     br S'()            S': v = alt.get r ; drop r ; br K(v)
 *           br_if c, S(), T()
 *     S: v = alt.get m ; drop m ; br K(v)
 *
 * A value built on each arm and tested after the join (`r = if c: make(a) else: make(b)` then `if v := r`)
 * would otherwise be a heap block, a tag read and a drop per pass. The predecessor evaluates the join's
 * operations on what it passes (a constant, an `alt.new` case, `opt.some`/`opt.none`); when that decides
 * the branch, it gets its own copy of the join's operations and of the chosen successor, where folding
 * finds the constructor behind each read and drop. The copy runs the same operations on the same values,
 * so every ownership edge stays what it was. The join must be pure and own nothing, the chosen successor
 * small and reached only from the join, and what the join and the successor define must stay inside
 * them. Loop headers are left alone. */

#include "compiler/mir/mir_analysis.h"
#include "compiler/opt/opt_pass.h"
#include "base/safe.h"

enum { TH_MAX_JOIN = 8, TH_MAX_SUCC = 16, TH_MAX_MAP = 48, TH_BUDGET = 192, TH_ROUNDS = 4 };

typedef enum ThKind { TK_NONE, TK_INT, TK_ALT, TK_OPT } ThKind;

typedef struct ThKnown {
  uint8_t kind;
  int64_t val;
} ThKnown;

typedef struct ThMap {
  MirValue from[TH_MAX_MAP], to[TH_MAX_MAP];
  uint32_t n;
} ThMap;

typedef struct Th {
  MirModule *m;
  MirFunc *f;
  const MirBlock *owner; /* per value: the defining block */
  const uint32_t *pos;   /* per value: parameter index, or parameters + instruction index */
  uint32_t nvalues;
  const uint32_t *uses;
  uint32_t *inside;      /* scratch per value */
  const uint32_t *npreds;
  const MirBlock *idom;
} Th;

static const MirInst *def_inst(const Th *t, MirValue v) {
  if (v >= t->nvalues || t->owner[v] == MIR_NONE) {
    return NULL;
  }
  const MirBlockData *b = &t->f->blocks.ptr[t->owner[v]];
  const uint32_t np = (uint32_t)b->params.len;
  return t->pos[v] < np ? NULL : &b->insts.ptr[t->pos[v] - np];
}

static ThKnown known_of_def(const Th *t, MirValue v) {
  const MirInst *d = def_inst(t, v);
  if (!d) {
    return (ThKnown){TK_NONE, 0};
  }
  switch (d->op) {
  case MOP_IConst: return (ThKnown){TK_INT, d->imm.i};
  case MOP_BConst: return (ThKnown){TK_INT, d->imm.a ? 1 : 0};
  case MOP_AltNew: return (ThKnown){TK_ALT, d->imm.b};
  case MOP_OptSome: return (ThKnown){TK_OPT, 1};
  case MOP_OptNone:
  case MOP_OptNoneOwned: return (ThKnown){TK_OPT, 0};
  default: return (ThKnown){TK_NONE, 0};
  }
}

static bool cmp_holds(uint32_t cc, int64_t a, int64_t b) {
  switch (cc) {
  case MCC_EQ: return a == b;
  case MCC_NE: return a != b;
  case MCC_LT: return a < b;
  case MCC_LE: return a <= b;
  case MCC_GT: return a > b;
  default: return a >= b;
  }
}

/* What the join's branch does when `j` is entered from `p` with `args`: 1 for the first target, 0 for the
 * second, -1 when unknown. */
static int decide(const Th *t, MirBlock j, const MirValue *args) {
  const MirBlockData *jb = &t->f->blocks.ptr[j];
  MirValue ids[TH_MAX_JOIN + 1];
  ThKnown vals[TH_MAX_JOIN + 1];
  uint32_t n = 0;
  for (uint32_t i = 0; i < jb->insts.len; i++) {
    const MirInst *in = &jb->insts.ptr[i];
    ThKnown a[2] = {{TK_NONE, 0}, {TK_NONE, 0}};
    for (uint32_t k = 0; k < in->nargs && k < 2; k++) {
      const MirValue v = in->args[k];
      a[k] = known_of_def(t, v);
      for (uint32_t q = 0; q < jb->params.len; q++) {
        if (jb->params.ptr[q].value == v) {
          a[k] = known_of_def(t, args[q]);
        }
      }
      for (uint32_t q = 0; q < n; q++) {
        if (ids[q] == v) {
          a[k] = vals[q];
        }
      }
    }
    ThKnown r = {TK_NONE, 0};
    switch (in->op) {
    case MOP_IConst: r = (ThKnown){TK_INT, in->imm.i}; break;
    case MOP_BConst: r = (ThKnown){TK_INT, in->imm.a ? 1 : 0}; break;
    case MOP_AltTag:
      if (a[0].kind == TK_ALT) {
        r = (ThKnown){TK_INT, a[0].val};
      }
      break;
    case MOP_OptIsSome:
      if (a[0].kind == TK_OPT) {
        r = (ThKnown){TK_INT, a[0].val};
      }
      break;
    case MOP_Not:
      if (a[0].kind == TK_INT) {
        r = (ThKnown){TK_INT, a[0].val ? 0 : 1};
      }
      break;
    case MOP_ICmp:
      if (a[0].kind == TK_INT && a[1].kind == TK_INT) {
        r = (ThKnown){TK_INT, cmp_holds(in->imm.a, a[0].val, a[1].val) ? 1 : 0};
      }
      break;
    default: break;
    }
    if (in->res != MIR_NONE && r.kind != TK_NONE && n <= TH_MAX_JOIN) {
      ids[n] = in->res;
      vals[n++] = r;
    }
  }
  const MirValue c = jb->term.value;
  for (uint32_t q = 0; q < n; q++) {
    if (ids[q] == c && vals[q].kind == TK_INT) {
      return vals[q].val != 0;
    }
  }
  return -1;
}

static MirValue map_get(const ThMap *map, MirValue v) {
  for (uint32_t i = 0; i < map->n; i++) {
    if (map->from[i] == v) {
      return map->to[i];
    }
  }
  return v;
}

static bool map_put(ThMap *map, MirValue from, MirValue to) {
  if (map->n == TH_MAX_MAP) {
    return false;
  }
  map->from[map->n] = from;
  map->to[map->n++] = to;
  return true;
}

static void subst(void *context, MirValue *v) {
  *v = map_get(context, *v);
}

static bool op_cloneable(const Th *t, const MirInst *in) {
  switch (in->op) {
  case MOP_Slot: case MOP_ScopeBegin: case MOP_ScopeOwn:
  case MOP_ScopeEnd: case MOP_ScopeDisown: case MOP_ScopeUnpin: case MOP_ScopeMark: case MOP_DepthEnter:
  case MOP_DepthLeave: case MOP_StackLow: case MOP_StackNear:
    return false;
  default:
    (void)t;
    return true;
  }
}

static void count_uses(void *context, MirValue v) {
  Th *t = context;
  if (v < t->nvalues) {
    t->inside[v]++;
  }
}

static void count_block(Th *t, MirBlock b) {
  const MirBlockData *blk = &t->f->blocks.ptr[b];
  for (uint32_t i = 0; i < blk->insts.len; i++) {
    for (uint32_t k = 0; k < blk->insts.ptr[i].nargs; k++) {
      count_uses(t, blk->insts.ptr[i].args[k]);
    }
  }
  mir_term_each_value(&blk->term, count_uses, t);
}

/* Whether every definition of `b` is used only inside the blocks counted into `inside`. Resets them. */
static bool defs_local(Th *t, MirBlock b) {
  const MirBlockData *blk = &t->f->blocks.ptr[b];
  bool ok = true;
  for (uint32_t i = 0; i < blk->params.len; i++) {
    const MirValue v = blk->params.ptr[i].value;
    ok = ok && t->inside[v] == t->uses[v];
  }
  for (uint32_t i = 0; i < blk->insts.len; i++) {
    const MirValue v = blk->insts.ptr[i].res;
    ok = ok && (v == MIR_NONE || t->inside[v] == t->uses[v]);
  }
  return ok;
}

static void reset_counts(Th *t, MirBlock b) {
  const MirBlockData *blk = &t->f->blocks.ptr[b];
  for (uint32_t i = 0; i < blk->insts.len; i++) {
    for (uint32_t k = 0; k < blk->insts.ptr[i].nargs; k++) {
      const MirValue v = blk->insts.ptr[i].args[k];
      if (v < t->nvalues) {
        t->inside[v] = 0;
      }
    }
  }
  const MirTerm *term = &blk->term;
  for (uint32_t k = 0; k < mir_term_ntargets(term); k++) {
    const MirTarget *tg = mir_term_target_const(term, k);
    for (uint32_t i = 0; i < tg->nargs; i++) {
      if (tg->args[i] < t->nvalues) {
        t->inside[tg->args[i]] = 0;
      }
    }
  }
  if (term->value != MIR_NONE && term->value < t->nvalues) {
    t->inside[term->value] = 0;
  }
}

/* Whether the join and the chosen successor may be copied for a predecessor. */
static bool copyable(Th *t, MirBlock j, MirBlock s, MirBlock other, const MirTarget *edge) {
  const MirBlockData *jb = &t->f->blocks.ptr[j], *sb = &t->f->blocks.ptr[s];
  if (edge->nargs != sb->params.len) {
    return false;
  }
  if (jb->insts.len > TH_MAX_JOIN || sb->insts.len > TH_MAX_SUCC || t->npreds[s] != 1 ||
    s == j || s == other || sb->term.kind == MT_SWITCH) {
    return false;
  }
  /* An owned parameter stays live along the copied path under the predecessor's value, and the original
   * path keeps the parameter: a block both reach, such as one that leaks into a panic, then sees two
   * different owned values. */
  for (uint32_t i = 0; i < jb->params.len; i++) {
    if (jb->params.ptr[i].mode == MM_MOVE) {
      return false;
    }
  }
  for (uint32_t i = 0; i < sb->params.len; i++) {
    if (sb->params.ptr[i].mode == MM_MOVE) {
      return false;
    }
  }
  for (uint32_t i = 0; i < jb->insts.len; i++) {
    const MirInst *in = &jb->insts.ptr[i];
    MirMode mode;
    if ((mir_op_info[in->op].effects & (MIR_E_WRITES | MIR_E_OWNERSHIP | MIR_E_ALLOC | MIR_E_IO)) != 0 ||
      (in->res != MIR_NONE && mir_result_mode(t->m, t->f, in, &mode) && mode == MM_MOVE)) {
      return false;
    }
  }
  for (uint32_t i = 0; i < sb->insts.len; i++) {
    if (!op_cloneable(t, &sb->insts.ptr[i])) {
      return false;
    }
  }
  /* What the join defines stays inside the join, the chosen successor and the other one; what the
   * successor defines stays inside it. */
  count_block(t, j);
  count_block(t, s);
  if (other != j && t->npreds[other] == 1) {
    count_block(t, other);
  }
  const bool join_ok = defs_local(t, j);
  reset_counts(t, j);
  reset_counts(t, s);
  reset_counts(t, other);
  if (!join_ok) {
    return false;
  }
  count_block(t, s);
  const bool succ_ok = defs_local(t, s);
  reset_counts(t, s);
  return succ_ok;
}

/* Copies the join's operations and the chosen successor into a new block `p` branches to. */
static void thread_edge(Th *t, MirBlock p, MirBlock j, MirBlock s, const MirTarget *edge) {
  MirModule *m = t->m;
  MirFunc *f = t->f;
  const MirBlockData jb = f->blocks.ptr[j];
  const MirBlockData sb = f->blocks.ptr[s];
  ThMap map = {.n = 0};
  for (uint32_t i = 0; i < jb.params.len; i++) {
    map_put(&map, jb.params.ptr[i].value, f->blocks.ptr[p].term.a.args[i]);
  }
  for (uint32_t i = 0; i < sb.params.len; i++) {
    map_put(&map, sb.params.ptr[i].value, map_get(&map, edge->args[i]));
  }
  MirBlockData nb = {0};
  nb.cold = sb.cold;
  nb.term_loc = sb.term_loc;
  MirInst *copy = MS_ARENA_NEW_ARRAY(&m->arena, MirInst, (size_t)(jb.insts.len + sb.insts.len) + 1);
  uint32_t n = 0;
  for (uint32_t pass = 0; pass < 2; pass++) {
    const MirBlockData *src = pass ? &sb : &jb;
    for (uint32_t i = 0; i < src->insts.len; i++) {
      MirInst in = src->insts.ptr[i];
      in.args = mir_args_copy(m, in.args, in.nargs);
      for (uint32_t k = 0; k < in.nargs; k++) {
        in.args[k] = map_get(&map, in.args[k]);
      }
      if (in.res != MIR_NONE) {
        const MirValue res = mir_new_value(f, mir_value_ty(f, in.res));
        map_put(&map, in.res, res);
        in.res = res;
      }
      copy[n++] = in;
    }
  }
  nb.term = sb.term;
  nb.term.a = opt_target_clone(m, &sb.term.a);
  nb.term.b = opt_target_clone(m, &sb.term.b);
  mir_term_each_use(&nb.term, subst, &map);
  mir_block_list_push(&f->blocks, nb);
  const MirBlock id = (MirBlock)(f->blocks.len - 1);
  opt_block_set_insts(&f->blocks.ptr[id], copy, n);
  MirTerm *pt = &f->blocks.ptr[p].term;
  opt_term_set_br(pt, (MirTarget){id, NULL, 0});
}

static bool sweep(MirModule *m, MirFunc *f, uint32_t *budget) {
  MsArena arena = ms_arena_new();
  const uint32_t nblocks = (uint32_t)f->blocks.len;
  MirBlock *order = NULL;
  const uint32_t reachable = mir_rpo(&arena, f, &order);
  const MirPreds preds = mir_preds(&arena, f);
  MirBlock *idom = mir_dominators(&arena, f, order, reachable, &preds);
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
  __builtin_memset(npreds, 0, sizeof(uint32_t) * ((size_t)nblocks + 1));
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
  Th t = {.m = m, .f = f, .owner = owner, .pos = pos, .nvalues = nvalues, .uses = uses, .inside = inside,
      .npreds = npreds, .idom = idom};
  bool changed = false;
  bool *touched = MS_ARENA_NEW_ARRAY(&arena, bool, (size_t)nblocks + 1);
  __builtin_memset(touched, 0, sizeof(bool) * ((size_t)nblocks + 1));
  /* A loop header is the target of an edge from a block it dominates. One pass finds them all: the dominators and the
   * blocks the sweep looks at are those of the function as it was before the first rewrite, which only adds blocks. */
  bool *header = MS_ARENA_NEW_ARRAY(&arena, bool, (size_t)nblocks + 1);
  for (uint32_t q = 0; q < reachable; q++) {
    const MirTerm *qt = &f->blocks.ptr[order[q]].term;
    for (uint32_t k = 0; k < mir_term_ntargets(qt); k++) {
      const MirBlock target = mir_term_target_const(qt, k)->block;
      header[target] = header[target] || mir_dominates(idom, target, order[q]);
    }
  }
  for (uint32_t i = 0; i < reachable; i++) {
    const MirBlock p = order[i];
    const MirTerm *pterm = &f->blocks.ptr[p].term;
    if (pterm->kind != MT_BR || touched[p]) {
      continue;
    }
    const MirBlock j = pterm->a.block;
    if (j == p || j >= nblocks || touched[j] || f->blocks.ptr[j].term.kind != MT_CONDBR ||
      f->blocks.ptr[j].term.a.block == f->blocks.ptr[j].term.b.block || f->blocks.ptr[j].params.len == 0 ||
      f->blocks.ptr[j].insts.len > TH_MAX_JOIN || pterm->a.nargs != f->blocks.ptr[j].params.len) {
      continue;
    }
    if (header[j]) {
      continue;
    }
    const int pick = decide(&t, j, pterm->a.args);
    if (pick < 0) {
      continue;
    }
    const MirTerm *jt = &f->blocks.ptr[j].term;
    const MirBlock s = pick ? jt->a.block : jt->b.block, other = pick ? jt->b.block : jt->a.block;
    const uint32_t cost = (uint32_t)(f->blocks.ptr[j].insts.len + f->blocks.ptr[s].insts.len);
    const MirTarget *edge = pick ? &jt->a : &jt->b;
    if (cost > *budget || !copyable(&t, j, s, other, edge)) {
      continue;
    }
    *budget -= cost;
    thread_edge(&t, p, j, s, edge);
    touched[p] = touched[j] = touched[s] = true;
    changed = true;
  }
  ms_arena_free(&arena);
  return changed;
}

bool opt_thread_func(MirModule *m, MirFunc *f) {
  bool changed = false;
  uint32_t budget = TH_BUDGET;
  for (uint32_t round = 0; round < TH_ROUNDS && sweep(m, f, &budget); round++) {
    changed = true;
  }
  return changed;
}

bool opt_thread(MirModule *m) {
  bool changed = false;
  for (uint32_t fi = 0; fi < m->funcs.len; fi++) {
    changed = opt_thread_func(m, &m->funcs.ptr[fi]) || changed;
  }
  return changed;
}

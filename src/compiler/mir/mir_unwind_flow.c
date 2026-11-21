/* unwind: cleanup stacks as shared-prefix trees, and the plan for which registrations cross
 * block edges. Port of `Stacks`, `Flow` and `plan_flow` in unwind.rs. */
#include "compiler/mir/mir_unwind.h"

void uws_init(UwStacks *s, MsArena *a) {
  s->a = a;
  s->cap = 16;
  s->nodes = MS_ARENA_NEW_ARRAY(a, UwNode, s->cap);
  __builtin_memset(s->nodes, 0, sizeof(UwNode) * s->cap);
  s->n = 1; /* the root: the empty stack */
  s->tcap = 64;
  s->table = MS_ARENA_NEW_ARRAY(a, uint32_t, s->tcap);
  __builtin_memset(s->table, 0, sizeof(uint32_t) * s->tcap);
}

uint32_t uws_depth(const UwStacks *s, uint32_t stack) { return s->nodes[stack].depth; }

/* The prefix of `stack` with `depth` entries. */
static uint32_t uws_ancestor(const UwStacks *s, uint32_t stack, uint32_t depth) {
  while (uws_depth(s, stack) > depth) {
    stack = s->nodes[stack].parent;
  }
  return stack;
}

/* The tag of the entry that ends the prefix of `depth` entries (the first is at depth 1). */
uint64_t uws_tag_at(const UwStacks *s, uint32_t stack, uint32_t depth) {
  return s->nodes[uws_ancestor(s, stack, depth)].tag;
}

/* The longest prefix both stacks start with. */
static uint32_t uws_common(const UwStacks *s, uint32_t a, uint32_t b) {
  a = uws_ancestor(s, a, uws_depth(s, b));
  b = uws_ancestor(s, b, uws_depth(s, a));
  while (a != b) {
    a = s->nodes[a].parent;
    b = s->nodes[b].parent;
  }
  return a;
}

/* How to bring `stack` to the owners in `target`: the first entry whose owner died is discarded
 * with every newer one, and the owners above it that live, and the ones not yet held, are
 * registered again. */
UwPlan uws_plan(UwStacks *s, uint32_t stack, const OwnerSet *target) {
  const UwNode *node = &s->nodes[stack];
  uint32_t *gone = NULL, *added = NULL, ngone = 0, nadded = 0;
  owner_diff(s->a, &node->owners, target, &gone, &ngone, &added, &nadded);
  UwPlan plan = {.keep = stack};
  for (uint32_t i = 0; i < ngone; i++) {
    uint64_t d = 0;
    if (posmap_get(&node->depths, gone[i], &d) && (!plan.has_cut || d - 1 < plan.cut)) {
      plan.has_cut = true;
      plan.cut = (uint32_t)d - 1;
    }
  }
  if (plan.has_cut) {
    uint32_t *grown = MS_ARENA_NEW_ARRAY(s->a, uint32_t, (size_t)nadded + uws_depth(s, stack) + 1);
    __builtin_memcpy(grown, added, sizeof(uint32_t) * nadded);
    added = grown;
    while (uws_depth(s, plan.keep) > plan.cut) {
      const UwNode *top = &s->nodes[plan.keep];
      if (owner_contains(target, top->owner)) {
        added[nadded++] = top->owner;
      }
      plan.keep = top->parent;
    }
    uw_sort_u32(added, nadded);
  }
  plan.added = added;
  plan.nadded = nadded;
  return plan;
}

static uint32_t uws_hash(uint32_t parent, uint32_t owner, uint64_t tag, uint32_t mask) {
  uint64_t h = (uint64_t)parent * UINT64_C(0x9e3779b97f4a7c15) ^ (uint64_t)owner << 20 ^ tag;
  h ^= h >> 31;
  h *= UINT64_C(0xff51afd7ed558ccd);
  h ^= h >> 33;
  return (uint32_t)h & mask;
}

/* The node of (parent, owner, tag), or MIR_NONE; `*slot` is where it is or would go. */
static uint32_t uws_find(const UwStacks *s, uint32_t parent, uint32_t owner, uint64_t tag,
            uint32_t *slot) {
  uint32_t i = uws_hash(parent, owner, tag, s->tcap - 1);
  while (s->table[i] != 0) {
    const UwNode *n = &s->nodes[s->table[i] - 1];
    if (n->parent == parent && n->owner == owner && n->tag == tag) {
      *slot = i;
      return s->table[i] - 1;
    }
    i = (i + 1) & (s->tcap - 1);
  }
  *slot = i;
  return MIR_NONE;
}

static void uws_grow_table(UwStacks *s) {
  s->tcap *= 2;
  s->table = MS_ARENA_NEW_ARRAY(s->a, uint32_t, s->tcap);
  __builtin_memset(s->table, 0, sizeof(uint32_t) * s->tcap);
  for (uint32_t id = 1; id < s->n; id++) {
    uint32_t slot = 0;
    (void)uws_find(s, s->nodes[id].parent, s->nodes[id].owner, s->nodes[id].tag, &slot);
    s->table[slot] = id + 1;
  }
}

static uint32_t uws_add(UwStacks *s, uint32_t parent, uint32_t owner, uint64_t tag,
            const OwnerSet *owners) {
  if (s->n == s->cap) {
    UwNode *grown = MS_ARENA_NEW_ARRAY(s->a, UwNode, (size_t)s->cap * 2);
    __builtin_memcpy(grown, s->nodes, sizeof(UwNode) * s->n);
    s->nodes = grown;
    s->cap *= 2;
  }
  if ((s->n + 1) * 2 > s->tcap) {
    uws_grow_table(s);
  }
  const UwNode *p = &s->nodes[parent];
  UwNode node = {.parent = parent, .depth = p->depth + 1, .owner = owner, .tag = tag,
         .owners = *owners, .depths = p->depths};
  posmap_insert(s->a, &node.depths, owner, node.depth);
  const uint32_t id = s->n++;
  s->nodes[id] = node;
  uint32_t slot = 0;
  (void)uws_find(s, parent, owner, tag, &slot);
  s->table[slot] = id + 1;
  return id;
}

/* Pushes the entries on `stack`. They bring it to the owners in `target`, which the last node
 * then shares, so the next comparison with a set derived from `target` skips what they have in
 * common. */
uint32_t uws_extend(UwStacks *s, uint32_t stack, const uint32_t *owners, const uint64_t *tags,
          uint32_t n, const OwnerSet *target) {
  for (uint32_t i = 0; i < n; i++) {
    uint32_t slot = 0;
    const uint32_t found = uws_find(s, stack, owners[i], tags[i], &slot);
    if (found != MIR_NONE) {
      stack = found;
      continue;
    }
    OwnerSet set = *target;
    if (i + 1 != n) {
      set = s->nodes[stack].owners;
      owner_insert(s->a, &set, owners[i]);
    }
    stack = uws_add(s, stack, owners[i], tags[i], &set);
  }
  return stack;
}

/* ---- plan_flow ---- */

typedef struct UwGraph {
  uint32_t n;
  uint32_t **succs, *nsuccs;
  uint32_t **preds, *npreds;
  uint32_t *pos; /* reverse post-order position, UW_INF when unreachable */
} UwGraph;

static UwGraph uw_graph(MsArena *a, const MirFunc *f, const MirBlock *rpo, uint32_t nrpo) {
  const uint32_t n = (uint32_t)f->blocks.len;
  UwGraph g = {.n = n, .succs = MS_ARENA_NEW_ARRAY(a, uint32_t *, n), .nsuccs = MS_ARENA_NEW_ARRAY(a, uint32_t, n),
        .preds = MS_ARENA_NEW_ARRAY(a, uint32_t *, n), .npreds = MS_ARENA_NEW_ARRAY(a, uint32_t, n),
        .pos = MS_ARENA_NEW_ARRAY(a, uint32_t, n)};
  __builtin_memset(g.nsuccs, 0, sizeof(uint32_t) * n);
  __builtin_memset(g.npreds, 0, sizeof(uint32_t) * n);
  for (uint32_t i = 0; i < n; i++) {
    g.pos[i] = UW_INF;
    g.succs[i] = MS_ARENA_NEW_ARRAY(a, uint32_t, mir_term_ntargets(&f->blocks.ptr[i].term) + 1);
  }
  for (uint32_t i = 0; i < nrpo; i++) {
    const uint32_t b = rpo[i];
    g.pos[b] = i;
    for (uint32_t k = 0; k < mir_term_ntargets(&f->blocks.ptr[b].term); k++) {
      const uint32_t t = mir_term_target_const(&f->blocks.ptr[b].term, k)->block;
      if (!uw_u32_contains(g.succs[b], g.nsuccs[b], t)) {
        g.succs[b][g.nsuccs[b]++] = t;
        g.npreds[t]++;
      }
    }
  }
  for (uint32_t b = 0; b < n; b++) {
    g.preds[b] = MS_ARENA_NEW_ARRAY(a, uint32_t, g.npreds[b] + 1);
    g.npreds[b] = 0;
  }
  for (uint32_t i = 0; i < nrpo; i++) {
    const uint32_t b = rpo[i];
    for (uint32_t k = 0; k < g.nsuccs[b]; k++) {
      g.preds[g.succs[b][k]][g.npreds[g.succs[b][k]]++] = b;
    }
  }
  return g;
}

typedef struct UwFlowPass {
  const MirFunc *f;
  const UwWalk *walk;
  const UwGraph *g;
  UwStacks *stacks;
  const bool *can;
  const MirBlock *rpo;
  uint32_t nrpo;
  uint32_t *trim, *entry, *full, *left;
} UwFlowPass;

/* One pass over the blocks: the stack each starts with and ends with, given the current trims. */
static void uw_flow_walk(UwFlowPass *p) {
  const uint32_t n = p->g->n;
  for (uint32_t i = 0; i < n; i++) {
    p->entry[i] = p->full[i] = p->left[i] = UW_ROOT;
  }
  for (uint32_t oi = 0; oi < p->nrpo; oi++) {
    const uint32_t bi = p->rpo[oi];
    if (!p->walk->plain[bi]) {
      continue;
    }
    uint32_t stack = UW_ROOT;
    if (p->can[bi]) {
      stack = p->left[p->g->preds[bi][0]];
      for (uint32_t k = 1; k < p->g->npreds[bi]; k++) {
        stack = uws_common(p->stacks, stack, p->left[p->g->preds[bi][k]]);
      }
    }
    p->entry[bi] = stack;
    uint32_t seq = 0;
    for (uint32_t e = 0; e < p->walk->nevents[bi]; e++) {
      const OwnerSet *target = &p->walk->events[bi][e].owners;
      const UwPlan plan = uws_plan(p->stacks, stack, target);
      uint64_t *tags = MS_ARENA_NEW_ARRAY(p->stacks->a, uint64_t, plan.nadded + 1);
      for (uint32_t i = 0; i < plan.nadded; i++) {
        tags[i] = (uint64_t)bi << 32 | seq++;
      }
      stack = uws_extend(p->stacks, plan.keep, plan.added, tags, plan.nadded, target);
    }
    p->left[bi] = uws_ancestor(p->stacks, stack, p->trim[bi]);
    p->full[bi] = stack;
  }
}

/* Lowers the trims to what every successor takes over; whether any changed. */
static bool uw_flow_trim(UwFlowPass *p) {
  bool changed = false;
  for (uint32_t bi = 0; bi < p->g->n; bi++) {
    if (!p->walk->plain[bi]) {
      continue;
    }
    uint32_t want = 0;
    const MirTermKind kind = (MirTermKind)p->f->blocks.ptr[bi].term.kind;
    if (kind == MT_FAULT) {
      want = UW_INF;
    } else if (kind != MT_RET && kind != MT_UNREACHABLE) {
      want = UW_INF;
      for (uint32_t k = 0; k < p->g->nsuccs[bi]; k++) {
        const uint32_t s = p->g->succs[bi][k];
        const uint32_t d = uws_depth(p->stacks, uws_common(p->stacks, p->full[bi], p->entry[s]));
        want = d < want ? d : want;
      }
      if (p->g->nsuccs[bi] == 0) {
        want = 0;
      }
    }
    if (want < p->trim[bi]) {
      p->trim[bi] = want;
      changed = true;
    }
  }
  return changed;
}

/* Decides which registrations cross block edges, so a branchy function registers an owner once
 * instead of once per block (see the Rust comment on `plan_flow` for the rules). Returns false
 * when the plan never settles, which cannot happen. */
bool uw_plan_flow(UwCx *cx, const MirFunc *f, const UwWalk *walk, UwStacks *stacks, UwFlow *out) {
  MsArena *a = &cx->fn;
  const uint32_t n = (uint32_t)f->blocks.len;
  MirBlock *rpo = NULL;
  const uint32_t nrpo = mir_rpo(a, f, &rpo);
  const UwGraph g = uw_graph(a, f, rpo, nrpo);
  bool *can = MS_ARENA_NEW_ARRAY(a, bool, n);
  for (uint32_t b = 0; b < n; b++) {
    can[b] = b != 0 && walk->plain[b] && g.npreds[b] > 0;
    for (uint32_t k = 0; k < g.npreds[b] && can[b]; k++) {
      can[b] = walk->plain[g.preds[b][k]] && g.pos[g.preds[b][k]] < g.pos[b];
    }
  }
  UwFlowPass p = {.f = f, .walk = walk, .g = &g, .stacks = stacks, .can = can, .rpo = rpo,
          .nrpo = nrpo, .trim = MS_ARENA_NEW_ARRAY(a, uint32_t, n), .entry = MS_ARENA_NEW_ARRAY(a, uint32_t, n),
          .full = MS_ARENA_NEW_ARRAY(a, uint32_t, n), .left = MS_ARENA_NEW_ARRAY(a, uint32_t, n)};
  for (uint32_t b = 0; b < n; b++) {
    p.trim[b] = walk->plain[b] ? UW_INF : 0;
  }
  /* Each pass lowers some trim, so this ends; the bound only guards a mistake. */
  for (uint32_t pass = 0; pass < n * 4 + 8; pass++) {
    uw_flow_walk(&p);
    if (!uw_flow_trim(&p)) {
      out->entry = p.entry;
      out->trim = p.trim;
      return true;
    }
  }
  return false;
}

/* ---- emitting registrations ---- */

/* The instruction that discards the registration behind `handle` and every newer one. */
MirInst uw_discard_inst(UwCx *cx, MirFunc *f, MirValue handle, MirLoc loc) {
  const MirValue res = mir_new_value(f, MIR_VOID);
  return mir_inst(MOP_CallRt, mir_imm_ext(cx->discard), res, loc,
          mir_args_copy(cx->m, &handle, 1), 1);
}

static MirInst uw_push_inst(UwCx *cx, MirOp op, MirValue arg, uint32_t func, MirValue res,
              MirLoc loc) {
  return mir_inst(op, (MirImm){.tag = MI_FUNC, .a = func}, res, loc,
          mir_args_copy(cx->m, &arg, 1), 1);
}

/* Appends one cleanup registration per value; their handles go to `handles` in order. */
void uw_push_each(UwCx *cx, MirFunc *f, MirInstList *o, const MirValue *values, uint32_t n, MirLoc loc,
         MirValue *handles) {
  for (uint32_t i = 0; i < n; i++) {
    const MirValue v = values[i];
    MirValue held = v;
    MirTy ty = mir_value_ty(f, v);
    uint64_t part = 0, cell = 0;
    if (uh_get(&cx->partials, v, &part)) {
      const uint32_t c = uw_partial_closer(cx, ty, mir_ty_data(cx->m, ty)->id, (uint32_t)part);
      handles[i] = mir_new_value(f, MIR_INT);
      mir_inst_list_push(o, uw_push_inst(cx, MOP_CleanupPush, (MirValue)(part >> 32), c, handles[i], loc));
      continue;
    }
    if (uh_get(&cx->cells, v, &cell)) {
      /* A cell registers a view of what its slot holds now. */
      ty = (MirTy)cell;
      held = mir_new_value(f, ty);
      mir_inst_list_push(o, mir_inst(MOP_Load, (MirImm){.tag = MI_TY, .a = ty}, held, loc,
                    mir_args_copy(cx->m, &v, 1), 1));
    }
    uint32_t c = uw_closer(cx, ty);
    if (uh_has(&cx->raw_values, v)) {
      c = uw_raw_closer(cx, ty);
    } else if (uh_has(&cx->box_values, v)) {
      c = uw_box_closer(cx, ty);
    }
    handles[i] = mir_new_value(f, MIR_INT);
    mir_inst_list_push(o, uw_push_inst(cx, MOP_CleanupPush, held, c, handles[i], loc));
  }
}

/* ---- rewriting a block that carries registrations ---- */

typedef struct UwRw {
  UwCx *cx;
  MirFunc *f;
  UwStacks *stacks;
  UwHash *handles; /* (block << 32 | push) -> handle */
  uint32_t bi, seq;
  MirInstList out;
} UwRw;

/* Brings `*stack` to the owners in `target`. */
static void uw_flow_sync(UwRw *r, uint32_t *stack, const OwnerSet *target, MirLoc loc) {
  const UwPlan plan = uws_plan(r->stacks, *stack, target);
  if (plan.has_cut) {
    uint64_t first = 0;
    (void)uh_get(r->handles, uws_tag_at(r->stacks, *stack, plan.cut + 1), &first);
    mir_inst_list_push(&r->out, uw_discard_inst(r->cx, r->f, (MirValue)first, loc));
  }
  MirValue *handles = MS_ARENA_NEW_ARRAY(r->stacks->a, MirValue, plan.nadded + 1);
  uint64_t *tags = MS_ARENA_NEW_ARRAY(r->stacks->a, uint64_t, plan.nadded + 1);
  uw_push_each(r->cx, r->f, &r->out, plan.added, plan.nadded, loc, handles);
  for (uint32_t i = 0; i < plan.nadded; i++) {
    tags[i] = (uint64_t)r->bi << 32 | r->seq++;
    (void)uh_put(r->stacks->a, r->handles, tags[i], handles[i]);
  }
  *stack = uws_extend(r->stacks, plan.keep, plan.added, tags, plan.nadded, target);
}

/* Rewrites a block that carries registrations across its edges: it starts with the ones its
 * predecessors left open, brings each owner up to date before an instruction that can park or
 * fault, and discards what is held beyond what its successors take over. */
void uw_rewrite_flow_block(UwCx *cx, MirFunc *f, const UwWalk *walk, const UwFlow *flow,
             UwStacks *stacks, UwHash *handles, uint32_t bi) {
  UwRw r = {.cx = cx, .f = f, .stacks = stacks, .handles = handles, .bi = bi};
  uint32_t stack = flow->entry[bi];
  MirInstList old_list = f->blocks.ptr[bi].insts;
  f->blocks.ptr[bi].insts = (MirInstList){0};
  const MirInst *old = old_list.ptr;
  const uint32_t len = (uint32_t)old_list.len;
  const MirLoc end_loc = len ? old[len - 1].loc : (MirLoc){0};
  const UwEvent *ev = walk->events[bi];
  uint32_t next = 0;
  for (uint32_t k = 0; k < len; k++) {
    const MirLoc loc = old[k].loc;
    /* The recursion check stays first in its block. */
    if (old[k].op == MOP_DepthEnter) {
      mir_inst_list_push(&r.out, old[k]);
    }
    if (next < walk->nevents[bi] && ev[next].at == k) {
      uw_flow_sync(&r, &stack, &ev[next++].owners, loc);
    }
    if (old[k].op != MOP_DepthEnter) {
      mir_inst_list_push(&r.out, old[k]);
    }
  }
  if (next < walk->nevents[bi] && ev[next].at == len) {
    uw_flow_sync(&r, &stack, &ev[next++].owners, end_loc);
  }
  /* A fault never returns, and its cleanups run newest first: nothing to discard. */
  if (f->blocks.ptr[bi].term.kind != MT_FAULT && uws_depth(stacks, stack) > flow->trim[bi]) {
    uint64_t first = 0;
    (void)uh_get(handles, uws_tag_at(stacks, stack, flow->trim[bi] + 1), &first);
    mir_inst_list_push(&r.out, uw_discard_inst(cx, f, (MirValue)first, end_loc));
  }
  mir_block_set_insts(&f->blocks.ptr[bi], &r.out);
  mir_inst_list_free(&old_list);
}

/* ---- a window's open registrations ---- */

/* Brings the registrations to the owners in `target`: a discard pops the first entry whose owner
 * died and every newer one, and the owners above it that live, and the ones not yet held, are
 * registered. `*at` is the window's stack. */
void uw_open_sync(UwCx *cx, MirFunc *f, UwStacks *stacks, uint32_t *at, MirInstList *out,
         const OwnerSet *target, MirLoc loc) {
  const UwPlan plan = uws_plan(stacks, *at, target);
  if (plan.has_cut) {
    const MirValue first = (MirValue)uws_tag_at(stacks, *at, plan.cut + 1);
    mir_inst_list_push(out, uw_discard_inst(cx, f, first, loc));
  }
  MirValue *handles = MS_ARENA_NEW_ARRAY(stacks->a, MirValue, plan.nadded + 1);
  uint64_t *tags = MS_ARENA_NEW_ARRAY(stacks->a, uint64_t, plan.nadded + 1);
  uw_push_each(cx, f, out, plan.added, plan.nadded, loc, handles);
  for (uint32_t i = 0; i < plan.nadded; i++) {
    tags[i] = handles[i];
  }
  *at = uws_extend(stacks, plan.keep, plan.added, tags, plan.nadded, target);
}

/* The instruction that discards every registration of the window, when any is open: the first
 * entry's handle discards them all. The window is empty afterwards. */
bool uw_open_close(UwCx *cx, MirFunc *f, UwStacks *stacks, uint32_t *at, MirLoc loc, MirInst *out) {
  if (*at == UW_ROOT) {
    return false;
  }
  const MirValue first = (MirValue)uws_tag_at(stacks, *at, 1);
  *at = UW_ROOT;
  *out = uw_discard_inst(cx, f, first, loc);
  return true;
}

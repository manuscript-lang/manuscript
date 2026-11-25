/* The `inline` pass: bottom-up inlining of direct calls, removal of functions that became
 * unreferenced, and removal of `depth.enter`/`depth.leave` from functions that cannot take part in
 * recursion. A callee is inlined when it is a plain function outside every direct-call cycle (or
 * on one that another function checks) and either carries `inline(always)` or is small enough and,
 * if it has a loop, called from inside one. Callees are processed before callers, so a caller sees
 * the already inlined body of its callee.; the closure
 * halves are in opt_inline_closure.c. Positions keep their scope numbers: the C function has no
 * scope table to nest the callee's under. */

#include "compiler/opt/opt_inline.h"
#include "compiler/opt/opt_simplify.h"

/* Extra allowance when the callee has a single call site, and per constant argument. */
#define IL_SINGLE_CALLER_BONUS 400u
#define IL_CONST_ARG_BONUS 5u
/* Largest self-recursive function unrolled once into itself. */
#define IL_SELF_UNROLL_MAX_SIZE 40u

/* ---- graphs ---- */

uint32_t opt_inline_degree(const OptInlineGraph *g, uint32_t v) {
  const uint32_t direct = g->off[v + 1] - g->off[v];
  return direct + (g->indirect != NULL && g->indirect[v] ? g->nit : 0);
}

uint32_t opt_inline_edge(const OptInlineGraph *g, uint32_t v, uint32_t k) {
  const uint32_t direct = g->off[v + 1] - g->off[v];
  return k < direct ? g->to[g->off[v] + k] : g->itargets[k - direct];
}

static bool il_call_target(const MirInst *inst, uint32_t *callee) {
  if (inst->op != MOP_Call || inst->imm.tag != MI_FUNC) {
    return false;
  }
  *callee = inst->imm.a;
  return true;
}

OptInlineGraph opt_inline_direct_graph(MsArena *arena, const MirModule *m) {
  OptInlineGraph g = {.n = (uint32_t)m->funcs.len};
  g.off = MS_ARENA_NEW_ARRAY(arena, uint32_t, (size_t)g.n + 1);
  for (uint32_t pass = 0; pass < 2; pass++) {
    uint32_t total = 0;
    for (uint32_t fi = 0; fi < g.n; fi++) {
      const uint32_t row = total;
      const MirFunc *f = &m->funcs.ptr[fi];
      for (uint32_t b = 0; b < f->blocks.len; b++) {
        for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
          uint32_t callee = 0;
          if (il_call_target(&f->blocks.ptr[b].insts.ptr[i], &callee)) {
            if (pass == 1) {
              g.to[total] = callee;
            }
            total++;
          }
        }
      }
      g.off[fi] = row;
    }
    g.off[g.n] = total;
    if (pass == 0) {
      g.to = MS_ARENA_NEW_ARRAY(arena, uint32_t, total);
    }
  }
  return g;
}

typedef struct IlSccs {
  uint32_t *nodes; /* the components' nodes, each component's in pop order */
  uint32_t *start; /* ncomps + 1 offsets into `nodes` */
  uint32_t ncomps;
} IlSccs;

typedef struct IlTarjan {
  const OptInlineGraph *g;
  uint32_t *index, *low, *stack, *wv, *wk;
  bool *on;
  uint32_t next, nstack, nwork, nout;
  IlSccs out;
} IlTarjan;

static void il_tarjan_visit(IlTarjan *t, uint32_t w) {
  t->index[w] = t->low[w] = t->next++;
  t->stack[t->nstack++] = w;
  t->on[w] = true;
  t->wv[t->nwork] = w;
  t->wk[t->nwork++] = 0;
}

static void il_tarjan_close(IlTarjan *t, uint32_t v) {
  t->out.start[t->out.ncomps] = t->nout;
  for (;;) {
    const uint32_t w = t->stack[--t->nstack];
    t->on[w] = false;
    t->out.nodes[t->nout++] = w;
    if (w == v) {
      break;
    }
  }
  t->out.ncomps++;
}

static void il_tarjan_from(IlTarjan *t, uint32_t root) {
  il_tarjan_visit(t, root);
  while (t->nwork > 0) {
    const uint32_t v = t->wv[t->nwork - 1], k = t->wk[t->nwork - 1];
    if (k < opt_inline_degree(t->g, v)) {
      t->wk[t->nwork - 1]++;
      const uint32_t w = opt_inline_edge(t->g, v, k);
      if (t->index[w] == MIR_NONE) {
        il_tarjan_visit(t, w);
      } else if (t->on[w] && t->index[w] < t->low[v]) {
        t->low[v] = t->index[w];
      }
      continue;
    }
    t->nwork--;
    if (t->nwork > 0) {
      const uint32_t p = t->wv[t->nwork - 1];
      t->low[p] = t->low[v] < t->low[p] ? t->low[v] : t->low[p];
    }
    if (t->low[v] == t->index[v]) {
      il_tarjan_close(t, v);
    }
  }
}

/* Strongly connected components, callees (successors) first. */
static IlSccs il_sccs(MsArena *arena, const OptInlineGraph *g) {
  const uint32_t n = g->n;
  IlTarjan t = {.g = g};
  t.index = MS_ARENA_NEW_ARRAY(arena, uint32_t, n);
  __builtin_memset(t.index, 0xff, sizeof(uint32_t) * n);
  t.low = MS_ARENA_NEW_ARRAY_UNINIT(arena, uint32_t, n);
  t.stack = MS_ARENA_NEW_ARRAY_UNINIT(arena, uint32_t, n);
  t.wv = MS_ARENA_NEW_ARRAY_UNINIT(arena, uint32_t, n);
  t.wk = MS_ARENA_NEW_ARRAY_UNINIT(arena, uint32_t, n);
  t.on = MS_ARENA_NEW_ARRAY_UNINIT(arena, bool, n);
  t.out.nodes = MS_ARENA_NEW_ARRAY_UNINIT(arena, uint32_t, n);
  t.out.start = MS_ARENA_NEW_ARRAY_UNINIT(arena, uint32_t, (size_t)n + 1);
  for (uint32_t root = 0; root < n; root++) {
    if (t.index[root] == MIR_NONE) {
      il_tarjan_from(&t, root);
    }
  }
  t.out.start[t.out.ncomps] = t.nout;
  return t.out;
}

bool *opt_inline_cyclic(MsArena *arena, const OptInlineGraph *g) {
  bool *out = MS_ARENA_NEW_ARRAY(arena, bool, g->n);
  const IlSccs s = il_sccs(arena, g);
  for (uint32_t c = 0; c < s.ncomps; c++) {
    const uint32_t first = s.nodes[s.start[c]];
    bool loops = s.start[c + 1] - s.start[c] > 1;
    for (uint32_t k = 0; k < opt_inline_degree(g, first) && !loops; k++) {
      loops = opt_inline_edge(g, first, k) == first;
    }
    for (uint32_t j = s.start[c]; loops && j < s.start[c + 1]; j++) {
      out[s.nodes[j]] = true;
    }
  }
  return out;
}

bool *opt_blocks_in_loops(MsArena *arena, const MirFunc *f) {
  OptInlineGraph g = {.n = (uint32_t)f->blocks.len};
  g.off = MS_ARENA_NEW_ARRAY_UNINIT(arena, uint32_t, (size_t)g.n + 1);
  uint32_t total = 0;
  for (uint32_t b = 0; b < g.n; b++) {
    g.off[b] = total;
    total += mir_term_ntargets(&f->blocks.ptr[b].term);
  }
  g.off[g.n] = total;
  g.to = MS_ARENA_NEW_ARRAY_UNINIT(arena, uint32_t, total);
  for (uint32_t b = 0; b < g.n; b++) {
    for (uint32_t k = 0; k < g.off[b + 1] - g.off[b]; k++) {
      g.to[g.off[b] + k] = mir_term_target_const(&f->blocks.ptr[b].term, k)->block;
    }
  }
  return opt_inline_cyclic(arena, &g);
}

/* The nodes that keep their recursion check: every cycle passes through one of them. They are the
 * targets of the depth-first back edges, found from `entry` first so a recursion is checked where
 * it is entered from outside. */
static bool *il_cycle_breakers(MsArena *arena, const OptInlineGraph *g, uint32_t entry) {
  uint8_t *state = MS_ARENA_NEW_ARRAY(arena, uint8_t, g->n); /* 0 unvisited, 1 on the stack, 2 done */
  bool *out = MS_ARENA_NEW_ARRAY(arena, bool, g->n);
  uint32_t *sv = MS_ARENA_NEW_ARRAY(arena, uint32_t, g->n);
  uint32_t *sk = MS_ARENA_NEW_ARRAY(arena, uint32_t, g->n);
  const uint32_t first = entry == MIR_NONE ? 0u : 1u;
  for (uint32_t r = 0; r < g->n + first; r++) {
    uint32_t root = r;
    if (first == 1) {
      root = r == 0 ? entry : r - 1;
    }
    if (state[root] != 0) {
      continue;
    }
    state[root] = 1;
    sv[0] = root;
    sk[0] = 0;
    uint32_t depth = 1;
    while (depth > 0) {
      const uint32_t v = sv[depth - 1];
      if (sk[depth - 1] >= opt_inline_degree(g, v)) {
        state[v] = 2;
        depth--;
        continue;
      }
      const uint32_t w = opt_inline_edge(g, v, sk[depth - 1]++);
      if (state[w] == 0) {
        state[w] = 1;
        sv[depth] = w;
        sk[depth++] = 0;
      } else if (state[w] == 1) {
        out[w] = true;
      }
    }
  }
  return out;
}

/* ---- editing helpers ---- */

bool opt_inline_cancel_mismatch(const MirFunc *caller, const MirFunc *callee) {
  if (caller->explicit_cancel == callee->explicit_cancel) {
    return false;
  }
  for (uint32_t b = 0; b < callee->blocks.len; b++) {
    for (uint32_t i = 0; i < callee->blocks.ptr[b].insts.len; i++) {
      const uint8_t op = callee->blocks.ptr[b].insts.ptr[i].op;
      if (op == MOP_Call || op == MOP_CallInd || op == MOP_CallMethod ||
        op == MOP_CallRt) {
        return true;
      }
    }
  }
  return false;
}

static MirValue *il_copy_args(MirModule *m, const MirValue *args, uint32_t n) {
  MirValue *out = MS_ARENA_NEW_ARRAY(&m->arena, MirValue, (size_t)n + 1);
  if (n > 0) {
    __builtin_memcpy(out, args, sizeof(MirValue) * n);
  }
  return out;
}

/* ---- inlining one call ---- */

typedef struct IlMap {
  const MirValue *value; /* callee value -> value in the caller */
  const MirBlock *block; /* callee block -> block in the caller */
  uint32_t scope_base;   /* the caller's scope count before the callee's were added */
} IlMap;

static MirTarget il_map_target(MirModule *m, const IlMap *map, const MirTarget *t) {
  MirTarget out = {.block = map->block[t->block], .nargs = t->nargs};
  out.args = MS_ARENA_NEW_ARRAY(&m->arena, MirValue, (size_t)t->nargs + 1);
  for (uint32_t i = 0; i < t->nargs; i++) {
    out.args[i] = map->value[t->args[i]];
  }
  return out;
}

/* A position the callee does not know (a generated thunk) is the call's own, so a fault there
 * reports the call line; the callee's scopes sit after one scope for the callee itself. */
static MirLoc il_map_loc(const IlMap *map, MirLoc l, MirLoc call) {
  if (l.line == 0 && l.scope == 0) {
    return call;
  }
  l.scope += map->scope_base + 1;
  return l;
}

static MirInst il_map_inst(MirModule *m, const IlMap *map, const MirInst *in, MirLoc call_loc) {
  MirInst out = *in;
  out.args = MS_ARENA_NEW_ARRAY(&m->arena, MirValue, (size_t)in->nargs + 1);
  for (uint32_t i = 0; i < in->nargs; i++) {
    out.args[i] = map->value[in->args[i]];
  }
  out.res = in->res == MIR_NONE ? MIR_NONE : map->value[in->res];
  out.loc = il_map_loc(map, in->loc, call_loc);
  return out;
}

/* The mapped terminator of callee block `cb`; a `ret` becomes a branch to `cont` carrying the
 * result, a missing one a fresh `void` appended to `insts`. */
static MirTerm il_map_term(MirModule *m, MirFunc *f, const IlMap *map, const MirBlockData *cb,
             MirBlock cont, MirLoc call_loc, MirBlockData *dst) {
  MirTerm t = cb->term;
  switch (cb->term.kind) {
  case MT_BR:
    t.a = il_map_target(m, map, &cb->term.a);
    break;
  case MT_CONDBR:
    t.value = map->value[cb->term.value];
    t.a = il_map_target(m, map, &cb->term.a);
    t.b = il_map_target(m, map, &cb->term.b);
    break;
  case MT_SWITCH:
    t.value = map->value[cb->term.value];
    t.b = il_map_target(m, map, &cb->term.b);
    t.cases = MS_ARENA_NEW_ARRAY(&m->arena, MirCase, (size_t)cb->term.ncases + 1);
    for (uint32_t c = 0; c < cb->term.ncases; c++) {
      t.cases[c].value = cb->term.cases[c].value;
      t.cases[c].target = il_map_target(m, map, &cb->term.cases[c].target);
    }
    break;
  case MT_RET: {
    MirValue arg = cb->term.value == MIR_NONE ? MIR_NONE : map->value[cb->term.value];
    if (arg == MIR_NONE) {
      arg = mir_new_value(f, MIR_VOID);
      dst->insts.ptr[dst->insts.len++] =
        opt_inst_make(m, MOP_VoidConst, NULL, 0, (MirImm){0}, arg,
               il_map_loc(map, cb->term_loc, call_loc));
    }
    opt_term_set_br(&t, (MirTarget){.block = cont, .args = il_copy_args(m, &arg, 1), .nargs = 1});
    break;
  }
  default:
    break;
  }
  return t;
}

static void il_fill_block(MirModule *m, MirFunc *f, const IlMap *map, const MirBlockData *cb,
             MirBlock at, MirBlock cont, const MirInst *call) {
  MirBlockData blk = mir_block_empty();
  blk.cold = cb->cold;
  for (uint32_t i = 0; i < cb->params.len; i++) {
    mir_block_param_list_push(&blk.params,
                              (MirBlockParam){map->value[cb->params.ptr[i].value], cb->params.ptr[i].mode});
  }
  mir_inst_list_reserve(&blk.insts, cb->insts.len + 1);
  /* An inlined body has no frame of its own: its recursion check belongs to the out-of-line
   * entry. */
  for (uint32_t i = 0; i < cb->insts.len; i++) {
    const MirInst *in = &cb->insts.ptr[i];
    if (in->op != MOP_DepthEnter && in->op != MOP_DepthLeave) {
      mir_inst_list_push(&blk.insts, il_map_inst(m, map, in, call->loc));
    }
  }
  blk.term = il_map_term(m, f, map, cb, cont, call->loc, &blk);
  blk.term_loc = il_map_loc(map, cb->term_loc, call->loc);
  f->blocks.ptr[at] = blk;
}

/* The callee's positions become a scope called from the call's position; scopes the callee
 * already carries (its own inlined callees) nest beneath it. Returns the new scope's index. */
static uint32_t il_add_scopes(MirFunc *f, const MirFunc *callee, const MirInst *call) {
  const uint32_t base = (uint32_t)f->scopes.len;
  mir_scope_list_push(&f->scopes, ((MirScope){callee->display != MS_NAME_EMPTY ? callee->display : callee->name, callee->loc.file, call->loc.scope, call->loc.line}));
  for (uint32_t k = 0; k < callee->scopes.len; k++) {
    MirScope s = callee->scopes.ptr[k];
    s.parent += base + 1;
    mir_scope_list_push(&f->scopes, s);
  }
  return base;
}

/* The callee's names follow its values, in the frame that scope shows. A parameter has no value of
 * its own once the body is inlined: the argument it receives carries the name, and the debugger
 * shows it only inside the callee's frame. */
static void il_add_names(MirFunc *f, const MirFunc *callee, const MirInst *call,
            const MirValue *values, uint32_t base) {
  const MirBlockData *entry = &callee->blocks.ptr[0];
  for (uint32_t k = 0; k < callee->names.len; k++) {
    MirNamedValue n = callee->names.ptr[k];
    MirValue value = values[n.value];
    for (uint32_t j = 0; j < entry->params.len; j++) {
      if (entry->params.ptr[j].value == n.value) {
        value = call->args[j];
        break;
      }
    }
    n.value = value;
    n.scope += base + 1;
    mir_named_value_list_push(&f->names, n);
  }
}

uint32_t opt_inline_at(MirModule *m, MirFunc *f, uint32_t bi, uint32_t ii, const MirFunc *callee,
           bool ret_own) {
  const MirInst call = f->blocks.ptr[bi].insts.ptr[ii];
  MirBlockData *head = &f->blocks.ptr[bi];
  const uint32_t ntail = (uint32_t)(head->insts.len - ii - 1);
  MirBlockData rest = mir_block_empty();
  mir_block_param_list_push(&rest.params, (MirBlockParam){call.res, ret_own ? MM_MOVE : MM_BORROW});
  mir_inst_list_reserve(&rest.insts, ntail + 1);
  for (uint32_t k = 0; k < ntail; k++) {
    mir_inst_list_push(&rest.insts, head->insts.ptr[ii + 1 + k]);
  }
  rest.term = head->term;
  rest.term_loc = head->term_loc;
  head->insts.len = ii;
  const MirBlock cont = mir_new_block(f);
  f->blocks.ptr[cont] = rest;

  MsArena scratch = ms_arena_new();
  const uint32_t scope_base = il_add_scopes(f, callee, &call);
  MirValue *values = MS_ARENA_NEW_ARRAY(&scratch, MirValue, (size_t)callee->values.len + 1);
  for (uint32_t v = 0; v < callee->values.len; v++) {
    values[v] = mir_new_value(f, callee->values.ptr[v]);
  }
  il_add_names(f, callee, &call, values, scope_base);
  MirBlock *blocks = MS_ARENA_NEW_ARRAY(&scratch, MirBlock, (size_t)callee->blocks.len + 1);
  for (uint32_t k = 0; k < callee->blocks.len; k++) {
    blocks[k] = mir_new_block(f);
  }
  const IlMap map = {values, blocks, scope_base};
  for (uint32_t k = 0; k < callee->blocks.len; k++) {
    il_fill_block(m, f, &map, &callee->blocks.ptr[k], blocks[k], cont, &call);
  }
  head = &f->blocks.ptr[bi];
  opt_term_set_br(&head->term, (MirTarget){.block = blocks[0], .args = call.args, .nargs = call.nargs});
  head->term_loc = call.loc;
  ms_arena_free(&scratch);
  return cont;
}

/* ---- choosing call sites ---- */

typedef struct IlSite { uint32_t ii, callee; } IlSite;

typedef struct IlRun {
  MirModule *m;
  MsArena *arena;
  uint32_t fi;
  const bool *cyc;
  const uint32_t *sites; /* call sites of each function in the module */
  bool only_self, has_unroll;
  MirFunc unroll; /* the body copied into its own recursive calls */
  uint32_t budget, grown;
  uint8_t *consts; /* values defined by a constant instruction */
  uint32_t nconsts, cconsts;
  bool *in_loop; /* per block of `fi`, computed once on first need: inlining at another site neither adds nor removes a cycle through an existing block; NULL until needed */
  IlSite *picks;
  uint32_t npicks, cpicks;
} IlRun;

static bool il_is_const_op(uint8_t op) {
  return op == MOP_IConst || op == MOP_FConst || op == MOP_BConst;
}

static void il_note_consts(IlRun *r, uint32_t first_block) {
  const MirFunc *f = &r->m->funcs.ptr[r->fi];
  /* The table grows by doubling: copying it whole for every inlined call made a long function
   * quadratic. */
  if (r->consts == NULL || f->values.len > r->cconsts) {
    uint32_t cap = r->cconsts == 0 ? 64 : r->cconsts;
    while (cap < f->values.len) {
      cap *= 2;
    }
    uint8_t *grown = MS_ARENA_NEW_ARRAY(r->arena, uint8_t, cap);
    if (r->consts != NULL) {
      __builtin_memcpy(grown, r->consts, r->nconsts);
    }
    r->consts = grown;
    r->cconsts = cap;
  }
  r->nconsts = (uint32_t)f->values.len;
  for (uint32_t b = first_block; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      const MirInst *in = &f->blocks.ptr[b].insts.ptr[i];
      if (il_is_const_op(in->op) && in->res != MIR_NONE) {
        r->consts[in->res] = 1;
      }
    }
  }
}

/* Whether the function has a loop: an edge to a block at or before its source in reverse
 * post-order. */
static bool il_has_loop(const MirFunc *f) {
  MsArena arena = ms_arena_new();
  MirBlock *order = NULL;
  const uint32_t count = mir_rpo(&arena, f, &order);
  uint32_t *pos = MS_ARENA_NEW_ARRAY(&arena, uint32_t, (size_t)f->blocks.len + 1);
  __builtin_memset(pos, 0xff, sizeof(uint32_t) * f->blocks.len);
  for (uint32_t i = 0; i < count; i++) {
    pos[order[i]] = i;
  }
  bool loops = false;
  for (uint32_t i = 0; i < count && !loops; i++) {
    const MirTerm *t = &f->blocks.ptr[order[i]].term;
    for (uint32_t k = 0; k < mir_term_ntargets(t) && !loops; k++) {
      loops = pos[mir_term_target_const(t, k)->block] <= i;
    }
  }
  ms_arena_free(&arena);
  return loops;
}

static bool il_has_check(const MirFunc *f) {
  return f->blocks.len > 0 && f->blocks.ptr[0].insts.len > 0 && f->blocks.ptr[0].insts.ptr[0].op == MOP_DepthEnter;
}

/* Whether `f` needs no stack of its own: no slot and no call, whose argument copies live in the frame. Inlined
 * into a recursive function anything else grows the frame of every level. */
static bool il_frame_free(const MirFunc *f) {
  for (size_t b = 0; b < f->blocks.len; b++) {
    for (size_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      switch ((MirOp)f->blocks.ptr[b].insts.ptr[i].op) {
      case MOP_Slot:
      case MOP_Call:
      case MOP_CallInd:
      case MOP_CallMethod:
      case MOP_CallRt:
        return false;
      default:
        break;
      }
    }
  }
  return true;
}

/* Whether a small enough, auto-hinted callee at `inst` (in block `bi`) is worth inlining. */
static bool il_auto_ok(IlRun *r, uint32_t bi, const MirInst *inst, const MirFunc *callee,
           uint32_t size) {
  if (il_has_loop(callee)) {
    if (r->in_loop == NULL) {
      r->in_loop = opt_blocks_in_loops(r->arena, &r->m->funcs.ptr[r->fi]);
    }
    if (!r->in_loop[bi]) {
      return false;
    }
  }
  uint32_t limit = r->m->inline_base != 0 ? r->m->inline_base : OPT_INLINE_BASE_THRESHOLD;
  if (r->m->funcs.ptr[r->fi].runs_once && limit > OPT_INLINE_COMPACT_THRESHOLD) {
    limit = OPT_INLINE_COMPACT_THRESHOLD; /* a test body runs once: only a call that costs no more than its copy is inlined */
  }
  if (r->sites[inst->imm.a] == 1) {
    limit += IL_SINGLE_CALLER_BONUS;
  }
  for (uint32_t i = 0; i < inst->nargs; i++) {
    limit += (inst->args[i] < r->nconsts && r->consts[inst->args[i]]) ? IL_CONST_ARG_BONUS : 0u;
  }
  return size <= limit && r->grown + size <= r->budget;
}

/* Whether the call `inst` in block `bi` is inlined. */
static bool il_choose(IlRun *r, uint32_t bi, const MirInst *inst) {
  const uint32_t gi = inst->imm.a;
  const MirModule *m = r->m;
  if (gi == r->fi && r->has_unroll) {
    return true;
  }
  if (r->only_self) {
    return false;
  }
  const MirFunc *callee = &m->funcs.ptr[gi];
  if (callee->blocks.len == 0) {
    return false;
  }
  /* A callee on a cycle inlines once its check is gone: every cycle through it still passes a
   * checked function, which never inlines. */
  if (gi == r->fi || (r->cyc[gi] && il_has_check(callee)) || callee->kind != MFK_NORMAL ||
    opt_inline_cancel_mismatch(&m->funcs.ptr[r->fi], callee)) {
    return false;
  }
  const uint32_t size = mir_inst_count(callee);
  bool ok = false;
  if (callee->inline_hint == MINL_ALWAYS) {
    ok = true;
  } else if (callee->inline_hint == MINL_AUTO && (!r->cyc[r->fi] || il_frame_free(callee))) {
    ok = il_auto_ok(r, bi, inst, callee, size);
  }
  if (ok) {
    r->grown += size;
  }
  return ok;
}

static void il_pick(IlRun *r, uint32_t ii, uint32_t gi) {
  if (r->npicks == r->cpicks) {
    const uint32_t cap = r->cpicks == 0 ? 8 : r->cpicks * 2;
    IlSite *grown = MS_ARENA_NEW_ARRAY(r->arena, IlSite, cap);
    if (r->npicks > 0) {
      __builtin_memcpy(grown, r->picks, sizeof(IlSite) * r->npicks);
    }
    r->picks = grown;
    r->cpicks = cap;
  }
  r->picks[r->npicks++] = (IlSite){ii, gi};
}

/* Chooses every site in block `bi`, then inlines from the last: each split moves only the
 * instructions up to the previous split. Callee constants never reach a later call's arguments, so
 * the choices match inlining one site at a time. */
static bool il_inline_block(IlRun *r, uint32_t bi) {
  MirFunc *f = &r->m->funcs.ptr[r->fi];
  r->npicks = 0;
  for (uint32_t ii = 0; ii < f->blocks.ptr[bi].insts.len; ii++) {
    const MirInst *inst = &f->blocks.ptr[bi].insts.ptr[ii];
    uint32_t gi = 0;
    if (il_call_target(inst, &gi) && il_choose(r, bi, inst)) {
      il_pick(r, ii, gi);
    }
  }
  for (uint32_t k = r->npicks; k > 0; k--) {
    const IlSite s = r->picks[k - 1];
    const MirFunc *callee = (s.callee == r->fi && r->has_unroll) ? &r->unroll : &r->m->funcs.ptr[s.callee];
    const bool ret_own = mir_needs_drop(r->m, callee->ret) && !callee->ret_borrowed;
    const MirBlock cont = opt_inline_at(r->m, f, bi, s.ii, callee, ret_own);
    /* Only the call definition is replaced; existing constants keep their ids when the tail
     * moves. Fresh callee definitions follow the continuation block. */
    il_note_consts(r, cont + 1);
  }
  return r->npicks > 0;
}

/* The body of a small directly self-recursive function, to be copied into its own recursive calls
 * once: each copy runs without a call, a frame or a recursion check of its own. The function then
 * takes `inline(never)`, so the unrolling happens once however often the pass runs. */
static bool il_unrollable(const MirModule *m, uint32_t fi) {
  const MirFunc *f = &m->funcs.ptr[fi];
  if (f->inline_hint != MINL_AUTO || f->kind != MFK_NORMAL) {
    return false;
  }
  uint32_t calls = 0;
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      uint32_t callee = 0;
      calls += (il_call_target(&f->blocks.ptr[b].insts.ptr[i], &callee) && callee == fi) ? 1u : 0u;
    }
  }
  return calls > 0 && calls <= 2 && mir_inst_count(f) <= IL_SELF_UNROLL_MAX_SIZE;
}

/* Inlines the call sites of `fi` its heuristics choose; with `only_self`, only its own calls (the
 * unrolling). */
static bool il_inline_sites(MirModule *m, MsArena *arena, uint32_t fi, const bool *cyc,
              const uint32_t *sites, bool only_self) {
  IlRun r = {.m = m, .arena = arena, .fi = fi, .cyc = cyc, .sites = sites,
       .only_self = only_self};
  r.has_unroll = il_unrollable(m, fi);
  if (r.has_unroll) {
    opt_func_deep_clone(m, &m->funcs.ptr[fi], &r.unroll);
  }
  r.budget = mir_inst_count(&m->funcs.ptr[fi]) * OPT_INLINE_GROWTH_FACTOR + OPT_INLINE_GROWTH_SLACK;
  il_note_consts(&r, 0);
  bool changed = false;
  for (uint32_t bi = (uint32_t)m->funcs.ptr[fi].blocks.len; bi > 0; bi--) {
    changed |= il_inline_block(&r, bi - 1);
  }
  if (r.has_unroll && changed) {
    m->funcs.ptr[fi].inline_hint = MINL_NEVER;
  }
  return changed;
}

static bool il_inline_into(MirModule *m, MsArena *arena, uint32_t fi, const bool *cyc,
             const uint32_t *sites) {
  bool changed = il_inline_sites(m, arena, fi, cyc, sites, false);
  /* Inlining a sibling on the cycle can leave the function directly self-recursive and small. */
  if (m->funcs.ptr[fi].inline_hint == MINL_AUTO && il_unrollable(m, fi)) {
    changed |= il_inline_sites(m, arena, fi, cyc, sites, true);
  }
  return changed;
}

static bool il_inline_calls(MirModule *m) {
  MsArena arena = ms_arena_new();
  const OptInlineGraph g = opt_inline_direct_graph(&arena, m);
  const bool *cyc = opt_inline_cyclic(&arena, &g);
  uint32_t *sites = MS_ARENA_NEW_ARRAY(&arena, uint32_t, m->funcs.len);
  for (uint32_t i = 0; i < g.off[g.n]; i++) {
    sites[g.to[i]]++;
  }
  const IlSccs s = il_sccs(&arena, &g);
  bool changed = false;
  for (uint32_t j = 0; j < g.n; j++) {
    changed |= il_inline_into(m, &arena, s.nodes[j], cyc, sites);
  }
  ms_arena_free(&arena);
  return changed;
}

/* ---- recursion checks ---- */

static bool il_strip_checks(MirFunc *f) {
  bool changed = false;
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    MirBlockData *blk = &f->blocks.ptr[b];
    uint32_t kept = 0;
    for (uint32_t i = 0; i < blk->insts.len; i++) {
      if (blk->insts.ptr[i].op != MOP_DepthEnter && blk->insts.ptr[i].op != MOP_DepthLeave) {
        blk->insts.ptr[kept++] = blk->insts.ptr[i];
      }
    }
    changed |= kept != blk->insts.len;
    blk->insts.len = kept;
  }
  return changed;
}

static bool il_has_indirect_call(const MirFunc *f) {
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      const uint8_t op = f->blocks.ptr[b].insts.ptr[i].op;
      if (op == MOP_CallInd || op == MOP_CallMethod || op == MOP_CallRt) {
        return true;
      }
    }
  }
  return false;
}

/* Removes depth accounting from every function that does not need it to bound the stack: a
 * function on no cycle, or on a cycle that another function already checks. Indirect calls
 * (closures, interfaces, runtime callbacks) may reach any closure or method function, so they are
 * edges to all of them. Runs after the last inlining: an inlined body drops its check, so merging
 * an unchecked function into a checked one is fine but the reverse would leave a cycle with none.
 * `early` keeps the check of an acyclic function, so its size is unchanged for the inliner. */
static bool il_strip_depth(MirModule *m, bool early) {
  MsArena arena = ms_arena_new();
  OptInlineGraph g = opt_inline_direct_graph(&arena, m);
  uint32_t *itargets = MS_ARENA_NEW_ARRAY(&arena, uint32_t, m->funcs.len + 2 * m->desc_glue.len);
  bool *indirect = MS_ARENA_NEW_ARRAY(&arena, bool, m->funcs.len);
  for (uint32_t i = 0; i < m->funcs.len; i++) {
    indirect[i] = il_has_indirect_call(&m->funcs.ptr[i]);
    if (m->funcs.ptr[i].kind != MFK_NORMAL) {
      itargets[g.nit++] = i;
    }
  }
  /* A descriptor's equality and hash functions are called by the runtime, which reaches them again through the
   * descriptors of the fields: a recursive type recurses through them with no direct call. */
  for (size_t k = 0; k < m->desc_glue.len; k++) {
    itargets[g.nit++] = m->desc_glue.ptr[k].eq;
    itargets[g.nit++] = m->desc_glue.ptr[k].hash;
  }
  g.indirect = indirect;
  g.itargets = itargets;
  const bool *checked = il_cycle_breakers(&arena, &g, m->entry);
  const bool *cyc = opt_inline_cyclic(&arena, &g);
  bool changed = false;
  for (uint32_t i = 0; i < m->funcs.len; i++) {
    if (!checked[i] && !(early && !cyc[i])) {
      changed |= il_strip_checks(&m->funcs.ptr[i]);
    }
  }
  ms_arena_free(&arena);
  return changed;
}

/* ---- entry points ---- */

bool opt_inline(MirModule *m) {
  bool changed = opt_inline_specialize_sort_thunks(m);
  changed |= opt_sortgen(m);
  changed |= opt_inline_specialize_closure_args(m);
  /* A recursive cycle keeps one check; the unchecked functions on it then inline like any other. */
  changed |= il_strip_depth(m, true);
  changed |= il_inline_calls(m);
  /* A call that inlining just moved into its caller may now pass a closure the caller makes. */
  changed |= opt_inline_specialize_closure_args(m);
  /* Before the closures are opened: a fused wrapper calls the inner code directly, which the next round inlines. */
  changed |= opt_inline_fuse_captured(m);
  changed |= opt_inline_closures(m);
  changed |= il_strip_depth(m, false);
  changed |= opt_inline_remove_dead(m);
  return changed;
}

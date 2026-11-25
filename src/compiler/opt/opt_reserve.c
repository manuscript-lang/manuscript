/* The `reserve` pass: sizes a fresh list for the loop that fills it.
 *
 * A list built one `append` per iteration of a counted loop grows by doubling, so it is copied
 * about `log2(n)` times. When the loop's trip count is known before it starts, the list can be
 * allocated at its final size instead:
 *
 *     l0 = list.lit                      cap = <clamped trip count + k>
 *     l1 = list.push l0, x               l0 = list.new cap
 *     br head(i0, l1)            =>      l1 = list.push l0, x
 *     head(i, l):                        br head(i0, l1)
 *       br_if (icmp.lt i, n), body, out
 *
 * The rewrite applies when the literal (empty, or with elements that become pushes) reaches the
 * loop entry through `k` pushes in one block, the loop's only exit is the header's false edge,
 * every back edge passes `i + 1`, and every path from the header to a back edge pushes the list
 * at least once. Then the loop pushes at least `max(0, n - i0)` items (one more for `icmp.le`).
 * Capacity is not observable, so a loop that faults early only allocated sooner; the trip count is
 * clamped to MAX_RESERVE items so a huge bound never allocates more than that up front. */

#include "compiler/mir/mir_analysis.h"
#include "compiler/opt/opt_pass.h"
#include "base/safe.h"

#define RESERVE_MAX INT64_C(1048576) /* the most items reserved ahead of the loop */

typedef enum DefKind { DEF_NONE, DEF_INST, DEF_PARAM } DefKind;

/* Where a value is defined. */
typedef struct DefAt {
  uint8_t kind;
  uint32_t block, index; /* index is the instruction position for DEF_INST */
} DefAt;

/* The control-flow facts the plan reads. */
typedef struct RsvCfg {
  const MirFunc *f;
  MirPreds preds;
  MirBlock *idom;
  DefAt *defs;
  uint32_t *uses;
} RsvCfg;

/* How to obtain a value at the literal. */
typedef enum SourceKind { SRC_VALUE, SRC_CONST, SRC_LEN } SourceKind;
typedef struct RsvSource {
  uint8_t kind;
  MirValue value; /* SRC_VALUE: the value; SRC_LEN: the list */
  int64_t constant;
} RsvSource;

/* A literal to replace with a sized `list.new`. */
typedef struct RsvPlan {
  MirBlock block;
  uint32_t index; /* the literal */
  MirValue lit;
  int64_t pushed; /* pushes between the literal and the loop */
  RsvSource start, bound;
  bool inclusive;
} RsvPlan;

static void rsv_cfg_init(MsArena *arena, const MirFunc *f, RsvCfg *cfg) {
  cfg->f = f;
  MirBlock *order = NULL;
  const uint32_t count = mir_rpo(arena, f, &order);
  cfg->preds = mir_preds(arena, f);
  cfg->idom = mir_dominators(arena, f, order, count, &cfg->preds);
  cfg->defs = MS_ARENA_NEW_ARRAY(arena, DefAt, (size_t)f->values.len + 1);
  for (uint32_t v = 0; v < f->values.len; v++) {
    cfg->defs[v] = (DefAt){DEF_NONE, 0, 0};
  }
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t p = 0; p < f->blocks.ptr[b].params.len; p++) {
      cfg->defs[f->blocks.ptr[b].params.ptr[p].value] = (DefAt){DEF_PARAM, b, 0};
    }
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      if (f->blocks.ptr[b].insts.ptr[i].res != MIR_NONE) {
        cfg->defs[f->blocks.ptr[b].insts.ptr[i].res] = (DefAt){DEF_INST, b, i};
      }
    }
  }
  cfg->uses = mir_use_counts(arena, f);
}

/* Whether `v` is defined before instruction `index` of `block`. */
static bool rsv_cfg_available(const RsvCfg *cfg, MirValue v, MirBlock block, uint32_t index) {
  const DefAt d = cfg->defs[v];
  switch ((DefKind)d.kind) {
  case DEF_PARAM: return mir_dominates(cfg->idom, d.block, block);
  case DEF_INST: return d.block == block ? d.index < index : mir_dominates(cfg->idom, d.block, block);
  case DEF_NONE: return false;
  }
  return false;
}

static const MirInst *rsv_cfg_inst(const RsvCfg *cfg, MirValue v) {
  const DefAt d = cfg->defs[v];
  return d.kind == DEF_INST ? &cfg->f->blocks.ptr[d.block].insts.ptr[d.index] : NULL;
}

/* The arguments latch `l` passes to header `h` (the last edge to `h`); NULL when there is none. */
static const MirTarget *rsv_back_edge(const MirFunc *f, MirBlock l, MirBlock h) {
  const MirTarget *found = NULL;
  for (uint32_t t = 0; t < mir_term_ntargets(&f->blocks.ptr[l].term); t++) {
    const MirTarget *target = mir_term_target_const(&f->blocks.ptr[l].term, t);
    found = target->block == h ? target : found;
  }
  return found;
}

/* The body of the natural loop of `h`: `in_body` marks it, the return value counts it. */
static uint32_t rsv_natural_loop(MsArena *arena, const RsvCfg *cfg, MirBlock h, const MirBlock *latches,
              uint32_t nlatches, bool *in_body) {
  const uint32_t n = (uint32_t)cfg->f->blocks.len;
  MirBlock *work = MS_ARENA_NEW_ARRAY(arena, MirBlock, (size_t)n * 2 + nlatches + 2);
  uint32_t top = 0, count = 1;
  __builtin_memset(in_body, 0, n);
  in_body[h] = true;
  for (uint32_t i = 0; i < nlatches; i++) {
    work[top++] = latches[i];
  }
  while (top > 0) {
    const MirBlock b = work[--top];
    if (in_body[b]) {
      continue;
    }
    in_body[b] = true;
    count++;
    for (uint32_t k = 0; k < mir_preds_count(&cfg->preds, b); k++) {
      work[top++] = mir_pred(&cfg->preds, b, k);
    }
  }
  return count;
}

/* Whether `v` is `i + 1`. */
static bool rsv_is_increment(const RsvCfg *cfg, MirValue v, MirValue i) {
  const MirInst *add = rsv_cfg_inst(cfg, v);
  if (add == NULL || (add->op != MOP_IAdd && add->op != MOP_IAddChk) || add->args[0] != i) {
    return false;
  }
  const MirInst *one = rsv_cfg_inst(cfg, add->args[1]);
  return one != NULL && one->op == MOP_IConst && one->imm.tag == MI_INT && one->imm.i == 1;
}

typedef struct Reach {
  const RsvCfg *cfg;
  const bool *in_body;
  MirValue list;
  MirValue *seen; /* the values on the current path; at most one per value, so the recursion is
           bounded by the number of values */
  uint32_t nseen;
} Reach;

/* Whether `v` is the list after pushes only (at least one with `once`). Loop parameters met again
 * are assumed to hold the list unchanged, which never proves a push. */
static bool rsv_reach(Reach *r, MirValue v, bool once) {
  if (v == r->list) {
    return !once;
  }
  for (uint32_t i = 0; i < r->nseen; i++) {
    if (r->seen[i] == v) {
      return !once;
    }
  }
  r->seen[r->nseen++] = v;
  const MirFunc *f = r->cfg->f;
  const DefAt d = r->cfg->defs[v];
  bool ok = false;
  if (d.kind == DEF_INST && r->in_body[d.block]) {
    const MirInst *inst = &f->blocks.ptr[d.block].insts.ptr[d.index];
    ok = inst->op == MOP_ListPush && rsv_reach(r, inst->args[0], false);
  } else if (d.kind == DEF_PARAM && r->in_body[d.block]) {
    const MirBlockData *blk = &f->blocks.ptr[d.block];
    uint32_t k = 0;
    while (k < blk->params.len && blk->params.ptr[k].value != v) {
      k++;
    }
    ok = k < blk->params.len;
    for (uint32_t p = 0; ok && p < mir_preds_count(&r->cfg->preds, d.block); p++) {
      const MirTarget *edge = rsv_back_edge(f, mir_pred(&r->cfg->preds, d.block, p), d.block);
      ok = edge != NULL && rsv_reach(r, edge->args[k], once);
    }
  }
  r->nseen--;
  return ok;
}

/* The empty literal that reaches `v` in block `entry` through pushes, with the push count. */
static bool rsv_literal_chain(const RsvCfg *cfg, MirBlock entry, MirValue v, RsvPlan *plan) {
  int64_t pushed = 0;
  for (;;) {
    const DefAt d = cfg->defs[v];
    if (cfg->uses[v] != 1 || d.kind != DEF_INST || d.block != entry) {
      return false;
    }
    const MirInst *inst = &cfg->f->blocks.ptr[d.block].insts.ptr[d.index];
    if (inst->op == MOP_ListLit) {
      plan->block = d.block;
      plan->index = d.index;
      plan->lit = v;
      plan->pushed = pushed + (int64_t)inst->nargs;
      return true;
    }
    if (inst->op != MOP_ListPush) {
      return false;
    }
    pushed++;
    v = inst->args[0];
  }
}

/* How to compute `v` at the literal: a constant, an available value, or the length of an available
 * list (a loop condition re-reads `list.len` each iteration). */
static bool rsv_find_source(const RsvCfg *cfg, const bool *in_body, MirValue v, const RsvPlan *at,
            RsvSource *out) {
  const MirInst *inst = rsv_cfg_inst(cfg, v);
  if (inst != NULL && inst->op == MOP_IConst && inst->imm.tag == MI_INT) {
    *out = (RsvSource){SRC_CONST, MIR_NONE, inst->imm.i};
    return true;
  }
  if (rsv_cfg_available(cfg, v, at->block, at->index)) {
    *out = (RsvSource){SRC_VALUE, v, 0};
    return true;
  }
  if (inst == NULL || inst->op != MOP_ListLen) {
    return false;
  }
  if (in_body[cfg->defs[v].block] && rsv_cfg_available(cfg, inst->args[0], at->block, at->index)) {
    *out = (RsvSource){SRC_LEN, inst->args[0], 0};
    return true;
  }
  return false;
}

/* The loop at header `h` and the facts the rewrite needs about it. */
typedef struct LoopInfo {
  const MirBlockData *head;
  MirBlock entry;
  const MirTarget *enter;
  MirValue counter, bound;
  uint32_t counter_param;
  bool inclusive;
  const MirBlock *latches;
  uint32_t nlatches;
  const bool *in_body;
} LoopInfo;

/* Whether the body of the loop at `h` neither returns nor leaves except through the header. */
static bool rsv_body_closed(const MirFunc *f, MirBlock h, const bool *in_body) {
  for (MirBlock b = 0; b < f->blocks.len; b++) {
    const MirTerm *term = &f->blocks.ptr[b].term;
    if (!in_body[b]) {
      continue;
    }
    if (term->kind == MT_RET || term->kind == MT_UNREACHABLE) {
      return false;
    }
    for (uint32_t t = 0; b != h && t < mir_term_ntargets(term); t++) {
      if (!in_body[mir_term_target_const(term, t)->block]) {
        return false;
      }
    }
  }
  return true;
}

/* Checks the shape of the loop at `h`: one exit (the header's false edge), one entry edge, and a
 * counted condition. Fills `info`. */
static bool rsv_analyse_loop(MsArena *arena, const RsvCfg *cfg, MirBlock h, LoopInfo *info) {
  const MirFunc *f = cfg->f;
  const MirBlockData *head = &f->blocks.ptr[h];
  if (head->term.kind != MT_CONDBR) {
    return false;
  }
  MirBlock *latches = MS_ARENA_NEW_ARRAY(arena, MirBlock, (size_t)f->blocks.len + 1);
  uint32_t nlatches = 0;
  for (uint32_t k = 0; k < mir_preds_count(&cfg->preds, h); k++) {
    const MirBlock p = mir_pred(&cfg->preds, h, k);
    if (mir_dominates(cfg->idom, h, p)) {
      latches[nlatches++] = p;
    }
  }
  bool *in_body = MS_ARENA_NEW_ARRAY(arena, bool, (size_t)f->blocks.len + 1);
  if (nlatches == 0) {
    return false;
  }
  rsv_natural_loop(arena, cfg, h, latches, nlatches, in_body);
  if (in_body[head->term.b.block] || !in_body[head->term.a.block]) {
    return false;
  }
  if (!rsv_body_closed(f, h, in_body)) {
    return false;
  }
  uint32_t nentries = 0;
  for (uint32_t k = 0; k < mir_preds_count(&cfg->preds, h); k++) {
    const MirBlock p = mir_pred(&cfg->preds, h, k);
    info->entry = in_body[p] ? info->entry : p;
    nentries += in_body[p] ? 0u : 1u;
  }
  if (nentries != 1 || f->blocks.ptr[info->entry].term.kind != MT_BR) {
    return false;
  }
  const MirInst *test = rsv_cfg_inst(cfg, head->term.value);
  if (test == NULL || test->op != MOP_ICmp || test->imm.tag != MI_CC ||
    (test->imm.a != MCC_LT && test->imm.a != MCC_LE)) {
    return false;
  }
  info->head = head;
  info->enter = &f->blocks.ptr[info->entry].term.a;
  info->counter = test->args[0];
  info->bound = test->args[1];
  info->inclusive = test->imm.a == MCC_LE;
  info->latches = latches;
  info->nlatches = nlatches;
  info->in_body = in_body;
  for (info->counter_param = 0; info->counter_param < head->params.len; info->counter_param++) {
    if (head->params.ptr[info->counter_param].value == info->counter) {
      return true;
    }
  }
  return false;
}

/* Whether every latch passes `counter + 1` and, for parameter `lp`, a list that grew. */
static bool rsv_latches_grow(MsArena *arena, const RsvCfg *cfg, const LoopInfo *info, uint32_t lp,
            MirBlock h) {
  Reach r = {cfg, info->in_body, info->head->params.ptr[lp].value,
       MS_ARENA_NEW_ARRAY(arena, MirValue, (size_t)cfg->f->values.len + 1), 0};
  for (uint32_t i = 0; i < info->nlatches; i++) {
    const MirTarget *edge = rsv_back_edge(cfg->f, info->latches[i], h);
    if (edge == NULL || !rsv_reach(&r, edge->args[lp], true)) {
      return false;
    }
    r.nseen = 0;
  }
  return true;
}

static bool rsv_counter_increments(const RsvCfg *cfg, const LoopInfo *info, MirBlock h) {
  for (uint32_t i = 0; i < info->nlatches; i++) {
    const MirTarget *edge = rsv_back_edge(cfg->f, info->latches[i], h);
    if (edge == NULL || !rsv_is_increment(cfg, edge->args[info->counter_param], info->counter)) {
      return false;
    }
  }
  return true;
}

/* A plan for loop header `h`, when the loop qualifies. */
static bool rsv_plan_loop(MsArena *arena, const RsvCfg *cfg, MirBlock h, RsvPlan *plan) {
  LoopInfo info = {0};
  info.entry = MIR_NONE;
  if (!rsv_analyse_loop(arena, cfg, h, &info) || !rsv_counter_increments(cfg, &info, h)) {
    return false;
  }
  for (uint32_t lp = 0; lp < info.head->params.len; lp++) {
    if (lp == info.counter_param || !rsv_latches_grow(arena, cfg, &info, lp, h) ||
      !rsv_literal_chain(cfg, info.entry, info.enter->args[lp], plan) ||
      !rsv_find_source(cfg, info.in_body, info.enter->args[info.counter_param], plan, &plan->start) ||
      !rsv_find_source(cfg, info.in_body, info.bound, plan, &plan->bound)) {
      continue;
    }
    plan->inclusive = info.inclusive;
    return true;
  }
  return false;
}

/* Instructions inserted in place of the literal. */
typedef struct RsvEmit {
  MirModule *m;
  MirFunc *f;
  MirInst *code;
  uint32_t count;
  MirLoc loc;
} RsvEmit;

static MirValue rsv_emit_op(RsvEmit *e, MirOp op, const MirValue *args, uint32_t nargs, MirImm imm,
            MirTy ty) {
  MirInst inst = {0};
  inst.op = (uint8_t)op;
  inst.imm = imm;
  inst.res = mir_new_value(e->f, ty);
  inst.loc = e->loc;
  inst.nargs = nargs;
  inst.args = MS_ARENA_NEW_ARRAY(&e->m->arena, MirValue, (size_t)nargs + 1);
  for (uint32_t i = 0; i < nargs; i++) {
    inst.args[i] = args[i];
  }
  e->code[e->count++] = inst;
  return inst.res;
}

static MirValue rsv_emit_int(RsvEmit *e, int64_t c) {
  return rsv_emit_op(e, MOP_IConst, NULL, 0, (MirImm){.tag = MI_INT, .i = c}, MIR_INT);
}

static MirValue rsv_emit_source(RsvEmit *e, const RsvSource *s) {
  if (s->kind == SRC_VALUE) {
    return s->value;
  }
  if (s->kind == SRC_CONST) {
    return rsv_emit_int(e, s->constant);
  }
  return rsv_emit_op(e, MOP_ListLen, &s->value, 1, (MirImm){0}, MIR_INT);
}

static MirValue rsv_emit_cmp(RsvEmit *e, MirCc cc, MirValue a, MirValue b) {
  const MirValue args[2] = {a, b};
  return rsv_emit_op(e, MOP_ICmp, args, 2, (MirImm){.tag = MI_CC, .a = cc}, MIR_BOOL);
}

static MirValue rsv_emit_select(RsvEmit *e, MirValue cond, MirValue yes, MirValue no) {
  const MirValue args[3] = {cond, yes, no};
  return rsv_emit_op(e, MOP_Select, args, 3, (MirImm){0}, MIR_INT);
}

/* The clamped capacity: `max(0, min(bound - start, MAX))` when the loop runs, plus the pushes
 * made before it. A wrapped difference lands in 0..=MAX and is zeroed unless the loop runs. */
static MirValue rsv_emit_capacity(RsvEmit *e, const RsvPlan *plan) {
  const MirValue start = rsv_emit_source(e, &plan->start);
  const MirValue bound = rsv_emit_source(e, &plan->bound);
  const MirValue zero = rsv_emit_int(e, 0);
  const MirValue most = rsv_emit_int(e, RESERVE_MAX);
  const MirValue extra = rsv_emit_int(e, plan->pushed + (plan->inclusive ? 1 : 0));
  const MirValue sub_args[2] = {bound, start};
  MirValue diff = rsv_emit_op(e, MOP_ISub, sub_args, 2, (MirImm){0}, MIR_INT);
  diff = rsv_emit_select(e, rsv_emit_cmp(e, MCC_LT, diff, zero), zero, diff);
  diff = rsv_emit_select(e, rsv_emit_cmp(e, MCC_GT, diff, most), most, diff);
  const MirValue runs = rsv_emit_cmp(e, plan->inclusive ? MCC_LE : MCC_LT, start, bound);
  diff = rsv_emit_select(e, runs, diff, zero);
  const MirValue add_args[2] = {diff, extra};
  return rsv_emit_op(e, MOP_IAdd, add_args, 2, (MirImm){0}, MIR_INT);
}

static void rsv_apply_plan(MirModule *m, MirFunc *f, const RsvPlan *plan) {
  MirBlockData *blk = &f->blocks.ptr[plan->block];
  const MirInst lit = blk->insts.ptr[plan->index];
  RsvEmit e = {m, f, MS_ARENA_NEW_ARRAY(&m->arena, MirInst, (size_t)lit.nargs + 24), 0, lit.loc};
  const MirValue cap = rsv_emit_capacity(&e, plan);
  const MirTy ty = mir_value_ty(f, plan->lit);
  /* A literal with elements becomes the sized list and one push per element. */
  MirValue list = lit.nargs == 0 ? plan->lit : mir_new_value(f, ty);
  MirInst fresh = {0};
  fresh.op = MOP_ListNew;
  fresh.res = list;
  fresh.loc = e.loc;
  fresh.nargs = 1;
  fresh.args = MS_ARENA_NEW_ARRAY(&m->arena, MirValue, 1);
  fresh.args[0] = cap;
  e.code[e.count++] = fresh;
  for (uint32_t k = 0; k < lit.nargs; k++) {
    MirInst push = {0};
    push.op = MOP_ListPush;
    push.res = k + 1 == lit.nargs ? plan->lit : mir_new_value(f, ty);
    push.loc = e.loc;
    push.nargs = 2;
    push.args = MS_ARENA_NEW_ARRAY(&m->arena, MirValue, 2);
    push.args[0] = list;
    push.args[1] = lit.args[k];
    e.code[e.count++] = push;
    list = push.res;
  }
  MirInst *out = MS_ARENA_NEW_ARRAY(&m->arena, MirInst, (size_t)blk->insts.len + e.count);
  __builtin_memcpy(out, blk->insts.ptr, sizeof(MirInst) * plan->index);
  __builtin_memcpy(out + plan->index, e.code, sizeof(MirInst) * e.count);
  __builtin_memcpy(out + plan->index + e.count, blk->insts.ptr + plan->index + 1,
                   sizeof(MirInst) * (blk->insts.len - plan->index - 1));
  opt_block_set_insts(blk, out, (uint32_t)(blk->insts.len + e.count - 1));
}

static bool rsv_has_list_literal(const MirFunc *f) {
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      if (f->blocks.ptr[b].insts.ptr[i].op == MOP_ListLit) {
        return true;
      }
    }
  }
  return false;
}

/* Sizes the first literal that qualifies; false when none does. */
static bool rsv_reserve_one(MirModule *m, MirFunc *f) {
  if (!rsv_has_list_literal(f)) {
    return false;
  }
  MsArena arena = ms_arena_new();
  RsvCfg cfg;
  RsvPlan plan = {0};
  rsv_cfg_init(&arena, f, &cfg);
  bool found = false;
  for (MirBlock h = 1; h < f->blocks.len && !found; h++) {
    found = rsv_plan_loop(&arena, &cfg, h, &plan);
  }
  if (found) {
    rsv_apply_plan(m, f, &plan);
  }
  ms_arena_free(&arena);
  return found;
}

bool opt_reserve(MirModule *m) {
  bool changed = false;
  for (uint32_t fi = 0; fi < m->funcs.len; fi++) {
    while (rsv_reserve_one(m, &m->funcs.ptr[fi])) {
      changed = true;
    }
  }
  return changed;
}

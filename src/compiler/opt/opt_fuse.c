/* The `fuse` pass: a loop that builds a temporary list runs inside the loop that reads it.
 *
 * `xs.map(f).filter(g).sum()` builds a list for each stage and reads it back once. After inlining, MIR shows
 * the two halves: a *builder* loop that pushes to a list nobody else can see, and a *reader* loop that visits
 * that list in order and then drops it. Both loops are counted and the list is owned by one slot, so the
 * pass runs the reader's body at the builder's push and never makes the list:
 *
 *     E:  cancel c; L = take S; discard c; <setup>; n = list.len L; br R(0, init..)
 *     R(j, acc..):  br_if j < n, body, X(..)          body: e = list.get L, j; ..; br R(j + 1, acc'..)
 *     P:  .. v ..; t = take S; t' = list.push t, v; put S, t'; ..
 *
 *   becomes
 *
 *     Pre: <setup>; put sk, init                 P: .. v ..; br body
 *     body: acc = load sk; ..; put sk, acc'; br C    C: the rest of P after the push
 *     E:  acc = load sk; br X(..)
 *
 * The reader's accumulators live in stack slots, which the backend turns back into registers. A slot is
 * written only on the reader's own paths, so the exit reads what the last iteration left.
 *
 * Conditions: the list has scalar elements and one push site; the reader reads it only by the counter, drops
 * it once and carries only scalars; neither loop calls out, writes memory other than its own lists, or
 * waits (so the order of their effects cannot be seen); the setup between the loops only allocates. If both loops can fault, the fault reported first may now come from the reader: the
 * program faults either way, and the owner chose that over keeping the producer's fault first.
 *
 * Chains fuse stage by stage: the first fusion leaves a loop that builds the next stage's list. The pass
 * makes one fusion per function and call, and the pipeline simplifies and calls it again until nothing changes. */

#include "compiler/mir/mir_analysis.h"
#include "compiler/mir/mir_pass.h"
#include "compiler/opt/opt_pass.h"
#include "base/safe.h"

#define FUSE_MAX_ACC 4

typedef struct Def {
  MirBlock block;
  uint32_t index; /* MIR_NONE for a block parameter */
} Def;

/* Everything one fusion needs, found before anything is changed. */
typedef struct Fusion {
  MirBlock reader;   /* header R */
  MirBlock entry;    /* E: leaves the builder loop and enters R */
  MirBlock body0;    /* the reader's first body block */
  MirBlock exit;     /* X */
  MirBlock header;   /* builder loop header P */
  MirBlock pre;      /* the builder loop's only entry edge's source */
  MirBlock site;     /* the block with the push */
  uint32_t take_at;  /* the push triple in `site` */
  MirValue list, count, slot, element;
  uint32_t nacc;
  MirValue acc[FUSE_MAX_ACC]; /* R's parameters after the counter */
  MirValue init[FUSE_MAX_ACC];
  MirTy acc_ty[FUSE_MAX_ACC];
} Fusion;

typedef struct Ctx {
  const MirModule *m;
  const MirFunc *f;
  Def *defs;
  uint32_t *uses;
  MirPreds preds;
  MirBlock *idom;
  MirBits body;  /* the reader's body blocks */
  MirBits loop;  /* the builder loop's blocks */
} Ctx;

static bool is_op(const MirInst *i, MirOp op) {
  return i->op == op;
}

static const MirInst *def_inst(const Ctx *c, MirValue v) {
  const Def d = c->defs[v];
  return d.index == MIR_NONE ? NULL : &c->f->blocks.ptr[d.block].insts.ptr[d.index];
}

static bool const_int_is(const Ctx *c, MirValue v, int64_t want) {
  const MirInst *d = def_inst(c, v);
  return d != NULL && is_op(d, MOP_IConst) && d->imm.i == want;
}

/* An instruction that may sit between two loops without anyone seeing it move: it allocates, makes a slot or is
 * pure. */
static bool movable_setup(const MirInst *i) {
  switch ((MirOp)i->op) {
  case MOP_Slot:
  case MOP_Put:
  case MOP_ListNew:
    return true;
  default: return (mir_op_info[i->op].effects & ~MIR_E_ALLOC) == 0;
  }
}

/* Whether an instruction of a fused loop cannot be told apart by when it runs: it makes no call, waits for
 * nothing and writes no memory but the lists and slots the loops own. */
static bool order_free(const MirInst *i) {
  const uint8_t fx = mir_op_info[i->op].effects;
  if ((fx & MIR_E_IO) != 0) {
    return false;
  }
  if ((fx & MIR_E_WRITES) == 0) {
    return true;
  }
  switch ((MirOp)i->op) {
  case MOP_Put:
  case MOP_Take:
  case MOP_ListPush:
  case MOP_ListPushU:
  case MOP_Drop: return true;
  default: return false;
  }
}

static bool blocks_order_free(const Ctx *c, const MirBits *set) {
  for (uint32_t b = 0; b < c->f->blocks.len; b++) {
    if (!mir_bits_test(set, b)) {
      continue;
    }
    const MirBlockData *blk = &c->f->blocks.ptr[b];
    for (uint32_t i = 0; i < blk->insts.len; i++) {
      if (!order_free(&blk->insts.ptr[i])) {
        return false;
      }
    }
  }
  return true;
}

/* ---- the reader ---- */

/* Fills the body set of reader header `r`: what its true edge reaches without passing `r`. False when the
 * body leaves by anything but an edge back to `r`. */
static bool reader_body(MsArena *arena, Ctx *c, MirBlock r, MirBlock first) {
  c->body = mir_bits_new(arena, (uint32_t)c->f->blocks.len);
  MirBlock *stack = MS_ARENA_NEW_ARRAY(arena, MirBlock, (size_t)c->f->blocks.len + 1);
  uint32_t top = 0;
  stack[top++] = first;
  mir_bits_set(&c->body, first);
  while (top > 0) {
    const MirBlock b = stack[--top];
    const MirTerm *term = &c->f->blocks.ptr[b].term;
    if (term->kind == MT_RET) {
      return false;
    }
    for (uint32_t t = 0; t < mir_term_ntargets(term); t++) {
      const MirBlock to = mir_term_target_const(term, t)->block;
      if (to == r || mir_bits_test(&c->body, to)) {
        continue;
      }
      if (to == 0 || c->preds.start[to + 1] - c->preds.start[to] == 0) {
        return false;
      }
      mir_bits_set(&c->body, to);
      stack[top++] = to;
    }
  }
  /* Nothing outside the body may enter it except through the first block. */
  for (uint32_t b = 0; b < c->f->blocks.len; b++) {
    if (!mir_bits_test(&c->body, b) || b == first) {
      continue;
    }
    for (uint32_t p = 0; p < mir_preds_count(&c->preds, b); p++) {
      if (!mir_bits_test(&c->body, mir_pred(&c->preds, b, p))) {
        return false;
      }
    }
  }
  return true;
}

/* Whether the body reads `list` only as `list.get[..] list, counter` and steps the counter by one on every
 * edge to `r`, with nothing else using the counter. */
static bool reader_uses(const Ctx *c, MirBlock r, MirValue counter, MirValue list) {
  uint32_t gets = 0, incs = 0, edges = 0;
  for (uint32_t b = 0; b < c->f->blocks.len; b++) {
    if (!mir_bits_test(&c->body, b)) {
      continue;
    }
    const MirBlockData *blk = &c->f->blocks.ptr[b];
    for (uint32_t i = 0; i < blk->insts.len; i++) {
      const MirInst *inst = &blk->insts.ptr[i];
      if ((inst->op == MOP_ListGet || inst->op == MOP_ListGetNn || inst->op == MOP_ListGetU) &&
          inst->args[0] == list) {
        if (inst->args[1] != counter) {
          return false;
        }
        gets++;
      } else if (is_op(inst, MOP_IAdd) && inst->args[0] == counter && const_int_is(c, inst->args[1], 1)) {
        incs++;
      }
    }
    const MirTerm *term = &blk->term;
    for (uint32_t t = 0; t < mir_term_ntargets(term); t++) {
      const MirTarget *target = mir_term_target_const(term, t);
      if (target->block != r) {
        continue;
      }
      const MirInst *step = def_inst(c, target->args[0]);
      if (step == NULL || !is_op(step, MOP_IAdd) || step->args[0] != counter || !const_int_is(c, step->args[1], 1)) {
        return false;
      }
      edges++;
    }
  }
  /* The counter feeds the test, the steps and the reads; the list the length, the reads and one drop. */
  if (edges == 0 || c->uses[counter] != 1 + incs + gets) {
    return false;
  }
  return c->uses[list] == 1 + gets + 1;
}

/* ---- the builder ---- */

/* Marks the natural loop of `header`: the blocks it dominates that reach one of its back edges. */
static bool builder_loop(MsArena *arena, Ctx *c, MirBlock header, MirBlock *pre) {
  c->loop = mir_bits_new(arena, (uint32_t)c->f->blocks.len);
  MirBlock *stack = MS_ARENA_NEW_ARRAY(arena, MirBlock, (size_t)c->f->blocks.len + 1);
  uint32_t top = 0;
  uint32_t outside = 0;
  mir_bits_set(&c->loop, header);
  for (uint32_t p = 0; p < mir_preds_count(&c->preds, header); p++) {
    const MirBlock from = mir_pred(&c->preds, header, p);
    if (mir_dominates(c->idom, header, from)) {
      if (!mir_bits_test(&c->loop, from)) {
        mir_bits_set(&c->loop, from);
        stack[top++] = from;
      }
    } else {
      outside++;
      *pre = from;
    }
  }
  if (outside != 1 || top == 0) {
    return false;
  }
  while (top > 0) {
    const MirBlock b = stack[--top];
    for (uint32_t p = 0; p < mir_preds_count(&c->preds, b); p++) {
      const MirBlock from = mir_pred(&c->preds, b, p);
      if (!mir_bits_test(&c->loop, from)) {
        mir_bits_set(&c->loop, from);
        stack[top++] = from;
      }
    }
  }
  return true;
}

/* Finds the push triple `take S; list.push; put S` of slot `s` in the loop and checks that nothing else
 * touches the slot but its one initial put and the final take. */
static bool builder_slot(const Ctx *c, Fusion *fu, MirValue s) {
  uint32_t triples = 0, initial = 0, finals = 0, others = 0;
  for (uint32_t b = 0; b < c->f->blocks.len; b++) {
    const MirBlockData *blk = &c->f->blocks.ptr[b];
    const bool in_loop = mir_bits_test(&c->loop, b);
    for (uint32_t i = 0; i < blk->insts.len; i++) {
      const MirInst *inst = &blk->insts.ptr[i];
      bool touches = false;
      for (uint32_t a = 0; a < inst->nargs; a++) {
        touches = touches || inst->args[a] == s;
      }
      if (!touches) {
        continue;
      }
      if (is_op(inst, MOP_Take) && inst->args[0] == s && in_loop && i + 2 < blk->insts.len &&
                 is_op(&blk->insts.ptr[i + 1], MOP_ListPush) && blk->insts.ptr[i + 1].args[0] == inst->res &&
                 is_op(&blk->insts.ptr[i + 2], MOP_Put) && blk->insts.ptr[i + 2].args[0] == s &&
                 blk->insts.ptr[i + 2].args[1] == blk->insts.ptr[i + 1].res &&
                 c->uses[inst->res] == 1 && c->uses[blk->insts.ptr[i + 1].res] == 1) {
        fu->site = b;
        fu->take_at = i;
        fu->element = blk->insts.ptr[i + 1].args[1];
        triples++;
        i += 2;
      } else if (is_op(inst, MOP_Take) && inst->args[0] == s && b == fu->entry) {
        finals++;
      } else if (is_op(inst, MOP_Put) && inst->args[0] == s && !in_loop) {
        const MirInst *made = def_inst(c, inst->args[1]);
        if (made == NULL || !is_op(made, MOP_ListNew) || c->uses[inst->args[1]] != 1) {
          return false;
        }
        initial++;
      } else {
        others++;
      }
    }
  }
  return triples == 1 && initial == 1 && finals == 1 && others == 0;
}

/* The setup in `entry` must be hoistable above the builder loop: it reads nothing the loop makes. */
static bool setup_hoistable(const Ctx *c, const Fusion *fu) {
  const MirBlockData *e = &c->f->blocks.ptr[fu->entry];
  for (uint32_t i = 0; i < e->insts.len; i++) {
    const MirInst *inst = &e->insts.ptr[i];
    if ((is_op(inst, MOP_Take) && inst->res == fu->list) || inst->res == fu->count) {
      continue;
    }
    if (!movable_setup(inst)) {
      return false;
    }
    for (uint32_t a = 0; a < inst->nargs; a++) {
      const MirValue v = inst->args[a];
      if (v == fu->list || v == fu->count) {
        return false;
      }
      const Def d = c->defs[v];
      if (mir_bits_test(&c->loop, d.block)) {
        return false;
      }
    }
  }
  /* The values leaving for the reader come from outside the loop too. */
  const MirTerm *term = &e->term;
  for (uint32_t k = 1; k < term->a.nargs; k++) {
    if (mir_bits_test(&c->loop, c->defs[term->a.args[k]].block)) {
      return false;
    }
  }
  return true;
}

/* Matches reader header `r`; fills `fu` and the sets in `c`. */
static bool match(MsArena *arena, Ctx *c, MirBlock r, Fusion *fu) {
  const MirFunc *f = c->f;
  const MirBlockData *hr = &f->blocks.ptr[r];
  if (hr->params.len < 1 || hr->params.len > 1 + FUSE_MAX_ACC || hr->insts.len != 1 || hr->term.kind != MT_CONDBR ||
      mir_value_ty(f, hr->params.ptr[0].value) != MIR_INT) {
    return false;
  }
  const MirInst *cmp = &hr->insts.ptr[0];
  const MirValue counter = hr->params.ptr[0].value;
  if (!is_op(cmp, MOP_ICmp) || cmp->imm.a != MCC_LT || cmp->args[0] != counter || hr->term.value != cmp->res ||
      c->uses[cmp->res] != 1 || hr->term.a.nargs != 0) {
    return false;
  }
  const MirInst *len = def_inst(c, cmp->args[1]);
  if (len == NULL || !is_op(len, MOP_ListLen) || c->uses[len->res] != 1) {
    return false;
  }
  fu->reader = r;
  fu->count = len->res;
  fu->list = len->args[0];
  fu->body0 = hr->term.a.block;
  fu->exit = hr->term.b.block;
  const MirTy list_ty = mir_value_ty(f, fu->list);
  const MirTyData *td = mir_ty_data(c->m, list_ty);
  if (td->kind != MK_LIST || !mir_is_scalar(c->m, td->elem)) {
    return false;
  }
  fu->nacc = (uint32_t)hr->params.len - 1;
  for (uint32_t k = 0; k < fu->nacc; k++) {
    fu->acc[k] = hr->params.ptr[k + 1].value;
    fu->acc_ty[k] = mir_value_ty(f, fu->acc[k]);
    if (!mir_is_scalar(c->m, fu->acc_ty[k]) || hr->params.ptr[k + 1].mode == MM_MOVE) {
      return false;
    }
  }
  /* The one edge into R from outside the body. */
  if (c->defs[len->res].index == MIR_NONE) {
    return false;
  }
  fu->entry = c->defs[len->res].block;
  const MirBlockData *e = &f->blocks.ptr[fu->entry];
  if (e->term.kind != MT_BR || e->term.a.block != r || e->term.a.nargs != hr->params.len ||
      !const_int_is(c, e->term.a.args[0], 0)) {
    return false;
  }
  for (uint32_t k = 0; k < fu->nacc; k++) {
    fu->init[k] = e->term.a.args[k + 1];
  }
  if (!reader_body(arena, c, r, fu->body0) || f->blocks.ptr[fu->body0].params.len != 0 ||
      mir_bits_test(&c->body, fu->entry) || !reader_uses(c, r, counter, fu->list)) {
    return false;
  }
  /* The entry block leaves a loop: its only predecessor is the builder's header. */
  if (mir_preds_count(&c->preds, fu->entry) != 1) {
    return false;
  }
  fu->header = mir_pred(&c->preds, fu->entry, 0);
  /* Edges into R from outside the body: only E. */
  for (uint32_t p = 0; p < mir_preds_count(&c->preds, r); p++) {
    const MirBlock from = mir_pred(&c->preds, r, p);
    if (from != fu->entry && !mir_bits_test(&c->body, from)) {
      return false;
    }
  }
  if (!builder_loop(arena, c, fu->header, &fu->pre) || mir_bits_test(&c->loop, fu->entry) ||
      f->blocks.ptr[fu->pre].term.kind != MT_BR) {
    return false;
  }
  /* The list is `take S` in E. */
  const MirInst *take = def_inst(c, fu->list);
  if (take == NULL || !is_op(take, MOP_Take) || c->defs[fu->list].block != fu->entry) {
    return false;
  }
  fu->slot = take->args[0];
  const MirInst *push = def_inst(c, fu->slot);
  if (push == NULL || !is_op(push, MOP_Slot)) {
    return false;
  }
  if (!builder_slot(c, fu, fu->slot) ||
      !mir_bits_test(&c->loop, fu->site) || !setup_hoistable(c, fu)) {
    return false;
  }
  /* The pushed value is defined before the push and the loops are free of effects that order could show. */
  if (!blocks_order_free(c, &c->loop) || !blocks_order_free(c, &c->body)) {
    return false;
  }
  return true;
}

/* ---- the rewrite ---- */

static MirInst make_inst(MirModule *m, MirOp op, const MirValue *args, uint32_t n, MirImm imm, MirValue res,
                         MirLoc loc) {
  return mir_inst(op, imm, res, loc, mir_args_copy(m, args, n), n);
}

static MirImm ty_imm(MirTy ty) {
  MirImm imm = {0};
  imm.tag = MI_TY;
  imm.a = ty;
  return imm;
}

static void use_replace(void *context, MirValue *value) {
  const struct {
    MirValue from, to;
  } *pair = context;
  if (*value == pair->from) {
    *value = pair->to;
  }
}

/* Replaces uses of `from` by `to` in the blocks of `set`. */
static void replace_in(MirFunc *f, const MirBits *set, MirValue from, MirValue to) {
  struct {
    MirValue from, to;
  } pair = {from, to};
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    if (!mir_bits_test(set, b)) {
      continue;
    }
    MirBlockData *blk = &f->blocks.ptr[b];
    for (uint32_t i = 0; i < blk->insts.len; i++) {
      for (uint32_t a = 0; a < blk->insts.ptr[i].nargs; a++) {
        if (blk->insts.ptr[i].args[a] == from) {
          blk->insts.ptr[i].args[a] = to;
        }
      }
    }
    mir_term_each_use(&blk->term, use_replace, &pair);
  }
}

/* Marks every instruction the fusion deletes. */
static void mark_dead(const MirFunc *f, const Ctx *c, const Fusion *fu, bool *const *dead) {
  const MirBlockData *e = &f->blocks.ptr[fu->entry];
  for (uint32_t i = 0; i < e->insts.len; i++) {
    dead[fu->entry][i] = true;
  }
  const MirValue counter = f->blocks.ptr[fu->reader].params.ptr[0].value;
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    const MirBlockData *blk = &f->blocks.ptr[b];
    for (uint32_t i = 0; i < blk->insts.len; i++) {
      const MirInst *inst = &blk->insts.ptr[i];
      const bool made = is_op(inst, MOP_Slot) && inst->res == fu->slot;
      const bool initial = is_op(inst, MOP_Put) && inst->args[0] == fu->slot && !mir_bits_test(&c->loop, b);
      const bool read = mir_bits_test(&c->body, b) &&
                        (((inst->op == MOP_ListGet || inst->op == MOP_ListGetNn || inst->op == MOP_ListGetU) &&
                          inst->args[0] == fu->list) ||
                         (is_op(inst, MOP_IAdd) && inst->args[0] == counter));
      dead[b][i] = dead[b][i] || made || initial || read || (is_op(inst, MOP_Drop) && inst->args[0] == fu->list);
      if (initial) {
        /* The first list, found through its only use. */
        const MirInst *first = def_inst(c, inst->args[1]);
        dead[c->defs[inst->args[1]].block][c->defs[inst->args[1]].index] = first != NULL;
      }
    }
  }
}

static void apply(MirModule *m, MirFunc *f, MsArena *arena, const Ctx *c, const Fusion *fu) {
  const MirLoc loc = f->blocks.ptr[fu->entry].term_loc;

  /* The setup that moves above the builder loop, in order. */
  MirInst *hoisted = MS_ARENA_NEW_ARRAY(arena, MirInst, (size_t)f->blocks.ptr[fu->entry].insts.len + 1);
  uint32_t nhoisted = 0;
  const MirBlockData *e = &f->blocks.ptr[fu->entry];
  for (uint32_t i = 0; i < e->insts.len; i++) {
    const MirInst *inst = &e->insts.ptr[i];
    if ((is_op(inst, MOP_Take) && inst->res == fu->list) || inst->res == fu->count) {
      continue;
    }
    hoisted[nhoisted++] = *inst;
  }

  /* The tail of the push block moves to a new block that the reader's body returns to. */
  const MirBlock cont = mir_new_block(f);
  MirBlockData *site = &f->blocks.ptr[fu->site];
  const uint32_t tail_from = fu->take_at + 3;
  /* Made before the flags so the new block has its own. */
  {
    const uint32_t ntail = (uint32_t)site->insts.len - tail_from;
    MirInst *tail = MS_ARENA_NEW_ARRAY(arena, MirInst, (size_t)ntail + 1);
    for (uint32_t i = 0; i < ntail; i++) {
      tail[i] = site->insts.ptr[tail_from + i];
    }
    opt_block_set_insts(&f->blocks.ptr[cont], tail, ntail);
    f->blocks.ptr[cont].term = site->term;
    f->blocks.ptr[cont].term_loc = site->term_loc;
    f->blocks.ptr[cont].cold = site->cold;
  }
  bool **marks = opt_dead_flags(arena, f);
  mark_dead(f, c, fu, marks);
  for (uint32_t i = fu->take_at; i < site->insts.len; i++) {
    marks[fu->site][i] = true;
  }
  /* Where the builder's element goes. */
  const MirValue element = fu->element;

  /* The reader's element reads become the pushed value. */
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    if (!mir_bits_test(&c->body, b)) {
      continue;
    }
    const MirBlockData *blk = &f->blocks.ptr[b];
    for (uint32_t i = 0; i < blk->insts.len; i++) {
      const MirInst *inst = &blk->insts.ptr[i];
      if ((inst->op == MOP_ListGet || inst->op == MOP_ListGetNn || inst->op == MOP_ListGetU) &&
          inst->args[0] == fu->list) {
        mir_func_replace_uses(f, inst->res, element);
      }
    }
  }

  opt_sweep_dead(f, marks, arena);

  /* The builder block now ends by entering the reader's body. */
  site = &f->blocks.ptr[fu->site];
  opt_term_set_br(&site->term, (MirTarget){fu->body0, NULL, 0});

  /* Accumulator slots: made at entry, filled before the builder loop. */
  MirValue slots[FUSE_MAX_ACC];
  for (uint32_t k = 0; k < fu->nacc; k++) {
    slots[k] = mir_new_value(f, MIR_PTR);
  }
  MirBlockData *pre = &f->blocks.ptr[fu->pre];
  for (uint32_t i = 0; i < nhoisted; i++) {
    mir_block_insert(pre, (uint32_t)pre->insts.len, &hoisted[i]);
  }
  for (uint32_t k = 0; k < fu->nacc; k++) {
    const MirValue args[2] = {slots[k], fu->init[k]};
    const MirInst put = make_inst(m, MOP_Put, args, 2, mir_imm_none(), MIR_NONE, loc);
    mir_block_insert(pre, (uint32_t)pre->insts.len, &put);
  }

  /* The reader's accumulators are read from their slots on entry to the body. */
  MirBlockData *body0 = &f->blocks.ptr[fu->body0];
  for (uint32_t k = fu->nacc; k-- > 0;) {
    const MirValue loaded = mir_new_value(f, fu->acc_ty[k]);
    const MirInst load = make_inst(m, MOP_Load, &slots[k], 1, ty_imm(fu->acc_ty[k]), loaded, loc);
    mir_block_insert(body0, 0, &load);
    replace_in(f, &c->body, fu->acc[k], loaded);
  }

  /* Each edge back to the reader stores the next values and returns to the builder. */
  const uint32_t nblocks = (uint32_t)f->blocks.len;
  for (uint32_t b = 0; b < nblocks; b++) {
    if (!mir_bits_test(&c->body, b)) {
      continue;
    }
    for (uint32_t t = 0; t < mir_term_ntargets(&f->blocks.ptr[b].term); t++) {
      if (mir_term_target(&f->blocks.ptr[b].term, t)->block != fu->reader) {
        continue;
      }
      const MirTarget old = *mir_term_target(&f->blocks.ptr[b].term, t);
      const MirBlock edge = mir_new_block(f);
      for (uint32_t k = 0; k < fu->nacc; k++) {
        const MirValue args[2] = {slots[k], old.args[k + 1]};
        const MirInst put = make_inst(m, MOP_Put, args, 2, mir_imm_none(), MIR_NONE, loc);
        mir_block_insert(&f->blocks.ptr[edge], (uint32_t)f->blocks.ptr[edge].insts.len, &put);
      }
      opt_term_set_br(&f->blocks.ptr[edge].term, (MirTarget){cont, NULL, 0});
      f->blocks.ptr[edge].term_loc = loc;
      MirTarget *target = mir_term_target(&f->blocks.ptr[b].term, t);
      *target = (MirTarget){edge, NULL, 0};
    }
  }

  /* The old entry block now only leaves the loop: it reads the accumulators and goes to the exit. */
  MirBlockData *entry = &f->blocks.ptr[fu->entry];
  MirTarget exit_target = opt_target_clone(m, &f->blocks.ptr[fu->reader].term.b);
  for (uint32_t k = 0; k < fu->nacc; k++) {
    const MirValue loaded = mir_new_value(f, fu->acc_ty[k]);
    const MirInst load = make_inst(m, MOP_Load, &slots[k], 1, ty_imm(fu->acc_ty[k]), loaded, loc);
    mir_block_insert(entry, (uint32_t)entry->insts.len, &load);
    /* The exit block reads the parameters of R directly; everything past the loop sees this load. */
    mir_func_replace_uses(f, fu->acc[k], loaded);
    for (uint32_t a = 0; a < exit_target.nargs; a++) {
      if (exit_target.args[a] == fu->acc[k]) {
        exit_target.args[a] = loaded;
      }
    }
  }
  opt_term_set_br(&entry->term, exit_target);

  /* The slots are made at function entry. */
  for (uint32_t k = 0; k < fu->nacc; k++) {
    const MirInst slot = make_inst(m, MOP_Slot, NULL, 0, ty_imm(fu->acc_ty[k]), slots[k], loc);
    mir_block_insert(&f->blocks.ptr[0], mir_entry_insert_at(f), &slot);
  }
  mir_func_compact_blocks(f);
}

static bool fuse_function(MirModule *m, MirFunc *f) {
  MsArena arena = ms_arena_new();
  Ctx c = {.m = m, .f = f};
  c.defs = MS_ARENA_NEW_ARRAY(&arena, Def, (size_t)f->values.len + 1);
  for (uint32_t v = 0; v < f->values.len; v++) {
    c.defs[v] = (Def){MIR_NONE, MIR_NONE};
  }
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t p = 0; p < f->blocks.ptr[b].params.len; p++) {
      c.defs[f->blocks.ptr[b].params.ptr[p].value] = (Def){b, MIR_NONE};
    }
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      if (f->blocks.ptr[b].insts.ptr[i].res != MIR_NONE) {
        c.defs[f->blocks.ptr[b].insts.ptr[i].res] = (Def){b, i};
      }
    }
  }
  c.uses = mir_use_counts(&arena, f);
  c.preds = mir_preds(&arena, f);
  MirBlock *order = NULL;
  const uint32_t count = mir_rpo(&arena, f, &order);
  c.idom = mir_dominators(&arena, f, order, count, &c.preds);
  bool done = false;
  for (MirBlock r = 1; r < f->blocks.len && !done; r++) {
    Fusion fu = {0};
    if (match(&arena, &c, r, &fu)) {
      apply(m, f, &arena, &c, &fu);
      done = true;
    }
  }
  ms_arena_free(&arena);
  return done;
}

bool opt_fuse(MirModule *m) {
  bool changed = false;
  for (uint32_t fi = 0; fi < m->funcs.len; fi++) {
    changed = fuse_function(m, &m->funcs.ptr[fi]) || changed;
  }
  return changed;
}

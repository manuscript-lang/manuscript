/* The control-flow half of `simplify`: block merging and jump threading, dominator-scoped value
 * numbering. The map-probe rewrites are in opt_simplify_probes.c. */

#include "compiler/opt/opt_simplify.h"

#include "base/sort.h"

/* ---- small helpers ---- */

static bool sb_has_value(const MirValue *v, uint32_t n, MirValue x) {
  for (uint32_t k = 0; k < n; k++) {
    if (v[k] == x) {
      return true;
    }
  }
  return false;
}

/* ---- block merging and jump threading ---- */

/* Merges a block into its unique predecessor when that predecessor falls into it; true when it
 * merged anything. */
static bool sb_merge_blocks(MirFunc *f) {
  MsArena arena = ms_arena_new();
  uint32_t *edges = MS_ARENA_NEW_ARRAY(&arena, uint32_t, f->blocks.len);
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    const MirTerm *t = &f->blocks.ptr[bi].term;
    for (uint32_t s = 0; s < mir_term_ntargets(t); s++) {
      edges[mir_term_target_const(t, s)->block]++;
    }
  }
  OptSubst subst = opt_subst_new(&arena, (uint32_t)f->values.len);
  bool merged = false;
  for (uint32_t p = 0; p < f->blocks.len; p++) {
    /* A consumed block was emptied and ends in `unreachable`, so it is skipped. */
    while (f->blocks.ptr[p].term.kind == MT_BR) {
      const MirTarget t = f->blocks.ptr[p].term.a;
      const uint32_t b = t.block;
      if (b == 0 || b == p || edges[b] != 1) {
        break;
      }
      merged = true;
      MirBlockData bd = f->blocks.ptr[b];
      f->blocks.ptr[b] = mir_block_empty();
      opt_block_append(&f->blocks.ptr[p], bd.insts.ptr, (uint32_t)bd.insts.len);
      mir_inst_list_free(&bd.insts);
      f->blocks.ptr[p].term = bd.term;
      f->blocks.ptr[p].term_loc = bd.term_loc;
      for (uint32_t k = 0; k < bd.params.len && k < t.nargs; k++) {
        opt_subst_set(&subst, bd.params.ptr[k].value, t.args[k]);
      }
    }
  }
  if (merged) {
    opt_subst_apply(f, &subst);
    mir_func_compact_blocks(f);
  }
  ms_arena_free(&arena);
  return merged;
}

/* Redirects the edges into empty block `b`, which only forwards its arguments to `t`. */
static bool sb_thread_block(MirModule *m, MirFunc *f, OptIdList *preds, MsArena *arena, uint32_t b,
              const uint32_t *uses, uint32_t *forward) {
  if (f->blocks.ptr[b].insts.len != 0 || f->blocks.ptr[b].term.kind != MT_BR) {
    return false;
  }
  MirTarget t = f->blocks.ptr[b].term.a;
  if (t.block == b) {
    return false;
  }
  const MirBlockData *blk = &f->blocks.ptr[b];
  /* A bare forward (no parameters, no arguments) goes to where the block it forwards to goes: a chain of them is
   * resolved from its far end, so the edges into the chain move once and not once per link. */
  if (blk->params.len == 0 && t.nargs == 0) {
    uint32_t final = t.block;
    while (forward[final] != MIR_NONE) {
      final = forward[final];
    }
    if (final == b) {
      return false;
    }
    forward[b] = final;
    t.block = final;
  }
  for (uint32_t k = 0; k < blk->params.len; k++) {
    uint32_t in_args = 0;
    for (uint32_t a = 0; a < t.nargs; a++) {
      in_args += t.args[a] == blk->params.ptr[k].value;
    }
    if (uses[blk->params.ptr[k].value] != in_args) {
      return false;
    }
  }
  bool did = false;
  const OptIdList taken = preds[b];
  preds[b] = (OptIdList){0};
  for (uint32_t k = 0; k < taken.n; k++) {
    const uint32_t pb = taken.v[k];
    if (pb == b) {
      opt_id_push(arena, &preds[b], pb);
      continue;
    }
    MirTerm *term = &f->blocks.ptr[pb].term;
    for (uint32_t s = 0; s < mir_term_ntargets(term); s++) {
      MirTarget *e = mir_term_target(term, s);
      if (e->block != b) {
        continue;
      }
      MirValue *args = MS_ARENA_NEW_ARRAY(&m->arena, MirValue, t.nargs + 1);
      for (uint32_t a = 0; a < t.nargs; a++) {
        uint32_t pos = 0;
        while (pos < blk->params.len && blk->params.ptr[pos].value != t.args[a]) {
          pos++;
        }
        args[a] = pos < blk->params.len ? e->args[pos] : t.args[a];
      }
      e->block = t.block;
      e->args = args;
      e->nargs = t.nargs;
      did = true;
    }
    /* A repeated entry only revisits a block whose edges already moved. */
    opt_id_push(arena, &preds[t.block], pb);
  }
  return did;
}

/* Threads edges through empty blocks that only forward their arguments. */
static bool sb_thread_edges(MirModule *m, MirFunc *f) {
  MsArena arena = ms_arena_new();
  uint32_t *uses = mir_use_counts(&arena, f);
  /* The blocks whose terminator targets each block, kept current as edges move. */
  OptIdList *preds = MS_ARENA_NEW_ARRAY(&arena, OptIdList, f->blocks.len);
  for (uint32_t pb = 0; pb < f->blocks.len; pb++) {
    const MirTerm *t = &f->blocks.ptr[pb].term;
    for (uint32_t s = 0; s < mir_term_ntargets(t); s++) {
      OptIdList *l = &preds[mir_term_target_const(t, s)->block];
      if (l->n == 0 || l->v[l->n - 1] != pb) {
        opt_id_push(&arena, l, pb);
      }
    }
  }
  uint32_t *forward = MS_ARENA_NEW_ARRAY(&arena, uint32_t, (size_t)f->blocks.len + 1);
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    forward[b] = MIR_NONE;
  }
  bool changed = false;
  for (uint32_t b = (uint32_t)f->blocks.len; b-- > 1;) { /* the far end of a chain of forwards first */
    changed |= sb_thread_block(m, f, preds, &arena, b, uses, forward);
  }
  ms_arena_free(&arena);
  return changed;
}

/* Jump threading through a flag join: an empty block whose only parameter is a `Bool` that its
 * terminator branches on (the join of `a and b` or `a or b` used as a condition). An edge that
 * passes a constant goes straight to the target that constant selects. Values the targets read
 * dominate the join, hence its predecessors. */
static bool sb_thread_flag_branches(MirModule *m, MirFunc *f) {
  MsArena arena = ms_arena_new();
  uint8_t *flag = MS_ARENA_NEW_ARRAY(&arena, uint8_t, f->values.len); /* 0 unknown, 1 false, 2 true */
  bool any = false;
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    for (uint32_t ii = 0; ii < f->blocks.ptr[bi].insts.len; ii++) {
      const MirInst *i = &f->blocks.ptr[bi].insts.ptr[ii];
      if (i->op == MOP_BConst && i->imm.tag == MI_BOOL && i->res != MIR_NONE) {
        flag[i->res] = i->imm.a != 0 ? 2 : 1;
        any = true;
      }
    }
  }
  uint32_t *uses = any ? mir_use_counts(&arena, f) : NULL;
  /* The blocks whose terminator targets each block, so a join finds its edges without reading every block. */
  OptIdList *preds = MS_ARENA_NEW_ARRAY(&arena, OptIdList, (size_t)f->blocks.len + 1);
  for (uint32_t pb = 0; any && pb < f->blocks.len; pb++) {
    const MirTerm *t = &f->blocks.ptr[pb].term;
    for (uint32_t s = 0; s < mir_term_ntargets(t); s++) {
      OptIdList *l = &preds[mir_term_target_const(t, s)->block];
      if (l->n == 0 || l->v[l->n - 1] != pb) {
        opt_id_push(&arena, l, pb);
      }
    }
  }
  bool changed = false;
  for (uint32_t j = 1; any && j < f->blocks.len; j++) {
    const MirBlockData *blk = &f->blocks.ptr[j];
    if (blk->params.len != 1 || blk->term.kind != MT_CONDBR) {
      continue;
    }
    const MirBlockParam param = blk->params.ptr[0];
    const MirTarget then = blk->term.a, els = blk->term.b;
    /* The flag must feed only this branch: a bypassing edge no longer defines it. */
    if (blk->insts.len != 0 || blk->term.value != param.value || param.mode != MM_BORROW ||
      uses[param.value] != 1) {
      continue;
    }
    if (then.block == j || els.block == j || sb_has_value(then.args, then.nargs, param.value) ||
      sb_has_value(els.args, els.nargs, param.value)) {
      continue;
    }
    const uint32_t entering = preds[j].n; /* what an edge moved to `j` meanwhile adds is not revisited */
    for (uint32_t k = 0; k < entering; k++) {
      const uint32_t pb = preds[j].v[k];
      MirTerm *term = &f->blocks.ptr[pb].term;
      for (uint32_t s = 0; pb != j && s < mir_term_ntargets(term); s++) {
        MirTarget *e = mir_term_target(term, s);
        if (e->block != j || e->nargs == 0 || flag[e->args[0]] == 0) {
          continue;
        }
        const MirTarget *to = flag[e->args[0]] == 2 ? &then : &els;
        *e = opt_target_clone(m, to);
        opt_id_push(&arena, &preds[to->block], pb); /* the edge now enters the target */
        changed = true;
      }
    }
  }
  ms_arena_free(&arena);
  return changed;
}

bool opt_simplify_branches(MirModule *m, MirFunc *f) {
  bool changed = false;
  const uint32_t before = (uint32_t)f->blocks.len;
  mir_func_compact_blocks(f);
  changed |= f->blocks.len != before;
  while (sb_merge_blocks(f)) {
    changed = true;
  }
  changed |= sb_thread_edges(m, f);
  changed |= sb_thread_flag_branches(m, f);
  const uint32_t after_threading = (uint32_t)f->blocks.len;
  mir_func_compact_blocks(f);
  return changed || f->blocks.len != after_threading;
}

/* ---- value numbering ---- */

/* An expression table for value numbering over a dominator tree: entries are added on entering a
 * block and dropped, newest first, on leaving it. */
typedef struct SbEntry {
  uint64_t hash;
  uint8_t op;
  MirImm imm;
  MirTy ty;
  uint32_t arg_start, nargs;
  MirValue value;
  uint32_t next; /* the previous entry of the bucket plus one */
} SbEntry;

typedef struct SbTable {
  uint32_t *heads;
  uint32_t mask;
  SbEntry *entries;
  uint32_t nentries;
  MirValue *operands;
  uint32_t noperands;
} SbTable;

static uint64_t sb_mix(uint64_t h, uint64_t x) {
  h ^= x + UINT64_C(0x9E3779B97F4A7C15) + (h << 6) + (h >> 2);
  return h * UINT64_C(0xFF51AFD7ED558CCD);
}

static uint64_t sb_hash(uint8_t op, const MirImm *imm, MirTy ty, const MirValue *args,
            uint32_t nargs) {
  uint64_t h = sb_mix(op, ty);
  h = sb_mix(h, imm->tag);
  h = sb_mix(h, ((uint64_t)imm->a << 32) | imm->b);
  h = sb_mix(h, ((uint64_t)imm->c << 32) | (uint64_t)imm->tag);
  h = sb_mix(h, (uint64_t)imm->i);
  for (uint32_t k = 0; k < nargs; k++) {
    h = sb_mix(h, args[k]);
  }
  return h ^ (h >> 29);
}

static SbTable sb_table_new(MsArena *arena, uint32_t expected, uint32_t operands) {
  uint32_t size = 16;
  while (size < expected * 2) {
    size *= 2;
  }
  SbTable t = {0};
  t.heads = MS_ARENA_NEW_ARRAY(arena, uint32_t, size);
  t.mask = size - 1;
  t.entries = MS_ARENA_NEW_ARRAY_UNINIT(arena, SbEntry, (size_t)expected + 1);
  t.operands = MS_ARENA_NEW_ARRAY_UNINIT(arena, MirValue, (size_t)operands + 1);
  return t;
}

static bool sb_table_get(const SbTable *t, uint8_t op, const MirImm *imm, MirTy ty,
            const MirValue *args, uint32_t nargs, MirValue *out) {
  const uint64_t hash = sb_hash(op, imm, ty, args, nargs);
  for (uint32_t at = t->heads[hash & t->mask]; at != 0;) {
    const SbEntry *e = &t->entries[at - 1];
    if (e->hash == hash && e->op == op && e->ty == ty && opt_imm_eq(&e->imm, imm) &&
      e->nargs == nargs &&
      (nargs == 0 || __builtin_memcmp(&t->operands[e->arg_start], args, sizeof(MirValue) * nargs) == 0)) {
      *out = e->value;
      return true;
    }
    at = e->next;
  }
  return false;
}

static void sb_table_insert(SbTable *t, uint8_t op, const MirImm *imm, MirTy ty,
              const MirValue *args, uint32_t nargs, MirValue value) {
  const uint64_t hash = sb_hash(op, imm, ty, args, nargs);
  const uint32_t bucket = (uint32_t)(hash & t->mask);
  SbEntry *e = &t->entries[t->nentries++];
  *e = (SbEntry){hash, op, *imm, ty, t->noperands, nargs, value, t->heads[bucket]};
  if (nargs > 0) {
    __builtin_memcpy(&t->operands[t->noperands], args, sizeof(MirValue) * nargs);
  }
  t->noperands += nargs;
  t->heads[bucket] = t->nentries;
}

/* Drops every entry added since `mark`. */
static void sb_table_reset(SbTable *t, uint32_t mark) {
  while (t->nentries > mark) {
    const SbEntry *e = &t->entries[--t->nentries];
    t->heads[e->hash & t->mask] = e->next;
    t->noperands = e->arg_start;
  }
}

typedef struct SbCse {
  MirModule *m;
  MirFunc *f;
  SbTable table;
  OptSubst subst;
  bool **dead;
  MirValue *scratch; /* resolved operands of one instruction */
  bool any;
} SbCse;

static int64_t sb_cmp_value(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  const MirValue x = *(const MirValue *)(const void *)a, y = *(const MirValue *)(const void *)b;
  if (x == y) {
    return 0;
  }
  return x < y ? -1 : 1;
}

/* Whether instruction `inst` takes part in value numbering. */
static bool sb_numbered(const MirModule *m, const MirInst *inst, MirTy ty) {
  const bool checked = inst->op == MOP_IAddChk || inst->op == MOP_ISubChk ||
            inst->op == MOP_IMulChk || inst->op == MOP_INegChk ||
            inst->op == MOP_SDivChk || inst->op == MOP_SRemChk;
  /* A field read is a borrowed view of an immutable type value, so repeating it yields the
   * same view even when the field's type owns heap data. */
  const bool view = inst->op == MOP_TypeGet;
  const MirOpInfo *info = &mir_op_info[inst->op];
  const bool numberable = info->effects == 0 && info->has_result && inst->op != MOP_Slot &&
              inst->op != MOP_Clone;
  if (!(numberable || inst->op == MOP_AltTag || checked || view)) {
    return false;
  }
  return !mir_needs_drop(m, ty) || view;
}

static void sb_number_block(SbCse *c, uint32_t b) {
  const MirBlockData *blk = &c->f->blocks.ptr[b];
  for (uint32_t ii = 0; ii < blk->insts.len; ii++) {
    const MirInst *inst = &blk->insts.ptr[ii];
    if (inst->res == MIR_NONE) {
      continue;
    }
    const MirTy ty = c->f->values.ptr[inst->res];
    if (!sb_numbered(c->m, inst, ty)) {
      continue;
    }
    for (uint32_t k = 0; k < inst->nargs; k++) {
      c->scratch[k] = opt_subst_resolve(&c->subst, inst->args[k]);
    }
    if (opt_op_commutative(inst->op, &inst->imm) && inst->nargs > 1) {
      ms_sort((uint8_t *)c->scratch, inst->nargs, sizeof(MirValue), sb_cmp_value, NULL);
    }
    MirValue prev = 0;
    if (sb_table_get(&c->table, inst->op, &inst->imm, ty, c->scratch, inst->nargs, &prev)) {
      opt_subst_set(&c->subst, inst->res, prev);
      c->dead[b][ii] = true;
      c->any = true;
    } else {
      sb_table_insert(&c->table, inst->op, &inst->imm, ty, c->scratch, inst->nargs, inst->res);
    }
  }
}

/* The instruction and operand counts of `f` and the most operands one instruction has. */
static void sb_measure(const MirFunc *f, uint32_t *insts, uint32_t *operands, uint32_t *widest) {
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    *insts += (uint32_t)f->blocks.ptr[b].insts.len;
    for (uint32_t ii = 0; ii < f->blocks.ptr[b].insts.len; ii++) {
      const uint32_t nargs = f->blocks.ptr[b].insts.ptr[ii].nargs;
      *operands += nargs;
      *widest = nargs > *widest ? nargs : *widest;
    }
  }
}

bool opt_simplify_cse(MirModule *m, MirFunc *f) {
  MsArena arena = ms_arena_new();
  MirBlock *order = NULL;
  const uint32_t count = mir_rpo(&arena, f, &order);
  const MirPreds preds = mir_preds(&arena, f);
  const MirBlock *idom = mir_dominators(&arena, f, order, count, &preds);
  /* The dominator tree: block b's children are `child[cstart[b]..cstart[b + 1]]`, in
   * reverse post-order. */
  uint32_t *cstart = MS_ARENA_NEW_ARRAY(&arena, uint32_t, (size_t)f->blocks.len + 2);
  for (uint32_t k = 0; k < count; k++) {
    const uint32_t i = order[k];
    if (i != 0 && idom[i] != MIR_NONE) {
      cstart[idom[i] + 1]++;
    }
  }
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    cstart[b + 1] += cstart[b];
  }
  uint32_t *fill = MS_ARENA_NEW_ARRAY(&arena, uint32_t, (size_t)f->blocks.len + 1);
  __builtin_memcpy(fill, cstart, sizeof(uint32_t) * f->blocks.len);
  uint32_t *child = MS_ARENA_NEW_ARRAY(&arena, uint32_t, (size_t)cstart[f->blocks.len] + 1);
  for (uint32_t k = 0; k < count; k++) {
    const uint32_t i = order[k];
    if (i != 0 && idom[i] != MIR_NONE) {
      child[fill[idom[i]]++] = i;
    }
  }
  uint32_t insts = 0, operands = 0, widest = 1;
  sb_measure(f, &insts, &operands, &widest);
  SbCse c = {.m = m, .f = f};
  c.table = sb_table_new(&arena, insts, operands);
  c.subst = opt_subst_new(&arena, (uint32_t)f->values.len);
  c.dead = opt_dead_flags(&arena, f);
  c.scratch = MS_ARENA_NEW_ARRAY(&arena, MirValue, widest);
  /* An explicit walk of the dominator tree: an entry is a block to enter, or (high bit set) the
   * table mark to return to on leaving one. */
  const uint64_t exit_bit = UINT64_C(1) << 63;
  uint64_t *stack = MS_ARENA_NEW_ARRAY(&arena, uint64_t, 2 * (size_t)f->blocks.len + 2);
  uint32_t nstack = 0;
  stack[nstack++] = 0;
  while (nstack > 0) {
    const uint64_t s = stack[--nstack];
    if ((s & exit_bit) != 0) {
      sb_table_reset(&c.table, (uint32_t)s);
      continue;
    }
    const uint32_t b = (uint32_t)s;
    stack[nstack++] = exit_bit | c.table.nentries;
    sb_number_block(&c, b);
    for (uint32_t k = cstart[b + 1]; k-- > cstart[b];) {
      stack[nstack++] = child[k];
    }
  }
  if (c.any) {
    opt_sweep_dead(f, (bool *const *)c.dead, &arena);
    opt_subst_apply(f, &c.subst);
  }
  ms_arena_free(&arena);
  return c.any;
}

/* The `loopslot` pass: keeps a loop-carried owned value in one stack slot.
 *
 * A runtime mutator works on a value in memory, so a loop that threads an owned buffer through a
 * block parameter moves it into a slot, calls, and moves it back on every pass:
 *
 *     b1(%p: move T):  ..  s = slot T;  put s, %p;  call.rt f(s, ..);  t = take T s;  br b1(t)
 *
 * When every use of the parameter is such a `put` into a slot of its own block, the value can live
 * in one slot made at function entry: the entry edges put into it, the calls use it directly, and
 * the parameter, the per-pass `put` and the `take` go away. */

#include "compiler/mir/mir_analysis.h"
#include "compiler/opt/opt_pass.h"
#include "base/safe.h"

/* One `put`/`take` pair in a block: positions of the `slot`, the `put` and the optional `take`. */
typedef struct SlotPair {
  MirBlock block;
  uint32_t slot, put, take; /* take is MIR_NONE without one */
} SlotPair;

/* Where each value is put into a slot: a list per value, in block and instruction order. */
typedef struct SlotPuts {
  uint32_t *head; /* per value: the first put, MIR_NONE without */
  uint32_t *next; /* per put: the next put of the same value */
  MirBlock *block;
  uint32_t *index;
} SlotPuts;

static SlotPuts collect_puts(MsArena *arena, const MirFunc *f) {
  const uint32_t total = mir_inst_count(f);
  SlotPuts p = {MS_ARENA_NEW_ARRAY(arena, uint32_t, f->values.len + 1), MS_ARENA_NEW_ARRAY(arena, uint32_t, total + 1),
         MS_ARENA_NEW_ARRAY(arena, MirBlock, total + 1), MS_ARENA_NEW_ARRAY(arena, uint32_t, total + 1)};
  for (uint32_t v = 0; v < f->values.len; v++) {
    p.head[v] = MIR_NONE;
  }
  uint32_t count = 0;
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      if (f->blocks.ptr[b].insts.ptr[i].op == MOP_Put) {
        p.block[count] = b;
        p.index[count] = i;
        count++;
      }
    }
  }
  /* Link from the last put back so each list reads in block and instruction order. */
  for (uint32_t k = count; k-- > 0;) {
    const MirValue v = f->blocks.ptr[p.block[k]].insts.ptr[p.index[k]].args[1];
    p.next[k] = p.head[v];
    p.head[v] = k;
  }
  return p;
}

static bool imm_is_ty(const MirImm *imm, MirTy ty) {
  return imm->tag == MI_TY && imm->a == ty;
}

/* Whether the put at `pi` and its slot, call uses and optional take form a pair that loop `l`
 * parameter `k` can carry; fills `pair`. */
static bool plan_pair(const MirFunc *f, MirBlock l, uint32_t k, uint32_t pi, MirBlock bi,
           const uint32_t *uses, SlotPair *pair) {
  const MirBlockData *blk = &f->blocks.ptr[bi];
  const MirInst *put = &blk->insts.ptr[pi];
  const MirTy ty = mir_value_ty(f, f->blocks.ptr[l].params.ptr[k].value);
  const MirValue s = put->args[0];
  uint32_t slot = MIR_NONE, take = MIR_NONE, calls = 0;
  for (uint32_t i = 0; i < pi && slot == MIR_NONE; i++) {
    if (blk->insts.ptr[i].op == MOP_Slot && blk->insts.ptr[i].res == s) {
      slot = i;
    }
  }
  if (slot == MIR_NONE || !imm_is_ty(&blk->insts.ptr[slot].imm, ty)) {
    return false;
  }
  for (uint32_t i = pi + 1; i < blk->insts.len; i++) {
    const MirInst *inst = &blk->insts.ptr[i];
    if (take == MIR_NONE && inst->op == MOP_Take && inst->nargs > 0 && inst->args[0] == s) {
      take = i;
    }
    if (inst->op == MOP_CallRt) {
      for (uint32_t a = 0; a < inst->nargs; a++) {
        calls += inst->args[a] == s ? 1u : 0u;
      }
    }
  }
  /* The slot is only put into, called on and taken from, inside this block. */
  if (uses[s] != 1 + (take != MIR_NONE ? 1u : 0u) + calls) {
    return false;
  }
  if (take != MIR_NONE) {
    const MirValue t = blk->insts.ptr[take].res;
    for (uint32_t i = pi + 1; i < take; i++) {
      if (blk->insts.ptr[i].op != MOP_CallRt) {
        return false;
      }
    }
    if (t == MIR_NONE || blk->term.kind != MT_BR || !imm_is_ty(&blk->insts.ptr[take].imm, ty) ||
      uses[t] != 1 || blk->term.a.block != l || blk->term.a.args[k] != t) {
      return false;
    }
  }
  *pair = (SlotPair){bi, slot, pi, take};
  return true;
}

static bool pair_carries_back(const SlotPair *pairs, uint32_t n, MirBlock b) {
  for (uint32_t i = 0; i < n; i++) {
    if (pairs[i].block == b && pairs[i].take != MIR_NONE) {
      return true;
    }
  }
  return false;
}

/* An edge into `l` that does not carry the value back is an entry edge; it must be a plain `br`. */
static bool entry_edges_plain(const MirFunc *f, MirBlock l, const SlotPair *pairs, uint32_t n) {
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    const MirTerm *term = &f->blocks.ptr[b].term;
    const bool back = pair_carries_back(pairs, n, b);
    for (uint32_t t = 0; t < mir_term_ntargets(term); t++) {
      if (mir_term_target_const(term, t)->block == l && !back && term->kind != MT_BR) {
        return false;
      }
    }
  }
  return true;
}

/* The pairs that use parameter `k` of `l`, when the parameter qualifies; returns their number. */
static uint32_t plan_param(MsArena *arena, const MirFunc *f, MirBlock l, uint32_t k,
             const uint32_t *uses, const SlotPuts *puts, SlotPair **out) {
  const MirValue p = f->blocks.ptr[l].params.ptr[k].value;
  if (puts->head[p] == MIR_NONE) {
    return 0;
  }
  SlotPair *pairs = MS_ARENA_NEW_ARRAY(arena, SlotPair, (size_t)mir_inst_count(f) + 1);
  uint32_t n = 0;
  for (uint32_t e = puts->head[p]; e != MIR_NONE; e = puts->next[e]) {
    if (!plan_pair(f, l, k, puts->index[e], puts->block[e], uses, &pairs[n])) {
      return 0;
    }
    n++;
  }
  /* Every use of the parameter is one of the puts, and the loop really carries it. */
  bool carried = false;
  for (uint32_t i = 0; i < n; i++) {
    carried = carried || pairs[i].take != MIR_NONE;
  }
  if (uses[p] != n || !carried || !entry_edges_plain(f, l, pairs, n)) {
    return 0;
  }
  *out = pairs;
  return n;
}

static void rewrite_pair(MirFunc *f, const SlotPair *pair, MirValue s) {
  MirBlockData *blk = &f->blocks.ptr[pair->block];
  const MirValue old = blk->insts.ptr[pair->slot].res;
  for (uint32_t i = 0; i < blk->insts.len; i++) {
    for (uint32_t k = 0; k < blk->insts.ptr[i].nargs; k++) {
      if (blk->insts.ptr[i].args[k] == old) {
        blk->insts.ptr[i].args[k] = s;
      }
    }
  }
  const uint32_t dead[3] = {pair->slot, pair->put, pair->take}; /* ascending */
  const uint32_t ndead = pair->take == MIR_NONE ? 2 : 3;
  mir_block_remove(blk, dead, ndead);
}

static void apply_carry(MirModule *m, MirFunc *f, MirBlock l, uint32_t k, const SlotPair *pairs,
            uint32_t n) {
  const MirImm slot_imm = f->blocks.ptr[pairs[0].block].insts.ptr[pairs[0].slot].imm;
  const MirValue s = mir_new_value(f, MIR_PTR);
  const MirLoc loc = f->blocks.ptr[l].term_loc;
  /* Entry edges put into the shared slot; back edges are the pairs' own blocks. */
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    const bool back = pair_carries_back(pairs, n, b);
    MirValue arg = MIR_NONE;
    MirTerm *term = &f->blocks.ptr[b].term;
    for (uint32_t t = 0; t < mir_term_ntargets(term); t++) {
      MirTarget *target = mir_term_target(term, t);
      if (target->block != l) {
        continue;
      }
      const MirValue a = target->args[k];
      mir_target_remove_arg(target, k);
      arg = back ? arg : a;
    }
    if (arg != MIR_NONE) {
      MirInst put = {0};
      put.op = MOP_Put;
      put.res = MIR_NONE;
      put.loc = loc;
      put.args = MS_ARENA_NEW_ARRAY(&m->arena, MirValue, 2);
      put.args[0] = s;
      put.args[1] = arg;
      put.nargs = 2;
      mir_block_insert(&f->blocks.ptr[b], (uint32_t)f->blocks.ptr[b].insts.len, &put);
    }
  }
  for (uint32_t i = 0; i < n; i++) {
    rewrite_pair(f, &pairs[i], s);
  }
  MirBlockData *header = &f->blocks.ptr[l];
  __builtin_memmove(&header->params.ptr[k], &header->params.ptr[k + 1],
      sizeof(MirBlockParam) * (header->params.len - k - 1));
  header->params.len--;
  MirInst slot = {0};
  slot.op = MOP_Slot;
  slot.imm = slot_imm;
  slot.res = s;
  slot.loc = loc;
  mir_block_insert(&f->blocks.ptr[0], mir_entry_insert_at(f), &slot);
}

/* Carries one parameter in a slot; false when none qualifies. */
static bool carry_one(MirModule *m, MirFunc *f) {
  MsArena arena = ms_arena_new();
  const uint32_t *uses = mir_use_counts(&arena, f);
  const SlotPuts puts = collect_puts(&arena, f);
  bool done = false;
  for (MirBlock l = 1; l < f->blocks.len && !done; l++) {
    for (uint32_t k = 0; k < f->blocks.ptr[l].params.len && !done; k++) {
      SlotPair *pairs = NULL;
      if (f->blocks.ptr[l].params.ptr[k].mode != MM_MOVE) {
        continue;
      }
      const uint32_t n = plan_param(&arena, f, l, k, uses, &puts, &pairs);
      if (n > 0) {
        apply_carry(m, f, l, k, pairs, n);
        done = true;
      }
    }
  }
  ms_arena_free(&arena);
  return done;
}

bool opt_loopslot(MirModule *m) {
  bool changed = false;
  for (uint32_t fi = 0; fi < m->funcs.len; fi++) {
    while (carry_one(m, &m->funcs.ptr[fi])) {
      changed = true;
    }
  }
  return changed;
}

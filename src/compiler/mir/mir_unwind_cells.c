/* The unwind pass's view of stack slots: which values hand a slot off, and where cells and covered takes are
 * (see mir_unwind.h). */
#include "compiler/mir/mir_unwind.h"

/* ---- hands_off ---- */

/* Whether a call hands the slot at argument `k` to a callee that owns it while it runs: the
 * callee covers what it takes, so the caller's cover pauses for the call. */
bool uw_hands_off(const UwCx *cx, const MirInst *inst, uint32_t k) {
  uint32_t g = 0;
  if (uw_is_func(inst, MOP_Call, &g)) {
    return uw_flag(&cx->owns, g, k);
  }
  if (inst->op != MOP_CallInd || k == 0) {
    return false;
  }
  bool any = false;
  for (uint32_t t = 0; t < cx->ntargets; t++) {
    const uint32_t h = cx->targets[t];
    if (cx->safe.len[h] != inst->nargs || !uw_flag(&cx->pointer, h, k)) {
      continue;
    }
    if (!uw_flag(&cx->owns, h, k)) {
      return false;
    }
    any = true;
  }
  return any;
}

/* Whether every closure that takes `arity` parameters and a pointer at position `k` only borrows
 * what that pointer's slot holds. False when there is no such closure. */
static bool uw_closures_borrow(const UwCx *cx, uint32_t arity, uint32_t k) {
  bool any = false, unsafe = false;
  for (uint32_t t = 0; t < cx->ntargets; t++) {
    const uint32_t g = cx->targets[t];
    if (cx->safe.len[g] != arity) {
      continue;
    }
    any = any || uw_flag(&cx->safe, g, k);
    /* A candidate whose parameter at `k` is a pointer that it may consume makes the call unsafe. */
    unsafe = unsafe || (!uw_flag(&cx->safe, g, k) && uw_flag(&cx->pointer, g, k));
  }
  return any && !unsafe;
}

/* ---- find_cells ---- */

typedef struct UwCells {
  UwCx *cx;
  const MirFunc *f;
  MsArena *a;
  const UwHash *params;
  UwHash slots, bad, captured, guarded;
} UwCells;

static bool uw_fresh_def_op(MirOp op) {
  return op == MOP_ListLit || op == MOP_ListFill || op == MOP_TypeNew || op == MOP_AltNew ||
     op == MOP_IfaceNew || op == MOP_Clone || op == MOP_Call || op == MOP_TypeFill;
}

static bool uw_hands_a_call(MirOp op) {
  return op == MOP_Call || op == MOP_CallInd || op == MOP_CallMethod || op == MOP_CallRt ||
     op == MOP_Poll;
}

/* The slots a closure captures by reference or that stay within a block (see the Rust comment). */
static void uw_cells_captured(UwCells *c) {
  const MirFunc *f = c->f;
  UwHash handed = {0}, fresh = {0}, stale = {0};
  UW_INSTS(f, b, i, inst) {
    for (uint32_t k = 0; k < inst->nargs && uw_hands_a_call(inst->op); k++) {
      (void)uh_put(c->a, &handed, inst->args[k], 0);
    }
    if (inst->res != MIR_NONE && uw_fresh_def_op(inst->op)) {
      (void)uh_put(c->a, &fresh, inst->res, 0);
    }
  }
  UW_INSTS(f, b2, i2, inst2) {
    if (inst2->op == MOP_Put && inst2->nargs > 1 && !uh_has(&fresh, inst2->args[1])) {
      (void)uh_put(c->a, &stale, inst2->args[0], 0);
    }
    uint32_t scoped = 0;
    const bool owns = !(uw_is_func(inst2, MOP_ClosureNew, &scoped) && c->cx->m->funcs.ptr[scoped].scoped);
    for (uint32_t k = 0; k < inst2->nargs && inst2->op == MOP_ClosureNew && owns; k++) { /* a scoped closure only reads */
      (void)uh_put(c->a, &c->captured, inst2->args[k], 0);
    }
  }
  /* A slot parameter that is only refilled with fresh values; one refilled with the very value
   * taken out of it stays within a block. */
  for (uint32_t i = 0; i < c->params->cap; i++) {
    if (c->params->used[i] && !uh_has(&stale, c->params->key[i])) {
      (void)uh_put(c->a, &c->captured, c->params->key[i], 0);
    }
  }
  for (uint32_t i = 0; i < c->slots.cap; i++) {
    const uint64_t s = c->slots.key[i];
    if (c->slots.used[i] && !uh_has(&handed, s) && !uh_has(&stale, s)) {
      (void)uh_put(c->a, &c->captured, s, 0);
    }
  }
}

/* The values that only feed the condition of a `drop.if`. */
static void uw_cells_guarded(UwCells *c) {
  UwHash other = {0}, cond = {0};
  const MirFunc *f = c->f;
  UW_INSTS(f, b, i, inst) {
    for (uint32_t k = 0; k < inst->nargs; k++) {
      if (inst->op == MOP_DropIf && k == 1) {
        (void)uh_put(c->a, &cond, inst->args[k], 0);
      } else {
        (void)uh_put(c->a, &other, inst->args[k], 0);
      }
    }
  }
  for (uint32_t i = 0; i < cond.cap; i++) {
    if (cond.used[i] && !uh_has(&other, cond.key[i])) {
      (void)uh_put(c->a, &c->guarded, cond.key[i], 0);
    }
  }
}

/* Whether use `k` of slot `a` by `inst` keeps the slot a cell; `full` holds the slots that hold a
 * value now. */
static bool uw_cell_use_ok(UwCells *c, UwHash *full, const MirInst *inst, uint32_t k, MirTy ty) {
  const MirValue a = inst->args[k];
  const UwCx *cx = c->cx;
  uint32_t g = 0;
  switch ((MirOp)inst->op) {
  case MOP_Put:
    if (k == 0) {
      return uh_put(c->a, full, a, 0) && mir_value_ty(c->f, inst->args[1]) == ty;
    }
    return false;
  case MOP_Take:
    /* A take whose result only feeds `drop.if` runs after a move emptied the slot. */
    return uh_del(full, a) || (inst->res != MIR_NONE && uh_has(&c->guarded, inst->res));
  case MOP_Load:
    return uh_has(full, a);
  case MOP_Call:
  case MOP_CallInd:
    if (uw_hands_off(cx, inst, k)) {
      return uh_has(full, a);
    }
    if (inst->op == MOP_Call && uw_is_func(inst, MOP_Call, &g)) {
      return uh_has(full, a) && uw_flag(&cx->safe, g, k);
    }
    /* The callee is some closure of this arity; the slot stays covered when every one that
     * could receive it at this position only borrows it. */
    return inst->op == MOP_CallInd && k > 0 && uh_has(full, a) &&
       uw_closures_borrow(cx, inst->nargs, k);
  case MOP_ClosureNew:
    return uw_is_func(inst, MOP_ClosureNew, &g) && uh_has(full, a) &&
       uw_closure_borrows_capture(cx->m, &cx->safe, cx->parks, g, k);
  default:
    return false;
  }
}

static void uw_cells_insts(UwCells *c, const MirBlockData *blk, UwHash *full) {
  for (uint32_t n = 0; n < blk->insts.len; n++) {
    const MirInst *inst = &blk->insts.ptr[n];
    for (uint32_t k = 0; k < inst->nargs; k++) {
      uint64_t ty = 0;
      if (uh_get(&c->slots, inst->args[k], &ty) &&
        !uw_cell_use_ok(c, full, inst, k, (MirTy)ty)) {
        (void)uh_put(c->a, &c->bad, inst->args[k], 0);
      }
    }
  }
}

/* Marks slots that disagree across an edge, leak out of the block, or are returned. */
static void uw_cells_edges(UwCells *c, const MirBlockData *blk, UwHash *full, UwHash *entry,
             bool *have) {
  for (uint32_t i = 0; i < full->cap; i++) {
    if (full->used[i] && !uh_has(&c->captured, full->key[i])) {
      (void)uh_put(c->a, &c->bad, full->key[i], 0);
    }
  }
  const uint32_t ntargets = mir_term_ntargets(&blk->term);
  for (uint32_t k = 0; k < ntargets; k++) {
    const MirTarget *t = mir_term_target_const(&blk->term, k);
    for (uint32_t j = 0; j < t->nargs; j++) {
      if (uh_has(&c->slots, t->args[j])) {
        (void)uh_put(c->a, &c->bad, t->args[j], 0);
      }
    }
    if (!have[t->block]) {
      entry[t->block] = uh_clone(c->a, full);
      have[t->block] = true;
      continue;
    }
    const UwHash *seen = &entry[t->block];
    for (uint32_t i = 0; i < seen->cap; i++) {
      if (seen->used[i] && !uh_has(full, seen->key[i])) {
        (void)uh_put(c->a, &c->bad, seen->key[i], 0);
      }
    }
    for (uint32_t i = 0; i < full->cap; i++) {
      if (full->used[i] && !uh_has(seen, full->key[i])) {
        (void)uh_put(c->a, &c->bad, full->key[i], 0);
      }
    }
  }
  if (ntargets == 0) {
    /* A `put` left unmatched when the function ends is not followed; a slot parameter goes
     * back to the caller holding its value. */
    for (uint32_t i = 0; i < full->cap; i++) {
      if (full->used[i] && !uh_has(c->params, full->key[i])) {
        (void)uh_put(c->a, &c->bad, full->key[i], 0);
      }
    }
  }
  if (blk->term.kind == MT_RET && blk->term.value != MIR_NONE) {
    (void)uh_put(c->a, &c->bad, blk->term.value, 0);
  }
}

/* The slots of `f` that hold an owned value across calls, each with the type it holds, in
 * `cx->cells`. A slot qualifies when every use is a `put` into it, a `take` out of it, a `load`,
 * or a call whose callee only borrows what it takes from the slot, and each such use sits between
 * a `put` and its `take`. */
void uw_find_cells(UwCx *cx, const MirFunc *f, const UwHash *params) {
  MsArena tmp = {0};
  UwCells c = {.cx = cx, .f = f, .a = &tmp, .params = params};
  c.slots = uh_clone(&tmp, params);
  UW_INSTS(f, b, i, inst) {
    if (inst->op == MOP_Slot && inst->imm.tag == MI_TY && inst->res != MIR_NONE &&
      mir_needs_drop(cx->m, inst->imm.a)) {
      (void)uh_put(&tmp, &c.slots, inst->res, inst->imm.a);
    }
  }
  if (c.slots.n > 0) {
    uw_cells_captured(&c);
    uw_cells_guarded(&c);
    UwHash *entry = MS_ARENA_NEW_ARRAY(&tmp, UwHash, f->blocks.len);
    bool *have = MS_ARENA_NEW_ARRAY(&tmp, bool, f->blocks.len);
    __builtin_memset(entry, 0, sizeof(UwHash) * f->blocks.len);
    __builtin_memset(have, 0, f->blocks.len);
    entry[0] = uh_clone(&tmp, params);
    have[0] = true;
    MirBlock *order = NULL;
    const uint32_t norder = mir_rpo(&tmp, f, &order);
    for (uint32_t oi = 0; oi < norder; oi++) {
      if (!have[order[oi]]) {
        continue;
      }
      UwHash full = uh_clone(&tmp, &entry[order[oi]]);
      uw_cells_insts(&c, &f->blocks.ptr[order[oi]], &full);
      uw_cells_edges(&c, &f->blocks.ptr[order[oi]], &full, entry, have);
    }
  }
  cx->cells = (UwHash){0};
  for (uint32_t i = 0; i < c.slots.cap; i++) {
    if (c.slots.used[i] && !uh_has(&c.bad, c.slots.key[i])) {
      (void)uh_put(&cx->fn, &cx->cells, c.slots.key[i], c.slots.val[i]);
    }
  }
  ms_arena_free(&tmp);
}

/* ---- covered_slot_takes ---- */

/* Whether every use of `taken` borrows it or puts it back into `slot`. */
static bool uw_only_borrowed_until_put(const MirModule *m, MsArena *a, const MirFunc *f,
                   MirValue taken, MirValue slot) {
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    const MirBlockData *blk = &f->blocks.ptr[b];
    for (uint32_t n = 0; n < blk->insts.len; n++) {
      const MirInst *inst = &blk->insts.ptr[n];
      MirMode *modes = MS_ARENA_NEW_ARRAY(a, MirMode, inst->nargs ? inst->nargs : 1);
      mir_arg_modes(m, f, inst, modes);
      for (uint32_t i = 0; i < inst->nargs; i++) {
        if (inst->args[i] != taken) {
          continue;
        }
        const bool putback = inst->op == MOP_Put && i == 1 && inst->args[0] == slot;
        const bool moves_out = inst->op == MOP_MoveOut || inst->op == MOP_Store ||
                   inst->op == MOP_Put || inst->op == MOP_CleanupPush ||
                   inst->op == MOP_TypeFill || inst->op == MOP_ListFill ||
                   inst->op == MOP_CallInd;
        if (!putback && !(modes[i] == MM_BORROW && !moves_out)) {
          return false;
        }
      }
    }
    if (blk->term.kind == MT_RET && blk->term.value == taken) {
      return false;
    }
    for (uint32_t k = 0; k < mir_term_ntargets(&blk->term); k++) {
      const MirTarget *t = mir_term_target_const(&blk->term, k);
      for (uint32_t j = 0; j < t->nargs; j++) {
        if (t->args[j] == taken) {
          return false;
        }
      }
    }
  }
  return true;
}

typedef struct UwCovered {
  const MirModule *m;
  MsArena *a;
  UwHash handle; /* cleanup handle -> slot */
} UwCovered;

static bool uw_slot_push(const UwCovered *c, const MirInst *inst, MirValue *slot) {
  MirTy ty = 0;
  uint32_t g = 0;
  if (!uw_is_func(inst, MOP_CleanupPush, &g) || !uw_slot_close_value(c->m, g, &ty) ||
    inst->nargs == 0) {
    return false;
  }
  *slot = inst->args[0];
  return true;
}

static void uw_covered_step(UwCovered *c, UwHash *covered, const MirInst *inst) {
  MirValue slot = 0;
  uint64_t via = 0;
  if (inst->op == MOP_CleanupRun) {
    *covered = (UwHash){0};
  } else if (inst->op == MOP_CallRt && inst->imm.tag == MI_EXT && inst->nargs == 1) {
    const MirRole role = c->m->externs.ptr[inst->imm.a].role;
    if ((role == MR_CLEANUP_DISCARD || role == MR_CLEANUP_CANCEL) &&
      uh_get(&c->handle, inst->args[0], &via)) {
      (void)uh_del(covered, via);
    }
  } else if (uw_slot_push(c, inst, &slot)) {
    (void)uh_put(c->a, covered, slot, 0);
  }
}

/* Slots covered on entry to each block: covered on every path that reaches it. */
static void uw_covered_flow(UwCovered *c, const MirFunc *f, const MirBlock *order, uint32_t norder,
              UwHash *entry, bool *have) {
  have[0] = true;
  for (bool changed = true; changed;) {
    changed = false;
    for (uint32_t oi = 0; oi < norder; oi++) {
      const MirBlockData *blk = &f->blocks.ptr[order[oi]];
      if (!have[order[oi]]) {
        continue;
      }
      UwHash covered = uh_clone(c->a, &entry[order[oi]]);
      for (uint32_t n = 0; n < blk->insts.len; n++) {
        uw_covered_step(c, &covered, &blk->insts.ptr[n]);
      }
      for (uint32_t k = 0; k < mir_term_ntargets(&blk->term); k++) {
        const MirBlock t = mir_term_target_const(&blk->term, k)->block;
        UwHash next = {0};
        for (uint32_t i = 0; i < covered.cap; i++) {
          if (covered.used[i] && (!have[t] || uh_has(&entry[t], covered.key[i]))) {
            (void)uh_put(c->a, &next, covered.key[i], 0);
          }
        }
        if (!have[t] || !uh_equal_sets(&entry[t], &next)) {
          changed = true;
          have[t] = true;
          entry[t] = next;
        }
      }
    }
  }
}

/* The results of `take`s from a local slot whose scope close is registered and not yet
 * discarded, when the value is only borrowed until it is put back (when `borrowed_only`). The
 * close drops what the slot holds, and the slot still holds the same value while the call runs. */
UwHash uw_covered_slot_takes(MsArena *a, const MirModule *m, const MirFunc *f, bool borrowed_only) {
  UwHash out = {0};
  UwCovered c = {.m = m, .a = a};
  bool any = false;
  UW_INSTS(f, b, i, inst) {
    MirValue slot = 0;
    if (uw_slot_push(&c, inst, &slot)) {
      any = true;
      if (inst->res != MIR_NONE) {
        (void)uh_put(a, &c.handle, inst->res, slot);
      }
    }
  }
  if (!any) {
    return out;
  }
  UwHash *entry = MS_ARENA_NEW_ARRAY(a, UwHash, f->blocks.len);
  bool *have = MS_ARENA_NEW_ARRAY(a, bool, f->blocks.len);
  __builtin_memset(entry, 0, sizeof(UwHash) * f->blocks.len);
  __builtin_memset(have, 0, f->blocks.len);
  MirBlock *order = NULL;
  const uint32_t norder = mir_rpo(a, f, &order);
  uw_covered_flow(&c, f, order, norder, entry, have);
  for (uint32_t oi = 0; oi < norder; oi++) {
    if (!have[order[oi]]) {
      continue;
    }
    UwHash covered = uh_clone(a, &entry[order[oi]]);
    const MirBlockData *blk = &f->blocks.ptr[order[oi]];
    for (uint32_t n = 0; n < blk->insts.len; n++) {
      const MirInst *inst = &blk->insts.ptr[n];
      if (inst->op == MOP_Take && inst->nargs > 0 && inst->res != MIR_NONE &&
        uh_has(&covered, inst->args[0]) &&
        (!borrowed_only || uw_only_borrowed_until_put(m, a, f, inst->res, inst->args[0]))) {
        (void)uh_put(a, &out, inst->res, 0);
      }
      uw_covered_step(&c, &covered, inst);
    }
  }
  return out;
}

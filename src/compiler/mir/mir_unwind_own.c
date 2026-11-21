/* unwind: which values of a function it owns, and so must be registered. Port of the start of
 * `function` in unwind.rs. */
#include "compiler/mir/mir_unwind.h"

typedef struct UwOwn {
  bool *def; /* owned_def, by value */
  uint32_t n;
} UwOwn;

typedef struct UwDefs {
  UwCx *cx;
  MirFunc *f;
  UwOwn *own;
  UwHash slot_params, owned_params, from_slot, caller_slots, caller_values, caller_projections;
} UwDefs;

void uw_own_resize(UwCx *cx, bool **def, uint32_t *n, uint32_t nvalues) {
  if (nvalues <= *n) {
    return;
  }
  bool *grown = MS_ARENA_NEW_ARRAY(&cx->fn, bool, nvalues);
  __builtin_memset(grown, 0, nvalues);
  if (*n > 0) {
    __builtin_memcpy(grown, *def, *n);
  }
  *def = grown;
  *n = nvalues;
}

/* The slot pointers the function does not own (parameters and by-reference captures) and the
 * parameters no caller covers. */
static void uw_slot_params(UwDefs *d, uint32_t fi) {
  const MirFunc *f = d->f;
  MsArena *a = &d->cx->fn;
  for (uint32_t k = 0; k < f->blocks.ptr[0].params.len; k++) {
    (void)uh_put(a, &d->slot_params, f->blocks.ptr[0].params.ptr[k].value, 0);
    if (uw_flag(&d->cx->owns, fi, k)) {
      (void)uh_put(a, &d->owned_params, f->blocks.ptr[0].params.ptr[k].value, 0);
    }
  }
  /* A slot pointer a closure captured by reference is the enclosing function's slot, as a
   * parameter is the caller's: a cancellation inside the closure must not drop what it took. */
  UW_INSTS(f, b, i, inst) {
    if (inst->op == MOP_ClosureCap && inst->res != MIR_NONE &&
      mir_value_ty(f, inst->res) == MIR_PTR) {
      (void)uh_put(a, &d->slot_params, inst->res, 0);
    }
  }
}

static bool uw_from_caller_param(const UwDefs *d, const MirInst *inst) {
  return inst->op == MOP_Take && inst->nargs > 0 && uh_has(&d->slot_params, inst->args[0]) &&
     !uh_has(&d->owned_params, inst->args[0]);
}

static void uw_defs_initial(UwDefs *d, const UwHash *covered_takes) {
  const MirFunc *f = d->f;
  UwCx *cx = d->cx;
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    const MirBlockData *blk = &f->blocks.ptr[bi];
    for (uint32_t i = 0; i < blk->params.len; i++) {
      const MirValue v = blk->params.ptr[i].value;
      d->own->def[v] = mir_needs_drop(cx->m, mir_value_ty(f, v)) && blk->params.ptr[i].mode == MM_MOVE;
    }
    for (uint32_t n = 0; n < blk->insts.len; n++) {
      const MirInst *inst = &blk->insts.ptr[n];
      /* A value taken out of a slot the caller passed in stays the caller's: the slot still
       * holds it while the call runs, and the caller (or its owner) drops it. */
      const bool from_caller = uw_from_caller_param(d, inst) ||
                  (inst->op == MOP_Take && inst->res != MIR_NONE &&
                   uh_has(covered_takes, inst->res));
      MirMode mode = MM_BORROW;
      if (inst->res != MIR_NONE && mir_result_mode(cx->m, f, inst, &mode) && mode == MM_MOVE) {
        d->own->def[inst->res] = !from_caller;
        if (from_caller) {
          (void)uh_put(&cx->fn, &d->from_slot, inst->res, 0);
        }
      }
    }
  }
}

/* Marks `r` as the caller's: it is not owned here. Whether it was new. */
static bool uw_caller_value(UwDefs *d, MirValue r) {
  MsArena *a = &d->cx->fn;
  if (uh_put(a, &d->caller_values, r, 0) && uh_put(a, &d->from_slot, r, 0)) {
    d->own->def[r] = false;
    return true;
  }
  return false;
}

static bool uw_defs_edges(UwDefs *d, const MirBlockData *blk) {
  bool moved = false;
  for (uint32_t k = 0; k < mir_term_ntargets(&blk->term); k++) {
    const MirTarget *t = mir_term_target_const(&blk->term, k);
    const MirBlockData *dest = &d->f->blocks.ptr[t->block];
    for (uint32_t j = 0; j < t->nargs && j < dest->params.len; j++) {
      if (uh_has(&d->from_slot, t->args[j]) &&
        uh_put(&d->cx->fn, &d->from_slot, dest->params.ptr[j].value, 0)) {
        d->own->def[dest->params.ptr[j].value] = false;
        moved = true;
      }
    }
  }
  return moved;
}

static bool uw_defs_inst(UwDefs *d, const MirInst *inst) {
  MsArena *a = &d->cx->fn;
  const MirValue a0 = uw_arg(inst, 0), r = inst->res;
  switch ((MirOp)inst->op) {
  case MOP_Put:
    return inst->nargs > 1 && uh_has(&d->caller_values, inst->args[1]) &&
       !uh_has(&d->slot_params, a0) && uh_put(a, &d->caller_slots, a0, 0);
  case MOP_Take:
    return r != MIR_NONE && uh_has(&d->caller_slots, a0) && uw_caller_value(d, r);
  case MOP_TypeGet:
  case MOP_AltGet:
    /* A field of a caller's value, and that field moved out: the caller still covers the value
     * it came from. */
    return r != MIR_NONE && uh_has(&d->caller_values, a0) &&
       uh_put(a, &d->caller_projections, r, 0);
  case MOP_MoveOut:
    return r != MIR_NONE && uh_has(&d->caller_projections, a0) && uw_caller_value(d, r);
  case MOP_TypeFill:
  case MOP_ListFill:
    /* Refilling a field moved out of a caller's value yields that same value again. */
    return r != MIR_NONE && uh_has(&d->from_slot, a0) && uw_caller_value(d, r);
  default:
    return false;
  }
}

/* A block parameter that receives such a value stays the caller's too, and so does a value taken
 * back out of a local slot that only parks it for a borrower (`caller_slots`). */
static void uw_defs_propagate(UwDefs *d) {
  const MirFunc *f = d->f;
  UW_INSTS(f, b, i, inst) {
    if (uw_from_caller_param(d, inst) && inst->res != MIR_NONE) {
      (void)uh_put(&d->cx->fn, &d->caller_values, inst->res, 0);
    }
  }
  for (bool moved = true; moved;) {
    moved = false;
    for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
      moved = uw_defs_edges(d, &f->blocks.ptr[bi]) || moved;
      for (uint32_t n = 0; n < f->blocks.ptr[bi].insts.len; n++) {
        moved = uw_defs_inst(d, &f->blocks.ptr[bi].insts.ptr[n]) || moved;
      }
    }
  }
}

/* What an owned slot parameter holds, read from how the function takes, fills or loads it. */
static UwHash uw_param_cells(UwDefs *d) {
  const MirFunc *f = d->f;
  UwHash cells = {0};
  UW_INSTS(f, b, i, inst) {
    if (inst->nargs == 0) {
      continue;
    }
    MirTy ty = 0;
    if ((inst->op == MOP_Take || inst->op == MOP_Load) && inst->imm.tag == MI_TY) {
      ty = inst->imm.a;
    } else if (inst->op == MOP_Put && inst->nargs > 1) {
      ty = mir_value_ty(f, inst->args[1]);
    } else {
      continue;
    }
    if (uh_has(&d->owned_params, inst->args[0]) && mir_needs_drop(d->cx->m, ty) &&
      !uh_has(&cells, inst->args[0])) {
      (void)uh_put(&d->cx->fn, &cells, inst->args[0], ty);
    }
  }
  return cells;
}

/* Computes the owned values of `f` (`*def`, `*n`) and the cells in `cx->cells`; false when
 * nothing can be live across a call. */
bool uw_owned_values(UwCx *cx, MirFunc *f, uint32_t fi, bool **def, uint32_t *n) {
  UwOwn own = {.def = NULL, .n = 0};
  uw_own_resize(cx, &own.def, &own.n, f->values.len);
  UwDefs d = {.cx = cx, .f = f, .own = &own};
  uw_slot_params(&d, fi);
  const UwHash covered_takes = uw_covered_slot_takes(&cx->fn, cx->m, f, true);
  uw_defs_initial(&d, &covered_takes);
  uw_defs_propagate(&d);
  const UwHash param_cells = uw_param_cells(&d);
  uw_find_cells(cx, f, &param_cells);
  UwHash kept = {0};
  for (uint32_t i = 0; i < cx->cells.cap; i++) {
    if (cx->cells.used[i] && !uh_has(&d.caller_slots, cx->cells.key[i])) {
      (void)uh_put(&cx->fn, &kept, cx->cells.key[i], cx->cells.val[i]);
    }
  }
  cx->cells = kept;
  *def = own.def;
  *n = own.n;
  for (uint32_t i = 0; i < own.n; i++) {
    if (own.def[i]) {
      return true;
    }
  }
  return cx->cells.n > 0;
}

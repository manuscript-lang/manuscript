/* The `fieldview` pass: a `var` record parameter is edited where the caller keeps it.
 *
 * A function that updates a `var` record takes it out of the parameter pointer, threads the value through block
 * parameters and `type.set`, lends it to callees through a slot, and puts it back before each exit:
 *
 *     %1 = take T %0;  %2 = type.set T.f %1, %n;  s = slot T;  put s, %2;  call g(s);  %3 = take T s;  put %0, %3
 *
 * Every value of the record is a cell of its own in the frame. When every use of the values is a field read, a
 * scalar field write, an edge argument, a lend through a private slot or the final `put`, the record can stay in
 * `%0`: a read loads the field there, a write stores it there, a lend passes `%0`, and the `take`, the `put`s, the
 * slots and the block parameters go away. The caller's record is valid at every instruction, and is the same record
 * the chain would have put back. */

#include "compiler/mir/mir_analysis.h"
#include "compiler/mir/mir_layout.h"
#include "compiler/opt/opt_pass.h"
#include "base/safe.h"

/* A slot that lends the record to calls: where it is made, put into, and taken from. */
typedef struct Lend {
  MirBlock block;
  uint32_t slot, put, take;
} Lend;

/* A field of the record lent to calls the same way: `g = type.get T.f V;  m = move.out g;  s = slot F;  put s, m;
 * call h(s);  t = take F s;  r = type.set T.f W, t`. The callee gets the field's address in the record. */
typedef struct FieldLend {
  MirBlock block;
  uint32_t get, move, slot, put, take, set;
} FieldLend;

/* A scalar edit of a field that is itself a record: `g = type.get T.f V;  c = clone g;  c1 = type.set F.s c, x;  ...;
 * m = move.out g;  drop m;  r = type.set T.f W, cn`. The scalars are stored where the field lies, and the clone, the
 * move and the drop go. */
typedef struct NestedEdit {
  MirBlock block;
  uint32_t get, outer;
  uint32_t nsets, sets[8];
} NestedEdit;

/* A field replaced as a whole: `g = type.get T.f V;  m = move.out g;  drop m;  r = type.set T.f W, x`, nothing between
 * them. The old value is dropped and `x` stored where the field lies, with no fault point in between. */
typedef struct Replace {
  MirBlock block;
  uint32_t get, outer;
} Replace;

typedef struct View {
  MirModule *m;
  MirLayouts *layouts;
  MirFunc *f;
  MsArena *arena;
  MirValue param; /* the `var` pointer */
  MirTy record;   /* the record's type */
  uint32_t def;   /* the record's type definition */
  bool *view;     /* by value: holds the record `param` points to */
  bool *lent;     /* by value: a slot of a lend */
  Lend *lends;
  uint32_t nlends;
  bool *candidate; /* by value: a block parameter that may carry the record */
  FieldLend *flends;
  uint32_t nflends;
  bool *fslot; /* by value: the slot of a field lend */
  bool *fdead; /* by value: the result of a get, move.out or take that a field lend removes */
  Replace *reps;
  uint32_t nreps;
  uint32_t *rset; /* by value: 1 + the replacement the type.set producing it ends, or 0 */
  bool *rmove;    /* by value: the result of the move.out a replacement keeps */
  NestedEdit *nedits;
  uint32_t nnedits;
  uint32_t *nsub;   /* by value: 1 + the nested edit the type.set producing it is a step of, or 0 */
  uint32_t *nouter; /* by value: 1 + the nested edit the type.set producing it ends, or 0 */
  bool *ndead;      /* by value: the result of a clone or move.out a nested edit removes */
  uint32_t *fset; /* by value: 1 + the field lend that the type.set producing it ends, or 0 */
} View;

static bool is_view(const View *v, MirValue x) {
  return x != MIR_NONE && v->view[x];
}

/* The lend made on slot value `s`, or NULL. */
static const Lend *lend_of(const View *v, MirValue s) {
  for (uint32_t i = 0; i < v->nlends; i++) {
    if (v->f->blocks.ptr[v->lends[i].block].insts.ptr[v->lends[i].slot].res == s && v->lent[s]) {
      return &v->lends[i];
    }
  }
  return NULL;
}

/* How the slot made at instruction `si` of `blk` is used: put into once, handed to calls, taken from once, nothing else. */
static bool slot_shape(const MirBlockData *blk, uint32_t si, const uint32_t *uses, uint32_t *put_out, uint32_t *take_out) {
  const MirValue slot = blk->insts.ptr[si].res;
  uint32_t put = MIR_NONE, take = MIR_NONE, calls = 0;
  for (uint32_t i = si + 1; i < blk->insts.len; i++) {
    const MirInst *inst = &blk->insts.ptr[i];
    bool names = false;
    for (uint32_t a = 0; a < inst->nargs; a++) {
      names = names || inst->args[a] == slot;
    }
    if (!names) {
      continue;
    }
    if (inst->op == MOP_Put && inst->args[0] == slot && put == MIR_NONE && take == MIR_NONE) {
      put = i;
    } else if (inst->op == MOP_Take && inst->args[0] == slot && put != MIR_NONE && take == MIR_NONE) {
      take = i;
    } else if (mir_op_is_call(inst->op) && put != MIR_NONE && take == MIR_NONE) {
      for (uint32_t a = 0; a < inst->nargs; a++) {
        calls += inst->args[a] == slot ? 1u : 0u;
      }
    } else {
      return false;
    }
  }
  *put_out = put;
  *take_out = take;
  return put != MIR_NONE && take != MIR_NONE && uses[slot] == 2 + calls;
}

/* The index in `blk` of the instruction with result `r`, or MIR_NONE. */
static uint32_t def_in(const MirBlockData *blk, MirValue r) {
  for (uint32_t i = 0; i < blk->insts.len; i++) {
    if (blk->insts.ptr[i].res == r) {
      return i;
    }
  }
  return MIR_NONE;
}

static bool field_aligned(const View *v, uint32_t field);
static bool scalar_field(const View *v, uint32_t field);

/* The field lend a slot makes, when the slot's `put` takes a field moved out of the record and its `take` goes
 * straight back into the same field. */
static bool field_lend_of(const View *v, MirBlock bi, uint32_t si, uint32_t put, uint32_t take, const uint32_t *uses,
                          FieldLend *out) {
  const MirBlockData *blk = &v->f->blocks.ptr[bi];
  const MirInst *slot = &blk->insts.ptr[si];
  const uint32_t move = def_in(blk, blk->insts.ptr[put].args[1]);
  const uint32_t get = move == MIR_NONE ? MIR_NONE : def_in(blk, blk->insts.ptr[move].args[0]);
  if (get == MIR_NONE || blk->insts.ptr[move].op != MOP_MoveOut || blk->insts.ptr[get].op != MOP_TypeGet || get > put) {
    return false;
  }
  const MirInst *g = &blk->insts.ptr[get];
  if (g->imm.tag != MI_FIELD || g->imm.a != v->def || uses[g->res] != 1 || uses[blk->insts.ptr[move].res] != 1 ||
      slot->imm.a != mir_value_ty(v->f, g->res) || !field_aligned(v, g->imm.b)) {
    return false;
  }
  const MirValue taken = blk->insts.ptr[take].res;
  for (uint32_t i = take + 1; i < blk->insts.len && taken != MIR_NONE && uses[taken] == 1; i++) {
    const MirInst *set = &blk->insts.ptr[i];
    if (set->op == MOP_TypeSet && set->imm.tag == MI_FIELD && set->imm.a == v->def && set->imm.b == g->imm.b &&
        set->nargs == 2 && set->args[1] == taken) {
      *out = (FieldLend){bi, get, move, si, put, take, i};
      return true;
    }
  }
  return false;
}

/* A nested edit that ends at instruction `oi` of block `bi`, found by walking its chain back to the clone. */
static bool nested_edit_at(const View *v, MirBlock bi, uint32_t oi, const uint32_t *uses, NestedEdit *out) {
  const MirBlockData *blk = &v->f->blocks.ptr[bi];
  const MirInst *outer = &blk->insts.ptr[oi];
  if (outer->op != MOP_TypeSet || outer->imm.tag != MI_FIELD || outer->imm.a != v->def || outer->nargs != 2 ||
      scalar_field(v, outer->imm.b) || !field_aligned(v, outer->imm.b)) {
    return false;
  }
  const MirTy fty = v->m->type_defs.ptr[v->def].fields[outer->imm.b].ty;
  const MirTyData *fdata = mir_ty_data(v->m, fty);
  if (fdata->kind != MK_TYPE || v->m->type_defs.ptr[fdata->id].indirect || v->m->type_defs.ptr[fdata->id].native) {
    return false;
  }
  NestedEdit edit = {.block = bi, .outer = oi};
  MirValue at = outer->args[1];
  uint32_t clone = MIR_NONE;
  for (uint32_t depth = 0; depth < 8 && clone == MIR_NONE; depth++) {
    const uint32_t di = def_in(blk, at);
    if (di == MIR_NONE || uses[at] != 1 || di >= oi) {
      return false;
    }
    const MirInst *d = &blk->insts.ptr[di];
    if (d->op == MOP_Clone) {
      clone = di;
    } else if (d->op == MOP_TypeSet && d->imm.tag == MI_FIELD && d->imm.a == fdata->id && d->nargs == 2 &&
               mir_is_scalar(v->m, v->m->type_defs.ptr[fdata->id].fields[d->imm.b].ty)) {
      edit.sets[edit.nsets++] = di;
      at = d->args[0];
    } else {
      return false;
    }
  }
  if (clone == MIR_NONE || edit.nsets == 0) {
    return false;
  }
  const MirValue g = blk->insts.ptr[clone].args[0];
  const uint32_t get = def_in(blk, g);
  if (get == MIR_NONE || blk->insts.ptr[get].op != MOP_TypeGet || blk->insts.ptr[get].imm.tag != MI_FIELD ||
      blk->insts.ptr[get].imm.a != v->def || blk->insts.ptr[get].imm.b != outer->imm.b) {
    return false;
  }
  /* The old field is moved out of the record and dropped right after the clone. */
  bool moved = false;
  for (uint32_t i = clone + 1; i < oi && !moved; i++) {
    const MirInst *m = &blk->insts.ptr[i];
    if (m->op == MOP_MoveOut && m->args[0] == g && uses[m->res] == 1 && i + 1 < blk->insts.len &&
        blk->insts.ptr[i + 1].op == MOP_Drop && blk->insts.ptr[i + 1].args[0] == m->res) {
      moved = true;
    }
  }
  edit.get = get;
  *out = edit;
  return moved;
}

/* Finds the slots of block `bi` that lend the record, or one of its fields, to calls. */
static void find_lends(View *v, MirBlock bi, const uint32_t *uses) {
  const MirBlockData *blk = &v->f->blocks.ptr[bi];
  for (uint32_t si = 0; si < blk->insts.len; si++) {
    const MirInst *slot = &blk->insts.ptr[si];
    uint32_t put = MIR_NONE, take = MIR_NONE;
    if (slot->op != MOP_Slot || slot->imm.tag != MI_TY || slot->res == MIR_NONE ||
        !slot_shape(blk, si, uses, &put, &take)) {
      continue;
    }
    FieldLend fl;
    if (slot->imm.a == v->record) {
      v->lends[v->nlends++] = (Lend){bi, si, put, take};
    } else if (field_lend_of(v, bi, si, put, take, uses, &fl)) {
      v->flends[v->nflends++] = fl;
    }
  }
  for (uint32_t gi = 0; gi + 3 < blk->insts.len; gi++) {
    const MirInst *get = &blk->insts.ptr[gi], *mv = &blk->insts.ptr[gi + 1], *dr = &blk->insts.ptr[gi + 2],
                  *set = &blk->insts.ptr[gi + 3];
    if (get->op == MOP_TypeGet && get->imm.tag == MI_FIELD && get->imm.a == v->def && mv->op == MOP_MoveOut &&
        mv->args[0] == get->res && dr->op == MOP_Drop && dr->args[0] == mv->res && set->op == MOP_TypeSet &&
        set->imm.tag == MI_FIELD && set->imm.a == v->def && set->imm.b == get->imm.b && set->nargs == 2 &&
        uses[get->res] == 1 && uses[mv->res] == 1 && !scalar_field(v, get->imm.b) && field_aligned(v, get->imm.b)) {
      v->reps[v->nreps++] = (Replace){bi, gi, gi + 3};
    }
  }
  for (uint32_t oi = 0; oi < blk->insts.len; oi++) {
    NestedEdit edit;
    if (nested_edit_at(v, bi, oi, uses, &edit)) {
      v->nedits[v->nnedits++] = edit;
    }
  }
}

/* Whether field `field` of the record is a scalar. */
static bool scalar_field(const View *v, uint32_t field) {
  return mir_is_scalar(v->m, v->m->type_defs.ptr[v->def].fields[field].ty);
}

/* One round of propagation: the values that hold the record, given the block parameters still candidates. Returns
 * whether a value became one. */
static bool propagate(View *v) {
  bool grew = false;
  for (uint32_t b = 0; b < v->f->blocks.len; b++) {
    const MirBlockData *blk = &v->f->blocks.ptr[b];
    for (uint32_t i = 0; i < blk->insts.len; i++) {
      const MirInst *inst = &blk->insts.ptr[i];
      if (inst->res == MIR_NONE || v->view[inst->res]) {
        continue;
      }
      bool now = false;
      if (inst->op == MOP_TypeSet && inst->imm.tag == MI_FIELD && inst->imm.a == v->def && is_view(v, inst->args[0]) &&
          scalar_field(v, inst->imm.b)) {
        now = true;
      } else if (v->rset[inst->res] != 0) {
        const Replace *rp = &v->reps[v->rset[inst->res] - 1];
        now = is_view(v, inst->args[0]) && is_view(v, blk->insts.ptr[rp->get].args[0]);
      } else if (v->nouter[inst->res] != 0) {
        const NestedEdit *ne = &v->nedits[v->nouter[inst->res] - 1];
        now = is_view(v, inst->args[0]) && is_view(v, blk->insts.ptr[ne->get].args[0]);
      } else if (v->fset[inst->res] != 0) {
        const FieldLend *fl = &v->flends[v->fset[inst->res] - 1];
        now = is_view(v, inst->args[0]) && is_view(v, blk->insts.ptr[fl->get].args[0]);
      } else if (inst->op == MOP_Take && inst->nargs == 1 && v->lent[inst->args[0]]) {
        const Lend *lend = lend_of(v, inst->args[0]);
        const MirInst *put = &blk->insts.ptr[lend->put];
        now = lend->block == b && lend->take == i && is_view(v, put->args[1]);
      }
      if (now) {
        v->view[inst->res] = true;
        grew = true;
      }
    }
  }
  return grew;
}

/* Whether every edge into parameter `k` of block `b` carries a view. */
static bool edges_carry_views(const View *v, MirBlock b, uint32_t k) {
  for (uint32_t pb = 0; pb < v->f->blocks.len; pb++) {
    const MirTerm *term = &v->f->blocks.ptr[pb].term;
    for (uint32_t t = 0; t < mir_term_ntargets(term); t++) {
      const MirTarget *target = mir_term_target_const(term, t);
      if (target->block == b && !is_view(v, target->args[k])) {
        return false;
      }
    }
  }
  return true;
}

/* Settles which values hold the record: the parameter's `take`, field writes, takes from lends, and the block
 * parameters whose every incoming edge carries one. */
static void settle(View *v, MirValue first) {
  for (bool again = true; again;) {
    __builtin_memset(v->view, 0, sizeof(bool) * (v->f->values.len + 1));
    v->view[first] = true;
    for (MirBlock b = 0; b < v->f->blocks.len; b++) {
      for (uint32_t k = 0; k < v->f->blocks.ptr[b].params.len; k++) {
        const MirValue p = v->f->blocks.ptr[b].params.ptr[k].value;
        v->view[p] = v->candidate[p];
      }
    }
    while (propagate(v)) {
    }
    again = false;
    for (MirBlock b = 1; b < v->f->blocks.len; b++) {
      for (uint32_t k = 0; k < v->f->blocks.ptr[b].params.len; k++) {
        const MirValue p = v->f->blocks.ptr[b].params.ptr[k].value;
        if (v->candidate[p] && !edges_carry_views(v, b, k)) {
          v->candidate[p] = false;
          again = true;
        }
      }
    }
  }
}

/* Whether a read of field `field` at its offset in the record equals a read of the field alone. The record lays its
 * leaves out in one run, so a field of several leaves that starts off its own alignment (after a bool) has its leaves
 * at other offsets than the field's own cell, and a whole-field load would read the wrong bytes. */
static bool field_aligned(const View *v, uint32_t field) {
  const MirTy ty = v->m->type_defs.ptr[v->def].fields[field].ty;
  if (mir_leaves(v->layouts, ty).len <= 1) {
    return true;
  }
  return mir_field_offset(v->layouts, v->def, field) % mir_type_mem(v->layouts, ty).align == 0;
}

/* A call that only borrows the record, and whose result does not point into it: it gets a copy loaded from the pointer. */
static bool borrowed_call_arg(const View *v, const MirInst *inst, uint32_t a) {
  if (!mir_op_is_call(inst->op)) {
    return false;
  }
  MirMode *modes = MS_ARENA_NEW_ARRAY(v->arena, MirMode, inst->nargs ? inst->nargs : 1);
  mir_arg_modes(v->m, v->f, inst, modes);
  MirMode result = MM_BORROW;
  const bool owned = inst->res == MIR_NONE || !mir_needs_drop(v->m, mir_value_ty(v->f, inst->res)) ||
                     (mir_result_mode(v->m, v->f, inst, &result) && result == MM_MOVE);
  return modes[a] == MM_BORROW && owned;
}

/* Whether the use of a record value at argument `a` of `inst` is one the rewrite handles. */
static bool use_ok(const View *v, const MirInst *inst, uint32_t a) {
  switch ((MirOp)inst->op) {
  case MOP_TypeGet:
    return a == 0 && inst->imm.tag == MI_FIELD && inst->imm.a == v->def && field_aligned(v, inst->imm.b);
  case MOP_TypeSet:
    return a == 0 && is_view(v, inst->res);
  case MOP_Put:
    return a == 1 && (inst->args[0] == v->param || v->lent[inst->args[0]]);
  default:
    return borrowed_call_arg(v, inst, a);
  }
}

/* Whether every use of a record value and of the pointer is handled. */
static bool uses_ok(const View *v, MirValue first) {
  const MirFunc *f = v->f;
  /* A field moved out of the record stays in place: only a lend that puts it back handles that. */
  bool *read = MS_ARENA_NEW_ARRAY(v->arena, bool, (size_t)f->values.len + 1);
  for (MirBlock b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      const MirInst *inst = &f->blocks.ptr[b].insts.ptr[i];
      if (inst->op == MOP_TypeGet && inst->res != MIR_NONE && is_view(v, inst->args[0]) && !v->fdead[inst->res]) {
        read[inst->res] = true;
      }
    }
  }
  for (MirBlock b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      const MirInst *inst = &f->blocks.ptr[b].insts.ptr[i];
      if (inst->op == MOP_MoveOut && read[inst->args[0]] && !v->ndead[inst->res] && !v->rmove[inst->res]) {
        return false;
      }
    }
  }
  for (MirBlock b = 0; b < f->blocks.len; b++) {
    const MirBlockData *blk = &f->blocks.ptr[b];
    for (uint32_t i = 0; i < blk->insts.len; i++) {
      const MirInst *inst = &blk->insts.ptr[i];
      for (uint32_t a = 0; a < inst->nargs; a++) {
        const MirValue x = inst->args[a];
        if (is_view(v, x) && !use_ok(v, inst, a)) {
          return false;
        }
        if (x == v->param && !((inst->op == MOP_Take && inst->res == first) ||
                               (inst->op == MOP_Put && a == 0 && is_view(v, inst->args[1])))) {
          return false;
        }
        if (v->lent[x] && inst->op != MOP_Put && inst->op != MOP_Take && !mir_op_is_call(inst->op) &&
            inst->op != MOP_Slot) {
          return false;
        }
      }
    }
    const MirTerm *term = &blk->term;
    const bool has_value = term->kind == MT_CONDBR || term->kind == MT_SWITCH || term->kind == MT_RET;
    if (has_value && term->value != MIR_NONE &&
        (is_view(v, term->value) || term->value == v->param || v->lent[term->value])) {
      return false;
    }
    for (uint32_t t = 0; t < mir_term_ntargets(term); t++) {
      const MirTarget *target = mir_term_target_const(term, t);
      const MirBlockData *to = &f->blocks.ptr[target->block];
      for (uint32_t k = 0; k < target->nargs; k++) {
        const MirValue x = target->args[k];
        if ((is_view(v, x) && !is_view(v, to->params.ptr[k].value)) || x == v->param || v->lent[x]) {
          return false;
        }
      }
    }
  }
  return true;
}

static MirInst make(MirModule *m, MirOp op, MirValue res, const MirValue *args, uint32_t nargs, MirImm imm,
                    MirLoc loc) {
  MirInst inst = {0};
  inst.op = (uint8_t)op;
  inst.res = res;
  inst.imm = imm;
  inst.loc = loc;
  inst.nargs = nargs;
  inst.args = MS_ARENA_NEW_ARRAY(&m->arena, MirValue, nargs + 1);
  for (uint32_t i = 0; i < nargs; i++) {
    inst.args[i] = args[i];
  }
  return inst;
}

/* The type.get that opens the field lend whose slot is `slot`. */
static const MirInst *field_get_of(const View *v, MirValue slot) {
  for (uint32_t i = 0; i < v->nflends; i++) {
    const FieldLend *fl = &v->flends[i];
    if (v->f->blocks.ptr[fl->block].insts.ptr[fl->slot].res == slot) {
      return &v->f->blocks.ptr[fl->block].insts.ptr[fl->get];
    }
  }
  return NULL;
}

/* Rewrites block `bi`: field reads and writes go through the pointer, the takes, puts and slots of the record go. */
static void rewrite_block(View *v, MirBlock bi, MirValue first) {
  MirBlockData *blk = &v->f->blocks.ptr[bi];
  MirInstList out = {0};
  for (uint32_t i = 0; i < blk->insts.len; i++) {
    MirInst inst = blk->insts.ptr[i];
    if (inst.op == MOP_Slot && inst.res != MIR_NONE && v->fslot[inst.res]) {
      const MirInst *get = field_get_of(v, inst.res);
      const MirValue base[1] = {v->param};
      mir_inst_list_push(&out, make(v->m, MOP_PtrField, inst.res, base, 1, get->imm, inst.loc));
      continue;
    }
    if (inst.res != MIR_NONE && v->rset[inst.res] != 0) {
      const MirValue at = mir_new_value(v->f, MIR_PTR);
      const MirValue base[1] = {v->param};
      mir_inst_list_push(&out, make(v->m, MOP_PtrField, at, base, 1, inst.imm, inst.loc));
      const MirValue stored[2] = {at, inst.args[1]};
      mir_inst_list_push(&out, make(v->m, MOP_Put, MIR_NONE, stored, 2, mir_imm_none(), inst.loc));
      continue;
    }
    if (inst.res != MIR_NONE && v->nsub[inst.res] != 0) {
      const NestedEdit *ne = &v->nedits[v->nsub[inst.res] - 1];
      const MirInst *get = &blk->insts.ptr[ne->get];
      const MirValue base[1] = {v->param};
      const MirValue outer_ptr = mir_new_value(v->f, MIR_PTR);
      mir_inst_list_push(&out, make(v->m, MOP_PtrField, outer_ptr, base, 1, get->imm, inst.loc));
      const MirValue inner_ptr = mir_new_value(v->f, MIR_PTR);
      mir_inst_list_push(&out, make(v->m, MOP_PtrField, inner_ptr, &outer_ptr, 1, inst.imm, inst.loc));
      const MirValue stored[2] = {inner_ptr, inst.args[1]};
      mir_inst_list_push(&out, make(v->m, MOP_Store, MIR_NONE, stored, 2, mir_imm_none(), inst.loc));
      continue;
    }
    if ((inst.op == MOP_Drop && inst.nargs == 1 && v->ndead[inst.args[0]]) ||
        (inst.res != MIR_NONE && (v->ndead[inst.res] || v->nouter[inst.res] != 0))) {
      continue;
    }
    if ((inst.res != MIR_NONE && (v->fdead[inst.res] || v->fset[inst.res] != 0)) ||
        (inst.op == MOP_Put && v->fslot[inst.args[0]])) {
      continue;
    }
    const Lend *own = inst.op == MOP_Slot && inst.res != MIR_NONE ? lend_of(v, inst.res) : NULL;
    const bool lend_take = inst.op == MOP_Take && inst.nargs == 1 && v->lent[inst.args[0]];
    const bool lend_put = inst.op == MOP_Put && v->lent[inst.args[0]];
    if (own != NULL || lend_take || lend_put || (inst.op == MOP_Take && inst.res == first) ||
        (inst.op == MOP_Put && inst.args[0] == v->param)) {
      continue;
    }
    if (inst.op == MOP_TypeGet && is_view(v, inst.args[0])) {
      const MirValue at = mir_new_value(v->f, MIR_PTR);
      const MirValue base[1] = {v->param};
      mir_inst_list_push(&out, make(v->m, MOP_PtrField, at, base, 1, inst.imm, inst.loc));
      const MirTy ty = mir_value_ty(v->f, inst.res);
      mir_inst_list_push(&out, make(v->m, MOP_Load, inst.res, &at, 1, (MirImm){.tag = MI_TY, .a = ty}, inst.loc));
      continue;
    }
    if (inst.op == MOP_TypeSet && is_view(v, inst.args[0])) {
      const MirValue at = mir_new_value(v->f, MIR_PTR);
      const MirValue base[1] = {v->param};
      mir_inst_list_push(&out, make(v->m, MOP_PtrField, at, base, 1, inst.imm, inst.loc));
      const MirValue stored[2] = {at, inst.args[1]};
      mir_inst_list_push(&out, make(v->m, MOP_Store, MIR_NONE, stored, 2, mir_imm_none(), inst.loc));
      continue;
    }
    for (uint32_t a = 0; a < inst.nargs && mir_op_is_call(inst.op); a++) {
      if (v->lent[inst.args[a]]) {
        inst.args[a] = v->param;
      } else if (is_view(v, inst.args[a])) {
        const MirValue copy = mir_new_value(v->f, v->record);
        const MirValue base[1] = {v->param};
        mir_inst_list_push(&out, make(v->m, MOP_Load, copy, base, 1, (MirImm){.tag = MI_TY, .a = v->record}, inst.loc));
        inst.args[a] = copy;
      }
    }
    mir_inst_list_push(&out, inst);
  }
  mir_block_set_insts(blk, &out);
}

/* The record's parameters and their edge arguments go. */
static void drop_params(View *v) {
  MirFunc *f = v->f;
  for (MirBlock b = 0; b < f->blocks.len; b++) {
    MirTerm *term = &f->blocks.ptr[b].term;
    for (uint32_t t = 0; t < mir_term_ntargets(term); t++) {
      MirTarget *target = mir_term_target(term, t);
      const MirBlockData *to = &f->blocks.ptr[target->block];
      for (uint32_t k = (uint32_t)to->params.len; k-- > 0;) {
        if (v->view[to->params.ptr[k].value] && v->candidate[to->params.ptr[k].value]) {
          mir_target_remove_arg(target, k);
        }
      }
    }
  }
  for (MirBlock b = 1; b < f->blocks.len; b++) {
    MirBlockData *blk = &f->blocks.ptr[b];
    uint32_t kept = 0;
    for (uint32_t k = 0; k < blk->params.len; k++) {
      if (!(v->view[blk->params.ptr[k].value] && v->candidate[blk->params.ptr[k].value])) {
        blk->params.ptr[kept++] = blk->params.ptr[k];
      }
    }
    blk->params.len = kept;
  }
}

/* Marks (or unmarks) the values and instructions of nested edit `ne`, number `number`. */
static void set_nested(View *v, const NestedEdit *ne, uint32_t number, bool on) {
  const MirBlockData *home = &v->f->blocks.ptr[ne->block];
  const MirValue g = home->insts.ptr[ne->get].res;
  v->nouter[home->insts.ptr[ne->outer].res] = on ? number : 0;
  for (uint32_t k = 0; k < ne->nsets; k++) {
    v->nsub[home->insts.ptr[ne->sets[k]].res] = on ? number : 0;
  }
  for (uint32_t i = 0; i < home->insts.len; i++) {
    const MirInst *inst = &home->insts.ptr[i];
    const bool clone = inst->op == MOP_Clone && inst->args[0] == g;
    const bool moved = inst->op == MOP_MoveOut && inst->args[0] == g;
    if ((clone || moved) && inst->res != MIR_NONE) {
      v->ndead[inst->res] = on;
    }
  }
}

/* Keeps the record of `var` parameter `index` in its pointer; false when some use is not handled. */
static bool view_param(MirModule *m, MirLayouts *layouts, MirFunc *f, uint32_t index) {
  const MirValue param = f->blocks.ptr[0].params.ptr[index].value;
  MirValue first = MIR_NONE;
  MirTy record = MIR_NONE;
  for (uint32_t i = 0; i < f->blocks.ptr[0].insts.len && first == MIR_NONE; i++) {
    const MirInst *inst = &f->blocks.ptr[0].insts.ptr[i];
    if (inst->op == MOP_Take && inst->nargs == 1 && inst->args[0] == param && inst->imm.tag == MI_TY) {
      first = inst->res;
      record = inst->imm.a;
    }
  }
  if (first == MIR_NONE) {
    return false;
  }
  const MirTyData *data = mir_ty_data(m, record);
  if (data->kind != MK_TYPE || m->type_defs.ptr[data->id].indirect || m->type_defs.ptr[data->id].native) {
    return false;
  }
  MsArena arena = ms_arena_new();
  const uint32_t *uses = mir_use_counts(&arena, f);
  const size_t n = (size_t)f->values.len + 1;
  View v = {.m = m,
            .layouts = layouts,
            .f = f,
            .arena = &arena,
            .param = param,
            .record = record,
            .def = data->id,
            .view = MS_ARENA_NEW_ARRAY(&arena, bool, n),
            .lent = MS_ARENA_NEW_ARRAY(&arena, bool, n),
            .lends = MS_ARENA_NEW_ARRAY(&arena, Lend, (size_t)mir_inst_count(f) + 1),
            .candidate = MS_ARENA_NEW_ARRAY(&arena, bool, n),
            .flends = MS_ARENA_NEW_ARRAY(&arena, FieldLend, (size_t)mir_inst_count(f) + 1),
            .fslot = MS_ARENA_NEW_ARRAY(&arena, bool, n),
            .fdead = MS_ARENA_NEW_ARRAY(&arena, bool, n),
            .fset = MS_ARENA_NEW_ARRAY(&arena, uint32_t, n),
            .reps = MS_ARENA_NEW_ARRAY(&arena, Replace, (size_t)mir_inst_count(f) + 1),
            .rset = MS_ARENA_NEW_ARRAY(&arena, uint32_t, n),
            .rmove = MS_ARENA_NEW_ARRAY(&arena, bool, n),
            .nedits = MS_ARENA_NEW_ARRAY(&arena, NestedEdit, (size_t)mir_inst_count(f) + 1),
            .nsub = MS_ARENA_NEW_ARRAY(&arena, uint32_t, n),
            .nouter = MS_ARENA_NEW_ARRAY(&arena, uint32_t, n),
            .ndead = MS_ARENA_NEW_ARRAY(&arena, bool, n)};
  for (MirBlock b = 0; b < f->blocks.len; b++) {
    find_lends(&v, b, uses);
  }
  for (uint32_t i = 0; i < v.nlends; i++) {
    v.lent[f->blocks.ptr[v.lends[i].block].insts.ptr[v.lends[i].slot].res] = true;
  }
  for (uint32_t i = 0; i < v.nflends; i++) {
    const FieldLend *fl = &v.flends[i];
    const MirBlockData *home = &f->blocks.ptr[fl->block];
    v.fslot[home->insts.ptr[fl->slot].res] = true;
    v.fdead[home->insts.ptr[fl->get].res] = true;
    v.fdead[home->insts.ptr[fl->move].res] = true;
    v.fdead[home->insts.ptr[fl->take].res] = true;
    v.fset[home->insts.ptr[fl->set].res] = i + 1;
  }
  for (uint32_t i = 0; i < v.nnedits; i++) {
    set_nested(&v, &v.nedits[i], i + 1, true);
  }
  for (uint32_t i = 0; i < v.nreps; i++) {
    const MirBlockData *home = &f->blocks.ptr[v.reps[i].block];
    v.rset[home->insts.ptr[v.reps[i].outer].res] = i + 1;
    v.rmove[home->insts.ptr[v.reps[i].get + 1].res] = true;
  }
  for (MirBlock b = 1; b < f->blocks.len; b++) {
    for (uint32_t k = 0; k < f->blocks.ptr[b].params.len; k++) {
      const MirBlockParam *p = &f->blocks.ptr[b].params.ptr[k];
      v.candidate[p->value] = p->mode == MM_MOVE && mir_value_ty(f, p->value) == record;
    }
  }
  settle(&v, first);
  /* A field lend whose record is not this one's is plain code. */
  for (uint32_t i = 0; i < v.nflends; i++) {
    const FieldLend *fl = &v.flends[i];
    const MirBlockData *home = &f->blocks.ptr[fl->block];
    if (!is_view(&v, home->insts.ptr[fl->get].args[0]) || !is_view(&v, home->insts.ptr[fl->set].args[0])) {
      v.fslot[home->insts.ptr[fl->slot].res] = false;
      v.fdead[home->insts.ptr[fl->get].res] = false;
      v.fdead[home->insts.ptr[fl->move].res] = false;
      v.fdead[home->insts.ptr[fl->take].res] = false;
      v.fset[home->insts.ptr[fl->set].res] = 0;
    }
  }
  for (uint32_t i = 0; i < v.nnedits; i++) {
    const NestedEdit *ne = &v.nedits[i];
    const MirBlockData *home = &f->blocks.ptr[ne->block];
    if (!is_view(&v, home->insts.ptr[ne->get].args[0]) || !is_view(&v, home->insts.ptr[ne->outer].args[0])) {
      set_nested(&v, ne, i + 1, false);
    }
  }
  for (uint32_t i = 0; i < v.nreps; i++) {
    const MirBlockData *home = &f->blocks.ptr[v.reps[i].block];
    if (!is_view(&v, home->insts.ptr[v.reps[i].get].args[0]) || !is_view(&v, home->insts.ptr[v.reps[i].outer].args[0])) {
      v.rset[home->insts.ptr[v.reps[i].outer].res] = 0;
      v.rmove[home->insts.ptr[v.reps[i].get + 1].res] = false;
    }
  }
  /* A slot of the record's type that holds some other record (another `var` parameter's) is not a lend of this one. */
  for (uint32_t i = 0; i < v.nlends; i++) {
    const Lend *lend = &v.lends[i];
    const MirBlockData *home = &f->blocks.ptr[lend->block];
    if (!is_view(&v, home->insts.ptr[lend->put].args[1])) {
      v.lent[home->insts.ptr[lend->slot].res] = false;
    }
  }
  const bool ok = uses_ok(&v, first);
  if (ok) {
    for (MirBlock b = 0; b < f->blocks.len; b++) {
      rewrite_block(&v, b, first);
    }
    drop_params(&v);
  }
  ms_arena_free(&arena);
  return ok;
}

bool opt_fieldview(MirModule *m) {
  bool changed = false;
  MirLayouts layouts;
  mir_layouts_init(&layouts, m);
  for (uint32_t fi = 0; fi < m->funcs.len; fi++) {
    MirFunc *f = &m->funcs.ptr[fi];
    for (uint32_t p = 0; f->blocks.len > 0 && p < f->blocks.ptr[0].params.len; p++) {
      if (mir_value_ty(f, f->blocks.ptr[0].params.ptr[p].value) == MIR_PTR && view_param(m, &layouts, f, p)) {
        changed = true;
      }
    }
  }
  mir_layouts_free(&layouts);
  return changed;
}

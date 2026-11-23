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

/* Finds the slots of block `bi` that are put into once, handed to calls, and taken from once, with no other use. */
static void find_lends(View *v, MirBlock bi, const uint32_t *uses) {
  const MirBlockData *blk = &v->f->blocks.ptr[bi];
  for (uint32_t si = 0; si < blk->insts.len; si++) {
    const MirInst *slot = &blk->insts.ptr[si];
    if (slot->op != MOP_Slot || slot->imm.tag != MI_TY || slot->imm.a != v->record ||
        slot->res == MIR_NONE) {
      continue;
    }
    uint32_t put = MIR_NONE, take = MIR_NONE, calls = 0;
    bool ok = true;
    for (uint32_t i = si + 1; i < blk->insts.len && ok; i++) {
      const MirInst *inst = &blk->insts.ptr[i];
      bool names = false;
      for (uint32_t a = 0; a < inst->nargs; a++) {
        names = names || inst->args[a] == slot->res;
      }
      if (!names) {
        continue;
      }
      if (inst->op == MOP_Put && inst->args[0] == slot->res && put == MIR_NONE && take == MIR_NONE) {
        put = i;
      } else if (inst->op == MOP_Take && inst->args[0] == slot->res && put != MIR_NONE && take == MIR_NONE) {
        take = i;
      } else if (mir_op_is_call(inst->op) && put != MIR_NONE && take == MIR_NONE) {
        for (uint32_t a = 0; a < inst->nargs; a++) {
          calls += inst->args[a] == slot->res ? 1u : 0u;
        }
      } else {
        ok = false;
      }
    }
    if (ok && put != MIR_NONE && take != MIR_NONE && uses[slot->res] == 2 + calls) {
      v->lends[v->nlends++] = (Lend){bi, si, put, take};
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
    return false;
  }
}

/* Whether every use of a record value and of the pointer is handled. */
static bool uses_ok(const View *v, MirValue first) {
  const MirFunc *f = v->f;
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

/* Rewrites block `bi`: field reads and writes go through the pointer, the takes, puts and slots of the record go. */
static void rewrite_block(View *v, MirBlock bi, MirValue first) {
  MirBlockData *blk = &v->f->blocks.ptr[bi];
  MirInstList out = {0};
  for (uint32_t i = 0; i < blk->insts.len; i++) {
    MirInst inst = blk->insts.ptr[i];
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
      }
    }
    mir_inst_list_push(&out, inst);
  }
  mir_block_set_insts(blk, &out);
}

static void remove_target_arg(MirTarget *t, uint32_t k) {
  __builtin_memmove(&t->args[k], &t->args[k + 1], sizeof(MirValue) * (t->nargs - k - 1));
  t->nargs--;
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
          remove_target_arg(target, k);
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
  /* A Map or Set field lives in a box, a word in the record: `ptr.field` offsets and loads do not see that. */
  const MirTypeDef *def = &m->type_defs.ptr[data->id];
  for (uint32_t k = 0; k < def->nfields; k++) {
    if (mir_ty_is_map_or_set(m, def->fields[k].ty)) {
      return false;
    }
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
            .candidate = MS_ARENA_NEW_ARRAY(&arena, bool, n)};
  for (MirBlock b = 0; b < f->blocks.len; b++) {
    find_lends(&v, b, uses);
  }
  for (uint32_t i = 0; i < v.nlends; i++) {
    v.lent[f->blocks.ptr[v.lends[i].block].insts.ptr[v.lends[i].slot].res] = true;
  }
  for (MirBlock b = 1; b < f->blocks.len; b++) {
    for (uint32_t k = 0; k < f->blocks.ptr[b].params.len; k++) {
      const MirBlockParam *p = &f->blocks.ptr[b].params.ptr[k];
      v.candidate[p->value] = p->mode == MM_MOVE && mir_value_ty(f, p->value) == record;
    }
  }
  settle(&v, first);
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

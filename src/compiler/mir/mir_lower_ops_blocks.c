/* compiler/mir/mir_lower_ops_blocks.c: the block-level rewrites of the lower-ops pass: list element drops,
 * string literal compares, block copies, record field sets, conditional drops, cleanups and fault messages. */
#include "compiler/mir/mir_lower_ops_internal.h"

#include "base/alloc.h"

/* Appends an instruction with a fresh result of `ty` (none when MIR_NONE) to `out`. */
static MirValue add(LowerCx *cx, MirFunc *func, MirInstList *out, MirOp op, const MirValue *args, uint32_t count,
                    MirImm imm, MirTy ty, MirLoc loc) {
  const MirValue result = ty == MIR_NONE ? MIR_NONE : mir_new_value(func, ty);
  mir_inst_list_push(out, mir_inst(op, imm, result, loc, mir_args_copy(cx->module, args, count), count));
  return result;
}

/* ---- list element drops ---- */

static bool is_list_drop(const LowerCx *cx, const MirFunc *func, const MirInst *inst, MirTy *elem) {
  const bool set = inst->op == MOP_ListSetU;
  const bool last = inst->op == MOP_ListDropLast && !(inst->imm.tag == MI_INT && inst->imm.i == 1);
  if (!set && !last) {
    return false;
  }
  *elem = mir_ty_data(cx->module, mir_value_ty(func, inst->args[0]))->elem;
  return mir_needs_drop(cx->module, *elem);
}

/* The position of the last element of the list `inst` removes. */
static MirValue last_index(LowerCx *cx, MirFunc *func, MirInstList *out, const MirInst *inst) {
  const MirValue len = add(cx, func, out, MOP_ListLen, inst->args, 1, mir_imm_none(), MIR_INT, inst->loc);
  const MirValue one = add(cx, func, out, MOP_IConst, NULL, 0, (MirImm){.tag = MI_INT, .i = 1}, MIR_INT, inst->loc);
  const MirValue pair[2] = {len, one};
  return add(cx, func, out, MOP_ISub, pair, 2, mir_imm_none(), MIR_INT, inst->loc);
}

/* `list.set.u` and `list.droplast` drop the element they overwrite or remove. The emitters only write memory,
 * so the old element is read and dropped first and the op becomes its plain form (`list.fill.u`,
 * `list.droplast 1`). */
void mirlo_list_drops(LowerCx *cx, MirFunc *func) {
  for (size_t bi = 0; bi < func->blocks.len; bi++) {
    MirInstList out = {0};
    bool changed = false;
    for (size_t ii = 0; ii < func->blocks.ptr[bi].insts.len; ii++) {
      MirInst inst = func->blocks.ptr[bi].insts.ptr[ii];
      MirTy elem = MIR_NONE;
      const bool set = inst.op == MOP_ListSetU;
      if (is_list_drop(cx, func, &inst, &elem)) {
        MirValue at = set ? inst.args[1] : last_index(cx, func, &out, &inst);
        const MirValue get[2] = {inst.args[0], at};
        const MirValue old = add(cx, func, &out, MOP_ListGetU, get, 2, mir_imm_none(), elem, inst.loc);
        (void)add(cx, func, &out, MOP_Drop, &old, 1, mir_imm_none(), MIR_NONE, inst.loc);
        inst.imm = set ? inst.imm : (MirImm){.tag = MI_INT, .i = 1};
        changed = true;
      }
      inst.op = set ? MOP_ListFillU : inst.op;
      mir_inst_list_push(&out, inst);
    }
    if (changed) {
      mir_block_set_insts(&func->blocks.ptr[bi], &out);
    } else {
      mir_inst_list_free(&out);
    }
  }
}

/* ---- string literal compares ---- */

/* `str.eq_lit s` with literal L becomes `msrt_string_eq(s, str L)`. */
void mirlo_str_eq_lits(LowerCx *cx, MirFunc *func) {
  const MirTy strs[2] = {MIR_STR, MIR_STR};
  for (size_t bi = 0; bi < func->blocks.len; bi++) {
    MirInstList out = {0};
    bool changed = false;
    for (size_t ii = 0; ii < func->blocks.ptr[bi].insts.len; ii++) {
      const MirInst held = func->blocks.ptr[bi].insts.ptr[ii];
      if (held.op != MOP_StrEqLit) {
        mir_inst_list_push(&out, held);
        continue;
      }
      changed = true;
      const MirValue lit = add(cx, func, &out, MOP_StrLit, NULL, 0, held.imm, MIR_STR, held.loc);
      const MirValue args[2] = {held.args[0], lit};
      const uint32_t eq = mirlo_rt(cx, &cx->string_eq, "msrt_string_eq", strs, 2, MIR_BOOL);
      mir_inst_list_push(&out, mir_inst(MOP_CallRt, mir_imm_ext(eq), held.res, held.loc,
                                        mir_args_copy(cx->module, args, 2), 2));
    }
    if (changed) {
      mir_block_set_insts(&func->blocks.ptr[bi], &out);
    } else {
      mir_inst_list_free(&out);
    }
  }
}

/* ---- string drops ---- */

/* A string owns heap memory only when its tag is zero, and most strings built by a program are inline or
 * borrowed, so `drop s` becomes `drop.if owns s`: the runtime is called only for the strings that need it. The
 * tag word is read through one slot made in the entry block, which the back end keeps in registers. */
void mirlo_str_drops(LowerCx *cx, MirFunc *func) {
  MirValue slot = MIR_NONE;
  for (size_t bi = 0; bi < func->blocks.len; bi++) {
    MirInstList out = {0};
    bool changed = false;
    for (size_t ii = 0; ii < func->blocks.ptr[bi].insts.len; ii++) {
      const MirInst held = func->blocks.ptr[bi].insts.ptr[ii];
      if (held.op != MOP_Drop || mir_value_ty(func, held.args[0]) != MIR_STR) {
        mir_inst_list_push(&out, held);
        continue;
      }
      changed = true;
      if (slot == MIR_NONE) {
        slot = mir_new_value(func, MIR_PTR);
      }
      const MirValue value = held.args[0];
      const MirValue stored[2] = {slot, value};
      (void)add(cx, func, &out, MOP_Store, stored, 2, mir_imm_none(), MIR_NONE, held.loc);
      const MirValue eight = add(cx, func, &out, MOP_IConst, NULL, 0, (MirImm){.tag = MI_INT, .i = 8}, MIR_INT, held.loc);
      const MirValue pair[2] = {slot, eight};
      const MirValue tag_at = add(cx, func, &out, MOP_PtrAdd, pair, 2, mir_imm_none(), MIR_PTR, held.loc);
      const MirValue word = add(cx, func, &out, MOP_Load, &tag_at, 1, (MirImm){.tag = MI_TY, .a = MIR_INT}, MIR_INT, held.loc);
      const MirValue shift = add(cx, func, &out, MOP_IConst, NULL, 0, (MirImm){.tag = MI_INT, .i = 62}, MIR_INT, held.loc);
      const MirValue shifted_args[2] = {word, shift};
      const MirValue tag = add(cx, func, &out, MOP_Ushr, shifted_args, 2, mir_imm_none(), MIR_INT, held.loc);
      const MirValue zero = add(cx, func, &out, MOP_IConst, NULL, 0, (MirImm){.tag = MI_INT, .i = 0}, MIR_INT, held.loc);
      const MirValue compared[2] = {tag, zero};
      const MirValue owns = add(cx, func, &out, MOP_ICmp, compared, 2, mir_imm_cc(MCC_EQ), MIR_BOOL, held.loc);
      const MirValue conditional[2] = {owns, value};
      (void)add(cx, func, &out, MOP_DropIf, conditional, 2, mir_imm_none(), MIR_NONE, held.loc);
    }
    if (changed) {
      mir_block_set_insts(&func->blocks.ptr[bi], &out);
    } else {
      mir_inst_list_free(&out);
    }
  }
  if (slot != MIR_NONE) {
    const MirInst made = mir_inst(MOP_Slot, (MirImm){.tag = MI_TY, .a = MIR_STR}, slot, func->loc,
                                  mir_args_copy(cx->module, NULL, 0), 0);
    mir_block_insert(&func->blocks.ptr[0], mir_entry_insert_at(func), &made);
  }
}

/* ---- block copies ---- */

/* A clone of bytes, or of a list whose elements own nothing, is one block copy by the runtime. A list's copy
 * needs the element descriptor, which this pass makes a value of its own. */
static bool is_block_clone(const LowerCx *cx, const MirFunc *func, const MirInst *inst) {
  if (inst->op != MOP_Clone || inst->nargs == 0) {
    return false;
  }
  const MirTyData *data = mir_ty_data(cx->module, mir_value_ty(func, inst->args[0]));
  return data->kind == MK_BYTES || (data->kind == MK_LIST && !mir_needs_drop(cx->module, data->elem));
}

static uint32_t block_copy_extern(LowerCx *cx, MirTy list, bool bytes) {
  MirExtern def = {.name = mir_name(cx->module, ms_span_of_text(bytes ? "msrt_bytes_copy" : "msrt_list_copy")),
                   .nparams = bytes ? 1 : 2,
                   .ret = list,
                   .fresh = true,
                   .leaf = true,
                   .role = MR_NONE};
  MirParam params[2] = {{list, MM_BORROW}, {MIR_PTR, MM_BORROW}};
  def.params = params;
  return mir_extern_intern(cx->module, &def);
}

void mirlo_block_clones(LowerCx *cx, MirFunc *func) {
  for (size_t bi = 0; bi < func->blocks.len; bi++) {
    MirInstList out = {0};
    bool changed = false;
    for (size_t ii = 0; ii < func->blocks.ptr[bi].insts.len; ii++) {
      MirInst inst = func->blocks.ptr[bi].insts.ptr[ii];
      if (!is_block_clone(cx, func, &inst)) {
        mir_inst_list_push(&out, inst);
        continue;
      }
      changed = true;
      const MirTy list = mir_value_ty(func, inst.args[0]);
      const MirTyData *data = mir_ty_data(cx->module, list);
      MirValue args[2] = {inst.args[0], MIR_NONE};
      uint32_t nargs = 1;
      if (data->kind == MK_LIST) {
        args[1] = add(cx, func, &out, MOP_TypeDesc, NULL, 0, (MirImm){.tag = MI_TY, .a = data->elem}, MIR_PTR, inst.loc);
        nargs = 2;
      }
      mirlo_to_call_rt(&inst, block_copy_extern(cx, list, data->kind == MK_BYTES));
      inst.args = mir_args_copy(cx->module, args, nargs);
      inst.nargs = nargs;
      mir_inst_list_push(&out, inst);
    }
    if (changed) {
      mir_block_set_insts(&func->blocks.ptr[bi], &out);
    } else {
      mir_inst_list_free(&out);
    }
  }
}

/* ---- record field sets ---- */

/* Whether `inst` is a `type.set` of a field that owns something, on a record behind a pointer. */
static bool is_dropping_set(const LowerCx *cx, const MirFunc *func, const MirInst *inst) {
  if (inst->op != MOP_TypeSet) {
    return false;
  }
  const MirTyData *data = mir_ty_data(cx->module, mir_value_ty(func, inst->args[0]));
  if (data->kind != MK_TYPE) {
    return false;
  }
  const MirTypeDef *def = &cx->module->type_defs.ptr[data->id];
  return def->indirect && mir_needs_drop(cx->module, def->fields[inst->imm.b].ty);
}

/* `type.set` of an owning field of a record behind a pointer drops the old value first; the emitters only
 * write the field (`type.fill`), so the drop becomes `type.get` and `drop` before it. */
void mirlo_expand_sets(LowerCx *cx, MirFunc *func) {
  for (size_t bi = 0; bi < func->blocks.len; bi++) {
    MirInstList out = {0};
    bool changed = false;
    for (size_t ii = 0; ii < func->blocks.ptr[bi].insts.len; ii++) {
      MirInst held = func->blocks.ptr[bi].insts.ptr[ii];
      if (is_dropping_set(cx, func, &held)) {
        const MirTyData *data = mir_ty_data(cx->module, mir_value_ty(func, held.args[0]));
        const MirTy field_ty = cx->module->type_defs.ptr[data->id].fields[held.imm.b].ty;
        const MirValue old = add(cx, func, &out, MOP_TypeGet, held.args, 1, held.imm, field_ty, held.loc);
        (void)add(cx, func, &out, MOP_Drop, &old, 1, mir_imm_none(), MIR_NONE, held.loc);
        held.op = MOP_TypeFill;
        changed = true;
      }
      mir_inst_list_push(&out, held);
    }
    if (changed) {
      mir_block_set_insts(&func->blocks.ptr[bi], &out);
    } else {
      mir_inst_list_free(&out);
    }
  }
}

/* ---- conditional drops ---- */

/* Splits block `bi` at the `drop.if` at position `at`: the block ends with a branch on the flag to a block that
 * drops the value and on to a block holding the rest. */
static void split_at(MirModule *module, MirFunc *func, size_t bi, size_t at) {
  const MirInst held = func->blocks.ptr[bi].insts.ptr[at];
  const MirTerm term = func->blocks.ptr[bi].term;
  const MirLoc term_loc = func->blocks.ptr[bi].term_loc;
  MirInstList rest = {0};
  for (size_t index = at + 1; index < func->blocks.ptr[bi].insts.len; index++) {
    mir_inst_list_push(&rest, func->blocks.ptr[bi].insts.ptr[index]);
  }
  func->blocks.ptr[bi].insts.len = at;
  const MirBlock drop = mir_new_block(func);
  const MirBlock next = mir_new_block(func);
  MirBlockData *dropped = &func->blocks.ptr[drop];
  const MirValue victim = held.args[1];
  mir_inst_list_push(&dropped->insts,
                     mir_inst(MOP_Drop, mir_imm_none(), MIR_NONE, held.loc, mir_args_copy(module, &victim, 1), 1));
  dropped->term = (MirTerm){.kind = MT_BR, .value = MIR_NONE, .a = {.block = next}};
  dropped->term_loc = held.loc;
  MirBlockData *tail = &func->blocks.ptr[next];
  tail->insts = rest;
  tail->term = term;
  tail->term_loc = term_loc;
  MirBlockData *head = &func->blocks.ptr[bi];
  head->term = (MirTerm){.kind = MT_CONDBR, .value = held.args[0], .a = {.block = drop}, .b = {.block = next}};
  head->term_loc = held.loc;
}

/* `drop.if flag v` ends its block with a branch on `flag` to a block that drops `v` and on to a block holding
 * the rest, so the drop that remains is a plain `drop`. Blocks the split makes are visited too, for a second
 * `drop.if`. */
void mirlo_split_drop_ifs(MirModule *module, MirFunc *func) {
  for (size_t bi = 0; bi < func->blocks.len; bi++) {
    for (size_t ii = 0; ii < func->blocks.ptr[bi].insts.len; ii++) {
      if (func->blocks.ptr[bi].insts.ptr[ii].op == MOP_DropIf) {
        split_at(module, func, bi, ii);
        break;
      }
    }
  }
}

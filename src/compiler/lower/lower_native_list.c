/* compiler/lower/lower_native_list.c: the list natives that edit in place or close what they replace: `append`, `set`,
 * `get`, and the `_take` forms of `remove`, `splice` and a map's `add`, `remove` and `clear` on resources. */
#include "compiler/lower/lower_fn.h"
#include "compiler/natives/native_sigs.h"
#include "compiler/mir/mir_analysis.h"

MirValue fn_list_get(LowerFn *fn, MirValue list, MirValue index, MirTy elem) {
  const MirValue length = mir_b_emit(&fn->b, MOP_ListLen, &list, 1, (MirImm){0}, MIR_INT);
  const MirValue from_end = mir_b_binop(&fn->b, MOP_IAdd, index, length);
  const MirValue negative = mir_b_icmp(&fn->b, MCC_LT, index, mir_b_iconst(&fn->b, 0));
  const MirValue at = mir_b_select(&fn->b, negative, from_end, index);
  const MirValue args[2] = {list, at};
  return mir_b_emit(&fn->b, MOP_ListGet, args, 2, (MirImm){0}, elem);
}

/* A native that changes a list receiver in line: the list is taken out of its slot or place, and `list_put` puts
 * the updated list back. False when the receiver is neither (nothing is emitted then). */
static bool list_changeable(LowerFn *fn, const MsExpr *place, MirValue slot) {
  if (slot != MIR_NONE) {
    return true;
  }
  /* An element of a list held in place changes where it lies (`call_changing`), not through a copy put back. */
  MsExpr *container = NULL;
  MsExpr *key = NULL;
  if (place != NULL && ms_expr_index(place, &container, &key) && fn_is_list(fn, container) && lists_in_place(fn, container)) {
    return false;
  }
  return place != NULL && fn_place_changeable(fn, place);
}

static bool list_take(LowerFn *fn, const MsExpr *place, MirValue slot, MirTy list_ty, MirValue *owned, MirValue *record) {
  *record = MIR_NONE;
  if (slot != MIR_NONE) {
    *owned = mir_b_emit(&fn->b, MOP_Take, &slot, 1, (MirImm){.tag = MI_TY, .a = list_ty}, list_ty);
    return true;
  }
  return fn_take_field(fn, place, record, owned) || fn_take_place(fn, place, owned);
}

static bool list_put(LowerFn *fn, const MsExpr *place, MirValue slot, MirValue record, MirValue updated) {
  if (record != MIR_NONE) {
    return fn_put_field(fn, place, record, updated);
  }
  if (slot == MIR_NONE) {
    return fn_put_place(fn, place, updated);
  }
  const MirValue stored[2] = {slot, updated};
  (void)mir_b_emit(&fn->b, MOP_Put, stored, 2, (MirImm){0}, MIR_NONE);
  return true;
}

/* The address of the list that `place` names when it is an element of a list lying in a variable, field or element
 * (`rows[i].append(x)`), else MIR_NONE. */
static MirValue list_element_slot(LowerFn *fn, const MsExpr *place) {
  MsExpr *container = NULL;
  MsExpr *key = NULL;
  if (place == NULL || !ms_expr_index(place, &container, &key) || !fn_is_list(fn, container) || !lists_in_place(fn, container)) {
    return MIR_NONE;
  }
  const MirValue list = fn_expr(fn, container, LW_BORROW);
  const MirValue at = list == MIR_NONE ? MIR_NONE : fn_expr(fn, key, LW_BORROW);
  if (at == MIR_NONE) {
    return MIR_NONE;
  }
  const MirValue operands[2] = {list, at};
  return mir_b_emit(&fn->b, MOP_ListAddr, operands, 2, (MirImm){0}, MIR_PTR);
}

/* `list.append(value)`: the list grows in line (a full list calls the grow block) and the updated list goes back. */
bool fn_list_append(LowerFn *fn, const MsExpr *place, MirValue slot, const MirValue *args, MirValue *out) {
  const MirTy list_ty = mir_b_ty(&fn->b, args[0]);
  const MirTyData *list = mir_ty_data(fn->cx->module, list_ty);
  MirValue owned;
  MirValue record;
  if (list->kind != MK_LIST || mir_b_ty(&fn->b, args[1]) != list->elem) {
    return false;
  }
  if (slot == MIR_NONE) {
    slot = list_element_slot(fn, place);
  }
  if (!list_changeable(fn, place, slot) || !list_take(fn, place, slot, list_ty, &owned, &record)) {
    return false;
  }
  const MirValue operands[2] = {owned, args[1]};
  const MirValue updated = mir_b_emit(&fn->b, MOP_ListPush, operands, 2, (MirImm){0}, list_ty);
  *out = mir_b_emit(&fn->b, MOP_VoidConst, NULL, 0, (MirImm){0}, MIR_VOID);
  return list_put(fn, place, slot, record, updated);
}

/* `list.set(index, value)` on a list of plain values (an element that owns something needs the runtime to drop the
 * old one): the receiver is taken out of its place or slot, the index is checked with the runtime's `List.set`
 * fault, the element is stored by `list.set.u`, and the updated list goes back. */
bool fn_list_set(LowerFn *fn, const MsExpr *place, MirValue slot, const MirValue *args, MirValue *out) {
  const MirTy list_ty = mir_b_ty(&fn->b, args[0]);
  const MirTyData *list = mir_ty_data(fn->cx->module, list_ty);
  if (list->kind != MK_LIST || mir_needs_drop(fn->cx->module, list->elem) || mir_b_ty(&fn->b, args[2]) != list->elem) {
    return false;
  }
  if (slot == MIR_NONE) {
    slot = list_element_slot(fn, place);
  }
  if (!list_changeable(fn, place, slot)) {
    return false;
  }
  const MirValue length = mir_b_emit(&fn->b, MOP_ListLen, &args[0], 1, (MirImm){0}, MIR_INT);
  const MirValue zero = mir_b_iconst(&fn->b, 0);
  const MirValue negative = mir_b_icmp(&fn->b, MCC_LT, args[1], zero);
  const MirValue at = mir_b_select(&fn->b, negative, mir_b_binop(&fn->b, MOP_IAdd, args[1], length), args[1]);
  const MirValue pair[2] = {at, length};
  const MirValue inside = mir_b_emit(&fn->b, MOP_UICmp, pair, 2, (MirImm){.tag = MI_CC, .a = (uint32_t)MCC_LT}, MIR_BOOL);
  const MirBlock hit = mir_b_new_block(&fn->b);
  const MirBlock miss = mir_b_new_block(&fn->b);
  mir_b_br_if(&fn->b, inside, hit, NULL, 0, miss, NULL, 0);
  mir_b_seal_block(&fn->b, hit);
  mir_b_seal_block(&fn->b, miss);
  mir_b_switch_to(&fn->b, miss);
  const MirValue fault_args[3] = {mir_b_iconst(&fn->b, 2), args[1], length};
  (void)fn_runtime_call(fn, mir_name(fn->cx->module, ms_span_of_text("msrt_list_index_fault")), fault_args, 3, MIR_VOID);
  mir_b_unreachable(&fn->b);
  mir_b_switch_to(&fn->b, hit);
  MirValue owned;
  MirValue record;
  if (!list_take(fn, place, slot, list_ty, &owned, &record)) {
    return false;
  }
  const MirValue operands[3] = {owned, at, args[2]};
  const MirValue updated = mir_b_emit(&fn->b, MOP_ListSetU, operands, 3, (MirImm){0}, list_ty);
  *out = mir_b_emit(&fn->b, MOP_VoidConst, NULL, 0, (MirImm){0}, MIR_VOID);
  return list_put(fn, place, slot, record, updated);
}

/* `list.set(index, value)` on resources: the element it replaces closes, so the set is a `replace` whose old element
 * the scope closes (the incoming value is still held by its closing slot until the replace stored it). */
bool fn_list_set_closing(LowerFn *fn, const MsExpr *place, MirValue slot, MsTy owner, uint32_t argc,
                             const MirValue *args, MirValue *out) {
  MsTyTable *types = &fn->cx->program->types;
  if (argc != 3 || !ms_ty_is(types, owner, MS_BUILTIN_List) || fn->closing == NULL) {
    return false;
  }
  const MsTy elem = ms_ty_subst(types, ms_ty_args(types, owner)[0], fn->subst.vars, fn->subst.args, fn->subst.count);
  if (!fn_temp_closes(fn, elem)) {
    return false;
  }
  MirValue old = MIR_NONE;
  if (!native_on(fn, place, slot, owner, ms_span_of_text("replace"), argc, args, mir_b_ty(&fn->b, args[2]), &old) ||
      old == MIR_NONE || !fn_close_replaced(fn, elem, old)) {
    return false;
  }
  *out = mir_b_emit(&fn->b, MOP_VoidConst, NULL, 0, (MirImm){0}, MIR_VOID);
  return true;
}

/* The list type `List[elem]`, built from any list type of the program. */
static MsTy list_of(LowerFn *fn, MsTy elem) {
  MsTyTable *types = &fn->cx->program->types;
  for (size_t at = 1; at < types->rows.len; at++) {
    const MsTyRow *row = &types->rows.ptr[at];
    if (row->builtin == MS_BUILTIN_List && row->arg_count == 1) {
      const MsTyDesc desc = {.name = row->name, .id = row->id, .kind = (MsTyKind)row->kind, .builtin = MS_BUILTIN_List,
                             .def = row->def, .args = &elem, .arg_count = 1};
      return ms_ty_intern(types, &desc);
    }
  }
  return MS_TY_NONE;
}

/* A native that drops what it removes (`remove`, `splice`, a map's `add` over a key, `remove`, `clear`), on resources:
 * the `_take` form moves the removed values out in a list, and the list closes where the scope ends, last first. */
bool fn_native_closing_take(LowerFn *fn, const MsExpr *place, MirValue slot, MsTy owner, MsSpan operation, uint32_t argc,
                                  const MirValue *args, MirValue *out) {
  MsTyTable *types = &fn->cx->program->types;
  const bool is_list = ms_ty_is(types, owner, MS_BUILTIN_List);
  const bool is_map = ms_ty_is(types, owner, MS_BUILTIN_Map);
  const bool wanted = (is_list && ((ms_span_is_text(operation, "remove") && argc == 2) ||
                                   (ms_span_is_text(operation, "splice") && argc == 4))) ||
                      (is_map && ((ms_span_is_text(operation, "remove") && argc == 2) ||
                                  (ms_span_is_text(operation, "add") && argc == 3) ||
                                  (ms_span_is_text(operation, "clear") && argc == 1)));
  if (!wanted || fn->closing == NULL || (!is_list && ms_ty_arg_count(types, owner) != 2)) {
    return false;
  }
  const MsTy elem = ms_ty_subst(types, ms_ty_args(types, owner)[is_list ? 0 : 1], fn->subst.vars, fn->subst.args, fn->subst.count);
  if (!fn_temp_closes(fn, elem)) {
    return false;
  }
  const MsTy removed = is_list ? owner : list_of(fn, elem);
  if (removed == MS_TY_NONE) {
    return false;
  }
  const MirTy taken_ty = fn_type(fn, ms_ty_subst(types, removed, fn->subst.vars, fn->subst.args, fn->subst.count));
  const char *name = ms_span_is_text(operation, "remove") ? "remove_take"
                     : ms_span_is_text(operation, "splice") ? "splice_take"
                     : ms_span_is_text(operation, "add")    ? "add_take"
                                                            : "clear_take";
  MirValue taken = MIR_NONE;
  if (!native_on(fn, place, slot, owner, ms_span_of_text(name), argc, args, taken_ty, &taken) || taken == MIR_NONE ||
      !fn_close_replaced(fn, removed, taken)) {
    return false;
  }
  *out = mir_b_emit(&fn->b, MOP_VoidConst, NULL, 0, (MirImm){0}, MIR_VOID);
  return true;
}

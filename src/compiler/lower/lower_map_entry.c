/* compiler/lower/lower_map_entry.c: reading a map entry by key: the address of the entry, and the fault of a missing key. */
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_analysis.h"

/* Ends the current block with the fault of a missing map key, posted and left by the function's exit: `key` is the slot
 * holding the key of type `key_ty`. */
void fn_fault_missing_key(LowerFn *fn, MirValue key, MirTy key_ty) {
  const MirImm of_key = {.tag = MI_TY, .a = key_ty};
  const MirValue missing = mir_b_emit(&fn->b, MOP_Load, &key, 1, of_key, key_ty);
  const MirValue text = fn_value_repr(fn, missing, key_ty);
  const MirValue prefix_lit = mir_b_emit(&fn->b, MOP_StrLit, NULL, 0,
                                         (MirImm){.tag = MI_STR, .a = mir_add_string(fn->cx->module, ms_span_of_text("map key not found: "))},
                                         MIR_STR);
  const MirValue parts[2] = {prefix_lit, text};
  const MirValue message = fn_runtime_call(fn, mir_name(fn->cx->module, ms_span_of_text("msrt_string_concat")), parts, 2, MIR_STR);
  (void)fn_runtime_call(fn, mir_name(fn->cx->module, ms_span_of_text("msrt_panic")), &message, 1, MIR_VOID);
  fn_unwind_exit(fn);
}

/* `map[key]`: an owned copy of the value; a missing key faults with the key's text. */
MirValue fn_map_index(LowerFn *fn, MirValue map, const MsExpr *key_expr, MirTy ty) {
  const MirTyData *data = mir_ty_data(fn->cx->module, ty);
  const MirValue key = fn_operand_slot(fn, key_expr, true);
  if (key == MIR_NONE) {
    return MIR_NONE;
  }
  const MirImm key_ty = {.tag = MI_TY, .a = data->args[0]};
  const MirImm value_ty = {.tag = MI_TY, .a = data->args[1]};
  const MirValue key_desc = mir_b_emit(&fn->b, MOP_TypeDesc, NULL, 0, key_ty, MIR_PTR);
  const MirValue value_desc = mir_b_emit(&fn->b, MOP_TypeDesc, NULL, 0, value_ty, MIR_PTR);
  const MirValue out = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, value_ty, MIR_PTR);
  const MirValue operands[5] = {map, key_desc, value_desc, key, out};
  const MirValue found = fn_runtime_call(fn, mir_name(fn->cx->module, ms_span_of_text("msrt_map_get")), operands, 5, MIR_BOOL);
  const bool owns_value = mir_needs_drop(fn->cx->module, data->args[1]);
  const MirBlock hit = mir_b_new_block(&fn->b);
  const MirBlock miss = mir_b_new_block(&fn->b);
  mir_b_br_if(&fn->b, found, hit, NULL, 0, miss, NULL, 0);
  mir_b_seal_block(&fn->b, hit);
  mir_b_seal_block(&fn->b, miss);
  mir_b_switch_to(&fn->b, miss);
  fn_fault_missing_key(fn, key, data->args[0]);
  mir_b_switch_to(&fn->b, hit);
  return fn_emit(fn, owns_value ? MOP_Take : MOP_Load, &out, 1, value_ty, data->args[1]);
}

/* The address of the entry `place[key]?` names in a list or map, or a null pointer when there is none (a list index
 * out of range counts from nothing: a negative index is no entry). `entry_ty` is the entry's type. */
MirValue fn_entry_address(LowerFn *fn, MirValue container, const MsExpr *key_expr, MirTy *entry_ty) {
  const MirTy ty = mir_b_ty(&fn->b, container);
  const MirTyData *data = mir_ty_data(fn->cx->module, ty);
  if (data->kind == MK_OBJ && data->obj_class == MIR_OBJ_COLLECTION && data->nargs >= 2) {
    const MirValue key = fn_operand_slot(fn, key_expr, true);
    if (key == MIR_NONE) {
      return MIR_NONE;
    }
    const MirImm key_ty = {.tag = MI_TY, .a = data->args[0]};
    const MirImm value_ty = {.tag = MI_TY, .a = data->args[1]};
    const MirValue key_desc = mir_b_emit(&fn->b, MOP_TypeDesc, NULL, 0, key_ty, MIR_PTR);
    const MirValue value_desc = mir_b_emit(&fn->b, MOP_TypeDesc, NULL, 0, value_ty, MIR_PTR);
    const MirValue operands[4] = {container, key_desc, value_desc, key};
    const MirValue address = fn_runtime_call(fn, mir_name(fn->cx->module, ms_span_of_text("msrt_map_get_ptr")), operands, 4, MIR_PTR);
    *entry_ty = data->args[1];
    return address;
  }
  if (data->kind != MK_LIST) {
    (void)fn_fail(fn, "only a list or a map can be probed");
    return MIR_NONE;
  }
  const MirValue at = fn_expr(fn, key_expr, LW_BORROW);
  if (at == MIR_NONE) {
    return MIR_NONE;
  }
  const MirValue zero = mir_b_iconst(&fn->b, 0);
  const MirValue length = mir_b_emit(&fn->b, MOP_ListLen, &container, 1, (MirImm){0}, MIR_INT);
  const MirValue not_negative = mir_b_icmp(&fn->b, MCC_GE, at, zero);
  const MirValue below = mir_b_icmp(&fn->b, MCC_LT, at, length);
  const MirValue inside = mir_b_select(&fn->b, not_negative, below, mir_b_bconst(&fn->b, false));
  const MirBlock hit = mir_b_new_block(&fn->b);
  const MirBlock miss = mir_b_new_block(&fn->b);
  const MirBlock join = mir_b_new_block(&fn->b);
  const MirValue address = mir_b_add_block_param(&fn->b, join, MIR_PTR, MM_BORROW);
  mir_b_br_if(&fn->b, inside, hit, NULL, 0, miss, NULL, 0);
  mir_b_seal_block(&fn->b, hit);
  mir_b_seal_block(&fn->b, miss);
  mir_b_switch_to(&fn->b, hit);
  const MirValue operands[2] = {container, at};
  const MirValue found = mir_b_emit(&fn->b, MOP_ListAddrU, operands, 2, (MirImm){0}, MIR_PTR);
  mir_b_br(&fn->b, join, &found, 1);
  mir_b_switch_to(&fn->b, miss);
  const MirValue absent = mir_b_emit(&fn->b, MOP_PtrNull, NULL, 0, (MirImm){0}, MIR_PTR);
  mir_b_br(&fn->b, join, &absent, 1);
  mir_b_seal_block(&fn->b, join);
  mir_b_switch_to(&fn->b, join);
  *entry_ty = data->elem;
  return address;
}

/* `container[key] = value` for an element of a list or map the enclosing assignment took a copy of: the container's
 * own `set` (a list) or `add` (a map) stores it. */
bool fn_set_element(LowerFn *fn, const MsExpr *container, const MsExpr *key, MirValue value) {
  MsTyTable *types = &fn->cx->program->types;
  const MsTy owner = ms_ty_subst(types, ms_facts_type(fn->facts, container->id), fn->subst.vars, fn->subst.args, fn->subst.count);
  const MirValue receiver = fn_expr(fn, container, LW_BORROW);
  const MirValue at = receiver == MIR_NONE ? MIR_NONE : fn_expr(fn, key, LW_BORROW);
  if (at == MIR_NONE) {
    return false;
  }
  const bool map = ms_ty_is(types, owner, MS_BUILTIN_Map);
  const bool owns_key = map && mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, at));
  /* A map stores its key only when the entry is new: an entry that exists takes the value where it lies and keeps its
   * own key, so a borrowed key is copied by the insert alone. */
  MirBlock join = MIR_NONE;
  if (owns_key) {
    MirTy entry_ty = MIR_VOID;
    const MirValue address = fn_entry_address(fn, receiver, key, &entry_ty);
    if (address == MIR_NONE) {
      return false;
    }
    const MirValue absent = mir_b_emit(&fn->b, MOP_PtrIsNull, &address, 1, (MirImm){0}, MIR_BOOL);
    const MirBlock insert = mir_b_new_block(&fn->b);
    const MirBlock replace = mir_b_new_block(&fn->b);
    join = mir_b_new_block(&fn->b);
    mir_b_br_if(&fn->b, absent, insert, NULL, 0, replace, NULL, 0);
    mir_b_seal_block(&fn->b, insert);
    mir_b_seal_block(&fn->b, replace);
    mir_b_switch_to(&fn->b, replace);
    const bool drops = mir_needs_drop(fn->cx->module, entry_ty);
    if (drops) {
      const MirValue old = mir_b_emit(&fn->b, MOP_Take, &address, 1, (MirImm){.tag = MI_TY, .a = entry_ty}, entry_ty);
      (void)mir_b_emit(&fn->b, MOP_Drop, &old, 1, (MirImm){0}, MIR_NONE);
    }
    const MirValue replaced[2] = {address, value};
    (void)mir_b_emit(&fn->b, drops ? MOP_Put : MOP_Store, replaced, 2, (MirImm){0}, MIR_NONE);
    mir_b_br(&fn->b, join, NULL, 0);
    mir_b_switch_to(&fn->b, insert);
  }
  const MirValue stored_key = owns_key ? fn_emit(fn, MOP_Clone, &at, 1, (MirImm){0}, mir_b_ty(&fn->b, at)) : at; /* the insert's own copy of the key */
  if (stored_key == MIR_NONE) {
    return false;
  }
  const MirValue args[3] = {receiver, stored_key, value};
  MirValue out = MIR_NONE;
  const MsSpan operation = ms_span_of_text(map ? "add" : "set");
  fn->native_arg_moves = (map && stored_key != at ? 1u << 1 : 0u) | (1u << 2); /* the stored value (and key) are owned and held by no scope: the container takes them */
  const bool done = fn_native_on(fn, container, owner, operation, 3, args, MIR_VOID, &out);
  fn->native_arg_moves = 0;
  if (!done) {
    return fn_fail(fn, "an element of this container cannot be assigned yet");
  }
  if (join != MIR_NONE) {
    mir_b_br(&fn->b, join, NULL, 0);
    mir_b_seal_block(&fn->b, join);
    mir_b_switch_to(&fn->b, join);
  }
  return !fn->failed;
}

/* compiler/lower/lower_map_entry.c: reading a map entry by key: the address of the entry, and the fault of a missing key. */
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_analysis.h"

/* Ends the current block with the fault of a missing map key: `key` is the slot holding the key of type `key_ty`. */
void fn_fault_missing_key(LowerFn *fn, MirValue key, MirTy key_ty) {
  const MirImm of_key = {.tag = MI_TY, .a = key_ty};
  const MirValue missing = mir_b_emit(&fn->b, MOP_Load, &key, 1, of_key, key_ty);
  const MirValue text = fn_value_repr(fn, missing, key_ty);
  const MirValue prefix_lit = mir_b_emit(&fn->b, MOP_StrLit, NULL, 0,
                                         (MirImm){.tag = MI_STR, .a = mir_add_string(fn->cx->module, ms_span_of_text("map key not found: "))},
                                         MIR_STR);
  const MirValue parts[2] = {prefix_lit, text};
  const MirValue message = fn_runtime_call(fn, mir_name(fn->cx->module, ms_span_of_text("msrt_string_concat")), parts, 2, MIR_STR);
  (void)fn_runtime_call(fn, mir_name(fn->cx->module, ms_span_of_text("msrt_fault_string")), &message, 1, MIR_VOID);
  mir_b_unreachable(&fn->b);
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

/* compiler/lower/lower_list.c: list literals. Each element is evaluated left to right and the list takes ownership
 * of it: a droppable element that is only borrowed (a name, a literal) is cloned first. */
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_analysis.h"

MirValue fn_list(LowerFn *fn, const MsExpr *expr) {
  MirTy list_ty = fn_type(fn, ms_facts_type(fn->facts, expr->id));
  const MirTyData *data = mir_ty_data(fn->cx->module, list_ty);
  if (data->kind != MK_LIST && fn->hint != MIR_VOID && mir_ty_data(fn->cx->module, fn->hint)->kind == MK_LIST) {
    /* The checker left the literal's type open (`get_or([])`): the parameter it fills gives it. */
    list_ty = fn->hint;
    data = mir_ty_data(fn->cx->module, list_ty);
  }
  if (data->kind != MK_LIST) {
    (void)fn_fail(fn, "a list literal is not typed as a list");
    return MIR_NONE;
  }
  const uint32_t count = expr->u.list.len;
  if (count == 0) {
    const MirValue capacity = mir_b_iconst(&fn->b, 0);
    const MirValue fresh = mir_b_list_new(&fn->b, data->elem, capacity);
    fn_own_result(fn, fresh);
    return fresh;
  }
  MirValue *items = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, MirValue, count);
  for (uint32_t index = 0; index < count; index++) {
    items[index] = fn_expr(fn, expr->u.list.ptr[index], LW_MOVE);
    if (items[index] == MIR_NONE) {
      return MIR_NONE;
    }
    if (!mir_needs_drop(fn->cx->module, data->elem)) {
      continue;
    }
    if (!fn_fresh_owner(fn, items[index])) {
      items[index] = fn_implicit_clone(fn, items[index], false);
    } /* a fresh owner stays the scope's until `list.lit` consumes it: a later element may unwind */
  }
  mir_b_set_loc(&fn->b, fn_loc(fn, expr->pos));
  return fn_emit(fn, MOP_ListLit, items, count, (MirImm){0}, list_ty);
}

/* `list[index]`: the element, borrowed from the list; a droppable element wanted as an owner is cloned. */
MirValue fn_index(LowerFn *fn, const MsExpr *expr, LowerWant want) {
  MsExpr *left = NULL;
  MsExpr *index = NULL;
  if (!ms_expr_index(expr, &left, &index)) {
    (void)fn_fail(fn, "this bracket is not an index");
    return MIR_NONE;
  }
  const MirValue read = fn_expr(fn, left, LW_BORROW);
  if (read == MIR_NONE) {
    return MIR_NONE;
  }
  const MirValue list = fn_closing_indexed(fn, expr, read);
  const MirTy container = mir_b_ty(&fn->b, list);
  const MirTyData *data = mir_ty_data(fn->cx->module, container);
  if (data->kind == MK_OBJ && data->obj_class == MIR_OBJ_COLLECTION && data->nargs >= 2) {
    mir_b_set_loc(&fn->b, fn_loc(fn, expr->pos));
    return fn_map_index(fn, list, index, container);
  }
  const MirValue at = fn_expr(fn, index, LW_BORROW);
  if (at == MIR_NONE) {
    return MIR_NONE;
  }
  if (data->kind == MK_BYTES) { /* a byte of a Bytes value */
    mir_b_set_loc(&fn->b, fn_loc(fn, expr->pos));
    const MirValue pair[2] = {list, at};
    return mir_b_emit(&fn->b, MOP_ListGet, pair, 2, (MirImm){0}, MIR_UINT8);
  }
  if (data->kind != MK_LIST) {
    (void)fn_fail(fn, "only a list or bytes can be indexed for now");
    return MIR_NONE;
  }
  mir_b_set_loc(&fn->b, fn_loc(fn, expr->pos));
  const MirValue args[2] = {list, at};
  const MirValue element = mir_b_emit(&fn->b, MOP_ListGet, args, 2, (MirImm){0}, data->elem);
  if (want == LW_MOVE && mir_needs_drop(fn->cx->module, data->elem)) {
    return fn_implicit_clone(fn, element, true);
  }
  return element;
}

/* `Set[T](values)`: an empty set, then each element of the list added in order (the set keeps a copy of its keys). */
MirValue fn_set_from_list(LowerFn *fn, MirValue values, MirTy ty) {
  MirModule *module = fn->cx->module;
  const MirTyData *list = mir_ty_data(module, mir_b_ty(&fn->b, values));
  const MirTyData *set = mir_ty_data(module, ty);
  if (list->kind != MK_LIST || set->kind != MK_OBJ || set->nargs < 1 || set->args[0] != list->elem) {
    (void)fn_fail(fn, "a set is built from a list of its elements");
    return MIR_NONE;
  }
  const MirTy elem_ty = list->elem;
  const MirImm set_imm = {.tag = MI_TY, .a = ty};
  const MirImm elem_imm = {.tag = MI_TY, .a = elem_ty};
  const MirValue empty = fn_empty_map(fn, ty);
  (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &empty, 1, (MirImm){0}, MIR_NONE);
  const MirValue set_slot = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, set_imm, MIR_PTR);
  const MirValue created[2] = {set_slot, empty};
  (void)mir_b_emit(&fn->b, MOP_Put, created, 2, (MirImm){0}, MIR_NONE);
  const MirValue desc = mir_b_emit(&fn->b, MOP_TypeDesc, NULL, 0, elem_imm, MIR_PTR);
  const MirBlock head = mir_b_new_block(&fn->b);
  const MirBlock body = mir_b_new_block(&fn->b);
  const MirBlock exit = mir_b_new_block(&fn->b);
  const MirValue index = mir_b_add_block_param(&fn->b, head, MIR_INT, MM_BORROW);
  const MirValue zero = mir_b_iconst(&fn->b, 0);
  mir_b_br(&fn->b, head, &zero, 1);
  mir_b_switch_to(&fn->b, head);
  const MirValue length = mir_b_emit(&fn->b, MOP_ListLen, &values, 1, (MirImm){0}, MIR_INT);
  mir_b_br_if(&fn->b, mir_b_icmp(&fn->b, MCC_LT, index, length), body, NULL, 0, exit, NULL, 0);
  mir_b_seal_block(&fn->b, body);
  mir_b_seal_block(&fn->b, exit);
  mir_b_switch_to(&fn->b, body);
  const MirValue at[2] = {values, index};
  const MirValue element = mir_b_emit(&fn->b, MOP_ListGet, at, 2, (MirImm){0}, elem_ty);
  const MirValue key_slot = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, elem_imm, MIR_PTR);
  const MirValue stored[2] = {key_slot, element};
  (void)mir_b_emit(&fn->b, MOP_Store, stored, 2, (MirImm){0}, MIR_NONE);
  const MirValue add_args[3] = {set_slot, desc, key_slot};
  (void)fn_runtime_call(fn, mir_name(module, ms_span_of_text("msrt_set_add_copy")), add_args, 3, MIR_VOID);
  const MirValue stepped = mir_b_binop(&fn->b, MOP_IAdd, index, mir_b_iconst(&fn->b, 1));
  mir_b_br(&fn->b, head, &stepped, 1);
  mir_b_seal_block(&fn->b, head);
  mir_b_switch_to(&fn->b, exit);
  return fn_emit(fn, MOP_Take, &set_slot, 1, set_imm, ty);
}

/* `list.group_by(key)`: a map from each distinct key to the (cloned) elements that produced it, in first-seen order.
 * A closure cannot be called from the runtime, so the loop is expanded here: each element's key is looked up; a present
 * group is taken out of its entry, grown and put back where it lies, and an absent one starts as `[x]`. */
bool fn_list_group_by(LowerFn *fn, const MirValue *args, MirTy ret, MirValue *out) {
  MirModule *module = fn->cx->module;
  const MirTy list_ty = mir_b_ty(&fn->b, args[0]);
  const MirTyData *list = mir_ty_data(module, list_ty);
  const MirTyData *map = mir_ty_data(module, ret);
  if (list->kind != MK_LIST || map->kind != MK_OBJ || map->nargs < 2 || mir_ty_data(module, map->args[1])->kind != MK_LIST) {
    return false;
  }
  const MirTy key_ty = map->args[0];
  const MirTy group_ty = map->args[1];
  const MirTy elem_ty = list->elem;
  const MirImm map_imm = {.tag = MI_TY, .a = ret};
  const MirImm key_imm = {.tag = MI_TY, .a = key_ty};
  const MirImm group_imm = {.tag = MI_TY, .a = group_ty};
  const MirValue empty = fn_empty_map(fn, ret);
  (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &empty, 1, (MirImm){0}, MIR_NONE);
  const MirValue map_slot = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, map_imm, MIR_PTR);
  const MirValue created[2] = {map_slot, empty};
  (void)mir_b_emit(&fn->b, MOP_Put, created, 2, (MirImm){0}, MIR_NONE);
  const MirValue key_desc = mir_b_emit(&fn->b, MOP_TypeDesc, NULL, 0, key_imm, MIR_PTR);
  const MirValue group_desc = mir_b_emit(&fn->b, MOP_TypeDesc, NULL, 0, group_imm, MIR_PTR);
  const MirBlock head = mir_b_new_block(&fn->b);
  const MirBlock body = mir_b_new_block(&fn->b);
  const MirBlock exit = mir_b_new_block(&fn->b);
  const MirValue index = mir_b_add_block_param(&fn->b, head, MIR_INT, MM_BORROW);
  const MirValue zero = mir_b_iconst(&fn->b, 0);
  mir_b_br(&fn->b, head, &zero, 1);
  mir_b_switch_to(&fn->b, head);
  const MirValue length = mir_b_emit(&fn->b, MOP_ListLen, &args[0], 1, (MirImm){0}, MIR_INT);
  mir_b_br_if(&fn->b, mir_b_icmp(&fn->b, MCC_LT, index, length), body, NULL, 0, exit, NULL, 0);
  mir_b_seal_block(&fn->b, body);
  mir_b_seal_block(&fn->b, exit);
  mir_b_switch_to(&fn->b, body);
  const MirValue at[2] = {args[0], index};
  const MirValue element = mir_b_emit(&fn->b, MOP_ListGet, at, 2, (MirImm){0}, elem_ty);
  const MirValue call[2] = {args[1], element};
  const MirValue key = mir_b_emit(&fn->b, MOP_CallInd, call, 2, (MirImm){0}, key_ty);
  const MirValue probe = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, key_imm, MIR_PTR);
  const MirValue looked[2] = {probe, key};
  (void)mir_b_emit(&fn->b, MOP_Store, looked, 2, (MirImm){0}, MIR_NONE);
  const MirValue current = mir_b_emit(&fn->b, MOP_Load, &map_slot, 1, map_imm, ret);
  const MirValue probe_args[4] = {current, key_desc, group_desc, probe};
  const MirValue found = fn_runtime_call(fn, mir_name(module, ms_span_of_text("msrt_map_get_ptr")), probe_args, 4, MIR_PTR);
  const MirValue absent = mir_b_emit(&fn->b, MOP_PtrIsNull, &found, 1, (MirImm){0}, MIR_BOOL);
  const MirBlock add = mir_b_new_block(&fn->b);
  const MirBlock grow = mir_b_new_block(&fn->b);
  const MirBlock next = mir_b_new_block(&fn->b);
  mir_b_br_if(&fn->b, absent, add, NULL, 0, grow, NULL, 0);
  mir_b_seal_block(&fn->b, add);
  mir_b_seal_block(&fn->b, grow);
  const bool owns = mir_needs_drop(module, elem_ty);
  mir_b_switch_to(&fn->b, add);
  const MirValue fresh = mir_b_emit(&fn->b, MOP_ListLit, NULL, 0, (MirImm){0}, group_ty);
  const MirValue first = owns ? mir_b_emit(&fn->b, MOP_Clone, &element, 1, (MirImm){0}, elem_ty) : element;
  const MirValue started_args[2] = {fresh, first};
  const MirValue started = mir_b_emit(&fn->b, MOP_ListPush, started_args, 2, (MirImm){0}, group_ty);
  const MirValue key_slot = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, key_imm, MIR_PTR);
  const MirValue key_put[2] = {key_slot, key};
  (void)mir_b_emit(&fn->b, MOP_Put, key_put, 2, (MirImm){0}, MIR_NONE);
  const MirValue group_slot = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, group_imm, MIR_PTR);
  const MirValue group_put[2] = {group_slot, started};
  (void)mir_b_emit(&fn->b, MOP_Put, group_put, 2, (MirImm){0}, MIR_NONE);
  const MirValue add_args[5] = {map_slot, key_desc, group_desc, key_slot, group_slot};
  (void)fn_runtime_call(fn, mir_name(module, ms_span_of_text("msrt_map_add")), add_args, 5, MIR_VOID);
  mir_b_br(&fn->b, next, NULL, 0);
  mir_b_switch_to(&fn->b, grow);
  const MirValue taken = mir_b_emit(&fn->b, MOP_Take, &found, 1, group_imm, group_ty);
  const MirValue more = owns ? mir_b_emit(&fn->b, MOP_Clone, &element, 1, (MirImm){0}, elem_ty) : element;
  const MirValue grown_args[2] = {taken, more};
  const MirValue grown = mir_b_emit(&fn->b, MOP_ListPush, grown_args, 2, (MirImm){0}, group_ty);
  const MirValue back[2] = {found, grown};
  (void)mir_b_emit(&fn->b, MOP_Put, back, 2, (MirImm){0}, MIR_NONE);
  if (mir_needs_drop(module, key_ty)) {
    (void)mir_b_emit(&fn->b, MOP_Drop, &key, 1, (MirImm){0}, MIR_NONE);
  }
  mir_b_br(&fn->b, next, NULL, 0);
  mir_b_seal_block(&fn->b, next);
  mir_b_switch_to(&fn->b, next);
  const MirValue one = mir_b_iconst(&fn->b, 1);
  const MirValue stepped = mir_b_binop(&fn->b, MOP_IAdd, index, one);
  mir_b_br(&fn->b, head, &stepped, 1);
  mir_b_seal_block(&fn->b, head);
  mir_b_switch_to(&fn->b, exit);
  *out = fn_emit(fn, MOP_Take, &map_slot, 1, map_imm, ret);
  return true;
}

/* `map_from_entries(entries)`: an empty map, then the key and value of each entry (copies; the list keeps its own) added
 * in order, so a later entry for a key replaces the value of an earlier one. */
bool fn_map_from_entries(LowerFn *fn, const MirValue *args, MirTy ret, MirValue *out) {
  MirModule *module = fn->cx->module;
  const MirTyData *list = mir_ty_data(module, mir_b_ty(&fn->b, args[0]));
  const MirTyData *map = mir_ty_data(module, ret);
  const MirTyData *entry_data = list->kind == MK_LIST ? mir_ty_data(module, list->elem) : NULL;
  if (entry_data == NULL || entry_data->kind != MK_TYPE || map->kind != MK_OBJ || map->nargs < 2) {
    return false;
  }
  const MirTy entry_ty = list->elem;
  const MirTy key_ty = map->args[0];
  const MirTy value_ty = map->args[1];
  const MirImm map_imm = {.tag = MI_TY, .a = ret};
  const MirImm key_imm = {.tag = MI_TY, .a = key_ty};
  const MirImm value_imm = {.tag = MI_TY, .a = value_ty};
  const MirValue empty = fn_empty_map(fn, ret);
  (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &empty, 1, (MirImm){0}, MIR_NONE);
  const MirValue map_slot = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, map_imm, MIR_PTR);
  const MirValue created[2] = {map_slot, empty};
  (void)mir_b_emit(&fn->b, MOP_Put, created, 2, (MirImm){0}, MIR_NONE);
  const MirValue key_desc = mir_b_emit(&fn->b, MOP_TypeDesc, NULL, 0, key_imm, MIR_PTR);
  const MirValue value_desc = mir_b_emit(&fn->b, MOP_TypeDesc, NULL, 0, value_imm, MIR_PTR);
  const MirBlock head = mir_b_new_block(&fn->b);
  const MirBlock body = mir_b_new_block(&fn->b);
  const MirBlock exit = mir_b_new_block(&fn->b);
  const MirValue index = mir_b_add_block_param(&fn->b, head, MIR_INT, MM_BORROW);
  const MirValue zero = mir_b_iconst(&fn->b, 0);
  mir_b_br(&fn->b, head, &zero, 1);
  mir_b_switch_to(&fn->b, head);
  const MirValue length = mir_b_emit(&fn->b, MOP_ListLen, &args[0], 1, (MirImm){0}, MIR_INT);
  mir_b_br_if(&fn->b, mir_b_icmp(&fn->b, MCC_LT, index, length), body, NULL, 0, exit, NULL, 0);
  mir_b_seal_block(&fn->b, body);
  mir_b_seal_block(&fn->b, exit);
  mir_b_switch_to(&fn->b, body);
  const MirValue at[2] = {args[0], index};
  const MirValue entry = mir_b_emit(&fn->b, MOP_ListGet, at, 2, (MirImm){0}, entry_ty);
  const MirImm key_field = {.tag = MI_FIELD, .a = entry_data->id, .b = 0};
  const MirImm value_field = {.tag = MI_FIELD, .a = entry_data->id, .b = 1};
  MirValue key = mir_b_emit(&fn->b, MOP_TypeGet, &entry, 1, key_field, key_ty);
  MirValue value = mir_b_emit(&fn->b, MOP_TypeGet, &entry, 1, value_field, value_ty);
  key = mir_needs_drop(module, key_ty) ? mir_b_emit(&fn->b, MOP_Clone, &key, 1, (MirImm){0}, key_ty) : key;
  value = mir_needs_drop(module, value_ty) ? mir_b_emit(&fn->b, MOP_Clone, &value, 1, (MirImm){0}, value_ty) : value;
  const MirValue key_slot = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, key_imm, MIR_PTR);
  const MirValue value_slot = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, value_imm, MIR_PTR);
  const MirValue key_put[2] = {key_slot, key};
  const MirValue value_put[2] = {value_slot, value};
  (void)mir_b_emit(&fn->b, mir_needs_drop(module, key_ty) ? MOP_Put : MOP_Store, key_put, 2, (MirImm){0}, MIR_NONE);
  (void)mir_b_emit(&fn->b, mir_needs_drop(module, value_ty) ? MOP_Put : MOP_Store, value_put, 2, (MirImm){0}, MIR_NONE);
  const MirValue add_args[5] = {map_slot, key_desc, value_desc, key_slot, value_slot};
  (void)fn_runtime_call(fn, mir_name(module, ms_span_of_text("msrt_map_add")), add_args, 5, MIR_VOID);
  const MirValue stepped = mir_b_binop(&fn->b, MOP_IAdd, index, mir_b_iconst(&fn->b, 1));
  mir_b_br(&fn->b, head, &stepped, 1);
  mir_b_seal_block(&fn->b, head);
  mir_b_switch_to(&fn->b, exit);
  *out = fn_emit(fn, MOP_Take, &map_slot, 1, map_imm, ret);
  return true;
}

MirValue fn_map_literal(LowerFn *fn, const MsExpr *expr) {
  MirTy ty = fn_type(fn, ms_facts_type(fn->facts, expr->id));
  const MirTyData *data = mir_ty_data(fn->cx->module, ty);
  if (fn->hint != MIR_VOID && (data->kind != MK_OBJ || data->obj_class != MIR_OBJ_COLLECTION || data->nargs < 2)) {
    ty = fn->hint; /* the checker left the literal's type open: the parameter it fills gives it */
    data = mir_ty_data(fn->cx->module, ty);
  }
  if (data->kind != MK_OBJ || data->obj_class != MIR_OBJ_COLLECTION || data->nargs < 2) {
    (void)fn_fail(fn, "a map literal is not typed as a map");
    return MIR_NONE;
  }
  const MirValue empty = fn_empty_map(fn, ty);
  (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &empty, 1, (MirImm){0}, MIR_NONE);
  const MirImm of_map = {.tag = MI_TY, .a = ty};
  const MirValue map = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, of_map, MIR_PTR);
  const MirValue created[2] = {map, empty};
  (void)mir_b_emit(&fn->b, MOP_Put, created, 2, (MirImm){0}, MIR_NONE);
  const MirImm key_ty = {.tag = MI_TY, .a = data->args[0]};
  const MirImm value_ty = {.tag = MI_TY, .a = data->args[1]};
  const MsName add = mir_name(fn->cx->module, ms_span_of_text("msrt_map_add"));
  for (uint32_t at = 0; at < expr->u.map.len; at++) {
    const MirValue key = fn_operand_slot(fn, expr->u.map.ptr[at].key, false);
    const MirValue value = key == MIR_NONE ? MIR_NONE : fn_operand_slot(fn, expr->u.map.ptr[at].value, false);
    if (value == MIR_NONE) {
      return MIR_NONE;
    }
    const MirValue key_desc = mir_b_emit(&fn->b, MOP_TypeDesc, NULL, 0, key_ty, MIR_PTR);
    const MirValue value_desc = mir_b_emit(&fn->b, MOP_TypeDesc, NULL, 0, value_ty, MIR_PTR);
    const MirValue operands[5] = {map, key_desc, value_desc, key, value};
    (void)fn_runtime_call(fn, add, operands, 5, MIR_VOID);
  }
  return fn_emit(fn, MOP_Take, &map, 1, of_map, ty);
}

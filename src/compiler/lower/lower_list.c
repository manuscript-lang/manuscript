/* compiler/lower/lower_list.c: list literals. Each element is evaluated left to right and the list takes ownership
 * of it: a droppable element that is only borrowed (a name, a literal) is cloned first. */
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_analysis.h"

/* Whether `value` is the result of the instruction just emitted and an owned one. */
static bool is_fresh_owner(const LowerFn *fn, MirValue value) {
  const MirInstList *insts = &fn->b.func.blocks.ptr[fn->b.cur].insts;
  MirMode mode = MM_BORROW;
  if (insts->len == 0 || insts->ptr[insts->len - 1].res != value) {
    return false;
  }
  return mir_result_mode(fn->cx->module, &fn->b.func, &insts->ptr[insts->len - 1], &mode) && mode == MM_MOVE;
}

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
    return mir_b_list_new(&fn->b, data->elem, capacity);
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
    if (is_fresh_owner(fn, items[index])) {
      (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &items[index], 1, (MirImm){0}, MIR_NONE); /* the list owns it */
    } else {
      items[index] = fn_implicit_clone(fn, items[index], false);
    }
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
  const MirValue list = fn_expr(fn, left, LW_BORROW);
  if (list == MIR_NONE) {
    return MIR_NONE;
  }
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

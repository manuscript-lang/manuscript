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
  const MirTy list_ty = fn_type(fn, ms_facts_type(fn->facts, expr->id));
  const MirTyData *data = mir_ty_data(fn->cx->module, list_ty);
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
      items[index] = mir_b_emit(&fn->b, MOP_Clone, &items[index], 1, (MirImm){0}, data->elem);
    }
  }
  mir_b_set_loc(&fn->b, fn_loc(fn, expr->pos));
  return fn_emit(fn, MOP_ListLit, items, count, (MirImm){0}, list_ty);
}

/* compiler/lower/lower_or.c: `x or d` over a nullable `x`. */
#include "compiler/lower/lower_fn.h"
#include "compiler/own/result_borrows.h"
#include "compiler/mir/mir_analysis.h"

/* `x or d` over a nullable `x`: the payload when `x` holds one, else `d`, which runs only then. The result owns what it
 * holds: a payload view is copied, a fresh `x` gives its payload up. */
/* Whether a call's result is a part of one of its arguments (`xs.first()`), which the caller's owner keeps. */
static bool call_views_argument(const LowerFn *fn, const MsExpr *call) {
  const MsCall *fact = ms_facts_call(fn->facts, call->id);
  if (fact == NULL) {
    return false;
  }
  for (uint32_t position = 0; position <= fact->arg_count; position++) {
    if (ms_own_call_borrows(fn->cx->program, fact, position)) {
      return true;
    }
  }
  return false;
}

MirValue fn_lower_or_null(LowerFn *fn, const MsExpr *expr) {
  const MirTy result_ty = fn_type(fn, ms_facts_type(fn->facts, expr->id));
  /* A name this expression moves, or reads for the last time, gives its payload up as `if v := name { ... }` does. */
  const MsExpr *named = expr->u.bin.left;
  const bool moving = (named->kind == MS_E_CALL && ms_facts_use(fn->facts, named->id) == MS_USE_MOVE) ||
                      (named->kind == MS_E_NAME && (fn->narrow_take == expr || ms_facts_use(fn->facts, named->id) == MS_USE_MOVE ||
                                                   ms_facts_use(fn->facts, expr->id) == MS_USE_MOVE ||
                                                   (fn->facts->last != NULL && fn->facts->last[named->id] != 0)));
  const MirValue left = fn_expr(fn, named, moving ? LW_MOVE : LW_BORROW);
  if (left == MIR_NONE || result_ty == MIR_VOID) {
    return MIR_NONE;
  }
  const MirTy opt_ty = mir_b_ty(&fn->b, left);
  const bool fresh_left = fn_fresh_owner(fn, left) || (named->kind == MS_E_CALL && !call_views_argument(fn, named) && fn_owns_result(fn, left)); /* asked where `left` was made, before the branch */
  const MirVar result = mir_b_declare_var(&fn->b, result_ty, MM_MOVE);
  const MirValue present = mir_b_emit(&fn->b, MOP_OptIsSome, &left, 1, (MirImm){0}, MIR_BOOL);
  const MirBlock some_block = mir_b_new_block(&fn->b);
  const MirBlock null_block = mir_b_new_block(&fn->b);
  const MirBlock join = mir_b_new_block(&fn->b);
  mir_b_br_if(&fn->b, present, some_block, NULL, 0, null_block, NULL, 0);
  mir_b_seal_block(&fn->b, some_block);
  mir_b_seal_block(&fn->b, null_block);
  mir_b_switch_to(&fn->b, some_block);
  /* A temporary (`f()?`, a call) gives its payload up; a name or field gives it up only where it is moved. */
  const bool place = named->kind == MS_E_NAME || named->kind == MS_E_MEMBER || named->kind == MS_E_INDEX;
  const bool owns = (fresh_left && (named->kind != MS_E_NAME || moving)) || (named->kind == MS_E_CALL && moving) ||
                    (!place && named->kind != MS_E_CALL && fresh_left);
  /* `x or panic(..)` read in place: nothing else reaches the join, so the payload stays a view of `x` */
  const bool view_only = !owns && fn->or_view == expr && ms_ty_is(&fn->cx->program->types, ms_facts_type(fn->facts, expr->u.bin.right->id), MS_BUILTIN_Never) &&
                         ms_facts_use(fn->facts, expr->id) != MS_USE_MOVE;
  MirTy payload_ty = MIR_VOID;
  MirValue payload;
  if (owns) {
    payload = fn_take_payload(fn, left, &payload_ty);
  } else {
    payload_ty = mir_ty_data(fn->cx->module, opt_ty)->elem;
    payload = mir_b_emit(&fn->b, MOP_OptGet, &left, 1, (MirImm){0}, payload_ty);
    if (mir_needs_drop(fn->cx->module, payload_ty) && !view_only) {
      payload = fn_implicit_clone(fn, payload, true);
      if (payload == MIR_NONE) {
        return MIR_NONE;
      }
    }
  }
  if (mir_b_ty(&fn->b, payload) != result_ty) { /* the result is nullable too: `x or y` with `y: T?` */
    payload = mir_b_emit(&fn->b, MOP_OptSome, &payload, 1, (MirImm){0}, result_ty);
  }
  if ((mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, payload))) && !view_only) {
    (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &payload, 1, (MirImm){0}, MIR_NONE);
  }
  mir_b_def_var(&fn->b, result, payload);
  mir_b_br(&fn->b, join, NULL, 0);
  mir_b_switch_to(&fn->b, null_block);
  (void)fn_scope_begin(fn);
  const bool saved_temps = fn->temps;
  fn->temps = saved_temps || fn_expr_has_temporary(fn, expr->u.bin.right);
  MirValue other = fn_expr(fn, expr->u.bin.right, LW_MOVE);
  fn->temps = saved_temps;
  if (fn->terminated) { /* `x or panic(..)`: the right side never returns, so only the present branch reaches the join */
    fn->nopen--;
    fn->terminated = false;
    mir_b_seal_block(&fn->b, join);
    mir_b_switch_to(&fn->b, join);
    const MirValue only = mir_b_use_var(&fn->b, result);
    if ((mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, only))) && !view_only) {
      fn_own(fn, fn_scope(fn), only);
    }
    return only;
  }
  if (other == MIR_NONE) {
    return MIR_NONE;
  }
  if (mir_b_ty(&fn->b, other) != result_ty) {
    other = mir_b_emit(&fn->b, MOP_OptSome, &other, 1, (MirImm){0}, result_ty);
  }
  if (mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, other))) {
    (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &other, 1, (MirImm){0}, MIR_NONE);
  }
  mir_b_def_var(&fn->b, result, other);
  fn_scope_end(fn);
  mir_b_br(&fn->b, join, NULL, 0);
  mir_b_seal_block(&fn->b, join);
  mir_b_switch_to(&fn->b, join);
  const MirValue joined = mir_b_use_var(&fn->b, result);
  if (mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, joined))) {
    fn_own(fn, fn_scope(fn), joined);
  }
  return joined;
}

/* `left && right` and `left || right`: the right operand runs only when the left does not decide the result. */
MirValue fn_lower_logical(LowerFn *fn, const MsExpr *expr) {
  const bool is_and = expr->op == MS_B_AND;
  const MirValue left = fn_expr(fn, expr->u.bin.left, LW_BORROW);
  if (left == MIR_NONE) {
    return MIR_NONE;
  }
  const MirBlock rhs = mir_b_new_block(&fn->b);
  const MirBlock decided = mir_b_new_block(&fn->b);
  const MirBlock join = mir_b_new_block(&fn->b);
  const MirValue result = mir_b_add_block_param(&fn->b, join, MIR_BOOL, MM_BORROW);
  mir_b_br_if(&fn->b, left, is_and ? rhs : decided, NULL, 0, is_and ? decided : rhs, NULL, 0);
  mir_b_seal_block(&fn->b, rhs);
  mir_b_seal_block(&fn->b, decided);
  mir_b_switch_to(&fn->b, decided);
  const MirValue known = mir_b_bconst(&fn->b, !is_and);
  mir_b_br(&fn->b, join, &known, 1);
  mir_b_switch_to(&fn->b, rhs);
  (void)fn_scope_begin(fn);
  const bool saved_temps = fn->temps;
  fn->temps = saved_temps || fn_expr_has_temporary(fn, expr->u.bin.right); /* the operand's temporaries close with it */
  const MirValue right = fn_expr(fn, expr->u.bin.right, LW_BORROW);
  fn->temps = saved_temps;
  fn_scope_end(fn);
  if (right == MIR_NONE) {
    return MIR_NONE;
  }
  mir_b_br(&fn->b, join, &right, 1);
  mir_b_seal_block(&fn->b, join);
  mir_b_switch_to(&fn->b, join);
  return result;
}

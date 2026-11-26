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

/* `x or d` read in place, with `x` left where it is: the some branch answers a view of the payload; the null branch moves
 * `d` into a holder (an optional the enclosing scope owns, empty on the some path) and answers a view of that. */
static MirValue lower_or_view(LowerFn *fn, const MsExpr *expr, MirValue left, MirValue present, MirTy opt_ty, MirTy result_ty,
                              MirBlock some_block, MirBlock null_block, MirBlock join) {
  (void)present;
  const MirVar either = mir_b_declare_var(&fn->b, opt_ty, MM_BORROW);
  const MirVar holder = mir_b_declare_var(&fn->b, opt_ty, MM_MOVE);
  (void)some_block;
  const MirValue empty = mir_b_emit(&fn->b, MOP_OptNone, NULL, 0, (MirImm){0}, opt_ty);
  mir_b_def_var(&fn->b, either, left);
  mir_b_def_var(&fn->b, holder, empty);
  mir_b_br(&fn->b, join, NULL, 0);
  mir_b_switch_to(&fn->b, null_block);
  (void)fn_scope_begin(fn);
  const bool saved_temps = fn->temps;
  fn->temps = saved_temps || fn_expr_has_temporary(fn, expr->u.bin.right);
  /* A name the caller keeps alive (a `hold` parameter, a local) is answered as a view of itself, not moved into the holder. */
  const bool place = expr->u.bin.right->kind == MS_E_NAME;
  MirValue other = fn_expr(fn, expr->u.bin.right, place ? LW_BORROW : LW_MOVE);
  fn->temps = saved_temps;
  if (other == MIR_NONE) {
    return MIR_NONE;
  }
  if (!place) {
    (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &other, 1, (MirImm){0}, MIR_NONE);
  }
  const MirValue held = mir_b_emit(&fn->b, place ? MOP_OptView : MOP_OptSome, &other, 1, (MirImm){0}, opt_ty);
  mir_b_def_var(&fn->b, either, held);
  mir_b_def_var(&fn->b, holder, place ? mir_b_emit(&fn->b, MOP_OptNone, NULL, 0, (MirImm){0}, opt_ty) : held);
  fn_scope_end(fn);
  mir_b_br(&fn->b, join, NULL, 0);
  mir_b_seal_block(&fn->b, join);
  mir_b_switch_to(&fn->b, join);
  const MirValue kept = mir_b_use_var(&fn->b, holder);
  fn_own(fn, fn_scope(fn), kept);
  const MirValue chosen = mir_b_use_var(&fn->b, either);
  return mir_b_emit(&fn->b, MOP_OptGet, &chosen, 1, (MirImm){0}, result_ty);
}

/* `x or d` over a nullable `x` whose default is nullable too, read in place with `d` a name: both answers are views already,
 * so the result is `x` when it holds a payload and `d` otherwise, and nothing is copied. */
static MirValue lower_or_nullable_view(LowerFn *fn, const MsExpr *expr, MirValue left, MirTy opt_ty, MirBlock null_block, MirBlock join) {
  const MirVar either = mir_b_declare_var(&fn->b, opt_ty, MM_BORROW);
  mir_b_def_var(&fn->b, either, left);
  mir_b_br(&fn->b, join, NULL, 0);
  mir_b_switch_to(&fn->b, null_block);
  const MirValue other = fn_expr(fn, expr->u.bin.right, LW_BORROW);
  if (other == MIR_NONE) {
    return MIR_NONE;
  }
  mir_b_def_var(&fn->b, either, other);
  mir_b_br(&fn->b, join, NULL, 0);
  mir_b_seal_block(&fn->b, join);
  mir_b_switch_to(&fn->b, join);
  return mir_b_use_var(&fn->b, either);
}

MirValue fn_lower_or_null(LowerFn *fn, const MsExpr *expr, LowerWant want) {
  const MirTy result_ty = fn_type(fn, ms_facts_type(fn->facts, expr->id));
  /* A name this expression moves, or reads for the last time, gives its payload up as `if v := name { ... }` does. */
  const MsExpr *named = expr->u.bin.left;
  /* `(f()?) or d` that an owner takes: the payload leaves the Result `?` unwraps, and the Optional it is gives it up. */
  const bool unwrapped = want == LW_MOVE && named->kind == MS_E_UNARY && named->op == MS_U_TRY;
  const bool moving = unwrapped || (named->kind == MS_E_CALL && ms_facts_use(fn->facts, named->id) == MS_USE_MOVE) ||
                      (named->kind == MS_E_NAME && (fn->narrow_take == expr || ms_facts_use(fn->facts, named->id) == MS_USE_MOVE ||
                                                   ms_facts_use(fn->facts, expr->id) == MS_USE_MOVE ||
                                                   (fn->facts->last != NULL && fn->facts->last[named->id] != 0)));
  /* `m.get(k) or d` read in place views the entry `m` keeps, whatever its type, instead of copying it */
  const bool entry_read = want == LW_BORROW && !moving && named->kind == MS_E_CALL &&
                          ms_own_native_get(fn->cx->program, fn->facts, named) == MS_NATIVE_GET_MAP;
  /* an Optional value (`Map[K, V?]`) is stored boxed: the entry is no view of the answer */
  const MsTy answered = entry_read ? ms_facts_type(fn->facts, named->id) : MS_TY_NONE;
  const bool plain_entry = entry_read && ms_ty_arg_count(&fn->cx->program->types, answered) == 1;
  const MirValue entry = plain_entry ? fn_map_entry_view(fn, named) : MIR_NONE;
  const MirValue left = entry != MIR_NONE ? entry : fn_expr(fn, named, moving ? LW_MOVE : LW_BORROW);
  if (left == MIR_NONE || result_ty == MIR_VOID) {
    return MIR_NONE;
  }
  const MirTy opt_ty = mir_b_ty(&fn->b, left);
  const bool fresh_left = entry == MIR_NONE && (fn_fresh_owner(fn, left) || (named->kind == MS_E_CALL && !call_views_argument(fn, named) && fn_owns_result(fn, left))); /* asked where `left` was made, before the branch */
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
  const bool view_only = !owns && (fn->or_view == expr || want == LW_BORROW) && ms_ty_is(&fn->cx->program->types, ms_facts_type(fn->facts, expr->u.bin.right->id), MS_BUILTIN_Never) &&
                         ms_facts_use(fn->facts, expr->id) != MS_USE_MOVE;
  /* Read in place (a receiver, an operand, a borrowed argument): the result is a view of `x`'s payload or of the default,
   * which a holder owned by the enclosing scope keeps alive, so nothing is copied. */
  const bool never_rhs = ms_ty_is(&fn->cx->program->types, ms_facts_type(fn->facts, expr->u.bin.right->id), MS_BUILTIN_Never);
  if (!owns && !view_only && want == LW_BORROW && !never_rhs && mir_ty_data(fn->cx->module, opt_ty)->elem == result_ty &&
      mir_needs_drop(fn->cx->module, result_ty) && !ms_check_holds_resource(fn->cx->program, ms_facts_type(fn->facts, expr->id))) {
    return lower_or_view(fn, expr, left, present, opt_ty, result_ty, some_block, null_block, join);
  }
  if (!owns && !view_only && want == LW_BORROW && !never_rhs && result_ty == opt_ty && mir_needs_drop(fn->cx->module, opt_ty) &&
      expr->u.bin.right->kind == MS_E_NAME) {
    return lower_or_nullable_view(fn, expr, left, opt_ty, null_block, join);
  }
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

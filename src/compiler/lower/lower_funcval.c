/* compiler/lower/lower_funcval.c: function values whose parameters a call may leave out, and calls of function values.
 * A parameter the function type lets a caller omit crosses it as an optional: a call fills a missing argument with
 * none, and the function takes a none to its default. */
#include "compiler/lower/lower_fn.h"
#include "compiler/syntax/walk.h"
#include "compiler/mir/mir_analysis.h"

/* ---- parameters a function value may leave out ---- */

MirValue fn_unlift(LowerFn *fn, MirValue opt, const MsExpr *fallback, MirTy elem) {
  const MirValue present = mir_b_emit(&fn->b, MOP_OptIsSome, &opt, 1, (MirImm){0}, MIR_BOOL);
  const MirBlock some_block = mir_b_new_block(&fn->b);
  const MirBlock none_block = mir_b_new_block(&fn->b);
  const MirBlock join = mir_b_new_block(&fn->b);
  const MirValue result = mir_b_add_block_param(&fn->b, join, elem, MM_MOVE);
  const bool owns = mir_needs_drop(fn->cx->module, elem);
  mir_b_br_if(&fn->b, present, some_block, NULL, 0, none_block, NULL, 0);
  mir_b_seal_block(&fn->b, some_block);
  mir_b_seal_block(&fn->b, none_block);
  mir_b_switch_to(&fn->b, some_block);
  MirValue value = mir_b_emit(&fn->b, MOP_OptGet, &opt, 1, (MirImm){0}, elem);
  if (owns) {
    value = fn_implicit_clone(fn, value, false);
  }
  mir_b_br(&fn->b, join, &value, 1);
  mir_b_switch_to(&fn->b, none_block);
  const MirTy saved_hint = fn->hint;
  fn->hint = elem;
  /* The default's temporaries live only on this path. */
  (void)fn_scope_begin(fn);
  MirValue other = fallback != NULL ? fn_expr(fn, fallback, LW_MOVE) : MIR_NONE;
  fn->hint = saved_hint;
  if (other == MIR_NONE) {
    return MIR_NONE;
  }
  if (owns) {
    other = fn_move_out_of_scope(fn, other);
  }
  fn_scope_end(fn);
  mir_b_br(&fn->b, join, &other, 1);
  mir_b_seal_block(&fn->b, join);
  mir_b_switch_to(&fn->b, join);
  if (owns) {
    fn_own(fn, fn_scope(fn), result);
  }
  return result;
}

/* A function value used where its type differs only in which parameters may be left out: a closure holding a copy of
 * it that wraps a supplied argument in an optional, or reads one out. */
MirValue fn_adapt_function(LowerFn *fn, MirValue value, MirTy to_ty) {
  Lower *cx = fn->cx;
  const MirTy from_ty = mir_b_ty(&fn->b, value);
  const MirTyData *from = mir_ty_data(cx->module, from_ty);
  const MirTyData *to = mir_ty_data(cx->module, to_ty);
  if (from_ty == to_ty) {
    return value;
  }
  if (from->kind != MK_FN || to->kind != MK_FN || from->nargs != to->nargs || from->elem != to->elem) {
    (void)fn_fail(fn, "a function value of another shape cannot be adapted");
    return MIR_NONE;
  }
  const MirValue held = mir_needs_drop(cx->module, from_ty) ? fn_implicit_clone(fn, value, true) : value;
  const LowerCapture capture = {.kind = MS_REF_LOCAL, .ty = from_ty};
  const uint32_t slot = lower_closure_func(cx, to_ty, &capture, 1);
  const MirFunc reserved = cx->module->funcs.ptr[slot];
  MirBuilder b;
  mir_b_init(&b, cx->module, reserved.name, reserved.params, reserved.nparams, reserved.ret);
  MirValue *values = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirValue, (size_t)reserved.nparams + 1);
  mir_b_params(&b, values, reserved.nparams);
  MirValue *args = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirValue, (size_t)reserved.nparams + 1);
  const MirImm cap_imm = {.tag = MI_IDX, .a = 0};
  args[0] = mir_b_emit(&b, MOP_ClosureCap, &values[0], 1, cap_imm, from_ty);
  for (uint32_t at = 0; at < from->nargs; at++) {
    args[at + 1] = values[at + 1];
    if (from->args[at] == to->args[at]) {
      continue;
    }
    const MirTyData *want = mir_ty_data(cx->module, from->args[at]);
    const MirTyData *have = mir_ty_data(cx->module, to->args[at]);
    if (want->kind == MK_OPT && want->elem == to->args[at]) {
      args[at + 1] = mir_b_emit(&b, MOP_OptSome, &values[at + 1], 1, (MirImm){0}, from->args[at]);
    } else if (have->kind == MK_OPT && have->elem == from->args[at]) {
      args[at + 1] = mir_b_emit(&b, MOP_OptGet, &values[at + 1], 1, (MirImm){0}, from->args[at]);
    } else {
      (void)fn_fail(fn, "a function value of another shape cannot be adapted");
      return MIR_NONE;
    }
  }
  const MirValue result = mir_b_emit(&b, MOP_CallInd, args, from->nargs + 1, (MirImm){0}, from->elem);
  mir_b_ret(&b, reserved.ret == MIR_VOID ? MIR_NONE : result);
  MirFunc built;
  if (!mir_b_into_func(&b, &built)) {
    (void)fn_fail(fn, "a function value could not be adapted");
    return MIR_NONE;
  }
  built.linkage = ML_INTERNAL;
  built.kind = MFK_CLOSURE;
  built.captures = reserved.captures;
  built.ncaptures = reserved.ncaptures;
  mir_func_release(&cx->module->funcs.ptr[slot]);
  cx->module->funcs.ptr[slot] = built;
  const MirImm imm = {.tag = MI_FUNC, .a = slot};
  return fn_emit(fn, MOP_ClosureNew, &held, 1, imm, to_ty);
}

/* Whether `a` is written before `b` in the source. */
static bool written_before_value(const MsExpr *a, const MsExpr *b) {
  const MsPos from = ms_expr_start(a), to = ms_expr_start(b);
  return from.line != to.line ? from.line < to.line : from.column < to.column;
}

/* ---- calling a function value ---- */

MirValue fn_call_value(LowerFn *fn, const MsExpr *expr, const MsRef *ref) {
  const MirValue callee = ref != NULL ? fn_name_ref(fn, expr->u.call.callee, ref) : fn_expr(fn, expr->u.call.callee, LW_BORROW);
  if (callee == MIR_NONE) {
    return MIR_NONE;
  }
  const MirTyData *data = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, callee));
  if (data->kind != MK_FN || expr->u.call.args.len > data->nargs || data->nargs > 15) {
    (void)fn_fail(fn, "a call of a function value does not match its type");
    return MIR_NONE;
  }
  /* The arguments as the call wrote them, in the function type's parameter order: labels may reorder them. The
   * checker's call fact says which written argument fills each parameter; without one they are positional. */
  const MsCall *fact = fn_find_call(fn->facts, expr->id);
  const bool facts = fact != NULL && fact->arg_count == data->nargs;
  const MsExpr *written_args[16] = {0};
  for (uint32_t index = 0; index < data->nargs; index++) {
    if (facts) {
      written_args[index] = fact->args[index].source == MS_ARG_WRITTEN ? fn_written_arg(expr, fact->args[index].node.node) : NULL;
    } else {
      written_args[index] = index < expr->u.call.args.len ? expr->u.call.args.ptr[index].value : NULL;
    }
  }
  /* Evaluation follows the written order; a parameter nobody wrote is filled after them. */
  uint32_t order[16];
  for (uint32_t at = 0; at < data->nargs; at++) {
    uint32_t place = at;
    while (place > 0 && (written_args[order[place - 1]] == NULL ||
                         (written_args[at] != NULL && written_before_value(written_args[at], written_args[order[place - 1]])))) {
      if (written_args[order[place - 1]] != NULL && written_args[at] == NULL) {
        break;
      }
      order[place] = order[place - 1];
      place--;
    }
    order[place] = at;
  }
  MirValue bound_receiver = MIR_NONE; /* a local bound to a method value: the receiver it captured */
  const MsParams *bound_params = NULL;
  for (uint32_t at = 0; ref != NULL && ref->kind == MS_REF_LOCAL && at < fn->nbound_self; at++) {
    if (fn->bound_self[at].local == ref->local) {
      bound_receiver = fn->bound_self[at].receiver;
      bound_params = fn->bound_self[at].params;
    }
  }
  MirValue args[16];
  VarSlot slots[16];
  uint32_t nslots = 0;
  args[0] = callee;
  for (uint32_t step = 0; step < data->nargs; step++) {
    const uint32_t index = order[step];
    const MirTy param_ty = data->args[index];
    const MsExpr *written = written_args[index];
    if (written == NULL && facts && bound_params != NULL && fact->args[index].source == MS_ARG_DEFAULT) {
      /* A method value keeps its parameters' defaults: the default is written in the call, over the arguments so far and
       * the receiver the value captured. */
      fn->default_call = fact;
      fn->default_args = args + 1;
      fn->default_params = bound_params;
      fn->default_self = bound_receiver;
      fn->default_has_self = bound_receiver != MIR_NONE;
      args[index + 1] = fn_default_argument(fn, fact, &fact->args[index], param_ty);
      fn->default_call = NULL;
      fn->default_args = NULL;
      fn->default_has_self = false;
      fn->default_params = NULL;
      if (args[index + 1] == MIR_NONE) {
        return MIR_NONE;
      }
      continue;
    }
    if (written == NULL) {
      /* A parameter the call leaves out is none. */
      if (mir_ty_data(fn->cx->module, param_ty)->kind != MK_OPT) {
        (void)fn_fail(fn, "a call of a function value leaves out a required argument");
        return MIR_NONE;
      }
      args[index + 1] = fn_emit(fn, MOP_OptNone, NULL, 0, (MirImm){0}, param_ty);
      continue;
    }
    if (mir_param_is_var(data->owned, index)) {
      args[index + 1] = fn_var_slot(fn, written, &slots[nslots], slots, nslots);
      nslots++;
    } else {
      const bool moves = mir_owns(data->owned, index);
      args[index + 1] = fn_expr(fn, written, moves ? LW_MOVE : LW_BORROW);
      if (!moves && args[index + 1] != MIR_NONE) { /* a resource temporary the function only borrows closes with the statement */
        args[index + 1] = fn_closing_temporary(fn, expr, index, written, args[index + 1]);
      }
      const MirTyData *param = mir_ty_data(fn->cx->module, param_ty);
      if (args[index + 1] != MIR_NONE && param->kind == MK_OPT && mir_b_ty(&fn->b, args[index + 1]) == param->elem) {
        /* A supplied argument of a parameter the function type made optional. */
        args[index + 1] = fn_emit(fn, moves ? MOP_OptSome : MOP_OptView, &args[index + 1], 1, (MirImm){0}, param_ty);
      }
    }
    if (args[index + 1] == MIR_NONE) {
      return MIR_NONE;
    }
  }
  mir_b_set_loc(&fn->b, fn_loc(fn, expr->pos));
  const MirValue result = fn_emit(fn, MOP_CallInd, args, data->nargs + 1, (MirImm){0}, data->elem);
  return fn_var_slots_back(fn, slots, nslots) ? result : MIR_NONE;
}

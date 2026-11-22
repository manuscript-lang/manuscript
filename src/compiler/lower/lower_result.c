/* compiler/lower/lower_result.c: unary operators, `try`, and the Result a failable function returns. A function
 * whose result is a Result returns `ok(value)` for a value of the ok type and `err(error)` for any other; `try e`
 * returns the error of a failed `e` from the function and otherwise is the ok payload. */
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_analysis.h"

enum { OK_CASE = 0, ERR_CASE = 1 };

static const MirAltDef *result_def(const LowerFn *fn, MirTy ty, uint32_t *id) {
  const MirModule *module = fn->cx->module;
  const MirTyData *data = mir_ty_data(module, ty);
  if (data->kind != MK_ALT || module->alts.ptr[data->id].std != MSTD_RESULT) {
    return NULL;
  }
  *id = data->id;
  return &module->alts.ptr[data->id];
}

static MirValue build_case(LowerFn *fn, uint32_t alt, uint32_t which, MirValue payload, MirTy ty) {
  const MirImm imm = {.tag = MI_CASE, .a = alt, .b = which};
  const bool has_field = fn->cx->module->alts.ptr[alt].cases[which].nfields > 0;
  if (payload == MIR_NONE && has_field) {
    payload = mir_b_unit(&fn->b);
  }
  return fn_emit(fn, MOP_AltNew, &payload, payload == MIR_NONE ? 0 : 1, imm, ty);
}

/* Whether the end of the body may be reached: a function that returns a value has returned on every path the
 * checker allows, so what follows its last statement is unreachable. A Result whose ok case holds nothing, a
 * Void function and an Optional (which returns `none`) end by returning. */
bool fn_end_is_reachable(LowerFn *fn) {
  uint32_t alt = 0;
  const MirAltDef *def = result_def(fn, fn->ret, &alt);
  if (def != NULL) {
    const MirCaseDef *ok = &def->cases[OK_CASE];
    return ok->nfields == 0 || ok->fields[0].ty == MIR_VOID;
  }
  return fn->ret == MIR_VOID || fn->decl_void || mir_ty_data(fn->cx->module, fn->ret)->kind == MK_OPT;
}

MirValue fn_result_wrap(LowerFn *fn, MirValue value) {
  uint32_t alt = 0;
  const MirAltDef *def = result_def(fn, fn->ret, &alt);
  if (def == NULL || (value != MIR_NONE && mir_b_ty(&fn->b, value) == fn->ret)) {
    return value;
  }
  const MirCaseDef *ok = &def->cases[OK_CASE];
  const MirTy ok_ty = ok->nfields > 0 ? ok->fields[0].ty : MIR_VOID;
  const bool is_ok = value == MIR_NONE || ok_ty == MIR_VOID || mir_b_ty(&fn->b, value) == ok_ty;
  const bool empty = is_ok && ok_ty == MIR_VOID;
  const MirValue wrapped = empty ? build_case(fn, alt, OK_CASE, MIR_NONE, fn->ret)
                                 : build_case(fn, alt, is_ok ? OK_CASE : ERR_CASE, value, fn->ret);
  /* The function returns it, so the scope that owns every fresh result must not drop it. */
  (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &wrapped, 1, (MirImm){0}, MIR_NONE);
  return wrapped;
}

/* `value?` on an Optional: the payload when present; when absent the function returns `none` (or, in a function
 * that returns nothing, just returns). */
static MirValue try_optional(LowerFn *fn, const MsExpr *expr, MirValue value) {
  const MirTy opt_ty = mir_b_ty(&fn->b, value);
  const MirTyData *ret = mir_ty_data(fn->cx->module, fn->ret);
  if (ret->kind != MK_OPT && fn->ret != MIR_VOID && !fn->decl_void) {
    return fn_fail(fn, "`?` on an Optional needs a function that returns an Optional or nothing") ? MIR_NONE : MIR_NONE;
  }
  if (fn_place_owns(fn, expr->u.bin.left)) {
    (void)fn_fail(fn, "`?` on a `var` optional (changing its payload in place) is not lowered yet");
    return MIR_NONE;
  }
  mir_b_set_loc(&fn->b, fn_loc(fn, expr->pos));
  const MirValue present = mir_b_emit(&fn->b, MOP_OptIsSome, &value, 1, (MirImm){0}, MIR_BOOL);
  const MirBlock some_block = mir_b_new_block(&fn->b);
  const MirBlock none_block = mir_b_new_block(&fn->b);
  mir_b_br_if(&fn->b, present, some_block, NULL, 0, none_block, NULL, 0);
  mir_b_seal_block(&fn->b, some_block);
  mir_b_seal_block(&fn->b, none_block);
  mir_b_switch_to(&fn->b, none_block);
  MirValue absent = ret->kind == MK_OPT ? mir_b_emit(&fn->b, MOP_OptNone, NULL, 0, (MirImm){0}, fn->ret) : fn_default_result(fn);
  if (absent != MIR_NONE) {
    (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &absent, 1, (MirImm){0}, MIR_NONE);
  }
  fn_scope_unwind(fn, 0);
  mir_b_ret(&fn->b, absent);
  mir_b_switch_to(&fn->b, some_block);
  const MirTy payload = mir_ty_data(fn->cx->module, opt_ty)->elem;
  return mir_b_emit(&fn->b, MOP_OptGet, &value, 1, (MirImm){0}, payload);
}

MirValue fn_try(LowerFn *fn, const MsExpr *expr, LowerWant want) {
  const MirValue value = fn_expr(fn, expr->u.bin.left, LW_BORROW);
  const bool fresh = want == LW_MOVE && value != MIR_NONE && fn_fresh_owner(fn, value);
  uint32_t alt = 0;
  if (value == MIR_NONE) {
    return MIR_NONE;
  }
  if (mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, value))->kind == MK_OPT) {
    return try_optional(fn, expr, value);
  }
  const MirAltDef *def = result_def(fn, mir_b_ty(&fn->b, value), &alt);
  uint32_t ret_alt = 0;
  if (def == NULL || result_def(fn, fn->ret, &ret_alt) == NULL || def->cases[ERR_CASE].nfields == 0) {
    (void)fn_fail(fn, "`try` needs a Result operand in a function that returns a Result");
    return MIR_NONE;
  }
  const MirTy err_ty = def->cases[ERR_CASE].fields[0].ty;
  const MirTy ret_err = fn->cx->module->alts.ptr[ret_alt].cases[ERR_CASE].nfields > 0
                            ? fn->cx->module->alts.ptr[ret_alt].cases[ERR_CASE].fields[0].ty
                            : MIR_VOID;
  if (err_ty != ret_err) {
    (void)fn_fail(fn, "`try` of a Result whose error type differs from the function's is not lowered yet");
    return MIR_NONE;
  }
  mir_b_set_loc(&fn->b, fn_loc(fn, expr->pos));
  const MirValue tag = mir_b_emit(&fn->b, MOP_AltTag, &value, 1, (MirImm){0}, MIR_INT);
  const MirValue is_ok = mir_b_icmp(&fn->b, MCC_EQ, tag, mir_b_iconst(&fn->b, OK_CASE));
  const MirBlock ok_block = mir_b_new_block(&fn->b);
  const MirBlock err_block = mir_b_new_block(&fn->b);
  mir_b_br_if(&fn->b, is_ok, ok_block, NULL, 0, err_block, NULL, 0);
  mir_b_seal_block(&fn->b, ok_block);
  mir_b_seal_block(&fn->b, err_block);
  mir_b_switch_to(&fn->b, err_block);
  const MirImm err_imm = {.tag = MI_ALTFIELD, .a = alt, .b = ERR_CASE, .c = 0};
  /* The error moves out of the operand, which the function scope then drops without it. */
  const MirOp take = mir_needs_drop(fn->cx->module, err_ty) ? MOP_AltTake : MOP_AltGet;
  const MirValue err = mir_b_emit(&fn->b, take, &value, 1, err_imm, err_ty);
  const MirValue failed = build_case(fn, ret_alt, ERR_CASE, err, fn->ret);
  const MirImm none = {0};
  (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &failed, 1, none, MIR_NONE);
  fn_scope_unwind(fn, 0);
  mir_b_ret(&fn->b, failed);
  mir_b_switch_to(&fn->b, ok_block);
  const MirCaseDef *ok = &def->cases[OK_CASE];
  if (ok->nfields == 0) {
    return mir_b_unit(&fn->b);
  }
  const MirImm ok_imm = {.tag = MI_ALTFIELD, .a = alt, .b = OK_CASE, .c = 0};
  /* A payload of a Result nothing else owns moves out of it, so that its new owner closes it. */
  const bool takes = fresh && mir_needs_drop(fn->cx->module, ok->fields[0].ty);
  return mir_b_emit(&fn->b, takes ? MOP_AltTake : MOP_AltGet, &value, 1, ok_imm, ok->fields[0].ty);
}

MirValue fn_unary(LowerFn *fn, const MsExpr *expr, LowerWant want) {
  if (expr->op == MS_U_TRY) {
    return fn_try(fn, expr, want);
  }
  const MsExpr *inner = expr->u.bin.left;
  uint64_t bits = 0;
  if (expr->op == MS_U_NEG && inner->kind == MS_E_NUMBER &&
      fn_type(fn, ms_facts_type(fn->facts, inner->id)) == MIR_INT &&
      fn_number_bits(ms_names_span(fn->cx->program->names, inner->u.sym), &bits)) {
    /* A negative literal is one constant, so Int's lowest value needs no overflowing negation. */
    return mir_b_iconst(&fn->b, (int64_t)(0 - bits));
  }
  const MirValue operand = fn_expr(fn, expr->u.bin.left, LW_BORROW);
  if (operand == MIR_NONE || expr->op == MS_U_PLUS) {
    return operand;
  }
  const MirTy ty = mir_b_ty(&fn->b, operand);
  mir_b_set_loc(&fn->b, fn_loc(fn, expr->pos));
  if (expr->op == MS_U_NOT) {
    return mir_b_emit(&fn->b, MOP_Xor, (MirValue[]){operand, mir_b_bconst(&fn->b, true)}, 2, (MirImm){0}, MIR_BOOL);
  }
  if (ty == MIR_FLOAT || ty == MIR_FLOAT32) {
    return mir_b_emit(&fn->b, MOP_FNeg, &operand, 1, (MirImm){0}, ty);
  }
  return fn_emit(fn, MOP_INegChk, &operand, 1, (MirImm){0}, ty);
}

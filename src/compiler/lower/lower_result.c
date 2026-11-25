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
  const bool view = has_field && (fn->cx->module->alts.ptr[alt].borrowed >> which & 1u) != 0;
  return fn_emit(fn, view ? MOP_AltView : MOP_AltNew, &payload, payload == MIR_NONE ? 0 : 1, imm, ty);
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

/* A call's borrowing-variant result is read as the ordinary Result, a borrow of the variant its scope owns. */
MirValue fn_view_as_plain(LowerFn *fn, MirValue result, MirTy plain) {
  if (result == MIR_NONE || mir_b_ty(&fn->b, result) == plain || mir_ty_data(fn->cx->module, plain)->kind != MK_ALT ||
      fn->cx->module->alts.ptr[mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, result))->id].borrowed == 0) {
    return result;
  }
  const MirValue read = mir_b_emit(&fn->b, MOP_AltPlain, &result, 1, (MirImm){0}, plain);
  if (fn->nviewed < MS_COUNT_OF(fn->viewed)) {
    fn->viewed[fn->nviewed].plain = read;
    fn->viewed[fn->nviewed++].owner = result;
  }
  return read;
}

/* Whether the function returns a borrowing variant of Result (`&T!`). */
bool fn_returns_view(const LowerFn *fn) {
  const MirTyData *data = mir_ty_data(fn->cx->module, fn->ret);
  return data->kind == MK_ALT && fn->cx->module->alts.ptr[data->id].borrowed != 0 &&
         fn->cx->module->alts.ptr[data->id].std == MSTD_RESULT;
}

/* A Result some other owner keeps, read as the borrowing variant: the `ok` payload stays where it is, and an error is
 * copied because the variant owns its error. */
static MirValue fn_view_of_result(LowerFn *fn, MirValue plain) {
  uint32_t alt = 0;
  uint32_t source = 0;
  if (plain == MIR_NONE || result_def(fn, fn->ret, &alt) == NULL || result_def(fn, mir_b_ty(&fn->b, plain), &source) == NULL) {
    (void)fn_fail(fn, "a `&` Result result must be built with `ok(part)` or `error(e)`, or be a Result held by an argument");
    return MIR_NONE;
  }
  const MirModule *module = fn->cx->module;
  const MirTy ok_ty = module->alts.ptr[source].cases[OK_CASE].nfields > 0 ? module->alts.ptr[source].cases[OK_CASE].fields[0].ty : MIR_VOID;
  const MirTy err_ty = module->alts.ptr[source].cases[ERR_CASE].nfields > 0 ? module->alts.ptr[source].cases[ERR_CASE].fields[0].ty : MIR_VOID;
  const MirValue tag = mir_b_emit(&fn->b, MOP_AltTag, &plain, 1, (MirImm){0}, MIR_INT);
  const MirValue is_ok = mir_b_icmp(&fn->b, MCC_EQ, tag, mir_b_iconst(&fn->b, OK_CASE));
  const MirBlock ok_block = mir_b_new_block(&fn->b);
  const MirBlock err_block = mir_b_new_block(&fn->b);
  const MirBlock join = mir_b_new_block(&fn->b);
  const MirValue joined = mir_b_add_block_param(&fn->b, join, fn->ret, MM_MOVE);
  mir_b_br_if(&fn->b, is_ok, ok_block, NULL, 0, err_block, NULL, 0);
  mir_b_seal_block(&fn->b, ok_block);
  mir_b_seal_block(&fn->b, err_block);
  mir_b_switch_to(&fn->b, ok_block);
  const MirImm ok_imm = {.tag = MI_ALTFIELD, .a = source, .b = OK_CASE, .c = 0};
  const MirValue payload = ok_ty == MIR_VOID ? MIR_NONE : fn_emit(fn, MOP_AltGet, &plain, 1, ok_imm, ok_ty);
  const MirValue viewed = build_case(fn, alt, OK_CASE, payload, fn->ret);
  mir_b_br(&fn->b, join, &viewed, 1);
  mir_b_switch_to(&fn->b, err_block);
  const MirImm err_imm = {.tag = MI_ALTFIELD, .a = source, .b = ERR_CASE, .c = 0};
  MirValue err = err_ty == MIR_VOID ? MIR_NONE : fn_emit(fn, MOP_AltGet, &plain, 1, err_imm, err_ty);
  if (err != MIR_NONE && mir_needs_drop(module, err_ty)) {
    err = fn_implicit_clone(fn, err, false);
  }
  const MirValue failed = build_case(fn, alt, ERR_CASE, err, fn->ret);
  mir_b_br(&fn->b, join, &failed, 1);
  mir_b_seal_block(&fn->b, join);
  mir_b_switch_to(&fn->b, join);
  return joined;
}

/* `return ok(part)`, `return error(e)` or `return call()` in a function that returns a borrowing variant: the `ok`
 * payload is borrowed from where it is read, an error is owned, and a forwarded call hands its variant on. False when
 * the expression is none of these. */
bool fn_return_view(LowerFn *fn, const MsExpr *expr, MirValue *out) {
  const MsCall *call = expr->kind == MS_E_CALL ? ms_facts_call(fn->facts, expr->id) : NULL;
  if (fn->default_exit != NULL) {
    return false;
  }
  if (call != NULL && call->callee.kind == MS_REF_CASE && call->arg_count == 1 && expr->u.call.args.len == 1) {
    const uint32_t which = call->callee.index == OK_CASE ? OK_CASE : ERR_CASE;
    const MsExpr *written = expr->u.call.args.ptr[0].value;
    const MirValue payload = fn_expr(fn, written, which == OK_CASE ? LW_BORROW : LW_MOVE);
    if (payload == MIR_NONE) {
      *out = MIR_NONE;
      return true;
    }
    uint32_t alt = 0;
    (void)result_def(fn, fn->ret, &alt);
    *out = build_case(fn, alt, which, payload, fn->ret);
    return true;
  }
  const MirValue handed = fn_expr(fn, expr, LW_BORROW);
  const MirValue owner = fn_view_owner(fn, handed);
  if (owner != MIR_NONE) {
    *out = owner;
    return true;
  }
  *out = fn_view_of_result(fn, handed);
  return true;
}

MirValue fn_view_owner(const LowerFn *fn, MirValue value) {
  for (uint32_t index = 0; index < fn->nviewed; index++) {
    if (fn->viewed[index].plain == value) {
      return fn->viewed[index].owner;
    }
  }
  return MIR_NONE;
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

/* `place?.change()`: the optional `place` holds is taken; absent, the function returns as `?` does (the
 * optional put back); present, its payload moves into a slot the method changes, and `fn_var_slots_back`
 * wraps it and stores it into `place` again. */
MirValue fn_try_var_slot(LowerFn *fn, const MsExpr *expr, VarSlot *out) {
  const MsExpr *place = expr->u.bin.left;
  const MirTyData *ret = mir_ty_data(fn->cx->module, fn->ret);
  MirValue taken;
  MirValue record = MIR_NONE;
  MirValue home = MIR_NONE;
  VarSlot *outer = NULL;
  const MsExpr *base = place->kind == MS_E_MEMBER ? place->u.member.left : NULL;
  if (base != NULL && base->kind == MS_E_UNARY && base->op == MS_U_TRY && !fn_place_changeable(fn, place)) {
    /* `a?.b?.change()`: `a`'s payload moves into a slot, and the optional `b` is taken from the field there. */
    outer = MS_ARENA_NEW(&fn->cx->module->arena, VarSlot);
    const MirValue payload = fn_try_var_slot(fn, base, outer);
    const MsRef *field = ms_facts_ref(fn->facts, place->id);
    const MirTyData *owner = payload != MIR_NONE ? mir_ty_data(fn->cx->module, outer->ty) : NULL;
    if (payload == MIR_NONE || field == NULL || owner == NULL || owner->kind != MK_TYPE) {
      return MIR_NONE;
    }
    home = mir_b_emit(&fn->b, MOP_PtrField, &payload, 1, (MirImm){.tag = MI_FIELD, .a = owner->id, .b = field->index}, MIR_PTR);
    const MirTy element = fn_type(fn, ms_facts_type(fn->facts, place->id));
    taken = mir_b_emit(&fn->b, MOP_Take, &home, 1, (MirImm){.tag = MI_TY, .a = element}, element);
  } else if (fn_list_element_addr(fn, place, &home)) { /* an optional element: taken out of its place in the list, put back there */
    if (home == MIR_NONE) {
      return MIR_NONE;
    }
    const MirTy element = fn_type(fn, ms_facts_type(fn->facts, place->id));
    taken = mir_b_emit(&fn->b, MOP_Take, &home, 1, (MirImm){.tag = MI_TY, .a = element}, element);
  } else if (!fn_take_field(fn, place, &record, &taken) && !fn_take_place(fn, place, &taken)) {
    return MIR_NONE;
  }
  if (taken == MIR_NONE) {
    return MIR_NONE;
  }
  const MirTy opt_ty = mir_b_ty(&fn->b, taken);
  const MirTyData *opt = mir_ty_data(fn->cx->module, opt_ty);
  if (opt->kind != MK_OPT || (ret->kind != MK_OPT && fn->ret != MIR_VOID && !fn->decl_void)) {
    return fn_fail(fn, "`?` on an Optional needs a function that returns an Optional or nothing") ? MIR_NONE : MIR_NONE;
  }
  mir_b_set_loc(&fn->b, fn_loc(fn, expr->pos));
  const MirValue present = mir_b_emit(&fn->b, MOP_OptIsSome, &taken, 1, (MirImm){0}, MIR_BOOL);
  const MirBlock some_block = mir_b_new_block(&fn->b);
  const MirBlock none_block = mir_b_new_block(&fn->b);
  mir_b_br_if(&fn->b, present, some_block, NULL, 0, none_block, NULL, 0);
  mir_b_seal_block(&fn->b, some_block);
  mir_b_seal_block(&fn->b, none_block);
  mir_b_switch_to(&fn->b, none_block);
  if (home != MIR_NONE) {
    const MirValue stored[2] = {home, taken};
    (void)mir_b_emit(&fn->b, mir_needs_drop(fn->cx->module, opt_ty) ? MOP_Put : MOP_Store, stored, 2, (MirImm){0}, MIR_NONE);
    if (outer != NULL && !fn_var_slots_back(fn, outer, 1)) { /* `a`'s payload goes back before the function returns */
      return MIR_NONE;
    }
  } else if (!(record != MIR_NONE ? fn_put_field(fn, place, record, taken) : fn_put_place(fn, place, taken))) {
    return MIR_NONE;
  }
  MirValue absent = ret->kind == MK_OPT ? mir_b_emit(&fn->b, MOP_OptNone, NULL, 0, (MirImm){0}, fn->ret) : fn_default_result(fn);
  if (absent != MIR_NONE) {
    (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &absent, 1, (MirImm){0}, MIR_NONE);
  }
  fn_scope_unwind(fn, 0);
  mir_b_ret(&fn->b, absent);
  mir_b_switch_to(&fn->b, some_block);
  /* The slot owns the payload while the call runs, and the writeback makes the Optional again from it. */
  const MirValue payload = mir_b_emit(&fn->b, mir_needs_drop(fn->cx->module, opt->elem) ? MOP_OptUnbox : MOP_OptGet, &taken, 1,
                                      (MirImm){0}, opt->elem);
  const MirImm of_type = {.tag = MI_TY, .a = opt->elem};
  const MirValue slot = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, of_type, MIR_PTR);
  const MirValue stored[2] = {slot, payload};
  (void)mir_b_emit(&fn->b, mir_needs_drop(fn->cx->module, opt->elem) ? MOP_Put : MOP_Store, stored, 2, (MirImm){0}, MIR_NONE);
  *out = (VarSlot){place, slot, opt->elem, record, false, home, opt_ty, outer};
  return slot;
}

/* Leaves the function with the error of the failed Result `value`: its scope is unwound and the error is the function's. */
bool fn_return_error(LowerFn *fn, MirValue value) {
  uint32_t alt = 0;
  const MirAltDef *def = result_def(fn, mir_b_ty(&fn->b, value), &alt);
  uint32_t ret_alt = 0;
  const DefaultExit *leaves = fn->default_exit; /* a `?` in a default leaves the call that omitted it */
  const MirTy ret = leaves != NULL ? leaves->ret : fn->ret;
  if (def == NULL || result_def(fn, ret, &ret_alt) == NULL || def->cases[ERR_CASE].nfields == 0) {
    return fn_fail(fn, "`try` needs a Result operand in a function that returns a Result");
  }
  const MirTy err_ty = def->cases[ERR_CASE].fields[0].ty;
  const MirTy ret_err = fn->cx->module->alts.ptr[ret_alt].cases[ERR_CASE].nfields > 0
                            ? fn->cx->module->alts.ptr[ret_alt].cases[ERR_CASE].fields[0].ty
                            : MIR_VOID;
  if (err_ty != ret_err) {
    return fn_fail(fn, "`try` of a Result whose error type differs from the function's is not lowered yet");
  }
  const MirImm err_imm = {.tag = MI_ALTFIELD, .a = alt, .b = ERR_CASE, .c = 0};
  /* The error moves out of an operand the function owns, which its scope then drops without it. */
  const bool drops = mir_needs_drop(fn->cx->module, err_ty);
  const bool owned = drops && fn_fresh_owner(fn, value);
  MirValue err = mir_b_emit(&fn->b, owned ? MOP_AltTake : MOP_AltGet, &value, 1, err_imm, err_ty);
  if (drops && !owned) {
    err = fn_implicit_clone(fn, err, false); /* a Result something else owns (a borrowed parameter) keeps its error: the relay copies it */
  }
  const MirValue failed = build_case(fn, ret_alt, ERR_CASE, err, ret);
  const MirImm none = {0};
  (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &failed, 1, none, MIR_NONE);
  if (leaves != NULL) {
    fn_scope_unwind(fn, leaves->keep);
    mir_b_br(&fn->b, leaves->join, &failed, 1);
    return true;
  }
  fn_scope_unwind(fn, 0);
  mir_b_ret(&fn->b, failed);
  return true;
}

MirValue fn_try(LowerFn *fn, const MsExpr *expr, LowerWant want) {
  /* A narrowed name at its last use hands its payload to the `?`: its new owner closes it. */
  const MsExpr *operand = expr->u.bin.left;
  const bool hands_on = want == LW_MOVE && operand->kind == MS_E_NAME && fn->facts->last != NULL &&
                        fn->facts->last[operand->id] != 0 && fn_read_type(fn, operand) != ms_facts_type(fn->facts, operand->id);
  MirValue value = fn_expr(fn, operand, hands_on ? LW_MOVE : LW_BORROW);
  uint32_t alt = 0;
  if (value == MIR_NONE) {
    return MIR_NONE;
  }
  if (want == LW_MOVE && expr->u.bin.left->kind == MS_E_CALL && fn_is_borrowed_view(fn, value)) {
    /* A call that answers its dying temporary argument (`id(open(path))?`) hands the temporary's payload to the new owner. */
    const MirValue answered = fn_take_from_temporary(fn, expr->u.bin.left, value);
    value = answered != MIR_NONE ? answered : value;
  }
  const bool fresh = want == LW_MOVE && fn_fresh_owner(fn, value);
  if (mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, value))->kind == MK_OPT) {
    return try_optional(fn, expr, value);
  }
  const MirAltDef *def = result_def(fn, mir_b_ty(&fn->b, value), &alt);
  if (def == NULL) {
    (void)fn_fail(fn, "`try` needs a Result operand in a function that returns a Result");
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
  if (!fn_return_error(fn, value)) {
    return MIR_NONE;
  }
  mir_b_switch_to(&fn->b, ok_block);
  const MirCaseDef *ok = &def->cases[OK_CASE];
  if (ok->nfields == 0) {
    return mir_b_unit(&fn->b);
  }
  const MirImm ok_imm = {.tag = MI_ALTFIELD, .a = alt, .b = OK_CASE, .c = 0};
  /* A payload of a Result nothing else owns moves out of it, so that its new owner closes it. */
  const bool takes = fresh && mir_needs_drop(fn->cx->module, ok->fields[0].ty);
  return fn_emit(fn, takes ? MOP_AltTake : MOP_AltGet, &value, 1, ok_imm, ok->fields[0].ty);
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
  MirValue negated;
  if (expr->op == MS_U_NEG && fn_object_negate(fn, operand, &negated)) {
    return negated;
  }
  return fn_emit(fn, MOP_INegChk, &operand, 1, (MirImm){0}, ty);
}

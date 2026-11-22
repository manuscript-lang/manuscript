/* compiler/lower/lower_stmt.c: statements: bindings, assignment, calls, return, if, while, break, continue. */
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_analysis.h"

static MirValue take_value(LowerFn *fn, const MsExpr *expr) {
  const MirValue value = fn_expr(fn, expr, LW_MOVE);
  return value;
}

/* A `var` local of a type that needs a drop owns its current value: assignment moves the new value in and drops
 * the old one, and the scope that declared it owns what it holds where the scope ends. */
static bool var_owns(const LowerFn *fn, MirVar var) {
  return fn->b.vars.ptr[var].mode == MM_MOVE;
}

static void disown(LowerFn *fn, MirValue value) {
  (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &value, 1, (MirImm){0}, MIR_NONE);
}

static bool lower_bind(LowerFn *fn, const MsStmt *stmt) {
  const MsPattern *pattern = stmt->u.bind.pattern;
  if (pattern->kind != MS_P_NAME) {
    return fn_fail(fn, "only a name can be bound for now");
  }
  /* A name bound to another name borrows it; anything else, and every `var`, is a new owner. */
  const MsExprKind kind = (MsExprKind)stmt->u.bind.value->kind;
  const bool borrow = !stmt->u.bind.is_mutable && (kind == MS_E_NAME || kind == MS_E_MEMBER);
  const MirValue value = borrow ? fn_expr(fn, stmt->u.bind.value, LW_BORROW) : take_value(fn, stmt->u.bind.value);
  if (value == MIR_NONE) {
    return false;
  }
  const MirTy ty = mir_b_ty(&fn->b, value);
  const uint32_t local = ms_facts_ref(fn->facts, pattern->id)->local;
  const MsCloser *closer = ms_facts_closer(fn->facts, pattern->id);
  if (closer != NULL && fn->closing != NULL && !borrow && !stmt->u.bind.is_mutable && fn_closer_lowerable(closer) &&
      (!mir_needs_drop(fn->cx->module, ty) || fn_fresh_owner(fn, value))) {
    return fn_bind_closing(fn, local, ms_facts_type(fn->facts, pattern->id), value);
  }
  if (stmt->u.bind.is_mutable && mir_needs_drop(fn->cx->module, ty)) {
    if (local >= fn->nvars) {
      return fn_fail(fn, "a local binding is outside the function's locals");
    }
    fn->vars[local] = mir_b_declare_var(&fn->b, ty, MM_MOVE) + 1;
    disown(fn, value);
    mir_b_def_var(&fn->b, fn->vars[local] - 1, value);
    return fn_scope_own_var(fn, fn->vars[local] - 1) && !fn->failed;
  }
  mir_b_def_var(&fn->b, fn_local(fn, local, ty), value);
  return !fn->failed;
}

/* The variable a name place assigns to: a `var` local or a `var` parameter; false for any other place. */
static bool owned_local(LowerFn *fn, const MsExpr *place, MirVar *out) {
  const MsRef *ref = place->kind == MS_E_NAME ? ms_facts_ref(fn->facts, place->id) : NULL;
  if (ref == NULL) {
    return false;
  }
  if (ref->kind == MS_REF_LOCAL && ref->local < fn->nvars && fn->vars[ref->local] != 0) {
    *out = fn->vars[ref->local] - 1;
    return true;
  }
  if (ref->kind != MS_REF_PARAM) {
    return false;
  }
  for (uint32_t at = 0; at < fn->nvar_params; at++) {
    if (fn->var_params[at].var == fn->param_vars[ref->local]) {
      *out = fn->var_params[at].var;
      return true;
    }
  }
  return false;
}

/* Whether `place` is a `var` local, a `var` parameter or a member path rooted in one: the places `fn_put_place` stores into. */
bool fn_place_changeable(LowerFn *fn, const MsExpr *place) {
  MirVar var;
  return owned_local(fn, place, &var) || (place->kind == MS_E_MEMBER && fn_place_changeable(fn, place->u.member.left));
}

/* The owned value of `base`, a place a part of it is assigned in: an owning local's value is taken out (stored
 * back by `fn_put_place`), a member or element path's value is copied. */
bool fn_take_place(LowerFn *fn, const MsExpr *base, MirValue *out) {
  MirVar var;
  if (owned_local(fn, base, &var)) {
    *out = mir_b_use_var(&fn->b, var);
    return true;
  }
  if (base->kind != MS_E_MEMBER && base->kind != MS_E_INDEX) {
    return fn_fail(fn, "assignment into this place is not lowered yet");
  }
  const MirValue inner = fn_expr(fn, base, LW_BORROW);
  if (inner == MIR_NONE) {
    return false;
  }
  *out = fn_emit(fn, MOP_Clone, &inner, 1, (MirImm){0}, mir_b_ty(&fn->b, inner));
  disown(fn, *out);
  return true;
}

/* `base.field = value` where `base` is an owning local or a member path: the record is taken out of its place
 * (a path's inner record is copied), the old field is dropped, `type.set` makes the updated record and that is
 * stored back into the place of `base`. `value` is owned and held by no scope. */
static bool set_member(LowerFn *fn, const MsExpr *place, MirValue value) {
  const MsRef *ref = ms_facts_ref(fn->facts, place->id);
  const MsExpr *base = place->u.member.left;
  if (ref == NULL || ref->kind != MS_REF_FIELD) {
    return fn_fail(fn, "this member is not a record field");
  }
  MirValue record = MIR_NONE;
  if (!fn_take_place(fn, base, &record)) {
    return false;
  }
  const MirTyData *data = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, record));
  if (data->kind != MK_TYPE) {
    return fn_fail(fn, "a field is assigned in a record (found MIR kind %d)", (int)data->kind);
  }
  const MirImm imm = {.tag = MI_FIELD, .a = data->id, .b = ref->index};
  const MirTy field_ty = fn_type(fn, ms_facts_type(fn->facts, place->id));
  if (mir_needs_drop(fn->cx->module, field_ty)) {
    const MirValue old = mir_b_emit(&fn->b, MOP_TypeGet, &record, 1, imm, field_ty);
    (void)mir_b_emit(&fn->b, MOP_Drop, &old, 1, (MirImm){0}, MIR_NONE);
  }
  const MirValue operands[2] = {record, value};
  const MirValue updated = mir_b_emit(&fn->b, MOP_TypeSet, operands, 2, imm, mir_b_ty(&fn->b, record));
  return fn_put_place(fn, base, updated);
}

/* Stores the owned `value` (held by no scope) into `place`, the place of an earlier `fn_take_place`. */
bool fn_put_place(LowerFn *fn, const MsExpr *place, MirValue value) {
  MirVar var;
  if (place->kind == MS_E_MEMBER) {
    return set_member(fn, place, value);
  }
  if (!owned_local(fn, place, &var)) {
    return fn_fail(fn, "an assignment does not name an owning local");
  }
  mir_b_def_var(&fn->b, var, value);
  return !fn->failed;
}

static bool lower_assign(LowerFn *fn, const MsStmt *stmt) {
  if (stmt->u.assign.member_target) {
    const MirValue value = take_value(fn, stmt->u.assign.value);
    if (value == MIR_NONE) {
      return false;
    }
    if (mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, value))) {
      disown(fn, value);
    }
    return fn_put_place(fn, stmt->u.assign.target, value);
  }
  /* A name target records its local on the statement, a member target on its expression. */
  const MsRef *ref = ms_facts_ref(fn->facts, stmt->u.assign.target != NULL ? stmt->u.assign.target->id : stmt->id);
  MirVar var = 0;
  if (ref != NULL && ref->kind == MS_REF_LOCAL && ref->local < fn->nvars && fn->vars[ref->local] != 0) {
    var = fn->vars[ref->local] - 1;
  } else if (ref != NULL && ref->kind == MS_REF_PARAM) {
    var = fn->param_vars[ref->local];
  } else {
    return fn_fail(fn, "an assignment does not name a local");
  }
  const MirValue value = take_value(fn, stmt->u.assign.value);
  if (value == MIR_NONE) {
    return false;
  }
  if (var_owns(fn, var)) {
    const MirValue old = mir_b_use_var(&fn->b, var);
    disown(fn, value);
    (void)mir_b_emit(&fn->b, MOP_Drop, &old, 1, (MirImm){0}, MIR_NONE);
  }
  /* A compound assignment's value already reads the target (`a += b` is `a = a + b`). */
  mir_b_def_var(&fn->b, var, value);
  return !fn->failed;
}

/* What a function returns when it ends without a value: nothing, except the entry declared Void, which returns
 * the status 0. */
MirValue fn_default_result(LowerFn *fn) {
  return fn->ret == MIR_INT && fn->b.func.ret == MIR_INT && fn->decl_void ? mir_b_iconst(&fn->b, 0) : MIR_NONE;
}

static bool lower_return(LowerFn *fn, const MsStmt *stmt) {
  MirValue value = MIR_NONE;
  if (stmt->u.expr != NULL) {
    value = take_value(fn, stmt->u.expr);
    if (value == MIR_NONE) {
      return false;
    }
    const MirImm none = {0};
    (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &value, 1, none, MIR_NONE);
  }
  value = fn_result_wrap(fn, value);
  fn_scope_unwind(fn, 0);
  mir_b_ret(&fn->b, value == MIR_NONE ? fn_default_result(fn) : value);
  fn->terminated = true;
  return !fn->failed;
}

/* Lowers a block of statements in a scope of its own. */
static bool lower_block(LowerFn *fn, MsStmts stmts) {
  (void)fn_scope_begin(fn);
  const bool ok = fn_stmts(fn, stmts);
  if (!fn->terminated) {
    fn_scope_end(fn);
  } else {
    fn->nopen--;
  }
  return ok;
}

/* Starts `block` as the current block, sealed once its predecessors are known. */
static void enter(LowerFn *fn, MirBlock block) {
  mir_b_switch_to(&fn->b, block);
  fn->terminated = false;
}

static bool lower_if(LowerFn *fn, const MsStmt *stmt) {
  const MirValue tested = fn_expr(fn, stmt->u.branch.cond, LW_BORROW);
  const MirValue cond = stmt->u.branch.binding != NULL && tested != MIR_NONE ? fn_iflet_test(fn, tested) : tested;
  if (cond == MIR_NONE) {
    return false;
  }
  const MirBlock then = mir_b_new_block(&fn->b);
  const MirBlock otherwise = mir_b_new_block(&fn->b);
  const MirBlock join = mir_b_new_block(&fn->b);
  mir_b_br_if(&fn->b, cond, then, NULL, 0, otherwise, NULL, 0);
  mir_b_seal_block(&fn->b, then);
  mir_b_seal_block(&fn->b, otherwise);
  enter(fn, then);
  if (stmt->u.branch.binding != NULL && !fn_iflet_bind(fn, stmt->u.branch.binding, tested)) {
    return false;
  }
  bool ok = lower_block(fn, stmt->u.branch.body);
  const bool then_ended = fn->terminated;
  if (!then_ended) {
    mir_b_br(&fn->b, join, NULL, 0);
  }
  enter(fn, otherwise);
  ok = lower_block(fn, stmt->u.branch.else_body) && ok;
  const bool else_ended = fn->terminated;
  if (!else_ended) {
    mir_b_br(&fn->b, join, NULL, 0);
  }
  mir_b_seal_block(&fn->b, join);
  enter(fn, join);
  fn->terminated = then_ended && else_ended;
  if (fn->terminated) {
    mir_b_unreachable(&fn->b);
  }
  return ok;
}

static bool lower_while(LowerFn *fn, const MsStmt *stmt) {
  if (fn->nloops == LOWER_MAX_LOOPS) {
    return fn_fail(fn, "loops nest too deeply");
  }
  const MirBlock head = mir_b_new_block(&fn->b);
  const MirBlock body = mir_b_new_block(&fn->b);
  const MirBlock done = mir_b_new_block(&fn->b);
  mir_b_br(&fn->b, head, NULL, 0);
  enter(fn, head);
  const MirValue cond = fn_expr(fn, stmt->u.loop.cond, LW_BORROW);
  if (cond == MIR_NONE) {
    return false;
  }
  mir_b_br_if(&fn->b, cond, body, NULL, 0, done, NULL, 0);
  mir_b_seal_block(&fn->b, body);
  enter(fn, body);
  fn->loops[fn->nloops++] = (LowerLoop){done, head, fn->nopen};
  const bool ok = lower_block(fn, stmt->u.loop.body);
  fn->nloops--;
  if (!fn->terminated) {
    mir_b_br(&fn->b, head, NULL, 0);
  }
  mir_b_seal_block(&fn->b, head);
  mir_b_seal_block(&fn->b, done);
  enter(fn, done);
  return ok;
}

static bool lower_jump(LowerFn *fn, bool is_break) {
  if (fn->nloops == 0) {
    return fn_fail(fn, "`break` or `continue` outside a loop");
  }
  const LowerLoop loop = fn->loops[fn->nloops - 1];
  fn_scope_unwind(fn, loop.depth);
  mir_b_br(&fn->b, is_break ? loop.break_to : loop.continue_to, NULL, 0);
  fn->terminated = true;
  return !fn->failed;
}

static bool lower_stmt(LowerFn *fn, const MsStmt *stmt) {
  mir_b_set_loc(&fn->b, fn_loc(fn, stmt->pos));
  switch ((MsStmtKind)stmt->kind) {
    case MS_S_BIND: return lower_bind(fn, stmt);
    case MS_S_ASSIGN: return lower_assign(fn, stmt);
    case MS_S_CALL: return fn_expr(fn, stmt->u.expr, LW_BORROW) != MIR_NONE || !fn->failed;
    case MS_S_RETURN: return lower_return(fn, stmt);
    case MS_S_BREAK: return lower_jump(fn, true);
    case MS_S_CONTINUE: return lower_jump(fn, false);
    case MS_S_IF: return lower_if(fn, stmt);
    case MS_S_WHILE: return lower_while(fn, stmt);
    case MS_S_FOR: return fn_for(fn, stmt);
  }
  return fn_fail(fn, "unknown statement");
}

bool fn_stmts(LowerFn *fn, MsStmts stmts) {
  for (uint32_t index = 0; index < stmts.len && !fn->terminated; index++) {
    if (!lower_stmt(fn, stmts.ptr[index])) {
      return false;
    }
  }
  return true;
}

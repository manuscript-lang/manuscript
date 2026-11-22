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

/* Binds the names of `pattern` to the parts of `value`: a record pattern reads fields, a list pattern reads
 * elements. The parts are borrowed from `value`, which the binding's source keeps alive. */
static bool bind_parts(LowerFn *fn, const MsPattern *pattern, MirValue value, bool owned) {
  const MirModule *module = fn->cx->module;
  if (pattern->kind == MS_P_NAME) {
    const MsRef *ref = ms_facts_ref(fn->facts, pattern->id);
    if (ref == NULL || ref->kind != MS_REF_LOCAL) {
      return fn_fail(fn, "a bound name has no local");
    }
    mir_b_def_var(&fn->b, fn_local(fn, ref->local, mir_b_ty(&fn->b, value)), value);
    return !fn->failed;
  }
  const MirTyData *data = mir_ty_data(module, mir_b_ty(&fn->b, value));
  if (pattern->kind == MS_P_LIST) {
    if (data->kind != MK_LIST) {
      return fn_fail(fn, "a list pattern binds a list");
    }
    for (uint32_t at = 0; at < pattern->u.list.len; at++) {
      const MirValue args[2] = {value, mir_b_iconst(&fn->b, (int64_t)at)};
      const MirValue element = mir_b_emit(&fn->b, MOP_ListGet, args, 2, (MirImm){0}, data->elem);
      if (!bind_parts(fn, pattern->u.list.ptr[at], element, false)) {
        return false;
      }
    }
    return true;
  }
  if (data->kind != MK_TYPE) {
    return fn_fail(fn, "a field pattern binds a record");
  }
  const MirTypeDef *def = &module->type_defs.ptr[data->id];
  uint32_t taken = 0;
  for (uint32_t at = 0; at < pattern->u.fields.len; at++) {
    const MsPatternField *field = &pattern->u.fields.ptr[at];
    const MsSpan wanted = ms_names_span(fn->cx->program->names, field->name);
    uint32_t found = def->nfields;
    for (uint32_t index = 0; index < def->nfields; index++) {
      const MsSpan have = ms_names_span(&module->names, def->fields[index].name);
      if (ms_span_equal(have, wanted)) {
        found = index;
      }
    }
    if (found == def->nfields) {
      return fn_fail(fn, "a pattern names a field the record does not have");
    }
    const MirImm imm = {.tag = MI_FIELD, .a = data->id, .b = found};
    MirValue part = mir_b_emit(&fn->b, MOP_TypeGet, &value, 1, imm, def->fields[found].ty);
    const bool takes = owned && field->pattern->kind == MS_P_NAME && mir_needs_drop(module, def->fields[found].ty);
    if (takes) { /* a fresh record hands its part to the name; what the pattern leaves out is released with it */
      part = fn_emit(fn, MOP_MoveOut, &part, 1, (MirImm){0}, def->fields[found].ty);
      taken |= found < 32 ? UINT32_C(1) << found : 0;
    }
    if (!bind_parts(fn, field->pattern, part, false)) {
      return false;
    }
  }
  if (taken != 0) {
    (void)mir_b_emit(&fn->b, MOP_TypeRelease, &value, 1, (MirImm){.tag = MI_TYPEMASK, .a = data->id, .b = taken}, MIR_NONE);
  }
  return true;
}

static bool lower_bind(LowerFn *fn, const MsStmt *stmt) {
  const MsPattern *pattern = stmt->u.bind.pattern;
  if (pattern->kind != MS_P_NAME) {
    if (stmt->u.bind.is_mutable) {
      return fn_fail(fn, "a `var` destructuring is not lowered yet");
    }
    const MirValue source = fn_expr(fn, stmt->u.bind.value, LW_BORROW);
    return source != MIR_NONE && bind_parts(fn, pattern, source, fn_fresh_owner(fn, source));
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
  /* A name that converts to a new value (a type to its Optional) owns that value, though it reads another name. */
  const bool fresh = fn_fresh_owner(fn, value);
  if ((!borrow || fresh) && fn_closer_for(fn, closer, ms_facts_type(fn->facts, pattern->id)) &&
      (!mir_needs_drop(fn->cx->module, ty) || fresh)) {
    return fn_bind_closing(fn, local, ms_facts_type(fn->facts, pattern->id), value, stmt->u.bind.is_mutable);
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
bool fn_owned_local(LowerFn *fn, const MsExpr *place, MirVar *out) {
  const MsRef *ref = place->kind == MS_E_NAME ? ms_facts_ref(fn->facts, place->id) : NULL;
  if (ref == NULL) {
    return false;
  }
  if (ref->kind == MS_REF_LOCAL && ref->local < fn->nvars && fn->vars[ref->local] != 0) {
    *out = fn->vars[ref->local] - 1;
    return true;
  }
  if (ref->kind != MS_REF_PARAM || fn->default_call != NULL) { /* a default's parameters are the callee's, not this function's */
    return false;
  }
  if (fn->lambda != NULL) { /* a captured parameter is a variable of the closure body */
    for (uint32_t at = 0; at < fn->lambda->ncaptures; at++) {
      const LowerCapture *capture = &fn->lambda->captures[at];
      if (capture->kind == MS_REF_PARAM && capture->index == ref->local && capture->name == place->u.sym) {
        *out = fn->cap_vars[at];
        return true;
      }
    }
  }
  if (var_owns(fn, fn->param_vars[ref->local])) {
    *out = fn->param_vars[ref->local]; /* a `move` parameter the body assigns into */
    return true;
  }
  for (uint32_t at = 0; at < fn->nvar_params; at++) {
    if (fn->var_params[at].var == fn->param_vars[ref->local]) {
      *out = fn->var_params[at].var;
      return true;
    }
  }
  return false;
}

/* A resource parameter lives in a slot its scope owns, and its variable is a view of that slot: the slot and
 * variable of the parameter `place` names, or false. */
static bool closing_param(const LowerFn *fn, const MsExpr *place, MirValue *slot, MirVar *var) {
  const MsRef *ref = place->kind == MS_E_NAME ? ms_facts_ref(fn->facts, place->id) : NULL;
  if (ref == NULL || ref->kind != MS_REF_PARAM || fn->closing == NULL ||
      fn->nvars + ref->local >= fn->nvars + LOWER_MAX_CLOSING_PARAMS || fn->closing[fn->nvars + ref->local] == MIR_NONE) {
    return false;
  }
  *slot = fn->closing[fn->nvars + ref->local];
  *var = fn->param_vars[ref->local];
  return true;
}

/* The slot of the `var` resource local a name place assigns in, or false. */
static bool closing_local(const LowerFn *fn, const MsExpr *place, MirValue *slot, MirTy *ty) {
  const MsRef *ref = place->kind == MS_E_NAME ? ms_facts_ref(fn->facts, place->id) : NULL;
  if (ref == NULL || ref->kind != MS_REF_LOCAL || ref->local >= fn->nvars || fn->closing == NULL ||
      !fn->closing_var[ref->local]) {
    return false;
  }
  *slot = fn->closing[ref->local];
  *ty = fn->closing_types[ref->local];
  return true;
}

/* Whether `place` is a `var` local, a `var` parameter or a member path rooted in one: the places `fn_put_place` stores into. */
bool fn_place_changeable(LowerFn *fn, const MsExpr *place) {
  MirVar var;
  MirValue slot;
  MirTy ty;
  if (place == NULL) {
    return false;
  }
  return fn_owned_local(fn, place, &var) || closing_local(fn, place, &slot, &ty) || (place->kind == MS_E_MEMBER && fn_place_changeable(fn, place->u.member.left));
}

bool fn_place_owns(LowerFn *fn, const MsExpr *place) {
  MirVar var;
  MirValue slot;
  MirTy ty;
  if (place->kind == MS_E_MEMBER) {
    return fn_place_owns(fn, place->u.member.left);
  }
  return closing_local(fn, place, &slot, &ty) ? mir_needs_drop(fn->cx->module, ty) : fn_owned_local(fn, place, &var) && var_owns(fn, var);
}

/* The owned value of `base`, a place a part of it is assigned in: an owning local's value is taken out (stored
 * back by `fn_put_place`), a member or element path's value is copied. */
bool fn_take_place(LowerFn *fn, const MsExpr *base, MirValue *out) {
  MirVar var;
  if (fn_owned_local(fn, base, &var)) {
    *out = mir_b_use_var(&fn->b, var);
    return true;
  }
  MirValue slot;
  MirTy slot_ty;
  if (closing_local(fn, base, &slot, &slot_ty)) {
    *out = mir_b_emit(&fn->b, mir_needs_drop(fn->cx->module, slot_ty) ? MOP_Take : MOP_Load, &slot, 1,
                      (MirImm){.tag = MI_TY, .a = slot_ty}, slot_ty);
    return true;
  }
  if (closing_param(fn, base, &slot, &var)) {
    const MirTy ty = mir_b_ty(&fn->b, mir_b_use_var(&fn->b, var));
    *out = mir_b_emit(&fn->b, MOP_Take, &slot, 1, (MirImm){.tag = MI_TY, .a = ty}, ty);
    return true;
  }
  MsExpr *index_left = NULL;
  MsExpr *index_key = NULL;
  if (base->kind != MS_E_MEMBER && !ms_expr_index(base, &index_left, &index_key)) {
    return fn_fail(fn, "assignment into this place is not lowered yet (expression kind %d at %u:%u)", (int)base->kind, base->pos.line, base->pos.column);
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

/* `container[key] = value` for an element of a list or map the enclosing assignment took a copy of: the container's
 * own `set` (a list) or `add` (a map) stores it. */
static bool set_element(LowerFn *fn, const MsExpr *container, const MsExpr *key, MirValue value) {
  MsTyTable *types = &fn->cx->program->types;
  const MsTy owner = ms_ty_subst(types, ms_facts_type(fn->facts, container->id), fn->subst.vars, fn->subst.args, fn->subst.count);
  const MirValue receiver = fn_expr(fn, container, LW_BORROW);
  const MirValue at = receiver == MIR_NONE ? MIR_NONE : fn_expr(fn, key, LW_BORROW);
  if (at == MIR_NONE) {
    return false;
  }
  const MirValue args[3] = {receiver, at, value};
  MirValue out = MIR_NONE;
  const MsSpan operation = ms_span_of_text(ms_ty_is(types, owner, MS_BUILTIN_Map) ? "add" : "set");
  if (!fn_native_on(fn, container, owner, operation, 3, args, MIR_VOID, &out)) {
    return fn_fail(fn, "an element of this container cannot be assigned yet");
  }
  return !fn->failed;
}

/* Stores the owned `value` (held by no scope) into `place`, the place of an earlier `fn_take_place`. */
bool fn_put_place(LowerFn *fn, const MsExpr *place, MirValue value) {
  MirVar var;
  if (place->kind == MS_E_MEMBER) {
    return set_member(fn, place, value);
  }
  MsExpr *container = NULL;
  MsExpr *key = NULL;
  if (ms_expr_index(place, &container, &key)) {
    return set_element(fn, container, key, value);
  }
  MirValue slot;
  MirTy slot_ty;
  if (closing_local(fn, place, &slot, &slot_ty)) {
    const MirValue stored[2] = {slot, value};
    (void)mir_b_emit(&fn->b, mir_needs_drop(fn->cx->module, slot_ty) ? MOP_Put : MOP_Store, stored, 2, (MirImm){0}, MIR_NONE);
    return !fn->failed;
  }
  if (closing_param(fn, place, &slot, &var)) {
    const MirTy ty = mir_b_ty(&fn->b, value);
    const MirValue stored[2] = {slot, value};
    (void)mir_b_emit(&fn->b, MOP_Put, stored, 2, (MirImm){0}, MIR_NONE);
    mir_b_def_var(&fn->b, var, mir_b_emit(&fn->b, MOP_Load, &slot, 1, (MirImm){.tag = MI_TY, .a = ty}, ty));
    return !fn->failed;
  }
  if (!fn_owned_local(fn, place, &var)) {
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
  bool resource = false;
  if (ref != NULL && ref->kind == MS_REF_LOCAL && ref->local < fn->nvars && fn->closing != NULL && fn->closing_var[ref->local]) {
    const MirValue value = take_value(fn, stmt->u.assign.value);
    return value != MIR_NONE && fn_closing_assign(fn, ref, value, &resource);
  }
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
    if (fn->terminated) { /* the expression never returns: `return panic(...)` */
      return !fn->failed;
    }
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
  const bool probes = stmt->u.branch.binding != NULL && stmt->u.branch.cond->kind == MS_E_PROBE;
  const bool owns = !probes && stmt->u.branch.binding != NULL && fn_iflet_owns(fn, stmt);
  MirValue entry = MIR_NONE;
  MirTy entry_ty = MIR_VOID;
  MirValue cond = MIR_NONE;
  if (probes) {
    if (!fn_probe_begin(fn, stmt, &cond, &entry, &entry_ty)) {
      return false;
    }
  } else {
    MirValue tested = fn_expr(fn, stmt->u.branch.cond, owns ? LW_MOVE : LW_BORROW);
    if (owns && stmt->u.branch.cond->kind == MS_E_NAME && tested != MIR_NONE) {
      fn_own_result(fn, tested); /* the payload leaves the taken value in the branch that binds it */
    }
    cond = stmt->u.branch.binding != NULL && tested != MIR_NONE ? fn_iflet_test(fn, tested) : tested;
    entry = tested;
  }
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
  (void)fn_scope_begin(fn);
  if (probes && !fn_probe_bind(fn, stmt, entry, entry_ty)) {
    return false;
  }
  if (!probes && stmt->u.branch.binding != NULL && !fn_iflet_bind(fn, stmt->u.branch.binding, entry, owns)) {
    return false;
  }
  bool ok = fn_stmts(fn, stmt->u.branch.body);
  if (probes) {
    fn_probe_end(fn, !fn->terminated);
  }
  if (!fn->terminated) {
    fn_scope_end(fn);
  } else {
    fn->nopen--;
  }
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
  fn->stmt_loc = fn_loc(fn, stmt->pos);
  mir_b_set_loc(&fn->b, fn->stmt_loc);
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

/* A statement whose calls lend temporary resources lowers in a scope of its own: they close where it ends. */
static bool lower_scoped(LowerFn *fn, const MsStmt *stmt) {
  if (fn->temps || !fn_stmt_has_temporary(fn, stmt)) {
    return lower_stmt(fn, stmt);
  }
  (void)fn_scope_begin(fn);
  fn->temps = true;
  const bool ok = lower_stmt(fn, stmt);
  fn->temps = false;
  if (!fn->terminated) {
    fn_scope_end(fn);
  } else {
    fn->nopen--;
  }
  return ok;
}

bool fn_stmts(LowerFn *fn, MsStmts stmts) {
  for (uint32_t index = 0; index < stmts.len && !fn->terminated; index++) {
    if (!lower_scoped(fn, stmts.ptr[index])) {
      return false;
    }
  }
  return true;
}

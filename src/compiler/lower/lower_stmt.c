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
static bool bind_parts(LowerFn *fn, const MsPattern *pattern, MirValue value, bool owned, const MirVar *owner,
                       bool reassignable) {
  const MirModule *module = fn->cx->module;
  if (pattern->kind == MS_P_NAME) {
    const MsRef *ref = ms_facts_ref(fn->facts, pattern->id);
    if (ref == NULL || ref->kind != MS_REF_LOCAL) {
      return fn_fail(fn, "a bound name has no local");
    }
    if (reassignable) { /* `var` takes its own copy of the part, which the name then owns and may reassign */
      const MirTy ty = mir_b_ty(&fn->b, value);
      if (!mir_needs_drop(module, ty)) {
        mir_b_def_var(&fn->b, fn_local(fn, ref->local, ty), value);
        return !fn->failed;
      }
      if (ref->local >= fn->nvars) {
        return fn_fail(fn, "a local binding is outside the function's locals");
      }
      const MirValue copy = fn_emit(fn, MOP_Clone, &value, 1, (MirImm){0}, ty);
      fn->vars[ref->local] = mir_b_declare_var(&fn->b, ty, MM_MOVE) + 1;
      disown(fn, copy);
      mir_b_def_var(&fn->b, fn->vars[ref->local] - 1, copy);
      return fn_scope_own_var(fn, fn->vars[ref->local] - 1) && !fn->failed;
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
      if (!bind_parts(fn, pattern->u.list.ptr[at], element, false, NULL, reassignable)) {
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
      if (owner != NULL) { /* a `var` record keeps what is left and releases it where its scope ends */
        fn_scope_var_moved(fn, *owner, found);
      }
    }
    if (!bind_parts(fn, field->pattern, part, false, NULL, reassignable)) {
      return false;
    }
  }
  if (taken != 0 && owner == NULL) {
    (void)mir_b_emit(&fn->b, MOP_TypeRelease, &value, 1, (MirImm){.tag = MI_TYPEMASK, .a = data->id, .b = taken}, MIR_NONE);
  }
  return true;
}

/* Whether a call reads a value that dies with the statement (`make().get()`): a result that borrows from it
 * cannot outlive the statement. */
static bool call_reads_temporary(const MsFacts *facts, const MsExpr *call) {
  const MsExpr *callee = call->u.call.callee;
  if (callee->kind == MS_E_MEMBER && callee->u.member.left->kind == MS_E_CALL) {
    return true;
  }
  if (callee->kind == MS_E_MEMBER && callee->u.member.left->kind == MS_E_NAME && facts != NULL &&
      facts->last != NULL && facts->last[callee->u.member.left->id] != 0) {
    return true; /* an owner at its last use dies with the call */
  }
  for (uint32_t index = 0; index < call->u.call.args.len; index++) {
    if (call->u.call.args.ptr[index].value->kind == MS_E_CALL) {
      return true;
    }
  }
  return false;
}

/* Whether `value` is the `none` just built: it holds nothing, so the binding that takes it owns all of it. */
static bool is_empty_optional(const LowerFn *fn, MirValue value) {
  const MirInstList *insts = &fn->b.func.blocks.ptr[fn->b.cur].insts;
  if (insts->len == 0 || insts->ptr[insts->len - 1].res != value) {
    return false;
  }
  const MirOp op = (MirOp)insts->ptr[insts->len - 1].op;
  return op == MOP_OptNone;
}

static bool lower_bind(LowerFn *fn, const MsStmt *stmt) {
  const MsPattern *pattern = stmt->u.bind.pattern;
  if (pattern->kind != MS_P_NAME) {
    MirValue source = fn_expr(fn, stmt->u.bind.value, LW_BORROW);
    MirVar owner = 0;
    MirValue taken = MIR_NONE;
    if (source != MIR_NONE && !stmt->u.bind.is_mutable && stmt->u.bind.value->kind == MS_E_NAME &&
        fn_closing_move(fn, stmt->u.bind.value, source, &taken)) {
      /* A record destructured out of a closing slot hands its parts to the names: the slot gives the record up. */
      return bind_parts(fn, pattern, taken, true, NULL, false);
    }
    const bool from_var = source != MIR_NONE && !stmt->u.bind.is_mutable && fn_owned_local(fn, stmt->u.bind.value, &owner);
    return source != MIR_NONE &&
           bind_parts(fn, pattern, source, !stmt->u.bind.is_mutable && (from_var || fn_fresh_owner(fn, source)),
                      from_var ? &owner : NULL, stmt->u.bind.is_mutable);
  }
  /* A name bound to another name borrows it unless the checker marked the read a move (the source is assigned while
   * the binding lives); anything else, and every `var`, is a new owner. */
  const MsExprKind kind = (MsExprKind)stmt->u.bind.value->kind;
  MsExpr *index_container = NULL;
  MsExpr *index_key = NULL;
  bool borrow = !stmt->u.bind.is_mutable &&
                (kind == MS_E_NAME || kind == MS_E_MEMBER || ms_expr_index(stmt->u.bind.value, &index_container, &index_key)) &&
                ms_facts_use(fn->facts, stmt->u.bind.value->id) != MS_USE_MOVE;
  const bool from_call = !stmt->u.bind.is_mutable && kind == MS_E_CALL;
  /* A function bound to a name may take the type that lets its omittable parameters be left out. */
  const MsTy bound_ty = ms_facts_type(fn->facts, pattern->id);
  const MirTy saved_hint = fn->hint;
  if (kind == MS_E_NAME && bound_ty != MS_TY_NONE && ms_ty_kind(&fn->cx->program->types, bound_ty) == MS_TY_FUNCTION) {
    fn->hint = fn_type(fn, bound_ty);
  }
  fn->moving_field = !borrow && !stmt->u.bind.is_mutable && kind == MS_E_MEMBER ? stmt->u.bind.value : NULL;
  MirValue value = borrow || from_call ? fn_expr(fn, stmt->u.bind.value, LW_BORROW) : take_value(fn, stmt->u.bind.value);
  fn->moving_field = NULL;
  if (from_call && value != MIR_NONE && fn_is_borrowed_view(fn, value)) { /* a call whose result borrows */
    if (call_reads_temporary(fn->facts, stmt->u.bind.value) &&
        fn_closer_for(fn, ms_facts_closer(fn->facts, pattern->id), ms_facts_type(fn->facts, pattern->id))) {
      /* A temporary resource closes where its statement ends: a part kept past it is taken out of the temporary. */
      const MirValue owned = fn_take_from_temporary(fn, stmt->u.bind.value, value);
      value = owned != MIR_NONE ? owned : fn_implicit_clone(fn, value, true);
    } else {
      borrow = true;
    }
  }
  fn->hint = saved_hint;
  if (value == MIR_NONE) {
    return false;
  }
  const MirTy ty = mir_b_ty(&fn->b, value);
  const uint32_t local = ms_facts_ref(fn->facts, pattern->id)->local;
  const MsCloser *closer = ms_facts_closer(fn->facts, pattern->id);
  /* A name that converts to a new value (a type to its Optional) owns that value, though it reads another name. */
  const bool fresh = fn_fresh_owner(fn, value) || is_empty_optional(fn, value);
  const bool shared = stmt->u.bind.is_mutable && fn->shared != NULL && local < fn->nvars && fn->shared[local] != 0 &&
                      fn->closing != NULL;
  if (shared || ((!borrow || fresh) && fn_closer_for(fn, closer, ms_facts_type(fn->facts, pattern->id)) &&
                 (!mir_needs_drop(fn->cx->module, ty) || fresh))) {
    return fn_bind_closing_in(fn, fn->bind_scope != 0 ? fn->bind_scope - 1 : fn_scope(fn), local,
                              ms_facts_type(fn->facts, pattern->id), value, stmt->u.bind.is_mutable);
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
  if (fn->local_owns != NULL && local < fn->nvars && (!borrow || fresh) && !stmt->u.bind.is_mutable &&
      mir_needs_drop(fn->cx->module, ty)) {
    fn->local_owns[local] = 1; /* a value the scope owns: an escaping closure may take it */
  } else if (fn->local_owns != NULL && local < fn->nvars && borrow && !fresh && !stmt->u.bind.is_mutable &&
             mir_needs_drop(fn->cx->module, ty)) {
    fn->local_owns[local] = 2; /* a view of another owner's value: moving it out copies it */
  }
  if (!stmt->u.bind.is_mutable && local < fn->nvars && fn->vars[local] == 0 && mir_needs_drop(fn->cx->module, ty)) {
    /* An owned binding that is never assigned again has one value everywhere it is read: no loop or join carries it
     * as a block parameter, which would hide the owner from a later move. */
    fn->vars[local] = mir_b_declare_single(&fn->b, ty, MM_BORROW) + 1;
  }
  if (!stmt->u.bind.is_mutable && local < fn->nvars && fn->vars[local] == 0 && mir_needs_drop(fn->cx->module, ty)) {
    /* An owned binding that is never assigned again has one value everywhere it is read: no loop or join carries it
     * as a block parameter, which would hide the owner from a later move. */
    fn->vars[local] = mir_b_declare_single(&fn->b, ty, MM_BORROW) + 1;
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
  if (fn_closing_at(fn, ref, place->u.sym) != UINT32_MAX) {
    return false; /* it lives in a slot: `closing_local` has it */
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
      if (capture->kind == MS_REF_PARAM && capture->index == ref->local && capture->name == place->u.sym && !capture->shared) {
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
  const uint32_t at = fn_closing_at(fn, ref, place->u.sym);
  if (at == UINT32_MAX) {
    return false;
  }
  *slot = fn->closing[at];
  *ty = fn->closing_types[at];
  return true;
}

/* Whether `expr` is a List (an index into one is an element place; a Map's entry is read out as a copy). */
bool fn_is_list(LowerFn *fn, const MsExpr *expr) {
  MsTyTable *types = &fn->cx->program->types;
  const MsTy owner = ms_ty_subst(types, ms_facts_type(fn->facts, expr->id), fn->subst.vars, fn->subst.args, fn->subst.count);
  return ms_ty_is(types, owner, MS_BUILTIN_List);
}

/* Whether `place` is a `var` local, a `var` parameter or a member path rooted in one: the places `fn_put_place` stores into. */
bool fn_place_changeable(LowerFn *fn, const MsExpr *place) {
  MirVar var;
  MirValue slot;
  MirTy ty;
  if (place == NULL) {
    return false;
  }
  MsExpr *container = NULL;
  MsExpr *key = NULL;
  if (ms_expr_index(place, &container, &key)) { /* an element of a changeable place changes with it */
    return fn_place_changeable(fn, container);
  }
  return fn_owned_local(fn, place, &var) || closing_local(fn, place, &slot, &ty) || closing_param(fn, place, &slot, &var) ||
         (place->kind == MS_E_MEMBER && fn_place_changeable(fn, place->u.member.left));
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
  *out = fn_implicit_clone(fn, inner, true);
  disown(fn, *out);
  return true;
}

/* A field of an owning local or parameter, taken without a copy for a native that changes it in place: `record` is the
 * record, taken out of its variable, and `field` the field's value, which shares its storage with the record until
 * `fn_put_field` stores the changed one. False when `place` is not such a field. */
enum { FIELD_PATH_MAX = 6 };

/* The record fields from the owning root to `place`, outermost first (`holder.reader.names` is `reader`, `names`),
 * and the root's place. False when `place` is not a field path rooted in an owning local or parameter. */
static bool field_path(LowerFn *fn, const MsExpr *place, const MsExpr **fields, uint32_t *count, const MsExpr **root) {
  const MsExpr *chain[FIELD_PATH_MAX];
  uint32_t length = 0;
  const MsExpr *at = place;
  for (;;) {
    const MsRef *ref = at->kind == MS_E_MEMBER ? ms_facts_ref(fn->facts, at->id) : NULL;
    if (ref == NULL || ref->kind != MS_REF_FIELD || length == FIELD_PATH_MAX) {
      return false;
    }
    chain[length++] = at;
    const MsExpr *base = at->u.member.left;
    MirVar var;
    MirValue slot;
    MirTy slot_ty;
    if (fn_owned_local(fn, base, &var) || closing_local(fn, base, &slot, &slot_ty) || closing_param(fn, base, &slot, &var)) {
      *root = base;
      break;
    }
    at = base;
  }
  for (uint32_t index = 0; index < length; index++) {
    fields[index] = chain[length - 1 - index];
  }
  *count = length;
  return true;
}

/* The value of each field of the path, read from the root record `record`; values[0] is `record` itself. */
static bool read_path(LowerFn *fn, const MsExpr **fields, uint32_t count, MirValue record, MirValue *values) {
  values[0] = record;
  for (uint32_t index = 0; index < count; index++) {
    const MirTyData *data = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, values[index]));
    if (data->kind != MK_TYPE) {
      return false;
    }
    const MsRef *ref = ms_facts_ref(fn->facts, fields[index]->id);
    const MirImm imm = {.tag = MI_FIELD, .a = data->id, .b = ref->index};
    values[index + 1] = mir_b_emit(&fn->b, MOP_TypeGet, &values[index], 1, imm, fn_type(fn, ms_facts_type(fn->facts, fields[index]->id)));
  }
  return true;
}

/* A field of an owning local or parameter, or a field path below it, taken without a copy for a native that changes
 * it in place: `record` is the root record, taken out of its variable, and `field` the field's value, which shares its
 * storage with the record until `fn_put_field` stores the changed one. False when `place` is not such a field. */
bool fn_take_field(LowerFn *fn, const MsExpr *place, MirValue *record, MirValue *field) {
  const MsExpr *fields[FIELD_PATH_MAX];
  const MsExpr *root = NULL;
  uint32_t count = 0;
  if (!field_path(fn, place, fields, &count, &root)) {
    return false;
  }
  if (!fn_take_place(fn, root, record)) {
    return false;
  }
  MirValue values[FIELD_PATH_MAX + 1];
  if (!read_path(fn, fields, count, *record, values)) {
    return false;
  }
  *field = values[count];
  if (mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, *field))) {
    /* The field leaves its record for the change, which owns it; `fn_put_field_chain` fills it again. */
    *field = mir_b_emit(&fn->b, MOP_MoveOut, field, 1, (MirImm){0}, mir_b_ty(&fn->b, *field));
  }
  return true;
}

/* Stores `field`, the changed value of the field `fn_take_field` took, back: the old ones share its storage, so they
 * are not dropped. */
bool fn_put_field(LowerFn *fn, const MsExpr *place, MirValue record, MirValue field) {
  return fn_put_field_chain(fn, place, record, field, NULL);
}

/* The same, and `*updated_record` is the root record with the field changed: a later field of the same root is put
 * into that, not into the record the first one replaced. */
bool fn_put_field_chain(LowerFn *fn, const MsExpr *place, MirValue record, MirValue field, MirValue *updated_record) {
  const MsExpr *fields[FIELD_PATH_MAX];
  const MsExpr *root = NULL;
  uint32_t count = 0;
  MirValue values[FIELD_PATH_MAX + 1];
  if (!field_path(fn, place, fields, &count, &root) || !read_path(fn, fields, count, record, values)) {
    return fn_fail(fn, "a changed field is not a field path");
  }
  MirValue updated = field;
  for (uint32_t index = count; index-- > 0;) {
    if (index > 0) { /* an inner record leaves the one above it and goes back into it with the field filled */
      values[index] = mir_b_emit(&fn->b, MOP_MoveOut, &values[index], 1, (MirImm){0}, mir_b_ty(&fn->b, values[index]));
    }
    const MirTyData *data = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, values[index]));
    const MsRef *ref = ms_facts_ref(fn->facts, fields[index]->id);
    const MirImm imm = {.tag = MI_FIELD, .a = data->id, .b = ref->index};
    const MirValue operands[2] = {values[index], updated};
    updated = mir_b_emit(&fn->b, MOP_TypeSet, operands, 2, imm, mir_b_ty(&fn->b, values[index]));
  }
  if (updated_record != NULL) {
    *updated_record = updated;
  }
  return fn_put_place(fn, root, updated);
}

/* The field `place` of the root record `record`, which an earlier field of the same root already took out of its variable. */
bool fn_read_field(LowerFn *fn, const MsExpr *place, MirValue record, MirValue *field) {
  const MsExpr *fields[FIELD_PATH_MAX];
  const MsExpr *root = NULL;
  uint32_t count = 0;
  MirValue values[FIELD_PATH_MAX + 1];
  if (!field_path(fn, place, fields, &count, &root) || !read_path(fn, fields, count, record, values)) {
    return false;
  }
  *field = values[count];
  return true;
}

/* Whether the field paths `a` and `b` start at the same variable. */
bool fn_same_field_root(LowerFn *fn, const MsExpr *a, const MsExpr *b) {
  const MsExpr *fields[FIELD_PATH_MAX];
  const MsExpr *root_a = NULL;
  const MsExpr *root_b = NULL;
  uint32_t count = 0;
  if (!field_path(fn, a, fields, &count, &root_a) || !field_path(fn, b, fields, &count, &root_b)) {
    return false;
  }
  const MsRef *ref_a = ms_facts_ref(fn->facts, root_a->id);
  const MsRef *ref_b = ms_facts_ref(fn->facts, root_b->id);
  return ref_a != NULL && ref_b != NULL && ref_a->kind == ref_b->kind && ref_a->local == ref_b->local;
}

/* Whether two member paths name the same field of the same variable. */
static bool fn_same_member_path(LowerFn *fn, const MsExpr *a, const MsExpr *b) {
  while (a->kind == MS_E_MEMBER && b->kind == MS_E_MEMBER) {
    const MsRef *ra = ms_facts_ref(fn->facts, a->id);
    const MsRef *rb = ms_facts_ref(fn->facts, b->id);
    if (ra == NULL || rb == NULL || ra->kind != MS_REF_FIELD || rb->kind != MS_REF_FIELD || ra->index != rb->index) {
      return false;
    }
    a = a->u.member.left;
    b = b->u.member.left;
  }
  const MsRef *ra = a->kind == MS_E_NAME ? ms_facts_ref(fn->facts, a->id) : NULL;
  const MsRef *rb = b->kind == MS_E_NAME ? ms_facts_ref(fn->facts, b->id) : NULL;
  return ra != NULL && rb != NULL && ra->kind == rb->kind && ra->local == rb->local;
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
  bool moved_out = false; /* an earlier bind took the field: there is nothing to drop */
  for (uint32_t at = 0; at < fn->nmoved_fields; at++) {
    if (fn_same_member_path(fn, fn->moved_fields[at], place)) {
      moved_out = true;
      fn->moved_fields[at] = fn->moved_fields[--fn->nmoved_fields];
      break;
    }
  }
  if (!moved_out && mir_needs_drop(fn->cx->module, field_ty)) {
    const MirValue old = mir_b_emit(&fn->b, MOP_TypeGet, &record, 1, imm, field_ty);
    const MsTy checked = ms_facts_type(fn->facts, place->id);
    if (fn_closer_for(fn, ms_facts_closer(fn->facts, place->id), checked)) {
      if (!fn_close_replaced(fn, checked, old)) { /* a resource the assignment replaces closes, it is not dropped */
        return false;
      }
    } else {
      (void)mir_b_emit(&fn->b, MOP_Drop, &old, 1, (MirImm){0}, MIR_NONE);
    }
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

/* `m[key] op= value` on a map: the compound assignment read the entry, so it exists and the new value replaces the
 * old one at the entry's address; the key is not stored again, so it is not copied. False when `place` is not a map entry. */
static bool update_map_entry(LowerFn *fn, const MsExpr *place, MirValue value, bool *done) {
  MsExpr *container = NULL;
  MsExpr *key = NULL;
  *done = false;
  if (!ms_expr_index(place, &container, &key)) {
    return true;
  }
  const MirValue map = fn_expr(fn, container, LW_BORROW);
  if (map == MIR_NONE) {
    return false;
  }
  const MirTyData *data = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, map));
  if (data->kind != MK_OBJ || data->obj_class != MIR_OBJ_COLLECTION || data->nargs < 2) {
    return true;
  }
  MirTy entry_ty = MIR_VOID;
  const MirValue address = fn_entry_address(fn, map, key, &entry_ty);
  if (address == MIR_NONE) {
    return false;
  }
  const bool owns = mir_needs_drop(fn->cx->module, entry_ty);
  if (owns) {
    const MirValue old = mir_b_emit(&fn->b, MOP_Take, &address, 1, (MirImm){.tag = MI_TY, .a = entry_ty}, entry_ty);
    (void)mir_b_emit(&fn->b, MOP_Drop, &old, 1, (MirImm){0}, MIR_NONE);
  }
  const MirValue stored[2] = {address, value};
  (void)mir_b_emit(&fn->b, owns ? MOP_Put : MOP_Store, stored, 2, (MirImm){0}, MIR_NONE);
  *done = true;
  return !fn->failed;
}

/* Whether `view` is the result of a call that borrows `owner` (`n := cur.get()` views the payload of `cur`). */
static bool views_payload_of(const LowerFn *fn, MirValue view, MirValue owner) {
  for (size_t block = 0; block < fn->b.func.blocks.len; block++) {
    const MirInstList *insts = &fn->b.func.blocks.ptr[block].insts;
    for (size_t at = 0; at < insts->len; at++) {
      const MirInst *inst = &insts->ptr[at];
      if (inst->res == view) {
        MirMode mode = MM_MOVE;
        return inst->nargs != 0 && inst->args[0] == owner && mir_result_mode(fn->cx->module, &fn->b.func, inst, &mode) &&
               mode == MM_BORROW;
      }
    }
  }
  return false;
}

/* `cur = n.next` where `n` views the payload of the owning Optional `cur`: the old payload leaves `cur`, its field
 * moves into the new value and the rest of it is released, so a walk along a list does not copy what is left of it.
 * `value` is the new value, or MIR_NONE when the assignment is not that shape. */
static MirValue take_field_of_old(LowerFn *fn, const MsStmt *stmt, MirVar var) {
  const MsExpr *member = stmt->u.assign.value;
  const MsRef *ref = member->kind == MS_E_MEMBER ? ms_facts_ref(fn->facts, member->id) : NULL;
  if (ref == NULL || ref->kind != MS_REF_FIELD || ms_facts_use(fn->facts, member->id) != MS_USE_MOVE || !var_owns(fn, var)) {
    return MIR_NONE;
  }
  const MirValue old = mir_b_use_var(&fn->b, var);
  const MirTyData *old_data = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, old));
  if (old_data->kind != MK_OPT || !mir_needs_drop(fn->cx->module, old_data->elem)) {
    return MIR_NONE;
  }
  const MirValue view = fn_expr(fn, member->u.member.left, LW_BORROW);
  if (view == MIR_NONE || !views_payload_of(fn, view, old)) {
    return MIR_NONE;
  }
  const MirTy elem = old_data->elem;
  const MirTyData *record = mir_ty_data(fn->cx->module, elem);
  if (record->kind != MK_TYPE) {
    return MIR_NONE;
  }
  const MirImm imm = {.tag = MI_FIELD, .a = record->id, .b = ref->index};
  const MirValue item = mir_b_emit(&fn->b, MOP_OptUnbox, &old, 1, (MirImm){0}, elem);
  const MirTy field_ty = fn_type(fn, ms_facts_type(fn->facts, member->id));
  const MirValue field = mir_b_emit(&fn->b, MOP_TypeGet, &item, 1, imm, field_ty);
  const MirValue taken = mir_b_emit(&fn->b, MOP_MoveOut, &field, 1, (MirImm){0}, field_ty);
  const MirImm mask = {.tag = MI_TYPEMASK, .a = record->id, .b = ref->index < 32 ? UINT32_C(1) << ref->index : 0};
  (void)mir_b_emit(&fn->b, MOP_TypeRelease, &item, 1, mask, MIR_NONE);
  return taken;
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
    bool done = false;
    if (stmt->u.assign.has_compound && (!update_map_entry(fn, stmt->u.assign.target, value, &done) || done)) {
      return done && !fn->failed;
    }
    return fn_put_place(fn, stmt->u.assign.target, value);
  }
  /* A name target records its local on the statement, a member target on its expression. */
  const MsRef *ref = ms_facts_ref(fn->facts, stmt->u.assign.target != NULL ? stmt->u.assign.target->id : stmt->id);
  MirVar var = 0;
  bool resource = false;
  const MsName assigned = stmt->u.assign.target != NULL && stmt->u.assign.target->kind == MS_E_NAME ? stmt->u.assign.target->u.sym : stmt->u.assign.name;
  if (fn_closing_at(fn, ref, assigned) != UINT32_MAX) {
    const MirValue value = take_value(fn, stmt->u.assign.value);
    return value != MIR_NONE && fn_closing_assign(fn, ref, assigned, value, &resource);
  }
  if (ref != NULL && ref->kind == MS_REF_LOCAL && ref->local < fn->nvars && fn->vars[ref->local] != 0) {
    var = fn->vars[ref->local] - 1;
  } else if (ref != NULL && ref->kind == MS_REF_PARAM) {
    var = fn->param_vars[ref->local];
  } else {
    return fn_fail(fn, "an assignment does not name a local");
  }
  fn->nmoved_names = 0;
  const MirValue advanced = take_field_of_old(fn, stmt, var);
  if (advanced != MIR_NONE) { /* the old value is gone: nothing is left to drop */
    mir_b_def_var(&fn->b, var, advanced);
    return !fn->failed;
  }
  const MirValue value = take_value(fn, stmt->u.assign.value);
  if (value == MIR_NONE) {
    return false;
  }
  if (var_owns(fn, var)) {
    const MirValue old = mir_b_use_var(&fn->b, var);
    disown(fn, value);
    bool handed_on = false; /* `x = f(x)` moved the old value into the new one */
    for (uint32_t at = 0; at < fn->nmoved_names; at++) {
      handed_on |= fn->moved_names[at] == old;
    }
    if (!handed_on) {
      (void)mir_b_emit(&fn->b, MOP_Drop, &old, 1, (MirImm){0}, MIR_NONE);
    }
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
    value = fn->returns_borrow ? fn_expr(fn, stmt->u.expr, LW_BORROW) : take_value(fn, stmt->u.expr);
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
  /* `return x` over an owning `var` hands its value on: the unwind must not own it again. */
  MirVar returned = 0;
  const bool hands_on = stmt->u.expr != NULL && stmt->u.expr->kind == MS_E_NAME && value != MIR_NONE &&
                        ms_facts_use(fn->facts, stmt->u.expr->id) == MS_USE_MOVE && fn_owned_local(fn, stmt->u.expr, &returned) &&
                        mir_b_use_var(&fn->b, returned) == value;
  if (hands_on) {
    fn_scope_var_released(fn, returned, true);
  }
  fn_scope_unwind(fn, 0);
  if (hands_on) {
    fn_scope_var_released(fn, returned, false);
  }
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
  MsExpr *probe_left = NULL;
  MsExpr *probe_key = NULL;
  const bool probes = fn_probe_parts(fn, stmt, &probe_left, &probe_key);
  bool owns = !probes && stmt->u.branch.binding != NULL && fn_iflet_owns(fn, stmt);
  const bool from_call = stmt->u.branch.cond->kind == MS_E_CALL;
  MirValue entry = MIR_NONE;
  MirTy entry_ty = MIR_VOID;
  MirValue cond = MIR_NONE;
  if (probes) {
    if (!fn_probe_begin(fn, stmt, &cond, &entry, &entry_ty)) {
      return false;
    }
  } else {
    MirValue tested = fn_expr(fn, stmt->u.branch.cond, owns && !from_call ? LW_MOVE : LW_BORROW);
    if (owns && from_call && tested != MIR_NONE && fn_is_borrowed_view(fn, tested)) {
      /* A call that answers a part of something else is a view, unless it answers a temporary the binding can take. */
      const MirValue taken = fn_take_from_temporary(fn, stmt->u.branch.cond, tested);
      owns = taken != MIR_NONE;
      tested = owns ? taken : tested;
      if (owns && mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, tested))) {
        fn_own(fn, fn_scope(fn), tested); /* the payload taken from the temporary is the scope's until the branch binds it */
      }
    }
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
  const bool writes_back = !probes && !owns && stmt->u.branch.is_mutable && stmt->u.branch.binding != NULL &&
                           fn_iflet_writeback(fn, stmt, entry);
  bool ok = fn_stmts(fn, stmt->u.branch.body);
  if (probes || writes_back) {
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

/* An expression statement discards its value; a fresh resource that value holds closes with the scope. */
static MsTy discarded_type(LowerFn *fn, const MsExpr *expr) {
  return ms_ty_subst(&fn->cx->program->types, ms_facts_type(fn->facts, expr->id), fn->subst.vars, fn->subst.args,
                     fn->subst.count);
}

static bool lower_call_stmt(LowerFn *fn, const MsStmt *stmt) {
  const MsExpr *expr = stmt->u.expr;
  const MirValue value = fn_expr(fn, expr, LW_BORROW);
  if (value == MIR_NONE) {
    return !fn->failed;
  }
  const MsTy checked = discarded_type(fn, expr);
  const bool owned = fn_fresh_owner(fn, value) ||
                     (!mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, value)) && !fn_is_borrowed_view(fn, value));
  if (expr->kind == MS_E_CALL && checked != MS_TY_NONE && owned && fn_temp_closes(fn, checked)) {
    fn_own_temporary(fn, checked, value);
  }
  return !fn->failed;
}

static bool lower_stmt(LowerFn *fn, const MsStmt *stmt) {
  fn->stmt_loc = fn_loc(fn, stmt->pos);
  mir_b_set_loc(&fn->b, fn->stmt_loc);
  switch ((MsStmtKind)stmt->kind) {
    case MS_S_BIND: return lower_bind(fn, stmt);
    case MS_S_ASSIGN: return lower_assign(fn, stmt);
    case MS_S_CALL: return lower_call_stmt(fn, stmt);
    case MS_S_RETURN: return lower_return(fn, stmt);
    case MS_S_BREAK: return lower_jump(fn, true);
    case MS_S_CONTINUE: return lower_jump(fn, false);
    case MS_S_IF: return lower_if(fn, stmt);
    case MS_S_WHILE: return lower_while(fn, stmt);
    case MS_S_FOR: return fn_for(fn, stmt);
  }
  return fn_fail(fn, "unknown statement");
}

/* A statement whose calls borrow temporary resources lowers in a scope of its own: they close where it ends. */
static bool lower_scoped(LowerFn *fn, const MsStmt *stmt) {
  const bool discards = stmt->kind == MS_S_CALL && stmt->u.expr->kind == MS_E_CALL && fn->closing != NULL &&
                        discarded_type(fn, stmt->u.expr) != MS_TY_NONE && fn_temp_closes(fn, discarded_type(fn, stmt->u.expr));
  if (fn->temps || !(discards || fn_stmt_has_temporary(fn, stmt))) {
    return lower_stmt(fn, stmt);
  }
  fn->bind_scope = stmt->kind == MS_S_BIND ? fn_scope(fn) + 1 : 0;
  (void)fn_scope_begin(fn);
  fn->temps = true;
  const bool ok = lower_stmt(fn, stmt);
  fn->temps = false;
  fn->bind_scope = 0;
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

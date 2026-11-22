/* compiler/lower/lower_call.c: calls to module functions (with their type arguments and default arguments)
 * and to runtime functions declared `extern fn`. */
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_analysis.h"

const MsCall *fn_find_call(const MsFacts *facts, MsNode node) {
  size_t lo = 0;
  size_t hi = facts->calls.len;
  while (lo < hi) {
    const size_t mid = lo + (hi - lo) / 2;
    if (facts->calls.ptr[mid].node < node) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo < facts->calls.len && facts->calls.ptr[lo].node == node ? &facts->calls.ptr[lo] : NULL;
}

/* The symbol a function reference names: the symbol declared by that node of that module. */
MsSymbolId fn_symbol_at(const Lower *cx, MsNodeRef decl) {
  const MsSymbolList *symbols = &cx->program->symbols;
  for (MsSymbolId id = 1; id < symbols->len; id++) {
    const MsSymbol *symbol = &symbols->ptr[id];
    if (symbol->module == decl.module && symbol->decl != NULL && symbol->decl->id == decl.node) {
      return id;
    }
  }
  return 0;
}

/* The expression a written argument names. */
static const MsExpr *written_arg(const MsExpr *call, MsNode node) {
  for (uint32_t index = 0; index < call->u.call.args.len; index++) {
    if (call->u.call.args.ptr[index].value->id == node) {
      return call->u.call.args.ptr[index].value;
    }
  }
  /* The receiver of a method call is written before the dot. */
  const MsExpr *callee = call->u.call.callee;
  return callee->kind == MS_E_MEMBER && callee->u.member.left->id == node ? callee->u.member.left : NULL;
}

/* The parameter or field of declaration `decl` whose default expression is node `node`. */
static const MsParam *declared_default(const MsDecl *decl, uint32_t case_index, MsNode node) {
  const MsParams *list = NULL;
  if (decl != NULL && decl->kind == MS_D_FN) {
    list = &decl->u.fn.params;
  } else if (decl != NULL && decl->kind == MS_D_TYPE) {
    list = &decl->u.type.fields;
  } else if (decl != NULL && decl->kind == MS_D_ENUM && case_index < decl->u.enumeration.cases.len) {
    list = &decl->u.enumeration.cases.ptr[case_index]->fields;
  }
  for (uint32_t index = 0; list != NULL && index < list->len; index++) {
    if (list->ptr[index]->def != NULL && list->ptr[index]->def->id == node) {
      return list->ptr[index];
    }
  }
  return NULL;
}

/* A default argument is written in the callee's module: its names and types come from that module's facts. */
static MirValue default_arg(LowerFn *fn, const MsCall *call, const MsCallArg *arg, MirTy expected) {
  const MsFacts *saved_facts = fn->facts;
  const uint32_t saved_file = fn->file;
  fn->facts = &fn->cx->program->modules.ptr[arg->node.module].facts;
  fn->file = lower_file(fn->cx, arg->node.module);
  const MsSymbol *callee = &fn->cx->program->symbols.ptr[fn_symbol_at(fn->cx, call->callee.decl)];
  const MsParam *param = declared_default(callee->decl, call->callee.index, arg->node.node);
  const MirTy saved_hint = fn->hint;
  fn->hint = expected;
  const MirValue value = param != NULL ? fn_expr(fn, param->def, LW_MOVE) : MIR_NONE;
  fn->hint = saved_hint;
  fn->facts = saved_facts;
  fn->file = saved_file;
  return value;
}

static bool is_literal(const MsExpr *expr) {
  return expr->kind == MS_E_TEXT && (expr->u.text.len == 0 || (expr->u.text.len == 1 && expr->u.text.ptr[0].expr == NULL));
}

/* A `var` argument of a source function: the place it names, and the slot the callee changes it in. */
typedef struct VarSlot {
  const MsExpr *place;
  MirValue slot;
  MirTy ty;
} VarSlot;

/* Moves the value of `place` into a new slot and returns the slot's address. */
static MirValue var_slot(LowerFn *fn, const MsExpr *place, VarSlot *out) {
  MirValue owned;
  const bool is_place = place->kind == MS_E_NAME || place->kind == MS_E_MEMBER || place->kind == MS_E_INDEX;
  if (is_place) {
    if (!fn_take_place(fn, place, &owned)) {
      return MIR_NONE;
    }
  } else {
    /* A temporary: the callee changes it and what is left is dropped after the call. */
    owned = fn_expr(fn, place, LW_MOVE);
    if (owned != MIR_NONE && mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, owned))) {
      (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &owned, 1, (MirImm){0}, MIR_NONE);
    }
  }
  if (owned == MIR_NONE) {
    return MIR_NONE;
  }
  const MirTy ty = mir_b_ty(&fn->b, owned);
  const MirImm of_type = {.tag = MI_TY, .a = ty};
  const MirValue slot = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, of_type, MIR_PTR);
  const MirValue stored[2] = {slot, owned};
  (void)mir_b_emit(&fn->b, mir_needs_drop(fn->cx->module, ty) ? MOP_Put : MOP_Store, stored, 2, (MirImm){0}, MIR_NONE);
  *out = (VarSlot){is_place ? place : NULL, slot, ty};
  return slot;
}

/* After the call: each slot's value goes back into the place it came from. */
static bool var_slots_back(LowerFn *fn, const VarSlot *slots, uint32_t count) {
  for (uint32_t at = 0; at < count; at++) {
    const MirImm of_type = {.tag = MI_TY, .a = slots[at].ty};
    const MirValue updated = mir_b_emit(&fn->b, mir_needs_drop(fn->cx->module, slots[at].ty) ? MOP_Take : MOP_Load,
                                        &slots[at].slot, 1, of_type, slots[at].ty);
    if (slots[at].place == NULL) {
      if (mir_needs_drop(fn->cx->module, slots[at].ty)) {
        (void)mir_b_emit(&fn->b, MOP_Drop, &updated, 1, (MirImm){0}, MIR_NONE);
      }
    } else if (!fn_put_place(fn, slots[at].place, updated)) {
      return false;
    }
  }
  return true;
}

static bool lower_args(LowerFn *fn, const MsExpr *expr, const MsCall *call, MirValue *out, VarSlot *slots,
                       uint32_t *nslots, bool receiver_var) {
  for (uint32_t index = 0; index < call->arg_count; index++) {
    const MsCallArg *arg = &call->args[index];
    if (arg->source == MS_ARG_WRITTEN && slots != NULL && ((arg->flags & MS_PARAM_VAR) != 0 || (index == 0 && receiver_var)) &&
        *nslots < 16) {
      const MsExpr *place = written_arg(expr, arg->node.node);
      out[index] = place != NULL ? var_slot(fn, place, &slots[(*nslots)++]) : MIR_NONE;
    } else if (arg->source == MS_ARG_WRITTEN) {
      const MsExpr *written = written_arg(expr, arg->node.node);
      /* A constructor's fields own what they are given. */
      const bool owning = call->callee.kind == MS_REF_TYPE || call->callee.kind == MS_REF_CASE;
      const LowerWant want = owning || (arg->flags & MS_PARAM_MOVE) != 0 ? LW_MOVE : LW_BORROW;
      out[index] = written != NULL ? fn_expr(fn, written, want) : MIR_NONE;
      if (want == LW_MOVE && out[index] != MIR_NONE && is_literal(written)) {
        /* A literal is static, so what owns it holds a copy. */
        out[index] = fn_emit(fn, MOP_Clone, &out[index], 1, (MirImm){0}, mir_b_ty(&fn->b, out[index]));
      }
    } else if (arg->source == MS_ARG_DEFAULT) {
      const MsTyTable *types = &fn->cx->program->types;
      const size_t declared = ms_ty_param_count(types, call->callee_ty);
      const size_t at = index >= call->arg_count - declared ? index - (call->arg_count - declared) : 0;
      out[index] = default_arg(fn, call, arg, fn_type(fn, ms_ty_params(types, call->callee_ty)[at].ty));
    } else {
      const MsTy param = ms_ty_params(&fn->cx->program->types, call->callee_ty)[index].ty;
      const MirTy ty = fn_type(fn, param);
      out[index] = ty == MIR_VOID ? mir_b_unit(&fn->b) : fn_emit(fn, MOP_OptNone, NULL, 0, (MirImm){0}, ty);
    }
    if (out[index] == MIR_NONE) {
      return fn_fail(fn, "an argument has no value");
    }
  }
  return true;
}

/* The runtime function an `extern fn` declares, from the callee's type. */
static uint32_t runtime_function(LowerFn *fn, const MsSymbol *symbol, MirTy ret) {
  const MsTyTable *types = &fn->cx->program->types;
  const uint32_t count = (uint32_t)ms_ty_param_count(types, symbol->ty);
  const MsTyParam *params = ms_ty_params(types, symbol->ty);
  MirParam *mir_params = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, MirParam, (size_t)count + 1);
  for (uint32_t index = 0; index < count; index++) {
    mir_params[index] = (MirParam){fn_type(fn, params[index].ty), (uint8_t)MM_BORROW};
  }
  const MirExtern def = {.name = mir_name(fn->cx->module, ms_names_span(fn->cx->program->names, symbol->name)),
                         .params = mir_params,
                         .nparams = count,
                         .ret = ret};
  return mir_extern_intern(fn->cx->module, &def);
}

/* The method-table entry of the method declared by `node` in `module`. */
static const MsMethodEntry *find_entry(const Lower *cx, uint32_t module, MsNode node) {
  for (size_t index = 0; index < cx->program->methods.len; index++) {
    const MsMethodEntry *entry = &cx->program->methods.ptr[index];
    if (entry->module == module && entry->source->id == node) {
      return entry;
    }
  }
  return NULL;
}

/* What a call names, as something to lower: a module function or a method with a body. False for any other
 * callee (a runtime function, an operation, a builtin). */
static bool callee_target(LowerFn *fn, const MsCall *call, LowerTarget *out) {
  Lower *cx = fn->cx;
  if (call->callee.kind == MS_REF_FUNCTION) {
    const MsSymbolId id = fn_symbol_at(cx, call->callee.decl);
    if (id == 0 || cx->program->symbols.ptr[id].native != MS_NATIVE_SOURCE) {
      return false;
    }
    *out = lower_symbol_target(cx, id);
    return true;
  }
  if (call->callee.kind != MS_REF_METHOD) {
    return false;
  }
  const MsMethodEntry *entry = find_entry(cx, call->callee.decl.module, call->callee.decl.node);
  if (entry == NULL || entry->source->func.external) {
    return false;
  }
  *out = (LowerTarget){entry->module, entry->source->id, &entry->source->func, entry->source->func.name, entry->ty,
                       {NULL, 0}, entry->variables.ptr, (uint32_t)entry->variables.len, MS_TY_NONE, 0, false};
  out->receiver = entry->receiver;
  out->receiver_flags = (uint8_t)((entry->source->mutating ? MS_PARAM_VAR : 0) | (entry->source->consuming ? MS_PARAM_MOVE : 0));
  return true;
}

/* A call of an interface operation on a value of a bound variable (`item.clone()` with `T: Clonable`): the
 * instance knows the concrete receiver type, so the call is the method that type implements, or the structural
 * copy when it has none. */
static MirValue call_bound_operation(LowerFn *fn, const MsExpr *expr, const MsCall *call, const MirValue *args, MirTy ret) {
  const MsExpr *callee = expr->u.call.callee;
  if (callee->kind != MS_E_MEMBER || call->arg_count == 0) {
    (void)fn_fail(fn, "an interface operation needs an interface receiver");
    return MIR_NONE;
  }
  const MsTy receiver = ms_ty_subst(&fn->cx->program->types, ms_facts_type(fn->facts, callee->u.member.left->id),
                                    fn->subst.vars, fn->subst.args, fn->subst.count);
  const uint32_t method = lower_operation_method(fn->cx, receiver, callee->u.member.name);
  if (method != MIR_NONE) {
    const MirValue result = mir_b_call(&fn->b, method, args, call->arg_count);
    fn_own_result(fn, result);
    return result;
  }
  const MsSpan operation = ms_names_span(fn->cx->program->names, callee->u.member.name);
  if (!ms_span_is_text(operation, "clone") || call->arg_count != 1) {
    (void)fn_fail(fn, "the operation `%.*s` on a bound value is not lowered yet", (int)operation.len, (const char *)operation.ptr);
    return MIR_NONE;
  }
  return mir_needs_drop(fn->cx->module, ret) ? fn_emit(fn, MOP_Clone, args, 1, (MirImm){0}, ret) : args[0];
}

/* A call of an interface operation: dispatched through the receiver's vtable. */
static MirValue call_operation(LowerFn *fn, const MsExpr *expr, const MsCall *call, const MirValue *args, MirTy ret) {
  const MirTyData *data = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, args[0]));
  if (data->kind != MK_IFACE) {
    return call_bound_operation(fn, expr, call, args, ret);
  }
  const MirImm imm = {.tag = MI_METHOD, .a = data->id, .b = call->callee.index};
  return fn_emit(fn, MOP_CallMethod, args, call->arg_count, imm, ret);
}

/* `Case(payload...)`: an alternative's case built from its payload. */
static MirValue construct_case(LowerFn *fn, const MsCall *call, const MirValue *args, MirTy ty) {
  const MirTyData *data = mir_ty_data(fn->cx->module, ty);
  if (data->kind != MK_ALT) {
    (void)fn_fail(fn, "a case is built into an alternative");
    return MIR_NONE;
  }
  const MirImm imm = {.tag = MI_CASE, .a = data->id, .b = call->callee.index};
  return fn_emit(fn, MOP_AltNew, args, call->arg_count, imm, ty);
}

/* `Type(fields...)`: the record built from its arguments in field order. */
static MirValue construct(LowerFn *fn, const MsCall *call, const MirValue *args, MirTy ty) {
  const MirTyData *data = mir_ty_data(fn->cx->module, ty);
  if (data->kind == MK_LIST) {
    /* `List[T](reserve: n)`: the optional reserve is the starting capacity, none reserves nothing. */
    MirValue capacity = mir_b_iconst(&fn->b, 0);
    if (call->arg_count == 1 && mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, args[0]))->kind == MK_OPT) {
      const MirValue present = fn_emit(fn, MOP_OptIsSome, &args[0], 1, (MirImm){0}, MIR_BOOL);
      const MirValue wanted = fn_emit(fn, MOP_OptGet, &args[0], 1, (MirImm){0}, MIR_INT);
      capacity = mir_b_select(&fn->b, present, wanted, capacity);
    }
    return mir_b_list_new(&fn->b, data->elem, capacity);
  }
  if (data->kind == MK_OBJ && data->obj_class == MIR_OBJ_COLLECTION) {
    return fn_runtime_call(fn, mir_name(fn->cx->module, ms_span_of_text("msrt_map_new")), NULL, 0, ty);
  }
  if (data->kind != MK_TYPE) {
    (void)fn_fail(fn, "a value of this type cannot be built by its name yet (MIR kind %d, %u arguments, first source %d)", (int)data->kind, call->arg_count, call->arg_count > 0 ? (int)call->args[0].source : -1);
    return MIR_NONE;
  }
  const MirImm imm = {.tag = MI_TYPE, .a = data->id};
  return fn_emit(fn, MOP_TypeNew, args, call->arg_count, imm, ty);
}

/* Whether a native callee is an operation of a receiver (not an `extern fn`, which call_runtime handles). */
static bool callee_is_operation(LowerFn *fn, const MsCall *call) {
  const MsSymbolId id = fn_symbol_at(fn->cx, call->callee.decl);
  return id == 0 || fn->cx->program->symbols.ptr[id].native != MS_NATIVE_EXTERN;
}

static MirValue call_runtime(LowerFn *fn, const MsCall *call, const MirValue *args, MirTy ret) {
  const MsSymbolId id = fn_symbol_at(fn->cx, call->callee.decl);
  if (id == 0 || fn->cx->program->symbols.ptr[id].native != MS_NATIVE_EXTERN) {
    (void)fn_fail(fn, "this callee is not lowered yet (reference kind %d)", (int)call->callee.kind);
    return MIR_NONE;
  }
  const uint32_t external = runtime_function(fn, &fn->cx->program->symbols.ptr[id], ret);
  const MirValue result = mir_b_call_rt(&fn->b, external, args, call->arg_count);
  fn_own_result(fn, result);
  return result;
}

MirValue fn_call(LowerFn *fn, const MsExpr *expr, LowerWant want) {
  (void)want;
  const MsCall *call = fn_find_call(fn->facts, expr->id);
  /* A callee that is a parameter or local, or any expression with no declaration behind it (`fs[i]()`), is a value. */
  const bool named = expr->u.call.callee->kind == MS_E_NAME;
  const bool value_callee = call == NULL || call->callee.kind == MS_REF_NONE ||
                            (named && (call->callee.kind == MS_REF_PARAM || call->callee.kind == MS_REF_LOCAL));
  if (value_callee && (named || call != NULL)) {
    return fn_call_value(fn, expr, call != NULL && named && call->callee.kind != MS_REF_NONE ? &call->callee : NULL);
  }
  if (call == NULL || call->arg_count > 16) {
    (void)fn_fail(fn, "the checker recorded no usable call at %u:%u (node %u, %u calls)", expr->pos.line, expr->pos.column, expr->id, (unsigned)fn->facts->calls.len);
    return MIR_NONE;
  }
  MirValue args[16];
  VarSlot slots[16];
  uint32_t nslots = 0;
  LowerTarget target;
  const bool source = (call->callee.kind == MS_REF_FUNCTION || call->callee.kind == MS_REF_METHOD) &&
                      callee_target(fn, call, &target);
  const bool receiver_var = source && call->callee.kind == MS_REF_METHOD && (target.receiver_flags & MS_PARAM_VAR) != 0;
  if (!lower_args(fn, expr, call, args, source ? slots : NULL, &nslots, receiver_var)) {
    return MIR_NONE;
  }
  const MirTy ret = fn_type(fn, ms_facts_type(fn->facts, expr->id));
  mir_b_set_loc(&fn->b, fn_loc(fn, expr->pos));
  if (call->callee.kind == MS_REF_TYPE) {
    return construct(fn, call, args, ret);
  }
  if (call->callee.kind == MS_REF_OPERATION) {
    return call_operation(fn, expr, call, args, ret);
  }
  if (call->callee.kind == MS_REF_CASE) {
    return construct_case(fn, call, args, ret);
  }
  if (call->callee.kind == MS_REF_NATIVE && callee_is_operation(fn, call)) {
    return fn_native_call(fn, expr, call, args, ret);
  }
  if (!source) {
    return call_runtime(fn, call, args, ret);
  }
  MsTy bound[16] = {0};
  const MsTy *type_args = call->type_args;
  uint32_t ntype_args = call->type_arg_count;
  if (target.variables != NULL) {
    /* A method's variables are the receiver form's and its own: bind them against the instantiated signature. */
    if (target.nvariables > 16 || !ms_check_unify(&fn->cx->program->types, target.ty, call->callee_ty, target.variables,
                                                  target.nvariables, bound)) {
      (void)fn_fail(fn, "a method's type arguments could not be found from its call");
      return MIR_NONE;
    }
    type_args = bound;
    ntype_args = target.nvariables;
  }
  const uint32_t func = lower_instance(fn->cx, &target, type_args, ntype_args, &fn->subst);
  if (func == MIR_NONE) {
    return MIR_NONE;
  }
  const MirValue result = mir_b_call(&fn->b, func, args, call->arg_count);
  fn_own_result(fn, result);
  return var_slots_back(fn, slots, nslots) ? result : MIR_NONE;
}

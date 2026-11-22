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

/* A default argument is written in the callee's module: its names and types come from that module's facts. */
static MirValue default_arg(LowerFn *fn, const MsCall *call, const MsCallArg *arg) {
  const MsFacts *saved_facts = fn->facts;
  const uint32_t saved_file = fn->file;
  fn->facts = &fn->cx->program->modules.ptr[arg->node.module].facts;
  fn->file = lower_file(fn->cx, arg->node.module);
  const MsParam *param = NULL;
  const MsSymbol *callee = &fn->cx->program->symbols.ptr[fn_symbol_at(fn->cx, call->callee.decl)];
  for (uint32_t index = 0; callee->decl != NULL && index < callee->decl->u.fn.params.len; index++) {
    if (callee->decl->u.fn.params.ptr[index]->def != NULL && callee->decl->u.fn.params.ptr[index]->def->id == arg->node.node) {
      param = callee->decl->u.fn.params.ptr[index];
    }
  }
  const MirValue value = param != NULL ? fn_expr(fn, param->def, LW_MOVE) : MIR_NONE;
  fn->facts = saved_facts;
  fn->file = saved_file;
  return value;
}

static bool lower_args(LowerFn *fn, const MsExpr *expr, const MsCall *call, MirValue *out) {
  for (uint32_t index = 0; index < call->arg_count; index++) {
    const MsCallArg *arg = &call->args[index];
    if (arg->source == MS_ARG_WRITTEN) {
      const MsExpr *written = written_arg(expr, arg->node.node);
      /* A constructor's fields own what they are given. */
      const bool owning = call->callee.kind == MS_REF_TYPE || call->callee.kind == MS_REF_CASE;
      const LowerWant want = owning || (arg->flags & MS_PARAM_MOVE) != 0 ? LW_MOVE : LW_BORROW;
      out[index] = written != NULL ? fn_expr(fn, written, want) : MIR_NONE;
    } else if (arg->source == MS_ARG_DEFAULT) {
      out[index] = default_arg(fn, call, arg);
    } else {
      return fn_fail(fn, "an omitted argument is not lowered yet");
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
                       {NULL, 0}, entry->variables.ptr, (uint32_t)entry->variables.len};
  return true;
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
  if (data->kind != MK_TYPE) {
    (void)fn_fail(fn, "only a record can be built by its name for now");
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
  const bool value_callee = call != NULL && (call->callee.kind == MS_REF_PARAM || call->callee.kind == MS_REF_LOCAL);
  if ((call == NULL || value_callee) && expr->u.call.callee->kind == MS_E_NAME) {
    return fn_call_value(fn, expr, call != NULL ? &call->callee : NULL);
  }
  if (call == NULL || call->arg_count > 16) {
    (void)fn_fail(fn, "the checker recorded no usable call at %u:%u (node %u, %u calls)", expr->pos.line, expr->pos.column, expr->id, (unsigned)fn->facts->calls.len);
    return MIR_NONE;
  }
  MirValue args[16];
  if (!lower_args(fn, expr, call, args)) {
    return MIR_NONE;
  }
  const MirTy ret = fn_type(fn, ms_facts_type(fn->facts, expr->id));
  mir_b_set_loc(&fn->b, fn_loc(fn, expr->pos));
  if (call->callee.kind == MS_REF_TYPE) {
    return construct(fn, call, args, ret);
  }
  if (call->callee.kind == MS_REF_CASE) {
    return construct_case(fn, call, args, ret);
  }
  if (call->callee.kind == MS_REF_NATIVE && callee_is_operation(fn, call)) {
    return fn_native_call(fn, expr, call, args, ret);
  }
  LowerTarget target;
  if (!callee_target(fn, call, &target)) {
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
  return result;
}

/* compiler/lower/lower_call.c: calls to module functions (with their type arguments and default arguments)
 * and to runtime functions declared `extern fn`. */
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_analysis.h"

static const MsCall *find_call(const MsFacts *facts, MsNode node) {
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
static MsSymbolId symbol_at(const Lower *cx, MsNodeRef decl) {
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
  const MsSymbol *callee = &fn->cx->program->symbols.ptr[symbol_at(fn->cx, call->callee.decl)];
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
      out[index] = written != NULL ? fn_expr(fn, written, LW_MOVE) : MIR_NONE;
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

/* The method declared by `node` in `module`, and the `impl` that holds it. */
static const MsMethod *find_method(const MsModule *tree, MsNode node, const MsDecl **owner) {
  for (uint32_t decl = 0; decl < tree->ndecls; decl++) {
    const MsDecl *item = tree->decls[decl];
    for (uint32_t index = 0; item->kind == MS_D_IMPL && index < item->u.impl.methods.len; index++) {
      if (item->u.impl.methods.ptr[index]->id == node) {
        *owner = item;
        return item->u.impl.methods.ptr[index];
      }
    }
  }
  return NULL;
}

/* What a call names, as something to lower: a module function or a method with a body. False for any other
 * callee (a runtime function, an operation, a builtin). */
static bool callee_target(LowerFn *fn, const MsCall *call, LowerTarget *out) {
  Lower *cx = fn->cx;
  if (call->callee.kind == MS_REF_FUNCTION) {
    const MsSymbolId id = symbol_at(cx, call->callee.decl);
    if (id == 0 || cx->program->symbols.ptr[id].native != MS_NATIVE_SOURCE) {
      return false;
    }
    *out = lower_symbol_target(cx, id);
    return true;
  }
  if (call->callee.kind != MS_REF_METHOD) {
    return false;
  }
  const uint32_t module = call->callee.decl.module;
  const MsDecl *owner = NULL;
  const MsMethod *method = find_method(cx->program->modules.ptr[module].tree, call->callee.decl.node, &owner);
  if (method == NULL || method->func.external) {
    return false;
  }
  const MsFacts *facts = &cx->program->modules.ptr[module].facts;
  *out = (LowerTarget){module, method->id, &method->func, method->func.name, ms_facts_type(facts, method->id),
                       owner->u.impl.bounds};
  return true;
}

static MirValue call_runtime(LowerFn *fn, const MsCall *call, const MirValue *args, MirTy ret) {
  const MsSymbolId id = symbol_at(fn->cx, call->callee.decl);
  if (id == 0 || fn->cx->program->symbols.ptr[id].native != MS_NATIVE_EXTERN) {
    (void)fn_fail(fn, "this callee is not lowered yet");
    return MIR_NONE;
  }
  const uint32_t external = runtime_function(fn, &fn->cx->program->symbols.ptr[id], ret);
  const MirValue result = mir_b_call_rt(&fn->b, external, args, call->arg_count);
  fn_own_result(fn, result);
  return result;
}

MirValue fn_call(LowerFn *fn, const MsExpr *expr, LowerWant want) {
  (void)want;
  const MsCall *call = find_call(fn->facts, expr->id);
  if (call == NULL || call->arg_count > 16) {
    (void)fn_fail(fn, "the checker recorded no usable call here");
    return MIR_NONE;
  }
  MirValue args[16];
  if (!lower_args(fn, expr, call, args)) {
    return MIR_NONE;
  }
  const MirTy ret = fn_type(fn, ms_ty_result(&fn->cx->program->types, call->callee_ty));
  mir_b_set_loc(&fn->b, fn_loc(fn, expr->pos));
  LowerTarget target;
  if (!callee_target(fn, call, &target)) {
    return call_runtime(fn, call, args, ret);
  }
  const uint32_t func = lower_instance(fn->cx, &target, call->type_args, call->type_arg_count, &fn->subst);
  if (func == MIR_NONE) {
    return MIR_NONE;
  }
  const MirValue result = mir_b_call(&fn->b, func, args, call->arg_count);
  fn_own_result(fn, result);
  return result;
}

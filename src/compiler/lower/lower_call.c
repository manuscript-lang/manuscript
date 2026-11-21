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
  return NULL;
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

MirValue fn_call(LowerFn *fn, const MsExpr *expr, LowerWant want) {
  (void)want;
  const MsCall *call = find_call(fn->facts, expr->id);
  if (call == NULL || call->arg_count > 16) {
    (void)fn_fail(fn, "the checker recorded no usable call here");
    return MIR_NONE;
  }
  const MsSymbolId id = symbol_at(fn->cx, call->callee.decl);
  const MsSymbol *callee = id != 0 ? &fn->cx->program->symbols.ptr[id] : NULL;
  if (callee == NULL || callee->kind != MS_SYMBOL_FN) {
    (void)fn_fail(fn, "a call does not name a module function yet");
    return MIR_NONE;
  }
  MirValue args[16];
  if (!lower_args(fn, expr, call, args)) {
    return MIR_NONE;
  }
  const MirTy ret = fn_type(fn, ms_ty_result(&fn->cx->program->types, call->callee_ty));
  mir_b_set_loc(&fn->b, fn_loc(fn, expr->pos));
  if (callee->native == MS_NATIVE_EXTERN) {
    const MirValue result = mir_b_call_rt(&fn->b, runtime_function(fn, callee, ret), args, call->arg_count);
    fn_own_result(fn, result);
    return result;
  }
  const uint32_t target = lower_instance(fn->cx, id, call->type_args, call->type_arg_count, &fn->subst);
  if (target == MIR_NONE) {
    return MIR_NONE;
  }
  const MirValue result = mir_b_call(&fn->b, target, args, call->arg_count);
  fn_own_result(fn, result);
  return result;
}

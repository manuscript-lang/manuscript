/* compiler/lower/lower_closure.c: lambdas and calls of function values.
 *
 * A lambda becomes a closure function whose first parameter is the environment and whose captures are copies of
 * the parameters and locals it reads from the function around it. The maker finds the captures, builds the
 * `closure.new`, and queues the body; the body is lowered after the maker (lower_lambda_bodies), with each capture
 * read once from the environment at its start. A lambda that changes a captured variable, or holds a lambda,
 * is not lowered yet. */
#include "base/message.h"
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_analysis.h"
#include "compiler/syntax/walk.h"

/* ---- making the closure ---- */

uint32_t lower_closure_func(Lower *cx, MirTy fn_ty, const LowerCapture *captures, uint32_t count) {
  const MirTyData *data = mir_ty_data(cx->module, fn_ty);
  MirParam *params = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirParam, (size_t)data->nargs + 1);
  params[0] = (MirParam){MIR_PTR, (uint8_t)MM_BORROW};
  for (uint32_t index = 0; index < data->nargs; index++) {
    params[index + 1] = (MirParam){data->args[index], (uint8_t)(mir_owns(data->owned, index) ? MM_MOVE : MM_BORROW)};
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_printf(&text, "closure.%zu", (size_t)cx->module->funcs.len);
  const MsName name = mir_name(cx->module, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  MirFunc func;
  mir_func_init(cx->module, &func, name, params, data->nargs + 1, data->elem);
  func.kind = MFK_CLOSURE;
  func.linkage = ML_INTERNAL;
  func.captures = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirTy, (size_t)count + 1);
  for (uint32_t index = 0; index < count; index++) {
    func.captures[index] = captures[index].ty;
  }
  func.ncaptures = count;
  return mir_add_func(cx->module, &func);
}

/* Whether an escaping closure takes the capture itself: a local the maker owns, or a parameter it was given.
 * A `var` lives in a slot the maker keeps, and a borrowed parameter is not the maker's to give away. */
static bool fn_capture_moves(const LowerFn *fn, const LowerCapture *capture) {
  if (capture->kind == MS_REF_LOCAL) {
    /* A binding the maker's scope owns; a loop element or pattern binding is a view, a `var` re-owns. */
    return capture->index < fn->nvars && fn->local_owns != NULL && fn->local_owns[capture->index] == 1 &&
           (fn->closing == NULL || !fn->closing_var[capture->index]);
  }
  const uint32_t param_at = capture->index + (fn->lambda != NULL ? 1u : 0u); /* a closure's first parameter is its environment */
  return param_at < fn->b.func.nparams && fn->b.func.params[param_at].mode == MM_MOVE &&
         (fn->closing == NULL || capture->index >= LOWER_MAX_CLOSING_PARAMS ||
          !fn->closing_var[fn->nvars + capture->index]);
}

/* Whether the captured local or parameter lives in a slot the maker's scope owns, so an escaping closure takes it out. */
static bool fn_capture_slot_owned(const LowerFn *fn, const LowerCapture *capture) {
  if (fn->closing == NULL) {
    return false;
  }
  if (capture->kind == MS_REF_LOCAL) {
    return capture->index < fn->nvars && fn->closing_var[capture->index];
  }
  return capture->index < fn->b.func.nparams && capture->index < LOWER_MAX_CLOSING_PARAMS &&
         fn->b.func.params[capture->index].mode == MM_MOVE && fn->closing_var[fn->nvars + capture->index];
}

/* The values the closure takes, as the maker reads them (a droppable one is cloned: the closure owns its copy). */
static bool capture_values(LowerFn *fn, LowerCapture *captures, uint32_t count, MirValue *out, const bool *changed,
                           bool escapes, bool *borrows, MirCaptureCloser *closers, uint32_t *nclosers) {
  for (uint32_t index = 0; index < count; index++) {
    if (changed[index] && !escapes) {
      /* A variable the lambda changes stays in the maker's slot, which the closure borrows. */
      const uint32_t at = captures[index].kind == MS_REF_LOCAL ? captures[index].index : fn->nvars + captures[index].index;
      const bool in_range = captures[index].kind == MS_REF_LOCAL ? captures[index].index < fn->nvars
                                                                 : captures[index].index < LOWER_MAX_CLOSING_PARAMS;
      const bool slotted = in_range && fn->closing != NULL && fn->closing_var[at];
      if (!slotted) {
        return fn_fail(fn, "a lambda changes a captured variable that does not live in a slot (%s %u)", captures[index].kind == MS_REF_LOCAL ? "local" : "parameter", captures[index].index);
      }
      captures[index].shared = true;
      captures[index].elem = fn->closing_types[at];
      captures[index].ty = MIR_PTR;
      out[index] = fn->closing[at];
      continue;
    }
    const MsRef ref = {.kind = captures[index].kind, .local = captures[index].index};
    MirValue value = fn_name_ref(fn, captures[index].use, &ref);
    if (value == MIR_NONE) {
      return false;
    }
    captures[index].ty = mir_b_ty(&fn->b, value);
    if (changed[index]) { /* an escaping closure keeps a variable it changes in its own environment */
      captures[index].shared = true;
      captures[index].cell = true;
      captures[index].elem = captures[index].ty;
    }
    if (mir_needs_drop(fn->cx->module, captures[index].ty)) {
      if (!escapes) {
        *borrows = true; /* a closure that stays in its maker reads the value where it lives */
      } else if (!fn_capture_moves(fn, &captures[index])) {
        MirValue taken = MIR_NONE;
        MirVar owned_var = 0;
        if (fn_capture_slot_owned(fn, &captures[index]) && fn_closing_take(fn, &ref, value, &taken)) {
          value = taken; /* a resource or var in a slot gives its value to the closure */
        } else if (captures[index].kind == MS_REF_LOCAL && captures[index].use != NULL &&
                   fn_owned_local(fn, captures[index].use, &owned_var) && fn->b.vars.ptr[owned_var].mode == MM_MOVE) {
          fn_scope_var_released(fn, owned_var, true); /* an owning `var` the maker does not use again goes to the closure */
        } else {
          value = fn_implicit_clone(fn, value, false);
        }
      }
    }
    out[index] = value;
    uint32_t silent = MIR_NONE;
    if (escapes && captures[index].use != NULL && mir_needs_drop(fn->cx->module, captures[index].ty) &&
        fn_capture_closer(fn, ms_facts_type(fn->facts, captures[index].use->id), captures[index].ty, &silent)) {
      closers[(*nclosers)++] = (MirCaptureCloser){index, silent}; /* the closure closes what it owns when it is dropped */
    }
  }
  return true;
}

MirValue fn_lambda(LowerFn *fn, const MsExpr *expr) {
  const MirTy fn_ty = fn_type(fn, ms_facts_type(fn->facts, expr->id));
  if (mir_ty_data(fn->cx->module, fn_ty)->kind != MK_FN) {
    (void)fn_fail(fn, "a lambda is not typed as a function");
    return MIR_NONE;
  }
  LowerCapture *captures = NULL;
  uint32_t count = 0;
  if (!find_captures(fn, expr, &captures, &count)) {
    return MIR_NONE;
  }
  bool *changed = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, bool, (size_t)count + 1);
  (void)capture_changes(fn, expr, captures, count, changed);
  MirValue *values = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, MirValue, (size_t)count + 1);
  const bool escapes = ms_facts_use(fn->facts, expr->id) == MS_USE_MOVE;

  bool borrows = false;
  MirCaptureCloser *closers = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, MirCaptureCloser, (size_t)count + 1);
  uint32_t nclosers = 0;
  if (!capture_values(fn, captures, count, values, changed, escapes, &borrows, closers, &nclosers)) {
    return MIR_NONE;
  }
  const uint32_t func = lower_closure_func(fn->cx, fn_ty, captures, count);
  fn->cx->module->funcs.ptr[func].capture_closers = closers;
  fn->cx->module->funcs.ptr[func].ncapture_closers = nclosers;
  fn->cx->module->funcs.ptr[func].scoped = borrows;
  /* A fault trace calls a lambda `<enclosing function>.closure`. */
  const MsName enclosing = fn->b.func.display != MS_NAME_EMPTY ? fn->b.func.display : fn->b.func.name;
  fn->cx->module->funcs.ptr[func].display = mir_name(
      fn->cx->module, ms_message_format(&fn->cx->module->arena, "%S.closure", ms_names_span(&fn->cx->module->names, enclosing), (MsSpan){0}));
  LowerSubst subst = fn->subst;
  MsTy *vars = MS_ARENA_NEW_ARRAY(&fn->cx->program->arena, MsTy, subst.count * 2 + 1);
  for (size_t index = 0; index < subst.count; index++) {
    vars[index] = subst.vars[index];
    vars[subst.count + index] = subst.args[index];
  }
  subst.vars = vars;
  subst.args = vars + subst.count;
  lower_lambda_list_push(&fn->cx->lambdas, (LowerLambda){expr, fn->module_index, func, fn->nvars, subst, captures, count, false});
  const MirImm imm = {.tag = MI_FUNC, .a = func};
  mir_b_set_loc(&fn->b, fn_loc(fn, expr->pos));
  return fn_emit(fn, MOP_ClosureNew, values, count, imm, fn_ty);
}

/* ---- the body ---- */

/* Reads each capture from the environment once; a local's variable is the one its name resolves to. */
static bool bind_captures(LowerFn *fn, const LowerLambda *lambda, MirValue env) {
  fn->cap_vars = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, MirVar, (size_t)lambda->ncaptures + 1);
  for (uint32_t index = 0; index < lambda->ncaptures; index++) {
    const LowerCapture *capture = &lambda->captures[index];
    const MirImm imm = {.tag = MI_IDX, .a = index};
    const MirValue value = capture->cell ? mir_b_emit(&fn->b, MOP_ClosureCapAddr, &env, 1, imm, MIR_PTR)
                                         : mir_b_emit(&fn->b, MOP_ClosureCap, &env, 1, imm, capture->ty);
    if (capture->shared && capture->kind == MS_REF_LOCAL && capture->index < fn->nvars) {
      fn->closing[capture->index] = value;
      fn->closing_var[capture->index] = true;
      fn->closing_types[capture->index] = capture->elem;
      fn->shared[capture->index] = LOWER_SHARED_BORROWED;
      continue;
    }
    if (capture->shared && capture->kind == MS_REF_PARAM && capture->index < LOWER_MAX_CLOSING_PARAMS) {
      /* The parameter's index is shared with the lambda's own parameters: the slot table cannot tell them apart. */
      fn->closing[fn->nvars + capture->index] = value;
      fn->closing_var[fn->nvars + capture->index] = true;
      fn->closing_types[fn->nvars + capture->index] = capture->elem;
      continue;
    }
    fn->cap_vars[index] = mir_b_declare_var(&fn->b, capture->ty, MM_BORROW);
    mir_b_def_var(&fn->b, fn->cap_vars[index], value);
    if (capture->kind == MS_REF_LOCAL) {
      if (capture->index >= fn->nvars) {
        return fn_fail(fn, "a captured local is outside the function's locals");
      }
      fn->vars[capture->index] = fn->cap_vars[index] + 1;
    }
  }
  return true;
}

bool fn_lambda_name(LowerFn *fn, const MsExpr *expr, const MsRef *ref, MirValue *out) {
  const LowerLambda *lambda = fn->lambda;
  if (lambda == NULL || ref == NULL || ref->kind != MS_REF_PARAM) {
    return false;
  }
  if (is_own_param(fn, lambda->expr, expr->u.sym, ref)) {
    return false;
  }
  for (uint32_t index = 0; index < lambda->ncaptures; index++) {
    const LowerCapture *capture = &lambda->captures[index];
    if (capture->kind == MS_REF_PARAM && capture->index == ref->local && capture->name == expr->u.sym && !capture->shared) {
      *out = mir_b_use_var(&fn->b, fn->cap_vars[index]);
      return true;
    }
  }
  return false;
}

static bool lower_lambda_body(Lower *cx, uint32_t index) {
  const LowerLambda lambda = cx->lambdas.ptr[index]; /* a copy: lowering the body may add lambdas */
  const MirFunc reserved = cx->module->funcs.ptr[lambda.func];
  LowerFn fn = {.cx = cx,
                .facts = &cx->program->modules.ptr[lambda.module].facts,
                .module_index = lambda.module,
                .file = lower_file(cx, lambda.module),
                .subst = lambda.subst,
                .ret = reserved.ret,
                .lambda = &lambda};
  mir_b_init(&fn.b, cx->module, reserved.name, reserved.params, reserved.nparams, reserved.ret);
  fn.b.func.kind = MFK_CLOSURE;
  fn.b.func.captures = reserved.captures;
  fn.b.func.ncaptures = reserved.ncaptures;
  fn.b.func.loc = (MirLoc){fn.file, 0, 0, 0};
  (void)fn_scope_begin(&fn);
  MirValue *values = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirValue, (size_t)reserved.nparams + 1);
  mir_b_params(&fn.b, values, reserved.nparams);
  fn.param_vars = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirVar, (size_t)reserved.nparams + 1);
  const MirTy lambda_ty = fn_type(&fn, ms_facts_type(fn.facts, lambda.expr->id));
  const MirTyData *lambda_data = mir_ty_data(cx->module, lambda_ty);
  bool lifted[LOWER_MAX_ARGS + 1] = {false};
  bool resource[LOWER_MAX_ARGS + 1] = {false};
  const MsTy source_ty = ms_ty_subst(&cx->program->types, ms_facts_type(fn.facts, lambda.expr->id), lambda.subst.vars,
                                     lambda.subst.args, lambda.subst.count);
  for (uint32_t at = 1; at < reserved.nparams; at++) {
    if (mir_param_is_var(lambda_data->owned, at - 1) && fn.nvar_params < LOWER_MAX_VAR_PARAMS) {
      const MirTy held_ty = fn_type(&fn, ms_ty_params(&cx->program->types, source_ty)[at - 1].ty);
      const bool owns = mir_needs_drop(cx->module, held_ty);
      const MirImm of_type = {.tag = MI_TY, .a = held_ty};
      const MirValue held = mir_b_emit(&fn.b, owns ? MOP_Take : MOP_Load, &values[at], 1, of_type, held_ty);
      fn.param_vars[at - 1] = mir_b_declare_var(&fn.b, held_ty, owns ? MM_MOVE : MM_BORROW);
      mir_b_def_var(&fn.b, fn.param_vars[at - 1], held);
      fn.var_params[fn.nvar_params++] = (LowerVarParam){fn.param_vars[at - 1], values[at], held_ty};
      continue;
    }
    MirValue param = values[at];
    MirTy ty = mir_b_ty(&fn.b, param);
    MirMode mode = (MirMode)reserved.params[at].mode;
    const MsParam *written = at - 1 < lambda.expr->u.lambda.params.len ? lambda.expr->u.lambda.params.ptr[at - 1] : NULL;
    const MirTy declared = fn_type(&fn, ms_ty_params(&cx->program->types, source_ty)[at - 1].ty);
    if (written != NULL && written->def != NULL && mir_ty_data(cx->module, ty)->kind == MK_OPT && ty != declared) {
      /* A parameter the function type lets the caller omit arrives as an optional: the default, which may read
       * a capture, fills a none once the captures are bound. */
      fn.param_vars[at - 1] = mir_b_declare_var(&fn.b, declared, MM_MOVE);
      lifted[at] = true;
      continue;
    }
    if (written != NULL && mode == MM_MOVE && at - 1 < LOWER_MAX_CLOSING_PARAMS && ms_facts_closer(fn.facts, written->id) != NULL) {
      resource[at] = true; /* may be the body's to close: settled once the closing slots exist */
      fn.param_vars[at - 1] = mir_b_declare_var(&fn.b, ty, MM_BORROW);
      continue;
    }
    fn.param_vars[at - 1] = mir_b_declare_var(&fn.b, ty, mode);
    mir_b_def_var(&fn.b, fn.param_vars[at - 1], param);
    if (reserved.params[at].mode == MM_MOVE && mir_needs_drop(cx->module, ty) && param == values[at]) {
      fn_own(&fn, fn_scope(&fn), values[at]);
    }
  }
  fn.nvars = lambda.nvars;
  fn.vars = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirVar, (size_t)fn.nvars + 1);
  fn.local_owns = MS_ARENA_NEW_ARRAY(&cx->module->arena, uint8_t, (size_t)fn.nvars + 1);
  fn_init_closing(&fn);
  for (uint32_t at = 1; at < reserved.nparams && at <= LOWER_MAX_ARGS; at++) {
    if (!resource[at]) {
      continue;
    }
    const MsParam *written = lambda.expr->u.lambda.params.ptr[at - 1];
    const MsTy checked = ms_facts_type(fn.facts, written->id);
    const MirTy ty = mir_b_ty(&fn.b, values[at]);
    if (fn_closer_for(&fn, ms_facts_closer(fn.facts, written->id), checked)) {
      /* A resource parameter is the body's to close: it lives in a slot the body's scope owns. */
      (void)fn_own_param(&fn, at - 1, checked, values[at], fn.param_vars[at - 1], false);
    } else {
      mir_b_def_var(&fn.b, fn.param_vars[at - 1], values[at]);
      if (mir_needs_drop(cx->module, ty)) {
        fn_own(&fn, fn_scope(&fn), values[at]);
      }
    }
  }
  fn_find_shared(&fn, lambda.expr->u.lambda.body);
  bool ok = bind_captures(&fn, &lambda, values[0]);
  for (uint32_t at = 1; ok && at < reserved.nparams && at <= LOWER_MAX_ARGS; at++) {
    if (lifted[at]) {
      const MirTy declared = fn_type(&fn, ms_ty_params(&cx->program->types, source_ty)[at - 1].ty);
      const MirValue filled = fn_unlift(&fn, values[at], lambda.expr->u.lambda.params.ptr[at - 1]->def, declared);
      ok = filled != MIR_NONE;
      if (ok) {
        mir_b_def_var(&fn.b, fn.param_vars[at - 1], filled);
      }
    }
  }
  ok = ok && fn_stmts(&fn, lambda.expr->u.lambda.body) && !fn.failed;
  if (!fn.terminated) {
    fn_scope_unwind(&fn, 0);
    mir_b_ret(&fn.b, MIR_NONE);
  }
  MirFunc built;
  if (!mir_b_into_func(&fn.b, &built) || !ok) {
    return !fn.failed ? lower_fail(cx, "a closure could not be built") : false;
  }
  MirFunc *slot = &cx->module->funcs.ptr[lambda.func];
  built.linkage = ML_INTERNAL;
  built.kind = MFK_CLOSURE;
  built.captures = reserved.captures;
  built.ncaptures = reserved.ncaptures;
  built.scoped = reserved.scoped;
  built.capture_closers = reserved.capture_closers;
  built.ncapture_closers = reserved.ncapture_closers;
  built.display = reserved.display;
  mir_func_release(slot);
  *slot = built;
  cx->lambdas.ptr[index].lowered = true;
  return true;
}

bool lower_lambda_bodies(Lower *cx, bool *progressed) {
  for (size_t index = 0; index < cx->lambdas.len; index++) {
    if (!cx->lambdas.ptr[index].lowered) {
      *progressed = true;
      if (!lower_lambda_body(cx, (uint32_t)index)) {
        return lower_fail(cx, "  while lowering a lambda at %u:%u", cx->lambdas.ptr[index].expr->pos.line, cx->lambdas.ptr[index].expr->pos.column);
      }
    }
  }
  return true;
}

/* ---- a named function as a value ---- */

/* A closure without captures whose body calls `callee` with the closure's own arguments. */
uint32_t lower_forwarding_closure(Lower *cx, MirTy fn_ty, uint32_t callee) {
  const uint32_t slot = lower_closure_func(cx, fn_ty, NULL, 0);
  const MirFunc reserved = cx->module->funcs.ptr[slot];
  MirBuilder b;
  mir_b_init(&b, cx->module, reserved.name, reserved.params, reserved.nparams, reserved.ret);
  MirValue *values = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirValue, (size_t)reserved.nparams + 1);
  mir_b_params(&b, values, reserved.nparams);
  const MirValue result = mir_b_call(&b, callee, values + 1, reserved.nparams - 1);
  mir_b_ret(&b, reserved.ret == MIR_VOID ? MIR_NONE : result);
  MirFunc built;
  if (!mir_b_into_func(&b, &built)) {
    return MIR_NONE;
  }
  built.linkage = ML_INTERNAL;
  built.kind = MFK_CLOSURE;
  mir_func_release(&cx->module->funcs.ptr[slot]);
  cx->module->funcs.ptr[slot] = built;
  return slot;
}

/* A forwarding closure whose type makes some parameters optional: a none is filled with the declared default of the
 * function `id`, whose copy `callee` the closure calls. */
static uint32_t lower_defaulting_closure(Lower *cx, MirTy fn_ty, uint32_t callee, MsSymbolId id) {
  const MsSymbol *symbol = &cx->program->symbols.ptr[id];
  const uint32_t slot = lower_closure_func(cx, fn_ty, NULL, 0);
  const MirFunc reserved = cx->module->funcs.ptr[slot];
  LowerFn fn = {.cx = cx,
                .facts = &cx->program->modules.ptr[symbol->module].facts,
                .module_index = symbol->module,
                .file = lower_file(cx, symbol->module),
                .ret = reserved.ret};
  mir_b_init(&fn.b, cx->module, reserved.name, reserved.params, reserved.nparams, reserved.ret);
  fn.b.func.kind = MFK_CLOSURE;
  fn.b.func.loc = (MirLoc){fn.file, 0, 0, 0};
  (void)fn_scope_begin(&fn);
  MirValue *values = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirValue, (size_t)reserved.nparams + 1);
  mir_b_params(&fn.b, values, reserved.nparams);
  MirValue *args = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirValue, (size_t)reserved.nparams + 1);
  const MirFunc target = cx->module->funcs.ptr[callee];
  const MsParams *declared = &symbol->decl->u.fn.params;
  for (uint32_t at = 1; at < reserved.nparams; at++) {
    args[at - 1] = values[at];
    const MirTy want = target.params[at - 1].ty;
    if (reserved.params[at].ty == want) {
      continue;
    }
    const MsParam *written = at - 1 < declared->len ? declared->ptr[at - 1] : NULL;
    args[at - 1] = fn_unlift(&fn, values[at], written != NULL ? written->def : NULL, want);
    if (args[at - 1] == MIR_NONE) {
      return MIR_NONE;
    }
  }
  const MirValue result = mir_b_call(&fn.b, callee, args, reserved.nparams - 1);
  fn_scope_unwind(&fn, 0);
  mir_b_ret(&fn.b, reserved.ret == MIR_VOID ? MIR_NONE : result);
  MirFunc built;
  if (fn.failed || !mir_b_into_func(&fn.b, &built)) {
    return MIR_NONE;
  }
  built.linkage = ML_INTERNAL;
  built.kind = MFK_CLOSURE;
  mir_func_release(&cx->module->funcs.ptr[slot]);
  cx->module->funcs.ptr[slot] = built;
  return slot;
}

/* A function the standard library declares without a body, used as a value: a closure whose body is the runtime call. */
static uint32_t lower_native_closure(Lower *cx, MirTy fn_ty, MsSymbolId id) {
  const MsSymbol *symbol = &cx->program->symbols.ptr[id];
  const uint32_t slot = lower_closure_func(cx, fn_ty, NULL, 0);
  const MirFunc reserved = cx->module->funcs.ptr[slot];
  LowerFn fn = {.cx = cx,
                .facts = &cx->program->modules.ptr[symbol->module].facts,
                .module_index = symbol->module,
                .file = lower_file(cx, symbol->module),
                .ret = reserved.ret};
  mir_b_init(&fn.b, cx->module, reserved.name, reserved.params, reserved.nparams, reserved.ret);
  fn.b.func.kind = MFK_CLOSURE;
  fn.b.func.loc = (MirLoc){fn.file, 0, 0, 0};
  (void)fn_scope_begin(&fn);
  MirValue *values = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirValue, (size_t)reserved.nparams + 1);
  mir_b_params(&fn.b, values, reserved.nparams);
  const MirValue result = fn_builtin_named(&fn, id, reserved.nparams - 1, values + 1, reserved.ret);
  if (result != MIR_NONE && fn_fresh_owner(&fn, result)) {
    (void)mir_b_emit(&fn.b, MOP_ScopeDisown, (MirValue[]){result}, 1, (MirImm){0}, MIR_NONE);
  }
  fn_scope_unwind(&fn, 0);
  mir_b_ret(&fn.b, reserved.ret == MIR_VOID ? MIR_NONE : result);
  MirFunc built;
  if (fn.failed || !mir_b_into_func(&fn.b, &built)) {
    return MIR_NONE;
  }
  built.linkage = ML_INTERNAL;
  built.kind = MFK_CLOSURE;
  mir_func_release(&cx->module->funcs.ptr[slot]);
  cx->module->funcs.ptr[slot] = built;
  return slot;
}

/* A module function used as a value: a closure with no captures whose body calls it. */
MirValue fn_function_value(LowerFn *fn, const MsExpr *expr, const MsRef *ref) {
  Lower *cx = fn->cx;
  MirTy fn_ty = fn_type(fn, ms_facts_type(fn->facts, expr->id));
  /* The type a binding gives the value may make parameters optional. */
  if (fn->hint != MIR_VOID && mir_ty_data(cx->module, fn->hint)->kind == MK_FN &&
      mir_ty_data(cx->module, fn->hint)->nargs == mir_ty_data(cx->module, fn_ty)->nargs) {
    fn_ty = fn->hint;
  }
  const MirTyData *data = mir_ty_data(cx->module, fn_ty);
  const MsSymbolId id = fn_symbol_at(cx, ref->decl);
  if (data->kind != MK_FN || id == 0 || cx->program->symbols.ptr[id].native != MS_NATIVE_SOURCE) {
    (void)fn_fail(fn, "this function cannot be used as a value yet");
    return MIR_NONE;
  }
  const MsSymbol *named = &cx->program->symbols.ptr[id];
  if (named->decl != NULL && named->decl->kind == MS_D_FN && named->decl->u.fn.bodiless) {
    const uint32_t native = lower_native_closure(cx, fn_ty, id);
    if (native == MIR_NONE) {
      (void)fn_fail(fn, "a function value could not be built");
      return MIR_NONE;
    }
    return fn_emit(fn, MOP_ClosureNew, NULL, 0, (MirImm){.tag = MI_FUNC, .a = native}, fn_ty);
  }
  const LowerTarget target = lower_symbol_target(cx, id);
  MsTy bound[16] = {0};
  if (target.nvariables != 0) {
    const MsTy actual = ms_ty_subst(&cx->program->types, ms_facts_type(fn->facts, expr->id), fn->subst.vars, fn->subst.args,
                                    fn->subst.count);
    if (target.nvariables > 16 || !ms_check_unify(&cx->program->types, target.ty, actual, target.variables,
                                                  target.nvariables, bound)) {
      (void)fn_fail(fn, "a generic function's type arguments could not be found from its use as a value");
      return MIR_NONE;
    }
  }
  const uint32_t callee = lower_instance(cx, &target, target.nvariables != 0 ? bound : NULL, target.nvariables, &fn->subst);
  if (callee == MIR_NONE) {
    return MIR_NONE;
  }
  bool lifted = false;
  for (uint32_t at = 0; at < data->nargs && at < cx->module->funcs.ptr[callee].nparams; at++) {
    lifted = lifted || data->args[at] != cx->module->funcs.ptr[callee].params[at].ty;
  }
  const uint32_t slot = lifted ? lower_defaulting_closure(cx, fn_ty, callee, id) : lower_forwarding_closure(cx, fn_ty, callee);
  if (slot == MIR_NONE) {
    (void)fn_fail(fn, "a function value could not be built");
    return MIR_NONE;
  }
  const MirImm imm = {.tag = MI_FUNC, .a = slot};
  return fn_emit(fn, MOP_ClosureNew, NULL, 0, imm, fn_ty);
}

/* The receiver a bound-method closure keeps: a dying temporary moves into the closure; a value some binding still owns
 * is a hidden copy. */
static MirValue fn_closure_owns(LowerFn *fn, const MsExpr *written, MirValue receiver, bool *borrowed) {
  /* A read of a binding is never the dying temporary, though the value is the one the binding was made from: the
   * closure borrows it. */
  const bool place = written->kind == MS_E_NAME || written->kind == MS_E_MEMBER;
  if (place) {
    *borrowed = true;
    return receiver;
  }
  if (!fn_fresh_owner(fn, receiver)) {
    return fn_implicit_clone(fn, receiver, true);
  }
  (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &receiver, 1, (MirImm){0}, MIR_NONE);
  return receiver;
}

/* `receiver.operation` where the standard library declares the operation without a body: a closure holding a copy of
 * the receiver whose body is the runtime call, made as a call of the operation is. */
static MirValue bound_native_method(LowerFn *fn, const MsExpr *expr, MirTy fn_ty) {
  Lower *cx = fn->cx;
  const MirTyData *data = mir_ty_data(cx->module, fn_ty);
  const MsTy owner = ms_ty_subst(&cx->program->types, ms_facts_type(fn->facts, expr->u.member.left->id), fn->subst.vars,
                                 fn->subst.args, fn->subst.count);
  const MsSpan operation = ms_names_span(cx->program->names, expr->u.member.name);
  const bool changes = fn_native_changes_receiver(fn, owner, operation, data->elem);
  MirValue receiver = MIR_NONE;
  MirTy slot_ty = MIR_VOID;
  if (changes) {
    /* The closure shares the receiver's slot, which find_shared gave the local variable. */
    const MsExpr *left = expr->u.member.left;
    const MsRef *place = left->kind == MS_E_NAME ? ms_facts_ref(fn->facts, left->id) : NULL;
    if (place == NULL || place->kind != MS_REF_LOCAL || fn->closing == NULL || place->local >= fn->nvars ||
        !fn->closing_var[place->local]) {
      (void)fn_fail(fn, "an operation that changes its receiver as a value needs a local `var` receiver");
      return MIR_NONE;
    }
    receiver = fn->closing[place->local];
    slot_ty = fn->closing_types[place->local];
  } else {
    receiver = fn_expr(fn, expr->u.member.left, LW_BORROW);
  }
  if (receiver == MIR_NONE) {
    return MIR_NONE;
  }
  const MirTy receiver_ty = changes ? slot_ty : mir_b_ty(&fn->b, receiver);
  bool borrowed = false;
  if (!changes && mir_needs_drop(cx->module, receiver_ty)) {
    receiver = fn_closure_owns(fn, expr->u.member.left, receiver, &borrowed);
  }
  const LowerCapture capture = {.kind = MS_REF_LOCAL, .ty = changes ? MIR_PTR : receiver_ty};
  const uint32_t slot = lower_closure_func(cx, fn_ty, &capture, 1);
  cx->module->funcs.ptr[slot].scoped = borrowed;
  const MirFunc reserved = cx->module->funcs.ptr[slot];
  LowerFn body = {.cx = cx, .facts = fn->facts, .module_index = fn->module_index, .file = fn->file, .subst = fn->subst,
                  .ret = reserved.ret};
  mir_b_init(&body.b, cx->module, reserved.name, reserved.params, reserved.nparams, reserved.ret);
  body.b.func.kind = MFK_CLOSURE;
  body.b.func.captures = reserved.captures;
  body.b.func.ncaptures = reserved.ncaptures;
  body.b.func.loc = (MirLoc){body.file, 0, 0, 0};
  (void)fn_scope_begin(&body);
  MirValue *values = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirValue, (size_t)reserved.nparams + 1);
  mir_b_params(&body.b, values, reserved.nparams);
  MirValue *args = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirValue, (size_t)reserved.nparams + 1);
  const MirImm cap_imm = {.tag = MI_IDX, .a = 0};
  args[0] = mir_b_emit(&body.b, MOP_ClosureCap, &values[0], 1, cap_imm, changes ? MIR_PTR : receiver_ty);
  const MirValue address = args[0];
  if (changes) {
    args[0] = mir_b_emit(&body.b, MOP_Load, &address, 1, (MirImm){.tag = MI_TY, .a = receiver_ty}, receiver_ty);
  }
  for (uint32_t at = 1; at < reserved.nparams; at++) {
    args[at] = values[at];
  }
  MirValue result = MIR_NONE;
  bool done = changes ? fn_native_through(&body, address, owner, operation, data->nargs + 1, args, reserved.ret, &result)
                      : fn_native_on(&body, NULL, owner, operation, data->nargs + 1, args, reserved.ret, &result);
  if (!done && !changes && !body.failed) { /* a scalar's own conversion has no form of its own: the runtime function */
    result = fn_native_default(&body, owner, operation, data->nargs + 1, args, reserved.ret);
    done = result != MIR_NONE || reserved.ret == MIR_VOID;
  }
  if (!done || body.failed) {
    (void)fn_fail(fn, "the operation `%.*s` cannot be used as a value yet", (int)operation.len, (const char *)operation.ptr);
    return MIR_NONE;
  }
  if (reserved.ret != MIR_VOID && result != MIR_NONE) {
    (void)mir_b_emit(&body.b, MOP_ScopeDisown, &result, 1, (MirImm){0}, MIR_NONE);
  }
  fn_scope_unwind(&body, 0);
  mir_b_ret(&body.b, reserved.ret == MIR_VOID ? MIR_NONE : result);
  MirFunc built;
  if (!mir_b_into_func(&body.b, &built)) {
    (void)fn_fail(fn, "a bound method could not be built");
    return MIR_NONE;
  }
  built.linkage = ML_INTERNAL;
  built.kind = MFK_CLOSURE;
  built.captures = reserved.captures;
  built.ncaptures = reserved.ncaptures;
  built.scoped = reserved.scoped;
  mir_func_release(&cx->module->funcs.ptr[slot]);
  cx->module->funcs.ptr[slot] = built;
  const MirImm imm = {.tag = MI_FUNC, .a = slot};
  return fn_emit(fn, MOP_ClosureNew, &receiver, 1, imm, fn_ty);
}

/* `view.operation` where `view` is an interface value: a closure that holds a copy of the view and dispatches the
 * operation through it when called. */
static MirValue bound_operation(LowerFn *fn, const MsExpr *expr, const MsRef *ref, MirTy fn_ty) {
  Lower *cx = fn->cx;
  const MirTyData *data = mir_ty_data(cx->module, fn_ty);
  MirValue receiver = fn_expr(fn, expr->u.member.left, LW_BORROW);
  if (receiver == MIR_NONE) {
    return MIR_NONE;
  }
  const MirTy receiver_ty = mir_b_ty(&fn->b, receiver);
  const MirTyData *view = mir_ty_data(cx->module, receiver_ty);
  if (data->kind != MK_FN || view->kind != MK_IFACE) {
    (void)fn_fail(fn, "an operation of a bound type cannot be used as a value yet (at %u:%u)", expr->pos.line, expr->pos.column);
    return MIR_NONE;
  }
  bool borrowed = false;
  if (mir_needs_drop(cx->module, receiver_ty)) {
    receiver = fn_closure_owns(fn, expr->u.member.left, receiver, &borrowed);
  }
  const LowerCapture capture = {.kind = MS_REF_LOCAL, .ty = receiver_ty};
  const uint32_t slot = lower_closure_func(cx, fn_ty, &capture, 1);
  cx->module->funcs.ptr[slot].scoped = borrowed;
  const MirFunc reserved = cx->module->funcs.ptr[slot];
  MirBuilder b;
  mir_b_init(&b, cx->module, reserved.name, reserved.params, reserved.nparams, reserved.ret);
  MirValue *values = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirValue, (size_t)reserved.nparams + 1);
  mir_b_params(&b, values, reserved.nparams);
  MirValue *args = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirValue, (size_t)reserved.nparams + 1);
  const MirImm cap_imm = {.tag = MI_IDX, .a = 0};
  args[0] = mir_b_emit(&b, MOP_ClosureCap, &values[0], 1, cap_imm, receiver_ty);
  for (uint32_t at = 1; at < reserved.nparams; at++) {
    args[at] = values[at];
  }
  const MirImm method = {.tag = MI_METHOD, .a = view->id, .b = fn_operation_index(fn, expr, ref->index)};
  const MirValue result = mir_b_emit(&b, MOP_CallMethod, args, reserved.nparams, method, reserved.ret);
  mir_b_ret(&b, reserved.ret == MIR_VOID ? MIR_NONE : result);
  MirFunc built;
  if (!mir_b_into_func(&b, &built)) {
    (void)fn_fail(fn, "a bound operation could not be built");
    return MIR_NONE;
  }
  built.linkage = ML_INTERNAL;
  built.kind = MFK_CLOSURE;
  built.captures = reserved.captures;
  built.ncaptures = reserved.ncaptures;
  built.scoped = reserved.scoped;
  mir_func_release(&cx->module->funcs.ptr[slot]);
  cx->module->funcs.ptr[slot] = built;
  const MirImm imm = {.tag = MI_FUNC, .a = slot};
  return fn_emit(fn, MOP_ClosureNew, &receiver, 1, imm, fn_ty);
}

/* `receiver.method` used as a value: a closure that holds a copy of the receiver and calls the method with it. A
 * method that changes its receiver would have to share the receiver's storage, which a copy does not. */
MirValue fn_bound_method(LowerFn *fn, const MsExpr *expr, const MsRef *ref, const MsExpr *typed) {
  Lower *cx = fn->cx;
  const MirTy fn_ty = fn_type(fn, ms_facts_type(fn->facts, typed->id));
  const MirTyData *data = mir_ty_data(cx->module, fn_ty);
  MsCall call = {.callee = *ref, .callee_ty = ms_facts_type(fn->facts, typed->id)};
  LowerTarget target;
  if (data->kind == MK_FN && (ref->kind == MS_REF_NATIVE || ref->kind == MS_REF_METHOD) &&
      !fn_callee_target(fn, &call, &target)) {
    return bound_native_method(fn, expr, fn_ty);
  }
  if (ref->kind == MS_REF_OPERATION) {
    return bound_operation(fn, expr, ref, fn_ty);
  }
  if (data->kind != MK_FN || ref->kind != MS_REF_METHOD) {
    (void)fn_fail(fn, "this method cannot be used as a value yet (reference kind %d at %u:%u)", (int)ref->kind, expr->pos.line,
                  expr->pos.column);
    return MIR_NONE;
  }
  const bool changes = (target.receiver_flags & MS_PARAM_VAR) != 0;
  MirValue shared = MIR_NONE;
  if (changes) {
    /* The closure shares the receiver's slot, which find_shared gave the local variable. */
    const MsExpr *left = expr->u.member.left;
    const MsRef *place = left->kind == MS_E_NAME ? ms_facts_ref(fn->facts, left->id) : NULL;
    if (place == NULL || place->kind != MS_REF_LOCAL || fn->closing == NULL || place->local >= fn->nvars ||
        !fn->closing_var[place->local]) {
      (void)fn_fail(fn, "a method that changes its receiver as a value needs a local `var` receiver");
      return MIR_NONE;
    }
    shared = fn->closing[place->local];
  }
  MsTy bound[16] = {0};
  const MsTy *type_args = NULL;
  uint32_t ntype_args = 0;
  if (target.variables != NULL) {
    if (target.nvariables > 16 || !ms_check_unify(&cx->program->types, target.ty, call.callee_ty, target.variables,
                                                  target.nvariables, bound)) {
      (void)fn_fail(fn, "a method's type arguments could not be found from its use as a value");
      return MIR_NONE;
    }
    const MsTy actual = ms_ty_subst(&cx->program->types, ms_facts_type(fn->facts, expr->u.member.left->id), fn->subst.vars,
                                    fn->subst.args, fn->subst.count);
    (void)ms_check_unify(&cx->program->types, target.receiver, actual, target.variables, target.nvariables, bound);
    type_args = bound;
    ntype_args = target.nvariables;
  }
  const uint32_t callee = lower_instance(cx, &target, type_args, ntype_args, &fn->subst);
  if (callee == MIR_NONE) {
    return MIR_NONE;
  }
  MirValue receiver = changes ? shared : fn_expr(fn, expr->u.member.left, LW_BORROW);
  if (receiver == MIR_NONE) {
    return MIR_NONE;
  }
  const MirTy receiver_ty = mir_b_ty(&fn->b, receiver);
  const bool owns = !changes && mir_needs_drop(cx->module, receiver_ty);
  bool borrowed = false;
  if (owns) {
    receiver = fn_closure_owns(fn, expr->u.member.left, receiver, &borrowed);
  }
  const LowerCapture capture = {.kind = MS_REF_LOCAL, .ty = receiver_ty};
  const uint32_t slot = lower_closure_func(cx, fn_ty, &capture, 1);
  cx->module->funcs.ptr[slot].scoped = borrowed;
  const MirFunc reserved = cx->module->funcs.ptr[slot];
  MirBuilder b;
  mir_b_init(&b, cx->module, reserved.name, reserved.params, reserved.nparams, reserved.ret);
  MirValue *values = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirValue, (size_t)reserved.nparams + 2);
  mir_b_params(&b, values, reserved.nparams);
  MirValue *args = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirValue, (size_t)reserved.nparams + 1);
  const MirImm cap_imm = {.tag = MI_IDX, .a = 0};
  args[0] = mir_b_emit(&b, MOP_ClosureCap, &values[0], 1, cap_imm, receiver_ty);
  if (owns && (target.receiver_flags & MS_PARAM_MOVE) != 0) {
    args[0] = mir_b_emit(&b, MOP_Clone, &args[0], 1, (MirImm){0}, receiver_ty);
  }
  for (uint32_t at = 1; at < reserved.nparams; at++) {
    args[at] = values[at];
  }
  MirValue result = mir_b_call(&b, callee, args, reserved.nparams);
  if (result != MIR_NONE && cx->module->funcs.ptr[callee].ret_borrowed && mir_needs_drop(cx->module, reserved.ret)) {
    result = mir_b_emit(&b, MOP_Clone, &result, 1, (MirImm){0}, reserved.ret); /* the closure's result is its caller's to own */
  }
  mir_b_ret(&b, reserved.ret == MIR_VOID ? MIR_NONE : result);
  MirFunc built;
  if (!mir_b_into_func(&b, &built)) {
    (void)fn_fail(fn, "a bound method could not be built");
    return MIR_NONE;
  }
  built.linkage = ML_INTERNAL;
  built.kind = MFK_CLOSURE;
  built.captures = reserved.captures;
  built.ncaptures = reserved.ncaptures;
  built.scoped = reserved.scoped;
  mir_func_release(&cx->module->funcs.ptr[slot]);
  cx->module->funcs.ptr[slot] = built;
  const MirImm imm = {.tag = MI_FUNC, .a = slot};
  return fn_emit(fn, MOP_ClosureNew, &receiver, 1, imm, fn_ty);
}

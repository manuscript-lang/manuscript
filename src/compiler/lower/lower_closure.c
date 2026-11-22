/* compiler/lower/lower_closure.c: lambdas and calls of function values.
 *
 * A lambda becomes a closure function whose first parameter is the environment and whose captures are copies of
 * the parameters and locals it reads from the function around it. The maker finds the captures, builds the
 * `closure.new`, and queues the body; the body is lowered after the maker (lower_lambda_bodies), with each capture
 * read once from the environment at its start. A lambda that changes a captured variable, or holds a lambda,
 * is not lowered yet. */
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_analysis.h"
#include "compiler/syntax/walk.h"

/* ---- finding the captures ---- */

typedef struct Scan {
  const LowerFn *fn;
  const MsExpr *root;
  uint8_t *declared; /* by local id: bound inside the lambda */
  uint32_t nvars;
  const MsExpr **names;
  const MsRef **refs; /* parallel to names: the ref a call fact holds for a callee, else NULL */
  uint32_t nnames, cnames;
  bool nested, assigns;
} Scan;

static void declare(Scan *scan, uint32_t local) {
  if (local < scan->nvars) {
    scan->declared[local] = 1;
  }
}

static void declare_pattern(Scan *scan, const MsPattern *pattern) {
  const MsRef *ref = ms_facts_ref(scan->fn->facts, pattern->id);
  if (pattern->kind == MS_P_NAME && ref != NULL && ref->kind == MS_REF_LOCAL) {
    declare(scan, ref->local);
  }
  for (uint32_t index = 0; pattern->kind == MS_P_LIST && index < pattern->u.list.len; index++) {
    declare_pattern(scan, pattern->u.list.ptr[index]);
  }
}

static void scan_stmt(void *ctx, const MsStmt *stmt) {
  Scan *scan = ctx;
  const MsRef *ref = ms_facts_ref(scan->fn->facts, stmt->id);
  if (stmt->kind == MS_S_BIND) {
    declare_pattern(scan, stmt->u.bind.pattern);
  } else if (stmt->kind == MS_S_IF && stmt->u.branch.binding != NULL) {
    declare_pattern(scan, stmt->u.branch.binding);
  } else if (stmt->kind == MS_S_FOR && ref != NULL) {
    declare(scan, ref->local);
  } else if (stmt->kind == MS_S_ASSIGN) {
    scan->assigns = true;
  }
}

static void push_name(Scan *scan, const MsExpr *name, const MsRef *ref) {
  if (ref == NULL) {
    return;
  }
  if (scan->nnames == scan->cnames) {
    scan->cnames = scan->cnames == 0 ? 16 : scan->cnames * 2;
    const MsExpr **names = MS_ARENA_NEW_ARRAY(&scan->fn->cx->module->arena, const MsExpr *, scan->cnames);
    const MsRef **refs = MS_ARENA_NEW_ARRAY(&scan->fn->cx->module->arena, const MsRef *, scan->cnames);
    for (uint32_t index = 0; index < scan->nnames; index++) {
      names[index] = scan->names[index];
      refs[index] = scan->refs[index];
    }
    scan->names = names;
    scan->refs = refs;
  }
  scan->names[scan->nnames] = name;
  scan->refs[scan->nnames++] = ref;
}

static void scan_expr(void *ctx, const MsExpr *expr) {
  Scan *scan = ctx;
  if (expr->kind == MS_E_LAMBDA && expr != scan->root) {
    scan->nested = true;
  } else if (expr->kind == MS_E_MATCH) {
    for (uint32_t index = 0; index < expr->u.match.arms.len; index++) {
      const MsArm *arm = expr->u.match.arms.ptr[index];
      const MsRef *ref = ms_facts_ref(scan->fn->facts, arm->id);
      for (uint32_t at = 0; ref != NULL && at < arm->bindings.len; at++) {
        declare(scan, ref->local + at);
      }
    }
  } else if (expr->kind == MS_E_NAME) {
    push_name(scan, expr, ms_facts_ref(scan->fn->facts, expr->id));
  } else if (expr->kind == MS_E_CALL && expr->u.call.callee->kind == MS_E_NAME) {
    const MsCall *call = fn_find_call(scan->fn->facts, expr->id);
    if (call != NULL && (call->callee.kind == MS_REF_PARAM || call->callee.kind == MS_REF_LOCAL)) {
      push_name(scan, expr->u.call.callee, &call->callee);
    }
  }
}

/* Whether the parameter reference `expr` names a parameter of the lambda itself. */
static bool is_own_param(const LowerFn *fn, const MsExpr *lambda, const MsExpr *expr, const MsRef *ref) {
  (void)fn;
  const MsParams *params = (const MsParams *)&lambda->u.lambda.params;
  return ref->local < params->len && params->ptr[ref->local]->name == expr->u.sym;
}

static bool have_capture(const LowerCapture *captures, uint32_t count, uint8_t kind, uint32_t index, MsName name) {
  for (uint32_t at = 0; at < count; at++) {
    if (captures[at].kind == kind && captures[at].index == index && captures[at].name == name) {
      return true;
    }
  }
  return false;
}

static bool find_captures(LowerFn *fn, const MsExpr *lambda, LowerCapture **out, uint32_t *count) {
  Scan scan = {.fn = fn, .root = lambda, .nvars = fn->nvars};
  scan.declared = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, uint8_t, (size_t)fn->nvars + 1);
  const MsVisitor visitor = {.ctx = &scan, .stmt = scan_stmt, .expr = scan_expr};
  ms_walk_block(&visitor, lambda->u.lambda.body);
  if (scan.nested) {
    return fn_fail(fn, "a lambda inside a lambda is not lowered yet");
  }
  LowerCapture *captures = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, LowerCapture, (size_t)scan.nnames + 1);
  uint32_t used = 0;
  for (uint32_t index = 0; index < scan.nnames; index++) {
    const MsExpr *name = scan.names[index];
    const MsRef *ref = scan.refs[index];
    if ((ref->kind != MS_REF_PARAM && ref->kind != MS_REF_LOCAL)) {
      continue;
    }
    if (ref->kind == MS_REF_PARAM ? is_own_param(fn, lambda, name, ref)
                                   : (ref->local < fn->nvars && scan.declared[ref->local] != 0)) {
      continue;
    }
    if (!have_capture(captures, used, (uint8_t)ref->kind, ref->local, name->u.sym)) {
      captures[used++] = (LowerCapture){(uint8_t)ref->kind, ref->local, name->u.sym, name, MIR_VOID};
    }
  }
  *out = captures;
  *count = used;
  return true;
}

/* A lambda that assigns to a captured local would have to share its storage. */
static bool assigns_capture(LowerFn *fn, const MsExpr *lambda, const LowerCapture *captures, uint32_t count) {
  Scan scan = {.fn = fn, .root = lambda, .nvars = fn->nvars};
  scan.declared = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, uint8_t, (size_t)fn->nvars + 1);
  (void)captures;
  (void)count;
  const MsVisitor visitor = {.ctx = &scan, .stmt = scan_stmt};
  ms_walk_block(&visitor, lambda->u.lambda.body);
  return scan.assigns && count > 0;
}

/* ---- making the closure ---- */

static uint32_t reserve_closure(LowerFn *fn, const MsExpr *expr, MirTy fn_ty, const LowerCapture *captures,
                                uint32_t count) {
  Lower *cx = fn->cx;
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
  (void)expr;
  return mir_add_func(cx->module, &func);
}

/* The values the closure takes, as the maker reads them (a droppable one is cloned: the closure owns its copy). */
static bool capture_values(LowerFn *fn, LowerCapture *captures, uint32_t count, MirValue *out) {
  for (uint32_t index = 0; index < count; index++) {
    const MsRef ref = {.kind = captures[index].kind, .local = captures[index].index};
    MirValue value = fn_name_ref(fn, captures[index].use, &ref);
    if (value == MIR_NONE) {
      return false;
    }
    captures[index].ty = mir_b_ty(&fn->b, value);
    if (mir_needs_drop(fn->cx->module, captures[index].ty)) {
      value = mir_b_emit(&fn->b, MOP_Clone, &value, 1, (MirImm){0}, captures[index].ty);
    }
    out[index] = value;
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
  if (assigns_capture(fn, expr, captures, count)) {
    (void)fn_fail(fn, "a lambda that assigns to a captured variable is not lowered yet");
    return MIR_NONE;
  }
  MirValue *values = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, MirValue, (size_t)count + 1);
  if (!capture_values(fn, captures, count, values)) {
    return MIR_NONE;
  }
  const uint32_t func = reserve_closure(fn, expr, fn_ty, captures, count);
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
    const MirValue value = mir_b_emit(&fn->b, MOP_ClosureCap, &env, 1, imm, capture->ty);
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
  if (is_own_param(fn, lambda->expr, expr, ref)) {
    return false;
  }
  for (uint32_t index = 0; index < lambda->ncaptures; index++) {
    const LowerCapture *capture = &lambda->captures[index];
    if (capture->kind == MS_REF_PARAM && capture->index == ref->local && capture->name == expr->u.sym) {
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
  for (uint32_t at = 1; at < reserved.nparams; at++) {
    const MirTy ty = mir_b_ty(&fn.b, values[at]);
    fn.param_vars[at - 1] = mir_b_declare_var(&fn.b, ty, (MirMode)reserved.params[at].mode);
    mir_b_def_var(&fn.b, fn.param_vars[at - 1], values[at]);
    if (reserved.params[at].mode == MM_MOVE && mir_needs_drop(cx->module, ty)) {
      fn_own(&fn, fn_scope(&fn), values[at]);
    }
  }
  fn.nvars = lambda.nvars;
  fn.vars = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirVar, (size_t)fn.nvars + 1);
  bool ok = bind_captures(&fn, &lambda, values[0]) && fn_stmts(&fn, lambda.expr->u.lambda.body) && !fn.failed;
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
        return lower_fail(cx, "  while lowering a lambda");
      }
    }
  }
  return true;
}

/* ---- a named function as a value ---- */

/* A module function used as a value: a closure with no captures whose body calls it. */
MirValue fn_function_value(LowerFn *fn, const MsRef *ref, MirTy fn_ty) {
  Lower *cx = fn->cx;
  const MirTyData *data = mir_ty_data(cx->module, fn_ty);
  const MsSymbolId id = fn_symbol_at(cx, ref->decl);
  if (data->kind != MK_FN || id == 0 || cx->program->symbols.ptr[id].native != MS_NATIVE_SOURCE) {
    (void)fn_fail(fn, "this function cannot be used as a value yet");
    return MIR_NONE;
  }
  const LowerTarget target = lower_symbol_target(cx, id);
  if (target.nvariables != 0) {
    (void)fn_fail(fn, "a generic function as a value is not lowered yet");
    return MIR_NONE;
  }
  const uint32_t callee = lower_instance(cx, &target, NULL, 0, &fn->subst);
  if (callee == MIR_NONE) {
    return MIR_NONE;
  }
  const uint32_t slot = reserve_closure(fn, NULL, fn_ty, NULL, 0);
  const MirFunc reserved = cx->module->funcs.ptr[slot];
  MirBuilder b;
  mir_b_init(&b, cx->module, reserved.name, reserved.params, reserved.nparams, reserved.ret);
  MirValue *values = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirValue, (size_t)reserved.nparams + 1);
  mir_b_params(&b, values, reserved.nparams);
  const MirValue result = mir_b_call(&b, callee, values + 1, reserved.nparams - 1);
  mir_b_ret(&b, reserved.ret == MIR_VOID ? MIR_NONE : result);
  MirFunc built;
  if (!mir_b_into_func(&b, &built)) {
    (void)fn_fail(fn, "a function value could not be built");
    return MIR_NONE;
  }
  built.linkage = ML_INTERNAL;
  built.kind = MFK_CLOSURE;
  mir_func_release(&cx->module->funcs.ptr[slot]);
  cx->module->funcs.ptr[slot] = built;
  const MirImm imm = {.tag = MI_FUNC, .a = slot};
  return fn_emit(fn, MOP_ClosureNew, NULL, 0, imm, fn_ty);
}

/* ---- calling a function value ---- */

MirValue fn_call_value(LowerFn *fn, const MsExpr *expr, const MsRef *ref) {
  const MirValue callee = ref != NULL ? fn_name_ref(fn, expr->u.call.callee, ref) : fn_expr(fn, expr->u.call.callee, LW_BORROW);
  if (callee == MIR_NONE) {
    return MIR_NONE;
  }
  const MirTyData *data = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, callee));
  if (data->kind != MK_FN || expr->u.call.args.len != data->nargs || data->nargs > 15) {
    (void)fn_fail(fn, "a call of a function value does not match its type");
    return MIR_NONE;
  }
  MirValue args[16];
  args[0] = callee;
  for (uint32_t index = 0; index < data->nargs; index++) {
    args[index + 1] = fn_expr(fn, expr->u.call.args.ptr[index].value, mir_owns(data->owned, index) ? LW_MOVE : LW_BORROW);
    if (args[index + 1] == MIR_NONE) {
      return MIR_NONE;
    }
  }
  mir_b_set_loc(&fn->b, fn_loc(fn, expr->pos));
  return fn_emit(fn, MOP_CallInd, args, data->nargs + 1, (MirImm){0}, data->elem);
}

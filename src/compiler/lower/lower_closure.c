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
  const MsExpr *inner[16]; /* lambdas written inside the root: their parameters are bound there */
  uint32_t ninner;
  const LowerCapture *captures;
  uint32_t ncaptures;
  bool *changed; /* parallel to captures: the lambda changes it */
  bool nested;
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

/* Notes that the lambda changes the captured variable `ref` names (`name`, 0 for a statement's own target). */
static void mark_changed(Scan *scan, const MsRef *ref, MsName name) {
  for (uint32_t at = 0; ref != NULL && scan->changed != NULL && at < scan->ncaptures; at++) {
    const LowerCapture *capture = &scan->captures[at];
    scan->changed[at] = scan->changed[at] ||
                        (capture->kind == ref->kind && capture->index == ref->local && (name == 0 || capture->name == name));
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
    const MsExpr *root = stmt->u.assign.target;
    while (root != NULL && root->kind == MS_E_MEMBER) {
      root = root->u.member.left;
    }
    MsExpr *left = NULL, *at = NULL;
    while (root != NULL && ms_expr_index(root, &left, &at)) {
      root = left;
      while (root != NULL && root->kind == MS_E_MEMBER) {
        root = root->u.member.left;
      }
    }
    const MsRef *target = ms_facts_ref(scan->fn->facts, root != NULL && root->kind == MS_E_NAME ? root->id : stmt->id);
    mark_changed(scan, target, root != NULL && root->kind == MS_E_NAME ? root->u.sym : 0);
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
    if (scan->ninner == 16) {
      scan->nested = true; /* too many to track */
    } else {
      scan->inner[scan->ninner++] = expr;
    }
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
    return fn_fail(fn, "a lambda holds too many lambdas to lower");
  }
  LowerCapture *captures = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, LowerCapture, (size_t)scan.nnames + 1);
  uint32_t used = 0;
  for (uint32_t index = 0; index < scan.nnames; index++) {
    const MsExpr *name = scan.names[index];
    const MsRef *ref = scan.refs[index];
    if ((ref->kind != MS_REF_PARAM && ref->kind != MS_REF_LOCAL)) {
      continue;
    }
    bool bound = ref->kind == MS_REF_PARAM ? is_own_param(fn, lambda, name, ref)
                                            : (ref->local < fn->nvars && scan.declared[ref->local] != 0);
    for (uint32_t at = 0; ref->kind == MS_REF_PARAM && !bound && at < scan.ninner; at++) {
      bound = is_own_param(fn, scan.inner[at], name, ref);
    }
    if (bound) {
      continue;
    }
    if (!have_capture(captures, used, (uint8_t)ref->kind, ref->local, name->u.sym)) {
      captures[used++] = (LowerCapture){(uint8_t)ref->kind, ref->local, name->u.sym, name, MIR_VOID, false, MIR_VOID};
    }
  }
  *out = captures;
  *count = used;
  return true;
}

/* A call that hands a captured variable (or a part of it) on as a `var` argument changes it. */
static void scan_var_args(void *ctx, const MsExpr *expr) {
  Scan *scan = ctx;
  if (expr->kind != MS_E_CALL) {
    return;
  }
  const MsCall *call = fn_find_call(scan->fn->facts, expr->id);
  for (uint32_t index = 0; call != NULL && index < call->arg_count; index++) {
    if ((call->args[index].flags & MS_PARAM_VAR) == 0 || call->args[index].source != MS_ARG_WRITTEN) {
      continue;
    }
    const MsExpr *root = fn_written_arg(expr, call->args[index].node.node);
    for (;;) {
      MsExpr *left = NULL, *at = NULL;
      if (root != NULL && root->kind == MS_E_MEMBER) {
        root = root->u.member.left;
      } else if (root != NULL && ms_expr_index(root, &left, &at)) {
        root = left;
      } else {
        break;
      }
    }
    mark_changed(scan, root != NULL && root->kind == MS_E_NAME ? ms_facts_ref(scan->fn->facts, root->id) : NULL,
                 root != NULL && root->kind == MS_E_NAME ? root->u.sym : 0);
  }
}

/* Which of the captures the lambda changes (assigns, or hands on as a `var` argument): it shares their storage. */
static bool capture_changes(LowerFn *fn, const MsExpr *lambda, const LowerCapture *captures, uint32_t count, bool *changed) {
  Scan scan = {.fn = fn, .root = lambda, .nvars = fn->nvars};
  scan.declared = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, uint8_t, (size_t)fn->nvars + 1);
  scan.captures = captures;
  scan.ncaptures = count;
  scan.changed = changed;
  const MsVisitor visitor = {.ctx = &scan, .stmt = scan_stmt, .expr = scan_var_args};
  ms_walk_block(&visitor, lambda->u.lambda.body);
  bool any = false;
  for (uint32_t at = 0; at < count; at++) {
    any = any || changed[at];
  }
  return any;
}

typedef struct SharedScan {
  LowerFn *fn;
} SharedScan;

static void find_shared_expr(void *ctx, const MsExpr *expr) {
  LowerFn *fn = ((SharedScan *)ctx)->fn;
  LowerCapture *captures = NULL;
  uint32_t count = 0;
  if (expr->kind != MS_E_LAMBDA || fn->failed || !find_captures(fn, expr, &captures, &count) || count == 0) {
    return;
  }
  bool *changed = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, bool, (size_t)count + 1);
  if (!capture_changes(fn, expr, captures, count, changed)) {
    return;
  }
  for (uint32_t at = 0; at < count; at++) {
    if (changed[at] && captures[at].kind == MS_REF_LOCAL && captures[at].index < fn->nvars) {
      fn->shared[captures[at].index] = LOWER_SHARED;
    }
  }
}

void fn_find_shared(LowerFn *fn, MsStmts body) {
  fn->shared = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, uint8_t, (size_t)fn->nvars + 1);
  SharedScan scan = {fn};
  const MsVisitor visitor = {.ctx = &scan, .expr = find_shared_expr};
  ms_walk_block(&visitor, body);
}

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

/* The values the closure takes, as the maker reads them (a droppable one is cloned: the closure owns its copy). */
static bool capture_values(LowerFn *fn, LowerCapture *captures, uint32_t count, MirValue *out, const bool *changed) {
  for (uint32_t index = 0; index < count; index++) {
    if (changed[index]) {
      /* A variable the lambda changes stays in the maker's slot, which the closure borrows. */
      const bool slotted = captures[index].kind == MS_REF_LOCAL && captures[index].index < fn->nvars &&
                           fn->closing != NULL && fn->closing_var[captures[index].index];
      if (!slotted) {
        return fn_fail(fn, "a lambda changes a captured variable that does not live in a slot (%s %u)", captures[index].kind == MS_REF_LOCAL ? "local" : "parameter", captures[index].index);
      }
      captures[index].shared = true;
      captures[index].elem = fn->closing_types[captures[index].index];
      captures[index].ty = MIR_PTR;
      out[index] = fn->closing[captures[index].index];
      continue;
    }
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
  bool *changed = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, bool, (size_t)count + 1);
  (void)capture_changes(fn, expr, captures, count, changed);
  MirValue *values = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, MirValue, (size_t)count + 1);
  if (!capture_values(fn, captures, count, values, changed)) {
    return MIR_NONE;
  }
  const uint32_t func = lower_closure_func(fn->cx, fn_ty, captures, count);
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
    if (capture->shared && capture->kind == MS_REF_LOCAL && capture->index < fn->nvars) {
      fn->closing[capture->index] = value;
      fn->closing_var[capture->index] = true;
      fn->closing_types[capture->index] = capture->elem;
      fn->shared[capture->index] = LOWER_SHARED_BORROWED;
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
  const MirTy lambda_ty = fn_type(&fn, ms_facts_type(fn.facts, lambda.expr->id));
  const MirTyData *lambda_data = mir_ty_data(cx->module, lambda_ty);
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
    const MirTy ty = mir_b_ty(&fn.b, values[at]);
    fn.param_vars[at - 1] = mir_b_declare_var(&fn.b, ty, (MirMode)reserved.params[at].mode);
    mir_b_def_var(&fn.b, fn.param_vars[at - 1], values[at]);
    if (reserved.params[at].mode == MM_MOVE && mir_needs_drop(cx->module, ty)) {
      fn_own(&fn, fn_scope(&fn), values[at]);
    }
  }
  fn.nvars = lambda.nvars;
  fn.vars = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirVar, (size_t)fn.nvars + 1);
  fn_init_closing(&fn);
  fn_find_shared(&fn, lambda.expr->u.lambda.body);
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
        return lower_fail(cx, "  while lowering a lambda at %u:%u", cx->lambdas.ptr[index].expr->pos.line, cx->lambdas.ptr[index].expr->pos.column);
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

/* `receiver.operation` where the standard library declares the operation without a body: a closure holding a copy of
 * the receiver whose body is the runtime call, made as a call of the operation is. */
static MirValue bound_native_method(LowerFn *fn, const MsExpr *expr, MirTy fn_ty) {
  Lower *cx = fn->cx;
  const MirTyData *data = mir_ty_data(cx->module, fn_ty);
  const MsTy owner = ms_ty_subst(&cx->program->types, ms_facts_type(fn->facts, expr->u.member.left->id), fn->subst.vars,
                                 fn->subst.args, fn->subst.count);
  MirValue receiver = fn_expr(fn, expr->u.member.left, LW_BORROW);
  if (receiver == MIR_NONE) {
    return MIR_NONE;
  }
  const MirTy receiver_ty = mir_b_ty(&fn->b, receiver);
  if (mir_needs_drop(cx->module, receiver_ty)) {
    receiver = fn_emit(fn, MOP_Clone, &receiver, 1, (MirImm){0}, receiver_ty);
  }
  const LowerCapture capture = {.kind = MS_REF_LOCAL, .ty = receiver_ty};
  const uint32_t slot = lower_closure_func(cx, fn_ty, &capture, 1);
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
  args[0] = mir_b_emit(&body.b, MOP_ClosureCap, &values[0], 1, cap_imm, receiver_ty);
  for (uint32_t at = 1; at < reserved.nparams; at++) {
    args[at] = values[at];
  }
  const MsSpan operation = ms_names_span(cx->program->names, expr->u.member.name);
  MirValue result = MIR_NONE;
  const bool done = fn_native_on(&body, NULL, owner, operation, data->nargs + 1, args, reserved.ret, &result);
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
  mir_func_release(&cx->module->funcs.ptr[slot]);
  cx->module->funcs.ptr[slot] = built;
  const MirImm imm = {.tag = MI_FUNC, .a = slot};
  return fn_emit(fn, MOP_ClosureNew, &receiver, 1, imm, fn_ty);
}

/* `receiver.method` used as a value: a closure that holds a copy of the receiver and calls the method with it. A
 * method that changes its receiver would have to share the receiver's storage, which a copy does not. */
MirValue fn_bound_method(LowerFn *fn, const MsExpr *expr, const MsRef *ref) {
  Lower *cx = fn->cx;
  const MirTy fn_ty = fn_type(fn, ms_facts_type(fn->facts, expr->id));
  const MirTyData *data = mir_ty_data(cx->module, fn_ty);
  MsCall call = {.callee = *ref, .callee_ty = ms_facts_type(fn->facts, expr->id)};
  LowerTarget target;
  if (data->kind == MK_FN && (ref->kind == MS_REF_NATIVE || ref->kind == MS_REF_METHOD) &&
      !fn_callee_target(fn, &call, &target)) {
    return bound_native_method(fn, expr, fn_ty);
  }
  if (data->kind != MK_FN || ref->kind != MS_REF_METHOD) {
    (void)fn_fail(fn, "this method cannot be used as a value yet (reference kind %d at %u:%u)", (int)ref->kind, expr->pos.line,
                  expr->pos.column);
    return MIR_NONE;
  }
  if ((target.receiver_flags & MS_PARAM_VAR) != 0) {
    (void)fn_fail(fn, "a method that changes its receiver as a value is not lowered yet");
    return MIR_NONE;
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
  MirValue receiver = fn_expr(fn, expr->u.member.left, LW_BORROW);
  if (receiver == MIR_NONE) {
    return MIR_NONE;
  }
  const MirTy receiver_ty = mir_b_ty(&fn->b, receiver);
  const bool owns = mir_needs_drop(cx->module, receiver_ty);
  if (owns) {
    receiver = fn_emit(fn, MOP_Clone, &receiver, 1, (MirImm){0}, receiver_ty);
  }
  const LowerCapture capture = {.kind = MS_REF_LOCAL, .ty = receiver_ty};
  const uint32_t slot = lower_closure_func(cx, fn_ty, &capture, 1);
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
  const MirValue result = mir_b_call(&b, callee, args, reserved.nparams);
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
  mir_func_release(&cx->module->funcs.ptr[slot]);
  cx->module->funcs.ptr[slot] = built;
  const MirImm imm = {.tag = MI_FUNC, .a = slot};
  return fn_emit(fn, MOP_ClosureNew, &receiver, 1, imm, fn_ty);
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
  VarSlot slots[16];
  uint32_t nslots = 0;
  args[0] = callee;
  for (uint32_t index = 0; index < data->nargs; index++) {
    const MsExpr *written = expr->u.call.args.ptr[index].value;
    if (mir_param_is_var(data->owned, index)) {
      args[index + 1] = fn_var_slot(fn, written, &slots[nslots++]);
    } else {
      args[index + 1] = fn_expr(fn, written, mir_owns(data->owned, index) ? LW_MOVE : LW_BORROW);
    }
    if (args[index + 1] == MIR_NONE) {
      return MIR_NONE;
    }
  }
  mir_b_set_loc(&fn->b, fn_loc(fn, expr->pos));
  const MirValue result = fn_emit(fn, MOP_CallInd, args, data->nargs + 1, (MirImm){0}, data->elem);
  return fn_var_slots_back(fn, slots, nslots) ? result : MIR_NONE;
}

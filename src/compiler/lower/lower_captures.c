/* compiler/lower/lower_captures.c: what a lambda reads or changes of the function around it.
 *
 * The scan walks the lambda body once and records the parameters and locals it reads (its captures), which of them
 * it changes, and the variables it shares by reference; lower_closure.c builds the closure from the answer. */
#include "base/message.h"
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
  MsName *syms;       /* parallel to names: the name written, which an assignment's bare-name target has no expression for */
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
  for (uint32_t index = 0; pattern->kind == MS_P_TYPE && index < pattern->u.fields.len; index++) {
    declare_pattern(scan, pattern->u.fields.ptr[index].pattern);
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

static void push_sym(Scan *scan, const MsExpr *name, const MsRef *ref, MsName sym);

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
    /* A target that is a bare name is kept in the statement's `name`, not as an expression. */
    mark_changed(scan, target, root != NULL && root->kind == MS_E_NAME ? root->u.sym : (stmt->u.assign.member_target ? 0 : stmt->u.assign.name));
    if (root == NULL && !stmt->u.assign.member_target && scan->root != NULL) { /* a bare name no expression stands for: still a capture */
      push_sym(scan, NULL, ms_facts_ref(scan->fn->facts, stmt->id), stmt->u.assign.name);
    }
  }
}

static void push_sym(Scan *scan, const MsExpr *name, const MsRef *ref, MsName sym) {
  if (ref == NULL) {
    return;
  }
  if (scan->nnames == scan->cnames) {
    scan->cnames = scan->cnames == 0 ? 16 : scan->cnames * 2;
    const MsExpr **names = MS_ARENA_NEW_ARRAY(&scan->fn->cx->module->arena, const MsExpr *, scan->cnames);
    const MsRef **refs = MS_ARENA_NEW_ARRAY(&scan->fn->cx->module->arena, const MsRef *, scan->cnames);
    MsName *syms = MS_ARENA_NEW_ARRAY(&scan->fn->cx->module->arena, MsName, scan->cnames);
    for (uint32_t index = 0; index < scan->nnames; index++) {
      names[index] = scan->names[index];
      refs[index] = scan->refs[index];
      syms[index] = scan->syms[index];
    }
    scan->names = names;
    scan->refs = refs;
    scan->syms = syms;
  }
  scan->names[scan->nnames] = name;
  scan->syms[scan->nnames] = sym;
  scan->refs[scan->nnames++] = ref;
}

static void push_name(Scan *scan, const MsExpr *name, const MsRef *ref) {
  push_sym(scan, name, ref, name->u.sym);
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
bool is_own_param(const LowerFn *fn, const MsExpr *lambda, MsName sym, const MsRef *ref) {
  (void)fn;
  const MsParams *params = (const MsParams *)&lambda->u.lambda.params;
  return ref->local < params->len && params->ptr[ref->local]->name == sym;
}

static bool have_capture(const LowerCapture *captures, uint32_t count, uint8_t kind, uint32_t index, MsName name) {
  for (uint32_t at = 0; at < count; at++) {
    if (captures[at].kind == kind && captures[at].index == index && captures[at].name == name) {
      return true;
    }
  }
  return false;
}

bool find_captures(LowerFn *fn, const MsExpr *lambda, LowerCapture **out, uint32_t *count) {
  Scan scan = {.fn = fn, .root = lambda, .nvars = fn->nvars};
  scan.declared = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, uint8_t, (size_t)fn->nvars + 1);
  const MsVisitor visitor = {.ctx = &scan, .stmt = scan_stmt, .expr = scan_expr};
  for (size_t at = 0; at < lambda->u.lambda.params.len; at++) {
    if (lambda->u.lambda.params.ptr[at]->def != NULL) { /* a default is evaluated in the closure */
      ms_walk_expr(&visitor, lambda->u.lambda.params.ptr[at]->def);
    }
  }
  ms_walk_block(&visitor, lambda->u.lambda.body);
  if (scan.nested) {
    return fn_fail(fn, "a lambda holds too many lambdas to lower");
  }
  LowerCapture *captures = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, LowerCapture, (size_t)scan.nnames + 1);
  uint32_t used = 0;
  for (uint32_t index = 0; index < scan.nnames; index++) {
    const MsExpr *name = scan.names[index];
    const MsName sym = scan.syms[index];
    const MsRef *ref = scan.refs[index];
    if ((ref->kind != MS_REF_PARAM && ref->kind != MS_REF_LOCAL)) {
      continue;
    }
    bool bound = ref->kind == MS_REF_PARAM ? is_own_param(fn, lambda, sym, ref)
                                            : (ref->local < fn->nvars && scan.declared[ref->local] != 0);
    for (uint32_t at = 0; ref->kind == MS_REF_PARAM && !bound && at < scan.ninner; at++) {
      bound = is_own_param(fn, scan.inner[at], sym, ref);
    }
    if (bound) {
      continue;
    }
    if (!have_capture(captures, used, (uint8_t)ref->kind, ref->local, sym)) {
      captures[used++] = (LowerCapture){(uint8_t)ref->kind, ref->local, sym, name, MIR_VOID, false, MIR_VOID, false};
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
      } else if (root != NULL && root->kind == MS_E_UNARY && root->op == MS_U_TRY) {
        root = root->u.bin.left; /* `c?.bump()` changes the optional `c` holds */
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
bool capture_changes(LowerFn *fn, const MsExpr *lambda, const LowerCapture *captures, uint32_t count, bool *changed) {
  Scan scan = {.fn = fn, .root = lambda, .nvars = fn->nvars};
  scan.declared = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, uint8_t, (size_t)fn->nvars + 1);
  scan.captures = captures;
  scan.ncaptures = count;
  scan.changed = changed;
  const MsVisitor visitor = {.ctx = &scan, .stmt = scan_stmt, .expr = scan_var_args};
  for (size_t at = 0; at < lambda->u.lambda.params.len; at++) {
    if (lambda->u.lambda.params.ptr[at]->def != NULL) {
      ms_walk_expr(&visitor, lambda->u.lambda.params.ptr[at]->def);
    }
  }
  ms_walk_block(&visitor, lambda->u.lambda.body);
  bool any = false;
  for (uint32_t at = 0; at < count; at++) {
    any = any || changed[at];
  }
  return any;
}

typedef struct SharedScan {
  LowerFn *fn;
  const MsExpr *callee; /* the callee of the call visited last: a method named there is called, not a value */
  const MsExpr *applied; /* the type application visited last: it records the type of its member operand */
} SharedScan;

/* `local.method` used as a value where the method changes its receiver: the closure shares the local's slot. */
static void find_shared_method(SharedScan *scan, const MsExpr *expr) {
  LowerFn *fn = scan->fn;
  const MsRef *ref = ms_facts_ref(fn->facts, expr->id);
  const MsExpr *left = expr->u.member.left;
  const MsRef *place = left->kind == MS_E_NAME ? ms_facts_ref(fn->facts, left->id) : NULL;
  const bool local = place != NULL && place->kind == MS_REF_LOCAL && place->local < fn->nvars;
  const bool param = place != NULL && place->kind == MS_REF_PARAM && place->local < 32;
  if (ref == NULL || (ref->kind != MS_REF_METHOD && ref->kind != MS_REF_NATIVE) || (!local && !param)) {
    return;
  }
  const MsCall call = {.callee = *ref};
  LowerTarget target;
  bool changes = false;
  if (ref->kind == MS_REF_METHOD && fn_callee_target(fn, &call, &target)) {
    changes = (target.receiver_flags & MS_PARAM_VAR) != 0;
  } else {
    const MsExpr *typed = scan->applied != NULL && scan->applied->u.apply.left == expr ? scan->applied : expr;
    const MirTy fn_ty = fn_type(fn, ms_facts_type(fn->facts, typed->id));
    const MirTyData *data = mir_ty_data(fn->cx->module, fn_ty);
    const MsTy owner = ms_ty_subst(&fn->cx->program->types, ms_facts_type(fn->facts, left->id), fn->subst.vars, fn->subst.args,
                                   fn->subst.count);
    changes = data->kind == MK_FN &&
              fn_native_changes_receiver(fn, owner, ms_names_span(fn->cx->program->names, expr->u.member.name), data->elem);
  }
  if (changes && local) {
    fn->shared[place->local] = LOWER_SHARED;
  } else if (changes) {
    fn->shared_params |= 1u << place->local; /* a `var` parameter stays in the caller's slot, which the closure borrows */
  }
}

static void find_shared_expr(void *ctx, const MsExpr *expr) {
  SharedScan *scan = ctx;
  LowerFn *fn = scan->fn;
  if (expr->kind == MS_E_CALL) {
    scan->callee = expr->u.call.callee;
  } else if (expr->kind == MS_E_APPLY && expr->u.apply.types.len != 0) {
    scan->applied = expr;
  } else if (expr->kind == MS_E_MEMBER && expr != scan->callee) {
    find_shared_method(scan, expr);
  }
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
    } else if (changed[at] && captures[at].kind == MS_REF_PARAM && captures[at].index < 32) {
      fn->shared_params |= 1u << captures[at].index;
    }
  }
}

void fn_find_shared(LowerFn *fn, MsStmts body) {
  fn->shared = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, uint8_t, (size_t)fn->nvars + 1);
  SharedScan scan = {fn, NULL, NULL};
  const MsVisitor visitor = {.ctx = &scan, .expr = find_shared_expr};
  ms_walk_block(&visitor, body);
}

/* compiler/check/scope_walk.c: the scope-keeping syntax walk (see scope_walk.h). */
#include "compiler/check/scope_walk.h"

typedef struct Walk {
  const MsScopeVisitor *visitor;
  MsBindingList scope; /* innermost last */
  MsScopeSite site;
  MsName self;
  uint32_t depth; /* the nesting the next binding is declared at */
  uint32_t anchor; /* the anchor of the next binding */
} Walk;

static void walk_stmts(Walk *pass, MsStmts body);
static void walk_expr(Walk *pass, const MsExpr *expr);
static bool unknown_callee(const Walk *pass, const MsExpr *callee);

static void set_kind(Walk *pass, MsBindingKind kind) {
  pass->scope.ptr[pass->scope.len - 1].kind = kind;
}

static void declare(Walk *pass, MsName name, MsPos decl, bool mutable_, MsBindingOrigin origin) {
  const MsBinding binding = {.name = name, .decl = decl, .mutable_ = mutable_, .origin = origin, .depth = pass->depth,
                           .anchor = pass->anchor};
  ms_binding_list_push(&pass->scope, binding);
  if (pass->visitor->declared != NULL) {
    pass->visitor->declared(pass->visitor->context, &binding, &pass->scope);
  }
}

const MsBinding *ms_scope_lookup(const MsBindingList *scope, MsName name) {
  for (size_t index = scope->len; index > 0; index--) {
    if (scope->ptr[index - 1].name == name) {
      return &scope->ptr[index - 1];
    }
  }
  return NULL;
}

static void declare_pattern(Walk *pass, const MsPattern *pattern, bool mutable_, MsBindingOrigin origin) {
  switch ((MsPatternKind)pattern->kind) {
  case MS_P_NAME:
    declare(pass, pattern->u.name, pattern->pos, mutable_, origin);
    return;
  case MS_P_LIST:
    for (uint32_t index = 0; index < pattern->u.list.len; index++) {
      declare_pattern(pass, pattern->u.list.ptr[index], mutable_, origin);
    }
    return;
  case MS_P_TYPE:
    for (uint32_t index = 0; index < pattern->u.fields.len; index++) {
      declare_pattern(pass, pattern->u.fields.ptr[index].pattern, mutable_, origin);
    }
    return;
  }
}

/* A default value sees the parameters before it, not itself. */
static void declare_params(Walk *pass, MsParams params) {
  for (uint32_t index = 0; index < params.len; index++) {
    const MsParam *param = params.ptr[index];
    if (param->def != NULL) {
      walk_expr(pass, param->def);
    }
    declare(pass, param->name, param->pos, param->is_mutable, MS_BIND_OTHER);
    set_kind(pass, param->moving ? MS_BK_OWNED_PARAM : MS_BK_PARAM);
    if (pass->visitor->invalid_param != NULL && pass->visitor->invalid_param(pass->visitor->context, param)) {
      pass->scope.ptr[pass->scope.len - 1].invalid = true;
    }
  }
}

static void walk_exprs(Walk *pass, const MsExpr *const *items, uint32_t count) {
  for (uint32_t index = 0; index < count; index++) {
    walk_expr(pass, items[index]);
  }
}

static void walk_lambda(Walk *pass, const MsExpr *expr) {
  const size_t mark = pass->scope.len;
  pass->depth++;
  declare_params(pass, expr->u.lambda.params);
  walk_stmts(pass, expr->u.lambda.body);
  pass->depth--;
  ms_binding_list_truncate(&pass->scope, mark);
}

/* A match on a name whose type is wrong has arms that cannot be understood, so they are left alone. */
static bool scrutinee_invalid(const Walk *pass, const MsExpr *scrutinee) {
  if (scrutinee->kind == MS_E_CALL) {
    return unknown_callee(pass, scrutinee->u.call.callee); /* a call of an unknown name has no type to match */
  }
  if (scrutinee->kind != MS_E_NAME) {
    return false;
  }
  const MsBinding *binding = ms_scope_lookup(&pass->scope, scrutinee->u.sym);
  return binding != NULL && binding->invalid;
}

static void walk_match(Walk *pass, const MsExpr *expr) {
  walk_expr(pass, expr->u.match.scrutinee);
  if (scrutinee_invalid(pass, expr->u.match.scrutinee)) {
    return;
  }
  for (uint32_t index = 0; index < expr->u.match.arms.len; index++) {
    const MsArm *arm = expr->u.match.arms.ptr[index];
    const size_t mark = pass->scope.len;
    pass->depth++;
    const bool variant = arm->bare && arm->bindings.len == 1 && pass->visitor->variant_name != NULL &&
                         pass->visitor->variant_name(pass->visitor->context, arm->bindings.ptr[0].name);
    for (uint32_t at = 0; !variant && at < arm->bindings.len; at++) {
      declare(pass, arm->bindings.ptr[at].name, arm->bindings.ptr[at].pos, false, MS_BIND_PAYLOAD);
    }
    walk_stmts(pass, arm->body);
    if (arm->value != NULL) {
      walk_expr(pass, arm->value);
    }
    pass->depth--;
    ms_binding_list_truncate(&pass->scope, mark);
  }
}

static void walk_expr(Walk *pass, const MsExpr *expr) {
  if (pass->visitor->expr != NULL) {
    pass->visitor->expr(pass->visitor->context, expr, &pass->scope, &pass->site);
  }
  switch ((MsExprKind)expr->kind) {
  case MS_E_NUMBER:
  case MS_E_BOOL:
  case MS_E_VOID:
    return;
  case MS_E_NAME:
    if (pass->visitor->name != NULL) {
      pass->visitor->name(pass->visitor->context, expr, &pass->scope, &pass->site);
    }
    return;
  case MS_E_TEXT:
    for (uint32_t index = 0; index < expr->u.text.len; index++) {
      if (expr->u.text.ptr[index].expr != NULL) {
        walk_expr(pass, expr->u.text.ptr[index].expr);
      }
    }
    return;
  case MS_E_MEMBER:
    walk_expr(pass, expr->u.member.left);
    return;
  case MS_E_APPLY:
    walk_expr(pass, expr->u.apply.left);
    if (expr->u.apply.value != NULL) {
      /* `f[T]` reads T as a value too; when it is a bare name it may be a type the value reading cannot see. */
      pass->site.type_reading = expr->u.apply.value->kind == MS_E_NAME;
      walk_expr(pass, expr->u.apply.value);
      pass->site.type_reading = false;
    }
    return;
  case MS_E_INDEX:
  case MS_E_BINARY:
    walk_expr(pass, expr->u.bin.left);
    walk_expr(pass, expr->u.bin.right);
    return;
  case MS_E_PROBE:
  case MS_E_UNARY:
    walk_expr(pass, expr->u.bin.left);
    return;
  case MS_E_LIST:
    walk_exprs(pass, (const MsExpr *const *)expr->u.list.ptr, expr->u.list.len);
    return;
  case MS_E_MAP:
    for (uint32_t index = 0; index < expr->u.map.len; index++) {
      walk_expr(pass, expr->u.map.ptr[index].key);
      walk_expr(pass, expr->u.map.ptr[index].value);
    }
    return;
  case MS_E_LAMBDA: {
    const bool outer = pass->site.in_constant_call;
    pass->site.in_constant_call = pass->site.in_constant;
    walk_lambda(pass, expr);
    pass->site.in_constant_call = outer;
    return;
  }
  case MS_E_CALL: {
    /* A call in a constant is reported as not constant; its unknown names are not reported again. */
    const bool outer = pass->site.in_constant_call;
    pass->site.in_constant_call = pass->site.in_constant;
    walk_expr(pass, expr->u.call.callee);
    if (!unknown_callee(pass, expr->u.call.callee)) {
      for (uint32_t index = 0; index < expr->u.call.args.len; index++) {
        walk_expr(pass, expr->u.call.args.ptr[index].value);
      }
    }
    pass->site.in_constant_call = outer;
    return;
  }
  case MS_E_MATCH:
    walk_match(pass, expr);
    return;
  }
}

/* Whether `callee` is a name already reported unknown, or a call of one: the arguments are then not checked. */
static bool unknown_callee(const Walk *pass, const MsExpr *callee) {
  if (pass->visitor->unknown == NULL) {
    return false;
  }
  while (callee->kind == MS_E_CALL) {
    callee = callee->u.call.callee;
  }
  if (callee->kind != MS_E_NAME) {
    return false;
  }
  return pass->visitor->unknown(pass->visitor->context, callee);
}

static void walk_scoped(Walk *pass, MsStmts body) {
  const size_t mark = pass->scope.len;
  pass->depth++;
  walk_stmts(pass, body);
  pass->depth--;
  ms_binding_list_truncate(&pass->scope, mark);
}

static void walk_branch(Walk *pass, const MsStmt *stmt) {
  walk_expr(pass, stmt->u.branch.cond);
  const size_t mark = pass->scope.len;
  if (stmt->u.branch.binding != NULL) {
    pass->depth++;
    pass->anchor = stmt->u.branch.cond->end.offset;
    declare_pattern(pass, stmt->u.branch.binding, stmt->u.branch.is_mutable, MS_BIND_NARROWED);
    pass->anchor = 0;
    pass->depth--;
  }
  walk_scoped(pass, stmt->u.branch.body);
  ms_binding_list_truncate(&pass->scope, mark);
  walk_scoped(pass, stmt->u.branch.else_body);
}

static void walk_stmt(Walk *pass, const MsStmt *stmt) {
  switch ((MsStmtKind)stmt->kind) {
  case MS_S_BIND:
    walk_expr(pass, stmt->u.bind.value);
    declare_pattern(pass, stmt->u.bind.pattern, stmt->u.bind.is_mutable, MS_BIND_LOCAL);
    return;
  case MS_S_ASSIGN:
    if (stmt->u.assign.member_target) {
      walk_expr(pass, stmt->u.assign.target);
      if (pass->visitor->store != NULL) {
        pass->visitor->store(pass->visitor->context, stmt, &pass->scope, &pass->site);
      }
    } else {
      if (pass->visitor->assign != NULL) {
        pass->visitor->assign(pass->visitor->context, stmt, &pass->scope, &pass->site);
      }
    }
    walk_expr(pass, stmt->u.assign.value);
    return;
  case MS_S_CALL:
    walk_expr(pass, stmt->u.expr);
    return;
  case MS_S_RETURN:
    if (stmt->u.expr != NULL) {
      walk_expr(pass, stmt->u.expr);
    }
    return;
  case MS_S_BREAK:
  case MS_S_CONTINUE:
    return;
  case MS_S_IF:
    walk_branch(pass, stmt);
    return;
  case MS_S_WHILE:
    walk_expr(pass, stmt->u.loop.cond);
    walk_scoped(pass, stmt->u.loop.body);
    return;
  case MS_S_FOR: {
    walk_expr(pass, stmt->u.each.iter);
    const size_t mark = pass->scope.len;
    pass->depth++;
    declare(pass, stmt->u.each.name, stmt->pos, false, MS_BIND_OTHER);
    pass->depth--;
    set_kind(pass, MS_BK_LOOP);
    walk_scoped(pass, stmt->u.each.body);
    ms_binding_list_truncate(&pass->scope, mark);
    return;
  }
  }
}

static void walk_stmts(Walk *pass, MsStmts body) {
  for (uint32_t index = 0; index < body.len; index++) {
    walk_stmt(pass, body.ptr[index]);
  }
}

static void walk_callable(Walk *pass, const MsFunc *func, const MsMethod *method) {
  const size_t mark = pass->scope.len;
  if (method != NULL) {
    declare(pass, pass->self, method->pos, method->mutating, MS_BIND_OTHER);
    set_kind(pass, method->consuming ? MS_BK_OWNED_PARAM : MS_BK_SELF);
  }
  declare_params(pass, func->params);
  walk_stmts(pass, func->body);
  ms_binding_list_truncate(&pass->scope, mark);
}

static void walk_methods(Walk *pass, MsMethod *const *methods, uint32_t count) {
  for (uint32_t index = 0; index < count; index++) {
    walk_callable(pass, &methods[index]->func, methods[index]);
  }
}

static void walk_decl(Walk *pass, const MsDecl *decl) {
  pass->site.decl = decl;
  switch ((MsDeclKind)decl->kind) {
  case MS_D_FN:
    walk_callable(pass, &decl->u.fn, NULL);
    return;
  case MS_D_CONST:
    pass->site.in_constant = true;
    walk_expr(pass, decl->u.konst.value);
    pass->site.in_constant = false;
    return;
  case MS_D_TEST:
    walk_scoped(pass, decl->u.test.body);
    return;
  case MS_D_IMPL:
    pass->site.impl = decl;
    walk_methods(pass, decl->u.impl.methods.ptr, decl->u.impl.methods.len);
    pass->site.impl = NULL;
    return;
  case MS_D_INTERFACE:
    walk_methods(pass, decl->u.iface.methods.ptr, decl->u.iface.methods.len);
    return;
  case MS_D_TYPE:
  case MS_D_ENUM:
  case MS_D_ALIAS:
    return;
  }
}


void ms_scope_walk_module(const MsModule *tree, const MsScopeVisitor *visitor, MsNames *names) {
  Walk pass = {.visitor = visitor, .self = ms_names_intern(names, ms_span_of_text("self"))};
  for (uint32_t index = 0; index < tree->ndecls; index++) {
    walk_decl(&pass, tree->decls[index]);
  }
  ms_binding_list_free(&pass.scope);
}

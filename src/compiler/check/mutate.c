/* compiler/check/mutate.c: the mutability pass.
 *
 * Walks every body with lexical scopes of bindings (parameters, `:=` and `var` bindings, pattern names, loop
 * variables, match payloads, lambda parameters) and checks the target of each assignment to a name. */
#include "compiler/check/mutate.h"
#include "compiler/check/mutate_fix.h"
#include "compiler/check/symbol_text.h"

typedef struct Binding {
  MsName name;
  MsPos decl;
  bool mutable_;
} Binding;

MS_LIST_DEFINE(BindingList, binding_list, Binding)

typedef struct Mutate {
  MsCheckProgram *program;
  uint32_t module;
  MsSpan source;
  BindingList scope; /* innermost last */
} Mutate;

static void walk_stmts(Mutate *pass, MsStmts body);
static void walk_expr(Mutate *pass, const MsExpr *expr);

static void declare(Mutate *pass, MsName name, MsPos decl, bool mutable_) {
  binding_list_push(&pass->scope, (Binding){.name = name, .decl = decl, .mutable_ = mutable_});
}

static const Binding *lookup(const Mutate *pass, MsName name) {
  for (size_t index = pass->scope.len; index > 0; index--) {
    if (pass->scope.ptr[index - 1].name == name) {
      return &pass->scope.ptr[index - 1];
    }
  }
  return NULL;
}

static void declare_pattern(Mutate *pass, const MsPattern *pattern, bool mutable_) {
  switch ((MsPatternKind)pattern->kind) {
  case MS_P_NAME:
    declare(pass, pattern->u.name, pattern->pos, mutable_);
    return;
  case MS_P_LIST:
    for (uint32_t index = 0; index < pattern->u.list.len; index++) {
      declare_pattern(pass, pattern->u.list.ptr[index], mutable_);
    }
    return;
  case MS_P_TYPE:
    for (uint32_t index = 0; index < pattern->u.fields.len; index++) {
      declare_pattern(pass, pattern->u.fields.ptr[index].pattern, mutable_);
    }
    return;
  }
}

static void declare_params(Mutate *pass, MsParams params) {
  for (uint32_t index = 0; index < params.len; index++) {
    const MsParam *param = params.ptr[index];
    declare(pass, param->name, param->pos, param->is_mutable);
  }
}

static void append_name(Mutate *pass, MsStrBuild *text, MsName name) {
  ms_strbuild_append(text, ms_names_span(pass->program->names, name));
}

/* "cannot assign immutable binding NAME; declare it with 'var NAME = ...' instead of 'NAME := ...'" */
static void report_immutable(Mutate *pass, const MsStmt *stmt, const Binding *binding) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "cannot assign immutable binding ");
  append_name(pass, &text, binding->name);
  ms_strbuild_append_text(&text, "; declare it with 'var ");
  append_name(pass, &text, binding->name);
  ms_strbuild_append_text(&text, " = ...' instead of '");
  append_name(pass, &text, binding->name);
  ms_strbuild_append_text(&text, " := ...'");
  MsVarFix fix = {0};
  const bool has_fix = ms_var_fix(pass->source, binding->decl, &fix);
  ms_check_report(pass->program, pass->module, stmt->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  if (has_fix) {
    ms_check_attach_fix(pass->program, fix.pos, fix.end, fix.replacement);
  }
}

static void report_not_a_binding(Mutate *pass, const MsStmt *stmt, const MsSymbol *symbol) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "cannot assign to ");
  ms_strbuild_append_text(&text, ms_symbol_description(pass->module, symbol));
  ms_strbuild_append_text(&text, " ");
  append_name(pass, &text, stmt->u.assign.name);
  ms_strbuild_append_text(&text, "; assignment targets are 'var' bindings and type fields");
  ms_check_report(pass->program, pass->module, stmt->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

static void check_assign(Mutate *pass, const MsStmt *stmt) {
  const MsName name = stmt->u.assign.name;
  const Binding *binding = lookup(pass, name);
  if (binding != NULL) {
    if (!binding->mutable_) {
      report_immutable(pass, stmt, binding);
    }
    return;
  }
  const MsSymbolId *id = ms_scope_get(&pass->program->modules.ptr[pass->module].scope, name);
  if (id != NULL) {
    report_not_a_binding(pass, stmt, &pass->program->symbols.ptr[*id]);
  }
}

static void walk_exprs(Mutate *pass, const MsExpr *const *items, uint32_t count) {
  for (uint32_t index = 0; index < count; index++) {
    walk_expr(pass, items[index]);
  }
}

static void walk_lambda(Mutate *pass, const MsExpr *expr) {
  const size_t mark = pass->scope.len;
  for (uint32_t index = 0; index < expr->u.lambda.params.len; index++) {
    if (expr->u.lambda.params.ptr[index]->def != NULL) {
      walk_expr(pass, expr->u.lambda.params.ptr[index]->def);
    }
  }
  declare_params(pass, expr->u.lambda.params);
  walk_stmts(pass, expr->u.lambda.body);
  binding_list_truncate(&pass->scope, mark);
}

static void walk_match(Mutate *pass, const MsExpr *expr) {
  walk_expr(pass, expr->u.match.scrutinee);
  for (uint32_t index = 0; index < expr->u.match.arms.len; index++) {
    const MsArm *arm = expr->u.match.arms.ptr[index];
    const size_t mark = pass->scope.len;
    for (uint32_t at = 0; at < arm->bindings.len; at++) {
      declare(pass, arm->bindings.ptr[at].name, arm->bindings.ptr[at].pos, false);
    }
    walk_stmts(pass, arm->body);
    if (arm->value != NULL) {
      walk_expr(pass, arm->value);
    }
    binding_list_truncate(&pass->scope, mark);
  }
}

static void walk_expr(Mutate *pass, const MsExpr *expr) {
  switch ((MsExprKind)expr->kind) {
  case MS_E_NUMBER:
  case MS_E_BOOL:
  case MS_E_VOID:
  case MS_E_NAME:
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
      walk_expr(pass, expr->u.apply.value);
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
  case MS_E_LAMBDA:
    walk_lambda(pass, expr);
    return;
  case MS_E_CALL:
    walk_expr(pass, expr->u.call.callee);
    for (uint32_t index = 0; index < expr->u.call.args.len; index++) {
      walk_expr(pass, expr->u.call.args.ptr[index].value);
    }
    return;
  case MS_E_MATCH:
    walk_match(pass, expr);
    return;
  }
}

static void walk_scoped(Mutate *pass, MsStmts body) {
  const size_t mark = pass->scope.len;
  walk_stmts(pass, body);
  binding_list_truncate(&pass->scope, mark);
}

static void walk_branch(Mutate *pass, const MsStmt *stmt) {
  walk_expr(pass, stmt->u.branch.cond);
  const size_t mark = pass->scope.len;
  if (stmt->u.branch.binding != NULL) {
    declare_pattern(pass, stmt->u.branch.binding, stmt->u.branch.is_mutable);
  }
  walk_scoped(pass, stmt->u.branch.body);
  binding_list_truncate(&pass->scope, mark);
  walk_scoped(pass, stmt->u.branch.else_body);
}

static void walk_stmt(Mutate *pass, const MsStmt *stmt) {
  switch ((MsStmtKind)stmt->kind) {
  case MS_S_BIND:
    walk_expr(pass, stmt->u.bind.value);
    declare_pattern(pass, stmt->u.bind.pattern, stmt->u.bind.is_mutable);
    return;
  case MS_S_ASSIGN:
    if (stmt->u.assign.member_target) {
      walk_expr(pass, stmt->u.assign.target);
    } else {
      check_assign(pass, stmt);
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
    declare(pass, stmt->u.each.name, stmt->pos, false);
    walk_scoped(pass, stmt->u.each.body);
    binding_list_truncate(&pass->scope, mark);
    return;
  }
  }
}

static void walk_stmts(Mutate *pass, MsStmts body) {
  for (uint32_t index = 0; index < body.len; index++) {
    walk_stmt(pass, body.ptr[index]);
  }
}

static void walk_callable(Mutate *pass, const MsFunc *func) {
  const size_t mark = pass->scope.len;
  for (uint32_t index = 0; index < func->params.len; index++) {
    if (func->params.ptr[index]->def != NULL) {
      walk_expr(pass, func->params.ptr[index]->def);
    }
  }
  declare_params(pass, func->params);
  walk_stmts(pass, func->body);
  binding_list_truncate(&pass->scope, mark);
}

static void walk_methods(Mutate *pass, MsMethod *const *methods, uint32_t count) {
  for (uint32_t index = 0; index < count; index++) {
    walk_callable(pass, &methods[index]->func);
  }
}

static void walk_decl(Mutate *pass, const MsDecl *decl) {
  switch ((MsDeclKind)decl->kind) {
  case MS_D_FN:
    walk_callable(pass, &decl->u.fn);
    return;
  case MS_D_CONST:
    walk_expr(pass, decl->u.konst.value);
    return;
  case MS_D_TEST:
    walk_scoped(pass, decl->u.test.body);
    return;
  case MS_D_IMPL:
    walk_methods(pass, decl->u.impl.methods.ptr, decl->u.impl.methods.len);
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

void ms_check_mutation(MsCheckProgram *program, uint32_t module, MsSpan source) {
  Mutate pass = {.program = program, .module = module, .source = source};
  const MsModule *tree = program->modules.ptr[module].tree;
  for (uint32_t index = 0; index < tree->ndecls; index++) {
    walk_decl(&pass, tree->decls[index]);
  }
  binding_list_free(&pass.scope);
}

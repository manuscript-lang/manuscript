/* compiler/check/returns.c: the return-statement pass (see returns.h). */
#include "compiler/check/returns.h"

#include "compiler/check/fallthrough.h"

typedef struct Returns {
  MsCheckProgram *program;
  uint32_t module;
  const MsFunc *func;
} Returns;

static void walk_stmts(Returns *pass, MsStmts body);

static void report_bare(Returns *pass, const MsStmt *stmt) {
  if (ms_fall_is_unit(pass->program, pass->func->result)) {
    return;
  }
  MsStrBuild type = ms_strbuild_new();
  if (ms_fall_type_text(pass->program, pass->module, pass->func, pass->func->result, &type)) {
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append_text(&text, "bare return requires Void or Void!; this function returns ");
    ms_strbuild_append(&text, ms_strbuild_span(&type));
    const MsTypeRef *result = pass->func->result;
    const bool is_result = ms_span_is_text(ms_names_span(pass->program->names, result->name), "Result");
    ms_strbuild_append_text(&text, is_result ? ", so write 'return ok(value)' for success or 'return error(e)' for failure"
                                             : ", so write 'return <value>'");
    ms_check_report(pass->program, pass->module, stmt->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  }
  ms_strbuild_free(&type);
}

/* The arms of a match used as a statement or as a value hold statements that can return. */
static void walk_expr(Returns *pass, const MsExpr *expr) {
  if (expr == NULL || expr->kind != MS_E_MATCH) {
    return;
  }
  for (uint32_t index = 0; index < expr->u.match.arms.len; index++) {
    walk_stmts(pass, expr->u.match.arms.ptr[index]->body);
  }
}

static void walk_stmt(Returns *pass, const MsStmt *stmt) {
  switch ((MsStmtKind)stmt->kind) {
  case MS_S_RETURN:
    if (stmt->u.expr == NULL) {
      report_bare(pass, stmt);
    }
    walk_expr(pass, stmt->u.expr);
    return;
  case MS_S_CALL:
    walk_expr(pass, stmt->u.expr);
    return;
  case MS_S_BIND:
    walk_expr(pass, stmt->u.bind.value);
    return;
  case MS_S_IF:
    walk_stmts(pass, stmt->u.branch.body);
    walk_stmts(pass, stmt->u.branch.else_body);
    return;
  case MS_S_WHILE:
    walk_stmts(pass, stmt->u.loop.body);
    return;
  case MS_S_FOR:
    walk_stmts(pass, stmt->u.each.body);
    return;
  case MS_S_ASSIGN:
  case MS_S_BREAK:
  case MS_S_CONTINUE:
    return;
  }
}

static void walk_stmts(Returns *pass, MsStmts body) {
  for (uint32_t index = 0; index < body.len; index++) {
    walk_stmt(pass, body.ptr[index]);
  }
}

static void walk_function(Returns *pass, const MsFunc *func) {
  if (func->external || func->result == NULL) {
    return;
  }
  pass->func = func;
  walk_stmts(pass, func->body);
}

void ms_check_returns(MsCheckProgram *program, uint32_t module) {
  Returns pass = {.program = program, .module = module};
  const MsModule *tree = program->modules.ptr[module].tree;
  for (uint32_t index = 0; index < tree->ndecls; index++) {
    const MsDecl *decl = tree->decls[index];
    if (decl->kind == MS_D_FN) {
      walk_function(&pass, &decl->u.fn);
    }
  }
}

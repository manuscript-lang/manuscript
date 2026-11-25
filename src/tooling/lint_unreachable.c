/* Owns the unreachable-statement rule of lint.h: MSL103. A statement is unreachable when an earlier statement of
 * its block never falls through (return, break, continue, a call or value that never returns, or a branch all of
 * whose paths end). */
#include "compiler/syntax/walk.h"
#include "tooling/lint.h"

typedef struct Ctx {
  const MsCheckProgram *program;
  const MsModuleInfo *module;
  MsSpan file;
  MsArena *arena;
  MsLintFindingList *findings;
} Ctx;

/* How an expression leaves: it never returns, or a `break` of the enclosing loop is reachable inside it. */
typedef struct ExprFlow {
  bool no_return, breaks;
} ExprFlow;

/* How a statement leaves: control falls through to the next one, or a `break` of the enclosing loop is reachable. */
typedef struct Flow {
  bool falls, breaks;
} Flow;

static ExprFlow expr_flow(const Ctx *ctx, const MsExpr *expr);
static Flow stmt_flow(const Ctx *ctx, const MsStmt *stmt);

static ExprFlow either(ExprFlow a, ExprFlow b) {
  return (ExprFlow){a.no_return || b.no_return, a.breaks || b.breaks};
}

static Flow block_flow(const Ctx *ctx, MsStmts body) {
  Flow flow = {.falls = true};
  for (uint32_t i = 0; i < body.len; i++) {
    const Flow next = stmt_flow(ctx, body.ptr[i]);
    if (flow.falls) {
      flow.breaks = flow.breaks || next.breaks;
      flow.falls = next.falls;
    }
  }
  return flow;
}

/* A match falls through when an arm does; one that does not never returns. */
static ExprFlow match_flow(const Ctx *ctx, const MsExpr *match) {
  const ExprFlow scrutinee = expr_flow(ctx, match->u.match.scrutinee);
  bool falls = false;
  bool breaks = false;
  for (uint32_t i = 0; i < match->u.match.arms.len; i++) {
    const MsArm *arm = match->u.match.arms.ptr[i];
    const Flow body = block_flow(ctx, arm->body);
    bool normal = body.falls;
    breaks = breaks || body.breaks;
    if (arm->value != NULL && normal) {
      const ExprFlow value = expr_flow(ctx, arm->value);
      breaks = breaks || value.breaks;
      normal = !value.no_return;
    }
    falls = falls || normal;
  }
  return (ExprFlow){scrutinee.no_return || !falls, scrutinee.breaks || (!scrutinee.no_return && breaks)};
}

static ExprFlow expr_flow(const Ctx *ctx, const MsExpr *expr) {
  const MsTy ty = ms_facts_type(&ctx->module->facts, expr->id);
  ExprFlow flow = {.no_return = ty != MS_TY_NONE && ms_ty_is(&ctx->program->types, ty, MS_BUILTIN_Never)};
  switch ((MsExprKind)expr->kind) {
  case MS_E_TEXT:
    for (uint32_t i = 0; i < expr->u.text.len; i++) {
      if (expr->u.text.ptr[i].expr != NULL) {
        flow = either(flow, expr_flow(ctx, expr->u.text.ptr[i].expr));
      }
    }
    break;
  case MS_E_MEMBER:
    flow = either(flow, expr_flow(ctx, expr->u.member.left));
    break;
  case MS_E_APPLY:
    flow = either(flow, expr_flow(ctx, expr->u.apply.left));
    break;
  case MS_E_INDEX:
    flow = either(flow, either(expr_flow(ctx, expr->u.bin.left), expr_flow(ctx, expr->u.bin.right)));
    break;
  case MS_E_PROBE:
  case MS_E_UNARY:
    flow = either(flow, expr_flow(ctx, expr->u.bin.left));
    break;
  case MS_E_LIST:
    for (uint32_t i = 0; i < expr->u.list.len; i++) {
      flow = either(flow, expr_flow(ctx, expr->u.list.ptr[i]));
    }
    break;
  case MS_E_MAP:
    for (uint32_t i = 0; i < expr->u.map.len; i++) {
      flow = either(flow, either(expr_flow(ctx, expr->u.map.ptr[i].key), expr_flow(ctx, expr->u.map.ptr[i].value)));
    }
    break;
  case MS_E_BINARY: {
    const bool logical = expr->op == MS_B_AND || expr->op == MS_B_OR;
    const ExprFlow left = expr_flow(ctx, expr->u.bin.left);
    const ExprFlow right = expr_flow(ctx, expr->u.bin.right);
    flow.no_return = flow.no_return || left.no_return || (!logical && right.no_return);
    flow.breaks = flow.breaks || left.breaks || right.breaks;
    break;
  }
  case MS_E_CALL:
    flow = either(flow, expr_flow(ctx, expr->u.call.callee));
    for (uint32_t i = 0; i < expr->u.call.args.len; i++) {
      flow = either(flow, expr_flow(ctx, expr->u.call.args.ptr[i].value));
    }
    break;
  case MS_E_MATCH:
    flow = match_flow(ctx, expr);
    break;
  case MS_E_NUMBER:
  case MS_E_BOOL:
  case MS_E_VOID:
  case MS_E_NAME:
  case MS_E_LAMBDA:
    break;
  }
  return flow;
}

static Flow value_flow(const Ctx *ctx, const MsExpr *value) {
  const ExprFlow flow = expr_flow(ctx, value);
  return (Flow){!flow.no_return, flow.breaks};
}

static Flow branch_flow(const Ctx *ctx, const MsStmt *stmt) {
  const ExprFlow cond = expr_flow(ctx, stmt->u.branch.cond);
  const Flow then = block_flow(ctx, stmt->u.branch.body);
  Flow other = {.falls = true};
  if (stmt->u.branch.else_body.len != 0) {
    other = block_flow(ctx, stmt->u.branch.else_body);
  }
  return (Flow){!cond.no_return && (then.falls || other.falls),
                cond.breaks || (!cond.no_return && (then.breaks || other.breaks))};
}

static Flow loop_flow(const Ctx *ctx, const MsStmt *stmt) {
  const ExprFlow cond = expr_flow(ctx, stmt->u.loop.cond);
  const Flow body = block_flow(ctx, stmt->u.loop.body);
  const bool forever = stmt->u.loop.cond->kind == MS_E_BOOL && stmt->u.loop.cond->u.flag;
  return (Flow){!cond.no_return && (!forever || body.breaks), cond.breaks};
}

static Flow assign_flow(const Ctx *ctx, const MsStmt *stmt) {
  ExprFlow flow = expr_flow(ctx, stmt->u.assign.value);
  if (stmt->u.assign.member_target) {
    flow = either(flow, expr_flow(ctx, stmt->u.assign.target));
  }
  return (Flow){!flow.no_return, flow.breaks};
}

static Flow stmt_flow(const Ctx *ctx, const MsStmt *stmt) {
  switch ((MsStmtKind)stmt->kind) {
  case MS_S_BIND:
    return value_flow(ctx, stmt->u.bind.value);
  case MS_S_ASSIGN:
    return assign_flow(ctx, stmt);
  case MS_S_CALL:
    return value_flow(ctx, stmt->u.expr);
  case MS_S_RETURN:
    return (Flow){false, stmt->u.expr != NULL && expr_flow(ctx, stmt->u.expr).breaks};
  case MS_S_BREAK:
    return (Flow){false, true};
  case MS_S_CONTINUE:
    return (Flow){false, false};
  case MS_S_IF:
    return branch_flow(ctx, stmt);
  case MS_S_WHILE:
    return loop_flow(ctx, stmt);
  case MS_S_FOR: {
    const ExprFlow iter = expr_flow(ctx, stmt->u.each.iter);
    return (Flow){!iter.no_return, iter.breaks};
  }
  }
  return (Flow){true, false};
}

static void scan_block(void *context, MsStmts body) {
  const Ctx *ctx = context;
  bool reachable = true;
  for (uint32_t i = 0; i < body.len; i++) {
    const MsStmt *stmt = body.ptr[i];
    if (!reachable) {
      ms_lint_add(ctx->findings, "MSL103", ctx->file, stmt->pos, ms_span_of_text("Statement is unreachable"));
    }
    if (!stmt_flow(ctx, stmt).falls) {
      reachable = false;
    }
  }
}

void ms_lint_unreachable(MsArena *arena, const MsCheckProgram *program, uint32_t module_index,
                         MsLintFindingList *findings) {
  const MsModuleInfo *module = &program->modules.ptr[module_index];
  if (module->tree == NULL) {
    return;
  }
  Ctx ctx = {program, module, ms_names_span(program->names, module->file), arena, findings};
  const MsVisitor visitor = {.ctx = &ctx, .block = scan_block};
  for (uint32_t i = 0; i < module->tree->ndecls; i++) {
    ms_walk_decl(&visitor, module->tree->decls[i]);
  }
}

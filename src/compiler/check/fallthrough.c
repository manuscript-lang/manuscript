/* compiler/check/fallthrough.c: the reachable-fallthrough pass (see fallthrough.h). */
#include "compiler/check/fallthrough.h"

/* Whether control can reach the end of a statement: yes, no, or maybe (a call that may never return). */
typedef enum Reach { REACH_NO, REACH_MAYBE, REACH_YES } Reach;

typedef struct Flow {
  Reach reach;
  bool breaks; /* a `break` of the enclosing loop is reachable inside */
} Flow;

static Flow block_flow(const MsStmts *body);
static Flow statement_flow(const MsStmt *stmt);

static Reach join(Reach a, Reach b) {
  return a > b ? a : b;
}

/* One statement after another: a later statement is reached only while the earlier ones fall through. */
static Flow sequence(Flow before, Flow next) {
  if (before.reach == REACH_NO) {
    return before;
  }
  const Reach reach = next.reach == REACH_NO ? REACH_NO : (before.reach == REACH_MAYBE ? REACH_MAYBE : next.reach);
  return (Flow){.reach = reach, .breaks = before.breaks || next.breaks};
}

static Flow block_flow(const MsStmts *body) {
  Flow flow = {.reach = REACH_YES};
  for (uint32_t index = 0; index < body->len; index++) {
    flow = sequence(flow, statement_flow(body->ptr[index]));
  }
  return flow;
}

static Flow arm_flow(const MsArm *arm) {
  Flow flow = block_flow(&arm->body);
  if (arm->value != NULL && arm->value->kind == MS_E_CALL) {
    flow = sequence(flow, (Flow){.reach = REACH_MAYBE});
  }
  return flow;
}

/* A match falls through when an arm does; one without arms never does. */
static Flow match_flow(const MsExpr *match) {
  Flow flow = {.reach = REACH_NO};
  for (uint32_t index = 0; index < match->u.match.arms.len; index++) {
    const Flow arm = arm_flow(match->u.match.arms.ptr[index]);
    flow = (Flow){.reach = join(flow.reach, arm.reach), .breaks = flow.breaks || arm.breaks};
  }
  return flow;
}

static Flow expression_flow(const MsExpr *expr) {
  if (expr->kind == MS_E_MATCH) {
    return match_flow(expr);
  }
  return (Flow){.reach = expr->kind == MS_E_CALL ? REACH_MAYBE : REACH_YES};
}

static Flow branch_flow(const MsStmt *stmt) {
  const Flow then = block_flow(&stmt->u.branch.body);
  Flow other = {.reach = REACH_YES};
  if (stmt->u.branch.else_body.len != 0) {
    other = block_flow(&stmt->u.branch.else_body);
  }
  return (Flow){.reach = join(then.reach, other.reach), .breaks = then.breaks || other.breaks};
}

/* `while true` leaves only through a break; any other loop may run zero times. */
static Flow while_flow(const MsStmt *stmt) {
  const Flow body = block_flow(&stmt->u.loop.body);
  const MsExpr *cond = stmt->u.loop.cond;
  const bool forever = cond->kind == MS_E_BOOL && cond->u.flag;
  return (Flow){.reach = !forever || body.breaks ? REACH_YES : REACH_NO};
}

static Flow statement_flow(const MsStmt *stmt) {
  switch ((MsStmtKind)stmt->kind) {
  case MS_S_RETURN:
  case MS_S_CONTINUE:
    return (Flow){.reach = REACH_NO};
  case MS_S_BREAK:
    return (Flow){.reach = REACH_NO, .breaks = true};
  case MS_S_CALL:
    return expression_flow(stmt->u.expr);
  case MS_S_IF:
    return branch_flow(stmt);
  case MS_S_WHILE:
    return while_flow(stmt);
  case MS_S_BIND:
  case MS_S_ASSIGN:
  case MS_S_FOR:
    return (Flow){.reach = REACH_YES};
  }
  return (Flow){.reach = REACH_YES};
}

static void report(MsCheckProgram *program, uint32_t module, const MsDecl *decl, MsStrBuild *type) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "reachable fallthrough in function returning ");
  ms_strbuild_append(&text, ms_strbuild_span(type));
  ms_strbuild_append_text(&text, "; end every path with 'return <");
  ms_strbuild_append(&text, ms_strbuild_span(type));
  ms_strbuild_append_text(&text, ">' (or make the last branch return)");
  ms_check_report(program, module, decl->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

static void check_function(MsCheckProgram *program, uint32_t module, const MsDecl *decl) {
  const MsFunc *func = &decl->u.fn;
  if (func->external || func->result == NULL || ms_fall_is_unit(program, func->result)) {
    return;
  }
  if (block_flow(&func->body).reach != REACH_YES) {
    return;
  }
  MsStrBuild type = ms_strbuild_new();
  if (ms_fall_type_text(program, module, func, func->result, &type)) {
    report(program, module, decl, &type);
  }
  ms_strbuild_free(&type);
}

void ms_check_fallthrough(MsCheckProgram *program, uint32_t module) {
  const MsModule *tree = program->modules.ptr[module].tree;
  for (uint32_t index = 0; index < tree->ndecls; index++) {
    if (tree->decls[index]->kind == MS_D_FN) {
      check_function(program, module, tree->decls[index]);
    }
  }
}

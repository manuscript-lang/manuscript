/* compiler/check/fallthrough.c: the reachable-fallthrough pass (see fallthrough.h). */
#include "compiler/check/fallthrough.h"

/* Whether control can reach the end of a statement: yes, no, or maybe (a call that may never return). */
typedef enum Reach { REACH_NO, REACH_MAYBE, REACH_YES } Reach;

typedef struct Ctx {
  const MsCheckProgram *program;
  const MsFacts *facts; /* the types of the module's expressions */
} Ctx;

typedef struct Flow {
  Reach reach;
  bool breaks; /* a `break` of the enclosing loop is reachable inside */
} Flow;

static Flow block_flow(const Ctx *ctx, const MsStmts *body);
static Flow statement_flow(const Ctx *ctx, const MsStmt *stmt);
static Flow expression_flow(const Ctx *ctx, const MsExpr *expr);

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

static Flow block_flow(const Ctx *ctx, const MsStmts *body) {
  Flow flow = {.reach = REACH_YES};
  for (uint32_t index = 0; index < body->len; index++) {
    flow = sequence(flow, statement_flow(ctx, body->ptr[index]));
  }
  return flow;
}

static Flow arm_flow(const Ctx *ctx, const MsArm *arm) {
  Flow flow = block_flow(ctx, &arm->body);
  if (arm->value != NULL) {
    flow = sequence(flow, expression_flow(ctx, arm->value));
  }
  return flow;
}

/* A match falls through when an arm does; one without arms never does. */
static Flow match_flow(const Ctx *ctx, const MsExpr *match) {
  Flow flow = {.reach = REACH_NO};
  for (uint32_t index = 0; index < match->u.match.arms.len; index++) {
    const Flow arm = arm_flow(ctx, match->u.match.arms.ptr[index]);
    flow = (Flow){.reach = join(flow.reach, arm.reach), .breaks = flow.breaks || arm.breaks};
  }
  return flow;
}

/* A call falls through unless its type is Never; a call the checker could not type may be one that never
 * returns. */
static Reach call_reach(const Ctx *ctx, const MsExpr *call) {
  const MsTy ty = ms_facts_type(ctx->facts, call->id);
  if (ty == MS_TY_NONE) {
    /* A callee that resolved to nothing is an unknown name: the call returns as far as the checker can tell. */
    const MsRef *callee = ms_facts_ref(ctx->facts, call->u.call.callee->id);
    return callee == NULL || callee->kind == MS_REF_NONE ? REACH_YES : REACH_MAYBE;
  }
  return ms_ty_is(&ctx->program->types, ty, MS_BUILTIN_Never) ? REACH_NO : REACH_YES;
}

/* A call whose receiver or argument never returns never runs, so what follows it is unreachable. */
static bool operand_never_returns(const Ctx *ctx, const MsExpr *call) {
  const MsExpr *callee = call->u.call.callee;
  if (callee->kind == MS_E_MEMBER && expression_flow(ctx, callee->u.member.left).reach == REACH_NO) {
    return true;
  }
  for (uint32_t index = 0; index < call->u.call.args.len; index++) {
    if (expression_flow(ctx, call->u.call.args.ptr[index].value).reach == REACH_NO) {
      return true;
    }
  }
  return false;
}

static Flow expression_flow(const Ctx *ctx, const MsExpr *expr) {
  if (expr->kind == MS_E_MATCH) {
    return match_flow(ctx, expr);
  }
  if (expr->kind != MS_E_CALL) {
    return (Flow){.reach = REACH_YES};
  }
  return (Flow){.reach = operand_never_returns(ctx, expr) ? REACH_NO : call_reach(ctx, expr)};
}

/* A value that is bound or assigned stops the path only when it is known to have type Never. */
static Flow value_flow(const Ctx *ctx, const MsExpr *value) {
  const MsTy ty = ms_facts_type(ctx->facts, value->id);
  const bool never = ty != MS_TY_NONE && ms_ty_is(&ctx->program->types, ty, MS_BUILTIN_Never);
  return (Flow){.reach = never ? REACH_NO : REACH_YES};
}

static Flow branch_flow(const Ctx *ctx, const MsStmt *stmt) {
  if (stmt->u.branch.cond != NULL && expression_flow(ctx, stmt->u.branch.cond).reach == REACH_NO) {
    return (Flow){.reach = REACH_NO}; /* the condition never completes: neither branch runs */
  }
  const Flow then = block_flow(ctx, &stmt->u.branch.body);
  Flow other = {.reach = REACH_YES};
  if (stmt->u.branch.else_body.len != 0) {
    other = block_flow(ctx, &stmt->u.branch.else_body);
  }
  return (Flow){.reach = join(then.reach, other.reach), .breaks = then.breaks || other.breaks};
}

/* `while true` leaves only through a break; any other loop may run zero times. */
static Flow while_flow(const Ctx *ctx, const MsStmt *stmt) {
  const Flow body = block_flow(ctx, &stmt->u.loop.body);
  const MsExpr *cond = stmt->u.loop.cond;
  const bool forever = cond->kind == MS_E_BOOL && cond->u.flag;
  /* A `break` in the condition (an arm of a match) belongs to the enclosing loop, not to this one. */
  return (Flow){.reach = !forever || body.breaks ? REACH_YES : REACH_NO, .breaks = expression_flow(ctx, cond).breaks};
}

static Flow statement_flow(const Ctx *ctx, const MsStmt *stmt) {
  switch ((MsStmtKind)stmt->kind) {
  case MS_S_RETURN:
  case MS_S_CONTINUE:
    return (Flow){.reach = REACH_NO};
  case MS_S_BREAK:
    return (Flow){.reach = REACH_NO, .breaks = true};
  case MS_S_CALL:
    return expression_flow(ctx, stmt->u.expr);
  case MS_S_IF:
    return branch_flow(ctx, stmt);
  case MS_S_WHILE:
    return while_flow(ctx, stmt);
  case MS_S_BIND:
    return value_flow(ctx, stmt->u.bind.value);
  case MS_S_ASSIGN:
    return value_flow(ctx, stmt->u.assign.value);
  case MS_S_FOR:
    return (Flow){.reach = REACH_YES};
  }
  return (Flow){.reach = REACH_YES};
}

static void report(MsCheckProgram *program, uint32_t module, MsPos pos, MsStrBuild *type) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "reachable fallthrough in function returning ");
  ms_strbuild_append(&text, ms_strbuild_span(type));
  ms_strbuild_append_text(&text, "; end every path with 'return <");
  ms_strbuild_append(&text, ms_strbuild_span(type));
  ms_strbuild_append_text(&text, ">' (or make the last branch return)");
  ms_check_report(program, module, pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  program->diagnostics.ptr[program->diagnostics.len - 1].ends_decl = true;
}

static void check_function(MsCheckProgram *program, uint32_t module, const MsFunc *func, MsPos pos) {
  if (func->external || func->result == NULL || ms_fall_is_unit(program, func->result)) {
    return;
  }
  const Ctx ctx = {.program = program, .facts = &program->modules.ptr[module].facts};
  if (block_flow(&ctx, &func->body).reach != REACH_YES) {
    return;
  }
  MsStrBuild type = ms_strbuild_new();
  if (ms_fall_type_text(program, module, func, func->result, &type)) {
    report(program, module, pos, &type);
  }
  ms_strbuild_free(&type);
}

void ms_check_fallthrough(MsCheckProgram *program, uint32_t module, const MsDecl *decl) {
  if (module >= program->user_modules) {
    return;
  }
  if (decl->kind == MS_D_FN) {
    check_function(program, module, &decl->u.fn, decl->pos);
  }
  const bool methods = decl->kind == MS_D_IMPL;
  for (uint32_t index = 0; methods && index < decl->u.impl.methods.len; index++) {
    const MsMethod *method = decl->u.impl.methods.ptr[index];
    check_function(program, module, &method->func, method->pos);
  }
}

/* Owns the recursion rule of lint.h: MSL112, a function that calls itself on every path, since no `return`, `?` or
 * fault leaves it before the recursive call. Port of crates/ms-tooling/src/lint/recursion.rs. */
#include "base/message.h"
#include "tooling/lint.h"

/* How control leaves a block. */
typedef enum Outcome {
  OUTCOME_RECURSED,  /* every path reaches the recursive call first */
  OUTCOME_ESCAPED,   /* some path returns, propagates an error or faults without recursing */
  OUTCOME_CONTINUES  /* control reaches the end of the block */
} Outcome;

typedef struct Scan {
  const MsCheckProgram *program;
  const MsModuleInfo *module;
  uint32_t module_index;
  const MsDecl *own;
} Scan;

static Outcome block(const Scan *scan, MsStmts stmts);
static Outcome value(const Scan *scan, const MsExpr *expr, bool returned);

/* Calls `visit` on `expr` and the subexpressions that are always evaluated: not the right side of `and`/`or`, a
 * lambda body, or a match arm. */
typedef void (*Visit)(void *context, const MsExpr *expr);

static void visit_always(const MsExpr *expr, Visit visit, void *context) {
  visit(context, expr);
  switch ((MsExprKind)expr->kind) {
  case MS_E_MEMBER:
    visit_always(expr->u.member.left, visit, context);
    break;
  case MS_E_APPLY:
    visit_always(expr->u.apply.left, visit, context);
    if (expr->u.apply.value != NULL) {
      visit_always(expr->u.apply.value, visit, context);
    }
    break;
  case MS_E_INDEX:
    visit_always(expr->u.bin.left, visit, context);
    visit_always(expr->u.bin.right, visit, context);
    break;
  case MS_E_LIST:
    for (uint32_t i = 0; i < expr->u.list.len; i++) {
      visit_always(expr->u.list.ptr[i], visit, context);
    }
    break;
  case MS_E_MAP:
    for (uint32_t i = 0; i < expr->u.map.len; i++) {
      visit_always(expr->u.map.ptr[i].key, visit, context);
      visit_always(expr->u.map.ptr[i].value, visit, context);
    }
    break;
  case MS_E_TEXT:
    for (uint32_t i = 0; i < expr->u.text.len; i++) {
      if (expr->u.text.ptr[i].expr != NULL) {
        visit_always(expr->u.text.ptr[i].expr, visit, context);
      }
    }
    break;
  case MS_E_UNARY:
    visit_always(expr->u.bin.left, visit, context);
    break;
  case MS_E_BINARY:
    visit_always(expr->u.bin.left, visit, context);
    if (expr->op != MS_B_AND && expr->op != MS_B_OR) {
      visit_always(expr->u.bin.right, visit, context);
    }
    break;
  case MS_E_CALL:
    visit_always(expr->u.call.callee, visit, context);
    for (uint32_t i = 0; i < expr->u.call.args.len; i++) {
      visit_always(expr->u.call.args.ptr[i].value, visit, context);
    }
    break;
  case MS_E_MATCH:
    visit_always(expr->u.match.scrutinee, visit, context);
    break;
  case MS_E_NUMBER:
  case MS_E_BOOL:
  case MS_E_VOID:
  case MS_E_NAME:
  case MS_E_PROBE:
  case MS_E_LAMBDA:
    break;
  }
}

typedef struct Found {
  const Scan *scan;
  bool found;
} Found;

static void note_exit(void *context, const MsExpr *expr) {
  Found *state = context;
  if (expr->kind == MS_E_UNARY && expr->op == MS_U_TRY) {
    state->found = true;
  }
  if (expr->kind == MS_E_CALL) {
    const MsTy ty = ms_facts_type(&state->scan->module->facts, expr->id);
    state->found = state->found || (ty != MS_TY_NONE && ms_ty_is(&state->scan->program->types, ty, MS_BUILTIN_Never));
  }
}

static void note_call(void *context, const MsExpr *expr) {
  Found *state = context;
  if (expr->kind != MS_E_CALL) {
    return;
  }
  const MsRef *ref = ms_facts_ref(&state->scan->module->facts, expr->u.call.callee->id);
  if (ref != NULL && ref->kind == MS_REF_FUNCTION && ref->decl.module == state->scan->module_index &&
      ref->decl.node == state->scan->own->id) {
    state->found = true;
  }
}

/* Whether evaluating `expr` can leave the function without returning normally: a `?`, or a call that never completes. */
static bool exits(const Scan *scan, const MsExpr *expr) {
  Found state = {scan, false};
  visit_always(expr, note_exit, &state);
  return state.found;
}

/* Whether evaluating `expr` unconditionally calls this function. */
static bool reaches_call(const Scan *scan, const MsExpr *expr) {
  Found state = {scan, false};
  visit_always(expr, note_call, &state);
  return state.found;
}

/* Branches taken one at a time: any exit is an exit, all recursing is recursing. */
static Outcome branches(const Outcome *outcomes, size_t count) {
  bool all_recursed = true;
  for (size_t i = 0; i < count; i++) {
    if (outcomes[i] == OUTCOME_ESCAPED) {
      return OUTCOME_ESCAPED;
    }
    all_recursed = all_recursed && outcomes[i] == OUTCOME_RECURSED;
  }
  return all_recursed ? OUTCOME_RECURSED : OUTCOME_CONTINUES;
}

static Outcome arm(const Scan *scan, const MsArm *arm_node, bool returned) {
  const Outcome body = block(scan, arm_node->body);
  if (body != OUTCOME_CONTINUES) {
    return body;
  }
  if (arm_node->value != NULL) {
    return value(scan, arm_node->value, returned);
  }
  return returned ? OUTCOME_ESCAPED : OUTCOME_CONTINUES;
}

/* The outcome of evaluating `expr`; `returned` when its value is the function's result. */
static Outcome value(const Scan *scan, const MsExpr *expr, bool returned) {
  if (exits(scan, expr)) {
    return OUTCOME_ESCAPED;
  }
  if (expr->kind == MS_E_MATCH) {
    if (reaches_call(scan, expr->u.match.scrutinee)) {
      return OUTCOME_RECURSED;
    }
    Outcome outcomes[64];
    const uint32_t count = expr->u.match.arms.len < 64 ? expr->u.match.arms.len : 64;
    for (uint32_t i = 0; i < count; i++) {
      outcomes[i] = arm(scan, expr->u.match.arms.ptr[i], returned);
    }
    return branches(outcomes, count);
  }
  if (reaches_call(scan, expr)) {
    return OUTCOME_RECURSED;
  }
  return returned ? OUTCOME_ESCAPED : OUTCOME_CONTINUES;
}

/* A loop may run zero times, so only an exit inside it counts. */
static Outcome looped(const Scan *scan, const MsExpr *head, MsStmts body) {
  const Outcome outcome = value(scan, head, false);
  if (outcome == OUTCOME_CONTINUES && block(scan, body) == OUTCOME_ESCAPED) {
    return OUTCOME_ESCAPED;
  }
  return outcome;
}

static Outcome stmt(const Scan *scan, const MsStmt *node) {
  switch ((MsStmtKind)node->kind) {
  case MS_S_RETURN:
    return node->u.expr == NULL ? OUTCOME_ESCAPED : value(scan, node->u.expr, true);
  case MS_S_BIND:
    return value(scan, node->u.bind.value, false);
  case MS_S_ASSIGN:
    return value(scan, node->u.assign.value, false);
  case MS_S_CALL:
    return value(scan, node->u.expr, false);
  case MS_S_BREAK:
  case MS_S_CONTINUE:
    return OUTCOME_CONTINUES;
  case MS_S_IF: {
    const Outcome cond = value(scan, node->u.branch.cond, false);
    if (cond != OUTCOME_CONTINUES) {
      return cond;
    }
    const Outcome both[2] = {block(scan, node->u.branch.body), block(scan, node->u.branch.else_body)};
    return branches(both, 2);
  }
  case MS_S_WHILE:
    return looped(scan, node->u.loop.cond, node->u.loop.body);
  case MS_S_FOR:
    return looped(scan, node->u.each.iter, node->u.each.body);
  }
  return OUTCOME_CONTINUES;
}

static Outcome block(const Scan *scan, MsStmts stmts) {
  for (uint32_t i = 0; i < stmts.len; i++) {
    const Outcome outcome = stmt(scan, stmts.ptr[i]);
    if (outcome != OUTCOME_CONTINUES) {
      return outcome;
    }
  }
  return OUTCOME_CONTINUES;
}

void ms_lint_recursion(MsArena *arena, const MsCheckProgram *program, uint32_t module_index,
                       MsLintFindingList *findings) {
  const MsModuleInfo *module = &program->modules.ptr[module_index];
  if (module->tree == NULL) {
    return;
  }
  const MsSpan file = ms_names_span(program->names, module->file);
  for (uint32_t i = 0; i < module->tree->ndecls; i++) {
    const MsDecl *decl = module->tree->decls[i];
    if (decl->kind != MS_D_FN || decl->u.fn.external || decl->u.fn.body.len == 0) {
      continue;
    }
    const Scan scan = {program, module, module_index, decl};
    if (block(&scan, decl->u.fn.body) == OUTCOME_RECURSED) {
      ms_lint_add(findings, "MSL112", file, decl->pos,
                  ms_message_format(arena,
                                    "%S calls itself on every path, so it never returns; add a base case that returns "
                                    "before the recursive call",
                                    ms_names_span(program->names, decl->u.fn.name), (MsSpan){0}));
    }
  }
}

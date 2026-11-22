/* Owns the promise rules of lint.h: a `while true` loop that never waits (MSL111) and a promise dropped the moment
 * it is made (MSL115). Port of crates/ms-tooling/src/lint/tasks.rs and promises.rs. */
#include "base/message.h"
#include "compiler/syntax/walk.h"
#include "tooling/lint.h"

typedef struct Scan {
  MsArena *arena;
  const MsCheckProgram *program;
  const MsModuleInfo *module;
  MsSpan file;
  MsLintFindingList *findings;
  bool loops;            /* the module imports promises, so loops are checked */
  bool may_wait_or_exit; /* while scanning a loop body */
} Scan;

/* A call that runs to completion without waiting: a constructor, or a method of a primitive or a core collection. */
static bool local_call(const Scan *scan, const MsExpr *call) {
  const MsFacts *facts = &scan->module->facts;
  const MsCall *fact = ms_facts_call(facts, call->id);
  if (fact != NULL && (fact->callee.kind == MS_REF_TYPE || fact->callee.kind == MS_REF_CASE)) {
    return true;
  }
  const MsExpr *callee = call->u.call.callee;
  if (callee->kind != MS_E_MEMBER) {
    return false;
  }
  const MsTy ty = ms_facts_type(facts, callee->u.member.left->id);
  if (ty == MS_TY_NONE) {
    return false;
  }
  const MsTyTable *types = &scan->program->types;
  if (ms_ty_kind(types, ty) == MS_TY_PRIMITIVE) {
    return true;
  }
  const MsBuiltin core[] = {MS_BUILTIN_List, MS_BUILTIN_Map, MS_BUILTIN_Set, MS_BUILTIN_Optional, MS_BUILTIN_Result,
                            MS_BUILTIN_Bytes};
  for (size_t i = 0; i < sizeof core / sizeof core[0]; i++) {
    if (ms_ty_is(types, ty, core[i])) {
      return true;
    }
  }
  return false;
}

static void body_stmt(void *context, const MsStmt *stmt) {
  Scan *scan = context;
  if (stmt->kind == MS_S_BREAK || stmt->kind == MS_S_RETURN) {
    scan->may_wait_or_exit = true;
  }
}

static void body_expr(void *context, const MsExpr *expr) {
  Scan *scan = context;
  if ((expr->kind == MS_E_CALL && !local_call(scan, expr)) || expr->kind == MS_E_LAMBDA ||
      expr->kind == MS_E_MATCH) {
    scan->may_wait_or_exit = true;
  }
}

static bool is_promise(const Scan *scan, const MsExpr *expr) {
  const MsTy ty = ms_facts_type(&scan->module->facts, expr->id);
  return ty != MS_TY_NONE && ms_ty_is(&scan->program->types, ty, MS_BUILTIN_Promise);
}

static void report_dropped(Scan *scan, const MsExpr *expr, const MsStmt *statement, bool allow_fix) {
  MsLintFinding *found = ms_lint_add(
      scan->findings, "MSL115", scan->file, expr->pos,
      ms_span_of_text("This promise is dropped as soon as it is made, which cancels it; bind it and call wait() on it, "
                      "or pass it to wait_all"));
  if (!allow_fix || expr->kind != MS_E_CALL) {
    return;
  }
  /* A call that used to wait for its result and ignored it: wait for it, still ignoring the result. */
  found->has_fix = true;
  if (statement != NULL) {
    const MsSpan source = scan->module->source;
    if (statement->pos.offset > expr->end.offset || expr->end.offset > source.len) {
      found->has_fix = false;
      return;
    }
    const MsSpan text = ms_span_of(source.ptr + statement->pos.offset, expr->end.offset - statement->pos.offset);
    found->fix_pos = statement->pos;
    found->fix_end = expr->end;
    found->replacement = ms_message_format(scan->arena, "void %S | .wait()", text);
  } else {
    found->fix_pos = expr->end;
    found->fix_end = expr->end;
    found->replacement = ms_span_of_text(" | .wait()");
  }
}

static void scan_stmt(void *context, const MsStmt *stmt) {
  Scan *scan = context;
  if (stmt->kind == MS_S_CALL && is_promise(scan, stmt->u.expr)) {
    report_dropped(scan, stmt->u.expr, stmt, true);
  } else if (stmt->kind == MS_S_BIND && stmt->u.bind.pattern->kind == MS_P_NAME &&
             ms_span_is_text(ms_names_span(scan->program->names, stmt->u.bind.pattern->u.name), "_") &&
             is_promise(scan, stmt->u.bind.value)) {
    /* Waiting changes Promise to Result; retain an explicit annotation. */
    report_dropped(scan, stmt->u.bind.value, NULL, stmt->u.bind.ty == NULL);
  }
  const bool forever = stmt->kind == MS_S_WHILE && stmt->u.loop.cond->kind == MS_E_BOOL && stmt->u.loop.cond->u.flag;
  if (forever && scan->loops) {
    const MsVisitor body = {.ctx = scan, .stmt = body_stmt, .expr = body_expr};
    ms_walk_block(&body, stmt->u.loop.body);
    if (!scan->may_wait_or_exit) {
      ms_lint_add(scan->findings, "MSL111", scan->file, stmt->u.loop.cond->pos,
                  ms_span_of_text("This loop never waits or exits, so other tasks cannot run and a timeout cannot "
                                  "stop it; wait inside the loop (sleep, or wait on a promise or a pipe), or return"));
    }
    scan->may_wait_or_exit = false;
  }
}

static bool imports_promises(const MsModule *tree) {
  for (uint32_t i = 0; i < tree->nimports; i++) {
    if (ms_span_ends_with(tree->imports[i].path, ms_span_of_text("promise.ms"))) {
      return true;
    }
  }
  return false;
}

void ms_lint_promises(MsArena *arena, const MsCheckProgram *program, uint32_t module_index,
                      MsLintFindingList *findings) {
  const MsModuleInfo *module = &program->modules.ptr[module_index];
  if (module->tree == NULL) {
    return;
  }
  Scan scan = {arena, program, module, ms_names_span(program->names, module->file), findings, imports_promises(module->tree), false};
  const MsVisitor visitor = {.ctx = &scan, .stmt = scan_stmt};
  for (uint32_t i = 0; i < module->tree->ndecls; i++) {
    ms_walk_decl(&visitor, module->tree->decls[i]);
  }
}

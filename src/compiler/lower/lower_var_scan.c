/* compiler/lower/lower_var_scan.c: what a function body does to a local after its declaration, for the binding rules of lower_stmt.c. */
#include "compiler/syntax/walk.h"
#include "compiler/lower/lower_fn.h"
#include "compiler/own/result_borrows.h"

/* Whether a `var` is ever given a value that is not a borrowing call's result (`found = own.clone()`, `found += "!"`): it then
 * owns what it holds, so a view bound at its declaration is copied there. */
typedef struct OwnedStores {
  const LowerFn *fn;
  uint32_t local;
  bool found;
} OwnedStores;

static void note_owned_store(void *ctx, const MsStmt *stmt) {
  OwnedStores *scan = ctx;
  if (stmt->kind != MS_S_ASSIGN || scan->found || stmt->u.assign.member_target) {
    return;
  }
  const MsRef *ref = ms_facts_ref(scan->fn->facts, stmt->u.assign.target != NULL ? stmt->u.assign.target->id : stmt->id);
  if (ref == NULL || ref->kind != MS_REF_LOCAL || ref->local != scan->local) {
    return;
  }
  const MsExpr *stored = stmt->u.assign.value;
  const MsCall *called = stored != NULL && stored->kind == MS_E_CALL && !stmt->u.assign.has_compound ? ms_facts_call(scan->fn->facts, stored->id) : NULL;
  scan->found = called == NULL || (called->callee.kind != MS_REF_FUNCTION && called->callee.kind != MS_REF_METHOD) ||
                !ms_own_result_is_borrowed(scan->fn->cx->program, called->callee.decl.module, called->callee.decl.node);
}

bool fn_var_stores_owned(const LowerFn *fn, uint32_t local) {
  OwnedStores scan = {.fn = fn, .local = local};
  const MsVisitor visitor = {.ctx = &scan, .stmt = note_owned_store};
  if (fn->func != NULL) {
    ms_walk_block(&visitor, fn->func->body);
  } else if (fn->lambda != NULL) {
    ms_walk_block(&visitor, fn->lambda->expr->u.lambda.body);
  }
  return scan.found;
}

/* Whether the local is assigned after `after` in the function's text: a name that took the local's value by a last-use move
 * must not read a later assignment. */
typedef struct LaterStores {
  const LowerFn *fn;
  uint32_t local;
  MsPos after;
  bool found;
} LaterStores;

static void note_later_store(void *ctx, const MsStmt *stmt) {
  LaterStores *scan = ctx;
  if (stmt->kind != MS_S_ASSIGN || scan->found || stmt->u.assign.member_target) {
    return;
  }
  const MsRef *ref = ms_facts_ref(scan->fn->facts, stmt->u.assign.target != NULL ? stmt->u.assign.target->id : stmt->id);
  const bool later = stmt->pos.line > scan->after.line || (stmt->pos.line == scan->after.line && stmt->pos.column > scan->after.column);
  scan->found = ref != NULL && ref->kind == MS_REF_LOCAL && ref->local == scan->local && later;
}

bool fn_stored_after(const LowerFn *fn, uint32_t local, MsPos after) {
  LaterStores scan = {.fn = fn, .local = local, .after = after};
  const MsVisitor visitor = {.ctx = &scan, .stmt = note_later_store};
  if (fn->func != NULL) {
    ms_walk_block(&visitor, fn->func->body);
  } else if (fn->lambda != NULL) {
    ms_walk_block(&visitor, fn->lambda->expr->u.lambda.body);
  }
  return scan.found;
}


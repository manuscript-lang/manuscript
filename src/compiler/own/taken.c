/* compiler/own/taken.c: see taken.h. */
#include "compiler/own/taken.h"

#include "compiler/check/properties.h"
#include "compiler/syntax/walk.h"

typedef struct Scan {
  const MsFacts *facts;
  uint32_t local;
  bool found;
} Scan;

static bool names_param(const Scan *scan, const MsExpr *expr) {
  const MsRef *ref = expr != NULL && expr->kind == MS_E_NAME ? ms_facts_ref(scan->facts, expr->id) : NULL;
  return ref != NULL && ref->kind == MS_REF_PARAM && ref->local == scan->local;
}

static void scan_expr(void *ctx, const MsExpr *expr) {
  Scan *scan = ctx;
  scan->found |= names_param(scan, expr) && ms_facts_use(scan->facts, expr->id) == MS_USE_MOVE;
}

/* A parameter bound to a name or assigned is handed on, though a plain bind only borrows it in the source. */
static void scan_stmt(void *ctx, const MsStmt *stmt) {
  Scan *scan = ctx;
  const MsExpr *value = stmt->kind == MS_S_BIND ? stmt->u.bind.value : stmt->kind == MS_S_ASSIGN ? stmt->u.assign.value : NULL;
  scan->found |= names_param(scan, value);
}

static uint32_t mask_of(MsCheckProgram *program, const MsFacts *facts, MsParams params, MsStmts body) {
  uint32_t mask = 0;
  for (uint32_t index = 0; index < params.len && index < 32; index++) {
    const MsParam *param = params.ptr[index];
    const MsRef *ref = ms_facts_ref(facts, param->id);
    const MsTy ty = ms_facts_type(facts, param->id);
    if (param->moving || ref == NULL || ref->kind != MS_REF_PARAM || ty == MS_TY_NONE ||
        !ms_check_holds_resource(program, ty)) {
      continue;
    }
    Scan scan = {facts, ref->local, false};
    const MsVisitor visitor = {.ctx = &scan, .stmt = scan_stmt, .expr = scan_expr};
    ms_walk_callable(&visitor, params, body);
    mask |= scan.found ? 1u << index : 0;
  }
  return mask;
}

static bool set(MsFacts *facts, MsNode node, uint32_t mask) {
  const bool changed = node < facts->node_count && facts->taken[node] != mask;
  if (node < facts->node_count) {
    facts->taken[node] = mask;
  }
  return changed;
}

bool ms_own_taken(MsCheckProgram *program) {
  bool changed = false;
  for (uint32_t module = 0; module < program->modules.len; module++) {
    MsFacts *facts = &program->modules.ptr[module].facts;
    const MsModule *tree = program->modules.ptr[module].tree;
    for (uint32_t index = 0; facts->taken != NULL && index < tree->ndecls; index++) {
      const MsDecl *decl = tree->decls[index];
      if (decl->kind == MS_D_FN) {
        changed |= set(facts, decl->id, mask_of(program, facts, decl->u.fn.params, decl->u.fn.body));
      }
      for (uint32_t at = 0; decl->kind == MS_D_IMPL && at < decl->u.impl.methods.len; at++) {
        const MsMethod *method = decl->u.impl.methods.ptr[at];
        changed |= set(facts, method->id, mask_of(program, facts, method->func.params, method->func.body));
      }
    }
  }
  return changed;
}

uint32_t ms_own_taken_mask(const MsCheckProgram *program, uint32_t module, MsNode node) {
  if (module >= program->modules.len) {
    return 0;
  }
  const MsFacts *facts = &program->modules.ptr[module].facts;
  return facts->taken != NULL && node < facts->node_count ? facts->taken[node] : 0;
}

bool ms_own_call_takes(const MsCheckProgram *program, const MsCall *call, uint32_t index) {
  const bool method = call->callee.kind == MS_REF_METHOD;
  if ((call->callee.kind != MS_REF_FUNCTION && !method) || index >= 32 + 1 || (method && index == 0)) {
    return false;
  }
  const uint32_t position = method ? index - 1 : index;
  return (ms_own_taken_mask(program, call->callee.decl.module, call->callee.decl.node) >> position & 1u) != 0;
}

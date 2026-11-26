/* compiler/own/taken.c: see taken.h. */
#include "compiler/own/taken.h"

#include "compiler/check/properties.h"
#include "compiler/own/result_borrows.h"
#include "compiler/syntax/walk.h"

typedef struct Scan {
  const MsFacts *facts;
  MsNode param; /* the declaration of the parameter: a closure's own parameter may share its position */
  bool found;
} Scan;

static bool names_param(const Scan *scan, const MsExpr *expr) {
  const MsRef *ref = expr != NULL && expr->kind == MS_E_NAME ? ms_facts_ref(scan->facts, expr->id) : NULL;
  return ref != NULL && ref->kind == MS_REF_PARAM && ref->decl.node == scan->param;
}

/* The parameter at the root of a field path: `param`, `param.a`, `param.a.b`. */
static bool roots_at_param(const Scan *scan, const MsExpr *expr) {
  while (expr != NULL && expr->kind == MS_E_MEMBER) {
    expr = expr->u.member.left;
  }
  return names_param(scan, expr);
}

static void scan_payload(void *ctx, const MsExpr *expr);

static void scan_expr(void *ctx, const MsExpr *expr) {
  Scan *scan = ctx;
  scan->found |= names_param(scan, expr) && ms_facts_use(scan->facts, expr->id) == MS_USE_MOVE;
  /* A field of the parameter handed to a consumer that takes it leaves the parameter: the caller's argument moves in. */
  scan->found |= expr->kind == MS_E_MEMBER && ms_facts_use(scan->facts, expr->id) == MS_USE_MOVE && roots_at_param(scan, expr->u.member.left);
  scan_payload(ctx, expr);
}

/* `param.get()` or `param or d` handed on (the expression carries the move): the payload leaves the parameter. */
static void scan_payload(void *ctx, const MsExpr *expr) {
  Scan *scan = ctx;
  if (expr->kind == MS_E_BINARY && expr->op == MS_B_OR && ms_facts_use(scan->facts, expr->id) == MS_USE_MOVE) {
    scan->found |= names_param(scan, expr->u.bin.left);
  }
  if (expr->kind == MS_E_CALL && ms_facts_use(scan->facts, expr->id) == MS_USE_MOVE &&
      expr->u.call.callee->kind == MS_E_MEMBER) {
    scan->found |= names_param(scan, expr->u.call.callee->u.member.left);
  }
}

/* A generic parameter a constructor stores (`ok(value)`) is handed on: its type may be a resource. */
static void scan_stored(void *ctx, const MsExpr *expr) {
  Scan *scan = ctx;
  scan_payload(ctx, expr);
  if (expr->kind != MS_E_CALL) {
    return;
  }
  const MsRef *callee = ms_facts_ref(scan->facts, expr->u.call.callee->id);
  for (uint32_t index = 0; callee != NULL && (callee->kind == MS_REF_TYPE || callee->kind == MS_REF_CASE) &&
                           index < expr->u.call.args.len; index++) {
    scan->found |= names_param(scan, expr->u.call.args.ptr[index].value);
  }
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
        (ms_ty_kind(&program->types, ty) != MS_TY_VARIABLE && ms_ty_kind(&program->types, ty) != MS_TY_FUNCTION &&
         !ms_ty_has_variable(&program->types, ty) && !ms_check_holds_resource(program, ty))) {
      continue;
    }
    Scan scan = {facts, param->id, false};
    const bool generic = ms_ty_kind(&program->types, ty) == MS_TY_VARIABLE;
    /* A container of a generic payload (`T?`) is judged as a generic parameter is: by what stores or extracts it. */
    const bool open = generic || (ms_ty_has_variable(&program->types, ty) && !ms_check_holds_resource(program, ty));
    const MsVisitor visitor = {.ctx = &scan, .stmt = open ? NULL : scan_stmt, .expr = open ? scan_stored : scan_expr};
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

/* ---- report ---- */

/* A function is not an owned value, so a parameter of function type has no argument mode to write. */
static void report_function_modes(MsCheckProgram *program, uint32_t module, MsParams params) {
  for (uint32_t index = 0; index < params.len; index++) {
    const MsParam *param = params.ptr[index];
    const MsTy ty = ms_facts_type(&program->modules.ptr[module].facts, param->id);
    if ((!param->moving && !param->holding) || ty == MS_TY_NONE || ms_ty_kind(&program->types, ty) != MS_TY_FUNCTION) {
      continue;
    }
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append_text(&text, "a function is not an owned value, so `");
    ms_strbuild_append(&text, ms_names_span(program->names, param->name));
    ms_strbuild_append_text(&text, "` takes no `move` or `hold`; write the parameter as `");
    ms_strbuild_append(&text, ms_names_span(program->names, param->name));
    ms_strbuild_append_text(&text, " fn(...) Type`");
    ms_check_report(program, module, param->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  }
}

static void report_params(MsCheckProgram *program, uint32_t module, MsNode node, MsParams params, bool modes) {
  if (modes) {
    report_function_modes(program, module, params);
  }
  const uint32_t mask = ms_own_taken_mask(program, module, node);
  for (uint32_t index = 0; mask != 0 && index < params.len && index < 32; index++) {
    const MsParam *param = params.ptr[index];
    const MsTy ty = ms_facts_type(&program->modules.ptr[module].facts, param->id);
    /* A `var` parameter is the caller's own value and cannot move out; what a function-typed parameter's closure
     * holds is a separate fact (see escapes.c). */
    if (param->moving || param->is_mutable || (mask >> index & 1u) == 0 || ty == MS_TY_NONE ||
        ms_ty_kind(&program->types, ty) == MS_TY_FUNCTION) {
      continue;
    }
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append_text(&text, "the body keeps `");
    ms_strbuild_append(&text, ms_names_span(program->names, param->name));
    ms_strbuild_append_text(&text, "`, so the signature must say so: write `move ");
    ms_strbuild_append(&text, ms_names_span(program->names, param->name));
    ms_strbuild_append_text(&text, " Type`, or keep `.clone()` of it");
    ms_check_report(program, module, param->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  }
}

void ms_own_taken_report(MsCheckProgram *program) {
  for (uint32_t module = 0; module < program->modules.len; module++) {
    const MsModule *tree = program->modules.ptr[module].tree;
    for (uint32_t index = 0; index < tree->ndecls; index++) {
      const MsDecl *decl = tree->decls[index];
      if (decl->kind == MS_D_FN) {
        report_params(program, module, decl->id, decl->u.fn.params, !decl->u.fn.external);
      }
      for (uint32_t at = 0; decl->kind == MS_D_IMPL && at < decl->u.impl.methods.len; at++) {
        const MsMethod *method = decl->u.impl.methods.ptr[at];
        report_params(program, module, method->id, method->func.params, true);
      }
    }
  }
}

/* Owns the match-shape rules of lint.h: nested matches (MSL107) and two-arm matches on an Optional (MSL108) or a
 * Result (MSL109). Port of crates/ms-tooling/src/lint/matches.rs. */
#include "compiler/syntax/walk.h"
#include "tooling/lint.h"

typedef struct Scan {
  const MsCheckProgram *program;
  const MsModuleInfo *module;
  MsSpan file;
  size_t depth;
  MsLintFindingList *findings;
} Scan;

/* A written `match`, not the Bool match an `if` expression stands for. */
static bool is_written_match(const MsExpr *expr) {
  return expr->kind == MS_E_MATCH && !(expr->u.match.arms.len > 0 && expr->u.match.arms.ptr[0]->from_if);
}

/* The final written segment of an arm path: `some` for `Optional.some`. */
static MsSpan path_text(const Scan *scan, const MsExpr *path) {
  if (path->kind == MS_E_NAME) {
    return ms_names_span(scan->program->names, path->u.sym);
  }
  if (path->kind == MS_E_MEMBER) {
    return ms_names_span(scan->program->names, path->u.member.name);
  }
  return (MsSpan){0};
}

static void two_arm(Scan *scan, const MsExpr *expr) {
  const MsExpr *scrutinee = expr->u.match.scrutinee;
  if (expr->u.match.arms.len != 2) {
    return;
  }
  const MsFacts *facts = &scan->module->facts;
  const MsTy ty = ms_facts_type(facts, scrutinee->id);
  if (ty == MS_TY_NONE) {
    return;
  }
  const MsTyTable *types = &scan->program->types;
  const bool optional = ms_ty_is(types, ty, MS_BUILTIN_Optional);
  if (!optional && !ms_ty_is(types, ty, MS_BUILTIN_Result)) {
    return;
  }
  const char *first = optional ? "some" : "ok";
  const char *second = optional ? "null" : "error";
  bool has_first = false;
  bool has_second = false;
  for (uint32_t i = 0; i < 2; i++) {
    const MsArm *arm = expr->u.match.arms.ptr[i];
    const MsSpan text = arm->bare && optional ? ms_span_of_text("some") : path_text(scan, arm->path);
    has_first = has_first || ms_span_is_text(text, first);
    has_second = has_second || ms_span_is_text(text, second);
  }
  if (has_first && has_second) {
    ms_lint_add(scan->findings, optional ? "MSL108" : "MSL109", scan->file, expr->pos,
                optional ? ms_span_of_text("Matching an Optional with only a payload arm and null; use 'if value := "
                                           "...:' with 'else:', or an Optional method such as get_or(default) or map")
                         : ms_span_of_text("Matching a Result with only ok and error; use a trailing '?', 'if value "
                                           ":= ...:' with 'else:', or a Result method such as get_or(default), "
                                           "is_error, or err"));
  }
}

static void enter(void *context, const MsExpr *expr) {
  Scan *scan = context;
  if (!is_written_match(expr)) {
    return;
  }
  if (scan->depth > 0) {
    ms_lint_add(scan->findings, "MSL107", scan->file, expr->pos,
                ms_span_of_text("Nested match obscures control flow; bind the outer payload with an early exit, use "
                                "a compatible trailing '?', or call a small helper"));
  }
  scan->depth++;
  if (scan->program != NULL) {
    two_arm(scan, expr);
  }
}

static void leave(void *context, const MsExpr *expr) {
  Scan *scan = context;
  if (is_written_match(expr)) {
    scan->depth--;
  }
}

void ms_lint_matches(MsArena *arena, const MsCheckProgram *program, uint32_t module_index,
                     MsLintFindingList *findings) {
  (void)arena;
  const MsModuleInfo *module = &program->modules.ptr[module_index];
  if (module->tree == NULL) {
    return;
  }
  Scan scan = {program, module, ms_names_span(program->names, module->file), 0, findings};
  const MsVisitor visitor = {.ctx = &scan, .expr = enter, .leave_expr = leave};
  for (uint32_t i = 0; i < module->tree->ndecls; i++) {
    ms_walk_decl(&visitor, module->tree->decls[i]);
  }
}

void ms_lint_nested_matches(const MsModule *tree, MsSpan file, MsLintFindingList *findings) {
  Scan scan = {NULL, NULL, file, 0, findings};
  const MsVisitor visitor = {.ctx = &scan, .expr = enter, .leave_expr = leave};
  for (uint32_t i = 0; i < tree->ndecls; i++) {
    ms_walk_decl(&visitor, tree->decls[i]);
  }
}

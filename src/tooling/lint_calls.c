/* Owns two single-expression rules of lint.h: `Optional.get()` without a default (MSL110) and an integer literal
 * interpolated into text (MSL117). Port of crates/ms-tooling/src/lint/faults.rs and text.rs. */
#include "compiler/syntax/walk.h"
#include "base/message.h"
#include "tooling/lint.h"

typedef struct Scan {
  MsArena *arena;
  const MsCheckProgram *program;
  const MsModuleInfo *module;
  MsSpan file;
  MsLintFindingList *findings;
} Scan;

/* `x.get()` on an Optional faults when the value is absent. */
static void optional_get(Scan *scan, const MsExpr *call) {
  const MsExpr *callee = call->u.call.callee;
  if (callee->kind != MS_E_MEMBER || call->u.call.args.len != 0 ||
      !ms_span_is_text(ms_names_span(scan->program->names, callee->u.member.name), "get")) {
    return;
  }
  const MsTy ty = ms_facts_type(&scan->module->facts, callee->u.member.left->id);
  if (ty != MS_TY_NONE && ms_ty_is(&scan->program->types, ty, MS_BUILTIN_Optional)) {
    ms_lint_add(scan->findings, "MSL110", scan->file, call->pos,
                ms_span_of_text("Optional.get() without a default faults when the value is absent; use 'if value := "
                                "...:', use get_or(default), or get_or_else"));
  }
}

/* `f"\d{4}"` reads as a regex quantifier but interpolates the number 4. */
static void interpolated_number(Scan *scan, const MsExpr *text) {
  for (uint32_t i = 0; i < text->u.text.len; i++) {
    const MsExpr *inner = text->u.text.ptr[i].expr;
    if (inner == NULL || inner->kind != MS_E_NUMBER) {
      continue;
    }
    const MsSpan digits = ms_names_span(scan->program->names, inner->u.sym);
    bool plain = digits.len > 0;
    for (size_t k = 0; k < digits.len; k++) {
      plain = plain && digits.ptr[k] >= '0' && digits.ptr[k] <= '9';
    }
    if (!plain) {
      continue;
    }
    ms_lint_add(scan->findings, "MSL117", scan->file, inner->pos,
                ms_message_format(scan->arena,
                                  "`{%S}` interpolates the number %S, not a literal brace; write `\\{%S\\}` for braces "
                                  "(a regex quantifier), or use `r\"...\"` raw text",
                                  digits, digits, digits));
  }
}

static void visit(void *context, const MsExpr *expr) {
  Scan *scan = context;
  if (expr->kind == MS_E_CALL) {
    optional_get(scan, expr);
  } else if (expr->kind == MS_E_TEXT) {
    interpolated_number(scan, expr);
  }
}

void ms_lint_calls(MsArena *arena, const MsCheckProgram *program, uint32_t module_index,
                   MsLintFindingList *findings) {
  const MsModuleInfo *module = &program->modules.ptr[module_index];
  if (module->tree == NULL) {
    return;
  }
  Scan scan = {arena, program, module, ms_names_span(program->names, module->file), findings};
  const MsVisitor visitor = {.ctx = &scan, .expr = visit};
  for (uint32_t i = 0; i < module->tree->ndecls; i++) {
    ms_walk_decl(&visitor, module->tree->decls[i]);
  }
}

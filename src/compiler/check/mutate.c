/* compiler/check/mutate.c: the mutability pass.
 *
 * Walks every body with lexical scopes of bindings (parameters, `:=` and `var` bindings, pattern names, loop
 * variables, match payloads, lambda parameters) and checks the target of each assignment to a name. */
#include "compiler/check/mutate.h"
#include "compiler/check/mutate_fix.h"
#include "compiler/check/scope_walk.h"
#include "compiler/check/symbol_text.h"

typedef struct Mutate {
  MsCheckProgram *program;
  uint32_t module;
  MsSpan source;
} Mutate;

static void append_name(Mutate *pass, MsStrBuild *text, MsName name) {
  ms_strbuild_append(text, ms_names_span(pass->program->names, name));
}

/* "cannot assign immutable binding NAME; declare it with 'var NAME = ...' instead of 'NAME := ...'" */
static void report_immutable(Mutate *pass, const MsStmt *stmt, const MsBinding *binding) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "cannot assign immutable binding ");
  append_name(pass, &text, binding->name);
  ms_strbuild_append_text(&text, "; declare it with 'var ");
  append_name(pass, &text, binding->name);
  ms_strbuild_append_text(&text, " = ...' instead of '");
  append_name(pass, &text, binding->name);
  ms_strbuild_append_text(&text, " := ...'");
  MsVarFix fix = {0};
  const bool has_fix = ms_var_fix(pass->source, binding->decl, &fix);
  ms_check_report(pass->program, pass->module, stmt->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  if (has_fix) {
    ms_check_attach_fix(pass->program, fix.pos, fix.end, fix.replacement);
  }
}

static void report_not_a_binding(Mutate *pass, const MsStmt *stmt, const MsSymbol *symbol) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "cannot assign to ");
  ms_strbuild_append_text(&text, ms_symbol_description(pass->module, symbol));
  ms_strbuild_append_text(&text, " ");
  append_name(pass, &text, stmt->u.assign.name);
  ms_strbuild_append_text(&text, "; assignment targets are 'var' bindings and type fields");
  ms_check_report(pass->program, pass->module, stmt->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

static void check_assign(void *context, const MsStmt *stmt, const MsBindingList *scope, const MsScopeSite *site) {
  (void)site;
  Mutate *pass = context;
  const MsName name = stmt->u.assign.name;
  const MsBinding *binding = ms_scope_lookup(scope, name);
  if (binding != NULL) {
    if (!binding->mutable_) {
      report_immutable(pass, stmt, binding);
    }
    return;
  }
  const MsSymbolId *id = ms_scope_get(&pass->program->modules.ptr[pass->module].scope, name);
  if (id == NULL) {
    id = ms_scope_get(&pass->program->modules.ptr[pass->module].imports, name);
  }
  if (id != NULL && *id != 0) {
    report_not_a_binding(pass, stmt, &pass->program->symbols.ptr[*id]);
  }
}

void ms_check_mutation(MsCheckProgram *program, uint32_t module, MsSpan source) {
  Mutate pass = {.program = program, .module = module, .source = source};
  const MsScopeVisitor visitor = {.context = &pass, .assign = check_assign};
  ms_scope_walk_module(program->modules.ptr[module].tree, &visitor, program->names);
}

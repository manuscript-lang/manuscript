/* compiler/check/shadow.c: see shadow.h. */
#include "compiler/check/shadow.h"

#include "compiler/check/scope_walk.h"

typedef struct Shadow {
  MsCheckProgram *program;
  uint32_t module;
} Shadow;

static bool may_reuse(MsSpan text) {
  return (text.len != 0 && text.ptr[0] == '_') || ms_span_is_text(text, "self");
}

static void declared(void *context, const MsBinding *binding, const MsBindingList *scope) {
  Shadow *pass = context;
  const MsSpan name = ms_names_span(pass->program->names, binding->name);
  if (may_reuse(name)) {
    return;
  }
  bool outer = false;
  for (size_t index = 0; index + 1 < scope->len && !outer; index++) {
    outer = scope->ptr[index].name == binding->name && scope->ptr[index].depth < binding->depth;
  }
  if (!outer) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "binding ");
  ms_strbuild_append(&text, name);
  ms_strbuild_append_text(&text, " shadows an outer binding of the same name; rename one of them, or assign to the "
                                 "outer 'var'");
  ms_check_report(pass->program, pass->module, binding->decl, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  pass->program->diagnostics.ptr[pass->program->diagnostics.len - 1].anchor = binding->anchor;
}

/* The lone name of an arm may be a variant: some declared enum has a variant of that name. */
static bool variant_name(void *context, MsName name) {
  const Shadow *pass = context;
  const MsDefs *defs = &pass->program->defs;
  for (size_t index = 1; index < defs->count; index++) {
    const MsDef *def = ms_defs_get(defs, (uint32_t)index);
    for (size_t at = 0; at < def->cases.len; at++) {
      if (def->cases.ptr[at].name == name) {
        return true;
      }
    }
  }
  return false;
}

void ms_check_shadowing(MsCheckProgram *program, uint32_t module) {
  Shadow pass = {.program = program, .module = module};
  const MsScopeVisitor visitor = {.context = &pass, .declared = declared, .variant_name = variant_name};
  ms_scope_walk_module(program->modules.ptr[module].tree, &visitor, program->names);
}

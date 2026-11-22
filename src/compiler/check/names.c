/* compiler/check/names.c: the name-resolution pass over function bodies (see names.h). */
#include "compiler/check/names.h"

#include "compiler/check/names_hint.h"

typedef struct Names {
  MsCheckProgram *program;
  uint32_t module;
} Names;

static const char *const ALWAYS_KNOWN[] = {"..", "_", "self",     "fixture",  "print",     "__LINE__", "__FILE__", "Equal",
                                           "Stringable", "Comparable", "Hashable", "Clonable", "Optional",
                                           "Result",   "Error",    "List",      "Map",      "Set",
                                           "ListEntry", "MapEntry"};

static bool always_known(MsSpan text) {
  for (size_t index = 0; index < MS_COUNT_OF(ALWAYS_KNOWN); index++) {
    if (ms_span_is_text(text, ALWAYS_KNOWN[index])) {
      return true;
    }
  }
  return false;
}

/* Whether any enum of any loaded module has a case called `name` (a case is written without its type). */
bool ms_check_is_case_name(const MsCheckProgram *program, MsName name) {
  for (size_t module = 0; module < program->modules.len; module++) {
    const MsModule *tree = program->modules.ptr[module].tree;
    for (uint32_t index = 0; index < tree->ndecls; index++) {
      const MsDecl *decl = tree->decls[index];
      if (decl->kind != MS_D_ENUM) {
        continue;
      }
      for (uint32_t at = 0; at < decl->u.enumeration.cases.len; at++) {
        if (decl->u.enumeration.cases.ptr[at]->name == name) {
          return true;
        }
      }
    }
  }
  return false;
}

static bool is_declared(const Names *pass, MsName name) {
  const MsModuleInfo *info = &pass->program->modules.ptr[pass->module];
  const MsSymbolId *imported = ms_scope_get(&info->imports, name);
  return ms_scope_has(&info->scope, name) || (imported != NULL && *imported != 0); /* a name whose import failed is unknown */
}

static void read_name(void *context, const MsExpr *expr, const MsBindingList *scope, const MsScopeSite *site) {
  const Names *pass = context;
  if (site->in_constant_call || site->type_reading) {
    return;
  }
  const MsName name = expr->u.sym;
  const MsSpan text = ms_names_span(pass->program->names, name);
  if (ms_scope_lookup(scope, name) != NULL || is_declared(pass, name) || always_known(text) || ms_builtin_primitive(text) != MS_BUILTIN_NONE ||
      ms_check_is_case_name(pass->program, name)) {
    return;
  }
  ms_unknown_name_report(pass->program, pass->module, expr->pos, name, scope, site);
}

/* A parameter whose written type already failed to resolve: a diagnostic sits at the type. */
static bool has_broken_type(void *context, const MsParam *param) {
  const Names *pass = context;
  if (param->ty == NULL) {
    return false;
  }
  for (size_t index = 0; index < pass->program->diagnostics.len; index++) {
    const MsCheckDiag *diag = &pass->program->diagnostics.ptr[index];
    if (diag->module == pass->module && diag->phase == MS_CHECK_RESOLUTION &&
        diag->pos.offset == param->ty->pos.offset) {
      return true;
    }
  }
  return false;
}

void ms_check_names(MsCheckProgram *program, uint32_t module) {
  Names pass = {.program = program, .module = module};
  const MsScopeVisitor visitor = {.context = &pass, .name = read_name, .invalid_param = has_broken_type};
  ms_scope_walk_module(program->modules.ptr[module].tree, &visitor, program->names);
}

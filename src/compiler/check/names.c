/* compiler/check/names.c: the name-resolution pass over function bodies (see names.h). */
#include "abi/prelude.h"
#include "compiler/check/names.h"

#include "compiler/check/names_hint.h"

typedef struct Names {
  MsCheckProgram *program;
  uint32_t module;
  const MsExpr *unknown; /* the last name read that was reported unknown */
} Names;

static bool always_known(MsSpan text) {
  static const char *const SPECIAL[] = {"..", "_", "self", "fixture", "print", "ok_or", "__LINE__", "__FILE__"};
  for (size_t index = 0; index < MS_COUNT_OF(SPECIAL); index++) {
    if (ms_span_is_text(text, SPECIAL[index])) {
      return true;
    }
  }
  return ms_is_prelude_type(text);
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
      ms_check_is_case_name(pass->program, name) || (site->impl != NULL && ms_span_is_text(text, "Self"))) {
    return;
  }
  /* A compound assignment's target is read again in its desugared value; the name is reported once. */
  const MsCheckDiagList *lists[2] = {&pass->program->diagnostics, &pass->program->deferred};
  for (size_t at = 0; at < 2; at++) {
    for (size_t index = 0; index < lists[at]->len; index++) {
      const MsCheckDiag *diag = &lists[at]->ptr[index];
      if (diag->module == pass->module && diag->pos.offset == expr->pos.offset && diag->phase == MS_CHECK_RESOLUTION) {
        ((Names *)context)->unknown = expr;
        return;
      }
    }
  }
  ms_unknown_name_report(pass->program, pass->module, expr->pos, name, scope, site);
  ((Names *)context)->unknown = expr;
}

/* An assignment to a plain name that nothing declares: the same report as reading it. */
static void assign_name(void *context, const MsStmt *stmt, const MsBindingList *scope, const MsScopeSite *site) {
  const Names *pass = context;
  const MsName name = stmt->u.assign.name;
  if (site->in_constant_call || ms_scope_lookup(scope, name) != NULL || is_declared(pass, name)) {
    return;
  }
  ms_unknown_name_report(pass->program, pass->module, stmt->pos, name, scope, site);
}

static bool was_reported(void *context, const MsExpr *expr) {
  return ((const Names *)context)->unknown == expr;
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
  const MsScopeVisitor visitor = {.context = &pass, .name = read_name, .assign = assign_name, .invalid_param = has_broken_type, .unknown = was_reported};
  ms_scope_walk_module(program->modules.ptr[module].tree, &visitor, program->names);
}

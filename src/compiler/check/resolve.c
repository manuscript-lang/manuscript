/* compiler/check/resolve.c: the type-name pass over declaration signatures.
 *
 * Finds each written type name (a field, case payload, parameter, result, alias target, constant type or
 * bound) and reports `unknown type` when no scope gives it a meaning. A type name is known when it is a
 * primitive, a prelude type, a type or alias declared in the module, a name the module imports (its kind is
 * the standard library's to confirm), or a type parameter in scope. Qualified names (`mod.Type`) are not
 * resolved here. Function bodies are not walked yet. */
#include "compiler/check/program.h"

MS_LIST_DEFINE(MsScopeNames, ms_scope_names, MsName)

typedef struct Resolver {
  MsCheckProgram *program;
  uint32_t module;
  MsScopeNames variables; /* owned: the type parameters in scope */
} Resolver;

static const char *const PRELUDE_TYPES[] = {"Equal", "Stringable", "Comparable", "Hashable", "Clonable",
                                            "Optional", "Result", "Error", "List", "Map", "Set",
                                            "ListEntry", "MapEntry"};

static bool in_variables(const Resolver *resolver, MsName name) {
  for (size_t index = 0; index < resolver->variables.len; index++) {
    if (resolver->variables.ptr[index] == name) {
      return true;
    }
  }
  return false;
}

/* An imported name is a type unless it bound to a function; one that did not resolve is not reported twice. */
static bool is_imported_type(const Resolver *resolver, MsName name) {
  const MsCheckProgram *program = resolver->program;
  const MsSymbolId *id = ms_scope_get(&program->modules.ptr[resolver->module].imports, name);
  return id != NULL && (*id == 0 || program->symbols.ptr[*id].kind != MS_SYMBOL_FN);
}

static bool is_declared_type(const Resolver *resolver, MsName name) {
  const MsCheckProgram *program = resolver->program;
  const MsSymbolId *id = ms_scope_get(&program->modules.ptr[resolver->module].scope, name);
  return id != NULL && program->symbols.ptr[*id].kind != MS_SYMBOL_FN;
}

static bool is_prelude_type(MsSpan text) {
  for (size_t index = 0; index < MS_COUNT_OF(PRELUDE_TYPES); index++) {
    if (ms_span_is_text(text, PRELUDE_TYPES[index])) {
      return true;
    }
  }
  return false;
}

static bool is_known(const Resolver *resolver, MsName name) {
  const MsSpan text = ms_names_span(resolver->program->names, name);
  size_t dot = 0;
  return ms_span_find(text, ms_span_of_text("."), &dot) || ms_span_is_text(text, "Self") ||
         ms_builtin_primitive(text) != MS_BUILTIN_NONE || is_prelude_type(text) ||
         in_variables(resolver, name) || is_imported_type(resolver, name) || is_declared_type(resolver, name);
}

static void report_unknown(Resolver *resolver, const MsTypeRef *type) {
  MsStrBuild text = ms_strbuild_new();
  const MsSpan name = ms_names_span(resolver->program->names, type->name);
  ms_strbuild_append_text(&text, "unknown type ");
  ms_strbuild_append(&text, name);
  ms_strbuild_append_text(&text, "; declare it with 'type ");
  ms_strbuild_append(&text, name);
  ms_strbuild_append_text(&text, ":' / 'enum ");
  ms_strbuild_append(&text, name);
  ms_strbuild_append_text(&text, ":' / 'interface ");
  ms_strbuild_append(&text, name);
  ms_strbuild_append_text(&text, ":', declare it as a type parameter, or import it");
  ms_check_report(resolver->program, resolver->module, type->pos, MS_CHECK_RESOLUTION,
                  ms_strbuild_finish(&text));
}

static void walk_type(Resolver *resolver, const MsTypeRef *type);

static void walk_params(Resolver *resolver, MsParams params) {
  for (uint32_t index = 0; index < params.len; index++) {
    if (params.ptr[index]->ty != NULL) {
      walk_type(resolver, params.ptr[index]->ty);
    }
  }
}

static void walk_type(Resolver *resolver, const MsTypeRef *type) {
  if (type->kind == MS_TYPE_FN) {
    walk_params(resolver, type->params);
    walk_type(resolver, type->result);
    return;
  }
  if (!is_known(resolver, type->name)) {
    report_unknown(resolver, type);
  }
  for (uint32_t index = 0; index < type->args.len; index++) {
    walk_type(resolver, type->args.ptr[index]);
  }
}

/* Brings the declared type parameters into scope and walks their bounds and defaults. */
static void enter_type_params(Resolver *resolver, MsTypeParams params) {
  for (uint32_t index = 0; index < params.len; index++) {
    ms_scope_names_push(&resolver->variables, params.ptr[index]->name);
  }
  for (uint32_t index = 0; index < params.len; index++) {
    for (uint32_t bound = 0; bound < params.ptr[index]->bounds.len; bound++) {
      walk_type(resolver, params.ptr[index]->bounds.ptr[bound]);
    }
    if (params.ptr[index]->def != NULL) {
      walk_type(resolver, params.ptr[index]->def);
    }
  }
}

static void walk_function(Resolver *resolver, const MsFunc *func) {
  const size_t mark = resolver->variables.len;
  enter_type_params(resolver, func->type_params);
  walk_params(resolver, func->params);
  if (func->result != NULL) {
    walk_type(resolver, func->result);
  }
  ms_scope_names_truncate(&resolver->variables, mark);
}

/* A method's receiver arguments declare its type variables (`fn Stack[T].push`). */
static void walk_method(Resolver *resolver, const MsMethod *method) {
  const size_t mark = resolver->variables.len;
  for (uint32_t index = 0; index < method->receiver_args.len; index++) {
    ms_scope_names_push(&resolver->variables, method->receiver_args.ptr[index]->name);
  }
  walk_function(resolver, &method->func);
  ms_scope_names_truncate(&resolver->variables, mark);
}

static void walk_enum(Resolver *resolver, const MsDecl *decl) {
  for (uint32_t index = 0; index < decl->u.enumeration.cases.len; index++) {
    walk_params(resolver, decl->u.enumeration.cases.ptr[index]->fields);
  }
}

static void walk_decl(Resolver *resolver, const MsDecl *decl) {
  const size_t mark = resolver->variables.len;
  switch ((MsDeclKind)decl->kind) {
  case MS_D_FN:
    walk_function(resolver, &decl->u.fn);
    break;
  case MS_D_CONST:
    if (decl->u.konst.ty != NULL) {
      walk_type(resolver, decl->u.konst.ty);
    }
    break;
  case MS_D_TYPE:
    enter_type_params(resolver, decl->u.type.type_params);
    walk_params(resolver, decl->u.type.fields);
    break;
  case MS_D_ENUM:
    enter_type_params(resolver, decl->u.enumeration.type_params);
    walk_enum(resolver, decl);
    break;
  case MS_D_ALIAS:
    enter_type_params(resolver, decl->u.alias.type_params);
    for (uint32_t index = 0; index < decl->u.alias.targets.len; index++) {
      walk_type(resolver, decl->u.alias.targets.ptr[index]);
    }
    break;
  case MS_D_INTERFACE:
    enter_type_params(resolver, decl->u.iface.type_params);
    for (uint32_t index = 0; index < decl->u.iface.methods.len; index++) {
      walk_method(resolver, decl->u.iface.methods.ptr[index]);
    }
    break;
  case MS_D_IMPL:
  case MS_D_TEST:
    break;
  }
  ms_scope_names_truncate(&resolver->variables, mark);
}

void ms_check_resolve_types(MsCheckProgram *program, uint32_t module) {
  Resolver resolver = {.program = program, .module = module};
  const MsModule *tree = program->modules.ptr[module].tree;
  for (uint32_t index = 0; index < tree->ndecls; index++) {
    walk_decl(&resolver, tree->decls[index]);
  }
  ms_scope_names_free(&resolver.variables);
}

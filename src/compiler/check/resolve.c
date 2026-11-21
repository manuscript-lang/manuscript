/* compiler/check/resolve.c: written types to checked types.
 *
 * A name resolves in this order: `Self`, the declaration's type variables, the primitives, the module's own
 * types, its imports, then the prelude. A qualified name (`mod.Type`) is not resolved yet and is invalid
 * without a diagnostic. A name given type arguments becomes the nominal type applied to them. */
#include "compiler/check/resolve_internal.h"

static const char *const PRELUDE_TYPES[] = {"Equal", "Stringable", "Comparable", "Hashable", "Clonable",
                                            "Optional", "Result", "Error", "List", "Map", "Set",
                                            "ListEntry", "MapEntry"};
static const char *const PRELUDE_MODULES[] = {"@std/core.ms", "@std/collections/collections.ms"};

void resolver_init(Resolver *resolver, MsCheckProgram *program, uint32_t module) {
  *resolver = (Resolver){.program = program, .module = module, .report = module < program->user_modules};
}

void resolver_free(Resolver *resolver) {
  ms_name_list_free(&resolver->names);
  ms_ty_list_free(&resolver->types);
}

void resolver_enter_symbol(Resolver *resolver, const MsSymbol *symbol) {
  const MsTypeParams params = ms_check_decl_type_params(symbol->decl);
  for (uint32_t index = 0; index < params.len && index < symbol->var_count; index++) {
    ms_name_list_push(&resolver->names, params.ptr[index]->name);
    ms_ty_list_push(&resolver->types,
                    resolver->program->symbol_vars.ptr[symbol->var_at + index]);
  }
}

MsTy resolver_primitive(MsCheckProgram *program, MsBuiltin builtin) {
  /* `Int64` and `Float64` are the same types as `Int` and `Float` (the default widths). */
  const MsBuiltin same = builtin == MS_BUILTIN_Int64 ? MS_BUILTIN_Int
                         : builtin == MS_BUILTIN_Float64 ? MS_BUILTIN_Float : builtin;
  const MsName name = ms_names_intern(program->names, ms_span_of_text(ms_builtin_name(same)));
  const MsTyDesc desc = {.name = name, .id = name, .kind = MS_TY_PRIMITIVE, .builtin = same};
  return ms_ty_intern(&program->types, &desc);
}

static bool find_variable(const Resolver *resolver, MsName name, MsTy *out) {
  for (size_t index = resolver->names.len; index > 0; index--) {
    if (resolver->names.ptr[index - 1] == name) {
      *out = resolver->types.ptr[index - 1];
      return true;
    }
  }
  return false;
}

/* The symbol a name denotes as a type in the module's scopes, or 0. `known` is set when the name is known even
 * though it has no symbol (an import that did not resolve). */
static MsSymbolId find_symbol(const Resolver *resolver, MsName name, bool *known) {
  const MsCheckProgram *program = resolver->program;
  const MsModuleInfo *module = &program->modules.ptr[resolver->module];
  const MsSymbolId *own = ms_scope_get(&module->scope, name);
  if (own != NULL && program->symbols.ptr[*own].kind != MS_SYMBOL_FN) {
    return *own;
  }
  const MsSymbolId *imported = ms_scope_get(&module->imports, name);
  if (imported != NULL) {
    *known = *imported == 0;
    return *imported != 0 && program->symbols.ptr[*imported].kind != MS_SYMBOL_FN ? *imported : 0;
  }
  const MsSpan text = ms_names_span(program->names, name);
  for (size_t index = 0; index < MS_COUNT_OF(PRELUDE_TYPES); index++) {
    if (!ms_span_is_text(text, PRELUDE_TYPES[index])) {
      continue;
    }
    for (size_t at = 0; at < MS_COUNT_OF(PRELUDE_MODULES); at++) {
      uint32_t found = 0;
      const MsName file = ms_names_intern(program->names, ms_span_of_text(PRELUDE_MODULES[at]));
      for (; found < program->modules.len && program->modules.ptr[found].file != file; found++) {
      }
      const MsSymbolId *symbol =
          found < program->modules.len ? ms_scope_get(&program->modules.ptr[found].scope, name) : NULL;
      if (symbol != NULL) {
        return *symbol;
      }
    }
  }
  return 0;
}

static void report_unknown(const Resolver *resolver, const MsTypeRef *type) {
  MsCheckProgram *program = resolver->program;
  MsStrBuild text = ms_strbuild_new();
  const MsSpan name = ms_names_span(program->names, type->name);
  ms_strbuild_append_text(&text, "unknown type ");
  ms_strbuild_append(&text, name);
  ms_strbuild_append_text(&text, "; declare it with 'type ");
  ms_strbuild_append(&text, name);
  ms_strbuild_append_text(&text, ":' / 'enum ");
  ms_strbuild_append(&text, name);
  ms_strbuild_append_text(&text, ":' / 'interface ");
  ms_strbuild_append(&text, name);
  ms_strbuild_append_text(&text, ":', declare it as a type parameter, or import it");
  ms_check_report(program, resolver->module, type->pos, MS_CHECK_RESOLUTION, ms_strbuild_finish(&text));
}

/* The nominal type `base` applied to the arguments written after its name. */
static MsTy apply(Resolver *resolver, MsTy base, const MsTypeRef *type) {
  if (type->args.len == 0) {
    return base;
  }
  MsTyList args = {0};
  for (uint32_t index = 0; index < type->args.len; index++) {
    ms_ty_list_push(&args, resolver_type(resolver, type->args.ptr[index]));
  }
  const MsTyRow row = *ms_ty_row(&resolver->program->types, base);
  const MsTyDesc desc = {.name = row.name, .id = row.id, .kind = (MsTyKind)row.kind,
                         .builtin = (MsBuiltin)row.builtin, .def = row.def, .args = args.ptr,
                         .arg_count = (uint32_t)args.len};
  const MsTy applied = ms_ty_intern(&resolver->program->types, &desc);
  ms_ty_list_free(&args);
  return applied;
}

static MsTy named_type(Resolver *resolver, const MsTypeRef *type) {
  MsCheckProgram *program = resolver->program;
  const MsSpan text = ms_names_span(program->names, type->name);
  size_t dot = 0;
  MsTy variable = MS_TY_NONE;
  if (ms_span_find(text, ms_span_of_text("."), &dot)) {
    return MS_TY_NONE;
  }
  if (ms_span_is_text(text, "Self")) {
    return resolver->self;
  }
  if (find_variable(resolver, type->name, &variable)) {
    return variable;
  }
  const MsBuiltin primitive = ms_builtin_primitive(text);
  if (primitive != MS_BUILTIN_NONE) {
    return resolver_primitive(program, primitive);
  }
  bool known = false;
  const MsSymbolId symbol = find_symbol(resolver, type->name, &known);
  if (symbol != 0) {
    return apply(resolver, program->symbols.ptr[symbol].ty, type);
  }
  if (!known && resolver->report) {
    report_unknown(resolver, type);
  }
  return MS_TY_NONE;
}

void resolver_params(Resolver *resolver, MsParams params, MsTyParamList *out) {
  for (uint32_t index = 0; index < params.len; index++) {
    const MsParam *param = params.ptr[index];
    const uint8_t flags = (uint8_t)((param->is_mutable ? MS_PARAM_VAR : 0) | (param->moving ? MS_PARAM_MOVE : 0));
    const MsTy ty = param->ty != NULL ? resolver_type(resolver, param->ty) : MS_TY_NONE;
    ms_ty_param_list_push(out, (MsTyParam){.name = param->name, .ty = ty, .flags = flags});
  }
}

MsTy resolver_function(Resolver *resolver, MsParams params, const MsTypeRef *result) {
  MsCheckProgram *program = resolver->program;
  MsTyParamList list = {0};
  resolver_params(resolver, params, &list);
  const MsTy returns =
      result != NULL ? resolver_type(resolver, result) : resolver_primitive(program, MS_BUILTIN_Void);
  const MsName fn = ms_names_intern(program->names, ms_span_of_text("fn"));
  const MsTyDesc desc = {.name = fn, .id = fn, .kind = MS_TY_FUNCTION, .params = list.ptr,
                         .param_count = (uint32_t)list.len, .result = returns};
  const MsTy function = ms_ty_intern(&program->types, &desc);
  ms_ty_param_list_free(&list);
  return function;
}

MsTy resolver_type(Resolver *resolver, const MsTypeRef *type) {
  if (type->kind == MS_TYPE_FN) {
    return resolver_function(resolver, type->params, type->result);
  }
  return named_type(resolver, type);
}

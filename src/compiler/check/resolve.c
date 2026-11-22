/* compiler/check/resolve.c: written types to checked types.
 *
 * A name resolves in this order: `Self`, the declaration's type variables, the primitives, the module's own
 * types, its imports, then the prelude. A qualified name (`mod.Type`) is not resolved yet and is invalid
 * without a diagnostic. A name given type arguments becomes the nominal type applied to them. */
#include "compiler/check/resolve_internal.h"
#include "compiler/check/std_exports.h"

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

/* The prelude type `name` names, or 0. */
MsSymbolId resolver_prelude_symbol(const MsCheckProgram *program, MsName name) {
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
  return resolver_prelude_symbol(program, name);
}

/* The built-in type a habit from another language names (`str` for `String`), or an empty span. */
static MsSpan type_habit(MsSpan name) {
  static const struct {
    const char *habit;
    const char *builtin;
  } TABLE[] = {
      {"Integer", "Int"},  {"long", "Int"},       {"Long", "Int"},      {"i64", "Int"},        {"int64", "Int"},
      {"number", "Int"},   {"Number", "Int"},     {"double", "Float"},  {"Double", "Float"},   {"f64", "Float"},
      {"float64", "Float"}, {"str", "String"},    {"Str", "String"},    {"string", "String"},  {"char", "String"},
      {"Char", "String"},  {"Text", "String"},    {"boolean", "Bool"},  {"Boolean", "Bool"},   {"bool", "Bool"},
      {"void", "Void"},    {"None", "Void"},      {"NoneType", "Void"}, {"Vec", "List"},       {"Vector", "List"},
      {"Array", "List"},   {"ArrayList", "List"}, {"array", "List"},    {"Dict", "Map"},       {"Dictionary", "Map"},
      {"HashMap", "Map"},  {"dict", "Map"},       {"TreeMap", "Map"},   {"HashSet", "Set"},    {"TreeSet", "Set"}};
  for (size_t index = 0; index < MS_COUNT_OF(TABLE); index++) {
    if (ms_span_is_text(name, TABLE[index].habit)) {
      return ms_span_of_text(TABLE[index].builtin);
    }
  }
  return (MsSpan){0};
}

/* Appends the oracle's advice for an unknown type; fills `statement` with the import it names, when it does. */
static void unknown_type_advice(MsCheckProgram *program, MsSpan name, MsStrBuild *text, MsStrBuild *statement) {
  MsStrBuild module_path = ms_strbuild_new();
  const MsSpan habit = type_habit(name);
  if (ms_std_exporter(program, name, true, &module_path)) {
    ms_strbuild_append_text(text, "; add: import ");
    ms_strbuild_append(text, name);
    ms_strbuild_append_text(text, " from \"");
    ms_strbuild_append(text, ms_strbuild_span(&module_path));
    ms_strbuild_append_text(text, "\"");
    ms_strbuild_append_text(statement, "import ");
    ms_strbuild_append(statement, name);
    ms_strbuild_append_text(statement, " from \"");
    ms_strbuild_append(statement, ms_strbuild_span(&module_path));
    ms_strbuild_append_text(statement, "\"\n");
  } else if (ms_span_is_text(name, "Callable") || ms_span_is_text(name, "Function") || ms_span_is_text(name, "Func") ||
             ms_span_is_text(name, "Fn")) {
    ms_strbuild_append_text(text, "; function types are written fn(Int) Int: parameter types in parentheses, then the result type");
  } else if (ms_span_is_text(name, "Option") || ms_span_is_text(name, "Maybe")) {
    ms_strbuild_append_text(text, "; an optional type is written T?, e.g. Int? or (fn(Int) Int)?");
  } else if (habit.len != 0) {
    ms_strbuild_append_text(text, "; did you mean '");
    ms_strbuild_append(text, habit);
    ms_strbuild_append_text(text, "'?");
  } else {
    ms_strbuild_append_text(text, "; declare it with 'type ");
    ms_strbuild_append(text, name);
    ms_strbuild_append_text(text, ":' / 'enum ");
    ms_strbuild_append(text, name);
    ms_strbuild_append_text(text, ":' / 'interface ");
    ms_strbuild_append(text, name);
    ms_strbuild_append_text(text, ":', declare it as a type parameter, or import it");
  }
  ms_strbuild_free(&module_path);
}

static void report_unknown(const Resolver *resolver, const MsTypeRef *type) {
  MsCheckProgram *program = resolver->program;
  MsStrBuild text = ms_strbuild_new();
  MsStrBuild statement = ms_strbuild_new();
  const MsSpan name = ms_names_span(program->names, type->name);
  ms_strbuild_append_text(&text, "unknown type ");
  ms_strbuild_append(&text, name);
  unknown_type_advice(program, name, &text, &statement);
  ms_check_report(program, resolver->module, type->pos, MS_CHECK_RESOLUTION, ms_strbuild_finish(&text));
  if (ms_strbuild_length(&statement) != 0) {
    const MsPos start = {.offset = 0, .line = 1, .column = 1};
    ms_check_attach_fix(program, start, start, ms_strbuild_finish(&statement));
  } else {
    ms_strbuild_free(&statement);
  }
}

MsTy resolver_apply(MsCheckProgram *program, MsTy base, const MsTy *args, size_t count) {
  if (count == 0) {
    return base;
  }
  const MsTyRow row = *ms_ty_row(&program->types, base);
  const MsTyDesc desc = {.name = row.name, .id = row.id, .kind = (MsTyKind)row.kind,
                         .builtin = (MsBuiltin)row.builtin, .def = row.def, .args = args,
                         .arg_count = (uint32_t)count};
  return ms_ty_intern(&program->types, &desc);
}

/* Appends the defaults of the type parameters `args` leaves out: `Pair[Int]` of `Pair[A, B = A]` is `Pair[Int, Int]`. */
static void fill_defaults(MsCheckProgram *program, MsTy base, MsTyList *args) {
  const uint32_t at = ms_ty_row(&program->types, base)->def;
  const MsDef *def = at == 0 ? NULL : ms_defs_get(&program->defs, at);
  for (size_t index = args->len; def != NULL && args->len != 0 && index < def->variables.len; index++) {
    const MsTyVariable *record = ms_ty_variable(&program->types, def->variables.ptr[index]);
    if (record == NULL || record->default_ty == MS_TY_NONE) {
      return;
    }
    ms_ty_list_push(args, ms_ty_subst(&program->types, record->default_ty, def->variables.ptr, args->ptr, args->len));
  }
}

/* The nominal type `base` applied to the arguments written after its name. */
static MsTy apply(Resolver *resolver, MsTy base, const MsTypeRef *type) {
  MsTyList args = {0};
  for (uint32_t index = 0; index < type->args.len; index++) {
    ms_ty_list_push(&args, resolver_type(resolver, type->args.ptr[index]));
  }
  fill_defaults(resolver->program, base, &args);
  const MsTy applied = resolver_apply(resolver->program, base, args.ptr, args.len);
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

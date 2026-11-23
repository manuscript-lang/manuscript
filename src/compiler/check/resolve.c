/* compiler/check/resolve.c: written types to checked types.
 *
 * A name resolves in this order: `Self`, the declaration's type variables, the primitives, the module's own
 * types, its imports, then the prelude. A qualified name (`mod.Type`) is not resolved yet and is invalid
 * without a diagnostic. A name given type arguments becomes the nominal type applied to them. */
#include "abi/prelude.h"
#include "base/cstr.h"
#include "compiler/check/resolve_internal.h"
#include "compiler/check/std_exports.h"
#include "compiler/check/bounds.h"
#include "compiler/check/suggest.h"
#include "base/cstr.h"

static const char *const PRELUDE_MODULES[] = {"@std/core.ms", "@std/collections/collections.ms"};

void resolver_init(Resolver *resolver, MsCheckProgram *program, uint32_t module) {
  *resolver = (Resolver){.program = program, .module = module, .report = module < program->user_modules || program->check_std};
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
  for (size_t index = 0; index < MS_PRELUDE_TYPE_COUNT; index++) {
    if (!ms_span_is_text(text, MS_PRELUDE_TYPES[index])) {
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
    *known = false; /* a failed import leaves its name unknown here too */
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
/* The type names a misspelling could mean: type variables, primitives, the prelude and the module's own and imported types. */
static void type_candidates(const Resolver *resolver, MsSpanList *out) {
  static const char *const PRIMITIVES[] = {"Int",   "Int8",   "Int16",  "Int32",   "Int64",   "UInt8",   "UInt16",
                                           "UInt32", "UInt64", "Float",  "Float32", "Float64", "Bool",    "String", "Void"};
  const MsCheckProgram *program = resolver->program;
  for (size_t index = 0; index < resolver->names.len; index++) {
    ms_span_list_push(out, ms_names_span(program->names, resolver->names.ptr[index]));
  }
  for (size_t index = 0; index < MS_COUNT_OF(PRIMITIVES); index++) {
    ms_span_list_push(out, ms_span_of_text(PRIMITIVES[index]));
  }
  for (size_t index = 0; index < MS_PRELUDE_TYPE_COUNT; index++) {
    if (!ms_cstr_equal(MS_PRELUDE_TYPES[index], "Optional")) {
      ms_span_list_push(out, ms_span_of_text(MS_PRELUDE_TYPES[index]));
    }
  }
  const MsModuleInfo *module = &program->modules.ptr[resolver->module];
  const MsScope *scopes[2] = {&module->scope, &module->imports};
  for (size_t at = 0; at < 2; at++) {
    size_t cursor = 0;
    MsName key = 0;
    MsSymbolId *id = NULL;
    while (ms_scope_next(scopes[at], &cursor, &key, &id)) {
      if (*id != 0 && program->symbols.ptr[*id].kind == MS_SYMBOL_TYPE) {
        ms_span_list_push(out, ms_names_span(program->names, key));
      }
    }
  }
}

static bool did_you_mean(const Resolver *resolver, MsSpan name, MsStrBuild *text) {
  MsSpanList candidates = {0};
  type_candidates(resolver, &candidates);
  const bool found = ms_suggest_did_you_mean(text, name, &candidates);
  ms_span_list_free(&candidates);
  return found;
}

static void unknown_type_advice(const Resolver *resolver, MsSpan name, MsStrBuild *text, MsStrBuild *statement) {
  MsCheckProgram *program = resolver->program;
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
  } else if (did_you_mean(resolver, name, text)) {
    /* a near miss of a type that is in scope */
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

/* Where a new import goes: the top of the module, or below a leading comment block (a header) set apart by a blank line. */
static MsPos import_point(MsSpan source) {
  MsPos at = {.offset = 0, .line = 1, .column = 1};
  size_t offset = 0;
  uint32_t line = 1;
  while (offset + 1 < source.len && source.ptr[offset] == '/' && source.ptr[offset + 1] == '/') {
    while (offset < source.len && source.ptr[offset] != '\n') {
      offset++;
    }
    offset += offset < source.len ? 1 : 0;
    line++;
  }
  if (line == 1 || offset >= source.len || source.ptr[offset] != '\n') {
    return at;
  }
  while (offset < source.len && source.ptr[offset] == '\n') { /* the blank lines under the header */
    offset++;
    line++;
  }
  return (MsPos){.offset = (uint32_t)offset, .line = line, .column = 1};
}

static void report_unknown(const Resolver *resolver, const MsTypeRef *type) {
  MsCheckProgram *program = resolver->program;
  MsStrBuild text = ms_strbuild_new();
  MsStrBuild statement = ms_strbuild_new();
  const MsSpan name = ms_names_span(program->names, type->name);
  ms_strbuild_append_text(&text, "unknown type ");
  ms_strbuild_append(&text, name);
  unknown_type_advice(resolver, name, &text, &statement);
  ms_check_report(program, resolver->module, type->pos, MS_CHECK_RESOLUTION, ms_strbuild_finish(&text));
  if (ms_strbuild_length(&statement) != 0) {
    const MsPos start = import_point(program->modules.ptr[resolver->module].source);
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
static void fill_defaults(MsCheckProgram *program, MsTy base, MsTyList *args, bool bare) {
  const uint32_t at = ms_ty_row(&program->types, base)->def;
  const MsDef *def = at == 0 ? NULL : ms_defs_get(&program->defs, at);
  for (size_t index = args->len; def != NULL && (args->len != 0 || bare) && index < def->variables.len; index++) {
    const MsTyVariable *record = ms_ty_variable(&program->types, def->variables.ptr[index]);
    if (record == NULL || record->default_ty == MS_TY_NONE) {
      return;
    }
    ms_ty_list_push(args, ms_ty_subst(&program->types, record->default_ty, def->variables.ptr, args->ptr, args->len));
  }
}

/* `Name[T1, T2]` for an arity, as the oracle sketches the fix. */
static void append_sketch(MsStrBuild *out, MsSpan name, size_t arity) {
  ms_strbuild_append(out, name);
  if (arity == 0) {
    ms_strbuild_append_text(out, " with no type arguments");
    return;
  }
  ms_strbuild_append_text(out, "[");
  for (size_t index = 0; index < arity; index++) {
    ms_strbuild_printf(out, "%sT%zu", index == 0 ? "" : ", ", index + 1);
  }
  ms_strbuild_append_text(out, "]");
}

/* A type written with the wrong number of type arguments. */
static void report_arity(Resolver *resolver, const MsTypeRef *type, MsTy base, size_t found, size_t arity,
                         size_t required) {
  MsCheckProgram *program = resolver->program;
  const MsSpan name = ms_names_span(program->names, ms_ty_row(&program->types, base)->name);
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append(&text, name);
  if (required < arity) {
    ms_strbuild_printf(&text, " takes %zu to %zu type arguments, found %zu; write ", required, arity, found);
  } else {
    ms_strbuild_printf(&text, " requires %zu type arguments, found %zu; write ", arity, found);
  }
  append_sketch(&text, name, arity);
  ms_check_report(program, resolver->module, type->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

/* A written type argument that does not satisfy the bound of the parameter it fills. */
static void report_unsatisfied(MsCheckProgram *program, uint32_t module, MsPos pos, MsTy applied) {
  const MsTyRow *row = ms_ty_row(&program->types, applied);
  const MsDef *def = row->def == 0 ? NULL : ms_defs_get(&program->defs, row->def);
  const MsTy *args = ms_ty_args(&program->types, applied);
  for (size_t index = 0; def != NULL && index < def->variables.len && index < row->arg_count; index++) {
    MsString why = ms_string_empty();
    if (args[index] == MS_TY_NONE || ms_ty_is_invalid(&program->types, args[index]) ||
        ms_check_bounds_hold_with(program, def->variables.ptr[index], args[index], def->variables.ptr, args,
                                  def->variables.len, "use a type that implements it", &why)) {
      continue;
    }
    ms_check_report(program, module, pos, MS_CHECK_TYPE, why);
  }
}

void ms_check_flush_pending_bounds(MsCheckProgram *program) {
  for (size_t index = 0; index < program->pending_bounds.len; index++) {
    const MsPendingBound pending = program->pending_bounds.ptr[index];
    report_unsatisfied(program, pending.module, pending.pos, pending.ty);
  }
  program->pending_bounds.len = 0;
  for (size_t index = 0; index < program->pending_defaults.len; index++) {
    const MsPendingDefault pending = program->pending_defaults.ptr[index];
    const MsTyVariable *record = ms_ty_variable(&program->types, pending.owner);
    for (size_t at = 0; record != NULL && at < record->bounds.len; at++) {
      const MsTy bound = ms_ty_subst(&program->types, record->bounds.ptr[at], &pending.owner, &pending.variable, 1);
      if (!ms_check_implements(program, pending.variable, bound)) {
        MsStrBuild text = ms_strbuild_new();
        ms_check_unsatisfied_message(program, pending.variable, bound, "choose a default that already implements it", &text);
        ms_check_report(program, pending.module, pending.pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
      }
    }
  }
  program->pending_defaults.len = 0;
}

/* The nominal type `base` applied to the arguments written after its name. */
static MsTy apply(Resolver *resolver, MsTy base, const MsTypeRef *type) {
  MsTyList args = {0};
  for (uint32_t index = 0; index < type->args.len; index++) {
    ms_ty_list_push(&args, resolver_type(resolver, type->args.ptr[index]));
  }
  MsCheckProgram *program = resolver->program;
  const uint32_t at = ms_ty_row(&program->types, base)->def;
  const MsDef *def = at == 0 ? NULL : ms_defs_get(&program->defs, at);
  const size_t arity = def == NULL ? 0 : def->variables.len;
  size_t required = 0;
  for (size_t index = 0; index < arity; index++) {
    const MsTyVariable *record = ms_ty_variable(&program->types, def->variables.ptr[index]);
    required = record != NULL && record->default_ty == MS_TY_NONE ? index + 1 : required;
  }
  fill_defaults(resolver->program, base, &args, arity != 0 && required == 0); /* a bare name of a fully defaulted type */
  if (resolver->report && args.len != arity) {
    report_arity(resolver, type, base, type->args.len, arity, required);
  }
  /* A wrong count keeps the bare type: a value of the applied type then differs from it, as the oracle says. */
  MsTy applied = args.len == arity ? resolver_apply(resolver->program, base, args.ptr, args.len) : base;
  if (args.len != arity) {
    const MsTyRow row = *ms_ty_row(&program->types, base);
    const MsTyDesc bare = {.name = row.name, .id = row.id, .kind = (MsTyKind)row.kind, .builtin = (MsBuiltin)row.builtin,
                           .def = row.def, .args = NULL, .arg_count = 0};
    applied = ms_ty_intern(&program->types, &bare); /* written with no arguments: it is no instance of the type */
  }
  if (resolver->report && args.len == arity && arity != 0) {
    if (program->stage == MS_STAGE_DECLARATIONS) { /* signatures resolve before the methods that satisfy bounds */
      ms_pending_bound_list_push(&program->pending_bounds, (MsPendingBound){resolver->module, type->pos, applied});
    } else {
      report_unsatisfied(program, resolver->module, type->pos, applied);
    }
  }
  ms_ty_list_free(&args);
  return applied;
}

/* A written use of an alias: its target with the written arguments in place of the alias's variables. */
static MsTy alias_use(Resolver *resolver, const MsSymbol *alias, const MsTypeRef *type) {
  MsCheckProgram *program = resolver->program;
  if (alias->ty == MS_TY_NONE && alias->module == resolver->module) { /* resolved on first use */
    resolver_resolve_alias(resolver, &program->symbols.ptr[alias - program->symbols.ptr]);
  }
  if (alias->ty == MS_TY_NONE) {
    return alias->ty;
  }
  if (ms_ty_builtin(&program->types, alias->ty) == MS_BUILTIN_TypeSet) {
    if (!resolver->allow_type_set && resolver->report) {
      MsStrBuild text = ms_strbuild_new();
      const MsSpan name = ms_names_span(program->names, type->name);
      ms_strbuild_append(&text, name);
      ms_strbuild_append_text(&text, " is a type set, which constrains a type parameter and has no values; write fn f[T: ");
      ms_strbuild_append(&text, name);
      ms_strbuild_append_text(&text, "](...) or use one of its members");
      ms_check_report(program, resolver->module, type->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
      return MS_TY_NONE;
    }
    return alias->ty;
  }
  MsTyList args = {0};
  for (uint32_t index = 0; index < type->args.len; index++) {
    ms_ty_list_push(&args, resolver_type(resolver, type->args.ptr[index]));
  }
  const MsTy *vars = program->symbol_vars.ptr + alias->var_at;
  MsTy result = MS_TY_NONE;
  if (args.len == alias->var_count) {
    result = ms_ty_subst(&program->types, alias->ty, vars, args.ptr, args.len);
  } else if (resolver->report) {
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_printf(&text, "alias %.*s takes %u type arguments, found %zu",
                       (int)ms_names_span(program->names, type->name).len,
                       (const char *)ms_names_span(program->names, type->name).ptr, alias->var_count, args.len);
    ms_strbuild_append_text(&text, "; write ");
    append_sketch(&text, ms_names_span(program->names, type->name), alias->var_count);
    ms_check_report(program, resolver->module, type->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  }
  ms_ty_list_free(&args);
  return result;
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
  if (symbol != 0 && program->symbols.ptr[symbol].kind == MS_SYMBOL_ALIAS) {
    return alias_use(resolver, &program->symbols.ptr[symbol], type);
  }
  if (symbol != 0) {
    return apply(resolver, program->symbols.ptr[symbol].ty, type);
  }
  if (!known && resolver->report) {
    report_unknown(resolver, type);
  }
  return MS_TY_NONE;
}

MsTy resolver_bound(Resolver *resolver, const MsTypeRef *bound) {
  MsCheckProgram *program = resolver->program;
  const bool allowed = resolver->allow_type_set;
  resolver->allow_type_set = true;
  const MsTy resolved = resolver_type(resolver, bound);
  resolver->allow_type_set = allowed;
  const MsTyKind kind = resolved == MS_TY_NONE ? MS_TY_INVALID : ms_ty_kind(&program->types, resolved);
  if (kind == MS_TY_CONTRACT || resolved == MS_TY_NONE || !resolver->report) {
    return resolved;
  }
  MsStrBuild text = ms_strbuild_new();
  if (kind == MS_TY_VARIABLE) {
    ms_strbuild_append_text(&text, "a bound must be an interface, but ");
    ms_strbuild_append(&text, ms_names_span(program->names, bound->name));
    ms_strbuild_append_text(&text, " resolves to a type parameter; rename the type parameter or name an interface");
  } else {
    ms_strbuild_append_text(&text, "a bound must be an interface; write T: SomeInterface where SomeInterface is declared with 'interface'");
  }
  ms_check_report(program, resolver->module, bound->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  return MS_TY_NONE;
}

void resolver_params(Resolver *resolver, MsParams params, MsTyParamList *out) {
  for (uint32_t index = 0; index < params.len; index++) {
    const MsParam *param = params.ptr[index];
    for (uint32_t before = 0; resolver->report && before < index; before++) {
      if (params.ptr[before]->name == param->name) {
        MsStrBuild text = ms_strbuild_new();
        ms_strbuild_append_text(&text, "duplicate parameter or field ");
        ms_strbuild_append(&text, ms_names_span(resolver->program->names, param->name));
        ms_strbuild_append_text(&text, "; each name may appear once, so rename one");
        ms_check_report(resolver->program, resolver->module, param->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
        break;
      }
    }
    const uint8_t flags = (uint8_t)((param->is_mutable ? MS_PARAM_VAR : 0) | (param->moving ? MS_PARAM_MOVE : 0));
    const MsTy ty = param->ty != NULL ? resolver_type(resolver, param->ty) : MS_TY_NONE;
    ms_ty_param_list_push(out, (MsTyParam){.name = param->name, .ty = ty, .flags = flags});
  }
}

/* The most parameters a function declares: the lowerer indexes the moves and shared `var` parameters of one function
 * with 32-bit masks. A receiver comes on top (`LOWER_MAX_PARAMS` is one more). */
enum { MAX_DECLARED_PARAMS = 32 };

MsTy resolver_function(Resolver *resolver, MsParams params, const MsTypeRef *result) {
  MsCheckProgram *program = resolver->program;
  if (resolver->report && params.len > MAX_DECLARED_PARAMS) {
    ms_check_report(program, resolver->module, params.ptr[MAX_DECLARED_PARAMS]->pos, MS_CHECK_TYPE,
                    ms_string_static(ms_span_of_text("a function takes at most 32 parameters; pass a record instead")));
  }
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
  MsCheckProgram *program = resolver->program;
  const MsTy resolved = type->kind == MS_TYPE_FN ? resolver_function(resolver, type->params, type->result)
                                                  : named_type(resolver, type);
  if (resolver->module < program->user_modules) {
    ms_type_ref_record_list_push(&program->type_refs, (MsTypeRefRecord){.module = resolver->module, .node = type->id, .ty = resolved});
  }
  return resolved;
}

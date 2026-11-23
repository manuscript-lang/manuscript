/* compiler/check/declare.c: the declare pass, the first pass over a module.
 *
 * Gives every type, enum, interface, alias, function and constant a symbol and a scope entry. A type-like
 * declaration also gets its (still empty) definition and nominal type, so later passes can name it before its
 * fields are resolved. A name already in scope is a duplicate. */
#include "compiler/check/lazy_std.h"
#include "base/alloc.h"
#include "compiler/check/program.h"

void ms_check_program_init(MsCheckProgram *program, MsNames *names) {
  *program = (MsCheckProgram){.arena = ms_arena_new(), .names = names};
  ms_tys_init(&program->types);
  ms_defs_init(&program->defs);
  ms_symbol_list_push(&program->symbols, (MsSymbol){0});
}

void ms_check_program_free(MsCheckProgram *program) {
  for (size_t index = 0; index < program->modules.len; index++) {
    ms_scope_free(&program->modules.ptr[index].scope);
    ms_scope_free(&program->modules.ptr[index].imports);
  }
  for (size_t index = 0; index < program->diagnostics.len; index++) {
    ms_string_release(&program->diagnostics.ptr[index].message);
    ms_string_release(&program->diagnostics.ptr[index].fix_text);
  }
  ms_module_list_free(&program->modules);
  ms_symbol_list_free(&program->symbols);
  ms_ty_list_free(&program->symbol_vars);
  ms_check_diag_list_free(&program->diagnostics);
  ms_local_record_list_free(&program->bindings);
  ms_type_ref_record_list_free(&program->type_refs);
  ms_pending_bound_list_free(&program->pending_bounds);
  ms_check_diag_list_free(&program->deferred);
  ms_check_diag_list_free(&program->ownership);
  ms_pending_default_list_free(&program->pending_defaults);
  ms_check_lazy_std_free(program);
  ms_methods_free(&program->methods);
  ms_method_key_list_free(&program->method_index.by_name);
  ms_method_key_list_free(&program->method_index.by_decl);
  ms_property_memo_free(&program->properties);
  ms_defs_free(&program->defs);
  ms_tys_free(&program->types);
  ms_arena_free(&program->arena);
}

uint32_t ms_check_add_module(MsCheckProgram *program, MsName file, const MsModule *tree) {
  ms_module_list_push(&program->modules, (MsModuleInfo){.file = file, .tree = tree});
  return (uint32_t)program->modules.len - 1;
}

void ms_check_report(MsCheckProgram *program, uint32_t module, MsPos pos, MsCheckPhase phase,
                     MsString message) {
  ms_check_diag_list_push(&program->diagnostics,
                          (MsCheckDiag){.module = module, .pos = pos, .phase = phase, .message = message,
                                        .stage = program->stage});
}

void ms_check_defer(MsCheckProgram *program, size_t from) {
  for (size_t index = from; index < program->diagnostics.len; index++) {
    ms_check_diag_list_push(&program->deferred, program->diagnostics.ptr[index]);
  }
  program->diagnostics.len = from;
}

bool ms_check_release(MsCheckProgram *program, uint32_t module, uint32_t offset, MsSpan prefix) {
  for (size_t index = 0; index < program->deferred.len; index++) {
    MsCheckDiag *diag = &program->deferred.ptr[index];
    if (diag->module != module || diag->pos.offset != offset || !ms_span_starts_with(ms_string_span(&diag->message), prefix)) {
      continue;
    }
    MsCheckDiag released = *diag;
    released.stage = MS_STAGE_WALK;
    ms_check_diag_list_push(&program->diagnostics, released);
    *diag = program->deferred.ptr[--program->deferred.len];
    return true;
  }
  return false;
}

void ms_check_release_rest(MsCheckProgram *program) {
  for (size_t index = 0; index < program->deferred.len; index++) {
    ms_check_diag_list_push(&program->diagnostics, program->deferred.ptr[index]);
  }
  program->deferred.len = 0;
}

void ms_check_attach_end(MsCheckProgram *program, MsPos end) {
  MsCheckDiag *last = ms_check_diag_list_last(&program->diagnostics);
  last->has_end = true;
  last->end = end;
}

void ms_check_attach_fix(MsCheckProgram *program, MsPos pos, MsPos end, MsString replacement) {
  MsCheckDiag *last = ms_check_diag_list_last(&program->diagnostics);
  last->has_fix = true;
  last->fix_pos = pos;
  last->fix_end = end;
  last->fix_text = replacement;
}

MsTypeParams ms_check_decl_type_params(const MsDecl *decl) {
  switch ((MsDeclKind)decl->kind) {
  case MS_D_FN:
    return decl->u.fn.type_params;
  case MS_D_TYPE:
    return decl->u.type.type_params;
  case MS_D_ENUM:
    return decl->u.enumeration.type_params;
  case MS_D_ALIAS:
    return decl->u.alias.type_params;
  case MS_D_INTERFACE:
    return decl->u.iface.type_params;
  case MS_D_CONST:
  case MS_D_IMPL:
  case MS_D_TEST:
    break;
  }
  return (MsTypeParams){0};
}

/* The name a declaration introduces, or false for impl and test declarations. */
bool ms_check_declared_name(const MsDecl *decl, MsName *name) {
  switch ((MsDeclKind)decl->kind) {
  case MS_D_FN:
    *name = decl->u.fn.name;
    return true;
  case MS_D_CONST:
    *name = decl->u.konst.name;
    return true;
  case MS_D_TYPE:
    *name = decl->u.type.name;
    return true;
  case MS_D_ENUM:
    *name = decl->u.enumeration.name;
    return true;
  case MS_D_ALIAS:
    *name = decl->u.alias.name;
    return true;
  case MS_D_INTERFACE:
    *name = decl->u.iface.name;
    return true;
  case MS_D_IMPL:
  case MS_D_TEST:
    return false;
  }
  return false;
}

static bool is_type_like(const MsDecl *decl, MsTyKind *kind) {
  switch ((MsDeclKind)decl->kind) {
  case MS_D_TYPE:
    *kind = decl->u.type.external ? MS_TY_NATIVE : MS_TY_TYPE;
    return true;
  case MS_D_ENUM:
    *kind = MS_TY_ALTERNATIVE;
    return true;
  case MS_D_INTERFACE:
    *kind = MS_TY_CONTRACT;
    return true;
  case MS_D_FN:
  case MS_D_CONST:
  case MS_D_ALIAS:
  case MS_D_IMPL:
  case MS_D_TEST:
    return false;
  }
  return false;
}

static MsSymbolKind symbol_kind(const MsDecl *decl) {
  MsTyKind unused = MS_TY_TYPE;
  if (is_type_like(decl, &unused)) {
    return MS_SYMBOL_TYPE;
  }
  return decl->kind == MS_D_ALIAS ? MS_SYMBOL_ALIAS : MS_SYMBOL_FN;
}

MsName ms_check_unique_id(MsCheckProgram *program, const char *prefix) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, prefix);
  ms_strbuild_append_u64(&text, ++program->serial);
  const MsName id = ms_names_intern(program->names, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  return id;
}

/* The built-in a standard module's type is: a prelude type by name, or a native-layout source type. */
static MsBuiltin builtin_of(const MsCheckProgram *program, const MsSymbol *symbol) {
  const MsSpan file = ms_names_span(program->names, program->modules.ptr[symbol->module].file);
  if (!ms_span_starts_with(file, ms_span_of_text("@std/"))) {
    return MS_BUILTIN_NONE;
  }
  const MsBuiltin source = ms_builtin_source(file, ms_names_span(program->names, symbol->name));
  if (source != MS_BUILTIN_NONE) {
    return source;
  }
  MsStrBuild id = ms_strbuild_new();
  ms_strbuild_append_text(&id, "@std/");
  ms_strbuild_append(&id, ms_names_span(program->names, symbol->name));
  const MsBuiltin by_id = ms_builtin_from_id(ms_strbuild_span(&id));
  ms_strbuild_free(&id);
  return by_id;
}

/* The nominal type of a type-like declaration: its definition is empty until the signature passes. */
static void declare_nominal(MsCheckProgram *program, MsSymbol *symbol, MsTyKind kind) {
  symbol->def = ms_defs_add(&program->defs, kind, (uint32_t)program->symbols.len);
  const MsTyDesc desc = {.name = symbol->name, .id = symbol->id, .kind = kind,
                         .builtin = builtin_of(program, symbol), .def = symbol->def};
  symbol->ty = ms_ty_intern(&program->types, &desc);
}

static void report_duplicate(MsCheckProgram *program, uint32_t module, const MsDecl *decl, MsName name) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "duplicate or intrinsic name ");
  ms_strbuild_append(&text, ms_names_span(program->names, name));
  ms_strbuild_append_text(&text, "; this name is already declared, imported, or built in, so rename one of them");
  ms_check_report(program, module, decl->pos, MS_CHECK_RESOLUTION, ms_strbuild_finish(&text));
}

static const char *const PRELUDE_NAMES[] = {"Equal",    "Stringable", "Comparable", "Hashable", "Clonable",
                                            "Optional", "Result",     "Error",      "List",     "Map",
                                            "Set",      "ListEntry",  "MapEntry",   "print",     "ok_or"};

/* Whether `name` is declared by the prelude, which every module sees under that name. */
static bool is_prelude_name(const MsCheckProgram *program, MsName name) {
  const MsSpan text = ms_names_span(program->names, name);
  for (size_t index = 0; index < MS_COUNT_OF(PRELUDE_NAMES); index++) {
    if (ms_span_is_text(text, PRELUDE_NAMES[index])) {
      return true;
    }
  }
  return false;
}

static void report_prelude_reuse(MsCheckProgram *program, uint32_t module, const MsDecl *decl, MsName name) {
  MsStrBuild text = ms_strbuild_new();
  const MsSpan span = ms_names_span(program->names, name);
  ms_strbuild_append_text(&text, "declaration ");
  ms_strbuild_append(&text, span);
  ms_strbuild_append_text(&text, " reuses a prelude name; rename it, because ");
  ms_strbuild_append(&text, span);
  ms_strbuild_append_text(&text, " always refers to the standard declaration");
  ms_check_report(program, module, decl->pos, MS_CHECK_RESOLUTION, ms_strbuild_finish(&text));
}

/* The prelude's constructor names: a module declaration cannot reuse one. */
static bool is_prelude_constructor(const MsCheckProgram *program, MsName name) {
  const MsSpan text = ms_names_span(program->names, name);
  return ms_span_is_text(text, "some") || ms_span_is_text(text, "null") || ms_span_is_text(text, "ok") ||
         ms_span_is_text(text, "error");
}

static void report_constructor_reuse(MsCheckProgram *program, uint32_t module, const MsDecl *decl, MsName name) {
  MsStrBuild text = ms_strbuild_new();
  const MsSpan span = ms_names_span(program->names, name);
  ms_strbuild_append_text(&text, "declaration ");
  ms_strbuild_append(&text, span);
  ms_strbuild_append_text(&text, " reuses a prelude constructor name; rename it, because ");
  ms_strbuild_append(&text, span);
  ms_strbuild_append_text(&text, " always refers to the prelude case");
  ms_check_report(program, module, decl->pos, MS_CHECK_RESOLUTION, ms_strbuild_finish(&text));
}

void ms_check_declare(MsCheckProgram *program, uint32_t module) {
  const MsModule *tree = program->modules.ptr[module].tree;
  for (uint32_t index = 0; index < tree->ndecls; index++) {
    const MsDecl *decl = tree->decls[index];
    MsName name = MS_NAME_EMPTY;
    if (!ms_check_declared_name(decl, &name)) {
      continue;
    }
    if (module < program->user_modules && is_prelude_constructor(program, name)) {
      report_constructor_reuse(program, module, decl, name);
    }
    if (module < program->user_modules && is_prelude_name(program, name)) {
      report_prelude_reuse(program, module, decl, name);
      continue;
    }
    if (ms_builtin_primitive(ms_names_span(program->names, name)) != MS_BUILTIN_NONE ||
        ms_scope_has(&program->modules.ptr[module].scope, name)) {
      report_duplicate(program, module, decl, name);
      continue;
    }
    if (module < program->user_modules && decl->kind == MS_D_TYPE && decl->u.type.external &&
        decl->u.type.type_params.len != 0) {
      MsStrBuild text = ms_strbuild_new();
      ms_strbuild_append_text(&text, "extern type ");
      ms_strbuild_append(&text, ms_names_span(program->names, name));
      ms_strbuild_append_text(&text, " cannot be generic; declare one extern type per native handle");
      ms_check_report(program, module, decl->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
    }
    MsSymbol symbol = {.name = name, .id = ms_check_unique_id(program, "symbol"), .kind = symbol_kind(decl),
                       .native = decl->kind == MS_D_FN && decl->u.fn.external ? MS_NATIVE_EXTERN
                                                                                : MS_NATIVE_SOURCE,
                       .module = module, .exported = decl->is_exported, .decl = decl};
    MsTyKind kind = MS_TY_TYPE;
    if (is_type_like(decl, &kind)) {
      declare_nominal(program, &symbol, kind);
    }
    ms_symbol_list_push(&program->symbols, symbol);
    ms_scope_put(&program->modules.ptr[module].scope, name, (MsSymbolId)program->symbols.len - 1);
  }
}

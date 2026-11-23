/* compiler/check/exprs.c: names, members, applications, lists, maps, indexing and lambdas.
 *
 * body_expr dispatches on the expression kind, records the result in the facts and returns it. Literals and
 * operators live in exprs_ops.c and calls in calls.c. A name resolves to a local or parameter, then a symbol of
 * the module (declared, imported or prelude), then a case of a visible enum. What fails to resolve is invalid;
 * reporting it is the job of the unknown-binding pass. */
#include "compiler/check/body.h"
#include "compiler/check/methods.h"
#include "compiler/check/suggest.h"

static MsName intern(const Body *body, const char *text) {
  return ms_names_intern(body->program->names, ms_span_of_text(text));
}

const MsSymbol *body_find_symbol(const Body *body, MsName name) {
  const MsCheckProgram *program = body->program;
  const MsModuleInfo *module = &program->modules.ptr[body->module];
  const MsSymbolId *found = ms_scope_get(&module->scope, name);
  if (found == NULL) {
    found = ms_scope_get(&module->imports, name);
  }
  MsSymbolId id = found != NULL ? *found : 0;
  if (found == NULL) {
    id = resolver_prelude_symbol(program, name);
  }
  /* `print` is a core function every module sees, and `a..b` calls the collections function `range`. */
  const MsSpan text = ms_names_span(program->names, name);
  const bool range = ms_span_is_text(text, "..");
  if (id == 0 && (range || ms_span_is_text(text, "print"))) {
    const MsName home = intern(body, range ? "@std/collections/collections.ms" : "@std/core.ms");
    const MsName target = range ? intern(body, "range") : name;
    for (uint32_t index = program->user_modules; index < program->modules.len; index++) {
      const MsSymbolId *symbol = program->modules.ptr[index].file == home
                                     ? ms_scope_get(&program->modules.ptr[index].scope, target)
                                     : NULL;
      id = symbol != NULL ? *symbol : id;
    }
  }
  return id != 0 ? &program->symbols.ptr[id] : NULL;
}

const MsDef *body_def(const Body *body, MsTy ty) {
  const MsTyRow *row = ms_ty_row(&body->program->types, ty);
  const bool nominal = row->kind == MS_TY_TYPE || row->kind == MS_TY_ALTERNATIVE || row->kind == MS_TY_CONTRACT ||
                       row->kind == MS_TY_NATIVE;
  return nominal && row->def != 0 ? ms_defs_get(&body->program->defs, row->def) : NULL;
}

/* A type's definition arguments replaced by the arguments `owner` carries. */
static MsTy owner_subst(Body *body, MsTy owner, MsTy ty) {
  MsCheckProgram *program = body->program;
  const MsTyRow *row = ms_ty_row(&program->types, owner);
  const MsDef *def = body_def(body, owner);
  if (def == NULL || row->arg_count == 0) {
    return ty;
  }
  if (def->variables.len != row->arg_count) {
    return ty;
  }
  return ms_ty_subst(&program->types, ty, def->variables.ptr, ms_ty_args(&program->types, owner), row->arg_count);
}

/* The record field `name` of `receiver`, with its type as the receiver's arguments give it. */
bool body_field(Body *body, MsTy receiver, MsName name, MsTy *ty, uint32_t *index) {
  const MsDef *def = body_def(body, receiver);
  if (def == NULL || ms_ty_kind(&body->program->types, receiver) != MS_TY_TYPE) {
    return false;
  }
  for (uint32_t at = 0; at < def->fields.len; at++) {
    if (def->fields.ptr[at].name == name) {
      *index = at;
      *ty = owner_subst(body, receiver, def->fields.ptr[at].ty);
      return true;
    }
  }
  return false;
}

/* The case `name` of the enum `owner`: its index and definition. */
const MsTyCase *body_case_of(Body *body, MsTy owner, MsName name, uint32_t *index) {
  const MsDef *def = body_def(body, owner);
  if (def == NULL || ms_ty_kind(&body->program->types, owner) != MS_TY_ALTERNATIVE) {
    return NULL;
  }
  size_t at = 0;
  if (!ms_def_find_case(def, name, &at)) {
    return NULL;
  }
  *index = (uint32_t)at;
  return &def->cases.ptr[at];
}

/* Whether a visible enum has a case `name`: its type (as `expected` fixes it) and the case. */
bool body_find_case(Body *body, MsName name, MsTy expected, const MsPos *at, MsTy *owner, uint32_t *index) {
  MsCheckProgram *program = body->program;
  const MsModuleInfo *module = &program->modules.ptr[body->module];
  MsSymbolList seen = {0};
  size_t cursor = 0;
  MsName key = 0;
  MsSymbolId *id = NULL;
  while (ms_scope_next(&module->scope, &cursor, &key, &id)) {
    ms_symbol_list_push(&seen, program->symbols.ptr[*id]);
  }
  cursor = 0;
  while (ms_scope_next(&module->imports, &cursor, &key, &id)) {
    ms_symbol_list_push(&seen, program->symbols.ptr[*id]);
  }
  static const char *const PRELUDE[] = {"Optional", "Result"};
  for (size_t position = 0; position < MS_COUNT_OF(PRELUDE); position++) {
    ms_symbol_list_push(&seen, program->symbols.ptr[resolver_prelude_symbol(program, intern(body, PRELUDE[position]))]);
  }
  size_t matches = 0;
  for (size_t position = 0; position < seen.len; position++) {
    const MsSymbol *symbol = &seen.ptr[position];
    uint32_t found_at = 0;
    if (symbol->kind == MS_SYMBOL_ALIAS || symbol->ty == MS_TY_NONE ||
        ms_ty_kind(&program->types, symbol->ty) != MS_TY_ALTERNATIVE ||
        body_case_of(body, symbol->ty, name, &found_at) == NULL) {
      continue;
    }
    matches += matches == 0 || *owner != symbol->ty ? 1 : 0;
    *owner = matches == 1 ? symbol->ty : *owner;
    *index = matches == 1 ? found_at : *index;
  }
  ms_symbol_list_free(&seen);
  (void)expected;
  if (matches > 1 && at != NULL && !body->quiet && body_reports(body)) {
    MsStrBuild text = ms_strbuild_new();
    const MsSpan written = ms_names_span(program->names, name);
    ms_strbuild_append_text(&text, "ambiguous alternative case ");
    ms_strbuild_append(&text, written);
    ms_strbuild_append_text(&text, "; qualify it with its type, e.g. Type.");
    ms_strbuild_append(&text, written);
    ms_check_report(program, body->module, *at, MS_CHECK_RESOLUTION, ms_strbuild_finish(&text));
  }
  return matches == 1;
}

MsRef body_method_ref(const MsMethodMatch *match, MsTy receiver) {
  const MsMethodEntry *entry = match->entry;
  MsRef ref = {.kind = MS_REF_METHOD, .owner = receiver};
  if (entry != NULL) {
    ref.decl = (MsNodeRef){entry->module, entry->source->id};
    ref.kind = entry->source->func.body.len == 0 ? MS_REF_NATIVE : MS_REF_METHOD;
  } else if (match->operation != NULL) {
    ref.kind = match->native ? MS_REF_NATIVE : MS_REF_OPERATION;
    ref.decl = (MsNodeRef){match->operation->decl.file, match->operation->decl.node};
  }
  return ref;
}

MsRef body_symbol_ref(const Body *body, const MsSymbol *symbol) {
  MsRefKind kind = MS_REF_FUNCTION;
  if (symbol->kind == MS_SYMBOL_TYPE) {
    kind = MS_REF_TYPE;
  } else if (symbol->decl != NULL && symbol->decl->kind == MS_D_CONST) {
    kind = MS_REF_CONSTANT;
  } else if (symbol->native == MS_NATIVE_BUILTIN || symbol->native == MS_NATIVE_EXTERN) {
    kind = MS_REF_NATIVE;
  }
  (void)body;
  return (MsRef){.kind = kind, .decl = {symbol->module, symbol->decl != NULL ? symbol->decl->id : 0}};
}

/* A generic function named as a value takes the type arguments its expected function type fixes; without one it keeps
 * its generic type. */
static MsTy generic_as_value(Body *body, const MsSymbol *symbol, MsTy expected) {
  MsTyTable *types = &body->program->types;
  if (symbol->kind != MS_SYMBOL_FN || symbol->var_count == 0 || symbol->var_count > 16 || expected == MS_TY_NONE ||
      ms_ty_row(types, expected)->id != ms_ty_row(types, symbol->ty)->id) {
    return symbol->ty;
  }
  const MsTy *vars = body->program->symbol_vars.ptr + symbol->var_at;
  MsTy bound[16] = {0};
  if (!ms_check_unify(types, symbol->ty, expected, vars, symbol->var_count, bound)) {
    return symbol->ty;
  }
  for (uint32_t index = 0; index < symbol->var_count; index++) {
    if (bound[index] == MS_TY_NONE) {
      return symbol->ty;
    }
  }
  return ms_ty_subst(types, symbol->ty, vars, bound, symbol->var_count);
}

static MsTy name_expr(Body *body, const MsExpr *expr, MsTy expected) {
  const MsName name = expr->u.sym;
  const MsLocal *local = body_find_any_local(body, name);
  if (local != NULL && local->rejected) {
    if (!body->quiet && body_reports(body) && !ms_check_release(body->program, body->module, expr->pos.offset, ms_span_of_text("unknown binding "))) {
      MsStrBuild text = ms_strbuild_new();
      const MsSpan written = ms_names_span(body->program->names, name);
      ms_strbuild_append_text(&text, "unknown binding ");
      ms_strbuild_append(&text, written);
      ms_strbuild_append_text(&text, "; declare it with '");
      ms_strbuild_append(&text, written);
      ms_strbuild_append_text(&text, " := ...' before use, define 'fn ");
      ms_strbuild_append(&text, written);
      ms_strbuild_append_text(&text, "(...) T:', or import it from a module");
      ms_check_report(body->program, body->module, expr->pos, MS_CHECK_RESOLUTION, ms_strbuild_finish(&text));
    }
    return MS_TY_NONE;
  }
  if (local != NULL) {
    body_set_ref(body, expr->id, body_local_ref(body, local));
    return local->ty;
  }
  const MsSymbol *symbol = body_find_symbol(body, name);
  if (symbol != NULL && symbol->kind == MS_SYMBOL_TYPE) {
    /* a type's name is read only as a callee or before a `.`: alone it builds nothing */
    if (!body->quiet && body_reports(body)) {
      MsStrBuild text = ms_strbuild_new();
      ms_strbuild_append_text(&text, "type name requires a constructor call; write ");
      ms_strbuild_append(&text, ms_names_span(body->program->names, name));
      ms_strbuild_append_text(&text, "(field: value, ...) to build a value");
      ms_check_report(body->program, body->module, expr->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
    }
    body_set_ref(body, expr->id, body_symbol_ref(body, symbol));
    return MS_TY_NONE;
  }
  if (symbol != NULL) {
    const MsRef ref = body_symbol_ref(body, symbol);
    body_set_ref(body, expr->id, ref);
    if (ref.kind != MS_REF_CONSTANT && symbol->kind == MS_SYMBOL_FN && symbol->var_count != 0 && expected == MS_TY_NONE) {
      if (!body->quiet && body_reports(body)) {
        MsStrBuild text = ms_strbuild_new();
        ms_strbuild_append_text(&text, "a generic function value requires explicit specialization; write ");
        ms_strbuild_append(&text, ms_names_span(body->program->names, name));
        ms_strbuild_append_text(&text, "[Type] or call it with arguments");
        ms_check_report(body->program, body->module, expr->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
      }
      return MS_TY_NONE;
    }
    if (ref.kind == MS_REF_CONSTANT) {
      return body_constant_type(body, symbol);
    }
    const MsTy value = generic_as_value(body, symbol, expected);
    uint32_t home = 0;
    const MsParams *declared = symbol->kind == MS_SYMBOL_FN ? body_function_params(body, expr, value, &home) : NULL;
    bool changes = false;
    bool defaults = false;
    for (uint32_t at = 0; declared != NULL && at < declared->len; at++) {
      changes = changes || declared->ptr[at]->is_mutable;
      defaults = defaults || declared->ptr[at]->def != NULL;
    }
    if (changes && defaults) { /* a function value fills defaults in a thunk that cannot also pass a changed parameter */
      if (!body->quiet && body_reports(body)) {
        MsStrBuild text = ms_strbuild_new();
        const MsSpan written = ms_names_span(body->program->names, name);
        ms_strbuild_append(&text, written);
        ms_strbuild_append_text(&text, " has both a var parameter and a parameter default, so it cannot be a function value; call ");
        ms_strbuild_append(&text, written);
        ms_strbuild_append_text(&text, " from a closure that supplies the default");
        ms_check_report(body->program, body->module, expr->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
      }
      return MS_TY_NONE;
    }
    return value;
  }
  const MsSpan text = ms_names_span(body->program->names, name);
  if (ms_builtin_primitive(text) != MS_BUILTIN_NONE) { /* a primitive type's name alone builds nothing */
    if (!body->quiet && body_reports(body)) {
      MsStrBuild message = ms_strbuild_new();
      ms_strbuild_append_text(&message, "type name requires a constructor call; write ");
      ms_strbuild_append(&message, text);
      ms_strbuild_append_text(&message, "(field: value, ...) to build a value");
      ms_check_report(body->program, body->module, expr->pos, MS_CHECK_TYPE, ms_strbuild_finish(&message));
    }
    return MS_TY_NONE;
  }
  if (ms_span_is_text(text, "__LINE__")) {
    return body_primitive(body, MS_BUILTIN_Int);
  }
  if (ms_span_is_text(text, "__FILE__")) {
    return body_primitive(body, MS_BUILTIN_String);
  }
  if (ms_span_is_text(text, "fixture") && !body->quiet) {
    ms_check_report(body->program, body->module, expr->pos, MS_CHECK_RESOLUTION,
                    ms_string_from_span(ms_span_of_text("fixture is available only in tests with a local make_fixture factory; declare fn make_fixture() returning a concrete TestHooks implementer in this file")));
    return MS_TY_NONE;
  }
  MsTy owner = MS_TY_NONE;
  uint32_t index = 0;
  if (body_find_case(body, name, expected, &expr->pos, &owner, &index)) {
    const bool fits = expected != MS_TY_NONE && ms_ty_row(&body->program->types, expected)->id == ms_ty_row(&body->program->types, owner)->id;
    owner = fits ? expected : owner;
    body_set_ref(body, expr->id, (MsRef){.kind = MS_REF_CASE, .index = index, .owner = owner});
    return owner;
  }
  if (!body->quiet) { /* the names pass found it unknown; the walk is where the oracle reports it */
    (void)ms_check_release(body->program, body->module, expr->pos.offset, ms_span_of_text("unknown binding "));
  }
  return MS_TY_NONE;
}

/* `Type.name` or `Type.name(...)` where the type cannot have the case written: an interface, Optional, or a type with no
 * cases (the call form says it has no static members). Reports and returns true; false leaves the name to the caller. */
bool body_report_type_member(Body *body, MsPos pos, MsTy owner, MsName name, bool call) {
  const MsTyTable *types = &body->program->types;
  const MsDef *def = body_def(body, owner);
  const bool optional = ms_ty_is(types, owner, MS_BUILTIN_Optional);
  const bool contract = ms_ty_kind(types, owner) == MS_TY_CONTRACT;
  const bool bare = call && def != NULL && def->cases.len == 0 && !contract && !optional;
  if (!optional && !contract && !bare) {
    return false;
  }
  if (!body_reports(body) || body->quiet) {
    return true;
  }
  MsStrBuild text = ms_strbuild_new();
  const MsSpan member = ms_names_span(body->program->names, name);
  if (optional) {
    ms_strbuild_append_text(&text, "Optional has no qualified cases; write none or the plain value where a T? is expected, and put the type on the binding, e.g. x: Int? := none");
  } else if (contract) {
    ms_ty_show(&text, body->program->names, types, owner);
    ms_strbuild_append_text(&text, " is an interface, not an alternative; declare a concrete type with the methods ");
    ms_ty_show(&text, body->program->names, types, owner);
    ms_strbuild_append_text(&text, " lists, then construct that concrete type");
  } else {
    ms_ty_show(&text, body->program->names, types, owner);
    ms_strbuild_append_text(&text, " has no cases or static members, so `");
    ms_ty_show(&text, body->program->names, types, owner);
    ms_strbuild_append_text(&text, ".");
    ms_strbuild_append(&text, member);
    ms_strbuild_append_text(&text, "(...)` does not exist; if ");
    ms_strbuild_append(&text, member);
    ms_strbuild_append_text(&text, " is a module function, import it and call ");
    ms_strbuild_append(&text, member);
    ms_strbuild_append_text(&text, "(...); if it is a method, call it on a value");
  }
  ms_check_report(body->program, body->module, pos, MS_CHECK_RESOLUTION, ms_strbuild_finish(&text));
  return true;
}

/* `Type.Case` or `Type.member` where the left side names a type; false when it does not. */
/* `Type.name` where the type has no such case: an enum lists its cases, any other type has none to name. */
static void report_unknown_case(Body *body, const MsExpr *expr, MsTy owner) {
  const MsDef *def = body_def(body, owner);
  if (!body_reports(body) || body->quiet) {
    return;
  }
  if (def == NULL || def->cases.len == 0) {
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append(&text, ms_names_span(body->program->names, ms_ty_row(&body->program->types, owner)->name));
    ms_strbuild_append_text(&text, " has no member ");
    ms_strbuild_append(&text, ms_names_span(body->program->names, expr->u.member.name));
    ms_strbuild_append_text(&text, "; a type name is followed only by an enum case");
    ms_check_report(body->program, body->module, expr->pos, MS_CHECK_RESOLUTION, ms_strbuild_finish(&text));
    return;
  }
  MsSpanList names = {0};
  for (size_t index = 0; index < def->cases.len; index++) {
    ms_span_list_push(&names, ms_names_span(body->program->names, def->cases.ptr[index].name));
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "unknown or non-nullary alternative case ");
  ms_strbuild_append(&text, ms_names_span(body->program->names, expr->u.member.name));
  ms_strbuild_append_text(&text, " of ");
  ms_ty_show(&text, body->program->names, &body->program->types, owner);
  ms_strbuild_append_text(&text, "; cases: ");
  ms_suggest_list(&text, &names, 12);
  ms_strbuild_append_text(&text, " (cases with payloads need call syntax)");
  ms_check_report(body->program, body->module, expr->pos, MS_CHECK_RESOLUTION, ms_strbuild_finish(&text));
  ms_span_list_free(&names);
}

static bool type_member(Body *body, const MsExpr *expr, MsTy *ty) {
  const MsExpr *left = expr->u.member.left;
  /* `Type[Args].Case`: the type applied to its arguments. */
  const bool applied = left->kind == MS_E_APPLY && left->u.apply.left->kind == MS_E_NAME &&
                       left->u.apply.types.len != 0;
  const MsExpr *named = applied ? left->u.apply.left : left;
  if (named->kind != MS_E_NAME || body_find_local(body, named->u.sym) != NULL) {
    return false;
  }
  const MsSymbol *symbol = body_find_symbol(body, named->u.sym);
  if (symbol == NULL || symbol->kind != MS_SYMBOL_TYPE) {
    return false;
  }
  MsTy owner = symbol->ty;
  if (applied) {
    MsTyList args = {0};
    for (uint32_t index = 0; index < left->u.apply.types.len; index++) {
      ms_ty_list_push(&args, resolver_type(&body->resolver, left->u.apply.types.ptr[index]));
    }
    owner = resolver_apply(body->program, symbol->ty, args.ptr, args.len);
    ms_ty_list_free(&args);
    body_set_ref(body, named->id, body_symbol_ref(body, symbol));
  }
  body_set_ref(body, left->id, body_symbol_ref(body, symbol));
  body_set_type(body, left->id, owner);
  if (body_report_type_member(body, expr->pos, owner, expr->u.member.name, false)) {
    *ty = MS_TY_NONE;
    return true;
  }
  uint32_t index = 0;
  const MsTyCase *kase = body_case_of(body, owner, expr->u.member.name, &index);
  if (kase != NULL) {
    if (kase->fields.len == 0) {
      MsStrBuild what = ms_strbuild_new();
      ms_strbuild_append_text(&what, "case ");
      ms_strbuild_append(&what, ms_names_span(body->program->names, expr->u.member.name));
      ms_strbuild_append_text(&what, " cannot be built here");
      (void)body_opaque_denied(body, expr->pos, owner, ms_strbuild_span(&what));
      ms_strbuild_free(&what);
    }
    body_set_ref(body, expr->id, (MsRef){.kind = MS_REF_CASE, .index = index, .owner = owner});
    *ty = owner;
  } else {
    *ty = MS_TY_NONE;
    report_unknown_case(body, expr, owner);
  }
  return true;
}

static void report_ownership(Body *body, MsPos pos, const char *text) {
  if (body_reports(body) && !body->quiet) {
    ms_check_diag_list_push(&body->program->ownership,
                            (MsCheckDiag){.module = body->module, .pos = pos, .phase = MS_CHECK_TYPE,
                                          .stage = MS_STAGE_WALK, .message = ms_string_from_span(ms_span_of_text(text))});
  }
}

/* Whether the method type takes a callback that may change an element of the receiver (`fn(var T)` on `List[T]`). */
static bool takes_element_mutator(const MsTyTable *types, MsTy method, MsTy receiver) {
  for (size_t at = 0; ms_ty_kind(types, method) == MS_TY_FUNCTION && at < ms_ty_param_count(types, method); at++) {
    const MsTy callback = ms_ty_params(types, method)[at].ty;
    for (size_t index = 0; ms_ty_kind(types, callback) == MS_TY_FUNCTION && index < ms_ty_param_count(types, callback); index++) {
      const MsTyParam *param = &ms_ty_params(types, callback)[index];
      for (size_t arg = 0; (param->flags & MS_PARAM_VAR) != 0 && arg < ms_ty_arg_count(types, receiver); arg++) {
        if (ms_ty_args(types, receiver)[arg] == param->ty) {
          return true;
        }
      }
    }
  }
  return false;
}

static MsTy member_expr(Body *body, const MsExpr *expr, MsTy expected) {
  (void)expected;
  MsTy ty = MS_TY_NONE;
  if (type_member(body, expr, &ty)) {
    return ty;
  }
  const MsTy receiver = body_expr(body, expr->u.member.left, MS_TY_NONE);
  uint32_t index = 0;
  if (body_field(body, receiver, expr->u.member.name, &ty, &index)) {
    if (ms_ty_kind(&body->program->types, receiver) == MS_TY_TYPE) {
      MsStrBuild what = ms_strbuild_new();
      ms_strbuild_append_text(&what, "field ");
      ms_strbuild_append(&what, ms_names_span(body->program->names, expr->u.member.name));
      ms_strbuild_append_text(&what, " is hidden");
      (void)body_opaque_denied(body, expr->pos, receiver, ms_strbuild_span(&what));
      ms_strbuild_free(&what);
    }
    body_set_ref(body, expr->id, (MsRef){.kind = MS_REF_FIELD, .index = index, .owner = receiver});
    return ty;
  }
  MsMethodMatchList found = {0};
  ms_check_find_method(body->program, receiver, expr->u.member.name, &found);
  if (found.len != 0) {
    ty = found.ptr[0].ty;
    body_set_ref(body, expr->id, body_method_ref(&found.ptr[0], receiver));
    if (found.ptr[0].entry != NULL && found.ptr[0].entry->source->mutating && !body->quiet && body_reports(body)) {
      const MsExpr *root = expr->u.member.left; /* a temporary receiver has no variable to share */
      const MsLocal *home = root->kind == MS_E_NAME ? body_find_local(body, root->u.sym) : NULL;
      if (home == NULL) {
        report_ownership(body, expr->pos, "a method value that changes its receiver must come from a variable, like `xs.append`; call the method, or write a closure");
      }
    }
    const MsExpr *place = expr->u.member.left;
    if (place->kind == MS_E_NAME && body_find_local(body, place->u.sym) != NULL &&
        takes_element_mutator(&body->program->types, ty, receiver)) {
      report_ownership(body, expr->pos, "this method takes a callback that can change the receiver's elements, so it cannot be used as a value; call it, or write a closure");
    }
  } else {
    body_report_unknown_member(body, expr, receiver);
  }
  ms_method_match_list_free(&found);
  return ty;
}

/* `List[T]`, `Map[K, V]` and the like, from the prelude. */
MsTy body_std_type(Body *body, const char *name, const MsTy *args, size_t count) {
  const MsSymbolId id = resolver_prelude_symbol(body->program, intern(body, name));
  return id == 0 ? MS_TY_NONE : resolver_apply(body->program, body->program->symbols.ptr[id].ty, args, count);
}

static MsTy expected_arg(const Body *body, MsTy expected, MsBuiltin builtin, size_t at) {
  const MsTyTable *types = &body->program->types;
  return expected != MS_TY_NONE && ms_ty_is(types, expected, builtin) && ms_ty_arg_count(types, expected) > at
             ? ms_ty_args(types, expected)[at]
             : MS_TY_NONE;
}

/* A literal holding the bare `none` beside values of one type holds that type optionally: `[none, 0]` is `[Int?]`. */
static MsTy none_widened(Body *body, MsExpr *const *entries, size_t count) {
  bool has_none = false;
  const MsExpr *typed = NULL;
  for (size_t index = 0; index < count; index++) {
    const MsExpr *entry = entries[index];
    const bool none = entry->kind == MS_E_NAME && body_find_local(body, entry->u.sym) == NULL &&
                      ms_span_is_text(ms_names_span(body->program->names, entry->u.sym), "none");
    has_none = has_none || none;
    typed = typed == NULL && !none ? entry : typed;
  }
  if (!has_none || typed == NULL) {
    return MS_TY_NONE;
  }
  const bool quiet = body->quiet;
  body->quiet = true;
  const MsTy value = body_expr(body, typed, MS_TY_NONE);
  body->quiet = quiet;
  if (value == MS_TY_NONE || holds_invalid(&body->program->types, value, 6) ||
      ms_ty_is(&body->program->types, value, MS_BUILTIN_Optional)) {
    return MS_TY_NONE;
  }
  return body_std_type(body, "Optional", &value, 1);
}

static MsTy list_expr(Body *body, const MsExpr *expr, MsTy expected) {
  MsTy element = expected_arg(body, expected, MS_BUILTIN_List, 0);
  if (element != MS_TY_NONE && body_has_foreign_variable(body, element)) {
    element = MS_TY_NONE; /* an open slot of the enclosing call is filled by the entries, not imposed on them */
  }
  if (element == MS_TY_NONE) {
    element = none_widened(body, expr->u.list.ptr, expr->u.list.len);
  }
  bool unknown = false;
  for (uint32_t index = 0; index < expr->u.list.len; index++) {
    MsStrBuild context = ms_strbuild_new();
    ms_strbuild_printf(&context, "entry %zu of the literal, whose entries share one type", (size_t)index + 1);
    const MsTy item = body_expect(body, expr->u.list.ptr[index], element, ms_strbuild_span(&context));
    ms_strbuild_free(&context);
    unknown = unknown || item == MS_TY_NONE;
    element = element == MS_TY_NONE ? item : element;
  }
  if (element == MS_TY_NONE || unknown) {
    return expr->u.list.len == 0 ? expected : MS_TY_NONE; /* an entry of unknown type leaves the literal unknown */
  }
  return body_std_type(body, "List", &element, 1);
}

static MsTy map_expr(Body *body, const MsExpr *expr, MsTy expected) {
  MsTy args[2] = {expected_arg(body, expected, MS_BUILTIN_Map, 0), expected_arg(body, expected, MS_BUILTIN_Map, 1)};
  if (args[1] == MS_TY_NONE && expr->u.map.len != 0) {
    MsExpr **values = MS_ARENA_NEW_ARRAY(&body->program->arena, MsExpr *, expr->u.map.len);
    for (uint32_t index = 0; index < expr->u.map.len; index++) {
      values[index] = expr->u.map.ptr[index].value;
    }
    args[1] = none_widened(body, values, expr->u.map.len);
  }
  for (uint32_t index = 0; index < expr->u.map.len; index++) {
    MsStrBuild context = ms_strbuild_new();
    ms_strbuild_printf(&context, "entry %zu of the literal, whose entries share one type", (size_t)index * 2 + 1);
    const MsTy key = args[0] == MS_TY_NONE ? body_expr(body, expr->u.map.ptr[index].key, args[0])
                                           : body_expect(body, expr->u.map.ptr[index].key, args[0], ms_strbuild_span(&context));
    ms_strbuild_free(&context);
    context = ms_strbuild_new();
    ms_strbuild_printf(&context, "entry %zu of the literal, whose entries share one type", (size_t)index * 2 + 2);
    const MsTy value = args[1] == MS_TY_NONE ? body_expr(body, expr->u.map.ptr[index].value, args[1])
                                             : body_expect(body, expr->u.map.ptr[index].value, args[1], ms_strbuild_span(&context));
    ms_strbuild_free(&context);
    args[0] = args[0] == MS_TY_NONE ? key : args[0];
    args[1] = args[1] == MS_TY_NONE ? value : args[1];
  }
  return args[0] == MS_TY_NONE || args[1] == MS_TY_NONE ? expected : body_std_type(body, "Map", args, 2);
}

/* `generic_function[Args]` named as a value: the function at those type arguments. */
static bool explicit_function_value(Body *body, const MsExpr *expr, MsTy *ty) {
  if (expr->kind != MS_E_APPLY || expr->u.apply.types.len == 0 || expr->u.apply.left->kind != MS_E_NAME ||
      body_find_local(body, expr->u.apply.left->u.sym) != NULL) {
    return false;
  }
  const MsSymbol *symbol = body_find_symbol(body, expr->u.apply.left->u.sym);
  if (symbol == NULL || symbol->kind != MS_SYMBOL_FN || symbol->var_count != expr->u.apply.types.len || symbol->ty == MS_TY_NONE) {
    return false;
  }
  MsTyList args = {0};
  for (uint32_t index = 0; index < expr->u.apply.types.len; index++) {
    ms_ty_list_push(&args, resolver_type(&body->resolver, expr->u.apply.types.ptr[index]));
  }
  const MsRef ref = body_symbol_ref(body, symbol);
  body_set_ref(body, expr->u.apply.left->id, ref);
  body_set_ref(body, expr->id, ref);
  *ty = ms_ty_subst(&body->program->types, symbol->ty, body->program->symbol_vars.ptr + symbol->var_at, args.ptr, args.len);
  ms_ty_list_free(&args);
  return true;
}

/* `receiver.method[Args]` named as a value: the method at those type arguments for its own type variables. */
static bool explicit_method_value(Body *body, const MsExpr *expr, MsTy *ty) {
  const MsExpr *member = expr->kind == MS_E_APPLY ? expr->u.apply.left : NULL;
  if (member == NULL || expr->u.apply.types.len == 0 || member->kind != MS_E_MEMBER) {
    return false;
  }
  const MsTy method = member_expr(body, member, MS_TY_NONE);
  body_set_type(body, member->id, method);
  const MsTy receiver = ms_facts_type(body->facts, member->u.member.left->id);
  MsMethodMatchList found = {0};
  ms_check_find_method(body->program, receiver, member->u.member.name, &found);
  const MsMethodEntry *entry = found.len != 0 ? found.ptr[0].entry : NULL;
  const size_t own = entry != NULL ? entry->variables.len - entry->shared : 0;
  if (entry == NULL || own < expr->u.apply.types.len) {
    ms_method_match_list_free(&found);
    return false;
  }
  MsTyList args = {0};
  for (uint32_t index = 0; index < expr->u.apply.types.len; index++) {
    ms_ty_list_push(&args, resolver_type(&body->resolver, expr->u.apply.types.ptr[index]));
  }
  /* type arguments left out take the method's defaults, which may name the receiver's arguments and earlier ones */
  const MsTyTable *types = &body->program->types;
  MsTyList names = {0};
  MsTyList values = {0};
  for (size_t at = 0; at < entry->shared && at < ms_ty_arg_count(types, receiver); at++) {
    ms_ty_list_push(&names, entry->variables.ptr[at]);
    ms_ty_list_push(&values, ms_ty_args(types, receiver)[at]);
  }
  for (size_t at = 0; at < args.len; at++) {
    ms_ty_list_push(&names, entry->variables.ptr[entry->shared + at]);
    ms_ty_list_push(&values, args.ptr[at]);
  }
  for (size_t at = args.len; at < own; at++) {
    const MsTyVariable *record = ms_ty_variable(&body->program->types, entry->variables.ptr[entry->shared + at]);
    if (record == NULL || record->default_ty == MS_TY_NONE) {
      ms_method_match_list_free(&found);
      ms_ty_list_free(&names);
      ms_ty_list_free(&values);
      ms_ty_list_free(&args);
      return false;
    }
    const MsTy fixed = ms_ty_subst(&body->program->types, record->default_ty, names.ptr, values.ptr, names.len);
    ms_ty_list_push(&args, fixed);
    ms_ty_list_push(&names, entry->variables.ptr[entry->shared + at]);
    ms_ty_list_push(&values, fixed);
  }
  ms_ty_list_free(&names);
  ms_ty_list_free(&values);
  body_set_ref(body, expr->id, *ms_facts_ref(body->facts, member->id));
  *ty = ms_ty_subst(&body->program->types, method, entry->variables.ptr + entry->shared, args.ptr, args.len);
  ms_ty_list_free(&args);
  ms_method_match_list_free(&found);
  return true;
}

static MsTy index_expr(Body *body, const MsExpr *expr) {
  MsExpr *left = NULL;
  MsExpr *index = NULL;
  MsTy function = MS_TY_NONE;
  if (explicit_function_value(body, expr, &function) || explicit_method_value(body, expr, &function)) {
    return function;
  }
  if (!ms_expr_index(expr, &left, &index)) {
    return MS_TY_NONE;
  }
  const MsTyTable *types = &body->program->types;
  const MsTy receiver = body_expr(body, left, MS_TY_NONE);
  if ((receiver == MS_TY_NONE || ms_ty_is_invalid(types, receiver)) && index->kind == MS_E_NAME) {
    return MS_TY_NONE; /* an unresolved receiver was reported; its bracket argument is probably a type argument */
  }
  const bool map = ms_ty_is(types, receiver, MS_BUILTIN_Map) && ms_ty_arg_count(types, receiver) == 2;
  const bool list = ms_ty_is(types, receiver, MS_BUILTIN_List) && ms_ty_arg_count(types, receiver) == 1;
  const MsTy key = map ? ms_ty_args(types, receiver)[0] : body_primitive(body, MS_BUILTIN_Int);
  (void)((list || map || ms_ty_is(types, receiver, MS_BUILTIN_Bytes)) ? body_expect(body, index, key, (MsSpan){0}) : body_expr(body, index, key));
  if (list) {
    body_check_constant_index(body, expr, left, index);
    return ms_ty_args(types, receiver)[0];
  }
  if (map) {
    return ms_ty_args(types, receiver)[1];
  }
  if (ms_ty_is(types, receiver, MS_BUILTIN_Bytes)) {
    return body_primitive(body, MS_BUILTIN_UInt8);
  }
  if (receiver != MS_TY_NONE && !ms_ty_is_invalid(types, receiver) && body_reports(body) &&
      !body->quiet) {
    ms_check_report(body->program, body->module, expr->pos, MS_CHECK_TYPE,
                    ms_string_from_span(ms_span_of_text(
                        ms_ty_is(types, receiver, MS_BUILTIN_String)
                            ? "indexing a String by integer is not supported; use for c in s.chars(), s.scalar_at(offset, "
                              "default) at a byte offset, or s.slice(start, end)"
                            : "indexing requires List[T], Map[K, V] or Bytes; use the receiver's lookup method for other "
                              "types")));
  }
  return MS_TY_NONE;
}

static MsTy probe_expr(Body *body, const MsExpr *expr) {
  if (expr != body->borrowing_probe) {
    report_ownership(body, expr->pos, "`?` after an index is only written as `if var name = place[key]?`, where it borrows the entry in place");
  }
  const MsTy entry = body_expr(body, expr->u.bin.left, MS_TY_NONE);
  return entry == MS_TY_NONE ? MS_TY_NONE : body_std_type(body, "Optional", &entry, 1);
}

/* Whether `ty` mentions a type variable that is not declared by the enclosing function: an inference slot. */
bool body_has_foreign_variable(const Body *body, MsTy ty) {
  const MsTyTable *types = &body->program->types;
  if (!ms_ty_has_variable(types, ty)) {
    return false;
  }
  if (ms_ty_kind(types, ty) == MS_TY_VARIABLE) {
    for (size_t index = 0; index < body->resolver.types.len; index++) {
      if (body->resolver.types.ptr[index] == ty) {
        return false;
      }
    }
    return true;
  }
  for (size_t index = 0; index < ms_ty_arg_count(types, ty); index++) {
    if (body_has_foreign_variable(body, ms_ty_args(types, ty)[index])) {
      return true;
    }
  }
  for (size_t index = 0; index < ms_ty_param_count(types, ty); index++) {
    if (body_has_foreign_variable(body, ms_ty_params(types, ty)[index].ty)) {
      return true;
    }
  }
  return ms_ty_kind(types, ty) == MS_TY_FUNCTION && body_has_foreign_variable(body, ms_ty_result(types, ty));
}

/* The `move`/`var` modes the expected function type gives its parameter: a lambda takes them from its context. */
static uint8_t context_modes(const MsTyTable *types, MsTy expected, bool shaped, uint32_t index) {
  return shaped && index < ms_ty_param_count(types, expected)
             ? (uint8_t)(ms_ty_params(types, expected)[index].flags & (MS_PARAM_VAR | MS_PARAM_MOVE))
             : 0;
}

/* A callback parameter with no written type and no context to take one from. */
static void report_uninferred_callback(Body *body, const MsParam *param) {
  if (!body_reports(body) || body->quiet) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "cannot infer callback parameter ");
  ms_strbuild_append(&text, ms_names_span(body->program->names, param->name));
  ms_strbuild_append_text(&text, "; provide a type or a known function context: a closure bound to a variable has none, "
                                 "so write the parameter types and result, as in `fn(n: Int) Int: n * 2`");
  ms_check_report(body->program, body->module, param->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

/* A lambda: parameters typed from the written annotation or the expected function type; the result is the
 * written result, the expected one, or the first returned value's type. */
static MsTy lambda_expr(Body *body, const MsExpr *expr, MsTy expected) {
  const MsTyTable *types = &body->program->types;
  if (expected != MS_TY_NONE && ms_ty_is(types, expected, MS_BUILTIN_Optional) && ms_ty_arg_count(types, expected) == 1 &&
      ms_ty_kind(types, ms_ty_args(types, expected)[0]) == MS_TY_FUNCTION) {
    expected = ms_ty_args(types, expected)[0]; /* a function literal where an optional function is wanted */
  }
  bool shaped = expected != MS_TY_NONE && ms_ty_kind(types, expected) == MS_TY_FUNCTION;
  bool miscounted = false;
  if (shaped && ms_ty_param_count(types, expected) != expr->u.lambda.params.len) {
    if (body_reports(body) && !body->quiet) {
      const size_t want = ms_ty_param_count(types, expected);
      MsStrBuild text = ms_strbuild_new();
      ms_strbuild_printf(&text, "callback parameter count does not match its context; the context expects %zu parameter%s, "
                                "found %zu, so write exactly the parameters its context declares",
                         want, want == 1 ? "" : "s", (size_t)expr->u.lambda.params.len);
      ms_check_report(body->program, body->module, expr->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
    }
    shaped = false; /* the count error explains why nothing can be inferred */
    miscounted = true;
  }
  MsTyParamList params = {0};
  const size_t mark = body_scope_mark(body);
  for (uint32_t index = 0; index < expr->u.lambda.params.len; index++) {
    const MsParam *param = expr->u.lambda.params.ptr[index];
    for (uint32_t before = 0; !body->quiet && body_reports(body) && before < index; before++) {
      if (expr->u.lambda.params.ptr[before]->name == param->name) {
        MsStrBuild text = ms_strbuild_new();
        ms_strbuild_append_text(&text, "duplicate parameter or field ");
        ms_strbuild_append(&text, ms_names_span(body->program->names, param->name));
        ms_strbuild_append_text(&text, "; each name may appear once, so rename one");
        ms_check_report(body->program, body->module, param->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
        break;
      }
    }
    MsTy ty = param->ty != NULL ? resolver_type(&body->resolver, param->ty) : MS_TY_NONE;
    ty = ty == MS_TY_NONE && shaped && index < ms_ty_param_count(types, expected) ? ms_ty_params(types, expected)[index].ty : ty;
    if (param->ty == NULL && ty != MS_TY_NONE && shaped && body_has_foreign_variable(body, ty)) {
      ty = MS_TY_NONE; /* a context parameter no other argument has fixed yet is no context */
    }
    if (ty == MS_TY_NONE && param->ty == NULL && !miscounted) {
      report_uninferred_callback(body, param);
    }
    MsLocal *local = body_declare(body, param->name, ty, MS_REF_PARAM, param->is_mutable, param->id, param->pos);
    local->id = index;
    body_set_type(body, param->id, ty);
    body_set_ref(body, param->id, body_local_ref(body, local));
    ms_ty_param_list_push(&params, (MsTyParam){.name = param->name, .ty = ty,
                                               .flags = (uint8_t)((param->is_mutable ? MS_PARAM_VAR : 0) |
                                                                  (param->moving ? MS_PARAM_MOVE : 0) |
                                                                  (param->def != NULL ? MS_PARAM_LIFTED : 0) |
                                                                  context_modes(types, expected, shaped, index))});
    if (param->def != NULL) {
      (void)body_expr(body, param->def, ty);
    }
  }
  MsTy result = expr->u.lambda.result != NULL ? resolver_type(&body->resolver, expr->u.lambda.result) : MS_TY_NONE;
  result = result == MS_TY_NONE && shaped && !body_has_foreign_variable(body, ms_ty_result(types, expected))
               ? ms_ty_result(types, expected)
               : result;
  const MsTy saved_result = body->result;
  const MsTy saved_hint = body->hint;
  body->hint = result == MS_TY_NONE && shaped ? ms_ty_result(types, expected) : MS_TY_NONE;
  const MsTy saved_returned = body->returned;
  const MsExpr *const saved_returned_expr = body->returned_expr;
  const bool saved_saw = body->saw_return;
  body->result = result;
  body->returned = MS_TY_NONE;
  body->returned_expr = NULL;
  body->saw_return = false;
  body_block(body, expr->u.lambda.body);
  const bool unknown_return = result == MS_TY_NONE && body->saw_return && body->returned == MS_TY_NONE;
  result = result == MS_TY_NONE ? body->returned : result;
  body->saw_return = saved_saw;
  body->result = saved_result;
  body->hint = saved_hint;
  body->returned = saved_returned;
  body->returned_expr = saved_returned_expr;
  body_scope_reset(body, mark);
  const MsName fn = intern(body, "fn");
  const MsTyDesc desc = {.name = fn, .id = fn, .kind = MS_TY_FUNCTION, .params = params.ptr,
                         .param_count = (uint32_t)params.len,
                         .result = result != MS_TY_NONE || unknown_return ? result : body_primitive(body, MS_BUILTIN_Void)};
  const MsTy ty = ms_ty_intern(&body->program->types, &desc);
  ms_ty_param_list_free(&params);
  return ty;
}

MsTy body_expr(Body *body, const MsExpr *expr, MsTy expected) {
  MsTy ty = MS_TY_NONE;
  switch ((MsExprKind)expr->kind) {
  case MS_E_NUMBER:
  case MS_E_BOOL:
  case MS_E_VOID:
  case MS_E_TEXT:
    ty = body_literal(body, expr, expected);
    break;
  case MS_E_NAME:
    ty = name_expr(body, expr, expected);
    break;
  case MS_E_MEMBER:
    ty = member_expr(body, expr, expected);
    break;
  case MS_E_APPLY:
  case MS_E_INDEX:
    ty = index_expr(body, expr);
    break;
  case MS_E_PROBE:
    ty = probe_expr(body, expr);
    break;
  case MS_E_LIST:
    ty = list_expr(body, expr, expected);
    break;
  case MS_E_MAP:
    ty = map_expr(body, expr, expected);
    break;
  case MS_E_UNARY:
    ty = body_unary(body, expr, expected);
    break;
  case MS_E_BINARY:
    ty = body_binary(body, expr, expected);
    break;
  case MS_E_LAMBDA:
    ty = lambda_expr(body, expr, expected);
    break;
  case MS_E_CALL:
    ty = body_call(body, expr, expected);
    break;
  case MS_E_MATCH:
    ty = body_match(body, expr, expected);
    break;
  }
  body_set_type(body, expr->id, ty);
  body_convert(body, expr, ty, expected);
  return ty;
}

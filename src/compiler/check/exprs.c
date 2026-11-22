/* compiler/check/exprs.c: names, members, applications, lists, maps, indexing and lambdas.
 *
 * body_expr dispatches on the expression kind, records the result in the facts and returns it. Literals and
 * operators live in exprs_ops.c and calls in calls.c. A name resolves to a local or parameter, then a symbol of
 * the module (declared, imported or prelude), then a case of a visible enum. What fails to resolve is invalid;
 * reporting it is the job of the unknown-binding pass. */
#include "compiler/check/body.h"
#include "compiler/check/methods.h"

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
bool body_find_case(Body *body, MsName name, MsTy expected, MsTy *owner, uint32_t *index) {
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
  for (size_t at = 0; at < MS_COUNT_OF(PRELUDE); at++) {
    ms_symbol_list_push(&seen, program->symbols.ptr[resolver_prelude_symbol(program, intern(body, PRELUDE[at]))]);
  }
  bool found = false;
  for (size_t at = 0; at < seen.len && !found; at++) {
    const MsSymbol *symbol = &seen.ptr[at];
    if (symbol->ty == MS_TY_NONE || ms_ty_kind(&program->types, symbol->ty) != MS_TY_ALTERNATIVE) {
      continue;
    }
    found = body_case_of(body, symbol->ty, name, index) != NULL;
    *owner = symbol->ty;
  }
  ms_symbol_list_free(&seen);
  (void)expected;
  return found;
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

static MsTy name_expr(Body *body, const MsExpr *expr, MsTy expected) {
  const MsName name = expr->u.sym;
  const MsLocal *local = body_find_local(body, name);
  if (local != NULL) {
    body_set_ref(body, expr->id, (MsRef){.kind = local->kind, .local = local->id});
    return local->ty;
  }
  const MsSymbol *symbol = body_find_symbol(body, name);
  if (symbol != NULL) {
    const MsRef ref = body_symbol_ref(body, symbol);
    body_set_ref(body, expr->id, ref);
    return ref.kind == MS_REF_CONSTANT ? body_constant_type(body, symbol) : symbol->ty;
  }
  const MsSpan text = ms_names_span(body->program->names, name);
  if (ms_span_is_text(text, "__LINE__")) {
    return body_primitive(body, MS_BUILTIN_Int);
  }
  if (ms_span_is_text(text, "__FILE__")) {
    return body_primitive(body, MS_BUILTIN_String);
  }
  MsTy owner = MS_TY_NONE;
  uint32_t index = 0;
  if (body_find_case(body, name, expected, &owner, &index)) {
    const bool fits = expected != MS_TY_NONE && ms_ty_row(&body->program->types, expected)->id == ms_ty_row(&body->program->types, owner)->id;
    owner = fits ? expected : owner;
    body_set_ref(body, expr->id, (MsRef){.kind = MS_REF_CASE, .index = index, .owner = owner});
    return owner;
  }
  return MS_TY_NONE;
}

/* `Type.Case` or `Type.member` where the left side names a type; false when it does not. */
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
  uint32_t index = 0;
  if (body_case_of(body, owner, expr->u.member.name, &index) != NULL) {
    body_set_ref(body, expr->id, (MsRef){.kind = MS_REF_CASE, .index = index, .owner = owner});
    *ty = owner;
  } else {
    *ty = MS_TY_NONE;
  }
  return true;
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
    body_set_ref(body, expr->id, (MsRef){.kind = MS_REF_FIELD, .index = index, .owner = receiver});
    return ty;
  }
  MsMethodMatchList found = {0};
  ms_check_find_method(body->program, receiver, expr->u.member.name, &found);
  if (found.len != 0) {
    ty = found.ptr[0].ty;
    body_set_ref(body, expr->id, body_method_ref(&found.ptr[0], receiver));
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

static MsTy list_expr(Body *body, const MsExpr *expr, MsTy expected) {
  MsTy element = expected_arg(body, expected, MS_BUILTIN_List, 0);
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
  for (uint32_t index = 0; index < expr->u.map.len; index++) {
    const MsTy key = body_expr(body, expr->u.map.ptr[index].key, args[0]);
    const MsTy value = body_expr(body, expr->u.map.ptr[index].value, args[1]);
    args[0] = args[0] == MS_TY_NONE ? key : args[0];
    args[1] = args[1] == MS_TY_NONE ? value : args[1];
  }
  return args[0] == MS_TY_NONE || args[1] == MS_TY_NONE ? expected : body_std_type(body, "Map", args, 2);
}

static MsTy index_expr(Body *body, const MsExpr *expr) {
  MsExpr *left = NULL;
  MsExpr *index = NULL;
  if (!ms_expr_index(expr, &left, &index)) {
    return MS_TY_NONE;
  }
  const MsTyTable *types = &body->program->types;
  const MsTy receiver = body_expr(body, left, MS_TY_NONE);
  const bool map = ms_ty_is(types, receiver, MS_BUILTIN_Map) && ms_ty_arg_count(types, receiver) == 2;
  const bool list = ms_ty_is(types, receiver, MS_BUILTIN_List) && ms_ty_arg_count(types, receiver) == 1;
  (void)body_expr(body, index, map ? ms_ty_args(types, receiver)[0] : body_primitive(body, MS_BUILTIN_Int));
  if (list) {
    return ms_ty_args(types, receiver)[0];
  }
  if (map) {
    return ms_ty_args(types, receiver)[1];
  }
  return ms_ty_is(types, receiver, MS_BUILTIN_Bytes) ? body_primitive(body, MS_BUILTIN_UInt8) : MS_TY_NONE;
}

static MsTy probe_expr(Body *body, const MsExpr *expr) {
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
  if (body->module >= body->program->user_modules || body->quiet) {
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
  const bool shaped = expected != MS_TY_NONE && ms_ty_kind(types, expected) == MS_TY_FUNCTION;
  MsTyParamList params = {0};
  const size_t mark = body_scope_mark(body);
  for (uint32_t index = 0; index < expr->u.lambda.params.len; index++) {
    const MsParam *param = expr->u.lambda.params.ptr[index];
    MsTy ty = param->ty != NULL ? resolver_type(&body->resolver, param->ty) : MS_TY_NONE;
    ty = ty == MS_TY_NONE && shaped && index < ms_ty_param_count(types, expected) ? ms_ty_params(types, expected)[index].ty : ty;
    if (ty == MS_TY_NONE && param->ty == NULL) {
      report_uninferred_callback(body, param);
    }
    MsLocal *local = body_declare(body, param->name, ty, MS_REF_PARAM, param->is_mutable);
    local->id = index;
    body_set_type(body, param->id, ty);
    body_set_ref(body, param->id, (MsRef){.kind = MS_REF_PARAM, .local = index});
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
  const bool saved_saw = body->saw_return;
  body->result = result;
  body->returned = MS_TY_NONE;
  body->saw_return = false;
  body_block(body, expr->u.lambda.body);
  const bool unknown_return = result == MS_TY_NONE && body->saw_return && body->returned == MS_TY_NONE;
  result = result == MS_TY_NONE ? body->returned : result;
  body->saw_return = saved_saw;
  body->result = saved_result;
  body->hint = saved_hint;
  body->returned = saved_returned;
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

/* compiler/check/bodies.c: walking declarations and statements, and the locals in scope.
 *
 * Every function, impl method, test and constant of a module is typed in order. A parameter is a local of kind
 * MS_REF_PARAM numbered by position (the receiver of a method is parameter 0); every other binding is a local
 * numbered densely from 0 within the enclosing function, lambdas included. Facts recorded: the type of each
 * expression, pattern and parameter node; the reference of each name, binding and loop variable; the number of
 * locals of each function. */
#include "compiler/check/body.h"
#include "compiler/check/methods.h"

void body_set_type(Body *body, MsNode node, MsTy ty) {
  if (node < body->facts->node_count) {
    body->facts->types[node] = ty;
  }
}

void body_set_ref(Body *body, MsNode node, MsRef ref) {
  if (node < body->facts->node_count) {
    body->facts->refs[node] = ref;
  }
}

MsTy body_primitive(Body *body, MsBuiltin builtin) {
  return resolver_primitive(body->program, builtin);
}

size_t body_scope_mark(const Body *body) {
  return body->locals.len;
}

void body_scope_reset(Body *body, size_t mark) {
  ms_local_list_truncate(&body->locals, mark);
}

MsLocal *body_declare(Body *body, MsName name, MsTy ty, MsRefKind kind, bool is_var) {
  MsLocal local = {.name = name, .ty = ty, .kind = kind, .is_var = is_var};
  local.id = kind == MS_REF_LOCAL ? body->next_local++ : 0;
  ms_local_list_push(&body->locals, local);
  return ms_local_list_last(&body->locals);
}

const MsLocal *body_find_local(const Body *body, MsName name) {
  for (size_t index = body->locals.len; index > 0; index--) {
    if (body->locals.ptr[index - 1].name == name) {
      return &body->locals.ptr[index - 1];
    }
  }
  return NULL;
}

/* The type a loop variable takes from the iterated type: a list's element, a set's member, or what the
 * iterator's `next` yields. */
static MsTy element_type(Body *body, MsTy iterable) {
  const MsTyTable *types = &body->program->types;
  if ((ms_ty_is(types, iterable, MS_BUILTIN_List) || ms_ty_is(types, iterable, MS_BUILTIN_Set)) &&
      ms_ty_arg_count(types, iterable) == 1) {
    return ms_ty_args(types, iterable)[0];
  }
  if (ms_ty_is(types, iterable, MS_BUILTIN_Map) && ms_ty_arg_count(types, iterable) == 2) {
    return body_std_type(body, "MapEntry", ms_ty_args(types, iterable), 2); /* a map yields its entries */
  }
  MsMethodMatchList found = {0};
  const MsName next = ms_names_intern(body->program->names, ms_span_of_text("next"));
  ms_check_find_method(body->program, iterable, next, &found);
  MsTy element = MS_TY_NONE;
  if (found.len != 0) {
    const MsTy result = ms_ty_result(types, found.ptr[0].ty);
    if (ms_ty_is(types, result, MS_BUILTIN_Optional) && ms_ty_arg_count(types, result) == 1) {
      element = ms_ty_args(types, result)[0];
    }
  }
  ms_method_match_list_free(&found);
  return element;
}

/* Declares the names of a binding pattern; `ty` is the type the whole pattern matches. */
static void bind_pattern(Body *body, const MsPattern *pattern, MsTy ty, bool is_var) {
  body_set_type(body, pattern->id, ty);
  if (pattern->kind == MS_P_NAME) {
    const MsLocal *local = body_declare(body, pattern->u.name, ty, MS_REF_LOCAL, is_var);
    body_set_ref(body, pattern->id, (MsRef){.kind = MS_REF_LOCAL, .local = local->id});
    return;
  }
  if (pattern->kind == MS_P_LIST) {
    const MsTyTable *types = &body->program->types;
    const MsTy element = ms_ty_is(types, ty, MS_BUILTIN_List) && ms_ty_arg_count(types, ty) == 1
                             ? ms_ty_args(types, ty)[0]
                             : MS_TY_NONE;
    for (uint32_t index = 0; index < pattern->u.list.len; index++) {
      bind_pattern(body, pattern->u.list.ptr[index], element, is_var);
    }
    return;
  }
  for (uint32_t index = 0; index < pattern->u.fields.len; index++) {
    const MsPatternField *field = &pattern->u.fields.ptr[index];
    MsTy field_ty = MS_TY_NONE;
    uint32_t at = 0;
    if (ty != MS_TY_NONE) {
      (void)body_field(body, ty, field->name, &field_ty, &at);
    }
    bind_pattern(body, field->pattern, field_ty, is_var);
  }
}

static void stmt_bind(Body *body, const MsStmt *stmt) {
  const MsTy declared = stmt->u.bind.ty != NULL ? resolver_type(&body->resolver, stmt->u.bind.ty) : MS_TY_NONE;
  MsStrBuild context = ms_strbuild_new();
  if (stmt->u.bind.pattern->kind == MS_P_NAME) {
    ms_strbuild_append_text(&context, "the initializer of '");
    ms_strbuild_append(&context, ms_names_span(body->program->names, stmt->u.bind.pattern->u.name));
    ms_strbuild_append_text(&context, "'");
  }
  const MsTy value = body_expect(body, stmt->u.bind.value, declared, ms_strbuild_span(&context));
  ms_strbuild_free(&context);
  const MsTy kept = stmt->u.bind.is_mutable ? value : body_lifted_function(body, stmt->u.bind.value, value);
  bind_pattern(body, stmt->u.bind.pattern, declared != MS_TY_NONE ? declared : kept, stmt->u.bind.is_mutable);
}

/* `x.field = ...` needs a field of a type value; a method, a case or an unknown member cannot be assigned. */
static void check_field_target(Body *body, const MsExpr *target) {
  const MsRef *ref = ms_facts_ref(body->facts, target->id);
  if (target->kind != MS_E_MEMBER || (ref != NULL && ref->kind == MS_REF_FIELD) ||
      body->module >= body->program->user_modules || body->quiet) {
    return;
  }
  ms_check_report(body->program, body->module, target->pos, MS_CHECK_TYPE,
                  ms_string_from_span(ms_span_of_text("assignment requires a type field; only fields of a type value can be assigned "
                                      "with 'x.field = ...'")));
}

static void stmt_assign(Body *body, const MsStmt *stmt) {
  MsTy target = MS_TY_NONE;
  if (stmt->u.assign.target != NULL) {
    target = body_expr(body, stmt->u.assign.target, MS_TY_NONE);
    check_field_target(body, stmt->u.assign.target);
  } else {
    const MsLocal *local = body_find_local(body, stmt->u.assign.name);
    if (local != NULL) {
      target = local->ty;
      body_set_ref(body, stmt->id, (MsRef){.kind = local->kind, .local = local->id});
    }
  }
  body_set_type(body, stmt->id, target);
  (void)body_expect(body, stmt->u.assign.value, target, (MsSpan){0});
}

/* The payload an `if x := expr:` binding takes from the tested value. */
static MsTy payload_type(const Body *body, MsTy tested) {
  const MsTyTable *types = &body->program->types;
  const bool wraps = ms_ty_is(types, tested, MS_BUILTIN_Optional) || ms_ty_is(types, tested, MS_BUILTIN_Result);
  return wraps && ms_ty_arg_count(types, tested) >= 1 ? ms_ty_args(types, tested)[0] : tested;
}

static void stmt_if(Body *body, const MsStmt *stmt) {
  const MsTy cond = stmt->u.branch.binding != NULL
                        ? body_expr(body, stmt->u.branch.cond, MS_TY_NONE)
                        : body_expect(body, stmt->u.branch.cond, body_primitive(body, MS_BUILTIN_Bool), ms_span_of_text("an if condition"));
  const size_t mark = body_scope_mark(body);
  if (stmt->u.branch.binding != NULL) {
    bind_pattern(body, stmt->u.branch.binding, payload_type(body, cond), stmt->u.branch.is_mutable);
  }
  body_block(body, stmt->u.branch.body);
  body_scope_reset(body, mark);
  body_block(body, stmt->u.branch.else_body);
}

static void stmt_for(Body *body, const MsStmt *stmt) {
  const MsTy iterable = body_expr(body, stmt->u.each.iter, MS_TY_NONE);
  const MsTy element = element_type(body, iterable);
  const size_t mark = body_scope_mark(body);
  const MsLocal *local = body_declare(body, stmt->u.each.name, element, MS_REF_LOCAL, false);
  body_set_ref(body, stmt->id, (MsRef){.kind = MS_REF_LOCAL, .local = local->id});
  body_set_type(body, stmt->id, element);
  body_block(body, stmt->u.each.body);
  body_scope_reset(body, mark);
}

static void statement(Body *body, const MsStmt *stmt) {
  switch ((MsStmtKind)stmt->kind) {
  case MS_S_BIND:
    stmt_bind(body, stmt);
    break;
  case MS_S_ASSIGN:
    stmt_assign(body, stmt);
    break;
  case MS_S_CALL:
    (void)body_expr(body, stmt->u.expr, MS_TY_NONE);
    break;
  case MS_S_RETURN:
    if (stmt->u.expr != NULL) {
      body->saw_return = true;
      const MsTy returned = body->result == MS_TY_NONE && body->hint != MS_TY_NONE
                                ? body_expr(body, stmt->u.expr, body->hint)
                                : body_expect(body, stmt->u.expr, body->result, ms_span_of_text("the return value"));
      body->returned = body->returned == MS_TY_NONE ? returned : body->returned;
    }
    break;
  case MS_S_IF:
    stmt_if(body, stmt);
    break;
  case MS_S_WHILE:
    (void)body_expect(body, stmt->u.loop.cond, body_primitive(body, MS_BUILTIN_Bool), ms_span_of_text("a while condition"));
    body_block(body, stmt->u.loop.body);
    break;
  case MS_S_FOR:
    stmt_for(body, stmt);
    break;
  case MS_S_BREAK:
  case MS_S_CONTINUE:
    break;
  }
}

void body_block(Body *body, MsStmts stmts) {
  const size_t mark = body_scope_mark(body);
  for (uint32_t index = 0; index < stmts.len; index++) {
    statement(body, stmts.ptr[index]);
  }
  body_scope_reset(body, mark);
}

/* ---- declarations ---- */

/* Declares a function's parameters; `first` is the index of the first written parameter (1 after a receiver). */
static void declare_params(Body *body, MsParams params, MsTy fn_ty, uint32_t first) {
  const MsTyTable *types = &body->program->types;
  const size_t count = ms_ty_param_count(types, fn_ty);
  for (uint32_t index = 0; index < params.len; index++) {
    const MsParam *param = params.ptr[index];
    const MsTy ty = index < count ? ms_ty_params(types, fn_ty)[index].ty : MS_TY_NONE;
    MsLocal *local = body_declare(body, param->name, ty, MS_REF_PARAM, param->is_mutable);
    local->id = first + index;
    body_set_type(body, param->id, ty);
    body_set_ref(body, param->id, (MsRef){.kind = MS_REF_PARAM, .local = local->id});
  }
}

/* Checks parameter defaults, then the body, of one callable; records its local count under `node`. */
static void callable(Body *body, MsNode node, MsParams params, MsStmts stmts) {
  for (uint32_t index = 0; index < params.len; index++) {
    if (params.ptr[index]->def != NULL) {
      (void)body_expr(body, params.ptr[index]->def, params.ptr[index]->ty != NULL ? resolver_type(&body->resolver, params.ptr[index]->ty) : MS_TY_NONE);
    }
  }
  body_block(body, stmts);
  body->facts->local_counts[node] = body->next_local;
}

static void function_decl(Body *body, const MsSymbol *symbol) {
  const MsFunc *func = &symbol->decl->u.fn;
  const size_t mark = body->resolver.names.len;
  resolver_enter_symbol(&body->resolver, symbol);
  body->result = ms_ty_result(&body->program->types, symbol->ty);
  declare_params(body, func->params, symbol->ty, 0);
  callable(body, symbol->decl->id, func->params, func->body);
  ms_name_list_truncate(&body->resolver.names, mark);
  ms_ty_list_truncate(&body->resolver.types, mark);
}

static const MsMethodEntry *find_entry(const MsCheckProgram *program, const MsMethod *method) {
  for (size_t index = 0; index < program->methods.len; index++) {
    if (program->methods.ptr[index].source == method) {
      return &program->methods.ptr[index];
    }
  }
  return NULL;
}

static void method_decl(Body *body, const MsMethod *method) {
  const MsMethodEntry *entry = find_entry(body->program, method);
  if (entry == NULL) {
    return;
  }
  const size_t mark = body->resolver.names.len;
  for (size_t index = 0; index < entry->variables.len; index++) {
    ms_name_list_push(&body->resolver.names, ms_ty_row(&body->program->types, entry->variables.ptr[index])->name);
    ms_ty_list_push(&body->resolver.types, entry->variables.ptr[index]);
  }
  body->resolver.self = entry->receiver;
  body->self_ty = entry->receiver;
  body->result = ms_ty_result(&body->program->types, entry->ty);
  const MsName self = ms_names_intern(body->program->names, ms_span_of_text("self"));
  (void)body_declare(body, self, entry->receiver, MS_REF_PARAM, method->mutating);
  declare_params(body, method->func.params, entry->ty, 1);
  callable(body, method->id, method->func.params, method->func.body);
  body->resolver.self = MS_TY_NONE;
  body->self_ty = MS_TY_NONE;
  ms_name_list_truncate(&body->resolver.names, mark);
  ms_ty_list_truncate(&body->resolver.types, mark);
}

static const MsSymbol *symbol_of(const MsCheckProgram *program, uint32_t module, const MsDecl *decl) {
  for (MsSymbolId id = 1; id < program->symbols.len; id++) {
    if (program->symbols.ptr[id].module == module && program->symbols.ptr[id].decl == decl) {
      return &program->symbols.ptr[id];
    }
  }
  return NULL;
}

/* Types the default expressions of a type's fields or an enum case's payload slots. */
static void field_defaults(Body *body, MsParams fields, const MsSymbol *owner) {
  const MsDef *def = owner != NULL && owner->ty != MS_TY_NONE ? body_def(body, owner->ty) : NULL;
  const size_t mark = body->resolver.names.len;
  const size_t scope = body_scope_mark(body);
  if (owner != NULL) {
    resolver_enter_symbol(&body->resolver, owner);
  }
  for (uint32_t index = 0; index < fields.len; index++) {
    const MsParam *field = fields.ptr[index];
    const MsTy ty = def != NULL && index < def->fields.len
                        ? def->fields.ptr[index].ty
                        : (field->ty != NULL ? resolver_type(&body->resolver, field->ty) : MS_TY_NONE);
    if (field->def != NULL) {
      (void)body_expr(body, field->def, ty);
    }
    /* A default may use the fields before it, which it reads as the constructor's arguments. */
    MsLocal *local = body_declare(body, field->name, ty, MS_REF_PARAM, false);
    local->id = index;
  }
  body_scope_reset(body, scope);
  ms_name_list_truncate(&body->resolver.names, mark);
  ms_ty_list_truncate(&body->resolver.types, mark);
}

static void declaration(Body *body, const MsDecl *decl) {
  body->next_local = 0;
  body->result = MS_TY_NONE;
  switch ((MsDeclKind)decl->kind) {
  case MS_D_FN: {
    const MsSymbol *symbol = symbol_of(body->program, body->module, decl);
    if (symbol != NULL && symbol->ty != MS_TY_NONE) {
      function_decl(body, symbol);
    }
    break;
  }
  case MS_D_IMPL:
    for (uint32_t index = 0; index < decl->u.impl.methods.len; index++) {
      body->next_local = 0;
      method_decl(body, decl->u.impl.methods.ptr[index]);
    }
    break;
  case MS_D_TEST: {
    /* A test returns `Void!`: `return error(...)` fails it. */
    const MsTy error = body_std_type(body, "Error", NULL, 0);
    const MsTy args[2] = {body_primitive(body, MS_BUILTIN_Void), error};
    body->result = error == MS_TY_NONE ? MS_TY_NONE : body_std_type(body, "Result", args, 2);
    /* With a valid `make_fixture` factory in the module, `fixture` names its value: a `var` parameter of the test. */
    const size_t mark = body_scope_mark(body);
    if (body->fixture_ty != MS_TY_NONE && !decl->u.test.bench) {
      const MsName fixture = ms_names_intern(body->program->names, ms_span_of_text("fixture"));
      (void)body_declare(body, fixture, body->fixture_ty, MS_REF_PARAM, true);
    }
    body_block(body, decl->u.test.body);
    body_scope_reset(body, mark);
    body->result = MS_TY_NONE;
    body->facts->local_counts[decl->id] = body->next_local;
    break;
  }
  case MS_D_CONST: {
    body->quiet = true;
    body->resolver.report = false; /* a constant's annotation is reported with the constant's own diagnostics */
    const MsTy declared = decl->u.konst.ty != NULL ? resolver_type(&body->resolver, decl->u.konst.ty) : MS_TY_NONE;
    (void)body_expr(body, decl->u.konst.value, declared);
    body->resolver.report = body->module < body->program->user_modules;
    body->quiet = false;
    break;
  }
  case MS_D_TYPE:
    field_defaults(body, decl->u.type.fields, symbol_of(body->program, body->module, decl));
    break;
  case MS_D_ENUM:
    for (uint32_t index = 0; index < decl->u.enumeration.cases.len; index++) {
      field_defaults(body, decl->u.enumeration.cases.ptr[index]->fields, NULL);
    }
    break;
  case MS_D_ALIAS:
  case MS_D_INTERFACE:
    break;
  }
}

/* The type of a module constant: its annotation, else the type of its initializer, found once in the declaring
 * module's own context and kept on the symbol. */
MsTy body_constant_type(const Body *body, const MsSymbol *symbol) {
  static int depth = 0;
  MsCheckProgram *program = body->program;
  MsSymbol *own = &program->symbols.ptr[symbol - program->symbols.ptr];
  if (own->ty != MS_TY_NONE || depth >= 8 || symbol->decl == NULL || symbol->decl->kind != MS_D_CONST) {
    return own->ty;
  }
  const MsModuleInfo *info = &program->modules.ptr[symbol->module];
  MsFacts scratch = {0};
  ms_facts_init(&scratch, &program->arena, symbol->module, info->tree->node_count);
  Body inner = {.program = program, .module = symbol->module, .facts = &scratch, .quiet = true};
  resolver_init(&inner.resolver, program, symbol->module);
  inner.resolver.report = false;
  depth++;
  const MsDecl *decl = symbol->decl;
  MsTy ty = decl->u.konst.ty != NULL ? resolver_type(&inner.resolver, decl->u.konst.ty) : MS_TY_NONE;
  ty = ty != MS_TY_NONE ? ty : body_expr(&inner, decl->u.konst.value, MS_TY_NONE);
  depth--;
  resolver_free(&inner.resolver);
  ms_local_list_free(&inner.locals);
  own->ty = ty;
  return ty;
}

static bool has_test(const MsModule *tree) {
  for (uint32_t index = 0; index < tree->ndecls; index++) {
    if (tree->decls[index]->kind == MS_D_TEST) {
      return true;
    }
  }
  return false;
}

void ms_check_bodies(MsCheckProgram *program, uint32_t module, MsSpan source) {
  MsModuleInfo *info = &program->modules.ptr[module];
  ms_facts_init(&info->facts, &program->arena, module, info->tree->node_count);
  Body body = {.program = program, .module = module, .facts = &info->facts, .source = source};
  resolver_init(&body.resolver, program, module);
  if (has_test(info->tree)) {
    ms_check_test_fixture(&body);
  }
  for (uint32_t index = 0; index < info->tree->ndecls; index++) {
    declaration(&body, info->tree->decls[index]);
    body_scope_reset(&body, 0);
  }
  ms_facts_finish(&info->facts);
  resolver_free(&body.resolver);
  ms_local_list_free(&body.locals);
}

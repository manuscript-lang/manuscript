/* compiler/check/bodies.c: walking declarations and statements, and the locals in scope.
 *
 * Every function, impl method, test and constant of a module is typed in order. A parameter is a local of kind
 * MS_REF_PARAM numbered by position (the receiver of a method is parameter 0); every other binding is a local
 * numbered densely from 0 within the enclosing function, lambdas included. Facts recorded: the type of each
 * expression, pattern and parameter node; the reference of each name, binding and loop variable; the number of
 * locals of each function. */
#include "compiler/check/body.h"
#include "compiler/check/call_internal.h"
#include "compiler/syntax/walk.h"
#include "compiler/check/methods.h"
#include "compiler/check/suggest.h"

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

MsRef body_local_ref(const Body *body, const MsLocal *local) {
  return (MsRef){.kind = local->kind, .local = local->id, .decl = {body->module, local->site}};
}

MsLocal *body_declare(Body *body, MsName name, MsTy ty, MsRefKind kind, bool is_var, MsNode site, MsPos pos) {
  ms_local_record_list_push(&body->program->bindings, (MsLocalRecord){.module = body->module, .name = name, .ty = ty, .pos = pos});
  MsLocal local = {.name = name, .ty = ty, .kind = kind, .is_var = is_var, .site = site};
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
/* Whether a diagnostic of this module already sits inside `value`. */
static bool rejected_value(const Body *body, const MsExpr *value) {
  const uint32_t start = ms_expr_start(value).offset;
  for (size_t index = 0; index < body->program->diagnostics.len; index++) {
    const MsCheckDiag *diag = &body->program->diagnostics.ptr[index];
    if (diag->module == body->module && diag->pos.offset >= start && diag->pos.offset < value->end.offset) {
      return true;
    }
  }
  return false;
}

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
    MsTy result = ms_ty_result(types, found.ptr[0].ty);
    if (ms_ty_is(types, result, MS_BUILTIN_Result) && ms_ty_arg_count(types, result) == 2) {
      result = ms_ty_args(types, result)[0]; /* a stream's `next` may fail: the loop reads the items of its ok value */
    }
    if (ms_ty_is(types, result, MS_BUILTIN_Optional) && ms_ty_arg_count(types, result) == 1) {
      element = ms_ty_args(types, result)[0];
    }
  }
  ms_method_match_list_free(&found);
  return element;
}

static void report_pattern(Body *body, MsPos pos, const char *text) {
  if (body->module < body->program->user_modules && !body->quiet) {
    ms_check_report(body->program, body->module, pos, MS_CHECK_TYPE, ms_string_from_span(ms_span_of_text(text)));
  }
}

static void bind_fields(Body *body, const MsPattern *pattern, MsTy ty, bool is_var);

/* Declares the names of a binding pattern; `ty` is the type the whole pattern matches and `source` the written value
 * when it is a literal whose shape is known. */
static void bind_pattern_from(Body *body, const MsPattern *pattern, MsTy ty, bool is_var, const MsExpr *source) {
  const MsTyTable *types = &body->program->types;
  body_set_type(body, pattern->id, ty);
  if (pattern->kind == MS_P_NAME) {
    const MsLocal *local = body_declare(body, pattern->u.name, ty, MS_REF_LOCAL, is_var, pattern->id, pattern->pos);
    body_set_ref(body, pattern->id, body_local_ref(body, local));
    return;
  }
  const bool known = ty != MS_TY_NONE && !holds_invalid(&body->program->types, ty, 6);
  if (pattern->kind == MS_P_LIST) {
    const bool list = ms_ty_is(types, ty, MS_BUILTIN_List) && ms_ty_arg_count(types, ty) == 1;
    if (known && !list) {
      report_pattern(body, pattern->pos, "positional binding requires a list; use [a, b] patterns only with List values");
      return;
    }
    if (list && source != NULL && source->kind == MS_E_LIST && source->u.list.len != pattern->u.list.len) {
      report_pattern(body, pattern->pos, "statically known list length does not match binding; bind exactly as many names "
                                         "as the list has elements");
    }
    const MsTy element = list ? ms_ty_args(types, ty)[0] : MS_TY_NONE;
    for (uint32_t index = 0; index < pattern->u.list.len; index++) {
      bind_pattern_from(body, pattern->u.list.ptr[index], element, is_var, NULL);
    }
    return;
  }
  if (known && (ms_ty_kind(types, ty) != MS_TY_TYPE || ms_ty_builtin(types, ty) != MS_BUILTIN_NONE)) {
    report_pattern(body, pattern->pos, "type binding requires a type; destructure only type values, or bind the whole value to one name");
    return;
  }
  bind_fields(body, pattern, ty, is_var);
}

static void bind_fields(Body *body, const MsPattern *pattern, MsTy ty, bool is_var) {
  static const char what[] = "its fields cannot be destructured here";
  if (ty != MS_TY_NONE && body_opaque_denied(body, pattern->pos, ty, ms_span_of_text(what))) {
    /* the opaque type keeps its fields private; the names below still bind */
  }
  const MsDef *def = ty == MS_TY_NONE ? NULL : body_def(body, ty);
  for (uint32_t index = 0; index < pattern->u.fields.len; index++) {
    const MsPatternField *field = &pattern->u.fields.ptr[index];
    for (uint32_t before = 0; before < index; before++) {
      if (pattern->u.fields.ptr[before].name == field->name) {
        MsStrBuild text = ms_strbuild_new();
        ms_strbuild_append_text(&text, "duplicate type field ");
        ms_strbuild_append(&text, ms_names_span(body->program->names, field->name));
        ms_strbuild_append_text(&text, "; bind each field once");
        if (body->module < body->program->user_modules && !body->quiet) {
          ms_check_report(body->program, body->module, field->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
        }
        break;
      }
    }
    MsTy field_ty = MS_TY_NONE;
    uint32_t at = 0;
    const bool found = ty != MS_TY_NONE && body_field(body, ty, field->name, &field_ty, &at);
    if (!found && def != NULL && ty != MS_TY_NONE && !holds_invalid(&body->program->types, ty, 6)) {
      MsSpanList names = {0};
      for (size_t each = 0; each < def->fields.len; each++) {
        ms_span_list_push(&names, ms_names_span(body->program->names, def->fields.ptr[each].name));
      }
      MsStrBuild text = ms_strbuild_new();
      ms_strbuild_append_text(&text, "unknown type field ");
      ms_strbuild_append(&text, ms_names_span(body->program->names, field->name));
      ms_strbuild_append_text(&text, "; fields: ");
      ms_suggest_list(&text, &names, 12);
      ms_span_list_free(&names);
      if (body->module < body->program->user_modules && !body->quiet) {
        ms_check_report(body->program, body->module, field->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
      }
    }
    bind_pattern_from(body, field->pattern, found ? field_ty : MS_TY_NONE, is_var, NULL);
  }
}

static void bind_pattern(Body *body, const MsPattern *pattern, MsTy ty, bool is_var) {
  bind_pattern_from(body, pattern, ty, is_var, NULL);
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
  if (stmt->u.bind.ty == NULL && body_is_none_type(body, value)) {
    body_report_uninferred_none(body, stmt->u.bind.value->pos); /* a binding with no type has no target for none */
  }
  const MsTy kept = stmt->u.bind.is_mutable ? value : body_lifted_function(body, stmt->u.bind.value, value);
  bind_pattern_from(body, stmt->u.bind.pattern, declared != MS_TY_NONE ? declared : kept, stmt->u.bind.is_mutable,
                    stmt->u.bind.value);
  if (stmt->u.bind.pattern->kind == MS_P_NAME && stmt->u.bind.ty != NULL && stmt->u.bind.ty->kind == MS_TYPE_FN) {
    ms_local_list_last(&body->locals)->written_fn = true;
  }
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
      body_set_ref(body, stmt->id, body_local_ref(body, local));
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
  if (element == MS_TY_NONE && iterable != MS_TY_NONE && !holds_invalid(&body->program->types, iterable, 6) &&
      ms_ty_kind(&body->program->types, iterable) != MS_TY_VARIABLE && body->module < body->program->user_modules &&
      !body->quiet) {
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append_text(&text, "for requires List, Set, Map, a ReadStream, or an Iterator, found ");
    ms_ty_show(&text, body->program->names, &body->program->types, iterable);
    ms_strbuild_append_text(&text, "; iterate a collection, e.g. a list literal [1, 2, 3], or implement ReadStream with "
                                   "'var fn next() T?!' and 'var fn close() Void!', or Iterator with 'var fn next() T?'");
    ms_check_report(body->program, body->module, stmt->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  }
  const size_t mark = body_scope_mark(body);
  const MsLocal *local = body_declare(body, stmt->u.each.name, element, MS_REF_LOCAL, false, stmt->id, stmt->pos);
  body_set_ref(body, stmt->id, body_local_ref(body, local));
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
    body_check_call_statement(body, stmt, body_expr(body, stmt->u.expr, MS_TY_NONE));
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
/* A default value must fit the type of the parameter or field it is for. */
static MsTy body_default(Body *body, const MsExpr *value, MsTy declared) {
  return declared == MS_TY_NONE ? body_expr(body, value, declared) : body_expect(body, value, declared, (MsSpan){0});
}

/* Each required parameter or field that follows an optional one; a `T?` parameter or field defaults to none. */
static void report_optionals_last(Body *body, MsParams params) {
  uint32_t first = 0;
  while (first < params.len && !body_param_omittable(body, params.ptr[first])) {
    first++;
  }
  if (first == params.len || body->module >= body->program->user_modules || body->quiet) {
    return;
  }
  const MsParam *optional = params.ptr[first];
  const bool by_type = optional->ty != NULL && optional->ty->kind == MS_TYPE_NAMED && optional->ty->args.len == 1 &&
                       ms_span_is_text(ms_names_span(body->program->names, optional->ty->name), "Optional");
  for (uint32_t index = first + 1; index < params.len; index++) {
    if (body_param_omittable(body, params.ptr[index])) {
      continue;
    }
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append_text(&text, "required ");
    ms_strbuild_append(&text, ms_names_span(body->program->names, params.ptr[index]->name));
    ms_strbuild_append_text(&text, " follows optional ");
    ms_strbuild_append(&text, ms_names_span(body->program->names, optional->name));
    ms_strbuild_append_text(&text, by_type ? " (a `T?` parameter or field defaults to none, so it counts as optional)" : "");
    ms_strbuild_append_text(&text, "; put optional parameters and fields last");
    ms_check_report(body->program, body->module, params.ptr[index]->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  }
}

/* Declares the parameters in order and checks each default before its own parameter is in scope, so a default sees
 * the parameters before it and a function of the same name as its own parameter (`headers: H = headers()`). */
static void declare_params(Body *body, MsParams params, MsTy fn_ty, uint32_t first) {
  report_optionals_last(body, params);
  const MsTyTable *types = &body->program->types;
  const size_t count = ms_ty_param_count(types, fn_ty);
  for (uint32_t index = 0; index < params.len; index++) {
    const MsParam *param = params.ptr[index];
    if (param->def != NULL) {
      const MsTy declared = param->ty != NULL ? resolver_type(&body->resolver, param->ty) : MS_TY_NONE;
      (void)body_default(body, param->def, declared);
    }
    const MsTy ty = index < count ? ms_ty_params(types, fn_ty)[index].ty : MS_TY_NONE;
    MsLocal *local = body_declare(body, param->name, ty, MS_REF_PARAM, param->is_mutable, param->id, param->pos);
    local->id = first + index;
    local->written_fn = param->ty != NULL && param->ty->kind == MS_TYPE_FN;
    body_set_type(body, param->id, ty);
    body_set_ref(body, param->id, body_local_ref(body, local));
  }
}

/* Checks the body of one callable; records its local count under `node`. */
static void callable(Body *body, MsNode node, MsParams params, MsStmts stmts) {
  (void)params;
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
  (void)body_declare(body, self, entry->receiver, MS_REF_PARAM, method->mutating, method->id, method->pos);
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
    /* A field without a default is reported with its declaration, not here (an enum case's variables are not in scope). */
    const bool report = body->resolver.report;
    body->resolver.report = report && field->def != NULL;
    const MsTy ty = def != NULL && index < def->fields.len
                        ? def->fields.ptr[index].ty
                        : (field->ty != NULL ? resolver_type(&body->resolver, field->ty) : MS_TY_NONE);
    body->resolver.report = report;
    if (field->def != NULL) {
      (void)body_default(body, field->def, ty);
    }
    /* A default may use the fields before it, which it reads as the constructor's arguments. */
    MsLocal *local = body_declare(body, field->name, ty, MS_REF_PARAM, false, field->id, field->pos);
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
    if (symbol != NULL && symbol->ty != MS_TY_NONE && decl->u.fn.external) {
      body_check_extern(body, decl, symbol->ty);
    } else if (symbol != NULL && symbol->ty != MS_TY_NONE) {
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
      (void)body_declare(body, fixture, body->fixture_ty, MS_REF_PARAM, true, decl->id, decl->pos);
    }
    body_block(body, decl->u.test.body);
    body_scope_reset(body, mark);
    body->result = MS_TY_NONE;
    body->facts->local_counts[decl->id] = body->next_local;
    break;
  }
  case MS_D_CONST: {
    /* The constants pass reported an initializer it rejects; the oracle then leaves the annotation alone. */
    body->resolver.report = body->resolver.report && !rejected_value(body, decl->u.konst.value);
    const MsTy declared = decl->u.konst.ty != NULL ? resolver_type(&body->resolver, decl->u.konst.ty) : MS_TY_NONE;
    body->resolver.report = body->module < body->program->user_modules;
    body->quiet = true; /* the initializer is reported by the constants pass */
    (void)body_expr(body, decl->u.konst.value, declared);
    body->quiet = false;
    body_report_decimal_literals(body, decl->u.konst.value);
    break;
  }
  case MS_D_TYPE:
    report_optionals_last(body, decl->u.type.fields);
    field_defaults(body, decl->u.type.fields, symbol_of(body->program, body->module, decl));
    break;
  case MS_D_ENUM:
    for (uint32_t index = 0; index < decl->u.enumeration.cases.len; index++) {
      field_defaults(body, decl->u.enumeration.cases.ptr[index]->fields, NULL);
    }
    break;
  case MS_D_INTERFACE:
    if (decl->u.iface.methods.len == 0 && body->module < body->program->user_modules && !body->quiet) {
      ms_check_report(body->program, body->module, decl->pos, MS_CHECK_TYPE,
                      ms_string_from_span(ms_span_of_text("an interface declares at least one operation; only the standard "
                                                          "library declares a property without operations, like `Data`")));
    }
    break;
  case MS_D_ALIAS:
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

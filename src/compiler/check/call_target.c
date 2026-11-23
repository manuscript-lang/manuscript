/* compiler/check/call_target.c: the callee of a call.
 *
 * The callee decides the signature: a function or closure, a method found for the receiver's type, a record
 * constructor, or an enum case with a payload. The target records the signature, the type variables to infer,
 * the declared parameters (names and defaults), and how a method takes its receiver. calls.c matches the
 * arguments against it. */
#include "compiler/check/call_internal.h"

#include <string.h>
#include "compiler/check/instantiate.h"
#include "compiler/check/methods.h"
#include "compiler/syntax/parse.h"

void body_target_free(Target *target) {
  ms_ty_list_free(&target->vars);
  ms_ty_list_free(&target->explicit_args);
  ms_ty_list_free(&target->outer_vars);
  ms_ty_list_free(&target->outer_args);
  ms_strbuild_free(&target->name_text);
}

/* A function type with these parameters returning `result`. */
MsTy body_call_function_type(Body *body, const MsTyParamList *params, MsTy result) {
  const MsName fn = ms_names_intern(body->program->names, ms_span_of_text("fn"));
  const MsTyDesc desc = {.name = fn, .id = fn, .kind = MS_TY_FUNCTION, .params = params->ptr,
                         .param_count = (uint32_t)params->len, .result = result};
  return ms_ty_intern(&body->program->types, &desc);
}

static void copy_vars(Target *target, const MsTy *vars, size_t count) {
  for (size_t index = 0; index < count; index++) {
    ms_ty_list_push(&target->vars, vars[index]);
  }
}

/* A constructor: the fields (or payload slots) of `owner` are the parameters, the result is `owner`. */
static void constructor_target(Body *body, Target *target, MsTy owner, const MsTyParamList *fields) {
  target->constructor = true;
  target->nominal = owner;
  target->sig = body_call_function_type(body, fields, owner);
  const MsDef *def = body_def(body, owner);
  if (def != NULL) {
    copy_vars(target, def->variables.ptr, def->variables.len);
  }
}

static bool symbol_target(Body *body, const MsSymbol *symbol, Target *target) {
  target->ref = body_symbol_ref(body, symbol);
  if (symbol->kind == MS_SYMBOL_TYPE) {
    const MsDef *def = body_def(body, symbol->ty);
    const MsTyKind kind = ms_ty_kind(&body->program->types, symbol->ty);
    if (def == NULL || (kind != MS_TY_TYPE && kind != MS_TY_NATIVE)) {
      return false;
    }
    MsTyParamList values = {0};
    if (kind == MS_TY_NATIVE && ms_ty_is(&body->program->types, symbol->ty, MS_BUILTIN_Set) && def->variables.len == 1) {
      /* `Set([1, 2])`: the optional list of the members */
      const MsTy list = body_std_type(body, "List", def->variables.ptr, 1);
      ms_ty_param_list_push(&values, (MsTyParam){.name = ms_names_intern(body->program->names, ms_span_of_text("values")),
                                                 .ty = list, .flags = MS_PARAM_LIFTED});
    }
    constructor_target(body, target, symbol->ty, values.len != 0 ? &values : &def->fields);
    ms_ty_param_list_free(&values);
    target->builtin = kind == MS_TY_NATIVE;
    if (symbol->decl != NULL && symbol->decl->kind == MS_D_TYPE) {
      target->ast = &symbol->decl->u.type.fields;
      target->ast_module = symbol->module;
    }
    return true;
  }
  if (symbol->ty == MS_TY_NONE || ms_ty_kind(&body->program->types, symbol->ty) != MS_TY_FUNCTION) {
    return false;
  }
  target->sig = symbol->ty;
  const MsSpan written = ms_names_span(body->program->names, symbol->name);
  target->constructor = symbol->module >= body->program->user_modules &&
                        (ms_span_is_text(written, "ok") || ms_span_is_text(written, "error") ||
                         ms_span_is_text(written, "some"));
  copy_vars(target, body->program->symbol_vars.ptr + symbol->var_at, symbol->var_count);
  if (symbol->decl != NULL && symbol->decl->kind == MS_D_FN) {
    target->ast = &symbol->decl->u.fn.params;
    target->ast_module = symbol->module;
  }
  return true;
}

static bool case_target(Body *body, const MsExpr *callee, MsName name, MsTy owner, Target *target) {
  uint32_t index = 0;
  const MsTyCase *kase = body_case_of(body, owner, name, &index);
  if (kase == NULL) {
    return false;
  }
  target->ref = (MsRef){.kind = MS_REF_CASE, .index = index, .owner = owner};
  constructor_target(body, target, owner, &kase->fields);
  const MsSymbol *home = &body->program->symbols.ptr[body_def(body, owner)->symbol];
  if (home->decl != NULL && home->decl->kind == MS_D_ENUM && index < home->decl->u.enumeration.cases.len) {
    target->ast = &home->decl->u.enumeration.cases.ptr[index]->fields;
    target->ast_module = home->module;
  }
  body_set_ref(body, callee->id, target->ref);
  return true;
}

/* The parameters of the function or method a value names, whose defaults a function value keeps. */
static const MsParams *lifted_params(Body *body, const MsExpr *value, MsTy ty, uint32_t *module) {
  *module = body->module;
  if (value->kind == MS_E_APPLY) { /* `value.ok_or[Error]`: the specialization keeps the method's defaults */
    return lifted_params(body, value->u.apply.left, MS_TY_NONE, module);
  }
  if (value->kind == MS_E_MEMBER) {
    const bool quiet = body->quiet;
    body->quiet = true;
    const MsTy receiver = body_expr(body, value->u.member.left, MS_TY_NONE);
    body->quiet = quiet;
    MsMethodMatchList found = {0};
    const MsParams *ast = NULL;
    if (receiver != MS_TY_NONE) {
      ms_check_find_method(body->program, receiver, value->u.member.name, &found);
    }
    if (found.len == 1 && (ty == MS_TY_NONE || found.ptr[0].ty == ty) && found.ptr[0].entry != NULL) {
      ast = &found.ptr[0].entry->source->func.params;
      *module = found.ptr[0].entry->module;
    }
    ms_method_match_list_free(&found);
    return ast;
  }
  if (value->kind == MS_E_LAMBDA) {
    return &value->u.lambda.params;
  }
  const MsSymbol *symbol = value->kind == MS_E_NAME && body_find_local(body, value->u.sym) == NULL
                               ? body_find_symbol(body, value->u.sym)
                               : NULL;
  if (symbol == NULL || symbol->decl == NULL || symbol->decl->kind != MS_D_FN || (ty != MS_TY_NONE && ty != symbol->ty)) {
    return NULL;
  }
  *module = symbol->module;
  return &symbol->decl->u.fn.params;
}

const MsParams *body_function_params(Body *body, const MsExpr *value, MsTy ty, uint32_t *module) {
  const MsTyTable *types = &body->program->types;
  return ty != MS_TY_NONE && ms_ty_kind(types, ty) == MS_TY_FUNCTION
             ? lifted_params(body, value, value->kind == MS_E_APPLY ? MS_TY_NONE : ty, module)
             : NULL;
}

/* The parameter names of the interface operation a method value names: a native method keeps no source to read. */
const MsParams *body_function_names(Body *body, const MsExpr *value, MsTy ty) {
  if (value->kind == MS_E_APPLY) {
    return body_function_names(body, value->u.apply.left, MS_TY_NONE);
  }
  if (value->kind != MS_E_MEMBER) {
    return NULL;
  }
  const bool quiet = body->quiet;
  body->quiet = true;
  const MsTy receiver = body_expr(body, value->u.member.left, MS_TY_NONE);
  body->quiet = quiet;
  MsMethodMatchList found = {0};
  const MsParams *names = NULL;
  if (receiver != MS_TY_NONE) {
    ms_check_find_method(body->program, receiver, value->u.member.name, &found);
  }
  if (found.len == 1 && (ty == MS_TY_NONE || found.ptr[0].ty == ty) && found.ptr[0].entry == NULL &&
      found.ptr[0].operation != NULL) {
    const MsMethod *declared = ms_check_operation_declaration(body->program, found.ptr[0].contract, found.ptr[0].operation);
    names = declared == NULL ? NULL : &declared->func.params;
  }
  ms_method_match_list_free(&found);
  return names;
}

MsTy body_lifted_function(Body *body, const MsExpr *value, MsTy ty) {
  const MsTyTable *types = &body->program->types;
  uint32_t module = 0;
  const MsParams *ast = value->kind == MS_E_LAMBDA ? NULL : body_function_params(body, value, ty, &module);
  if (ast == NULL) {
    return ty;
  }
  MsTyParamList params = {0};
  bool lifted = false;
  for (size_t index = 0; index < ms_ty_param_count(types, ty); index++) {
    MsTyParam param = ms_ty_params(types, ty)[index];
    if (index < ast->len && body_param_omittable(body, ast->ptr[index])) {
      param.flags |= MS_PARAM_LIFTED;
      lifted = true;
    }
    ms_ty_param_list_push(&params, param);
  }
  const MsTy result = lifted ? body_call_function_type(body, &params, ms_ty_result(types, ty)) : ty;
  ms_ty_param_list_free(&params);
  return result;
}

static bool name_target(Body *body, const MsExpr *callee, MsTy expected, Target *target) {
  const MsLocal *local = body_find_local(body, callee->u.sym);
  if (local != NULL) {
    target->ref = body_local_ref(body, local);
    body_set_ref(body, callee->id, target->ref); /* a call of a function value reads the local */
    target->sig = local->ty;
    target->ast = local->fn_params;
    target->names = local->fn_names;
    target->ast_module = local->fn_module;
    return local->ty != MS_TY_NONE && ms_ty_kind(&body->program->types, local->ty) == MS_TY_FUNCTION;
  }
  const MsSymbol *symbol = body_find_symbol(body, callee->u.sym);
  if (symbol == NULL && body->resolver.self != MS_TY_NONE &&
      ms_span_is_text(ms_names_span(body->program->names, callee->u.sym), "Self")) {
    /* `Self(...)` in a method builds the receiver's own type */
    const MsDef *home = body_def(body, body->resolver.self);
    symbol = home != NULL && ms_ty_kind(&body->program->types, body->resolver.self) == MS_TY_TYPE
                 ? &body->program->symbols.ptr[home->symbol]
                 : NULL;
  }
  if (symbol != NULL) {
    body_set_ref(body, callee->id, body_symbol_ref(body, symbol));
    return symbol_target(body, symbol, target);
  }
  MsTy owner = MS_TY_NONE;
  uint32_t index = 0;
  return body_find_case(body, callee->u.sym, expected, &callee->pos, &owner, &index) &&
         case_target(body, callee, callee->u.sym, owner, target);
}

/* Whether a call of `nargs` arguments fills the parameters of `match`. */
static bool fits_arguments(const Body *body, const MsMethodMatch *match, size_t nargs) {
  const size_t total = ms_ty_param_count(&body->program->types, match->ty);
  size_t required = 0;
  for (size_t at = 0; at < total; at++) {
    const MsTyParam *param = &ms_ty_params(&body->program->types, match->ty)[at];
    const MsParams *ast = match->entry != NULL ? &match->entry->source->func.params : NULL;
    if (ast == NULL && match->operation != NULL) {
      const MsMethod *declared = ms_check_operation_declaration(body->program, match->contract, match->operation);
      ast = declared == NULL ? NULL : &declared->func.params;
    }
    const bool defaulted = (param->flags & MS_PARAM_LIFTED) != 0 || (ast != NULL ? at < ast->len && body_param_omittable(body, ast->ptr[at])
                                                                       : ms_ty_is(&body->program->types, param->ty, MS_BUILTIN_Optional));
    required += defaulted ? 0 : 1;
  }
  return nargs >= required && nargs <= total;
}

/* The match whose parameters a call of `nargs` arguments fills; the first when none does. */
static const MsMethodMatch *pick_overload(const Body *body, const MsMethodMatchList *found, size_t nargs) {
  for (size_t index = 0; index < found->len; index++) {
    if (fits_arguments(body, &found->ptr[index], nargs)) {
      return &found->ptr[index];
    }
  }
  return &found->ptr[0];
}

/* More than one implementation provides the member for this many arguments: reports it and answers true. */
static bool report_ambiguous(Body *body, const MsExpr *callee, MsTy receiver, const MsMethodMatchList *found,
                             size_t nargs) {
  size_t fitting = 0;
  for (size_t index = 0; index < found->len; index++) {
    fitting += fits_arguments(body, &found->ptr[index], nargs) ? 1 : 0;
  }
  if (fitting < 2 || !body_reports(body) || body->quiet) {
    return fitting >= 2;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "ambiguous member ");
  ms_strbuild_append(&text, ms_names_span(body->program->names, callee->u.member.name));
  ms_strbuild_append_text(&text, " on ");
  ms_ty_show(&text, body->program->names, &body->program->types, receiver);
  ms_strbuild_append_text(&text, "; more than one implementation provides it");
  ms_check_report(body->program, body->module, callee->pos, MS_CHECK_RESOLUTION, ms_strbuild_finish(&text));
  return true;
}

/* The method a member name calls: `m[key] = value` is `m.add(key, value)` and `xs[i] = value` is `xs.set(i, value)`. */
static MsName called_name(Body *body, const MsExpr *callee, MsTy receiver) {
  const MsSpan text = ms_names_span(body->program->names, callee->u.member.name);
  if (!ms_span_is_text(text, MS_INDEX_SET)) {
    return callee->u.member.name;
  }
  const bool map = ms_ty_is(&body->program->types, receiver, MS_BUILTIN_Map);
  return ms_names_intern(body->program->names, ms_span_of_text(map ? "add" : "set"));
}

/* A method of the receiver's type or an operation of its interface. */
static bool method_target(Body *body, const MsExpr *callee, MsTy receiver, Target *target) {
  MsMethodMatchList found = {0};
  ms_check_find_method(body->program, receiver, called_name(body, callee, receiver), &found);
  bool ok = found.len != 0;
  if (ok && report_ambiguous(body, callee, receiver, &found, target->nargs)) {
    ms_method_match_list_free(&found);
    body_set_ref(body, callee->id, target->ref);
    return false;
  }
  if (ok) {
    const MsMethodMatch *match = pick_overload(body, &found, target->nargs);
    target->sig = match->ty;
    target->receiver = callee->u.member.left;
    target->ref = body_method_ref(match, receiver);
    if (match->entry != NULL) {
      target->ast = &match->entry->source->func.params;
      target->ast_module = match->entry->module;
      target->receiver_flags = (uint8_t)((match->entry->source->mutating ? MS_PARAM_VAR : 0) |
                                         (match->entry->source->consuming ? MS_PARAM_MOVE : 0));
      copy_vars(target, match->entry->variables.ptr + match->entry->shared,
                match->entry->variables.len - match->entry->shared);
      for (size_t at = 0; at < match->entry->shared && at < ms_ty_arg_count(&body->program->types, receiver); at++) {
        ms_ty_list_push(&target->outer_vars, match->entry->variables.ptr[at]);
        ms_ty_list_push(&target->outer_args, ms_ty_args(&body->program->types, receiver)[at]);
      }
    } else if (match->operation != NULL) {
      const MsMethod *declared = ms_check_operation_declaration(body->program, match->contract, match->operation);
      target->receiver_flags = declared == NULL ? 0 : (uint8_t)((declared->mutating ? MS_PARAM_VAR : 0) |
                                                                (declared->consuming ? MS_PARAM_MOVE : 0));
      copy_vars(target, match->operation->variables.ptr, match->operation->variables.len);
      const MsDef *home = match->contract != MS_TY_NONE ? body_def(body, match->contract) : NULL;
      for (size_t at = 0; home != NULL && at < home->variables.len && at < ms_ty_arg_count(&body->program->types, match->contract); at++) {
        ms_ty_list_push(&target->outer_vars, home->variables.ptr[at]);
        ms_ty_list_push(&target->outer_args, ms_ty_args(&body->program->types, match->contract)[at]);
      }
      if (declared != NULL) { /* the parameter names come from the declaration: shapes shared by operations carry one set */
        target->names = &declared->func.params;
      }
    }
  }
  ms_method_match_list_free(&found);
  if (!ok) {
    body_report_unknown_member(body, callee, receiver);
  }
  body_set_ref(body, callee->id, target->ref);
  return ok;
}

static bool member_target(Body *body, const MsExpr *callee, Target *target) {
  const MsExpr *left = callee->u.member.left;
  /* `Type[Args].Case(...)`: the arguments are the type's explicit type arguments. */
  if (left->kind == MS_E_APPLY && left->u.apply.left->kind == MS_E_NAME && left->u.apply.types.len != 0 &&
      body_find_local(body, left->u.apply.left->u.sym) == NULL) {
    const MsSymbol *symbol = body_find_symbol(body, left->u.apply.left->u.sym);
    if (symbol != NULL && symbol->kind == MS_SYMBOL_TYPE) {
      for (uint32_t index = 0; index < left->u.apply.types.len; index++) {
        ms_ty_list_push(&target->explicit_args, resolver_type(&body->resolver, left->u.apply.types.ptr[index]));
      }
      body_set_ref(body, left->u.apply.left->id, body_symbol_ref(body, symbol));
      body_set_ref(body, left->id, body_symbol_ref(body, symbol));
      body_set_type(body, left->id, symbol->ty);
      return !body_report_type_member(body, callee->pos, symbol->ty, callee->u.member.name, true) &&
             case_target(body, callee, callee->u.member.name, symbol->ty, target);
    }
  }
  if (left->kind == MS_E_NAME && body_find_local(body, left->u.sym) == NULL) {
    const MsSymbol *symbol = body_find_symbol(body, left->u.sym);
    if (symbol != NULL && symbol->kind == MS_SYMBOL_TYPE) {
      body_set_ref(body, left->id, body_symbol_ref(body, symbol));
      body_set_type(body, left->id, symbol->ty);
      return !body_report_type_member(body, callee->pos, symbol->ty, callee->u.member.name, true) &&
             case_target(body, callee, callee->u.member.name, symbol->ty, target);
    }
  }
  const MsTy receiver = body_expr(body, left, MS_TY_NONE);
  MsTy field = MS_TY_NONE;
  uint32_t index = 0;
  if (body_field(body, receiver, callee->u.member.name, &field, &index)) {
    target->sig = field;
    target->ref = (MsRef){.kind = MS_REF_FIELD, .index = index, .owner = receiver};
    body_set_ref(body, callee->id, target->ref);
    return ms_ty_kind(&body->program->types, field) == MS_TY_FUNCTION;
  }
  return method_target(body, callee, receiver, target);
}

/* `f[T]` or `Type[T]` with explicit type arguments: the bracket reads as types, or as a value that names a
 * declared function or type rather than a local. */
static bool is_type_apply(Body *body, const MsExpr *callee) {
  if (callee->kind != MS_E_APPLY) {
    return false;
  }
  const MsExpr *left = callee->u.apply.left;
  if (callee->u.apply.value != NULL && left->kind == MS_E_MEMBER) {
    /* `xs.map[String](f)`: a method named with type arguments, not a field indexed by a value */
    const bool quiet = body->quiet;
    body->quiet = true;
    const MsTy receiver = body_expr(body, left->u.member.left, MS_TY_NONE);
    body->quiet = quiet;
    MsTy field = MS_TY_NONE;
    uint32_t at = 0;
    MsMethodMatchList found = {0};
    if (receiver != MS_TY_NONE && !body_field(body, receiver, left->u.member.name, &field, &at)) {
      ms_check_find_method(body->program, receiver, left->u.member.name, &found);
    }
    const bool method = found.len != 0;
    ms_method_match_list_free(&found);
    return method;
  }
  return callee->u.apply.value == NULL ||
         (left->kind == MS_E_NAME && body_find_local(body, left->u.sym) == NULL &&
          body_find_symbol(body, left->u.sym) != NULL);
}

bool body_resolve_target(Body *body, const MsExpr *callee, MsTy expected, Target *target) {
  if (is_type_apply(body, callee)) {
    for (uint32_t index = 0; index < callee->u.apply.types.len; index++) {
      ms_ty_list_push(&target->explicit_args, resolver_type(&body->resolver, callee->u.apply.types.ptr[index]));
    }
    const bool ok = body_resolve_target(body, callee->u.apply.left, expected, target);
    body_set_type(body, callee->id, target->sig);
    return ok;
  }
  if (callee->kind == MS_E_NAME) {
    return name_target(body, callee, expected, target);
  }
  if (callee->kind == MS_E_MEMBER) {
    return member_target(body, callee, target);
  }
  target->sig = body_expr(body, callee, MS_TY_NONE);
  target->ref = (MsRef){0};
  return target->sig != MS_TY_NONE && ms_ty_kind(&body->program->types, target->sig) == MS_TY_FUNCTION;
}

/* A constructor or case call of an opaque type outside its module. */
void body_deny_opaque_build(Body *body, const MsExpr *call, const Target *target) {
  if (target->nominal == MS_TY_NONE) {
    return;
  }
  if (target->ref.kind != MS_REF_CASE) {
    (void)body_opaque_denied(body, call->pos, target->nominal, ms_span_of_text("it cannot be constructed here"));
    return;
  }
  const MsExpr *callee = call->u.call.callee;
  const MsName name = callee->kind == MS_E_MEMBER ? callee->u.member.name : callee->u.sym;
  MsStrBuild what = ms_strbuild_new();
  ms_strbuild_append_text(&what, "case ");
  ms_strbuild_append(&what, ms_names_span(body->program->names, name));
  ms_strbuild_append_text(&what, " cannot be built here");
  (void)body_opaque_denied(body, call->pos, target->nominal, ms_strbuild_span(&what));
  ms_strbuild_free(&what);
}

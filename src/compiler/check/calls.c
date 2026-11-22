/* compiler/check/calls.c: typing a call and recording its fact.
 *
 * The callee decides the signature: a function or closure, a method found for the receiver's type, a record
 * constructor, or an enum case with a payload. Arguments are matched to parameters (labels first, then
 * position), typed against the parameter types as far as inference has bound them, and the call's type
 * arguments come from ms_check_instantiate. The MsCall fact lists one argument per parameter, the receiver
 * first for a method: written, defaulted, or omitted. */
#include "compiler/check/body.h"
#include "compiler/check/instantiate.h"
#include "compiler/check/methods.h"

typedef struct Target {
  MsRef ref;
  MsTy sig;               /* the function type called, receiver already bound */
  MsTyList vars;          /* owned: the type variables to infer, in declaration order */
  const MsParams *ast;    /* the declared parameters (for defaults), or NULL */
  uint32_t ast_module;
  const MsExpr *receiver; /* the written receiver of a method call */
  MsStrBuild name_text;   /* owned: the callee as written, `values.map` */
  MsSpan name;
  MsTyList explicit_args; /* owned: written type arguments */
} Target;

static void target_free(Target *target) {
  ms_ty_list_free(&target->vars);
  ms_ty_list_free(&target->explicit_args);
  ms_strbuild_free(&target->name_text);
}

/* A function type with these parameters returning `result`. */
static MsTy function_type(Body *body, const MsTyParamList *params, MsTy result) {
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
  target->sig = function_type(body, fields, owner);
  const MsDef *def = body_def(body, owner);
  if (def != NULL) {
    copy_vars(target, def->variables.ptr, def->variables.len);
  }
}

static bool symbol_target(Body *body, const MsSymbol *symbol, Target *target) {
  target->ref = body_symbol_ref(body, symbol);
  if (symbol->kind == MS_SYMBOL_TYPE) {
    const MsDef *def = body_def(body, symbol->ty);
    if (def == NULL || ms_ty_kind(&body->program->types, symbol->ty) != MS_TY_TYPE) {
      return false;
    }
    constructor_target(body, target, symbol->ty, &def->fields);
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

static bool name_target(Body *body, const MsExpr *callee, MsTy expected, Target *target) {
  const MsLocal *local = body_find_local(body, callee->u.sym);
  if (local != NULL) {
    target->ref = (MsRef){.kind = local->kind, .local = local->id};
    target->sig = local->ty;
    return local->ty != MS_TY_NONE && ms_ty_kind(&body->program->types, local->ty) == MS_TY_FUNCTION;
  }
  const MsSymbol *symbol = body_find_symbol(body, callee->u.sym);
  if (symbol != NULL) {
    body_set_ref(body, callee->id, body_symbol_ref(body, symbol));
    return symbol_target(body, symbol, target);
  }
  MsTy owner = MS_TY_NONE;
  uint32_t index = 0;
  return body_find_case(body, callee->u.sym, expected, &owner, &index) &&
         case_target(body, callee, callee->u.sym, owner, target);
}

/* A method of the receiver's type or an operation of its interface. */
static bool method_target(Body *body, const MsExpr *callee, MsTy receiver, Target *target) {
  MsMethodMatchList found = {0};
  ms_check_find_method(body->program, receiver, callee->u.member.name, &found);
  bool ok = found.len != 0;
  if (ok) {
    const MsMethodMatch *match = &found.ptr[0];
    target->sig = match->ty;
    target->receiver = callee->u.member.left;
    target->ref = body_method_ref(match, receiver);
    if (match->entry != NULL) {
      target->ast = &match->entry->source->func.params;
      target->ast_module = match->entry->module;
      copy_vars(target, match->entry->variables.ptr + match->entry->shared,
                match->entry->variables.len - match->entry->shared);
    } else if (match->operation != NULL) {
      copy_vars(target, match->operation->variables.ptr, match->operation->variables.len);
    }
  }
  ms_method_match_list_free(&found);
  body_set_ref(body, callee->id, target->ref);
  return ok;
}

static bool member_target(Body *body, const MsExpr *callee, Target *target) {
  const MsExpr *left = callee->u.member.left;
  if (left->kind == MS_E_NAME && body_find_local(body, left->u.sym) == NULL) {
    const MsSymbol *symbol = body_find_symbol(body, left->u.sym);
    if (symbol != NULL && symbol->kind == MS_SYMBOL_TYPE) {
      body_set_ref(body, left->id, body_symbol_ref(body, symbol));
      body_set_type(body, left->id, symbol->ty);
      return case_target(body, callee, callee->u.member.name, symbol->ty, target);
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
  return callee->u.apply.value == NULL ||
         (left->kind == MS_E_NAME && body_find_local(body, left->u.sym) == NULL &&
          body_find_symbol(body, left->u.sym) != NULL);
}

static bool resolve_target(Body *body, const MsExpr *callee, MsTy expected, Target *target) {
  if (is_type_apply(body, callee)) {
    for (uint32_t index = 0; index < callee->u.apply.types.len; index++) {
      ms_ty_list_push(&target->explicit_args, resolver_type(&body->resolver, callee->u.apply.types.ptr[index]));
    }
    const bool ok = resolve_target(body, callee->u.apply.left, expected, target);
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

/* ---- arguments ---- */

typedef struct Matched {
  int32_t *slot; /* the argument written for each parameter, or -1 */
  size_t count;
} Matched;

static bool param_index(const MsTyTable *types, MsTy sig, MsName name, size_t *index) {
  for (size_t at = 0; at < ms_ty_param_count(types, sig); at++) {
    if (ms_ty_params(types, sig)[at].name == name) {
      *index = at;
      return true;
    }
  }
  return false;
}

/* Assigns each written argument a parameter: by label, else the next free one in order. */
static void match_args(const MsTyTable *types, MsTy sig, const MsExpr *call, Matched *matched) {
  const size_t nparams = ms_ty_param_count(types, sig);
  size_t cursor = 0;
  for (uint32_t at = 0; at < call->u.call.args.len; at++) {
    const MsArg *arg = &call->u.call.args.ptr[at];
    size_t index = 0;
    if (arg->has_name && param_index(types, sig, arg->name, &index)) {
      matched->slot[index] = (int32_t)at;
      continue;
    }
    while (cursor < nparams && matched->slot[cursor] >= 0) {
      cursor++;
    }
    if (cursor < nparams) {
      matched->slot[cursor] = (int32_t)at;
    }
  }
}

/* The parameter type with the variables bound so far substituted. */
static MsTy expected_param(Body *body, const Target *target, MsTy param, const MsTy *bound) {
  size_t known = 0;
  MsTy vars[16];
  MsTy args[16];
  for (size_t index = 0; index < target->vars.len && index < 16; index++) {
    if (bound[index] != MS_TY_NONE) {
      vars[known] = target->vars.ptr[index];
      args[known++] = bound[index];
    }
  }
  return known == 0 ? param : ms_ty_subst(&body->program->types, param, vars, args, known);
}

/* Whether `ty` mentions one of the callee's own variables (an inference slot not yet bound). */
static bool mentions_vars(const MsTyTable *types, MsTy ty, const MsTyList *vars) {
  if (!ms_ty_has_variable(types, ty)) {
    return false;
  }
  for (size_t index = 0; index < vars->len; index++) {
    if (vars->ptr[index] == ty) {
      return true;
    }
  }
  for (size_t index = 0; index < ms_ty_arg_count(types, ty); index++) {
    if (mentions_vars(types, ms_ty_args(types, ty)[index], vars)) {
      return true;
    }
  }
  for (size_t index = 0; index < ms_ty_param_count(types, ty); index++) {
    if (mentions_vars(types, ms_ty_params(types, ty)[index].ty, vars)) {
      return true;
    }
  }
  return ms_ty_kind(types, ty) == MS_TY_FUNCTION && mentions_vars(types, ms_ty_result(types, ty), vars);
}

/* Types the written arguments in parameter order; returns the type of each parameter's argument. */
static void type_args(Body *body, const Target *target, const MsExpr *call, const Matched *matched, MsTy *arg_tys,
                      MsTy *bound) {
  const MsTyTable *types = &body->program->types;
  for (size_t index = 0; index < matched->count; index++) {
    if (matched->slot[index] < 0) {
      continue;
    }
    const MsTy param = ms_ty_params(types, target->sig)[index].ty;
    const MsArg *arg = &call->u.call.args.ptr[matched->slot[index]];
    MsStrBuild context = ms_strbuild_new();
    if (target->name.len != 0) {
      ms_strbuild_append_text(&context, "argument '");
      ms_strbuild_append(&context, ms_names_span(body->program->names, ms_ty_params(types, target->sig)[index].name));
      ms_strbuild_append_text(&context, "' of ");
      ms_strbuild_append(&context, target->name);
    }
    const MsTy wanted = expected_param(body, target, param, bound);
    arg_tys[index] = mentions_vars(types, wanted, &target->vars)
                         ? body_expr(body, arg->value, wanted)
                         : body_expect(body, arg->value, wanted, ms_strbuild_span(&context));
    ms_strbuild_free(&context);
    if (target->vars.len != 0 && target->vars.len <= 16 && arg_tys[index] != MS_TY_NONE) {
      (void)ms_check_unify(types, param, arg_tys[index], target->vars.ptr, target->vars.len, bound);
    }
  }
  /* An argument checked while the callee's variables were open meets its final parameter type only now. */
  for (size_t index = 0; index < matched->count; index++) {
    if (matched->slot[index] < 0 || arg_tys[index] == MS_TY_NONE) {
      continue;
    }
    const MsTy param = ms_ty_params(types, target->sig)[index].ty;
    if (mentions_vars(types, param, &target->vars)) {
      body_convert(body, call->u.call.args.ptr[matched->slot[index]].value, arg_tys[index],
                   expected_param(body, target, param, bound));
    }
  }
}

/* One MsCallArg per parameter (the receiver first): written, defaulted or omitted. */
static MsCallArg *build_args(Body *body, const Target *target, const MsExpr *call, const Matched *matched,
                             uint32_t *count) {
  const MsTyTable *types = &body->program->types;
  const size_t offset = target->receiver != NULL ? 1 : 0;
  MsCallArg *args = MS_ARENA_NEW_ARRAY(&body->program->arena, MsCallArg, matched->count + offset);
  if (offset != 0) {
    args[0] = (MsCallArg){.source = MS_ARG_WRITTEN, .node = {body->module, target->receiver->id}};
  }
  for (size_t index = 0; index < matched->count; index++) {
    const MsTyParam *param = &ms_ty_params(types, target->sig)[index];
    MsCallArg *out = &args[index + offset];
    out->flags = param->flags & (MS_PARAM_VAR | MS_PARAM_MOVE);
    const MsExpr *def = target->ast != NULL && index < target->ast->len ? target->ast->ptr[index]->def : NULL;
    if (matched->slot[index] >= 0) {
      const MsArg *arg = &call->u.call.args.ptr[matched->slot[index]];
      *out = (MsCallArg){.source = MS_ARG_WRITTEN, .node = {body->module, arg->value->id},
                         .label = arg->has_name ? arg->name : 0, .flags = out->flags};
    } else if (def != NULL) {
      *out = (MsCallArg){.source = MS_ARG_DEFAULT, .node = {target->ast_module, def->id}, .flags = out->flags};
    } else {
      out->source = MS_ARG_OMITTED;
    }
  }
  *count = (uint32_t)(matched->count + offset);
  return args;
}

static MsTy record_call(Body *body, const MsExpr *call, const Target *target, MsTy instantiated, const MsTyList *type_args_list,
                        const Matched *matched) {
  MsCall fact = {.node = call->id, .callee = target->ref, .callee_ty = instantiated};
  fact.args = build_args(body, target, call, matched, &fact.arg_count);
  if (type_args_list->len != 0) {
    MsTy *copy = MS_ARENA_NEW_ARRAY(&body->program->arena, MsTy, type_args_list->len);
    for (size_t index = 0; index < type_args_list->len; index++) {
      copy[index] = type_args_list->ptr[index];
    }
    fact.type_args = copy;
    fact.type_arg_count = (uint32_t)type_args_list->len;
  }
  ms_facts_add_call(body->facts, &fact);
  return ms_ty_result(&body->program->types, instantiated);
}

static MsTy finish_call(Body *body, const MsExpr *call, Target *target, const MsTy *arg_tys, const Matched *matched,
                        MsTy expected) {
  MsInstance instance = {0};
  MsTy sig = target->sig;
  bool instantiated = true;
  if (target->vars.len != 0) {
    const MsSpan name = target->name;
    if (ms_check_instantiate(body->program, target->sig, target->vars.ptr, target->vars.len, name,
                             target->explicit_args.ptr, target->explicit_args.len, arg_tys, matched->count, expected,
                             &instance)) {
      sig = instance.ty;
    } else {
      instantiated = false;
    }
  }
  MsTy result = record_call(body, call, target, sig, &instance.args, matched);
  body_set_type(body, call->u.call.callee->id, sig);
  ms_instance_free(&instance);
  return instantiated ? result : MS_TY_NONE;
}

/* The callee as written: `f`, `values.map`; empty for any other expression. */
static void append_callee_name(const Body *body, MsStrBuild *out, const MsExpr *callee) {
  if (callee->kind == MS_E_NAME) {
    ms_strbuild_append(out, ms_names_span(body->program->names, callee->u.sym));
  } else if (callee->kind == MS_E_MEMBER) {
    append_callee_name(body, out, callee->u.member.left);
    ms_strbuild_append_text(out, ms_strbuild_length(out) != 0 ? "." : "");
    ms_strbuild_append(out, ms_names_span(body->program->names, callee->u.member.name));
  } else if (callee->kind == MS_E_APPLY) {
    append_callee_name(body, out, callee->u.apply.left);
  }
}

MsTy body_call(Body *body, const MsExpr *expr, MsTy expected) {
  Target target = {0};
  MsTy result = MS_TY_NONE;
  const MsExpr *callee = expr->u.call.callee;
  target.name_text = ms_strbuild_new();
  append_callee_name(body, &target.name_text, callee);
  target.name = ms_strbuild_span(&target.name_text);
  if (resolve_target(body, callee, expected, &target)) {
    const size_t count = ms_ty_param_count(&body->program->types, target.sig);
    Matched matched = {.slot = MS_ARENA_NEW_ARRAY(&body->program->arena, int32_t, count + 1), .count = count};
    MsTy *arg_tys = MS_ARENA_NEW_ARRAY(&body->program->arena, MsTy, count + 1);
    MsTy *bound = MS_ARENA_NEW_ARRAY(&body->program->arena, MsTy, target.vars.len + 1);
    for (size_t index = 0; index < target.vars.len; index++) {
      bound[index] = index < target.explicit_args.len ? target.explicit_args.ptr[index] : MS_TY_NONE;
    }
    for (size_t index = 0; index < count; index++) {
      matched.slot[index] = -1;
    }
    match_args(&body->program->types, target.sig, expr, &matched);
    type_args(body, &target, expr, &matched, arg_tys, bound);
    result = finish_call(body, expr, &target, arg_tys, &matched, expected);
  } else {
    for (uint32_t index = 0; index < expr->u.call.args.len; index++) {
      (void)body_expr(body, expr->u.call.args.ptr[index].value, MS_TY_NONE);
    }
  }
  target_free(&target);
  return result;
}

/* compiler/check/methods.c: registers a module's methods and finds the methods of a receiver.
 *
 * `fn Type[T: Bound].name(...)` becomes one entry: the receiver form (the written arguments, with a fresh
 * variable per type parameter the form leaves open), the method's own type parameters, and the signature with
 * `Self` read as the receiver. A method of a type another module declares, of an interface, or of a built-in
 * type is reported and not registered; the standard modules may extend built-in scalars and native types. */
#include "compiler/check/methods.h"

#include "base/alloc.h"
#include "compiler/check/resolve_internal.h"

typedef struct Context {
  Resolver resolver;
  MsCheckProgram *program;
  uint32_t module;
  MsTyList fresh;       /* the receiver form's variables, in step with the symbol's */
  MsTyList open;        /* the ones the receiver mentions */
} Context;

static void report(const Context *context, MsPos pos, const char *prefix, MsName name, const char *suffix) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, prefix);
  ms_strbuild_append(&text, ms_names_span(context->program->names, name));
  ms_strbuild_append_text(&text, suffix);
  ms_check_report(context->program, context->module, pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

void ms_methods_free(MsMethodList *methods) {
  for (size_t index = 0; index < methods->len; index++) {
    ms_ty_list_free(&methods->ptr[index].variables);
  }
  ms_method_list_free(methods);
}

/* ---- receivers ---- */

/* Whether `ty` is `variable` or mentions it. */
static bool mentions(const MsTyTable *types, MsTy ty, MsTy variable) {
  if (ty == variable) {
    return true;
  }
  if (!ms_ty_has_variable(types, ty)) {
    return false;
  }
  for (size_t index = 0; index < ms_ty_arg_count(types, ty); index++) {
    if (mentions(types, ms_ty_args(types, ty)[index], variable)) {
      return true;
    }
  }
  for (size_t index = 0; index < ms_ty_param_count(types, ty); index++) {
    if (mentions(types, ms_ty_params(types, ty)[index].ty, variable)) {
      return true;
    }
  }
  return ms_ty_result(types, ty) != MS_TY_NONE && mentions(types, ms_ty_result(types, ty), variable);
}

/* The symbol that declares the type named by the receiver of `decl`, or 0 with the reason reported. The
 * standard modules may also name built-in types, which have no symbol: `*primitive` is then set. */
static MsSymbolId receiver_symbol(Context *context, const MsDecl *decl, bool *primitive) {
  const MsCheckProgram *program = context->program;
  const MsTypeRef *receiver = decl->u.impl.receiver;
  const bool standard = context->module >= program->user_modules;
  const MsSymbolId *own = ms_scope_get(&program->modules.ptr[context->module].scope, receiver->name);
  const MsSymbolId *imported = ms_scope_get(&program->modules.ptr[context->module].imports, receiver->name);
  MsSymbolId id = own != NULL ? *own : 0;
  *primitive = false;
  if (id == 0 && standard) {
    id = imported != NULL ? *imported : 0;
    if (id == 0 && ms_builtin_primitive(ms_names_span(program->names, receiver->name)) != MS_BUILTIN_NONE) {
      *primitive = true;
      return 1; /* a stand-in: the caller reads `primitive` */
    }
  }
  if (id == 0 || program->symbols.ptr[id].kind != MS_SYMBOL_TYPE) {
    report(context, decl->pos, "inherent methods belong in the module that declares ", receiver->name,
           "; to add operations to another module's type, write a free function or a wrapper type");
    return 0;
  }
  return id;
}

/* The names `[T, U]` of a symbol's type parameters, for the argument-count message. */
static void append_parameter_names(const Context *context, const MsSymbol *symbol, MsStrBuild *text) {
  const MsTypeParams params = ms_check_decl_type_params(symbol->decl);
  for (uint32_t index = 0; index < params.len; index++) {
    ms_strbuild_append_text(text, index == 0 ? "[" : ", ");
    ms_strbuild_append(text, ms_names_span(context->program->names, params.ptr[index]->name));
  }
  ms_strbuild_append_text(text, params.len > 0 ? "]" : "");
}

/* Gives the receiver form a fresh variable per type parameter of `symbol`, bounded as the declaration bounds it
 * (and as the form writes), and enters their names. */
static void enter_form_variables(Context *context, const MsSymbol *symbol, const MsDecl *decl) {
  MsCheckProgram *program = context->program;
  const MsTypeParams params = ms_check_decl_type_params(symbol->decl);
  for (uint32_t index = 0; index < params.len; index++) {
    const MsName id = ms_check_unique_id(program, "var");
    const MsTy variable = ms_ty_variable_new(&program->types, params.ptr[index]->name, id);
    ms_ty_list_push(&context->fresh, variable);
    ms_name_list_push(&context->resolver.names, params.ptr[index]->name);
    ms_ty_list_push(&context->resolver.types, variable);
  }
  for (uint32_t index = 0; index < params.len; index++) {
    MsTyVariable *record = ms_ty_variable(&program->types, context->fresh.ptr[index]);
    const MsTyVariable *declared =
        ms_ty_variable(&program->types, program->symbol_vars.ptr[symbol->var_at + index]);
    for (size_t at = 0; at < declared->bounds.len; at++) {
      ms_ty_list_push(&record->bounds,
                      ms_ty_subst(&program->types, declared->bounds.ptr[at],
                                  program->symbol_vars.ptr + symbol->var_at, context->fresh.ptr, params.len));
    }
    for (uint32_t written = 0; written < decl->u.impl.bounds.len; written++) {
      const MsTypeParam *param = decl->u.impl.bounds.ptr[written];
      for (uint32_t bound = 0; param->name == params.ptr[index]->name && bound < param->bounds.len; bound++) {
        ms_ty_list_push(&record->bounds, resolver_type(&context->resolver, param->bounds.ptr[bound]));
      }
    }
  }
}

/* ---- one method ---- */

static bool declared_twice(const MsCheckProgram *program, MsTy receiver, MsName name, uint32_t module) {
  for (size_t index = 0; index < program->methods.len; index++) {
    const MsMethodEntry *entry = &program->methods.ptr[index];
    if (entry->receiver == receiver && entry->name == name && entry->module == module) {
      return true;
    }
  }
  return false;
}

/* The method's own type parameters, entered in scope and bounded; a name the receiver form already uses is
 * reported. */
static void enter_own_variables(Context *context, const MsMethod *method, MsTyList *own) {
  MsCheckProgram *program = context->program;
  for (uint32_t index = 0; index < method->func.type_params.len; index++) {
    const MsTypeParam *param = method->func.type_params.ptr[index];
    for (size_t at = 0; at < context->resolver.names.len; at++) {
      if (context->resolver.names.ptr[at] == param->name) {
        report(context, param->pos, "type parameter ", param->name,
               " shadows a type parameter of the impl; choose a different name");
        break;
      }
    }
    const MsTy variable = ms_ty_variable_new(&program->types, param->name, ms_check_unique_id(program, "var"));
    ms_ty_list_push(own, variable);
    ms_name_list_push(&context->resolver.names, param->name);
    ms_ty_list_push(&context->resolver.types, variable);
  }
  for (uint32_t index = 0; index < method->func.type_params.len; index++) {
    const MsTypeParam *param = method->func.type_params.ptr[index];
    MsTyVariable *record = ms_ty_variable(&program->types, own->ptr[index]);
    for (uint32_t bound = 0; bound < param->bounds.len; bound++) {
      ms_ty_list_push(&record->bounds, resolver_type(&context->resolver, param->bounds.ptr[bound]));
    }
    if (param->def != NULL) {
      record->default_ty = resolver_type(&context->resolver, param->def);
    }
  }
}

static void add_methods(Context *context, const MsDecl *decl, MsTy receiver) {
  MsCheckProgram *program = context->program;
  Resolver *resolver = &context->resolver;
  const size_t form_mark = resolver->names.len;
  resolver->self = receiver;
  for (uint32_t index = 0; index < decl->u.impl.methods.len; index++) {
    const MsMethod *method = decl->u.impl.methods.ptr[index];
    MsTyList own = {0};
    enter_own_variables(context, method, &own);
    const MsTy signature = resolver_function(resolver, method->func.params, method->func.result);
    if (declared_twice(program, receiver, method->func.name, context->module)) {
      report(context, method->pos, "duplicate operation ", method->func.name, "; rename or remove one of them");
      report(context, method->pos, "duplicate implementation operation ", method->func.name,
             "; define each operation once per impl");
    }
    MsMethodEntry entry = {.name = method->func.name, .receiver = receiver, .ty = signature,
                           .module = context->module, .source = method};
    ms_ty_list_reserve(&entry.variables, context->open.len + own.len);
    for (size_t at = 0; at < context->open.len; at++) {
      ms_ty_list_push(&entry.variables, context->open.ptr[at]);
    }
    entry.shared = (uint32_t)context->open.len;
    for (size_t at = 0; at < own.len; at++) {
      ms_ty_list_push(&entry.variables, own.ptr[at]);
    }
    ms_method_list_push(&program->methods, entry);
    ms_ty_list_free(&own);
    ms_name_list_truncate(&resolver->names, form_mark);
    ms_ty_list_truncate(&resolver->types, form_mark);
  }
}

/* `fn Ordered.min(...)` over a type set `type Ordered = Int | Float`: the method exists on every member. */
static bool add_set_block(Context *context, const MsDecl *decl) {
  MsCheckProgram *program = context->program;
  const MsSymbolId *own = ms_scope_get(&program->modules.ptr[context->module].scope, decl->u.impl.receiver->name);
  if (own == NULL || program->symbols.ptr[*own].kind != MS_SYMBOL_ALIAS || decl->u.impl.receiver->args.len != 0) {
    return false;
  }
  const MsDecl *alias = program->symbols.ptr[*own].decl;
  if (alias->u.alias.type_params.len != 0 || alias->u.alias.targets.len < 2) {
    return false;
  }
  for (uint32_t index = 0; index < alias->u.alias.targets.len; index++) {
    ms_name_list_truncate(&context->resolver.names, 0);
    ms_ty_list_truncate(&context->resolver.types, 0);
    ms_ty_list_truncate(&context->fresh, 0);
    ms_ty_list_truncate(&context->open, 0);
    const MsTy member = resolver_type(&context->resolver, alias->u.alias.targets.ptr[index]);
    if (member != MS_TY_NONE) {
      add_methods(context, decl, member);
    }
  }
  return true;
}

static void add_block(Context *context, const MsDecl *decl) {
  MsCheckProgram *program = context->program;
  Resolver *resolver = &context->resolver;
  if (add_set_block(context, decl)) {
    return;
  }
  bool primitive = false;
  const MsSymbolId id = receiver_symbol(context, decl, &primitive);
  if (id == 0) {
    return;
  }
  ms_name_list_truncate(&resolver->names, 0);
  ms_ty_list_truncate(&resolver->types, 0);
  ms_ty_list_truncate(&context->fresh, 0);
  ms_ty_list_truncate(&context->open, 0);
  MsTy receiver = MS_TY_NONE;
  if (primitive) {
    receiver = resolver_type(resolver, decl->u.impl.receiver);
  } else {
    const MsSymbol *symbol = &program->symbols.ptr[id];
    MsStrBuild text = ms_strbuild_new();
    if (symbol->def != 0 && ms_defs_get(&program->defs, symbol->def)->kind == MS_TY_CONTRACT) {
      ms_strbuild_append(&text, ms_names_span(program->names, symbol->name));
      ms_strbuild_append_text(&text, " is an interface; a method belongs to a type, and a type whose methods match the interface satisfies it");
    } else if (decl->u.impl.receiver->args.len != symbol->var_count) {
      ms_strbuild_append_text(&text, "a method of ");
      ms_strbuild_append(&text, ms_names_span(program->names, symbol->name));
      ms_strbuild_append_text(&text, " names one receiver argument per type parameter, as in 'fn ");
      ms_strbuild_append(&text, ms_names_span(program->names, symbol->name));
      append_parameter_names(context, symbol, &text);
      ms_strbuild_append_text(&text, ".name()'");
    }
    if (ms_strbuild_length(&text) > 0) {
      ms_check_report(program, context->module, decl->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
      return;
    }
    ms_strbuild_free(&text);
    enter_form_variables(context, symbol, decl);
    receiver = resolver_type(resolver, decl->u.impl.receiver);
    for (size_t at = 0; at < context->fresh.len; at++) {
      if (mentions(&program->types, receiver, context->fresh.ptr[at])) {
        ms_ty_list_push(&context->open, context->fresh.ptr[at]);
      }
    }
  }
  if (receiver == MS_TY_NONE) {
    return;
  }
  add_methods(context, decl, receiver);
}

void ms_check_methods(MsCheckProgram *program, uint32_t module) {
  Context context = {.program = program, .module = module};
  resolver_init(&context.resolver, program, module);
  const MsModule *tree = program->modules.ptr[module].tree;
  for (uint32_t index = 0; index < tree->ndecls; index++) {
    if (ms_decl_is_inherent_impl(tree->decls[index])) {
      add_block(&context, tree->decls[index]);
    }
  }
  ms_ty_list_free(&context.fresh);
  ms_ty_list_free(&context.open);
  resolver_free(&context.resolver);
}

/* ---- lookup ---- */

bool ms_check_unify(const MsTyTable *types, MsTy pattern, MsTy actual, const MsTy *vars, size_t count,
                    MsTy *bound) {
  for (size_t index = 0; index < count; index++) {
    if (vars[index] != pattern) {
      continue;
    }
    if (bound[index] != MS_TY_NONE) {
      return bound[index] == actual;
    }
    bound[index] = actual;
    return true;
  }
  if (pattern == actual) {
    return true;
  }
  if (!ms_ty_has_variable(types, pattern)) {
    return false;
  }
  const MsTyRow *want = ms_ty_row(types, pattern);
  const MsTyRow *have = ms_ty_row(types, actual);
  if (want->id != have->id || want->kind != have->kind || want->arg_count != have->arg_count ||
      want->param_count != have->param_count) {
    return false;
  }
  for (uint32_t index = 0; index < want->arg_count; index++) {
    if (!ms_check_unify(types, ms_ty_args(types, pattern)[index], ms_ty_args(types, actual)[index], vars, count,
                        bound)) {
      return false;
    }
  }
  for (uint32_t index = 0; index < want->param_count; index++) {
    const MsTyParam *left = &ms_ty_params(types, pattern)[index];
    const MsTyParam *right = &ms_ty_params(types, actual)[index];
    if ((left->flags & ~MS_PARAM_LIFTED) != (right->flags & ~MS_PARAM_LIFTED) ||
        !ms_check_unify(types, left->ty, right->ty, vars, count, bound)) {
      return false;
    }
  }
  return want->kind != MS_TY_FUNCTION ||
         (want->result != MS_TY_NONE && have->result != MS_TY_NONE &&
          ms_check_unify(types, want->result, have->result, vars, count, bound));
}

/* Whether each of `variables` holds an argument that meets the variable's bounds. */
static bool bounds_satisfied(MsCheckProgram *program, const MsTy *variables, size_t count, const MsTy *bound) {
  for (size_t index = 0; index < count; index++) {
    if (bound[index] == MS_TY_NONE) {
      return false;
    }
    const MsTyVariable *record = ms_ty_variable(&program->types, variables[index]);
    for (size_t at = 0; at < record->bounds.len; at++) {
      const MsTy wanted = ms_ty_subst(&program->types, record->bounds.ptr[at], variables, bound, count);
      if (!ms_check_implements(program, bound[index], wanted)) {
        return false;
      }
    }
  }
  return true;
}

static void find_in_contract(MsCheckProgram *program, MsTy contract, MsName name, MsTy implementor,
                             MsMethodMatchList *out) {
  const MsOperation *operation = ms_check_find_operation(program, contract, name);
  if (operation == NULL) {
    return;
  }
  for (size_t index = 0; index < out->len; index++) {
    if (out->ptr[index].operation == operation && out->ptr[index].contract == contract) {
      return; /* one bound inherited twice does not make the operation ambiguous */
    }
  }
  ms_method_match_list_push(out, (MsMethodMatch){
      .ty = ms_check_operation_type(program, contract, operation, implementor), .contract = contract,
      .operation = operation});
}

void ms_check_find_method(MsCheckProgram *program, MsTy receiver, MsName name, MsMethodMatchList *out) {
  const MsTyKind kind = ms_ty_kind(&program->types, receiver);
  if (kind == MS_TY_CONTRACT) {
    find_in_contract(program, receiver, name, receiver, out);
    ms_check_find_native(program, receiver, name, out);
    return;
  }
  if (kind == MS_TY_VARIABLE) {
    const MsTyVariable *record = ms_ty_variable(&program->types, receiver);
    for (size_t index = 0; index < record->bounds.len; index++) {
      if (ms_ty_kind(&program->types, record->bounds.ptr[index]) == MS_TY_CONTRACT) {
        find_in_contract(program, record->bounds.ptr[index], name, receiver, out);
      }
    }
    ms_check_find_native(program, receiver, name, out);
    return;
  }
  for (size_t index = 0; index < program->methods.len; index++) {
    const MsMethodEntry *entry = &program->methods.ptr[index];
    if (entry->name != name) {
      continue;
    }
    MsTyList bound = {0};
    for (uint32_t at = 0; at < entry->shared; at++) {
      ms_ty_list_push(&bound, MS_TY_NONE);
    }
    const bool fits = ms_check_unify(&program->types, entry->receiver, receiver, entry->variables.ptr, entry->shared,
                                     bound.ptr) &&
                      bounds_satisfied(program, entry->variables.ptr, entry->shared, bound.ptr);
    if (fits) {
      ms_method_match_list_push(out, (MsMethodMatch){
          .ty = ms_ty_subst(&program->types, entry->ty, entry->variables.ptr, bound.ptr, entry->shared),
          .entry = entry});
    }
    ms_ty_list_free(&bound);
  }
  ms_check_find_native(program, receiver, name, out);
}

/* compiler/check/signatures.c: bounds, defaults and the signatures of declarations.
 *
 * After the type variables exist, each type variable gets its bounds and default type, each record gets its
 * field types, each enum its cases, each interface its operations, and each function its function type.
 * Signatures resolve in declaration order; a reference to a type declared later needs nothing but that type's
 * variables, which the earlier pass made. Unknown names are reported for the program's own modules. */
#include "compiler/check/resolve_internal.h"

static void resolve_bounds(Resolver *resolver, const MsSymbol *symbol) {
  MsCheckProgram *program = resolver->program;
  const MsTypeParams params = ms_check_decl_type_params(symbol->decl);
  const size_t scope = resolver->names.len - (params.len < symbol->var_count ? params.len : symbol->var_count);
  bool defaulted = false;
  for (uint32_t index = 0; index < params.len && index < symbol->var_count; index++) {
    MsTyVariable *variable =
        ms_ty_variable(&program->types, program->symbol_vars.ptr[symbol->var_at + index]);
    for (uint32_t bound = 0; bound < params.ptr[index]->bounds.len; bound++) {
      const MsTy resolved = resolver_bound(resolver, params.ptr[index]->bounds.ptr[bound]);
      if (resolved != MS_TY_NONE) {
        ms_ty_list_push(&variable->bounds, resolved);
      }
    }
    if (params.ptr[index]->def == NULL) {
      if (defaulted && resolver->report) {
        MsStrBuild text = ms_strbuild_new();
        const MsSpan name = ms_names_span(program->names, params.ptr[index]->name);
        ms_strbuild_append_text(&text, "type parameter ");
        ms_strbuild_append(&text, name);
        ms_strbuild_append_text(&text, " needs a default because an earlier parameter has one; give ");
        ms_strbuild_append(&text, name);
        ms_strbuild_append_text(&text, " a default or move it before the defaulted parameters");
        ms_check_report(program, resolver->module, params.ptr[index]->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
      }
      continue;
    }
    defaulted = true;
    /* a default sees the receiver's variables and the parameters before it, not itself or those after */
    const size_t names = resolver->names.len;
    const size_t types = resolver->types.len;
    resolver->names.len = scope + index;
    resolver->types.len = scope + index;
    variable->default_ty = resolver_type(resolver, params.ptr[index]->def);
    resolver->names.len = names;
    resolver->types.len = types;
    if (resolver->report && variable->default_ty != MS_TY_NONE) {
      ms_pending_default_list_push(&program->pending_defaults, (MsPendingDefault){
          .module = resolver->module, .pos = params.ptr[index]->def->pos, .variable = variable->default_ty,
          .owner = program->symbol_vars.ptr[symbol->var_at + index]});
    }
  }
}

static void resolve_enum(Resolver *resolver, MsDef *def, const MsDecl *decl) {
  for (uint32_t index = 0; index < decl->u.enumeration.cases.len; index++) {
    const MsCase *source = decl->u.enumeration.cases.ptr[index];
    MsTyCase checked = {.name = source->name};
    resolver_params(resolver, source->fields, &checked.fields);
    ms_ty_case_list_push(&def->cases, checked);
  }
}

/* Whether the written type `type` mentions `Self` anywhere, including inside arguments and function types. */
static bool mentions_self(const MsCheckProgram *program, const MsTypeRef *type) {
  if (type == NULL) {
    return false;
  }
  if (ms_span_is_text(ms_names_span(program->names, type->name), "Self")) {
    return true;
  }
  for (uint32_t at = 0; at < type->args.len; at++) {
    if (mentions_self(program, type->args.ptr[at])) {
      return true;
    }
  }
  for (uint32_t at = 0; at < type->params.len; at++) {
    if (mentions_self(program, type->params.ptr[at]->ty)) {
      return true;
    }
  }
  return mentions_self(program, type->result);
}

/* `Self` is limited to whole parameter and result types, the positions where a call can substitute the implementing type. */
static bool self_misplaced(const MsCheckProgram *program, const MsFunc *func) {
  for (uint32_t at = 0; at < func->params.len; at++) {
    const MsTypeRef *type = func->params.ptr[at]->ty;
    const bool whole = type != NULL && type->args.len == 0 && type->params.len == 0 &&
                       ms_span_is_text(ms_names_span(program->names, type->name), "Self");
    if (!whole && mentions_self(program, type)) {
      return true;
    }
  }
  const MsTypeRef *result = func->result;
  const bool whole = result != NULL && result->args.len == 0 && result->params.len == 0 &&
                     ms_span_is_text(ms_names_span(program->names, result->name), "Self");
  return !whole && mentions_self(program, result);
}

static void resolve_interface(Resolver *resolver, MsDef *def, const MsDecl *decl, MsTy self) {
  resolver->self = self;
  for (uint32_t index = 0; index < decl->u.iface.methods.len; index++) {
    const MsMethod *method = decl->u.iface.methods.ptr[index];
    const size_t mark = resolver->names.len;
    MsTyList own = {0};
    for (uint32_t at = 0; at < method->func.type_params.len; at++) {
      const MsTypeParam *param = method->func.type_params.ptr[at];
      const MsName id = ms_check_unique_id(resolver->program, "var");
      const MsTy variable = ms_ty_variable_new(&resolver->program->types, param->name, id);
      ms_ty_list_push(&own, variable);
      ms_name_list_push(&resolver->names, param->name);
      ms_ty_list_push(&resolver->types, variable);
    }
    for (uint32_t at = 0; at < method->func.type_params.len; at++) {
      const MsTypeParam *param = method->func.type_params.ptr[at];
      MsTyVariable *record = ms_ty_variable(&resolver->program->types, own.ptr[at]);
      for (uint32_t bound = 0; bound < param->bounds.len; bound++) {
        const MsTy resolved = resolver_bound(resolver, param->bounds.ptr[bound]);
        if (resolved != MS_TY_NONE) {
          ms_ty_list_push(&record->bounds, resolved);
        }
      }
      if (param->def != NULL) {
        record->default_ty = resolver_type(resolver, param->def);
      }
    }
    const MsTy ty = resolver_function(resolver, method->func.params, method->func.result);
    if (!decl->synthetic && self_misplaced(resolver->program, &method->func)) {
      ms_check_report(resolver->program, resolver->module, method->pos, MS_CHECK_TYPE,
                      ms_string_from_span(ms_span_of_text("Self can only be a whole parameter or result type of an interface operation; write 'other: Self', not 'List[Self]'")));
    }
    ms_name_list_truncate(&resolver->names, mark);
    ms_ty_list_truncate(&resolver->types, mark);
    ms_operation_list_push(&def->operations, (MsOperation){.name = method->func.name, .ty = ty,
                                                           .decl = {resolver->module, method->id}, .variables = own});
  }
  resolver->self = MS_TY_NONE;
}

static void resolve_symbol(Resolver *resolver, MsSymbol *symbol) {
  const MsDecl *decl = symbol->decl;
  const size_t mark = resolver->names.len;
  resolver_enter_symbol(resolver, symbol);
  MsDef *def = symbol->def != 0 ? ms_defs_get(&resolver->program->defs, symbol->def) : NULL;
  switch ((MsDeclKind)decl->kind) {
  case MS_D_FN:
    symbol->ty = resolver_function(resolver, decl->u.fn.params, decl->u.fn.result);
    break;
  case MS_D_TYPE:
    resolver_params(resolver, decl->u.type.fields, &def->fields);
    break;
  case MS_D_ENUM:
    resolve_enum(resolver, def, decl);
    break;
  case MS_D_INTERFACE:
    resolve_interface(resolver, def, decl, symbol->ty);
    break;
  case MS_D_ALIAS:
  case MS_D_CONST:
  case MS_D_IMPL:
  case MS_D_TEST:
    break;
  }
  ms_name_list_truncate(&resolver->names, mark);
  ms_ty_list_truncate(&resolver->types, mark);
}

/* An alias of a union is a type set: its members are the resolved targets. */
void resolver_resolve_alias(Resolver *resolver, MsSymbol *symbol) {
  MsCheckProgram *program = resolver->program;
  const MsDecl *decl = symbol->decl;
  if (symbol->alias_state == 2) {
    return;
  }
  if (symbol->alias_state == 1) { /* reached again through its own target */
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append_text(&text, "type alias ");
    ms_strbuild_append(&text, ms_names_span(program->names, decl->u.alias.name));
    ms_strbuild_append_text(&text, " refers to itself; an alias names another type, so break the cycle with a type or enum");
    ms_check_report(program, resolver->module, decl->pos, MS_CHECK_RESOLUTION, ms_strbuild_finish(&text));
    return;
  }
  symbol->alias_state = 1;
  if (decl->u.alias.targets.len == 1) {
    /* A single target is another name for that type, over the alias's own variables. */
    const size_t mark = resolver->names.len;
    resolver_enter_symbol(resolver, symbol);
    const bool allowed = resolver->allow_type_set;
    resolver->allow_type_set = true;
    symbol->ty = resolver_type(resolver, decl->u.alias.targets.ptr[0]);
    resolver->allow_type_set = allowed;
    ms_name_list_truncate(&resolver->names, mark);
    ms_ty_list_truncate(&resolver->types, mark);
    symbol->alias_state = 2;
    return;
  }
  MsTyList members = {0};
  for (uint32_t index = 0; index < decl->u.alias.targets.len; index++) {
    const bool allowed = resolver->allow_type_set;
    resolver->allow_type_set = true;
    ms_ty_list_push(&members, resolver_type(resolver, decl->u.alias.targets.ptr[index]));
    resolver->allow_type_set = allowed;
  }
  const MsTyDesc desc = {.name = decl->u.alias.name, .id = decl->u.alias.name, .kind = MS_TY_CONTRACT,
                         .builtin = MS_BUILTIN_TypeSet, .args = members.ptr, .arg_count = (uint32_t)members.len};
  symbol->ty = ms_ty_intern(&program->types, &desc);
  symbol->alias_state = 2;
  ms_ty_list_free(&members);
}

void ms_check_signatures(MsCheckProgram *program, uint32_t module) {
  Resolver resolver;
  resolver_init(&resolver, program, module);
  for (MsSymbolId id = 1; id < program->symbols.len; id++) {
    if (program->symbols.ptr[id].module == module && program->symbols.ptr[id].decl->kind == MS_D_ALIAS) {
      resolver_resolve_alias(&resolver, &program->symbols.ptr[id]);
    }
  }
  for (MsSymbolId id = 1; id < program->symbols.len; id++) {
    if (program->symbols.ptr[id].module != module) {
      continue;
    }
    const size_t mark = resolver.names.len;
    resolver_enter_symbol(&resolver, &program->symbols.ptr[id]);
    resolve_bounds(&resolver, &program->symbols.ptr[id]);
    ms_name_list_truncate(&resolver.names, mark);
    ms_ty_list_truncate(&resolver.types, mark);
  }
  for (MsSymbolId id = 1; id < program->symbols.len; id++) {
    if (program->symbols.ptr[id].module == module) {
      resolve_symbol(&resolver, &program->symbols.ptr[id]);
    }
  }
  resolver_free(&resolver);
}

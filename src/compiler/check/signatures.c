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
  for (uint32_t index = 0; index < params.len && index < symbol->var_count; index++) {
    MsTyVariable *variable =
        ms_ty_variable(&program->types, program->symbol_vars.ptr[symbol->var_at + index]);
    for (uint32_t bound = 0; bound < params.ptr[index]->bounds.len; bound++) {
      const MsTy resolved = resolver_type(resolver, params.ptr[index]->bounds.ptr[bound]);
      ms_ty_list_push(&variable->bounds, resolved);
    }
    if (params.ptr[index]->def != NULL) {
      variable->default_ty = resolver_type(resolver, params.ptr[index]->def);
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

static void resolve_interface(Resolver *resolver, MsDef *def, const MsDecl *decl, MsTy self) {
  resolver->self = self;
  for (uint32_t index = 0; index < decl->u.iface.methods.len; index++) {
    const MsMethod *method = decl->u.iface.methods.ptr[index];
    const size_t mark = resolver->names.len;
    for (uint32_t at = 0; at < method->func.type_params.len; at++) {
      const MsTypeParam *param = method->func.type_params.ptr[at];
      const MsName id = ms_check_unique_id(resolver->program, "var");
      ms_name_list_push(&resolver->names, param->name);
      ms_ty_list_push(&resolver->types, ms_ty_variable_new(&resolver->program->types, param->name, id));
    }
    const MsTy ty = resolver_function(resolver, method->func.params, method->func.result);
    ms_name_list_truncate(&resolver->names, mark);
    ms_ty_list_truncate(&resolver->types, mark);
    ms_operation_list_push(&def->operations,
                           (MsOperation){.name = method->func.name, .ty = ty, .decl = {0, method->id}});
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
    for (uint32_t index = 0; index < decl->u.alias.targets.len; index++) {
      (void)resolver_type(resolver, decl->u.alias.targets.ptr[index]);
    }
    break;
  case MS_D_CONST:
  case MS_D_IMPL:
  case MS_D_TEST:
    break;
  }
  ms_name_list_truncate(&resolver->names, mark);
  ms_ty_list_truncate(&resolver->types, mark);
}

void ms_check_signatures(MsCheckProgram *program, uint32_t module) {
  Resolver resolver;
  resolver_init(&resolver, program, module);
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

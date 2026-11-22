/* compiler/check/typevars.c: the type variables of declarations.
 *
 * Every type-like or generic declaration gets one variable type per declared type parameter, numbered in
 * declaration order. A nominal type's own type carries its variables as arguments, so a use that writes
 * arguments substitutes them (resolve.c, ms_ty_subst). */
#include "compiler/check/resolve_internal.h"

/* The nominal type of `symbol` with its variables as arguments, and the variables recorded on its definition. */
static void own_type(MsCheckProgram *program, MsSymbol *symbol) {
  if (symbol->def == 0 || symbol->var_count == 0) {
    return;
  }
  MsDef *def = ms_defs_get(&program->defs, symbol->def);
  for (uint32_t index = 0; index < symbol->var_count; index++) {
    ms_ty_list_push(&def->variables, program->symbol_vars.ptr[symbol->var_at + index]);
  }
  const MsTyRow row = *ms_ty_row(&program->types, symbol->ty);
  const MsTyDesc desc = {.name = row.name, .id = row.id, .kind = (MsTyKind)row.kind,
                         .builtin = (MsBuiltin)row.builtin, .def = row.def,
                         .args = program->symbol_vars.ptr + symbol->var_at, .arg_count = symbol->var_count};
  symbol->ty = ms_ty_intern(&program->types, &desc);
}

void ms_check_type_variables(MsCheckProgram *program, uint32_t module) {
  for (MsSymbolId id = 1; id < program->symbols.len; id++) {
    MsSymbol *symbol = &program->symbols.ptr[id];
    if (symbol->module != module) {
      continue;
    }
    const MsTypeParams params = ms_check_decl_type_params(symbol->decl);
    symbol->var_at = (uint32_t)program->symbol_vars.len;
    for (uint32_t index = 0; index < params.len; index++) {
      const MsName var_id = ms_check_unique_id(program, "var");
      ms_ty_list_push(&program->symbol_vars, ms_ty_variable_new(&program->types, params.ptr[index]->name, var_id));
    }
    symbol->var_count = params.len;
    own_type(program, symbol);
  }
}

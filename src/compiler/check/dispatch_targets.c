/* compiler/check/dispatch_targets.c: see dispatch_targets.h. */
#include "compiler/check/dispatch_targets.h"

#include "compiler/check/methods.h"
#include "compiler/check/properties.h"

/* The definition of an interface type, or NULL. */
static const MsDef *contract_def(const MsCheckProgram *program, MsTy ty) {
  const MsTyRow *row = ms_ty_row(&program->types, ty);
  return row->kind == MS_TY_CONTRACT && row->def != 0 ? ms_defs_get(&program->defs, row->def) : NULL;
}

/* Visits the methods of `concrete` that `contract`'s operations name. */
static void implementors(const MsCheckProgram *program, const MsDef *contract, const MsDef *concrete, MsTargetFn visit,
                         void *ctx) {
  for (size_t index = 0; contract != NULL && concrete != NULL && index < contract->operations.len; index++) {
    for (size_t at = 0; at < program->methods.len; at++) {
      const MsMethodEntry *entry = &program->methods.ptr[at];
      if (entry->name == contract->operations.ptr[index].name && entry->source != NULL &&
          ms_check_def_of(program, entry->receiver) == concrete) {
        visit(ctx, entry->module, entry->source->id);
      }
    }
  }
}

void ms_check_view_targets(const MsCheckProgram *program, const MsConversion *conversion, MsTargetFn visit, void *ctx) {
  implementors(program, contract_def(program, conversion->to), ms_check_def_of(program, conversion->from), visit, ctx);
}

/* The symbol of the function declared at `ref`, or NULL. */
static const MsSymbol *function_symbol(const MsCheckProgram *program, const MsRef *ref) {
  for (size_t index = 0; index < program->symbols.len; index++) {
    const MsSymbol *symbol = &program->symbols.ptr[index];
    if (symbol->decl != NULL && symbol->module == ref->decl.module && symbol->decl->id == ref->decl.node) {
      return symbol;
    }
  }
  return NULL;
}

/* Visits the `close` of `ty` and of its type arguments, to a depth of four. */
static void closes(const MsCheckProgram *program, MsTy ty, uint32_t depth, MsTargetFn visit, void *ctx) {
  const MsDef *concrete = ms_check_def_of(program, ty);
  for (size_t at = 0; concrete != NULL && at < program->methods.len; at++) {
    const MsMethodEntry *entry = &program->methods.ptr[at];
    if (entry->source != NULL && ms_span_is_text(ms_names_span(program->names, entry->name), "close") &&
        ms_check_def_of(program, entry->receiver) == concrete) {
      visit(ctx, entry->module, entry->source->id);
    }
  }
  const size_t count = ms_ty_arg_count(&program->types, ty);
  for (size_t index = 0; depth < 4 && index < count; index++) {
    closes(program, ms_ty_args(&program->types, ty)[index], depth + 1, visit, ctx);
  }
}

void ms_check_instantiation_targets(const MsCheckProgram *program, const MsCall *call, MsTargetFn visit, void *ctx) {
  if (call->callee.kind != MS_REF_FUNCTION || call->type_arg_count == 0) {
    return;
  }
  for (uint32_t index = 0; index < call->type_arg_count; index++) {
    closes(program, call->type_args[index], 0, visit, ctx);
  }
  const MsSymbol *symbol = function_symbol(program, &call->callee);
  for (uint32_t index = 0; symbol != NULL && index < call->type_arg_count && index < symbol->var_count; index++) {
    const MsTyRow *row = ms_ty_row(&program->types, program->symbol_vars.ptr[symbol->var_at + index]);
    const MsDef *concrete = ms_check_def_of(program, call->type_args[index]);
    if (row->kind != MS_TY_VARIABLE || concrete == NULL) {
      continue;
    }
    const MsTyList *bounds = &program->types.variables.ptr[row->def].bounds;
    for (size_t bound = 0; bound < bounds->len; bound++) {
      implementors(program, contract_def(program, bounds->ptr[bound]), concrete, visit, ctx);
    }
  }
}

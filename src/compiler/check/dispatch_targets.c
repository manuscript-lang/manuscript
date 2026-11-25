/* compiler/check/dispatch_targets.c: see dispatch_targets.h. */
#include "compiler/check/dispatch_targets.h"

#include "compiler/check/methods.h"
#include "compiler/check/properties.h"

/* The definition of an interface type, or NULL. */
static const MsDef *contract_def(const MsCheckProgram *program, MsTy ty) {
  const MsTyRow *row = ms_ty_row(&program->types, ty);
  return row->kind == MS_TY_CONTRACT && row->def != 0 ? ms_defs_get(&program->defs, row->def) : NULL;
}

/* Whether a method declared on `form` can run for a value of type `ty`: the same definition, or for a type with none
 * the same builtin. A receiver of a type variable (`T.name`) fits any type. Arguments are not compared, so a
 * method of `List[Int]` is also found for `List[String]`: the lookup finds at least what lowering will call. */
static bool same_head(const MsCheckProgram *program, MsTy form, MsTy ty) {
  if (form == ty || ms_ty_kind(&program->types, form) == MS_TY_VARIABLE) {
    return true;
  }
  const MsDef *form_def = ms_check_def_of(program, form);
  const MsDef *ty_def = ms_check_def_of(program, ty);
  if (form_def != NULL || ty_def != NULL) {
    return form_def == ty_def;
  }
  return ms_ty_kind(&program->types, form) == ms_ty_kind(&program->types, ty) &&
         ms_ty_builtin(&program->types, form) == ms_ty_builtin(&program->types, ty);
}

void ms_check_method_targets(const MsCheckProgram *program, MsTy ty, MsName name, MsTargetFn visit, void *ctx) {
  if (ty == MS_TY_NONE || ms_ty_kind(&program->types, ty) == MS_TY_VARIABLE) {
    return;
  }
  const MsMethodKeyList *named = &program->method_index.by_name;
  size_t low = 0;
  size_t high = named->len;
  while (low < high) {
    const size_t mid = low + (high - low) / 2;
    if (named->ptr[mid].key < name) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  for (; low < named->len && named->ptr[low].key == name; low++) {
    const MsMethodEntry *entry = &program->methods.ptr[named->ptr[low].entry];
    if (entry->source != NULL && same_head(program, entry->receiver, ty)) {
      visit(ctx, entry->module, entry->source->id);
    }
  }
}

/* Visits the methods of `concrete` that `contract`'s operations name. */
static void implementors(const MsCheckProgram *program, const MsDef *contract, MsTy concrete, MsTargetFn visit,
                         void *ctx) {
  for (size_t index = 0; contract != NULL && index < contract->operations.len; index++) {
    ms_check_method_targets(program, concrete, contract->operations.ptr[index].name, visit, ctx);
  }
}

void ms_check_view_targets(const MsCheckProgram *program, const MsConversion *conversion, MsTargetFn visit, void *ctx) {
  implementors(program, contract_def(program, conversion->to), conversion->from, visit, ctx);
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
  MsName close = MS_NAME_EMPTY;
  if (ms_names_find(program->names, ms_span_of_text("close"), &close)) {
    ms_check_method_targets(program, ty, close, visit, ctx);
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
    const MsTy concrete = call->type_args[index];
    if (row->kind != MS_TY_VARIABLE || concrete == MS_TY_NONE) {
      continue;
    }
    const MsTyList *bounds = &program->types.variables.ptr[row->def].bounds;
    for (size_t bound = 0; bound < bounds->len; bound++) {
      implementors(program, contract_def(program, bounds->ptr[bound]), concrete, visit, ctx);
    }
  }
}

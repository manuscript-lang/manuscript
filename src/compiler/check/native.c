/* compiler/check/native.c: the operations a type has without declaring them.
 *
 * `to_string` exists on every value and `clone` on data; a primitive's operations are the `<Type>Operations`
 * interface that src/stdlib/core/intrinsics.ms declares, followed by the generic interfaces shared by its family,
 * applied to the primitive itself. A match found here is native: the compiler or runtime provides it. */
#include <stdio.h>

#include "base/cstr.h"

#include "compiler/check/methods.h"
#include "compiler/check/program.h"
#include "compiler/check/properties.h"
#include "compiler/check/resolve_internal.h"

/* Generic interfaces of intrinsics.ms that a family of primitives shares; `T` is the receiver. */
/* The interface declared as `name` in the standard library, or MS_TY_NONE. */
static MsTy standard_interface(MsCheckProgram *program, const char *name) {
  for (size_t index = 1; index < program->symbols.len; index++) {
    const MsSymbol *symbol = &program->symbols.ptr[index];
    if (symbol->kind == MS_SYMBOL_TYPE && symbol->ty != MS_TY_NONE && symbol->module >= program->user_modules &&
        ms_ty_kind(&program->types, symbol->ty) == MS_TY_CONTRACT &&
        ms_span_is_text(ms_names_span(program->names, symbol->name), name)) {
      return symbol->ty;
    }
  }
  return MS_TY_NONE;
}

/* The operation `name` of the standard interface `contract` applied to `receiver`, appended as a native match. */
static bool add_contract_operation(MsCheckProgram *program, MsTy contract, MsTy receiver, MsName name,
                                   MsMethodMatchList *out) {
  if (contract == MS_TY_NONE) {
    return false;
  }
  const uint32_t at = program->types.rows.ptr[contract].def;
  const MsDef *def = at == 0 ? NULL : ms_defs_get(&program->defs, at);
  if (def != NULL && def->variables.len != 0) {
    contract = resolver_apply(program, contract, &receiver, 1);
  }
  const MsOperation *operation = ms_check_find_operation(program, contract, name);
  if (operation == NULL) {
    return false;
  }
  ms_method_match_list_push(out, (MsMethodMatch){
      .ty = ms_check_operation_type(program, contract, operation, receiver), .contract = contract,
      .operation = operation, .native = true});
  return true;
}

static bool add_operation(MsCheckProgram *program, const char *interface, MsTy receiver, MsName name,
                          MsMethodMatchList *out) {
  return add_contract_operation(program, standard_interface(program, interface), receiver, name, out);
}

/* The standard interfaces that declare `receiver` a member: those whose one type parameter is bounded by a type set
 * that lists it (`interface IntegerOperations[T: IntegerTypes]`). */
static void collect_shared_sets(MsCheckProgram *program) {
  MsTyTable *types = &program->types;
  MsPropertyMemo *memo = &program->properties;
  ms_ty_list_clear(&memo->shared_sets);
  for (size_t index = 1; index < program->symbols.len; index++) {
    const MsSymbol *symbol = &program->symbols.ptr[index];
    if (symbol->kind != MS_SYMBOL_TYPE || symbol->ty == MS_TY_NONE || symbol->module < program->user_modules ||
        ms_ty_kind(types, symbol->ty) != MS_TY_CONTRACT || symbol->var_count != 1) {
      continue;
    }
    const MsTyVariable *variable = ms_ty_variable(types, program->symbol_vars.ptr[symbol->var_at]);
    for (size_t at = 0; variable != NULL && at < variable->bounds.len; at++) {
      if (ms_ty_is(types, variable->bounds.ptr[at], MS_BUILTIN_TypeSet)) {
        ms_ty_list_push(&memo->shared_sets, symbol->ty);
        ms_ty_list_push(&memo->shared_sets, variable->bounds.ptr[at]);
      }
    }
  }
  memo->shared_stamp = program->symbols.len + 1;
}

static void shared_contracts(MsCheckProgram *program, MsTy receiver, MsTyList *out) {
  MsTyTable *types = &program->types;
  MsPropertyMemo *memo = &program->properties;
  if (memo->shared_stamp != program->symbols.len + 1) {
    collect_shared_sets(program);
  }
  for (size_t index = 0; index + 1 < memo->shared_sets.len; index += 2) {
    const MsTy bound = memo->shared_sets.ptr[index + 1];
    for (size_t member = 0; member < ms_ty_arg_count(types, bound); member++) {
      if (ms_ty_args(types, bound)[member] == receiver) {
        ms_ty_list_push(out, memo->shared_sets.ptr[index]);
      }
    }
  }
}

static bool is_name(const MsCheckProgram *program, MsName name, const char *text) {
  return ms_span_is_text(ms_names_span(program->names, name), text);
}

/* Whether a type parameter has a bound that makes it clonable: `Clonable`, `Data` or `Hashable`. */
static bool variable_clonable(MsCheckProgram *program, MsTy receiver) {
  const MsTyVariable *variable = ms_ty_variable(&program->types, receiver);
  for (size_t index = 0; variable != NULL && index < variable->bounds.len; index++) {
    const MsBuiltin bound = ms_ty_builtin(&program->types, variable->bounds.ptr[index]);
    if (bound == MS_BUILTIN_Clonable || bound == MS_BUILTIN_Data || bound == MS_BUILTIN_Hashable) {
      return true;
    }
  }
  return false;
}

static bool clonable(MsCheckProgram *program, MsTy receiver) {
  const MsTyKind kind = ms_ty_kind(&program->types, receiver);
  if (kind == MS_TY_VARIABLE) {
    return variable_clonable(program, receiver);
  }
  const MsBuiltin builtin = (MsBuiltin)program->types.rows.ptr[receiver].builtin;
  return kind == MS_TY_TYPE || kind == MS_TY_ALTERNATIVE || kind == MS_TY_PRIMITIVE || builtin == MS_BUILTIN_List ||
         builtin == MS_BUILTIN_Map || builtin == MS_BUILTIN_Set || builtin == MS_BUILTIN_Bytes;
}

static void add_primitive(MsCheckProgram *program, MsTy receiver, MsName name, MsMethodMatchList *out) {
  const char *text = ms_builtin_name((MsBuiltin)program->types.rows.ptr[receiver].builtin);
  char own[48];
  snprintf(own, sizeof own, "%sOperations", text);
  if (add_operation(program, own, receiver, name, out)) {
    return;
  }
  MsTyList shared = {0};
  shared_contracts(program, receiver, &shared);
  for (size_t index = 0; index < shared.len; index++) {
    if (add_contract_operation(program, shared.ptr[index], receiver, name, out)) {
      break;
    }
  }
  ms_ty_list_free(&shared);
}

void ms_check_find_native(MsCheckProgram *program, MsTy receiver, MsName name, MsMethodMatchList *out) {
  const MsTyKind kind = ms_ty_kind(&program->types, receiver);
  if (is_name(program, name, "to_string")) {
    for (size_t index = 0; index < out->len; index++) {
      if (ms_ty_param_count(&program->types, out->ptr[index].ty) == 0) {
        return; /* the type's own `to_string()` is the text form */
      }
    }
    (void)add_operation(program, "ValueOperations", receiver, name, out);
  } else if (is_name(program, name, "clone")) {
    if (out->len == 0 && clonable(program, receiver)) {
      (void)add_operation(program, "CloneOperations", receiver, name, out);
    }
  } else if (kind == MS_TY_PRIMITIVE && out->len == 0) {
    add_primitive(program, receiver, name, out);
  }
  /* A value with the structural property has the operation that names it, without an implementation. */
  const bool hash = is_name(program, name, "hash");
  if (out->len == 0 && kind != MS_TY_CONTRACT && kind != MS_TY_VARIABLE && (hash || is_name(program, name, "equals")) &&
      ms_check_property(program, receiver, hash ? MS_PROPERTY_HASHABLE : MS_PROPERTY_EQUAL)) {
    (void)add_operation(program, hash ? "Hashable" : "Equal", receiver, name, out);
  }
}

/* Appends the names of the operations a primitive has without declaring them. */
void ms_check_native_names(MsCheckProgram *program, MsTy receiver, MsSpanList *out) {
  if (ms_ty_kind(&program->types, receiver) != MS_TY_PRIMITIVE) {
    return;
  }
  const char *text = ms_builtin_name((MsBuiltin)program->types.rows.ptr[receiver].builtin);
  char own[48];
  snprintf(own, sizeof own, "%sOperations", text);
  MsTyList contracts = {0};
  ms_ty_list_push(&contracts, standard_interface(program, own));
  shared_contracts(program, receiver, &contracts);
  for (size_t index = 0; index < contracts.len; index++) {
    const MsTy contract = contracts.ptr[index];
    const uint32_t at = contract == MS_TY_NONE ? 0 : program->types.rows.ptr[contract].def;
    const MsDef *def = at == 0 ? NULL : ms_defs_get(&program->defs, at);
    for (size_t op = 0; def != NULL && op < def->operations.len; op++) {
      ms_span_list_push(out, ms_names_span(program->names, def->operations.ptr[op].name));
    }
  }
  ms_ty_list_free(&contracts);
}

/* Whether a standard interface declares an operation `name`: a value that satisfies it has the operation natively
 * (an equality, hash or resource operation) without a method that says so. */
bool ms_check_standard_operation(MsCheckProgram *program, MsName name, MsTy receiver) {
  for (size_t index = 1; index < program->symbols.len; index++) {
    const MsSymbol *symbol = &program->symbols.ptr[index];
    if (symbol->kind != MS_SYMBOL_TYPE || symbol->ty == MS_TY_NONE || symbol->module < program->user_modules ||
        ms_ty_kind(&program->types, symbol->ty) != MS_TY_CONTRACT) {
      continue;
    }
    const uint32_t at = program->types.rows.ptr[symbol->ty].def;
    const MsDef *def = at == 0 ? NULL : ms_defs_get(&program->defs, at);
    for (size_t op = 0; def != NULL && op < def->operations.len; op++) {
      if (def->operations.ptr[op].name == name && ms_check_implements(program, receiver, symbol->ty)) {
        return true;
      }
    }
  }
  return false;
}

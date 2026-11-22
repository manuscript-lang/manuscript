/* compiler/check/native.c: the operations a type has without declaring them.
 *
 * `to_string` exists on every value and `clone` on data; a primitive's operations are the `<Type>Operations`
 * interface that stdlib/core/intrinsics.ms declares, followed by the generic interfaces shared by its family,
 * applied to the primitive itself. A match found here is native: the compiler or runtime provides it. */
#include <stdio.h>

#include "base/cstr.h"

#include "compiler/check/methods.h"
#include "compiler/check/program.h"
#include "compiler/check/resolve_internal.h"

/* Generic interfaces of intrinsics.ms that a family of primitives shares; `T` is the receiver. */
static const struct {
  const char *interface;
  const char *members[9];
} SHARED[] = {
    {"IntegerOperations", {"Int", "Int8", "Int16", "Int32", "UInt8", "UInt16", "UInt32", "UInt64", NULL}},
    {"SignedIntegerOperations", {"Int", "Int8", "Int16", "Int32", NULL}},
};

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

/* The operation `name` of the standard interface `interface` applied to `receiver`, appended as a native match. */
static bool add_operation(MsCheckProgram *program, const char *interface, MsTy receiver, MsName name,
                          MsMethodMatchList *out) {
  MsTy contract = standard_interface(program, interface);
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

static bool is_name(const MsCheckProgram *program, MsName name, const char *text) {
  return ms_span_is_text(ms_names_span(program->names, name), text);
}

static bool clonable(const MsCheckProgram *program, MsTy receiver) {
  const MsTyKind kind = ms_ty_kind(&program->types, receiver);
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
  for (size_t index = 0; index < sizeof SHARED / sizeof SHARED[0]; index++) {
    for (size_t at = 0; SHARED[index].members[at] != NULL; at++) {
      if (ms_cstr_equal(SHARED[index].members[at], text) && add_operation(program, SHARED[index].interface, receiver, name, out)) {
        return;
      }
    }
  }
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
}

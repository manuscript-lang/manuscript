/* compiler/check/fallthrough_type.c: the result type of a function as the checker would print it.
 *
 * Prints a written type reference the way the resolved type would display: `Optional[T]` as `T?`, other
 * arguments as `Name[A, B]`. Only names whose meaning is certain without the signature passes are printed: a
 * primitive, a prelude type, a type parameter of the function, or a type, enum or interface of the module. An
 * alias, an import, a qualified name or a function type is refused, and the caller reports nothing. */
#include "compiler/check/fallthrough.h"

static const char *const PRELUDE[] = {"Optional", "Result", "Error", "List", "Map", "Set"};

static bool is_type_parameter(const MsFunc *func, MsName name) {
  for (uint32_t index = 0; index < func->type_params.len; index++) {
    if (func->type_params.ptr[index]->name == name) {
      return true;
    }
  }
  return false;
}

static bool is_prelude(MsSpan text) {
  for (size_t index = 0; index < MS_COUNT_OF(PRELUDE); index++) {
    if (ms_span_is_text(text, PRELUDE[index])) {
      return true;
    }
  }
  return false;
}

static bool is_declared_type(const MsCheckProgram *program, uint32_t module, MsName name) {
  const MsSymbolId *id = ms_scope_get(&program->modules.ptr[module].scope, name);
  return id != NULL && program->symbols.ptr[*id].kind == MS_SYMBOL_TYPE;
}

static bool known_name(const MsCheckProgram *program, uint32_t module, const MsFunc *func, MsName name) {
  const MsSpan text = ms_names_span(program->names, name);
  return ms_builtin_primitive(text) != MS_BUILTIN_NONE || is_prelude(text) || is_type_parameter(func, name) ||
         is_declared_type(program, module, name);
}

bool ms_fall_type_text(const MsCheckProgram *program, uint32_t module, const MsFunc *func, const MsTypeRef *type,
                       MsStrBuild *out) {
  if (type->kind != MS_TYPE_NAMED || !known_name(program, module, func, type->name)) {
    return false;
  }
  const MsSpan name = ms_names_span(program->names, type->name);
  const bool optional = ms_span_is_text(name, "Optional") && type->args.len == 1;
  if (optional) {
    const MsTypeRef *inner = type->args.ptr[0];
    if (!ms_fall_type_text(program, module, func, inner, out)) {
      return false;
    }
    ms_strbuild_append_byte(out, '?');
    return true;
  }
  ms_strbuild_append(out, name);
  for (uint32_t index = 0; index < type->args.len; index++) {
    ms_strbuild_append_text(out, index == 0 ? "[" : ", ");
    if (!ms_fall_type_text(program, module, func, type->args.ptr[index], out)) {
      return false;
    }
  }
  if (type->args.len != 0) {
    ms_strbuild_append_byte(out, ']');
  }
  return true;
}

bool ms_fall_is_unit(const MsCheckProgram *program, const MsTypeRef *type) {
  if (type->kind != MS_TYPE_NAMED) {
    return false;
  }
  const MsSpan name = ms_names_span(program->names, type->name);
  if (ms_span_is_text(name, "Void")) {
    return true;
  }
  return ms_span_is_text(name, "Result") && type->args.len == 2 && type->args.ptr[0]->kind == MS_TYPE_NAMED &&
         ms_span_is_text(ms_names_span(program->names, type->args.ptr[0]->name), "Void");
}

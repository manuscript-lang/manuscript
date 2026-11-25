/* compiler/check/builtins.c: names and lookups of the built-in types listed in builtins.def. */
#include "compiler/check/types.h"

typedef enum Origin { ORIGIN_STD, ORIGIN_MARKER, ORIGIN_PRIMITIVE, ORIGIN_SOURCE } Origin;

typedef struct BuiltinInfo {
  Origin origin;
  const char *module;
  const char *text;
} BuiltinInfo;

static const BuiltinInfo INFO[MS_BUILTIN_COUNT] = {
#define MS_BUILTIN(id, origin, module, text) [MS_BUILTIN_##id] = {ORIGIN_##origin, module, text},
#include "compiler/check/builtins.def"
#undef MS_BUILTIN
};

const char *ms_builtin_name(MsBuiltin builtin) {
  return builtin == MS_BUILTIN_NONE || builtin >= MS_BUILTIN_COUNT ? "" : INFO[builtin].text;
}

static MsBuiltin find(Origin origin, MsSpan text) {
  for (size_t index = 1; index < MS_BUILTIN_COUNT; index++) {
    const BuiltinInfo *info = &INFO[index];
    if (info->origin == origin && ms_span_is_text(text, info->text)) {
      return (MsBuiltin)index;
    }
  }
  return MS_BUILTIN_NONE;
}

MsBuiltin ms_builtin_primitive(MsSpan name) {
  return find(ORIGIN_PRIMITIVE, name);
}

MsBuiltin ms_builtin_from_id(MsSpan id) {
  MsSpan name = {0};
  if (!ms_span_starts_with_text(id, "@std/") || !ms_span_slice(id, 5, id.len, &name)) {
    return MS_BUILTIN_NONE;
  }
  return find(ORIGIN_STD, name);
}

MsBuiltin ms_builtin_source(MsSpan module, MsSpan name) {
  for (size_t index = 1; index < MS_BUILTIN_COUNT; index++) {
    const BuiltinInfo *info = &INFO[index];
    if (info->origin == ORIGIN_SOURCE && ms_span_is_text(name, info->text) &&
        ms_span_is_text(module, info->module)) {
      return (MsBuiltin)index;
    }
  }
  return MS_BUILTIN_NONE;
}

bool ms_builtin_is_int(MsBuiltin builtin) {
  return builtin >= MS_BUILTIN_Int && builtin <= MS_BUILTIN_UInt64;
}

bool ms_builtin_is_float(MsBuiltin builtin) {
  return builtin >= MS_BUILTIN_Float && builtin <= MS_BUILTIN_Float64;
}

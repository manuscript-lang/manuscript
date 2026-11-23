/* compiler/check/bounds.c: bound checks of type arguments and their diagnostics. */
#include "compiler/check/bounds.h"
#include "compiler/check/program.h"

static void show(MsCheckProgram *program, MsStrBuild *out, MsTy ty) {
  ms_ty_show(out, program->names, &program->types, ty);
}

static bool holds_function(const MsTyTable *types, MsTy ty) {
  if (ms_ty_kind(types, ty) == MS_TY_FUNCTION) {
    return true;
  }
  const MsTy *args = ms_ty_args(types, ty);
  for (size_t index = 0; index < ms_ty_arg_count(types, ty); index++) {
    if (holds_function(types, args[index])) {
      return true;
    }
  }
  return false;
}

static bool is_collection(const MsTyTable *types, MsTy ty) {
  return ms_ty_is(types, ty, MS_BUILTIN_List) || ms_ty_is(types, ty, MS_BUILTIN_Map) ||
         ms_ty_is(types, ty, MS_BUILTIN_Set);
}

static void type_set_message(MsCheckProgram *program, MsTy ty, MsTy set, MsStrBuild *out) {
  const MsTyTable *types = &program->types;
  show(program, out, ty);
  ms_strbuild_append_text(out, " is not a member of the type set ");
  ms_strbuild_append(out, ms_names_span(program->names, ms_ty_row(types, set)->name));
  ms_strbuild_append_text(out, "; its members are ");
  for (size_t index = 0; index < ms_ty_arg_count(types, set); index++) {
    if (index > 0) {
      ms_strbuild_append_text(out, ", ");
    }
    show(program, out, ms_ty_args(types, set)[index]);
  }
}

void ms_check_unsatisfied_message(MsCheckProgram *program, MsTy ty, MsTy bound, const char *alternative,
                                  MsStrBuild *out) {
  const MsTyTable *types = &program->types;
  if (ms_ty_is(types, bound, MS_BUILTIN_TypeSet)) {
    type_set_message(program, ty, bound, out);
    return;
  }
  MsStrBuild prefix = ms_strbuild_new();
  show(program, &prefix, ty);
  ms_strbuild_append_text(&prefix, " does not satisfy ");
  show(program, &prefix, bound);
  ms_strbuild_append_text(&prefix, "; ");
  const MsSpan lead = ms_strbuild_span(&prefix);
  const bool variable = ms_ty_kind(types, ty) == MS_TY_VARIABLE;
  MsStrBuild path = ms_strbuild_new();
  MsDataReason reason = MS_DATA_RESOURCE;
  MsTy part = MS_TY_NONE;
  if (ms_ty_is(types, bound, MS_BUILTIN_Data) && ms_check_data_blocker(program, ty, &path, &reason, &part)) {
    ms_check_data_message(program, ty, reason, part, ms_strbuild_span(&path), out);
  } else if (ms_ty_is(types, bound, MS_BUILTIN_Hashable) && ms_builtin_is_float(ms_ty_builtin(types, ty))) {
    show(program, out, ty);
    ms_strbuild_append_text(out, " does not satisfy Hashable; Float has no Hashable implementation, so wrap it in a "
                                 "type with an Int or String key, or use Decimal");
  } else if (ms_ty_is(types, bound, MS_BUILTIN_Hashable) && is_collection(types, ty)) {
    ms_strbuild_append(out, lead);
    ms_strbuild_append_text(out, "collections have no Hashable implementation, so use a type as the key or join the "
                                 "elements into a String");
  } else if (ms_ty_is(types, bound, MS_BUILTIN_Hashable) && ms_check_closeable(program, ty)) {
    ms_strbuild_append(out, lead);
    ms_strbuild_append_text(out, "it is or holds a Closeable resource, which is closed once by its owner and cannot "
                                 "be a set element or map key; key on a plain value such as an Int id instead");
  } else if (ms_ty_is(types, bound, MS_BUILTIN_Clonable) && !variable) {
    ms_strbuild_append(out, lead);
    ms_strbuild_append_text(out, "it is or holds ");
    ms_strbuild_append_text(out, ms_check_closeable(program, ty) ? "a Closeable resource, which has one owner and closes once"
                                 : holds_function(types, ty)     ? "a function value, which owns its captures and has one owner"
                                                                 : "a native value without a `clone` of its own, which has one owner");
    ms_strbuild_append_text(out, ", so it cannot be cloned; move it, or use it in place");
  } else if (ms_ty_kind(types, ty) == MS_TY_TYPE || ms_ty_kind(types, ty) == MS_TY_ALTERNATIVE) {
    ms_strbuild_append(out, lead);
    ms_strbuild_append_text(out, "give ");
    show(program, out, ty);
    ms_strbuild_append_text(out, " the methods ");
    show(program, out, bound);
    ms_strbuild_append_text(out, " declares, or ");
    ms_strbuild_append_text(out, alternative);
  } else {
    ms_strbuild_append(out, lead);
    ms_strbuild_append_text(out, alternative);
  }
  ms_strbuild_free(&path);
  ms_strbuild_free(&prefix);
}

bool ms_check_bounds_hold_with(MsCheckProgram *program, MsTy variable, MsTy arg, const MsTy *vars, const MsTy *args,
                               size_t count, const char *alternative, MsString *why) {
  const MsTyVariable *record = ms_ty_variable(&program->types, variable);
  if (record == NULL) {
    return true;
  }
  for (size_t at = 0; at < record->bounds.len; at++) {
    const MsTy wanted = ms_ty_subst(&program->types, record->bounds.ptr[at], vars, args, count);
    if (ms_check_implements(program, arg, wanted)) {
      continue;
    }
    if (why != NULL) {
      MsStrBuild text = ms_strbuild_new();
      ms_check_unsatisfied_message(program, arg, wanted, alternative, &text);
      *why = ms_strbuild_finish(&text);
    }
    return false;
  }
  return true;
}

bool ms_check_bounds_hold(MsCheckProgram *program, MsTy variable, MsTy arg, MsString *why) {
  return ms_check_bounds_hold_with(program, variable, arg, NULL, NULL, 0, "pass a type that already implements it", why);
}

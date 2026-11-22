/* compiler/lower/lower_native.c: calls to bodiless standard operations (`fn String.trim() String`, the
 * operations of intrinsics.ms). The runtime function an operation maps to is named from its declaration: the
 * receiver type's lowercase name, then the operation (`msrt_string_trim`, `msrt_int_to_string`). The few that are
 * one MIR instruction are written out here: copying a string is `clone`, and joining two strings is the concat
 * function with its result fresh. */
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_analysis.h"

static bool name_is(MsSpan name, const char *text) {
  return ms_span_is_text(name, text);
}

/* `msrt_<receiver>_<operation>`: the receiver's type name lowercased. */
static MsName runtime_name(LowerFn *fn, MsTy receiver, MsSpan operation) {
  const MsTyTable *types = &fn->cx->program->types;
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "msrt_");
  const char *type_name = ms_builtin_name(ms_ty_builtin(types, receiver));
  for (const char *at = type_name; *at != '\0'; at++) {
    ms_strbuild_append_byte(&text, (uint8_t)(*at >= 'A' && *at <= 'Z' ? *at - 'A' + 'a' : *at));
  }
  ms_strbuild_append_byte(&text, '_');
  ms_strbuild_append(&text, operation);
  const MsName name = mir_name(fn->cx->module, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  return name;
}

/* The runtime function `name` taking the types of `args` and returning `ret`. */
static uint32_t runtime_extern(LowerFn *fn, MsName name, const MirValue *args, uint32_t nargs, MirTy ret) {
  MirParam *params = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, MirParam, (size_t)nargs + 1);
  for (uint32_t index = 0; index < nargs; index++) {
    params[index] = (MirParam){mir_b_ty(&fn->b, args[index]), (uint8_t)MM_BORROW};
  }
  const MirExtern def = {.name = name, .params = params, .nparams = nargs, .ret = ret,
                         .fresh = mir_needs_drop(fn->cx->module, ret)};
  return mir_extern_intern(fn->cx->module, &def);
}

MirValue fn_runtime_call(LowerFn *fn, MsName name, const MirValue *args, uint32_t nargs, MirTy ret) {
  const uint32_t external = runtime_extern(fn, name, args, nargs, ret);
  const MirValue result = mir_b_call_rt(&fn->b, external, args, nargs);
  fn_own_result(fn, result);
  return result;
}

MirValue fn_native_call(LowerFn *fn, const MsExpr *expr, const MsCall *call, const MirValue *args, MirTy ret) {
  const MsExpr *callee = expr->u.call.callee;
  if (callee->kind != MS_E_MEMBER || call->arg_count == 0) {
    (void)fn_fail(fn, "a standard operation is called through a receiver");
    return MIR_NONE;
  }
  const MsSpan operation = ms_names_span(fn->cx->program->names, callee->u.member.name);
  if (name_is(operation, "to_string") && mir_b_ty(&fn->b, args[0]) == MIR_STR) {
    const MirImm none = {0};
    return fn_emit(fn, MOP_Clone, args, 1, none, MIR_STR);
  }
  return fn_runtime_call(fn, runtime_name(fn, call->callee.owner, operation), args, call->arg_count, ret);
}

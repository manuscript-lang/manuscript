/* compiler/lower/lower_native.c: calls to bodiless standard operations (`fn String.trim() String`, the
 * operations of intrinsics.ms). The runtime function an operation maps to is named from its declaration: the
 * receiver type's lowercase name, then the operation (`msrt_string_trim`, `msrt_int_to_string`). The few that are
 * one MIR instruction are written out here: copying a string is `clone`, and joining two strings is the concat
 * function with its result fresh. */
#include "compiler/lower/lower_fn.h"
#include "compiler/lower/native_sigs.h"
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

/* The `index`th type argument of a collection type (a map's key, value; a set's element), or MIR_NONE. */
static MirTy collection_arg(const LowerFn *fn, const MirTyData *data, uint32_t index) {
  if (data->kind == MK_LIST) {
    return index == 0 ? data->elem : MIR_NONE;
  }
  (void)fn;
  return index < data->nargs ? data->args[index] : MIR_NONE;
}

/* Whether `type` is a list, a map or a set: what the descriptor parameters of a native describe. */
static bool is_collection(const LowerFn *fn, MirTy type) {
  const MirTyData *data = mir_ty_data(fn->cx->module, type);
  return data->kind == MK_LIST || (data->kind == MK_OBJ && data->obj_class == MIR_OBJ_COLLECTION);
}

/* The descriptor argument `kind` asks for, from the first collection among `args`; false when there is none. */
static bool descriptor_argument(LowerFn *fn, uint8_t kind, const MirValue *args, uint32_t nargs, MirValue *out) {
  for (uint32_t at = 0; at < nargs; at++) {
    const MirTy type = mir_b_ty(&fn->b, args[at]);
    if (!is_collection(fn, type)) {
      continue;
    }
    const MirTyData *data = mir_ty_data(fn->cx->module, type);
    const MirTy element = collection_arg(fn, data, kind == NS_VAL_DESC ? 1 : 0);
    if (element == MIR_NONE) {
      return false;
    }
    const MirImm imm = {.tag = MI_TY, .a = element};
    *out = fn_emit(fn, MOP_TypeDesc, NULL, 0, imm, MIR_PTR);
    return true;
  }
  return false;
}

static bool is_result_kind(uint8_t kind) {
  return kind == NS_VEC_MUT || kind == NS_STR_MUT || kind == NS_MAP_MUT || kind == NS_ADDR_MUT ||
         kind == NS_OUT_SCALAR;
}

/* The operands the runtime function `sig` wants for a call with the source operands `args`: the descriptors
 * its signature names are added after the collection they describe, and the trailing result parameter is the
 * call's result. False when the source operands do not fit the signature. */
static bool signature_arguments(LowerFn *fn, const MsNativeSig *sig, const MirValue *args, uint32_t nargs,
                                MirTy ret, MirValue *out, uint32_t *count) {
  uint32_t params = sig->count;
  if (ret != MIR_VOID && params > 0 && is_result_kind(sig->kinds[params - 1])) {
    params--;
  }
  uint32_t next = 0;
  uint32_t used = 0;
  for (uint32_t at = 0; at < params; at++) {
    const uint8_t kind = sig->kinds[at];
    if (kind == NS_ELEM_DESC || kind == NS_KEY_DESC || kind == NS_VAL_DESC) {
      if (!descriptor_argument(fn, kind, args, nargs, &out[used++])) {
        return false;
      }
    } else if (next < nargs) {
      out[used++] = args[next++];
    } else {
      return false;
    }
  }
  *count = used;
  return next == nargs;
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
  const MsName name = runtime_name(fn, call->callee.owner, operation);
  const MsNativeSig *sig = ms_native_sig_find(ms_names_span(&fn->cx->module->names, name));
  MirValue wanted[NS_MAX_PARAMS];
  uint32_t count = 0;
  if (sig != NULL && call->arg_count <= NS_MAX_PARAMS &&
      signature_arguments(fn, sig, args, call->arg_count, ret, wanted, &count)) {
    return fn_runtime_call(fn, name, wanted, count, ret);
  }
  return fn_runtime_call(fn, name, args, call->arg_count, ret);
}

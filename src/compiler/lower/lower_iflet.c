/* compiler/lower/lower_iflet.c: `if x := value:`. The test says whether the value holds a payload (an Optional is
 * some, a Result is ok); the then branch binds the payload to the pattern's local. */
#include "compiler/lower/lower_fn.h"

/* The alternative case that holds the payload: a Result's `ok`, which is its first case. */
enum { OK_CASE = 0 };

/* The scrutinee's MIR type kind, after reporting a failure for one that holds no payload. */
static bool holds_payload(LowerFn *fn, MirValue value) {
  const MirModule *module = fn->cx->module;
  const MirTyData *data = mir_ty_data(module, mir_b_ty(&fn->b, value));
  if (data->kind == MK_OPT) {
    return true;
  }
  if (data->kind == MK_ALT && module->alts.ptr[data->id].std == MSTD_RESULT) {
    return true;
  }
  return fn_fail(fn, "`if` with a binding tests an Optional or a Result");
}

MirValue fn_iflet_test(LowerFn *fn, MirValue value) {
  if (!holds_payload(fn, value)) {
    return MIR_NONE;
  }
  const MirTyData *data = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, value));
  if (data->kind == MK_OPT) {
    return mir_b_emit(&fn->b, MOP_OptIsSome, &value, 1, (MirImm){0}, MIR_BOOL);
  }
  const MirValue tag = mir_b_emit(&fn->b, MOP_AltTag, &value, 1, (MirImm){0}, MIR_INT);
  return mir_b_icmp(&fn->b, MCC_EQ, tag, mir_b_iconst(&fn->b, OK_CASE));
}

bool fn_iflet_bind(LowerFn *fn, const MsPattern *pattern, MirValue value) {
  const MsRef *ref = ms_facts_ref(fn->facts, pattern->id);
  if (pattern->kind != MS_P_NAME || ref == NULL || ref->kind != MS_REF_LOCAL) {
    return fn_fail(fn, "only a name can be bound by `if` for now");
  }
  const MirModule *module = fn->cx->module;
  const MirTyData *data = mir_ty_data(module, mir_b_ty(&fn->b, value));
  MirValue payload = MIR_NONE;
  MirTy ty = MIR_VOID;
  if (data->kind == MK_OPT) {
    ty = data->elem;
    payload = mir_b_emit(&fn->b, MOP_OptGet, &value, 1, (MirImm){0}, ty);
  } else {
    const MirCaseDef *ok = &module->alts.ptr[data->id].cases[OK_CASE];
    ty = ok->nfields > 0 ? ok->fields[0].ty : MIR_VOID;
    const MirImm imm = {.tag = MI_ALTFIELD, .a = data->id, .b = OK_CASE, .c = 0};
    payload = mir_b_emit(&fn->b, MOP_AltGet, &value, 1, imm, ty);
  }
  mir_b_def_var(&fn->b, fn_local(fn, ref->local, ty), payload);
  return !fn->failed;
}

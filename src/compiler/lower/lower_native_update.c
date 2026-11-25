/* compiler/lower/lower_native_update.c: `Map.update` written out in line: one probe, and the change thunk called on a hit. */
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_analysis.h"

/* `Map.update` on a map the optimiser can probe (`opt_probe`): the entry of a present key is found in line and its value
 * changed there by the thunk; only an absent key calls the runtime, which appends the entry. `wanted` is the runtime's
 * operands: map address, descriptors, key, initial value, thunk, closure. */
bool fn_update_in_line(LowerFn *fn, MsName name, const MirValue *wanted, uint32_t count) {
  const uint32_t thunk = fn->update_thunk;
  const MirTy map_ty = fn->update_map;
  fn->update_thunk = MIR_NONE;
  if (thunk == MIR_NONE || count != 7 || !ms_span_is_text(ms_names_span(&fn->cx->module->names, name), "msrt_map_update") ||
      mir_b_ty(&fn->b, wanted[0]) != MIR_PTR) {
    return false;
  }
  const MsSpan probe_text = ms_span_of_text("msrt_map_get_ptr");
  const MirRole role = fn_native_role(fn->cx->module, probe_text, map_ty);
  if (role == MR_NONE || mir_needs_drop(fn->cx->module, mir_ty_data(fn->cx->module, map_ty)->args[1])) {
    return false;
  }
  MirParam *params = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, MirParam, 4);
  for (uint32_t at = 0; at < 4; at++) {
    params[at] = (MirParam){mir_b_ty(&fn->b, wanted[at]), MM_BORROW}; /* the key is passed as the value it is, as `runtime_extern` declares it */
  }
  const MirExtern def = {.name = mir_name(fn->cx->module, probe_text), .params = params, .nparams = 4, .ret = MIR_PTR,
                         .role = (uint8_t)role};
  const MirValue probe_args[4] = {wanted[0], wanted[1], wanted[2], wanted[3]};
  const MirValue entry = mir_b_call_rt(&fn->b, mir_extern_intern(fn->cx->module, &def), probe_args, 4);
  const MirValue absent = mir_b_emit(&fn->b, MOP_PtrIsNull, &entry, 1, (MirImm){0}, MIR_BOOL);
  const MirBlock miss = mir_b_new_block(&fn->b);
  const MirBlock hit = mir_b_new_block(&fn->b);
  const MirBlock join = mir_b_new_block(&fn->b);
  mir_b_br_if(&fn->b, absent, miss, NULL, 0, hit, NULL, 0);
  mir_b_seal_block(&fn->b, miss);
  mir_b_seal_block(&fn->b, hit);
  mir_b_switch_to(&fn->b, hit);
  const MirValue step[2] = {wanted[6], entry};
  (void)mir_b_call(&fn->b, thunk, step, 2);
  mir_b_br(&fn->b, join, NULL, 0);
  mir_b_switch_to(&fn->b, miss);
  MirValue operands[7];
  for (uint32_t at = 0; at < count; at++) {
    operands[at] = wanted[at];
  }
  (void)fn_runtime_call(fn, name, operands, count, MIR_VOID);
  mir_b_br(&fn->b, join, NULL, 0);
  mir_b_seal_block(&fn->b, join);
  mir_b_switch_to(&fn->b, join);
  return true;
}


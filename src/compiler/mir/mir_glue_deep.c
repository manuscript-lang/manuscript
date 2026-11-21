/* compiler/mir/mir_glue_deep.c: the slot and block functions descriptors and interface payloads point at, and
 * the wrappers that bound the stack use of recursive data. */
#include "compiler/mir/mir_glue_internal.h"

static const MirParam ptr_param = {MIR_PTR, MM_BORROW};

/* ---- slot and block functions ---- */

/* `fn(slot)`: drops the value stored at `slot`. */
uint32_t mirgl_make_slot_drop(MirModule *module, MirTy ty) {
  MirBuilder b;
  mir_b_init(&b, module, mirgl_name(module, module->funcs.len, "slot_drop"), &ptr_param, 1, MIR_VOID);
  MirValue slot;
  mir_b_params(&b, &slot, 1);
  mirgl_drop(&b, mirgl_take(&b, slot, ty));
  mir_b_ret(&b, MIR_NONE);
  return mirgl_finish(&b);
}

/* `fn(src, dst)`: clones the value at `src` into uninitialised `dst`. */
uint32_t mirgl_make_slot_copy(MirModule *module, MirTy ty) {
  const MirParam ptrs[2] = {ptr_param, ptr_param};
  MirBuilder b;
  mir_b_init(&b, module, mirgl_name(module, module->funcs.len, "slot_copy"), ptrs, 2, MIR_VOID);
  MirValue slots[2];
  mir_b_params(&b, slots, 2);
  mirgl_put(&b, slots[1], mirgl_clone(&b, mirgl_load(&b, slots[0], ty)));
  mir_b_ret(&b, MIR_NONE);
  return mirgl_finish(&b);
}

/* `fn(block)`: drops the `ty` value the heap block holds and frees the block. */
uint32_t mirgl_make_block_drop(MirModule *module, MirTy ty) {
  const bool needs = mir_needs_drop(module, ty);
  MirBuilder b;
  mir_b_init(&b, module, mirgl_name(module, module->funcs.len, "block_drop"), &ptr_param, 1, MIR_VOID);
  MirValue block;
  mir_b_params(&b, &block, 1);
  if (needs) {
    mirgl_drop(&b, mirgl_take(&b, block, ty));
  }
  mirgl_free(&b, block);
  mir_b_ret(&b, MIR_NONE);
  return mirgl_finish(&b);
}

/* `fn(block) -> block`: a new heap block holding a clone of the `ty` value in `block`. */
uint32_t mirgl_make_block_clone(MirModule *module, MirTy ty) {
  const int64_t size = mirgl_mem_size(module, ty);
  const MirTy int_param = MIR_INT;
  const uint32_t alloc = mirgl_extern(module, "msrt_alloc", &int_param, 1, MIR_PTR, true);
  MirBuilder b;
  mir_b_init(&b, module, mirgl_name(module, module->funcs.len, "block_clone"), &ptr_param, 1, MIR_PTR);
  MirValue block;
  mir_b_params(&b, &block, 1);
  const MirValue copy = mirgl_clone(&b, mirgl_load(&b, block, ty));
  const MirValue length = mir_b_iconst(&b, size > 1 ? size : 1);
  const MirValue fresh = mirgl_call_rt(&b, alloc, &length, 1);
  mirgl_put(&b, fresh, copy);
  mir_b_ret(&b, fresh);
  return mirgl_finish(&b);
}

/* ---- deep recursion ---- */

/* The slot drop or slot copy of `ty` the wrapper calls: the one already made, else a new one recorded now. */
static uint32_t slot_glue(MirModule *module, MirGlue *glue, MirGlueKind kind, MirTy ty) {
  uint32_t func = mir_glue_find(glue, kind, ty, 0, 0);
  if (func == MIR_NONE) {
    func = kind == MG_SLOT_DROP ? mirgl_make_slot_drop(module, ty) : mirgl_make_slot_copy(module, ty);
    mirgl_record(glue, kind, ty, 0, 0, func);
  }
  return func;
}

/* The parked branch of the deep drop: the value is copied to a heap block and handed to the runtime's
 * worklist, to be dropped from the top of the stack later through its slot drop function. */
static void park_value(MirBuilder *b, MirValue value, MirTy ty, uint32_t slot_drop) {
  MirModule *module = b->module;
  const MirTy int_param = MIR_INT;
  const MirTy two_ptrs[2] = {MIR_PTR, MIR_PTR};
  const uint32_t defer = mirgl_extern(module, "msrt_drop_defer", two_ptrs, 2, MIR_VOID, false);
  const uint32_t alloc = mirgl_extern(module, "msrt_alloc", &int_param, 1, MIR_PTR, true);
  const int64_t size = mirgl_mem_size(module, ty);
  const MirValue length = mir_b_iconst(b, size > 1 ? size : 1);
  const MirValue block = mirgl_call_rt(b, alloc, &length, 1);
  mirgl_put(b, block, value);
  const MirValue func = mirgl_val(b, MOP_FuncAddr, NULL, 0, mirgl_imm_func(slot_drop), MIR_PTR);
  const MirValue args[2] = {func, block};
  (void)mirgl_call_rt(b, defer, args, 2);
  mir_b_ret(b, MIR_NONE);
}

/* The drop function of recursive data: its nesting is bounded. When the stack is nearly used up the value is
 * parked; otherwise `body` runs, counted as one more level. */
uint32_t mirgl_wrap_deep_drop(MirModule *module, MirGlue *glue, MirTy ty, uint32_t body) {
  mir_idlist_push(&glue->bodies, body);
  const uint32_t slot_drop = slot_glue(module, glue, MG_SLOT_DROP, ty);
  const uint32_t enter = mirgl_extern(module, "msrt_drop_enter", NULL, 0, MIR_INT, false);
  const uint32_t leave = mirgl_extern(module, "msrt_drop_leave", NULL, 0, MIR_VOID, false);
  const MirParam param = {ty, MM_MOVE};
  MirBuilder b;
  mir_b_init(&b, module, mirgl_name(module, module->funcs.len, "drop_deep"), &param, 1, MIR_VOID);
  MirValue value;
  mir_b_params(&b, &value, 1);
  const MirBlock enter_block = mir_b_new_block(&b);
  const MirBlock park = mir_b_new_block(&b);
  const MirBlock run = mir_b_new_block(&b);
  const MirBlock leave_block = mir_b_new_block(&b);
  const MirBlock done = mir_b_new_block(&b);
  const MirImm headroom = mir_imm_int(MIRGL_DEEP_DROP_HEADROOM);
  const MirValue deep = mirgl_val(&b, MOP_StackNear, NULL, 0, headroom, MIR_BOOL);
  mir_b_br_if(&b, deep, enter_block, NULL, 0, run, NULL, 0);
  mir_b_switch_to(&b, enter_block);
  const MirValue defer_it = mirgl_call_rt(&b, enter, NULL, 0);
  const MirValue parked = mir_b_icmp(&b, MCC_NE, defer_it, mir_b_iconst(&b, 0));
  mir_b_br_if(&b, parked, park, NULL, 0, run, NULL, 0);
  mir_b_switch_to(&b, park);
  park_value(&b, value, ty, slot_drop);
  mir_b_switch_to(&b, run);
  (void)mirgl_val(&b, MOP_Call, &value, 1, mirgl_imm_func(body), MIR_NONE);
  mir_b_br_if(&b, deep, leave_block, NULL, 0, done, NULL, 0);
  mir_b_switch_to(&b, leave_block);
  (void)mirgl_call_rt(&b, leave, NULL, 0);
  mir_b_br(&b, done, NULL, 0);
  mir_b_switch_to(&b, done);
  mir_b_ret(&b, MIR_NONE);
  return mirgl_finish(&b);
}

/* The clone function of recursive data: when the stack is nearly used up the copy runs on a new stack segment
 * through the slot copy function; otherwise `body` runs. */
uint32_t mirgl_wrap_deep_clone(MirModule *module, MirGlue *glue, MirTy ty, uint32_t body) {
  mir_idlist_push(&glue->bodies, body);
  const uint32_t slot_copy = slot_glue(module, glue, MG_SLOT_COPY, ty);
  const MirTy three_ptrs[3] = {MIR_PTR, MIR_PTR, MIR_PTR};
  const uint32_t grown = mirgl_extern(module, "msrt_slot_copy_grown", three_ptrs, 3, MIR_VOID, false);
  const MirParam param = {ty, MM_BORROW};
  MirBuilder b;
  mir_b_init(&b, module, mirgl_name(module, module->funcs.len, "clone_deep"), &param, 1, ty);
  MirValue value;
  mir_b_params(&b, &value, 1);
  const MirBlock grow = mir_b_new_block(&b);
  const MirBlock run = mir_b_new_block(&b);
  const MirValue low = mirgl_val(&b, MOP_StackNear, NULL, 0, mir_imm_int(0), MIR_BOOL);
  mir_b_br_if(&b, low, grow, NULL, 0, run, NULL, 0);
  mir_b_switch_to(&b, grow);
  const MirValue src = mirgl_slot(&b, ty);
  const MirValue store_args[2] = {src, value};
  (void)mirgl_val(&b, MOP_Store, store_args, 2, (MirImm){0}, MIR_NONE);
  const MirValue dst = mirgl_slot(&b, ty);
  const MirValue func = mirgl_val(&b, MOP_FuncAddr, NULL, 0, mirgl_imm_func(slot_copy), MIR_PTR);
  const MirValue grown_args[3] = {func, src, dst};
  (void)mirgl_call_rt(&b, grown, grown_args, 3);
  mir_b_ret(&b, mirgl_take(&b, dst, ty));
  mir_b_switch_to(&b, run);
  mir_b_ret(&b, mirgl_val(&b, MOP_Call, &value, 1, mirgl_imm_func(body), ty));
  return mirgl_finish(&b);
}

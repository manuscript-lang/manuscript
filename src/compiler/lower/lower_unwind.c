/* compiler/lower/lower_unwind.c: the exit a call that may park or fault leaves through when a cancel or fault is
 * pending. After the call the program tests the task's `unwinding` byte; when it is set, the function leaves as a
 * `return` does, through the same scope exit (`fn_scope_unwind`), so elaboration closes whatever is live there like it
 * does on any early exit. A later pass deletes the test after calls that provably cannot park or fault. */
#include "base/env.h"
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_pass.h"
#include "compiler/mir/mir_analysis.h"

const MirInst *fn_just_made(const LowerFn *fn, MirValue value) {
  if (value == MIR_NONE) {
    return NULL;
  }
  const MirInstList *insts = &fn->b.func.blocks.ptr[fn->b.cur].insts;
  if (insts->len > 0 && insts->ptr[insts->len - 1].res == value) {
    return &insts->ptr[insts->len - 1];
  }
  if (fn->site_value == value && fn->site_block < fn->b.func.blocks.len) {
    const MirInstList *made = &fn->b.func.blocks.ptr[fn->site_block].insts;
    return fn->site_index < made->len && made->ptr[fn->site_index].res == value ? &made->ptr[fn->site_index] : NULL;
  }
  return NULL;
}

void fn_unwind_site(LowerFn *fn, MirValue result) {
  const MirInstList *before = &fn->b.func.blocks.ptr[fn->b.cur].insts;
  size_t at = before->len;
  while (result != MIR_NONE && at > 0 && before->ptr[at - 1].res != result && before->ptr[at - 1].res == MIR_NONE) {
    at--; /* ownership markers follow the instruction that made the result */
  }
  const bool made = result != MIR_NONE && at > 0 && before->ptr[at - 1].res == result;
  const uint32_t made_at = made ? (uint32_t)at - 1 : 0;
  const MirBlock made_in = fn->b.cur;
  if (made) { /* a constructor builds a value and calls nothing: it can neither fault nor park */
    const MirOp op = (MirOp)before->ptr[made_at].op;
    if (op == MOP_TypeNew || op == MOP_IfaceNew || op == MOP_AltNew || op == MOP_OptSome) {
      return;
    }
  }
  /* A compiled callee that leaves this way returns `undef`: its result is dead and nothing here may close it. A
   * native hands back a value that is still its caller's to drop. */
  bool dead_result = false;
  if (made) {
    const MirInst *call = &before->ptr[made_at];
    MirMode mode = MM_BORROW;
    dead_result = (call->op == MOP_Call || call->op == MOP_CallInd || call->op == MOP_CallMethod) &&
                  mir_result_mode(fn->cx->module, &fn->b.func, call, &mode) && mode == MM_MOVE;
  }
  if (fn->terminated || fn->failed || fn->b.func.unwind_only ||
      fn->b.func.closer) {
    return;
  }
  if (fn->cx->unwinding == MIR_NONE) {
    fn->cx->unwinding = mir_extern_get(fn->cx->module, ms_span_of_text("msrt_unwinding"), NULL, 0, MIR_BOOL, true, MR_UNWINDING);
  }
  /* A fresh result is not owned by any scope yet: it is, for the exit, and the next branch disowns it again. */
  const MirValue set = mir_b_emit(&fn->b, MOP_CallRt, NULL, 0, (MirImm){.tag = MI_EXT, .a = fn->cx->unwinding}, MIR_BOOL);
  const MirBlock leave = mir_b_new_block(&fn->b);
  const MirBlock next = mir_b_new_block(&fn->b);
  mir_b_br_if(&fn->b, set, leave, NULL, 0, next, NULL, 0);
  mir_b_seal_block(&fn->b, leave);
  mir_b_seal_block(&fn->b, next);
  mir_b_switch_to(&fn->b, leave);
  fn->b.func.blocks.ptr[leave].cold = true; /* the exit is out of line: the byte is almost never set */
  if (dead_result) {
    (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &result, 1, (MirImm){0}, MIR_NONE);
    (void)mir_b_emit(&fn->b, MOP_Forget, &result, 1, (MirImm){0}, MIR_NONE); /* dead: nothing to release */
  }
  /* The closes on the way out run as on any exit: the pending state is set aside while they do, so a close may park and
   * its own calls do not leave, and is delivered again before this function returns. */
  const uint32_t pause = mir_extern_get(fn->cx->module, ms_span_of_text("msrt_unwinding_pause"), NULL, 0, MIR_VOID, false, MR_NONE);
  const uint32_t resume = mir_extern_get(fn->cx->module, ms_span_of_text("msrt_unwinding_resume"), NULL, 0, MIR_VOID, false, MR_NONE);
  (void)mir_b_emit(&fn->b, MOP_CallRt, NULL, 0, (MirImm){.tag = MI_EXT, .a = pause}, MIR_VOID);
  fn_scope_unwind(fn, 0);
  (void)mir_b_emit(&fn->b, MOP_CallRt, NULL, 0, (MirImm){.tag = MI_EXT, .a = resume}, MIR_VOID);
  MirValue undef = MIR_NONE;
  if (fn->b.func.ret != MIR_VOID) {
    undef = mir_b_emit(&fn->b, MOP_Undef, NULL, 0, fn->returns_borrow ? mir_imm_int(1) : mir_imm_none(), fn->b.func.ret);
  }
  mir_b_ret(&fn->b, undef);
  mir_b_switch_to(&fn->b, next);
  fn->site_value = made ? result : MIR_NONE;
  fn->site_block = made_in;
  fn->site_index = made_at;
}

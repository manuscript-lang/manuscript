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


/* Whether `value` is the result of a call just emitted (ownership markers may follow it). */
bool fn_made_by_call(const LowerFn *fn, MirValue value) {
  if (value == MIR_NONE) {
    return false;
  }
  const MirInstList *insts = &fn->b.func.blocks.ptr[fn->b.cur].insts;
  size_t at = insts->len;
  while (at > 0 && insts->ptr[at - 1].res == MIR_NONE) {
    at--;
  }
  if (at == 0 || insts->ptr[at - 1].res != value) {
    return false;
  }
  const MirInst *call = &insts->ptr[at - 1];
  if (call->op == MOP_CallRt && call->imm.tag == MI_EXT && fn->cx->module->externs.ptr[call->imm.a].leaf) {
    return false; /* a leaf runtime call neither parks nor faults */
  }
  const MirOp op = (MirOp)call->op;
  return op == MOP_Call || op == MOP_CallInd || op == MOP_CallRt || op == MOP_CallMethod;
}

/* Returns the undefined result: what a function that leaves on a fault hands back. */
static void leave_with_undef(LowerFn *fn) {
  MirValue undef = MIR_NONE;
  if (fn->b.func.ret != MIR_VOID) {
    undef = mir_b_emit(&fn->b, MOP_Undef, NULL, 0, fn->returns_borrow ? mir_imm_int(1) : mir_imm_none(), fn->b.func.ret);
  }
  mir_b_ret(&fn->b, undef);
}

/* Leaves the function as a delivered cancel or a posted fault does: the closes run as on any exit, with the pending
 * state set aside while they do, so a close may park and its own calls do not leave; it is delivered again before the
 * function returns. The result is undefined. The current block ends here. */
void fn_unwind_exit(LowerFn *fn) {
  if (fn->leaving) {
    /* A fault while leaving on a fault (a check in a write-back, say) repeats one the normal path passed: the program
     * ends there, as a panic while unwinding does elsewhere. */
    mir_b_fault(&fn->b, MF_POSTED);
    return;
  }
  const uint32_t pause = mir_extern_get(fn->cx->module, ms_span_of_text("msrt_unwinding_pause"), NULL, 0, MIR_VOID, false, MR_NONE);
  const uint32_t resume = mir_extern_get(fn->cx->module, ms_span_of_text("msrt_unwinding_resume"), NULL, 0, MIR_VOID, false, MR_NONE);
  (void)mir_b_emit(&fn->b, MOP_CallRt, NULL, 0, (MirImm){.tag = MI_EXT, .a = pause}, MIR_VOID);
  const bool was_leaving = fn->leaving;
  fn->leaving = true;
  fn_scope_unwind(fn, 0);
  fn->leaving = was_leaving;
  (void)mir_b_emit(&fn->b, MOP_CallRt, NULL, 0, (MirImm){.tag = MI_EXT, .a = resume}, MIR_VOID);
  leave_with_undef(fn);
}

void fn_unwind_site(LowerFn *fn, MirValue result) {
  if (result != MIR_NONE && fn->sited == result + 1) {
    return; /* the call's own lowering put the site where its held values were still owned */
  }
  fn->sited = result == MIR_NONE ? 0 : result + 1;
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
  /* A callee that leaves this way hands back no value: a compiled one returns `undef`, a native an empty result. The
   * result is dead and nothing here may close or drop it. */
  bool dead_result = false;
  if (made) {
    const MirInst *call = &before->ptr[made_at];
    MirMode mode = MM_BORROW;
    dead_result = (call->op == MOP_Call || call->op == MOP_CallInd || call->op == MOP_CallMethod || call->op == MOP_CallRt) &&
                  mir_result_mode(fn->cx->module, &fn->b.func, call, &mode) && mode == MM_MOVE;
  }
  if (fn->terminated || fn->failed || fn->b.func.unwind_only || fn->b.func.closer) {
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
  fn_unwind_exit(fn);
  mir_b_switch_to(&fn->b, next);
  fn->site_value = made ? result : MIR_NONE;
  fn->site_block = made_in;
  fn->site_index = made_at;
}

/* Whether `op` is a check whose fault leaves through a site of its own: the instruction right after it. */
static bool has_fault_site(MirOp op) {
  switch (op) {
  case MOP_IAddChk: case MOP_ISubChk: case MOP_IMulChk: case MOP_INegChk:
  case MOP_UAddChk: case MOP_USubChk: case MOP_UMulChk:
  case MOP_SDivChk: case MOP_SRemChk: case MOP_UDivChk: case MOP_URemChk:
  case MOP_NarrowChk:
  case MOP_ListGet: case MOP_ListGetNn: case MOP_ListAddr: case MOP_OptUnwrap:
    return true;
  default:
    return false;
  }
}

/* After a checked instruction: the fault the check posts leaves by an exit that closes what is owned here, as a
 * call's does. The test is constant false on the normal path: only the check's cold path reaches `leave`. */
void fn_fault_site(LowerFn *fn, MirValue result) {
  const MirInst *made = fn_just_made(fn, result);
  if (made == NULL || !has_fault_site((MirOp)made->op) || fn->terminated || fn->failed || fn->b.func.unwind_only) {
    return;
  }
  const MirValue site = mir_b_emit(&fn->b, MOP_FaultSite, &result, 1, (MirImm){0}, MIR_BOOL);
  const MirBlock leave = mir_b_new_block(&fn->b);
  const MirBlock next = mir_b_new_block(&fn->b);
  mir_b_br_if(&fn->b, site, leave, NULL, 0, next, NULL, 0);
  mir_b_seal_block(&fn->b, leave);
  mir_b_seal_block(&fn->b, next);
  mir_b_switch_to(&fn->b, leave);
  fn->b.func.blocks.ptr[leave].cold = true;
  fn_unwind_exit(fn);
  mir_b_switch_to(&fn->b, next);
}

/* An instruction that can fault, and the exit its fault leaves by. */
MirValue fn_checked_emit(LowerFn *fn, MirOp op, const MirValue *args, uint32_t nargs, MirImm imm, MirTy ty) {
  const MirValue result = mir_b_emit(&fn->b, op, args, nargs, imm, ty);
  fn_fault_site(fn, result);
  return result;
}

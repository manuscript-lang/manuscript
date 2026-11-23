/* compiler/lower/lower_unwind.c: the exit a call that may park or fault leaves through when a cancel or fault is
 * pending. After the call the program tests the task's `unwinding` byte; when it is set, the function leaves as a
 * `return` does, through the same scope exit (`fn_scope_unwind`), so elaboration closes whatever is live there like it
 * does on any early exit. A later pass deletes the test after calls that provably cannot park or fault. */
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_pass.h"

void fn_unwind_site(LowerFn *fn, MirValue result) {
  if (!fn->cx->unwind_exits || fn->terminated || fn->failed || fn->b.func.unwind_only) {
    return;
  }
  if (fn->cx->unwinding == MIR_NONE) {
    fn->cx->unwinding = mir_extern_get(fn->cx->module, ms_span_of_text("msrt_unwinding"), NULL, 0, MIR_UINT8, true, MR_UNWINDING);
  }
  /* A fresh result is not owned by any scope yet: it is, for the exit, and the next branch disowns it again. */
  const bool owns = result != MIR_NONE && mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, result)) && fn_fresh_owner(fn, result);
  if (owns) {
    fn_own(fn, fn_scope(fn), result);
  }
  const MirValue byte = mir_b_emit(&fn->b, MOP_CallRt, NULL, 0, (MirImm){.tag = MI_EXT, .a = fn->cx->unwinding}, MIR_UINT8);
  const MirValue zero = mir_b_emit(&fn->b, MOP_IConst, NULL, 0, mir_imm_int(0), MIR_UINT8);
  const MirValue pair[2] = {byte, zero};
  const MirValue set = mir_b_emit(&fn->b, MOP_UICmp, pair, 2, mir_imm_cc(MCC_NE), MIR_BOOL);
  const MirBlock leave = mir_b_new_block(&fn->b);
  const MirBlock next = mir_b_new_block(&fn->b);
  mir_b_br_if(&fn->b, set, leave, NULL, 0, next, NULL, 0);
  mir_b_seal_block(&fn->b, leave);
  mir_b_seal_block(&fn->b, next);
  mir_b_switch_to(&fn->b, leave);
  fn_scope_unwind(fn, 0);
  MirValue undef = MIR_NONE;
  if (fn->b.func.ret != MIR_VOID) {
    undef = mir_b_emit(&fn->b, MOP_Undef, NULL, 0, fn->b.func.ret_borrowed ? mir_imm_int(1) : mir_imm_none(), fn->b.func.ret);
  }
  mir_b_ret(&fn->b, undef);
  mir_b_switch_to(&fn->b, next);
  if (owns) {
    const MirImm none = {0};
    (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &result, 1, none, MIR_NONE);
  }
}

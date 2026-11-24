/* Owns `undef`. */
#include "compiler/emit/emit_cx.h"

/* `undef`: any value of the type: zero, a held value's whole cell by one memset, a leaf in a register as the constant
 * the copy forwarding then folds into its users. */
static void undef(EmitCx *cx, const MirInst *inst) {
  if (emit_wide_zero(cx, inst->res)) {
    return;
  }
  MsSpan leaves = emit_value_leaves(cx, inst->res);
  for (uint32_t leaf = 0; leaf < leaves.len; leaf++) {
    emit_zero_leaf(cx, inst->res, leaf, leaves.ptr[leaf]);
  }
}

bool emit_task_op(EmitCx *cx, const MirInst *inst, bool *handled) {
  *handled = true;
  switch ((MirOp)inst->op) {
  case MOP_Undef:
    undef(cx, inst);
    return true;
  default:
    *handled = false;
    return true;
  }
}

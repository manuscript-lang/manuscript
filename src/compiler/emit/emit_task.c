/* Owns `undef`. */
#include "compiler/emit/emit_cx.h"

/* `undef`: any value of the type, one frozen `undef` per leaf, or a zeroed cell for a held value. */
static void undef(EmitCx *cx, const MirInst *inst) {
  if (emit_wide_zero(cx, inst->res)) {
    return;
  }
  MsSpan leaves = emit_value_leaves(cx, inst->res);
  for (uint32_t leaf = 0; leaf < leaves.len; leaf++) {
    ms_strbuild_append_text(cx->out, "  ");
    emit_name(cx->out, inst->res, leaf);
    ms_strbuild_printf(cx->out, " = freeze %s undef\n", emit_leaf_type(leaves.ptr[leaf]));
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

/* Owns what Cranelift needs to know about leaves: their register types, the value table of the function being
 * lowered, and widening (see cl_cx.h). */
#include "compiler/emit_cl/cl_cx.h"

MsSpan clx_leaves(ClCx *cx, MirTy type) {
  return mir_leaves(cx->layouts, type);
}

MirTy clx_value_type(const ClCx *cx, MirValue value) {
  return mir_value_ty(cx->func, value);
}

MsSpan clx_value_leaves(ClCx *cx, MirValue value) {
  return clx_leaves(cx, clx_value_type(cx, value));
}

cl_type clx_reg_type(MirLeaf leaf) {
  switch (leaf) {
  case MIR_LEAF_F64:
  case MIR_LEAF_F32:
    return CL_F64;
  case MIR_LEAF_I8:
    return CL_I8;
  default:
    return CL_I64;
  }
}

cl_type clx_value_reg_type(ClCx *cx, MirValue value) {
  MsSpan leaves = clx_value_leaves(cx, value);
  return leaves.len == 1 ? clx_reg_type(leaves.ptr[0]) : CL_I64;
}

bool clx_is_indirect(ClCx *cx, MirTy type) {
  return mir_type_mem(cx->layouts, type).size > CLX_DIRECT_BYTES;
}

uint32_t clx_slot_bytes(ClCx *cx, MirTy type) {
  uint32_t size = mir_type_mem(cx->layouts, type).size;
  if (size < 8) {
    size = 8;
  }
  return (size + 7U) / 8U * 8U;
}

cl_val clx_get(const ClCx *cx, MirValue value, uint32_t leaf) {
  return cx->regs[cx->first[value] + leaf];
}

void clx_set(ClCx *cx, MirValue value, uint32_t leaf, cl_val reg) {
  cx->regs[cx->first[value] + leaf] = reg;
}

cl_val clx_arg(const ClCx *cx, const MirInst *inst, uint32_t arg) {
  return clx_get(cx, inst->args[arg], 0);
}

cl_val clx_const(ClCx *cx, int64_t k) {
  return cl_i64const(cx->fb, k);
}


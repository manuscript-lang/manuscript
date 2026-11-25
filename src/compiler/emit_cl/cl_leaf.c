/* Owns what Cranelift needs to know about leaves: their register types, the value table of the function being
 * lowered, and widening (see cl_cx.h). */
#include "compiler/emit_cl/cl_cx.h"

MsSpan cl_leaves(ClCx *cx, MirTy type) {
  return mir_leaves(cx->layouts, type);
}

MirTy cl_value_type(const ClCx *cx, MirValue value) {
  return mir_value_ty(cx->func, value);
}

MsSpan cl_value_leaves(ClCx *cx, MirValue value) {
  return cl_leaves(cx, cl_value_type(cx, value));
}

ms_cl_type cl_reg_type(MirLeaf leaf) {
  switch (leaf) {
  case MIR_LEAF_F64:
  case MIR_LEAF_F32:
    return MS_CL_F64;
  case MIR_LEAF_I8:
    return MS_CL_I8;
  default:
    return MS_CL_I64;
  }
}

ms_cl_type cl_value_reg_type(ClCx *cx, MirValue value) {
  MsSpan leaves = cl_value_leaves(cx, value);
  return leaves.len == 1 ? cl_reg_type(leaves.ptr[0]) : MS_CL_I64;
}

bool cl_is_indirect(ClCx *cx, MirTy type) {
  return mir_type_mem(cx->layouts, type).size > CL_DIRECT_BYTES;
}

uint32_t cl_slot_bytes(ClCx *cx, MirTy type) {
  uint32_t size = mir_type_mem(cx->layouts, type).size;
  if (size < 8) {
    size = 8;
  }
  return (size + 7U) / 8U * 8U;
}

ms_cl_val cl_get(const ClCx *cx, MirValue value, uint32_t leaf) {
  return cx->regs[cx->first[value] + leaf];
}

void cl_set(ClCx *cx, MirValue value, uint32_t leaf, ms_cl_val reg) {
  cx->regs[cx->first[value] + leaf] = reg;
}

ms_cl_val cl_arg(const ClCx *cx, const MirInst *inst, uint32_t arg) {
  return cl_get(cx, inst->args[arg], 0);
}

ms_cl_val cl_const(ClCx *cx, int64_t k) {
  return ms_cl_i64const(cx->fb, k);
}

/* A loaded leaf of a sized kind is already extended by the load; only a boolean needs no change and a float32
 * widens. The loads in cl_mem.c do the extension, so this only converts Float32. */
ms_cl_val cl_widen(ClCx *cx, MirLeaf leaf, ms_cl_val loaded) {
  if (leaf == MIR_LEAF_F32) {
    return ms_cl_cast(cx->fb, MS_CL_FPROMOTE, MS_CL_F64, loaded);
  }
  return loaded;
}

/* Owns loads, stores and copies of leaves, and the memory operations on them (see cl_cx.h). */
#include "compiler/emit_cl/cl_cx.h"

#include "base/alloc.h"
#include "base/fatal.h"

/* Memory the program owns cannot trap, and every access here is a plain one. */
#define CL_MEM MS_CL_NOTRAP

void cl_load_leaf(ClCx *cx, MirLeaf leaf, MirValue dst, uint32_t index, ms_cl_val base, int32_t offset) {
  ms_cl_fn *f = cx->fb;
  ms_cl_val loaded;
  switch (leaf) {
  case MIR_LEAF_I64:
    loaded = ms_cl_load(f, MS_CL_I64, CL_MEM, base, offset);
    break;
  case MIR_LEAF_F64:
    loaded = ms_cl_load(f, MS_CL_F64, CL_MEM, base, offset);
    break;
  case MIR_LEAF_I8:
    loaded = ms_cl_load(f, MS_CL_I8, CL_MEM, base, offset);
    break;
  case MIR_LEAF_N8:
    loaded = ms_cl_load_ext(f, 8, 1, MS_CL_I64, CL_MEM, base, offset);
    break;
  case MIR_LEAF_N16:
    loaded = ms_cl_load_ext(f, 16, 1, MS_CL_I64, CL_MEM, base, offset);
    break;
  case MIR_LEAF_N32:
    loaded = ms_cl_load_ext(f, 32, 1, MS_CL_I64, CL_MEM, base, offset);
    break;
  case MIR_LEAF_U8:
    loaded = ms_cl_load_ext(f, 8, 0, MS_CL_I64, CL_MEM, base, offset);
    break;
  case MIR_LEAF_U16:
    loaded = ms_cl_load_ext(f, 16, 0, MS_CL_I64, CL_MEM, base, offset);
    break;
  case MIR_LEAF_U32:
    loaded = ms_cl_load_ext(f, 32, 0, MS_CL_I64, CL_MEM, base, offset);
    break;
  default: /* MIR_LEAF_F32 */
    loaded = ms_cl_cast(f, MS_CL_FPROMOTE, MS_CL_F64, ms_cl_load(f, MS_CL_F32, CL_MEM, base, offset));
    break;
  }
  cl_set(cx, dst, index, loaded);
}

void cl_store_leaf(ClCx *cx, MirLeaf leaf, MirValue src, uint32_t index, ms_cl_val base, int32_t offset) {
  ms_cl_fn *f = cx->fb;
  const ms_cl_val v = cl_get(cx, src, index);
  switch (leaf) {
  case MIR_LEAF_I64:
  case MIR_LEAF_F64:
  case MIR_LEAF_I8:
    ms_cl_store(f, CL_MEM, v, base, offset);
    return;
  case MIR_LEAF_N8:
  case MIR_LEAF_U8:
    ms_cl_store_trunc(f, 8, CL_MEM, v, base, offset);
    return;
  case MIR_LEAF_N16:
  case MIR_LEAF_U16:
    ms_cl_store_trunc(f, 16, CL_MEM, v, base, offset);
    return;
  case MIR_LEAF_N32:
  case MIR_LEAF_U32:
    ms_cl_store_trunc(f, 32, CL_MEM, v, base, offset);
    return;
  default: /* MIR_LEAF_F32 */
    ms_cl_store(f, CL_MEM, ms_cl_cast(f, MS_CL_FDEMOTE, MS_CL_F32, v), base, offset);
    return;
  }
}

void cl_leaves_at(ClCx *cx, MirValue value, ms_cl_val base, bool load) {
  MsSpan leaves = cl_value_leaves(cx, value);
  size_t bytes = 0;
  if (!ms_size_mul(leaves.len + 1, sizeof(uint32_t), &bytes)) {
    ms_fatal(MS_FATAL_OVERFLOW, "leaf count");
  }
  uint32_t *offsets = ms_alloc_zeroed(bytes);
  (void)mir_mem_layout(leaves, offsets);
  for (uint32_t leaf = 0; leaf < leaves.len; leaf++) {
    if (load) {
      cl_load_leaf(cx, leaves.ptr[leaf], value, leaf, base, (int32_t)offsets[leaf]);
    } else {
      cl_store_leaf(cx, leaves.ptr[leaf], value, leaf, base, (int32_t)offsets[leaf]);
    }
  }
  ms_free(offsets);
}

/* A zeroed slot: padding bytes compare equal when a descriptor compares a slot as bytes. */
ms_cl_val cl_slot(ClCx *cx, uint32_t bytes) {
  ms_cl_val address = ms_cl_stack_addr(cx->fb, ms_cl_stack_slot(cx->fb, bytes, 3), 0);
  ms_cl_fill(cx->fb, address, 0, bytes);
  return address;
}

void cl_zero_leaf(ClCx *cx, MirValue dst, uint32_t index, MirLeaf leaf) {
  ms_cl_fn *f = cx->fb;
  switch (cl_reg_type(leaf)) {
  case MS_CL_F64:
    cl_set(cx, dst, index, ms_cl_f64const(f, 0.0));
    return;
  case MS_CL_I8:
    cl_set(cx, dst, index, ms_cl_iconst(f, MS_CL_I8, 0));
    return;
  default:
    cl_set(cx, dst, index, ms_cl_i64const(f, 0));
    return;
  }
}

/* A slot an alternative's cases share has the widest leaf type: a narrower payload is read out of it by converting. */
void cl_copy_leaf(ClCx *cx, MirValue dst, uint32_t to, MirValue src, uint32_t from) {
  ms_cl_fn *f = cx->fb;
  const ms_cl_type want = cl_reg_type(cl_value_leaves(cx, dst).ptr[to]);
  const ms_cl_type have = cl_reg_type(cl_value_leaves(cx, src).ptr[from]);
  ms_cl_val v = cl_get(cx, src, from);
  if (want != have) {
    if (want == MS_CL_I8) {
      v = ms_cl_icmp(f, MS_CL_NE, v, ms_cl_i64const(f, 0));
    } else if (have == MS_CL_I8) {
      v = ms_cl_cast(f, MS_CL_UEXTEND, MS_CL_I64, v);
    } else {
      v = ms_cl_cast(f, MS_CL_BITCAST, want, v);
    }
  }
  cl_set(cx, dst, to, v);
}

/* `load`, `take`: the result's leaves from the pointer in the first operand. */
static void lower_load(ClCx *cx, const MirInst *inst) {
  cl_leaves_at(cx, inst->res, cl_arg(cx, inst, 0), true);
}

/* `store`, `put`: the second operand's leaves to the pointer in the first. */
static void lower_store(ClCx *cx, const MirInst *inst) {
  cl_leaves_at(cx, inst->args[1], cl_arg(cx, inst, 0), false);
}

/* `ptr.field`: the address of a field of the inline record the operand points to. */
static bool lower_ptr_field(ClCx *cx, const MirInst *inst) {
  if (cx->module->type_defs.ptr[inst->imm.a].indirect) {
    cx->why = "record behind a pointer";
    return false;
  }
  const uint32_t offset = mir_field_offset(cx->layouts, inst->imm.a, inst->imm.b);
  cl_set(cx, inst->res, 0, ms_cl_iadd(cx->fb, cl_arg(cx, inst, 0), cl_const(cx, offset)));
  return true;
}

bool cl_memory_op(ClCx *cx, const MirInst *inst, bool *handled) {
  *handled = true;
  switch ((MirOp)inst->op) {
  case MOP_Slot:
    cl_set(cx, inst->res, 0, cl_slot(cx, cl_slot_bytes(cx, inst->imm.a)));
    return true;
  case MOP_Load:
  case MOP_Take:
    lower_load(cx, inst);
    return true;
  case MOP_Store:
  case MOP_Put:
    lower_store(cx, inst);
    return true;
  case MOP_PtrField:
    return lower_ptr_field(cx, inst);
  default:
    *handled = false;
    return true;
  }
}

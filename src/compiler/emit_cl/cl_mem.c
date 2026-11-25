/* Owns loads, stores and copies of leaves, and the memory operations on them (see cl_cx.h). */
#include "compiler/emit_cl/cl_cx.h"

#include "base/alloc.h"
#include "base/fatal.h"

/* Memory the program owns cannot trap, and every access here is a plain one. */
#define CLX_MEM CL_NOTRAP

void clx_load_leaf(ClCx *cx, MirLeaf leaf, MirValue dst, uint32_t index, cl_val base, int32_t offset) {
  cl_fn *f = cx->fb;
  cl_val loaded;
  switch (leaf) {
  case MIR_LEAF_I64:
    loaded = cl_load(f, CL_I64, CLX_MEM, base, offset);
    break;
  case MIR_LEAF_F64:
    loaded = cl_load(f, CL_F64, CLX_MEM, base, offset);
    break;
  case MIR_LEAF_I8:
    loaded = cl_load(f, CL_I8, CLX_MEM, base, offset);
    break;
  case MIR_LEAF_N8:
    loaded = cl_load_ext(f, 8, 1, CL_I64, CLX_MEM, base, offset);
    break;
  case MIR_LEAF_N16:
    loaded = cl_load_ext(f, 16, 1, CL_I64, CLX_MEM, base, offset);
    break;
  case MIR_LEAF_N32:
    loaded = cl_load_ext(f, 32, 1, CL_I64, CLX_MEM, base, offset);
    break;
  case MIR_LEAF_U8:
    loaded = cl_load_ext(f, 8, 0, CL_I64, CLX_MEM, base, offset);
    break;
  case MIR_LEAF_U16:
    loaded = cl_load_ext(f, 16, 0, CL_I64, CLX_MEM, base, offset);
    break;
  case MIR_LEAF_U32:
    loaded = cl_load_ext(f, 32, 0, CL_I64, CLX_MEM, base, offset);
    break;
  default: /* MIR_LEAF_F32 */
    loaded = cl_cast(f, CL_FPROMOTE, CL_F64, cl_load(f, CL_F32, CLX_MEM, base, offset));
    break;
  }
  clx_set(cx, dst, index, loaded);
}

void clx_store_leaf(ClCx *cx, MirLeaf leaf, MirValue src, uint32_t index, cl_val base, int32_t offset) {
  cl_fn *f = cx->fb;
  const cl_val v = clx_get(cx, src, index);
  switch (leaf) {
  case MIR_LEAF_I64:
  case MIR_LEAF_F64:
  case MIR_LEAF_I8:
    cl_store(f, CLX_MEM, v, base, offset);
    return;
  case MIR_LEAF_N8:
  case MIR_LEAF_U8:
    cl_store_trunc(f, 8, CLX_MEM, v, base, offset);
    return;
  case MIR_LEAF_N16:
  case MIR_LEAF_U16:
    cl_store_trunc(f, 16, CLX_MEM, v, base, offset);
    return;
  case MIR_LEAF_N32:
  case MIR_LEAF_U32:
    cl_store_trunc(f, 32, CLX_MEM, v, base, offset);
    return;
  default: /* MIR_LEAF_F32 */
    cl_store(f, CLX_MEM, cl_cast(f, CL_FDEMOTE, CL_F32, v), base, offset);
    return;
  }
}

void clx_leaves_at(ClCx *cx, MirValue value, cl_val base, bool load) {
  MsSpan leaves = clx_value_leaves(cx, value);
  size_t bytes = 0;
  if (!ms_size_mul(leaves.len + 1, sizeof(uint32_t), &bytes)) {
    ms_fatal(MS_FATAL_OVERFLOW, "leaf count");
  }
  uint32_t *offsets = ms_alloc_zeroed(bytes);
  (void)mir_mem_layout(leaves, offsets);
  for (uint32_t leaf = 0; leaf < leaves.len; leaf++) {
    if (load) {
      clx_load_leaf(cx, leaves.ptr[leaf], value, leaf, base, (int32_t)offsets[leaf]);
    } else {
      clx_store_leaf(cx, leaves.ptr[leaf], value, leaf, base, (int32_t)offsets[leaf]);
    }
  }
  ms_free(offsets);
}

/* A zeroed slot: padding bytes compare equal when a descriptor compares a slot as bytes. */
cl_val clx_slot(ClCx *cx, uint32_t bytes) {
  cl_val address = cl_stack_addr(cx->fb, cl_stack_slot(cx->fb, bytes, 3), 0);
  cl_fill(cx->fb, address, 0, bytes);
  return address;
}

void clx_zero_leaf(ClCx *cx, MirValue dst, uint32_t index, MirLeaf leaf) {
  cl_fn *f = cx->fb;
  switch (clx_reg_type(leaf)) {
  case CL_F64:
    clx_set(cx, dst, index, cl_f64const(f, 0.0));
    return;
  case CL_I8:
    clx_set(cx, dst, index, cl_iconst(f, CL_I8, 0));
    return;
  default:
    clx_set(cx, dst, index, cl_i64const(f, 0));
    return;
  }
}

/* A slot an alternative's cases share has the widest leaf type: a narrower payload is read out of it by converting. */
void clx_copy_leaf(ClCx *cx, MirValue dst, uint32_t to, MirValue src, uint32_t from) {
  cl_fn *f = cx->fb;
  const cl_type want = clx_reg_type(clx_value_leaves(cx, dst).ptr[to]);
  const cl_type have = clx_reg_type(clx_value_leaves(cx, src).ptr[from]);
  cl_val v = clx_get(cx, src, from);
  if (want != have) {
    if (want == CL_I8) {
      v = cl_icmp(f, CL_NE, v, cl_i64const(f, 0));
    } else if (have == CL_I8) {
      v = cl_cast(f, CL_UEXTEND, CL_I64, v);
    } else {
      v = cl_cast(f, CL_BITCAST, want, v);
    }
  }
  clx_set(cx, dst, to, v);
}

/* `load`, `take`: the result's leaves from the pointer in the first operand. */
static void lower_load(ClCx *cx, const MirInst *inst) {
  clx_leaves_at(cx, inst->res, clx_arg(cx, inst, 0), true);
}

/* `store`, `put`: the second operand's leaves to the pointer in the first. */
static void lower_store(ClCx *cx, const MirInst *inst) {
  clx_leaves_at(cx, inst->args[1], clx_arg(cx, inst, 0), false);
}

/* `ptr.field`: the address of a field of the inline record the operand points to. */
static bool lower_ptr_field(ClCx *cx, const MirInst *inst) {
  if (cx->module->type_defs.ptr[inst->imm.a].indirect) {
    cx->why = "record behind a pointer";
    return false;
  }
  const uint32_t offset = mir_field_offset(cx->layouts, inst->imm.a, inst->imm.b);
  clx_set(cx, inst->res, 0, cl_iadd(cx->fb, clx_arg(cx, inst, 0), clx_const(cx, offset)));
  return true;
}

bool clx_memory_op(ClCx *cx, const MirInst *inst, bool *handled) {
  *handled = true;
  switch ((MirOp)inst->op) {
  case MOP_Slot:
    clx_set(cx, inst->res, 0, clx_slot(cx, clx_slot_bytes(cx, inst->imm.a)));
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

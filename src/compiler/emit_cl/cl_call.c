/* Owns calls: the stack areas a call needs, and the calls of MIR functions and runtime functions. */
#include "compiler/emit_cl/cl_cx.h"

#include "abi/layout.h"
#include "base/alloc.h"
#include "compiler/mir/mir_analysis.h"
#include "compiler/mir/mir_pass.h"

/* An argument copy is dead once its call returns unless the result can point into it (a short string's view
 * does), so a call whose result is void or a number shares one copy slot per argument position, as large as
 * the largest copy; any other call keeps a slot of its own. Positions past CLX_SHARED_ARGS keep one per site. */
static bool temps_shared(const ClCx *cx, const MirInst *inst) {
  MirTy result = MIR_NONE;
  if ((MirOp)inst->op == MOP_CallRt) {
    const MirExtern *external = &cx->module->externs.ptr[inst->imm.a];
    /* A runtime call that neither returns a view nor keeps an argument leaves nothing pointing into the copies. */
    if (!mir_extern_pins_argument(external)) {
      return true;
    }
    result = external->ret;
  } else if (inst->res != MIR_NONE) {
    result = clx_value_type(cx, inst->res);
    /* A function whose result is not a view of an argument leaves nothing pointing into the copies. */
    if ((MirOp)inst->op == MOP_Call && inst->imm.tag == MI_FUNC && inst->imm.a < cx->module->funcs.len &&
        !cx->module->funcs.ptr[inst->imm.a].ret_borrowed) {
      return true;
    }
  } else {
    return true;
  }
  return mir_ty_data(cx->module, result)->kind == MK_VOID || mir_is_scalar(cx->module, result);
}

static bool rt_direct(ClCx *cx, MirTy type) {
  return mir_rt_direct(cx->module, cx->layouts, type);
}

/* An `opt<scalar>` the runtime returns as a C `u8` flag with the payload through a trailing output pointer. */
static bool rt_scalar_option(ClCx *cx, MirTy type) {
  return mir_ty_data(cx->module, type)->kind == MK_OPT && rt_direct(cx, type) && clx_leaves(cx, type).len == 2;
}

/* Whether extern `def` is a function of a C library: the runtime's own (`msrt_`, `msstd_`) take a Float32 as a double. */
static bool extern_is_c(const ClCx *cx, const MirExtern *def) {
  MsSpan name = ms_names_span(&cx->module->names, def->name);
  return !ms_span_starts_with_text(name, "msrt_") && !ms_span_starts_with_text(name, "msstd_");
}

/* ---- frame areas ---- */

static void note(uint32_t *slot, uint32_t bytes) {
  *slot = bytes > *slot ? bytes : *slot;
}

/* The areas a call needs: a copy of each argument that does not pass directly, and the result area when the result does
 * not. */
static void scan_call(ClCx *cx, const MirInst *inst, uint32_t *shared, uint32_t *area) {
  const bool share = temps_shared(cx, inst);
  if ((MirOp)inst->op == MOP_CallRt) {
    const MirExtern *def = &cx->module->externs.ptr[inst->imm.a];
    for (uint32_t arg = 0; arg < inst->nargs; arg++) {
      if (!rt_direct(cx, def->params[arg].ty) && share && arg < CLX_SHARED_ARGS) {
        note(&shared[arg], clx_slot_bytes(cx, def->params[arg].ty));
      }
    }
    if (!rt_direct(cx, def->ret)) {
      note(area, clx_slot_bytes(cx, def->ret));
    } else if (rt_scalar_option(cx, def->ret)) {
      note(area, 8);
    }
    return;
  }
  if (inst->res != MIR_NONE && clx_value_leaves(cx, inst->res).len > 1) {
    note(area, clx_slot_bytes(cx, clx_value_type(cx, inst->res)));
  }
  for (uint32_t arg = 0; arg < inst->nargs; arg++) {
    const MirTy type = clx_value_type(cx, inst->args[arg]);
    if (clx_is_indirect(cx, type) && share && arg < CLX_SHARED_ARGS) {
      note(&shared[arg], clx_slot_bytes(cx, type));
    }
  }
}

/* The shared areas of the function: one stack slot per argument position of the calls, and one result area. */
void clx_frame_areas(ClCx *cx) {
  uint32_t shared[CLX_SHARED_ARGS] = {0};
  uint32_t area = 0;
  for (uint32_t block = 0; block < cx->func->blocks.len; block++) {
    const MirInstList *insts = &cx->func->blocks.ptr[block].insts;
    for (uint32_t index = 0; index < insts->len; index++) {
      const MirInst *inst = &insts->ptr[index];
      if ((MirOp)inst->op == MOP_Call || (MirOp)inst->op == MOP_CallRt || (MirOp)inst->op == MOP_CallInd ||
          (MirOp)inst->op == MOP_CallMethod) {
        scan_call(cx, inst, shared, &area);
      }
    }
  }
  for (uint32_t arg = 0; arg < CLX_SHARED_ARGS; arg++) {
    cx->shared_bytes[arg] = shared[arg];
    cx->shared_made[arg] = false;
  }
  cx->area_bytes = area;
  cx->area_made = false;
}

/* The address of a shared slot, made when first needed. */
static cl_val shared_slot(ClCx *cx, uint32_t arg) {
  if (!cx->shared_made[arg]) {
    cx->shared_made[arg] = true;
    cx->shared[arg] = cl_stack_slot(cx->fb, cx->shared_bytes[arg], 3);
  }
  return cl_stack_addr(cx->fb, cx->shared[arg], 0);
}

static cl_val result_area(ClCx *cx) {
  if (!cx->area_made) {
    cx->area_made = true;
    cx->area = cl_stack_slot(cx->fb, cx->area_bytes, 3);
  }
  return cl_stack_addr(cx->fb, cx->area, 0);
}

/* The slot for argument `arg` of the call: the shared one for its position, or a new one. */
static cl_val arg_slot(ClCx *cx, const MirInst *inst, uint32_t arg, uint32_t bytes) {
  if (arg < CLX_SHARED_ARGS && temps_shared(cx, inst)) {
    return shared_slot(cx, arg);
  }
  return cl_stack_addr(cx->fb, cl_stack_slot(cx->fb, bytes, 3), 0);
}

/* ---- calls of MIR functions ---- */

/* The signature of an indirect call: the hidden result pointer, the lead address when there is one, then the leaves of
 * each argument as `function_sig` gives a MIR function (cl_module.c). */
static cl_sig indirect_sig(ClCx *cx, const MirInst *inst, bool lead) {
  cl *cl = cx->mod->cl;
  cl_sig sig = cl_sig_new(cl);
  const MsSpan result = inst->res == MIR_NONE ? (MsSpan){0} : clx_value_leaves(cx, inst->res);
  if (result.len > 1) {
    cl_sig_param(cl, sig, CL_I64, CL_EXT_NONE);
  }
  if (lead) {
    cl_sig_param(cl, sig, CL_I64, CL_EXT_NONE);
  }
  for (uint32_t arg = lead ? 1 : 0; arg < inst->nargs; arg++) {
    const MirTy type = clx_value_type(cx, inst->args[arg]);
    if (clx_is_indirect(cx, type)) {
      cl_sig_param(cl, sig, CL_I64, CL_EXT_NONE);
      continue;
    }
    const MsSpan leaves = clx_leaves(cx, type);
    for (uint32_t leaf = 0; leaf < leaves.len; leaf++) {
      const cl_type reg = clx_reg_type((MirLeaf)leaves.ptr[leaf]);
      cl_sig_param(cl, sig, reg, reg == CL_I8 ? CL_EXT_U : CL_EXT_NONE);
    }
  }
  if (result.len == 1) {
    const cl_type reg = clx_reg_type((MirLeaf)result.ptr[0]);
    cl_sig_ret(cl, sig, reg, reg == CL_I8 ? CL_EXT_U : CL_EXT_NONE);
  }
  return sig;
}

/* A call of the MIR function the instruction names, or, with `code`, of the code address it holds; `lead`, when set,
 * is the first argument in place of operand 0 (the data address of an interface value). */
static void call_function(ClCx *cx, const MirInst *inst, const cl_val *code, const cl_val *lead) {
  cl_fn *f = cx->fb;
  uint32_t capacity = 3;
  for (uint32_t arg = 0; arg < inst->nargs; arg++) {
    capacity += (uint32_t)clx_value_leaves(cx, inst->args[arg]).len;
  }
  cl_val *args = ms_alloc(capacity * sizeof(cl_val));
  uint32_t count = 0;
  const uint32_t result_leaves = inst->res == MIR_NONE ? 0 : (uint32_t)clx_value_leaves(cx, inst->res).len;
  cl_val area = {0};
  if (result_leaves > 1) {
    area = result_area(cx);
    args[count++] = area;
  }
  if (lead != NULL) {
    args[count++] = *lead;
  }
  for (uint32_t arg = lead != NULL ? 1 : 0; arg < inst->nargs; arg++) {
    const MirTy type = clx_value_type(cx, inst->args[arg]);
    if (clx_is_indirect(cx, type)) {
      cl_val slot = arg_slot(cx, inst, arg, clx_slot_bytes(cx, type));
      clx_leaves_at(cx, inst->args[arg], slot, false);
      args[count++] = slot;
      continue;
    }
    const uint32_t leaves = (uint32_t)clx_value_leaves(cx, inst->args[arg]).len;
    for (uint32_t leaf = 0; leaf < leaves; leaf++) {
      args[count++] = clx_get(cx, inst->args[arg], leaf);
    }
  }
  cl_val ret[1];
  if (code != NULL) {
    cl_call_indirect(f, indirect_sig(cx, inst, lead != NULL), *code, args, count, ret);
  } else {
    cl_call(f, cx->mod->funcs[inst->imm.a], args, count, ret);
  }
  ms_free(args);
  if (result_leaves == 1) {
    clx_set(cx, inst->res, 0, ret[0]);
  } else if (result_leaves > 1) {
    clx_leaves_at(cx, inst->res, area, true);
  }
}

/* The header word offsets of a closure object, and the slots of an interface vtable. */
enum { CLOSURE_CODE = 16 };

/* `call.ind`: the code word of the closure in the first operand, called with the closure first. */
static void call_closure(ClCx *cx, const MirInst *inst) {
  const cl_val code = cl_load(cx->fb, CL_I64, CL_NOTRAP, clx_arg(cx, inst, 0), CLOSURE_CODE);
  call_function(cx, inst, &code, NULL);
}

/* `call.method`: the code word of the method's slot, called with the data address first. */
static void call_method(ClCx *cx, const MirInst *inst) {
  cl_fn *f = cx->fb;
  const cl_val table = cl_band(f, clx_get(cx, inst->args[0], 1), clx_const(cx, -4));
  const cl_val code = cl_load(f, CL_I64, CL_NOTRAP, table, (int32_t)(8 * (1 + inst->imm.b)));
  const cl_val data = clx_get(cx, inst->args[0], 0);
  call_function(cx, inst, &code, &data);
}

/* ---- runtime calls ---- */

/* The address of the running task's `unwinding` byte: the region's cell holds the header pointer, and the byte sits at a
 * fixed offset (read in line, as the depth check reads its limit). */
static cl_val unwinding_address(ClCx *cx) {
  cl_fn *f = cx->fb;
  cl_val region = cl_band(f, cl_sp(f), clx_const(cx, -(int64_t)MS_STACK_REGION));
  cl_val cell = cl_iadd(f, region, clx_const(cx, (int64_t)(MS_STACK_REGION - MS_STACK_CELL_HDR)));
  cl_val header = cl_load(f, CL_I64, CL_NOTRAP | CL_READONLY, cell, 0);
  return cl_iadd(f, header, clx_const(cx, MS_HDR_UNWINDING));
}

/* The leaf `leaf` of a runtime call's result, as it arrives, widened to its register. */
static cl_val widen_result(ClCx *cx, MirLeaf leaf, cl_val raw, bool is_c) {
  cl_fn *f = cx->fb;
  switch (leaf) {
  case MIR_LEAF_N8:
  case MIR_LEAF_N16:
  case MIR_LEAF_N32:
    return cl_cast(f, CL_SEXTEND, CL_I64, raw);
  case MIR_LEAF_U8:
  case MIR_LEAF_U16:
  case MIR_LEAF_U32:
    return cl_cast(f, CL_UEXTEND, CL_I64, raw);
  case MIR_LEAF_F32:
    return is_c ? cl_cast(f, CL_FPROMOTE, CL_F64, raw) : raw; /* the runtime's own functions return a double */
  default:
    return raw;
  }
}

/* The type a runtime function returns a leaf in: the leaf's own width, so the extension above reads only the bits
 * the callee set (a C function leaves the rest as they are). A Float32 is a double for the runtime's own functions. */
cl_type clx_rt_leaf_type(MirLeaf leaf, bool is_c) {
  switch (leaf) {
  case MIR_LEAF_I8:
  case MIR_LEAF_N8:
  case MIR_LEAF_U8:
    return CL_I8;
  case MIR_LEAF_N16:
  case MIR_LEAF_U16:
    return CL_I16;
  case MIR_LEAF_N32:
  case MIR_LEAF_U32:
    return CL_I32;
  case MIR_LEAF_F32:
    return is_c ? CL_F32 : CL_F64;
  case MIR_LEAF_F64:
    return CL_F64;
  default:
    return CL_I64;
  }
}

static bool call_runtime(ClCx *cx, const MirInst *inst) {
  cl_fn *f = cx->fb;
  const MirExtern *def = &cx->module->externs.ptr[inst->imm.a];
  if (def->role == MR_UNWINDING && inst->res != MIR_NONE) {
    cl_val flag = cl_load_ext(f, 8, 0, CL_I64, CL_NOTRAP, unwinding_address(cx), 0);
    clx_set(cx, inst->res, 0, cl_icmp(f, CL_NE, flag, clx_const(cx, 0)));
    return true;
  }
  const bool is_c = extern_is_c(cx, def);
  MsSpan result = clx_leaves(cx, def->ret);
  const bool direct = rt_direct(cx, def->ret);
  const bool option = direct && rt_scalar_option(cx, def->ret);
  if (direct && result.len > 1 && !option) {
    cx->why = "runtime result of several scalars";
    return false;
  }
  uint32_t capacity = 2;
  for (uint32_t arg = 0; arg < inst->nargs; arg++) {
    capacity += (uint32_t)clx_value_leaves(cx, inst->args[arg]).len;
  }
  cl_val *args = ms_alloc(capacity * sizeof(cl_val));
  uint32_t count = 0;
  for (uint32_t arg = 0; arg < inst->nargs; arg++) {
    const MirTy type = def->params[arg].ty;
    if (!rt_direct(cx, type)) {
      cl_val slot = arg_slot(cx, inst, arg, clx_slot_bytes(cx, type));
      clx_leaves_at(cx, inst->args[arg], slot, false);
      args[count++] = slot;
      continue;
    }
    if (type == MIR_PTR) {
      args[count++] = clx_get(cx, inst->args[arg], 0);
      continue;
    }
    MsSpan leaves = clx_leaves(cx, type);
    for (uint32_t leaf = 0; leaf < leaves.len; leaf++) {
      cl_val v = clx_get(cx, inst->args[arg], leaf);
      if (leaves.ptr[leaf] == MIR_LEAF_F32 && is_c) {
        v = cl_cast(f, CL_FDEMOTE, CL_F32, v); /* a C library function takes a float */
      }
      args[count++] = v;
    }
  }
  cl_val area = {0};
  if (!direct || option) {
    area = result_area(cx);
    args[count++] = area;
  }
  cl_val ret[1];
  cl_call(f, clx_extern_func(cx->mod, inst->imm.a), args, count, ret);
  ms_free(args);
  if (option) {
    if (inst->res != MIR_NONE) {
      clx_set(cx, inst->res, 0, cl_icmp(f, CL_NE, ret[0], cl_iconst(f, CL_I8, 0)));
      clx_load_leaf(cx, result.ptr[1], inst->res, 1, area, 0);
    }
    return true;
  }
  if (direct && result.len == 1 && inst->res != MIR_NONE) {
    clx_set(cx, inst->res, 0, widen_result(cx, result.ptr[0], ret[0], extern_is_c(cx, &cx->module->externs.ptr[inst->imm.a])));
  } else if (!direct && inst->res != MIR_NONE) {
    clx_leaves_at(cx, inst->res, area, true);
  }
  return true;
}

bool clx_call_op(ClCx *cx, const MirInst *inst, bool *handled) {
  *handled = true;
  switch ((MirOp)inst->op) {
  case MOP_Call:
    call_function(cx, inst, NULL, NULL);
    return true;
  case MOP_CallInd:
    call_closure(cx, inst);
    return true;
  case MOP_CallMethod:
    call_method(cx, inst);
    return true;
  case MOP_CallRt:
    return call_runtime(cx, inst);
  case MOP_FuncAddr:
    clx_set(cx, inst->res, 0, cl_func_addr(cx->fb, cx->mod->funcs[inst->imm.a]));
    return true;
  default:
    *handled = false;
    return true;
  }
}

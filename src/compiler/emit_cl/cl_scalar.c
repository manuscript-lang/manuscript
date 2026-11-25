/* Owns the arithmetic, comparison and constant operations that are one or a few Cranelift instructions. */
#include "compiler/emit_cl/cl_cx.h"

/* A Float32 lives in an f64 register: round it once to binary32 and back. */
static cl_val round_to_float32(ClCx *cx, cl_val v) {
  return cl_cast(cx->fb, CL_FPROMOTE, CL_F64,
                    cl_cast(cx->fb, CL_FDEMOTE, CL_F32, v));
}

static bool is_float32(ClCx *cx, MirValue value) {
  MsSpan leaves = clx_value_leaves(cx, value);
  return leaves.len == 1 && leaves.ptr[0] == MIR_LEAF_F32;
}

/* Operations that are one Cranelift instruction on their two operands. Shifts take their amount modulo the width in
 * Cranelift, as MIR's do. */
typedef struct Binary {
  MirOp op;
  cl_binop cl;
  bool is_float;
} Binary;

static const Binary binaries[] = {
    {MOP_IAdd, CL_IADD, false}, {MOP_ISub, CL_ISUB, false}, {MOP_IMul, CL_IMUL, false},
    {MOP_And, CL_BAND, false},  {MOP_Or, CL_BOR, false},    {MOP_Xor, CL_BXOR, false},
    {MOP_Shl, CL_ISHL, false},  {MOP_Sshr, CL_SSHR, false}, {MOP_Ushr, CL_USHR, false},
    {MOP_FAdd, CL_FADD, true},  {MOP_FSub, CL_FSUB, true},  {MOP_FMul, CL_FMUL, true},
    {MOP_FDiv, CL_FDIV, true},  {MOP_SDiv, CL_SDIV, false}, {MOP_SRem, CL_SREM, false},
    {MOP_Rotl, CL_ROTL, false}, {MOP_Rotr, CL_ROTR, false}, {MOP_UMulHi, CL_UMULHI, false},
};

static const Binary *find_binary(MirOp op) {
  for (size_t index = 0; index < MS_COUNT_OF(binaries); index++) {
    if (binaries[index].op == op) {
      return &binaries[index];
    }
  }
  return NULL;
}

static void binary_inst(ClCx *cx, const MirInst *inst, const Binary *binary) {
  cl_val v = cl_binary(cx->fb, binary->cl, clx_arg(cx, inst, 0), clx_arg(cx, inst, 1));
  if (binary->is_float && is_float32(cx, inst->res)) {
    v = round_to_float32(cx, v); /* computed in double (exact enough for + - * /), rounded once to binary32 */
  }
  clx_set(cx, inst->res, 0, v);
}

static cl_val float_function(ClCx *cx, const MirInst *inst) {
  cl_unop op = CL_TRUNC;
  switch ((MirOp)inst->op) {
  case MOP_FSqrt:
    op = CL_SQRT;
    break;
  case MOP_FAbs:
    op = CL_FABS;
    break;
  case MOP_FFloor:
    op = CL_FLOOR;
    break;
  case MOP_FCeil:
    op = CL_CEIL;
    break;
  default:
    break;
  }
  cl_val v = cl_unary(cx->fb, op, clx_arg(cx, inst, 0));
  return inst->op == MOP_FSqrt && is_float32(cx, inst->res) ? round_to_float32(cx, v) : v;
}

/* An unsigned 64-bit integer to binary32 with one rounding: a value with the top bit set is halved, keeping the low bit
 * as a sticky bit so the rounding sees it, converted as a signed one, and doubled (exact). Cranelift's own unsigned
 * conversion to a 32-bit float does not lower on x64 (0.136). */
static cl_val unsigned_to_float32(ClCx *cx, cl_val v) {
  cl_fn *f = cx->fb;
  cl_val top = cl_icmp(f, CL_SLT, v, clx_const(cx, 0));
  cl_val halved = cl_bor(f, cl_ushr(f, v, clx_const(cx, 1)), cl_band(f, v, clx_const(cx, 1)));
  cl_val single = cl_cast(f, CL_FCVT_FROM_SINT, CL_F32, cl_select(f, top, halved, v));
  return cl_select(f, top, cl_fadd(f, single, single), single);
}

/* One rounding, straight to binary32 for a Float32 result: through a double it would round twice at the midpoints. */
static cl_val int_to_float(ClCx *cx, const MirInst *inst) {
  const cl_castop convert = inst->op == MOP_U2F ? CL_FCVT_FROM_UINT : CL_FCVT_FROM_SINT;
  if (clx_value_leaves(cx, inst->res).ptr[0] == MIR_LEAF_F32) {
    const cl_val single = inst->op == MOP_U2F ? unsigned_to_float32(cx, clx_arg(cx, inst, 0))
                                                 : cl_cast(cx->fb, convert, CL_F32, clx_arg(cx, inst, 0));
    return cl_cast(cx->fb, CL_FPROMOTE, CL_F64, single);
  }
  return cl_cast(cx->fb, convert, CL_F64, clx_arg(cx, inst, 0));
}

/* `f.bits`: the bit pattern of a Float (64 bits) or Float32 (its 32 bits, as a non-negative Int). */
static cl_val float_bits(ClCx *cx, const MirInst *inst) {
  if (inst->imm.i == 32) {
    cl_val narrow = cl_cast(cx->fb, CL_FDEMOTE, CL_F32, clx_arg(cx, inst, 0));
    return cl_cast(cx->fb, CL_UEXTEND, CL_I64, cl_cast(cx->fb, CL_BITCAST, CL_I32, narrow));
  }
  return cl_cast(cx->fb, CL_BITCAST, CL_I64, clx_arg(cx, inst, 0));
}

/* `bits.f`: a Float of 64 bits, or a Float32 of the low 32 bits. */
static cl_val bits_float(ClCx *cx, const MirInst *inst) {
  if (inst->imm.i == 32) {
    cl_val low = cl_cast(cx->fb, CL_IREDUCE, CL_I32, clx_arg(cx, inst, 0));
    return cl_cast(cx->fb, CL_FPROMOTE, CL_F64, cl_cast(cx->fb, CL_BITCAST, CL_F32, low));
  }
  return cl_cast(cx->fb, CL_BITCAST, CL_F64, clx_arg(cx, inst, 0));
}

/* The one-operand operations; false when `inst` is not one. */
static bool unary_inst(ClCx *cx, const MirInst *inst) {
  cl_fn *f = cx->fb;
  cl_val x = inst->nargs > 0 ? clx_arg(cx, inst, 0) : (cl_val){0};
  cl_val v;
  switch ((MirOp)inst->op) {
  case MOP_Not: {
    const cl_type type = clx_value_reg_type(cx, inst->res);
    v = cl_bxor(f, x, cl_iconst(f, type, 1));
    break;
  }
  case MOP_FNeg:
    v = cl_fneg(f, x);
    break;
  case MOP_I2F:
  case MOP_U2F:
    v = int_to_float(cx, inst);
    break;
  case MOP_FBits:
    v = float_bits(cx, inst);
    break;
  case MOP_BitsF:
    v = bits_float(cx, inst);
    break;
  case MOP_B2I:
    v = cl_cast(f, CL_UEXTEND, CL_I64, x);
    break;
  case MOP_INeg:
    v = cl_ineg(f, x);
    break;
  case MOP_Clz:
    v = cl_clz(f, x);
    break;
  case MOP_Ctz:
    v = cl_ctz(f, x);
    break;
  case MOP_Popcnt:
    v = cl_popcnt(f, x);
    break;
  case MOP_FSqrt:
  case MOP_FAbs:
  case MOP_FFloor:
  case MOP_FCeil:
  case MOP_FTrunc:
    v = float_function(cx, inst);
    break;
  default:
    return false;
  }
  clx_set(cx, inst->res, 0, v);
  return true;
}

static cl_icmp_cc int_condition(MirCc cc, bool is_unsigned) {
  static const cl_icmp_cc signed_names[] = {CL_EQ, CL_NE, CL_SLT, CL_SLE, CL_SGT, CL_SGE};
  static const cl_icmp_cc unsigned_names[] = {CL_EQ, CL_NE, CL_ULT, CL_ULE, CL_UGT, CL_UGE};
  return is_unsigned ? unsigned_names[cc] : signed_names[cc];
}

/* Ordered, except `!=`, which is also true for an unordered pair. */
static cl_fcmp_cc float_condition(MirCc cc) {
  static const cl_fcmp_cc names[] = {CL_FEQ, CL_FNE, CL_FLT, CL_FLE, CL_FGT, CL_FGE};
  return names[cc];
}

static void compare_inst(ClCx *cx, const MirInst *inst) {
  const MirCc cc = (MirCc)inst->imm.a;
  cl_val v;
  if (inst->op == MOP_FCmp) {
    v = cl_fcmp(cx->fb, float_condition(cc), clx_arg(cx, inst, 0), clx_arg(cx, inst, 1));
  } else {
    v = cl_icmp(cx->fb, int_condition(cc, inst->op == MOP_UICmp), clx_arg(cx, inst, 0), clx_arg(cx, inst, 1));
  }
  clx_set(cx, inst->res, 0, v);
}

/* A constant. The float's bits are a 64-bit integer, so no decimal text can round it. */
static void constant_inst(ClCx *cx, const MirInst *inst) {
  cl_fn *f = cx->fb;
  switch ((MirOp)inst->op) {
  case MOP_FConst: {
    double value;
    const int64_t bits = inst->imm.i;
    __builtin_memcpy(&value, &bits, sizeof value);
    clx_set(cx, inst->res, 0, cl_f64const(f, value));
    return;
  }
  case MOP_BConst:
    clx_set(cx, inst->res, 0, cl_iconst(f, CL_I8, inst->imm.a != 0 ? 1 : 0));
    return;
  default:
    clx_set(cx, inst->res, 0, cl_iconst(f, clx_value_reg_type(cx, inst->res), inst->imm.i));
    return;
  }
}

/* `conv`, `f32.round`: a Float32 result of a double takes one rounding; anything else copies its leaves. */
static void conversion_inst(ClCx *cx, const MirInst *inst) {
  if (inst->op == MOP_F32Round) {
    clx_set(cx, inst->res, 0, round_to_float32(cx, clx_arg(cx, inst, 0)));
    return;
  }
  MsSpan out = clx_value_leaves(cx, inst->res);
  const bool round = out.len == 1 && out.ptr[0] == MIR_LEAF_F32 &&
                     clx_value_leaves(cx, inst->args[0]).ptr[0] == MIR_LEAF_F64;
  if (round) {
    clx_set(cx, inst->res, 0, round_to_float32(cx, clx_arg(cx, inst, 0)));
    return;
  }
  for (uint32_t leaf = 0; leaf < out.len; leaf++) {
    clx_copy_leaf(cx, inst->res, leaf, inst->args[0], leaf);
  }
}

bool clx_scalar_op(ClCx *cx, const MirInst *inst, bool *handled) {
  *handled = true;
  const Binary *binary = find_binary((MirOp)inst->op);
  if (binary != NULL) {
    binary_inst(cx, inst, binary);
    return true;
  }
  if (unary_inst(cx, inst)) {
    return true;
  }
  switch ((MirOp)inst->op) {
  case MOP_Select:
    clx_set(cx, inst->res, 0, cl_select(cx->fb, clx_arg(cx, inst, 0), clx_arg(cx, inst, 1), clx_arg(cx, inst, 2)));
    return true;
  case MOP_IConst:
  case MOP_BConst:
  case MOP_FConst:
    constant_inst(cx, inst);
    return true;
  case MOP_ICmp:
  case MOP_UICmp:
  case MOP_FCmp:
    compare_inst(cx, inst);
    return true;
  case MOP_Conv:
  case MOP_F32Round:
    conversion_inst(cx, inst);
    return true;
  case MOP_Undef: {
    const MsSpan leaves = clx_value_leaves(cx, inst->res);
    for (uint32_t leaf = 0; leaf < leaves.len; leaf++) {
      clx_zero_leaf(cx, inst->res, leaf, (MirLeaf)leaves.ptr[leaf]);
    }
    return true;
  }
  case MOP_VoidConst:
  case MOP_DepthLeave:
    return true; /* nothing to write */
  default:
    *handled = false;
    return true;
  }
}

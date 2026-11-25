/* Owns the arithmetic, comparison and constant operations that are one or a few Cranelift instructions. */
#include "compiler/emit_cl/cl_cx.h"

/* A Float32 lives in an f64 register: round it once to binary32 and back. */
static ms_cl_val round_to_float32(ClCx *cx, ms_cl_val v) {
  return ms_cl_cast(cx->fb, MS_CL_FPROMOTE, MS_CL_F64,
                    ms_cl_cast(cx->fb, MS_CL_FDEMOTE, MS_CL_F32, v));
}

static bool is_float32(ClCx *cx, MirValue value) {
  MsSpan leaves = cl_value_leaves(cx, value);
  return leaves.len == 1 && leaves.ptr[0] == MIR_LEAF_F32;
}

/* Operations that are one Cranelift instruction on their two operands. Shifts take their amount modulo the width in
 * Cranelift, as MIR's do. */
typedef struct Binary {
  MirOp op;
  ms_cl_binop cl;
  bool is_float;
} Binary;

static const Binary binaries[] = {
    {MOP_IAdd, MS_CL_IADD, false}, {MOP_ISub, MS_CL_ISUB, false}, {MOP_IMul, MS_CL_IMUL, false},
    {MOP_And, MS_CL_BAND, false},  {MOP_Or, MS_CL_BOR, false},    {MOP_Xor, MS_CL_BXOR, false},
    {MOP_Shl, MS_CL_ISHL, false},  {MOP_Sshr, MS_CL_SSHR, false}, {MOP_Ushr, MS_CL_USHR, false},
    {MOP_FAdd, MS_CL_FADD, true},  {MOP_FSub, MS_CL_FSUB, true},  {MOP_FMul, MS_CL_FMUL, true},
    {MOP_FDiv, MS_CL_FDIV, true},  {MOP_SDiv, MS_CL_SDIV, false}, {MOP_SRem, MS_CL_SREM, false},
    {MOP_Rotl, MS_CL_ROTL, false}, {MOP_Rotr, MS_CL_ROTR, false}, {MOP_UMulHi, MS_CL_UMULHI, false},
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
  ms_cl_val v = ms_cl_binary(cx->fb, binary->cl, cl_arg(cx, inst, 0), cl_arg(cx, inst, 1));
  if (binary->is_float && is_float32(cx, inst->res)) {
    v = round_to_float32(cx, v); /* computed in double (exact enough for + - * /), rounded once to binary32 */
  }
  cl_set(cx, inst->res, 0, v);
}

static ms_cl_val float_function(ClCx *cx, const MirInst *inst) {
  ms_cl_unop op = MS_CL_TRUNC;
  switch ((MirOp)inst->op) {
  case MOP_FSqrt:
    op = MS_CL_SQRT;
    break;
  case MOP_FAbs:
    op = MS_CL_FABS;
    break;
  case MOP_FFloor:
    op = MS_CL_FLOOR;
    break;
  case MOP_FCeil:
    op = MS_CL_CEIL;
    break;
  default:
    break;
  }
  ms_cl_val v = ms_cl_unary(cx->fb, op, cl_arg(cx, inst, 0));
  return inst->op == MOP_FSqrt && is_float32(cx, inst->res) ? round_to_float32(cx, v) : v;
}

/* One rounding, straight to binary32 for a Float32 result: through a double it would round twice at the midpoints. */
static ms_cl_val int_to_float(ClCx *cx, const MirInst *inst) {
  const ms_cl_castop convert = inst->op == MOP_U2F ? MS_CL_FCVT_FROM_UINT : MS_CL_FCVT_FROM_SINT;
  if (cl_value_leaves(cx, inst->res).ptr[0] == MIR_LEAF_F32) {
    return ms_cl_cast(cx->fb, MS_CL_FPROMOTE, MS_CL_F64, ms_cl_cast(cx->fb, convert, MS_CL_F32, cl_arg(cx, inst, 0)));
  }
  return ms_cl_cast(cx->fb, convert, MS_CL_F64, cl_arg(cx, inst, 0));
}

/* `f.bits`: the bit pattern of a Float (64 bits) or Float32 (its 32 bits, as a non-negative Int). */
static ms_cl_val float_bits(ClCx *cx, const MirInst *inst) {
  if (inst->imm.i == 32) {
    ms_cl_val narrow = ms_cl_cast(cx->fb, MS_CL_FDEMOTE, MS_CL_F32, cl_arg(cx, inst, 0));
    return ms_cl_cast(cx->fb, MS_CL_UEXTEND, MS_CL_I64, ms_cl_cast(cx->fb, MS_CL_BITCAST, MS_CL_I32, narrow));
  }
  return ms_cl_cast(cx->fb, MS_CL_BITCAST, MS_CL_I64, cl_arg(cx, inst, 0));
}

/* `bits.f`: a Float of 64 bits, or a Float32 of the low 32 bits. */
static ms_cl_val bits_float(ClCx *cx, const MirInst *inst) {
  if (inst->imm.i == 32) {
    ms_cl_val low = ms_cl_cast(cx->fb, MS_CL_IREDUCE, MS_CL_I32, cl_arg(cx, inst, 0));
    return ms_cl_cast(cx->fb, MS_CL_FPROMOTE, MS_CL_F64, ms_cl_cast(cx->fb, MS_CL_BITCAST, MS_CL_F32, low));
  }
  return ms_cl_cast(cx->fb, MS_CL_BITCAST, MS_CL_F64, cl_arg(cx, inst, 0));
}

/* The one-operand operations; false when `inst` is not one. */
static bool unary_inst(ClCx *cx, const MirInst *inst) {
  ms_cl_fn *f = cx->fb;
  ms_cl_val x = inst->nargs > 0 ? cl_arg(cx, inst, 0) : (ms_cl_val){0};
  ms_cl_val v;
  switch ((MirOp)inst->op) {
  case MOP_Not: {
    const ms_cl_type type = cl_value_reg_type(cx, inst->res);
    v = ms_cl_bxor(f, x, ms_cl_iconst(f, type, 1));
    break;
  }
  case MOP_FNeg:
    v = ms_cl_fneg(f, x);
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
    v = ms_cl_cast(f, MS_CL_UEXTEND, MS_CL_I64, x);
    break;
  case MOP_INeg:
    v = ms_cl_ineg(f, x);
    break;
  case MOP_Clz:
    v = ms_cl_clz(f, x);
    break;
  case MOP_Ctz:
    v = ms_cl_ctz(f, x);
    break;
  case MOP_Popcnt:
    v = ms_cl_popcnt(f, x);
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
  cl_set(cx, inst->res, 0, v);
  return true;
}

static ms_cl_icmp_cc int_condition(MirCc cc, bool is_unsigned) {
  static const ms_cl_icmp_cc signed_names[] = {MS_CL_EQ, MS_CL_NE, MS_CL_SLT, MS_CL_SLE, MS_CL_SGT, MS_CL_SGE};
  static const ms_cl_icmp_cc unsigned_names[] = {MS_CL_EQ, MS_CL_NE, MS_CL_ULT, MS_CL_ULE, MS_CL_UGT, MS_CL_UGE};
  return is_unsigned ? unsigned_names[cc] : signed_names[cc];
}

/* Ordered, except `!=`, which is also true for an unordered pair. */
static ms_cl_fcmp_cc float_condition(MirCc cc) {
  static const ms_cl_fcmp_cc names[] = {MS_CL_FEQ, MS_CL_FNE, MS_CL_FLT, MS_CL_FLE, MS_CL_FGT, MS_CL_FGE};
  return names[cc];
}

static void compare_inst(ClCx *cx, const MirInst *inst) {
  const MirCc cc = (MirCc)inst->imm.a;
  ms_cl_val v;
  if (inst->op == MOP_FCmp) {
    v = ms_cl_fcmp(cx->fb, float_condition(cc), cl_arg(cx, inst, 0), cl_arg(cx, inst, 1));
  } else {
    v = ms_cl_icmp(cx->fb, int_condition(cc, inst->op == MOP_UICmp), cl_arg(cx, inst, 0), cl_arg(cx, inst, 1));
  }
  cl_set(cx, inst->res, 0, v);
}

/* A constant. The float's bits are a 64-bit integer, so no decimal text can round it. */
static void constant_inst(ClCx *cx, const MirInst *inst) {
  ms_cl_fn *f = cx->fb;
  switch ((MirOp)inst->op) {
  case MOP_FConst: {
    double value;
    const int64_t bits = inst->imm.i;
    __builtin_memcpy(&value, &bits, sizeof value);
    cl_set(cx, inst->res, 0, ms_cl_f64const(f, value));
    return;
  }
  case MOP_BConst:
    cl_set(cx, inst->res, 0, ms_cl_iconst(f, MS_CL_I8, inst->imm.a != 0 ? 1 : 0));
    return;
  default:
    cl_set(cx, inst->res, 0, ms_cl_iconst(f, cl_value_reg_type(cx, inst->res), inst->imm.i));
    return;
  }
}

/* `conv`, `f32.round`: a Float32 result of a double takes one rounding; anything else copies its leaves. */
static void conversion_inst(ClCx *cx, const MirInst *inst) {
  if (inst->op == MOP_F32Round) {
    cl_set(cx, inst->res, 0, round_to_float32(cx, cl_arg(cx, inst, 0)));
    return;
  }
  MsSpan out = cl_value_leaves(cx, inst->res);
  const bool round = out.len == 1 && out.ptr[0] == MIR_LEAF_F32 &&
                     cl_value_leaves(cx, inst->args[0]).ptr[0] == MIR_LEAF_F64;
  if (round) {
    cl_set(cx, inst->res, 0, round_to_float32(cx, cl_arg(cx, inst, 0)));
    return;
  }
  for (uint32_t leaf = 0; leaf < out.len; leaf++) {
    cl_copy_leaf(cx, inst->res, leaf, inst->args[0], leaf);
  }
}

bool cl_scalar_op(ClCx *cx, const MirInst *inst, bool *handled) {
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
    cl_set(cx, inst->res, 0, ms_cl_select(cx->fb, cl_arg(cx, inst, 0), cl_arg(cx, inst, 1), cl_arg(cx, inst, 2)));
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
    const MsSpan leaves = cl_value_leaves(cx, inst->res);
    for (uint32_t leaf = 0; leaf < leaves.len; leaf++) {
      cl_zero_leaf(cx, inst->res, leaf, (MirLeaf)leaves.ptr[leaf]);
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

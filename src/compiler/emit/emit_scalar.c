/* Owns the arithmetic, comparison and constant operations that are one or a few LLVM instructions. */
#include "compiler/emit/emit_cx.h"

/* Operations that are one LLVM instruction on their two operands. `masked` shifts take their amount modulo
 * the width, which LLVM leaves undefined past it. */
typedef struct Binary {
  const char *mnemonic;
  MirOp op;
  bool masked;
} Binary;

static const Binary binaries[] = {
    {"add", MOP_IAdd, false},   {"sub", MOP_ISub, false},   {"mul", MOP_IMul, false},
    {"and", MOP_And, false},    {"or", MOP_Or, false},      {"xor", MOP_Xor, false},
    {"shl", MOP_Shl, true},     {"ashr", MOP_Sshr, true},   {"lshr", MOP_Ushr, true},
    {"fadd", MOP_FAdd, false},  {"fsub", MOP_FSub, false},  {"fmul", MOP_FMul, false},
    {"fdiv", MOP_FDiv, false},  {"sdiv", MOP_SDiv, false},  {"srem", MOP_SRem, false},
};

static const Binary *find_binary(MirOp op) {
  for (size_t index = 0; index < MS_COUNT_OF(binaries); index++) {
    if (binaries[index].op == op) {
      return &binaries[index];
    }
  }
  return NULL;
}

/* Rounds the double named by `source` to the nearest float and back, into `%v<res>`: a Float32 lives in a
 * double register. */
static void round_to_float32(EmitCx *cx, MirValue res, const char *source) {
  uint32_t number = cx->next++;
  ms_strbuild_printf(cx->out, "  %%r%u = fptrunc double %s to float\n  %%v%u = fpext float %%r%u to double\n",
                     number, source, res, number);
}

static bool is_float32(EmitCx *cx, MirValue value) {
  MsSpan leaves = emit_value_leaves(cx, value);
  return leaves.len == 1 && leaves.ptr[0] == MIR_LEAF_F32;
}

static void binary_inst(EmitCx *cx, const MirInst *inst, const Binary *binary) {
  const char *type = emit_value_register_type(cx, inst->res);
  uint32_t number = cx->next++;
  if (binary->masked && cx->is_iconst != NULL && cx->is_iconst[inst->args[1]]) {
    /* A shift by a constant: the amount is masked here, not by an `and` of two constants. */
    ms_strbuild_printf(cx->out, "  %%v%u = %s %s %%v%u, %lld\n", inst->res, binary->mnemonic, type, inst->args[0],
                       (long long)(cx->iconst[inst->args[1]] & 63));
    return;
  }
  if (binary->masked) {
    ms_strbuild_printf(cx->out, "  %%m%u = and %s %%v%u, 63\n  %%v%u = %s %s %%v%u, %%m%u\n", number, type,
                       inst->args[1], inst->res, binary->mnemonic, type, inst->args[0], number);
    return;
  }
  if (type[0] == 'd' && is_float32(cx, inst->res)) {
    /* Computed in double (exact enough for + - * /), rounded once to binary32. */
    char source[24];
    ms_strbuild_printf(cx->out, "  %%t%u = %s double %%v%u, %%v%u\n", number, binary->mnemonic, inst->args[0],
                       inst->args[1]);
    emit_register_name(source, sizeof source, "t", number);
    round_to_float32(cx, inst->res, source);
    return;
  }
  ms_strbuild_printf(cx->out, "  %%v%u = %s %s %%v%u, %%v%u\n", inst->res, binary->mnemonic, type, inst->args[0],
                     inst->args[1]);
}

/* Rotates are funnel shifts of a value with itself; the high half of an unsigned product is a 128-bit
 * multiply; `select` picks by a flag. */
static bool wide_inst(EmitCx *cx, const MirInst *inst) {
  const MirValue *args = inst->args;
  uint32_t number = cx->next++;
  switch ((MirOp)inst->op) {
  case MOP_Rotl:
  case MOP_Rotr:
    ms_strbuild_printf(cx->out, "  %%v%u = call i64 @llvm.%s.i64(i64 %%v%u, i64 %%v%u, i64 %%v%u)\n", inst->res,
                       inst->op == MOP_Rotl ? "fshl" : "fshr", args[0], args[0], args[1]);
    return true;
  case MOP_UMulHi:
    ms_strbuild_printf(cx->out,
                       "  %%w%ua = zext i64 %%v%u to i128\n  %%w%ub = zext i64 %%v%u to i128\n"
                       "  %%w%uc = mul i128 %%w%ua, %%w%ub\n  %%w%ud = lshr i128 %%w%uc, 64\n"
                       "  %%v%u = trunc i128 %%w%ud to i64\n",
                       number, args[0], number, args[1], number, number, number, number, number, inst->res, number);
    return true;
  case MOP_Select: {
    const char *type = emit_value_register_type(cx, inst->res);
    ms_strbuild_printf(cx->out, "  %%v%u = select i1 %%v%u, %s %%v%u, %s %%v%u\n", inst->res, args[0], type, args[1],
                       type, args[2]);
    return true;
  }
  default:
    return false;
  }
}

static const char *float_function(MirOp op) {
  switch (op) {
  case MOP_FSqrt:
    return "sqrt";
  case MOP_FAbs:
    return "fabs";
  case MOP_FFloor:
    return "floor";
  case MOP_FCeil:
    return "ceil";
  default:
    return "trunc";
  }
}

static void float_function_inst(EmitCx *cx, const MirInst *inst) {
  if (inst->op == MOP_FSqrt && is_float32(cx, inst->res)) {
    char source[24];
    uint32_t number = cx->next++;
    ms_strbuild_printf(cx->out, "  %%t%u = call double @llvm.sqrt.f64(double %%v%u)\n", number, inst->args[0]);
    emit_register_name(source, sizeof source, "t", number);
    round_to_float32(cx, inst->res, source);
    return;
  }
  ms_strbuild_printf(cx->out, "  %%v%u = call double @llvm.%s.f64(double %%v%u)\n", inst->res,
                     float_function((MirOp)inst->op), inst->args[0]);
}

static void int_to_float(EmitCx *cx, const MirInst *inst) {
  const char *convert = inst->op == MOP_U2F ? "uitofp" : "sitofp";
  if (emit_value_leaves(cx, inst->res).ptr[0] == MIR_LEAF_F32) {
    /* One rounding, straight to binary32: through a double it would round twice at the midpoints. */
    uint32_t number = cx->next++;
    ms_strbuild_printf(cx->out, "  %%i%u = %s i64 %%v%u to float\n  %%v%u = fpext float %%i%u to double\n",
                       number, convert, inst->args[0], inst->res, number);
    return;
  }
  ms_strbuild_printf(cx->out, "  %%v%u = %s i64 %%v%u to double\n", inst->res, convert, inst->args[0]);
}

/* `f.bits`: the bit pattern of a Float (64 bits) or Float32 (its 32 bits, as a non-negative Int). */
static void float_bits(EmitCx *cx, const MirInst *inst) {
  if (inst->imm.i == 32) {
    uint32_t number = cx->next++;
    ms_strbuild_printf(cx->out,
                       "  %%i%ua = fptrunc double %%v%u to float\n  %%i%ub = bitcast float %%i%ua to i32\n"
                       "  %%v%u = zext i32 %%i%ub to i64\n",
                       number, inst->args[0], number, number, inst->res, number);
    return;
  }
  ms_strbuild_printf(cx->out, "  %%v%u = bitcast double %%v%u to i64\n", inst->res, inst->args[0]);
}

/* `bits.f`: a Float of 64 bits, or a Float32 of the low 32 bits. */
static void bits_float(EmitCx *cx, const MirInst *inst) {
  if (inst->imm.i == 32) {
    uint32_t number = cx->next++;
    ms_strbuild_printf(cx->out,
                       "  %%i%ua = trunc i64 %%v%u to i32\n  %%i%ub = bitcast i32 %%i%ua to float\n"
                       "  %%v%u = fpext float %%i%ub to double\n",
                       number, inst->args[0], number, number, inst->res, number);
    return;
  }
  ms_strbuild_printf(cx->out, "  %%v%u = bitcast i64 %%v%u to double\n", inst->res, inst->args[0]);
}

/* The one-operand operations. */
static bool unary_inst(EmitCx *cx, const MirInst *inst) {
  MsStrBuild *out = cx->out;
  switch ((MirOp)inst->op) {
  case MOP_Not: {
    const char *type = emit_value_register_type(cx, inst->res);
    ms_strbuild_printf(out, "  %%v%u = xor %s %%v%u, %s\n", inst->res, type, inst->args[0],
                       type[1] == '1' ? "true" : "1");
    return true;
  }
  case MOP_FNeg:
    ms_strbuild_printf(out, "  %%v%u = fneg double %%v%u\n", inst->res, inst->args[0]);
    return true;
  case MOP_I2F:
  case MOP_U2F:
    int_to_float(cx, inst);
    return true;
  case MOP_FBits:
    float_bits(cx, inst);
    return true;
  case MOP_BitsF:
    bits_float(cx, inst);
    return true;
  case MOP_B2I:
    ms_strbuild_printf(out, "  %%v%u = zext i1 %%v%u to i64\n", inst->res, inst->args[0]);
    return true;
  case MOP_INeg:
    ms_strbuild_printf(out, "  %%v%u = sub i64 0, %%v%u\n", inst->res, inst->args[0]);
    return true;
  case MOP_Clz:
  case MOP_Ctz:
    ms_strbuild_printf(out, "  %%v%u = call i64 @llvm.%s.i64(i64 %%v%u, i1 false)\n", inst->res,
                       inst->op == MOP_Clz ? "ctlz" : "cttz", inst->args[0]);
    return true;
  case MOP_Popcnt:
    ms_strbuild_printf(out, "  %%v%u = call i64 @llvm.ctpop.i64(i64 %%v%u)\n", inst->res, inst->args[0]);
    return true;
  case MOP_FSqrt:
  case MOP_FAbs:
  case MOP_FFloor:
  case MOP_FCeil:
  case MOP_FTrunc:
    float_function_inst(cx, inst);
    return true;
  default:
    return false;
  }
}

static const char *condition_name(MirCc cc, bool is_unsigned, bool is_float) {
  static const char *const signed_names[] = {"eq", "ne", "slt", "sle", "sgt", "sge"};
  static const char *const unsigned_names[] = {"eq", "ne", "ult", "ule", "ugt", "uge"};
  static const char *const float_names[] = {"oeq", "une", "olt", "ole", "ogt", "oge"};
  if (is_float) {
    return float_names[cc];
  }
  return is_unsigned ? unsigned_names[cc] : signed_names[cc];
}

static void compare_inst(EmitCx *cx, const MirInst *inst) {
  bool is_float = inst->op == MOP_FCmp;
  const char *type = is_float ? "double" : emit_value_register_type(cx, inst->args[0]);
  ms_strbuild_printf(cx->out, "  %%v%u = %s %s %s %%v%u, %%v%u\n", inst->res, is_float ? "fcmp" : "icmp",
                     condition_name((MirCc)inst->imm.a, inst->op == MOP_UICmp, is_float), type, inst->args[0],
                     inst->args[1]);
}

/* A constant. The float's bits go through an integer and a cast, so no decimal text can round it. */
static void constant_inst(EmitCx *cx, const MirInst *inst) {
  switch ((MirOp)inst->op) {
  case MOP_FConst:
    ms_strbuild_printf(cx->out, "  %%v%u = bitcast i64 %lld to double\n", inst->res, (long long)inst->imm.i);
    return;
  case MOP_BConst:
    ms_strbuild_printf(cx->out, "  %%v%u = or i1 false, %s\n", inst->res, inst->imm.a != 0 ? "true" : "false");
    return;
  default:
    ms_strbuild_printf(cx->out, "  %%v%u = add %s 0, %lld\n", inst->res, emit_value_register_type(cx, inst->res),
                       (long long)inst->imm.i);
    return;
  }
}

/* `conv`, `f32.round`: a Float32 result of a double takes one rounding; anything else copies its leaves. */
static void conversion_inst(EmitCx *cx, const MirInst *inst) {
  char source[24];
  emit_register_name(source, sizeof source, "v", inst->args[0]);
  if (inst->op == MOP_F32Round) {
    round_to_float32(cx, inst->res, source);
    return;
  }
  MsSpan out = emit_value_leaves(cx, inst->res);
  bool round = out.len == 1 && out.ptr[0] == MIR_LEAF_F32 &&
               emit_value_leaves(cx, inst->args[0]).ptr[0] == MIR_LEAF_F64;
  if (round) {
    round_to_float32(cx, inst->res, source);
    return;
  }
  for (uint32_t leaf = 0; leaf < out.len; leaf++) {
    emit_copy_leaf(cx, inst->res, leaf, inst->args[0], leaf);
  }
}

bool emit_scalar_op(EmitCx *cx, const MirInst *inst, const EmitSite *site, bool *handled) {
  (void)site;
  *handled = true;
  const Binary *binary = find_binary((MirOp)inst->op);
  if (binary != NULL) {
    binary_inst(cx, inst, binary);
    return true;
  }
  if (unary_inst(cx, inst) || wide_inst(cx, inst)) {
    return true;
  }
  switch ((MirOp)inst->op) {
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
  case MOP_VoidConst:
  case MOP_DepthLeave:
    return true; /* nothing to write */
  default:
    *handled = false;
    return true;
  }
}

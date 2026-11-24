/* compiler/lower/lower_scalar_ops.c: the runtime natives whose whole job is a few machine instructions. A native
 * declared `@op=<name>` in its `ms-sig` is written out as MIR here instead of being called, so the backend sees the
 * arithmetic and folds, hoists and vectorises it; the runtime keeps the heavy operations (text, parsing, memory).
 * An operation returns false, emitting nothing, when its operands are not the types it expects, and the caller then
 * calls the native. A fault keeps the message and the location the native gave it. */
#include "compiler/lower/lower_fn.h"
#include "compiler/natives/native_sigs.h"

static bool is_int(MirTy ty) {
  return ty == MIR_INT || ty == MIR_INT8 || ty == MIR_INT16 || ty == MIR_INT32 || ty == MIR_UINT8 || ty == MIR_UINT16 ||
         ty == MIR_UINT32 || ty == MIR_UINT64;
}

static bool is_float(MirTy ty) {
  return ty == MIR_FLOAT || ty == MIR_FLOAT32;
}

static MirValue emit1(LowerFn *fn, MirOp op, MirValue operand, MirTy ty) {
  return fn_checked_emit(fn, op, &operand, 1, (MirImm){0}, ty);
}

static MirValue float_const(LowerFn *fn, double value, MirTy ty) {
  MirImm imm = {.tag = MI_FLOAT};
  __builtin_memcpy(&imm.i, &value, sizeof value);
  return mir_b_emit(&fn->b, MOP_FConst, NULL, 0, imm, ty);
}

static MirValue fcmp(LowerFn *fn, MirCc cc, MirValue left, MirValue right) {
  const MirValue operands[2] = {left, right};
  return mir_b_emit(&fn->b, MOP_FCmp, operands, 2, (MirImm){.tag = MI_CC, .a = (uint32_t)cc}, MIR_BOOL);
}

/* `1` when `cc` holds and `0` otherwise, as an Int. */
static MirValue flag(LowerFn *fn, MirValue condition) {
  return emit1(fn, MOP_B2I, condition, MIR_INT);
}

/* The three-way order of two operands as -1, 0 or 1, from the two flags that differ. */
static MirValue order(LowerFn *fn, MirValue greater, MirValue less) {
  return mir_b_binop(&fn->b, MOP_ISub, flag(fn, greater), flag(fn, less));
}

/* An Int result in the integer type the native returns. */
static MirValue as_result(LowerFn *fn, MirValue value, MirTy ret) {
  return ret == MIR_INT ? value : emit1(fn, MOP_Conv, value, ret);
}

static bool float_unary(LowerFn *fn, MirOp op, const MirValue *args, uint32_t argc, MirTy ret, MirValue *out) {
  if (argc != 1 || !is_float(mir_b_ty(&fn->b, args[0])) || ret != mir_b_ty(&fn->b, args[0])) {
    return false;
  }
  *out = emit1(fn, op, args[0], ret);
  return true;
}

/* `NaN` stays `NaN`, a zero keeps its sign, anything else is -1.0 or 1.0. */
static bool float_sign(LowerFn *fn, const MirValue *args, uint32_t argc, MirTy ret, MirValue *out) {
  const MirTy ty = argc == 1 ? mir_b_ty(&fn->b, args[0]) : MIR_NONE;
  if (!is_float(ty) || ret != ty) {
    return false;
  }
  const MirValue zero = float_const(fn, 0.0, ty);
  const MirValue negative = mir_b_select(&fn->b, fcmp(fn, MCC_LT, args[0], zero), float_const(fn, -1.0, ty), args[0]);
  *out = mir_b_select(&fn->b, fcmp(fn, MCC_GT, args[0], zero), float_const(fn, 1.0, ty), negative);
  return true;
}

/* The order of two floats: a NaN is greater than every number and equal to another NaN. */
static bool float_compare(LowerFn *fn, const MirValue *args, uint32_t argc, MirTy ret, MirValue *out) {
  const MirTy ty = argc == 2 ? mir_b_ty(&fn->b, args[0]) : MIR_NONE;
  if (!is_float(ty) || mir_b_ty(&fn->b, args[1]) != ty || ret != MIR_INT) {
    return false;
  }
  const MirValue numbers = order(fn, fcmp(fn, MCC_GT, args[0], args[1]), fcmp(fn, MCC_LT, args[0], args[1]));
  const MirValue nans = order(fn, fcmp(fn, MCC_NE, args[0], args[0]), fcmp(fn, MCC_NE, args[1], args[1]));
  *out = mir_b_binop(&fn->b, MOP_IAdd, numbers, nans);
  return true;
}

static bool float_is_nan(LowerFn *fn, const MirValue *args, uint32_t argc, MirTy ret, MirValue *out) {
  if (argc != 1 || !is_float(mir_b_ty(&fn->b, args[0])) || ret != MIR_BOOL) {
    return false;
  }
  *out = fcmp(fn, MCC_NE, args[0], args[0]);
  return true;
}

/* Finite when `v - v` is zero: infinity and NaN both give NaN. */
static bool float_is_finite(LowerFn *fn, const MirValue *args, uint32_t argc, MirTy ret, MirValue *out) {
  const MirTy ty = argc == 1 ? mir_b_ty(&fn->b, args[0]) : MIR_NONE;
  if (!is_float(ty) || ret != MIR_BOOL) {
    return false;
  }
  const MirValue operands[2] = {args[0], args[0]};
  const MirValue difference = mir_b_emit(&fn->b, MOP_FSub, operands, 2, (MirImm){0}, ty);
  *out = fcmp(fn, MCC_EQ, difference, float_const(fn, 0.0, ty));
  return true;
}

/* `to_int` of a float: the integer part when it fits an Int, none otherwise. */
static bool float_truncate_to_int(LowerFn *fn, const MirValue *args, uint32_t argc, MirTy ret, MirValue *out) {
  const MirTyData *data = mir_ty_data(fn->cx->module, ret);
  if (argc != 1 || !is_float(mir_b_ty(&fn->b, args[0])) || data->kind != MK_OPT || data->elem != MIR_INT) {
    return false;
  }
  *out = emit1(fn, MOP_F2IOpt, args[0], ret);
  return true;
}

static bool int_compare(LowerFn *fn, const MirValue *args, uint32_t argc, MirTy ret, MirValue *out) {
  const MirTy ty = argc == 2 ? mir_b_ty(&fn->b, args[0]) : MIR_NONE;
  if (!is_int(ty) || mir_b_ty(&fn->b, args[1]) != ty || ret != MIR_INT) {
    return false;
  }
  *out = order(fn, mir_b_icmp(&fn->b, MCC_GT, args[0], args[1]), mir_b_icmp(&fn->b, MCC_LT, args[0], args[1]));
  return true;
}

static bool int_sign(LowerFn *fn, const MirValue *args, uint32_t argc, MirTy ret, MirValue *out) {
  const MirTy ty = argc == 1 ? mir_b_ty(&fn->b, args[0]) : MIR_NONE;
  if (!is_int(ty) || ty == MIR_UINT64 || !is_int(ret)) {
    return false;
  }
  const MirValue zero = emit1(fn, MOP_Conv, mir_b_iconst(&fn->b, 0), ty);
  *out = as_result(fn, order(fn, mir_b_icmp(&fn->b, MCC_GT, args[0], zero), mir_b_icmp(&fn->b, MCC_LT, args[0], zero)), ret);
  return true;
}

/* `Int.abs`: the lowest value has no absolute value and faults as an overflow, like a negation of it. */
static bool int_abs(LowerFn *fn, const MirValue *args, uint32_t argc, MirTy ret, MirValue *out) {
  if (argc != 1 || mir_b_ty(&fn->b, args[0]) != MIR_INT || ret != MIR_INT) {
    return false;
  }
  const MirValue negative = mir_b_icmp(&fn->b, MCC_LT, args[0], mir_b_iconst(&fn->b, 0));
  *out = mir_b_select(&fn->b, negative, emit1(fn, MOP_INegChk, args[0], MIR_INT), args[0]);
  return true;
}

/* The abs of a sized signed type: the lowest value faults as out of range, as a result that does not fit does. */
static bool sized_abs(LowerFn *fn, const MirValue *args, uint32_t argc, MirTy ret, MirValue *out) {
  const MirTy ty = argc == 1 ? mir_b_ty(&fn->b, args[0]) : MIR_NONE;
  if ((ty != MIR_INT8 && ty != MIR_INT16 && ty != MIR_INT32) || ret != ty) {
    return false;
  }
  const MirValue wide = emit1(fn, MOP_Conv, args[0], MIR_INT);
  const MirValue negative = mir_b_icmp(&fn->b, MCC_LT, wide, mir_b_iconst(&fn->b, 0));
  *out = emit1(fn, MOP_NarrowChk, mir_b_select(&fn->b, negative, emit1(fn, MOP_INeg, wide, MIR_INT), wide), ret);
  return true;
}

/* `to_<wider>` of an integer that always fits, and the Int64 spelling of Int. */
static bool int_widen(LowerFn *fn, const MirValue *args, uint32_t argc, MirTy ret, MirValue *out) {
  const MirTy ty = argc == 1 ? mir_b_ty(&fn->b, args[0]) : MIR_NONE;
  if (!is_int(ty) || !is_int(ret) || ty == MIR_UINT64 || ret == MIR_UINT64) {
    return false;
  }
  *out = ty == ret ? args[0] : emit1(fn, MOP_Conv, args[0], ret);
  return true;
}

/* `to_<narrower>` of an integer: the value when it is in the range of the type, none otherwise. */
static bool int_narrow(LowerFn *fn, const MirValue *args, uint32_t argc, MirTy ret, MirValue *out) {
  const MirTyData *data = mir_ty_data(fn->cx->module, ret);
  if (argc != 1 || !is_int(mir_b_ty(&fn->b, args[0])) || data->kind != MK_OPT || !is_int(data->elem)) {
    return false;
  }
  *out = emit1(fn, MOP_INarrowOpt, args[0], ret);
  return true;
}

/* `to_float` and `to_float32` of a signed or narrow unsigned integer (UInt64 reads its bits as unsigned). */
static bool int_to_float(LowerFn *fn, const MirValue *args, uint32_t argc, MirTy ret, MirValue *out) {
  const MirTy ty = argc == 1 ? mir_b_ty(&fn->b, args[0]) : MIR_NONE;
  if (!is_int(ty) || ty == MIR_UINT64 || !is_float(ret)) {
    return false;
  }
  *out = emit1(fn, MOP_I2F, args[0], ret);
  return true;
}

/* `UInt64.to_float` and `to_float32`: the bits are read as unsigned. */
static bool uint_to_float(LowerFn *fn, const MirValue *args, uint32_t argc, MirTy ret, MirValue *out) {
  if (argc != 1 || mir_b_ty(&fn->b, args[0]) != MIR_UINT64 || !is_float(ret)) {
    return false;
  }
  *out = emit1(fn, MOP_U2F, args[0], ret);
  return true;
}

/* `Float.to_bits`, `Float32.to_bits`. */
static bool float_bits_of(LowerFn *fn, int64_t width, const MirValue *args, uint32_t argc, MirTy ret, MirValue *out) {
  if (argc != 1 || !is_float(mir_b_ty(&fn->b, args[0])) || ret != MIR_INT) {
    return false;
  }
  *out = mir_b_emit(&fn->b, MOP_FBits, args, 1, (MirImm){.tag = MI_INT, .i = width}, MIR_INT);
  return true;
}

static bool float_to_bits(LowerFn *fn, const MirValue *args, uint32_t argc, MirTy ret, MirValue *out) {
  return float_bits_of(fn, 64, args, argc, ret, out);
}

static bool float32_to_bits(LowerFn *fn, const MirValue *args, uint32_t argc, MirTy ret, MirValue *out) {
  return float_bits_of(fn, 32, args, argc, ret, out);
}

/* `Float.from_bits`, `Float32.from_bits`. */
static bool float_from_bits_of(LowerFn *fn, int64_t width, const MirValue *args, uint32_t argc, MirTy ret,
                               MirValue *out) {
  if (argc != 1 || mir_b_ty(&fn->b, args[0]) != MIR_INT || !is_float(ret)) {
    return false;
  }
  *out = mir_b_emit(&fn->b, MOP_BitsF, args, 1, (MirImm){.tag = MI_INT, .i = width}, ret);
  return true;
}

static bool float_from_bits(LowerFn *fn, const MirValue *args, uint32_t argc, MirTy ret, MirValue *out) {
  return float_from_bits_of(fn, 64, args, argc, ret, out);
}

static bool float32_from_bits(LowerFn *fn, const MirValue *args, uint32_t argc, MirTy ret, MirValue *out) {
  return float_from_bits_of(fn, 32, args, argc, ret, out);
}

/* `Float32.to_float`: every binary32 value is a double. */
static bool float_widen(LowerFn *fn, const MirValue *args, uint32_t argc, MirTy ret, MirValue *out) {
  if (argc != 1 || mir_b_ty(&fn->b, args[0]) != MIR_FLOAT32 || ret != MIR_FLOAT) {
    return false;
  }
  *out = emit1(fn, MOP_Conv, args[0], MIR_FLOAT);
  return true;
}

/* The length of a list or bytes, or the byte length of a string; `empty` asks whether it is zero. */
static bool length(LowerFn *fn, MirOp op, MirTy operand, bool empty, const MirValue *args, uint32_t argc, MirTy ret,
                   MirValue *out) {
  if (argc != 1 || ret != (empty ? MIR_BOOL : MIR_INT)) {
    return false;
  }
  const MirTy ty = mir_b_ty(&fn->b, args[0]);
  const bool fits = operand == MIR_STR ? ty == MIR_STR : (ty == MIR_BYTES || mir_ty_data(fn->cx->module, ty)->kind == MK_LIST);
  if (!fits) {
    return false;
  }
  const MirValue size = emit1(fn, op, args[0], MIR_INT);
  *out = empty ? mir_b_icmp(&fn->b, MCC_EQ, size, mir_b_iconst(&fn->b, 0)) : size;
  return true;
}

/* One MIR instruction on Int operands: the standard wrapper has already checked a shift count, and a rotation takes
 * its count modulo 64. */
static bool bit_op(LowerFn *fn, MirOp op, uint32_t operands, const MirValue *args, uint32_t argc, MirTy ret,
                   MirValue *out) {
  if (argc != operands || ret != MIR_INT || mir_b_ty(&fn->b, args[0]) != MIR_INT) {
    return false;
  }
  *out = argc == 2 ? fn_checked_emit(fn, op, args, 2, (MirImm){0}, mir_b_ty(&fn->b, args[0])) : emit1(fn, op, args[0], MIR_INT);
  return true;
}

bool fn_inline_scalar_op(LowerFn *fn, const char *name, const MirValue *args, uint32_t argc, MirTy ret, MirValue *out) {
  static const struct {
    const char *name;
    MirOp op;
    uint32_t operands;
  } bits[] = {{"and", MOP_And, 2},       {"or", MOP_Or, 2},         {"xor", MOP_Xor, 2},       {"shl", MOP_Shl, 2},
              {"sshr", MOP_Sshr, 2},     {"ushr", MOP_Ushr, 2},     {"rotl", MOP_Rotl, 2},     {"rotr", MOP_Rotr, 2},
              {"popcnt", MOP_Popcnt, 1}, {"clz", MOP_Clz, 1},       {"ctz", MOP_Ctz, 1},       {"iadd", MOP_IAdd, 2},
              {"isub", MOP_ISub, 2},     {"imul", MOP_IMul, 2}};
  static const struct {
    const char *name;
    MirOp op;
  } floats[] = {{"fabs", MOP_FAbs}, {"fsqrt", MOP_FSqrt}, {"ffloor", MOP_FFloor}, {"fceil", MOP_FCeil}, {"ftrunc", MOP_FTrunc}};
  static const struct {
    const char *name;
    bool (*run)(LowerFn *, const MirValue *, uint32_t, MirTy, MirValue *);
  } ops[] = {{"fsign", float_sign},
             {"fcompare", float_compare},
             {"fis_nan", float_is_nan},
             {"fis_finite", float_is_finite},
             {"ftruncate_int", float_truncate_to_int},
             {"icompare", int_compare},
             {"isign", int_sign},
             {"iabs", int_abs},
             {"sized_abs", sized_abs},
             {"widen", int_widen},
             {"narrow", int_narrow},
             {"to_float", int_to_float},
             {"float_widen", float_widen},
             {"uint_to_float", uint_to_float},
             {"float_bits", float_to_bits},
             {"bits_float", float_from_bits},
             {"float32_bits", float32_to_bits},
             {"float32_bits_float", float32_from_bits}};
  const MsSpan op = ms_span_of_text(name);
  for (size_t at = 0; at < MS_COUNT_OF(bits); at++) {
    if (ms_span_is_text(op, bits[at].name)) {
      return bit_op(fn, bits[at].op, bits[at].operands, args, argc, ret, out);
    }
  }
  for (size_t at = 0; at < MS_COUNT_OF(floats); at++) {
    if (ms_span_is_text(op, floats[at].name)) {
      return float_unary(fn, floats[at].op, args, argc, ret, out);
    }
  }
  for (size_t at = 0; at < MS_COUNT_OF(ops); at++) {
    if (ms_span_is_text(op, ops[at].name)) {
      return ops[at].run(fn, args, argc, ret, out);
    }
  }
  if (ms_span_is_text(op, "list_len") || ms_span_is_text(op, "list_is_empty")) {
    return length(fn, MOP_ListLen, MIR_BYTES, ms_span_is_text(op, "list_is_empty"), args, argc, ret, out);
  }
  if (ms_span_is_text(op, "str_bytes") || ms_span_is_text(op, "str_is_empty")) {
    return length(fn, MOP_StrBytes, MIR_STR, ms_span_is_text(op, "str_is_empty"), args, argc, ret, out);
  }
  return false;
}

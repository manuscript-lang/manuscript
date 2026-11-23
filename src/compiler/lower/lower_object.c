/* Owns the operators of value objects: negation and binary operators call the object type's runtime functions. */
#include "compiler/lower/lower_fn.h"
#include "compiler/natives/native_sigs.h"
#include "compiler/mir/mir_analysis.h"

/* The operation word of a binary operator on a value object: its runtime function is `msstd_<type>_<word>`, the
 * receiver type's lowercase name as for every standard operation. A comparison reads the result of `compare`
 * against zero; `==` and `!=` use `equal`. */
typedef struct ObjectOp {
  const char *word;
  const char *fallback; /* the word a type without `word` has instead, or NULL */
  MirCc cc;
  bool compare;
} ObjectOp;

static bool object_op(MsBinaryOp op, ObjectOp *out) {
  switch (op) {
    case MS_B_ADD: *out = (ObjectOp){"add", NULL, MCC_EQ, false}; return true;
    case MS_B_SUB: *out = (ObjectOp){"subtract", NULL, MCC_EQ, false}; return true;
    case MS_B_MUL: *out = (ObjectOp){"multiply", NULL, MCC_EQ, false}; return true;
    case MS_B_DIV: *out = (ObjectOp){"quotient", "divide", MCC_EQ, false}; return true;
    case MS_B_REM: *out = (ObjectOp){"modulo", "remainder", MCC_EQ, false}; return true;
    case MS_B_EQ: *out = (ObjectOp){"equal", "compare", MCC_EQ, false}; return true;
    case MS_B_NE: *out = (ObjectOp){"equal", "compare", MCC_NE, false}; return true;
    case MS_B_LT: *out = (ObjectOp){"compare", NULL, MCC_LT, true}; return true;
    case MS_B_GT: *out = (ObjectOp){"compare", NULL, MCC_GT, true}; return true;
    case MS_B_LE: *out = (ObjectOp){"compare", NULL, MCC_LE, true}; return true;
    case MS_B_GE: *out = (ObjectOp){"compare", NULL, MCC_GE, true}; return true;
    default: return false;
  }
}

/* `msstd_<type>_<word>` for the value object `type`. */
static MsName object_function(LowerFn *fn, MsName type, const char *word) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "msstd_");
  const MsSpan type_name = ms_names_span(&fn->cx->module->names, type);
  for (size_t at = 0; at < type_name.len; at++) {
    const uint8_t byte = type_name.ptr[at];
    ms_strbuild_append_byte(&text, byte >= 'A' && byte <= 'Z' ? (uint8_t)(byte - 'A' + 'a') : byte);
  }
  ms_strbuild_append_byte(&text, '_');
  ms_strbuild_append_text(&text, word);
  const MsName name = mir_name(fn->cx->module, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  return name;
}

/* The name of a standard value type an operator is written on: a value object, or an inline native record. */
static bool value_type_name(const LowerFn *fn, MirTy type, MsName *name) {
  const MirTyData *data = mir_ty_data(fn->cx->module, type);
  if (data->kind == MK_OBJ && data->obj_class == MIR_OBJ_VALUE) {
    *name = data->name;
    return true;
  }
  if (data->kind == MK_TYPE && fn->cx->module->type_defs.ptr[data->id].native) {
    *name = fn->cx->module->type_defs.ptr[data->id].name;
    return true;
  }
  return false;
}

bool fn_object_negate(LowerFn *fn, MirValue operand, MirValue *out) {
  MsName type = MS_NAME_EMPTY;
  if (!value_type_name(fn, mir_b_ty(&fn->b, operand), &type)) {
    return false;
  }
  const MsName name = object_function(fn, type, "negate");
  if (ms_native_sig_find(ms_names_span(&fn->cx->module->names, name)) == NULL) {
    return false;
  }
  *out = fn_runtime_call(fn, name, &operand, 1, mir_b_ty(&fn->b, operand));
  return true;
}

bool fn_object_binary(LowerFn *fn, MsBinaryOp op, MirValue left, MirValue right, MirValue *out) {
  MsName type = MS_NAME_EMPTY;
  ObjectOp info;
  if (!value_type_name(fn, mir_b_ty(&fn->b, left), &type) || !object_op(op, &info)) {
    return false;
  }
  MsName name = object_function(fn, type, info.word);
  if (ms_native_sig_find(ms_names_span(&fn->cx->module->names, name)) == NULL) {
    if (info.fallback == NULL) {
      return false;
    }
    name = object_function(fn, type, info.fallback);
    if (ms_native_sig_find(ms_names_span(&fn->cx->module->names, name)) == NULL) {
      return false;
    }
    if (op == MS_B_EQ || op == MS_B_NE) {
      info.compare = true; /* equal when `compare` is zero */
    }
  }
  const MirValue operands[2] = {left, right};
  const bool equality = !info.compare && (op == MS_B_EQ || op == MS_B_NE);
  const MirTy ret = info.compare ? MIR_INT : (equality ? MIR_BOOL : mir_b_ty(&fn->b, left));
  const MirValue result = fn_runtime_call(fn, name, operands, 2, ret);
  if (result == MIR_NONE) {
    *out = MIR_NONE;
  } else if (info.compare) {
    *out = mir_b_icmp(&fn->b, info.cc, result, mir_b_iconst(&fn->b, 0));
  } else if (op == MS_B_NE) {
    *out = mir_b_icmp(&fn->b, MCC_EQ, result, mir_b_bconst(&fn->b, false));
  } else {
    *out = result;
  }
  return true;
}

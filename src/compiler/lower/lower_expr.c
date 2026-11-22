/* compiler/lower/lower_expr.c: expressions: literals, names, arithmetic and comparison. */
#include "base/float_parse.h"
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_analysis.h"

/* The value of a number spelling: decimal, `0x`, `0b` or `0o` digits with `_` separators, up to 64 bits (a
 * literal above Int's range is the bit pattern of its two's complement, so `-9223372036854775808` negates it). */
bool fn_number_bits(MsSpan text, uint64_t *out) {
  uint64_t radix = 10;
  size_t at = 0;
  if (text.len > 2 && text.ptr[0] == '0' && (text.ptr[1] == 'x' || text.ptr[1] == 'b' || text.ptr[1] == 'o')) {
    radix = text.ptr[1] == 'x' ? 16 : (text.ptr[1] == 'b' ? 2 : 8);
    at = 2;
  }
  uint64_t value = 0;
  for (; at < text.len; at++) {
    const uint8_t byte = (uint8_t)text.ptr[at];
    if (byte == '_') {
      continue;
    }
    uint64_t digit = radix;
    if (byte >= '0' && byte <= '9') {
      digit = (uint64_t)(byte - '0');
    } else if (byte >= 'a' && byte <= 'f') {
      digit = (uint64_t)(byte - 'a') + 10;
    } else if (byte >= 'A' && byte <= 'F') {
      digit = (uint64_t)(byte - 'A') + 10;
    }
    if (digit >= radix || value > (UINT64_MAX - digit) / radix) {
      return false;
    }
    value = value * radix + digit;
  }
  *out = value;
  return true;
}

static MirValue lower_float(LowerFn *fn, MsSpan text, MirTy ty) {
  double value = 0;
  if (ms_parse_float(text, &value) != MS_PARSE_FLOAT_OK) {
    (void)fn_fail(fn, "a number literal is not a Float that fits");
    return MIR_NONE;
  }
  MirImm imm = {.tag = MI_FLOAT};
  __builtin_memcpy(&imm.i, &value, sizeof value);
  return fn_emit(fn, MOP_FConst, NULL, 0, imm, ty);
}

static MirValue lower_number(LowerFn *fn, const MsExpr *expr) {
  const MsSpan text = ms_names_span(fn->cx->program->names, expr->u.sym);
  const MirTy ty = fn_type(fn, ms_facts_type(fn->facts, expr->id));
  if (ty == MIR_FLOAT || ty == MIR_FLOAT32) {
    return lower_float(fn, text, ty);
  }
  uint64_t bits = 0;
  if (!fn_number_bits(text, &bits)) {
    (void)fn_fail(fn, "a number literal is not a whole number that fits 64 bits");
    return MIR_NONE;
  }
  const int64_t value = (int64_t)bits;
  if (ty == MIR_INT) {
    return mir_b_iconst(&fn->b, value);
  }
  const MirImm imm = {.tag = MI_INT, .i = value};
  return fn_emit(fn, MOP_IConst, NULL, 0, imm, ty);
}

static MirValue lower_text(LowerFn *fn, const MsExpr *expr) {
  if (expr->u.text.len > 1 || (expr->u.text.len == 1 && expr->u.text.ptr[0].expr != NULL)) {
    return fn_text(fn, expr);
  }
  const MsSpan text = expr->u.text.len == 0 ? ms_span_of_text("") : expr->u.text.ptr[0].lit;
  const MirImm imm = {.tag = MI_STR, .a = mir_add_string(fn->cx->module, text)};
  return fn_emit(fn, MOP_StrLit, NULL, 0, imm, fn_type(fn, ms_facts_type(fn->facts, expr->id)));
}

MirVar fn_local(LowerFn *fn, uint32_t local, MirTy ty) {
  if (local >= fn->nvars) {
    (void)fn_fail(fn, "a local binding is outside the function's locals");
    return 0;
  }
  if (fn->vars[local] == 0) {
    fn->vars[local] = mir_b_declare_var(&fn->b, ty, MM_BORROW) + 1;
  }
  return fn->vars[local] - 1;
}

/* The value of the parameter or local `ref` names; `expr` is the name (a callee's ref is on its call). */
/* A module constant: its initializer lowered where it is read, under the facts and file of the module that declares
 * it. The value is read-only, so each read is the same value. */
static MirValue lower_constant(LowerFn *fn, const MsRef *ref) {
  const MsSymbolId id = fn_symbol_at(fn->cx, ref->decl);
  const MsDecl *decl = id == 0 ? NULL : fn->cx->program->symbols.ptr[id].decl;
  if (decl == NULL || decl->kind != MS_D_CONST || decl->u.konst.value == NULL) {
    (void)fn_fail(fn, "a constant has no initializer to read");
    return MIR_NONE;
  }
  const MsFacts *facts = fn->facts;
  const uint32_t module_index = fn->module_index;
  const uint32_t file = fn->file;
  fn->facts = &fn->cx->program->modules.ptr[ref->decl.module].facts;
  fn->module_index = ref->decl.module;
  fn->file = lower_file(fn->cx, ref->decl.module);
  const MirValue value = fn_expr(fn, decl->u.konst.value, LW_BORROW);
  fn->facts = facts;
  fn->module_index = module_index;
  fn->file = file;
  return value;
}

/* A parameter named by a default argument: the value the call passes for it, which must already be known. */
static MirValue default_param(LowerFn *fn, const MsRef *ref) {
  const MsCall *call = fn->default_call;
  const size_t declared = ms_ty_param_count(&fn->cx->program->types, call->callee_ty);
  const uint32_t at = ref->local + (uint32_t)(call->arg_count - declared);
  if (at >= call->arg_count || (call->args[at].flags & MS_PARAM_VAR) != 0) {
    (void)fn_fail(fn, "a default argument that reads a `var` parameter is not lowered yet");
    return MIR_NONE;
  }
  const MirValue value = fn->default_args[at];
  if (value == MIR_NONE) {
    (void)fn_fail(fn, "a default argument reads a parameter that has no value yet");
  }
  return value;
}

MirValue fn_name_ref(LowerFn *fn, const MsExpr *expr, const MsRef *ref) {
  MirValue captured = MIR_NONE;
  if (fn_lambda_name(fn, expr, ref, &captured)) {
    return captured;
  }
  if (fn_closing_read(fn, ref, &captured)) {
    return captured;
  }
  if (ref != NULL && ref->kind == MS_REF_PARAM && fn->default_call != NULL) {
    return default_param(fn, ref);
  }
  if (ref != NULL && ref->kind == MS_REF_PARAM && fn->param_vars == NULL) {
    /* A field default reads an earlier field of the record under construction, in place. */
    if (fn->default_base == MIR_NONE) {
      (void)fn_fail(fn, "a name read outside a function has no value");
      return MIR_NONE;
    }
    const MirImm of_record = {.tag = MI_TY, .a = fn->default_record_ty};
    const MirValue record = fn_emit(fn, MOP_Load, &fn->default_base, 1, of_record, fn->default_record_ty);
    const MirTyData *data = mir_ty_data(fn->cx->module, fn->default_record_ty);
    if (data->kind != MK_TYPE || ref->local >= fn->cx->module->type_defs.ptr[data->id].nfields) {
      (void)fn_fail(fn, "a field default reads a field its record does not have");
      return MIR_NONE;
    }
    const MirImm field = {.tag = MI_FIELD, .a = data->id, .b = ref->local};
    return fn_emit(fn, MOP_TypeGet, &record, 1, field, fn->cx->module->type_defs.ptr[data->id].fields[ref->local].ty);
  }
  if (ref != NULL && ref->kind == MS_REF_PARAM) {
    return mir_b_use_var(&fn->b, fn->param_vars[ref->local]);
  }
  if (ref != NULL && ref->kind == MS_REF_LOCAL && ref->local < fn->nvars && fn->vars[ref->local] != 0) {
    return mir_b_use_var(&fn->b, fn->vars[ref->local] - 1);
  }
  if (ref != NULL && ref->kind == MS_REF_FUNCTION) {
    return fn_function_value(fn, expr, ref);
  }
  if (ref != NULL && ref->kind == MS_REF_CONSTANT) {
    return lower_constant(fn, ref);
  }
  const MsTy checked = ms_facts_type(fn->facts, expr->id);
  if (checked == MS_TY_NONE && fn->hint != MIR_VOID && mir_ty_data(fn->cx->module, fn->hint)->kind == MK_OPT &&
      (ref == NULL || ref->kind == MS_REF_NONE || ref->kind == MS_REF_CASE)) {
    /* A default value the checker did not type: `none` for an optional parameter or field. */
    return fn_emit(fn, MOP_OptNone, NULL, 0, (MirImm){0}, fn->hint);
  }
  if (checked == MS_TY_NONE || (ref != NULL && ref->kind != MS_REF_NONE && ref->kind != MS_REF_CASE)) {
    (void)fn_fail(fn, "a name does not refer to a parameter, a local or a function (at %u:%u, reference kind %d, type %s)", expr->pos.line,
                  expr->pos.column, ref != NULL ? (int)ref->kind : -1, checked == MS_TY_NONE ? "unrecorded" : "recorded");
    return MIR_NONE;
  }
  const MirTy ty = fn_type(fn, checked);
  const MirTyData *data = mir_ty_data(fn->cx->module, ty);
  if (data->kind == MK_OPT && (ref == NULL || ref->kind == MS_REF_NONE || ref->kind == MS_REF_CASE)) {
    return fn_emit(fn, MOP_OptNone, NULL, 0, (MirImm){0}, ty); /* `none` */
  }
  if (data->kind == MK_ALT && ref != NULL && ref->kind == MS_REF_CASE) {
    const MirImm imm = {.tag = MI_CASE, .a = data->id, .b = ref->index};
    return fn_emit(fn, MOP_AltNew, NULL, 0, imm, ty); /* a case with no fields */
  }
  (void)fn_fail(fn, "a name does not refer to a parameter, a local or a function (at %u:%u, reference kind %d)", expr->pos.line, expr->pos.column,
                ref != NULL ? (int)ref->kind : -1);
  return MIR_NONE;
}

static MirValue lower_name(LowerFn *fn, const MsExpr *expr) {
  return fn_name_ref(fn, expr, ms_facts_ref(fn->facts, expr->id));
}

/* `value.field`: a field of a record, read from the value in place. */
static MirValue lower_member(LowerFn *fn, const MsExpr *expr) {
  const MsRef *ref = ms_facts_ref(fn->facts, expr->id);
  if (ref != NULL && ref->kind == MS_REF_CASE) {
    return fn_name_ref(fn, expr, ref); /* `Type.Case`, a case with no fields */
  }
  if (ref != NULL && (ref->kind == MS_REF_METHOD || ref->kind == MS_REF_NATIVE || ref->kind == MS_REF_OPERATION)) {
    return fn_bound_method(fn, expr, ref); /* `value.method`, a method used as a value */
  }
  if (ref == NULL || ref->kind != MS_REF_FIELD) {
    (void)fn_fail(fn, "this member is not a record field (reference kind %d at %u:%u)", ref == NULL ? -1 : (int)ref->kind,
                  expr->pos.line, expr->pos.column);
    return MIR_NONE;
  }
  const MirValue read = fn_expr(fn, expr->u.member.left, LW_BORROW);
  if (read == MIR_NONE) {
    return MIR_NONE;
  }
  const MirValue base = fn_closing_base(fn, expr, read);
  const MirTyData *data = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, base));
  if (data->kind != MK_TYPE) {
    (void)fn_fail(fn, "a field is read from a record (found MIR kind %d)", (int)data->kind);
    return MIR_NONE;
  }
  const MirImm imm = {.tag = MI_FIELD, .a = data->id, .b = ref->index};
  return fn_emit(fn, MOP_TypeGet, &base, 1, imm, fn_type(fn, ms_facts_type(fn->facts, expr->id)));
}

typedef struct BinaryOps {
  MirOp op;
  MirCc cc;
  bool compare;
} BinaryOps;

static bool binary_ops(MsBinaryOp op, BinaryOps *out) {
  switch (op) {
    case MS_B_ADD: *out = (BinaryOps){MOP_IAddChk, MCC_EQ, false}; return true;
    case MS_B_SUB: *out = (BinaryOps){MOP_ISubChk, MCC_EQ, false}; return true;
    case MS_B_MUL: *out = (BinaryOps){MOP_IMulChk, MCC_EQ, false}; return true;
    case MS_B_DIV: *out = (BinaryOps){MOP_SDivChk, MCC_EQ, false}; return true;
    case MS_B_REM: *out = (BinaryOps){MOP_SRemChk, MCC_EQ, false}; return true;
    case MS_B_EQ: *out = (BinaryOps){MOP_ICmp, MCC_EQ, true}; return true;
    case MS_B_NE: *out = (BinaryOps){MOP_ICmp, MCC_NE, true}; return true;
    case MS_B_LT: *out = (BinaryOps){MOP_ICmp, MCC_LT, true}; return true;
    case MS_B_GT: *out = (BinaryOps){MOP_ICmp, MCC_GT, true}; return true;
    case MS_B_LE: *out = (BinaryOps){MOP_ICmp, MCC_LE, true}; return true;
    case MS_B_GE: *out = (BinaryOps){MOP_ICmp, MCC_GE, true}; return true;
    default: return false;
  }
}

/* A Float operation. A Float32 is held in a double register, so its result is rounded back to single. */
static MirValue float_binary(LowerFn *fn, const BinaryOps *ops, MirValue left, MirValue right, MirTy ty) {
  const MirValue operands[2] = {left, right};
  if (ops->compare) {
    const MirImm cc = {.tag = MI_CC, .a = (uint32_t)ops->cc};
    return fn_emit(fn, MOP_FCmp, operands, 2, cc, MIR_BOOL);
  }
  MirOp op = MOP_FAdd;
  if (ops->op == MOP_ISubChk) {
    op = MOP_FSub;
  } else if (ops->op == MOP_IMulChk) {
    op = MOP_FMul;
  } else if (ops->op == MOP_SDivChk) {
    op = MOP_FDiv;
  } else if (ops->op != MOP_IAddChk) {
    (void)fn_fail(fn, "this operator is not defined on Float");
    return MIR_NONE;
  }
  const MirValue result = fn_emit(fn, op, operands, 2, (MirImm){0}, ty);
  return ty == MIR_FLOAT32 ? fn_emit(fn, MOP_F32Round, &result, 1, (MirImm){0}, ty) : result;
}

/* `left && right` and `left || right`: the right operand runs only when the left does not decide the result. */
static MirValue lower_logical(LowerFn *fn, const MsExpr *expr) {
  const bool is_and = expr->op == MS_B_AND;
  const MirValue left = fn_expr(fn, expr->u.bin.left, LW_BORROW);
  if (left == MIR_NONE) {
    return MIR_NONE;
  }
  const MirBlock rhs = mir_b_new_block(&fn->b);
  const MirBlock decided = mir_b_new_block(&fn->b);
  const MirBlock join = mir_b_new_block(&fn->b);
  const MirValue result = mir_b_add_block_param(&fn->b, join, MIR_BOOL, MM_BORROW);
  mir_b_br_if(&fn->b, left, is_and ? rhs : decided, NULL, 0, is_and ? decided : rhs, NULL, 0);
  mir_b_seal_block(&fn->b, rhs);
  mir_b_seal_block(&fn->b, decided);
  mir_b_switch_to(&fn->b, decided);
  const MirValue known = mir_b_bconst(&fn->b, !is_and);
  mir_b_br(&fn->b, join, &known, 1);
  mir_b_switch_to(&fn->b, rhs);
  (void)fn_scope_begin(fn);
  const MirValue right = fn_expr(fn, expr->u.bin.right, LW_BORROW);
  fn_scope_end(fn);
  if (right == MIR_NONE) {
    return MIR_NONE;
  }
  mir_b_br(&fn->b, join, &right, 1);
  mir_b_seal_block(&fn->b, join);
  mir_b_switch_to(&fn->b, join);
  return result;
}

/* A UInt64 operation: the checked forms fault when the result leaves the range, and ordering is unsigned. */
static MirValue unsigned_binary(LowerFn *fn, const BinaryOps *ops, MirValue left, MirValue right) {
  const MirValue operands[2] = {left, right};
  if (ops->compare) {
    const MirImm cc = {.tag = MI_CC, .a = (uint32_t)ops->cc};
    return fn_emit(fn, MOP_UICmp, operands, 2, cc, MIR_BOOL);
  }
  MirOp op = MOP_UAddChk;
  if (ops->op == MOP_ISubChk) {
    op = MOP_USubChk;
  } else if (ops->op == MOP_IMulChk) {
    op = MOP_UMulChk;
  } else if (ops->op == MOP_SDivChk) {
    op = MOP_UDivChk;
  } else if (ops->op == MOP_SRemChk) {
    op = MOP_URemChk;
  } else if (ops->op != MOP_IAddChk) {
    (void)fn_fail(fn, "this operator is not lowered for UInt64 yet");
    return MIR_NONE;
  }
  return fn_emit(fn, op, operands, 2, (MirImm){0}, MIR_UINT64);
}

/* `left == right`, `left < right` and the rest on two Strings: the runtime compares their bytes. */
static MirValue string_compare(LowerFn *fn, MirCc cc, MirValue left, MirValue right) {
  const MirValue operands[2] = {left, right};
  if (cc == MCC_EQ || cc == MCC_NE) {
    const MirValue same = fn_runtime_call(fn, mir_name(fn->cx->module, ms_span_of_text("msrt_string_eq")), operands, 2, MIR_BOOL);
    return cc == MCC_EQ || same == MIR_NONE ? same : mir_b_icmp(&fn->b, MCC_EQ, same, mir_b_bconst(&fn->b, false));
  }
  const MirValue order = fn_runtime_call(fn, mir_name(fn->cx->module, ms_span_of_text("msrt_string_compare")), operands, 2, MIR_INT);
  return order == MIR_NONE ? order : mir_b_icmp(&fn->b, cc, order, mir_b_iconst(&fn->b, 0));
}

/* The operator `op` over two values of one standard type: strings by the runtime, value objects by their operation
 * word, Floats and UInt64 by their own instructions, everything else as integers. */
static bool is_structural(const LowerFn *fn, MirTy ty) {
  const MirTyKind kind = mir_ty_data(fn->cx->module, ty)->kind;
  return kind == MK_LIST || kind == MK_BYTES || kind == MK_OPT || kind == MK_TYPE || kind == MK_ALT;
}

/* `a == b` on a list, bytes, an optional, a record or an alternative: the runtime compares the two by the type's descriptor. */
static MirValue structural_equality(LowerFn *fn, bool negate, MirValue left, MirValue right, MirTy ty) {
  const MirImm of_type = {.tag = MI_TY, .a = ty};
  const MirValue desc = mir_b_emit(&fn->b, MOP_TypeDesc, NULL, 0, of_type, MIR_PTR);
  const MirValue left_slot = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, of_type, MIR_PTR);
  const MirValue right_slot = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, of_type, MIR_PTR);
  const MirValue left_stored[2] = {left_slot, left};
  const MirValue right_stored[2] = {right_slot, right};
  (void)mir_b_emit(&fn->b, MOP_Store, left_stored, 2, (MirImm){0}, MIR_NONE);
  (void)mir_b_emit(&fn->b, MOP_Store, right_stored, 2, (MirImm){0}, MIR_NONE);
  const MirValue operands[3] = {desc, left_slot, right_slot};
  const MirValue same = fn_runtime_call(fn, mir_name(fn->cx->module, ms_span_of_text("msrt_slot_eq")), operands, 3, MIR_BOOL);
  return negate ? mir_b_emit(&fn->b, MOP_Not, &same, 1, (MirImm){0}, MIR_BOOL) : same;
}

/* `a == b` on two optionals: both absent, or both present with equal payloads. The payloads compare by the
 * same rules as any two values, and padding bytes never take part. */
static MirValue optional_equality(LowerFn *fn, bool negate, MirValue left, MirValue right) {
  const MirValue left_some = mir_b_emit(&fn->b, MOP_OptIsSome, &left, 1, (MirImm){0}, MIR_BOOL);
  const MirValue right_some = mir_b_emit(&fn->b, MOP_OptIsSome, &right, 1, (MirImm){0}, MIR_BOOL);
  const MirBlock both = mir_b_new_block(&fn->b);
  const MirBlock differ = mir_b_new_block(&fn->b);
  const MirBlock present = mir_b_new_block(&fn->b);
  const MirBlock absent = mir_b_new_block(&fn->b);
  const MirBlock join = mir_b_new_block(&fn->b);
  const MirValue result = mir_b_add_block_param(&fn->b, join, MIR_BOOL, MM_BORROW);
  const MirValue agree = mir_b_icmp(&fn->b, MCC_EQ, left_some, right_some);
  mir_b_br_if(&fn->b, agree, both, NULL, 0, differ, NULL, 0);
  mir_b_seal_block(&fn->b, both);
  mir_b_seal_block(&fn->b, differ);
  mir_b_switch_to(&fn->b, both);
  mir_b_br_if(&fn->b, left_some, present, NULL, 0, absent, NULL, 0);
  mir_b_seal_block(&fn->b, present);
  mir_b_seal_block(&fn->b, absent);
  mir_b_switch_to(&fn->b, present);
  const MirTy payload = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, left))->elem;
  const MirValue left_value = mir_b_emit(&fn->b, MOP_OptGet, &left, 1, (MirImm){0}, payload);
  const MirValue right_value = mir_b_emit(&fn->b, MOP_OptGet, &right, 1, (MirImm){0}, payload);
  const MirValue same = fn_compare_values(fn, MS_B_EQ, left_value, right_value);
  mir_b_br(&fn->b, join, &same, 1);
  mir_b_switch_to(&fn->b, absent);
  const MirValue yes = mir_b_bconst(&fn->b, true);
  mir_b_br(&fn->b, join, &yes, 1);
  mir_b_switch_to(&fn->b, differ);
  const MirValue no = mir_b_bconst(&fn->b, false);
  mir_b_br(&fn->b, join, &no, 1);
  mir_b_seal_block(&fn->b, join);
  mir_b_switch_to(&fn->b, join);
  return negate ? mir_b_emit(&fn->b, MOP_Not, &result, 1, (MirImm){0}, MIR_BOOL) : result;
}

/* `a == b` on two records: every field equal, field by field, so padding bytes never take part. */
static MirValue record_equality(LowerFn *fn, bool negate, MirValue left, MirValue right, MirTy ty) {
  const MirTypeDef *def = &fn->cx->module->type_defs.ptr[mir_ty_data(fn->cx->module, ty)->id];
  MirValue all = mir_b_bconst(&fn->b, true);
  for (uint32_t field = 0; field < def->nfields; field++) {
    const MirImm imm = {.tag = MI_FIELD, .a = mir_ty_data(fn->cx->module, ty)->id, .b = field};
    const MirTy field_ty = def->fields[field].ty;
    const MirValue l = mir_b_emit(&fn->b, MOP_TypeGet, &left, 1, imm, field_ty);
    const MirValue r = mir_b_emit(&fn->b, MOP_TypeGet, &right, 1, imm, field_ty);
    const MirValue same = fn_compare_values(fn, MS_B_EQ, l, r);
    if (same == MIR_NONE) {
      return MIR_NONE;
    }
    const MirValue pair[2] = {all, same};
    all = mir_b_emit(&fn->b, MOP_And, pair, 2, (MirImm){0}, MIR_BOOL);
  }
  return negate ? mir_b_emit(&fn->b, MOP_Not, &all, 1, (MirImm){0}, MIR_BOOL) : all;
}

MirValue fn_compare_values(LowerFn *fn, MsBinaryOp op, MirValue left, MirValue right) {
  BinaryOps ops;
  if (!binary_ops(op, &ops)) {
    (void)fn_fail(fn, "this binary operator is not lowered yet");
    return MIR_NONE;
  }
  if (ops.compare && mir_b_ty(&fn->b, left) == MIR_STR) {
    return string_compare(fn, ops.cc, left, right);
  }
  MirValue object;
  if (fn_object_binary(fn, op, left, right, &object)) {
    return object;
  }
  const MirTy operand = mir_b_ty(&fn->b, left);
  const bool equality = ops.compare && (op == MS_B_EQ || op == MS_B_NE);
  if (equality && mir_ty_data(fn->cx->module, operand)->kind == MK_OPT) {
    return optional_equality(fn, op == MS_B_NE, left, right);
  }
  if (equality && mir_ty_data(fn->cx->module, operand)->kind == MK_TYPE) {
    return record_equality(fn, op == MS_B_NE, left, right, operand);
  }
  if (equality && is_structural(fn, operand)) {
    return structural_equality(fn, op == MS_B_NE, left, right, operand);
  }
  if (operand == MIR_FLOAT || operand == MIR_FLOAT32) {
    return float_binary(fn, &ops, left, right, operand);
  }
  if (operand == MIR_UINT64) {
    return unsigned_binary(fn, &ops, left, right);
  }
  return ops.compare ? mir_b_icmp(&fn->b, ops.cc, left, right) : mir_b_binop(&fn->b, ops.op, left, right);
}

static MirValue lower_binary(LowerFn *fn, const MsExpr *expr) {
  if (expr->op == MS_B_AND || expr->op == MS_B_OR) {
    return lower_logical(fn, expr);
  }
  BinaryOps ops;
  if (!binary_ops((MsBinaryOp)expr->op, &ops)) {
    (void)fn_fail(fn, "this binary operator is not lowered yet");
    return MIR_NONE;
  }
  const MirValue left = fn_expr(fn, expr->u.bin.left, LW_BORROW);
  const MirValue right = fn_expr(fn, expr->u.bin.right, LW_BORROW);
  if (left == MIR_NONE || right == MIR_NONE) {
    return MIR_NONE;
  }
  if (expr->op == MS_B_ADD && mir_b_ty(&fn->b, left) == MIR_STR) {
    const MirValue operands[2] = {left, right};
    return fn_runtime_call(fn, mir_name(fn->cx->module, ms_span_of_text("msrt_string_concat")), operands, 2, MIR_STR);
  }
  return fn_compare_values(fn, (MsBinaryOp)expr->op, left, right);
}

static MirValue expr_value(LowerFn *fn, const MsExpr *expr, LowerWant want) {
  switch ((MsExprKind)expr->kind) {
    case MS_E_NUMBER: return lower_number(fn, expr);
    case MS_E_BOOL: return mir_b_bconst(&fn->b, expr->u.flag);
    case MS_E_VOID: return mir_b_unit(&fn->b);
    case MS_E_TEXT: return lower_text(fn, expr);
    case MS_E_NAME: return lower_name(fn, expr);
    case MS_E_MEMBER: return lower_member(fn, expr);
    case MS_E_MAP: return fn_map_literal(fn, expr);
    case MS_E_BINARY: return lower_binary(fn, expr);
    case MS_E_CALL: return fn_call(fn, expr, want);
    case MS_E_MATCH: return fn_match(fn, expr);
    case MS_E_LIST: return fn_list(fn, expr);
    case MS_E_INDEX:
    case MS_E_APPLY: {
      const MsRef *named = expr->kind == MS_E_APPLY && expr->u.apply.types.len != 0 ? ms_facts_ref(fn->facts, expr->id) : NULL;
      return named != NULL && named->kind == MS_REF_FUNCTION ? fn_function_value(fn, expr, named) : fn_index(fn, expr, want);
    }
    case MS_E_LAMBDA: return fn_lambda(fn, expr);
    case MS_E_UNARY: return fn_unary(fn, expr, want);
    default:
      (void)fn_fail(fn, "this expression (kind %d) is not lowered yet at %u:%u", (int)expr->kind, expr->pos.line, expr->pos.column);
      return MIR_NONE;
  }
}

/* A name or field read where the consumer takes ownership: the value stays with its binding unless the use moves
 * it, so the consumer gets a copy. */
static MirValue take_ownership(LowerFn *fn, const MsExpr *expr, MirValue value, LowerWant want) {
  MirValue taken = MIR_NONE;
  if (want == LW_MOVE && value != MIR_NONE && fn_is_text_literal(expr)) {
    /* A literal is static, so what owns it holds a copy. */
    return fn_emit(fn, MOP_Clone, &value, 1, (MirImm){0}, mir_b_ty(&fn->b, value));
  }
  if (want == LW_MOVE && expr->kind == MS_E_NAME && value != MIR_NONE && fn_closing_move(fn, expr, value, &taken)) {
    return taken;
  }
  const bool place = expr->kind == MS_E_NAME || expr->kind == MS_E_MEMBER;
  if (want != LW_MOVE || !place || value == MIR_NONE || !mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, value))) {
    return value;
  }
  /* A parameter taken by borrow is never the callee's to give away. */
  const MsRef *ref = ms_facts_ref(fn->facts, expr->id);
  const bool borrowed_param = ref != NULL && ref->kind == MS_REF_PARAM && ref->local < fn->b.func.nparams &&
                              fn->b.func.params[ref->local].mode != MM_MOVE;
  if (!borrowed_param && ms_facts_use(fn->facts, expr->id) == MS_USE_MOVE) {
    return value;
  }
  const MirImm none = {0};
  return fn_emit(fn, MOP_Clone, &value, 1, none, mir_b_ty(&fn->b, value));
}

MirValue fn_expr(LowerFn *fn, const MsExpr *expr, LowerWant want) {
  const MirValue value = take_ownership(fn, expr, expr_value(fn, expr, want), want);
  return fn_convert(fn, expr, value);
}

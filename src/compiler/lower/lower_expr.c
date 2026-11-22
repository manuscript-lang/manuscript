/* compiler/lower/lower_expr.c: expressions: literals, names, arithmetic and comparison. */
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_analysis.h"

/* The value of a number spelling: decimal digits with `_` separators. */
static bool number_value(MsSpan text, int64_t *out) {
  int64_t value = 0;
  for (size_t index = 0; index < text.len; index++) {
    const uint8_t byte = (uint8_t)text.ptr[index];
    if (byte == '_') {
      continue;
    }
    if (byte < '0' || byte > '9' || value > (INT64_MAX - (int64_t)(byte - '0')) / 10) {
      return false;
    }
    value = value * 10 + (int64_t)(byte - '0');
  }
  *out = value;
  return true;
}

static MirValue lower_number(LowerFn *fn, const MsExpr *expr) {
  int64_t value = 0;
  if (!number_value(ms_names_span(fn->cx->program->names, expr->u.sym), &value)) {
    (void)fn_fail(fn, "a number literal is not a whole number that fits Int");
    return MIR_NONE;
  }
  return mir_b_iconst(&fn->b, value);
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
MirValue fn_name_ref(LowerFn *fn, const MsExpr *expr, const MsRef *ref) {
  MirValue captured = MIR_NONE;
  if (fn_lambda_name(fn, expr, ref, &captured)) {
    return captured;
  }
  if (ref != NULL && ref->kind == MS_REF_PARAM) {
    return mir_b_use_var(&fn->b, fn->param_vars[ref->local]);
  }
  if (ref != NULL && ref->kind == MS_REF_LOCAL && ref->local < fn->nvars && fn->vars[ref->local] != 0) {
    return mir_b_use_var(&fn->b, fn->vars[ref->local] - 1);
  }
  if (ref != NULL && ref->kind == MS_REF_FUNCTION) {
    return fn_function_value(fn, ref, fn_type(fn, ms_facts_type(fn->facts, expr->id)));
  }
  (void)fn_fail(fn, "a name does not refer to a parameter, a local or a function");
  return MIR_NONE;
}

static MirValue lower_name(LowerFn *fn, const MsExpr *expr) {
  return fn_name_ref(fn, expr, ms_facts_ref(fn->facts, expr->id));
}

/* `value.field`: a field of a record, read from the value in place. */
static MirValue lower_member(LowerFn *fn, const MsExpr *expr) {
  const MsRef *ref = ms_facts_ref(fn->facts, expr->id);
  if (ref == NULL || ref->kind != MS_REF_FIELD) {
    (void)fn_fail(fn, "this member is not a record field");
    return MIR_NONE;
  }
  const MirValue base = fn_expr(fn, expr->u.member.left, LW_BORROW);
  if (base == MIR_NONE) {
    return MIR_NONE;
  }
  const MirTyData *data = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, base));
  if (data->kind != MK_TYPE) {
    (void)fn_fail(fn, "a field is read from a record");
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

static MirValue lower_binary(LowerFn *fn, const MsExpr *expr) {
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
  return ops.compare ? mir_b_icmp(&fn->b, ops.cc, left, right) : mir_b_binop(&fn->b, ops.op, left, right);
}

static MirValue expr_value(LowerFn *fn, const MsExpr *expr, LowerWant want) {
  mir_b_set_loc(&fn->b, fn_loc(fn, expr->pos));
  switch ((MsExprKind)expr->kind) {
    case MS_E_NUMBER: return lower_number(fn, expr);
    case MS_E_BOOL: return mir_b_bconst(&fn->b, expr->u.flag);
    case MS_E_VOID: return mir_b_unit(&fn->b);
    case MS_E_TEXT: return lower_text(fn, expr);
    case MS_E_NAME: return lower_name(fn, expr);
    case MS_E_MEMBER: return lower_member(fn, expr);
    case MS_E_BINARY: return lower_binary(fn, expr);
    case MS_E_CALL: return fn_call(fn, expr, want);
    case MS_E_MATCH: return fn_match(fn, expr);
    case MS_E_LIST: return fn_list(fn, expr);
    case MS_E_LAMBDA: return fn_lambda(fn, expr);
    case MS_E_UNARY: return fn_unary(fn, expr);
    default:
      (void)fn_fail(fn, "this expression is not lowered yet");
      return MIR_NONE;
  }
}

/* A name or field read where the consumer takes ownership: the value stays with its binding unless the use moves
 * it, so the consumer gets a copy. */
static MirValue take_ownership(LowerFn *fn, const MsExpr *expr, MirValue value, LowerWant want) {
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

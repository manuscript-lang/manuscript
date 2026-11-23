/* compiler/lower/lower_expr.c: expressions: literals, names, arithmetic and comparison. */
#include "base/float_parse.h"
#include "compiler/lower/lower_fn.h"
#include <stdlib.h>
#include "compiler/mir/mir_analysis.h"
#include "compiler/syntax/walk.h"
#include "compiler/own/result_borrows.h"
#include "compiler/check/properties.h"

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
  MsStrBuild digits = ms_strbuild_new(); /* `_` separators are not part of the number */
  for (size_t at = 0; at < text.len; at++) {
    if (text.ptr[at] != '_') {
      ms_strbuild_append_byte(&digits, text.ptr[at]);
    }
  }
  bool fits = ms_parse_float(ms_strbuild_span(&digits), &value) == MS_PARSE_FLOAT_OK;
  if (fits && ty == MIR_FLOAT32) {
    /* A Float32 literal rounds once, from its decimal text: rounding the Float first can land on the wrong neighbour. */
    char buffer[128];
    const MsSpan written = ms_strbuild_span(&digits);
    fits = written.len < sizeof buffer;
    if (fits) {
      __builtin_memcpy(buffer, written.ptr, written.len);
      buffer[written.len] = '\0';
      value = (double)strtof(buffer, NULL);
    }
  }
  ms_strbuild_free(&digits);
  if (!fits) {
    (void)fn_fail(fn, "a number literal is not a Float that fits");
    return MIR_NONE;
  }
  if (ty == MIR_FLOAT32) {
    value = (double)(float)value; /* a Float32 literal is the nearest single, kept widened in a double */
  }
  MirImm imm = {.tag = MI_FLOAT};
  __builtin_memcpy(&imm.i, &value, sizeof value);
  return fn_emit(fn, MOP_FConst, NULL, 0, imm, ty);
}

/* A `d` literal: the runtime parses its text (without the suffix) into a slot of the Decimal, which is then read. */
static MirValue lower_decimal(LowerFn *fn, MsSpan text, MirTy ty) {
  MsStrBuild digits = ms_strbuild_new();
  for (size_t at = 0; at < text.len; at++) {
    const uint8_t byte = text.ptr[at];
    if (byte != '_' && !(at + 1 == text.len && (byte == 'd' || byte == 'D'))) {
      ms_strbuild_append_byte(&digits, byte);
    }
  }
  const MirImm literal_imm = {.tag = MI_STR, .a = mir_add_string(fn->cx->module, ms_strbuild_span(&digits))};
  ms_strbuild_free(&digits);
  const MirValue literal = fn_emit(fn, MOP_StrLit, NULL, 0, literal_imm, MIR_STR);
  const MirImm of_type = {.tag = MI_TY, .a = ty};
  const MirValue slot = fn_emit(fn, MOP_Slot, NULL, 0, of_type, MIR_PTR);
  MirParam *params = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, MirParam, 2);
  params[0] = (MirParam){MIR_STR, (uint8_t)MM_BORROW};
  params[1] = (MirParam){MIR_PTR, (uint8_t)MM_BORROW};
  const MirExtern def = {.name = mir_name(fn->cx->module, ms_span_of_text("msstd_decimal_parse")),
                         .params = params, .nparams = 2, .ret = MIR_UINT8};
  const MirValue args[2] = {literal, slot};
  (void)mir_b_call_rt(&fn->b, mir_extern_intern(fn->cx->module, &def), args, 2);
  return fn_emit(fn, MOP_Load, &slot, 1, of_type, ty);
}

static MirValue lower_number(LowerFn *fn, const MsExpr *expr) {
  const MsSpan text = ms_names_span(fn->cx->program->names, expr->u.sym);
  const MirTy ty = fn_type(fn, ms_facts_type(fn->facts, expr->id));
  if (text.len > 0 && (text.ptr[text.len - 1] == 'd' || text.ptr[text.len - 1] == 'D') &&
      !mir_is_scalar(fn->cx->module, ty)) {
    return lower_decimal(fn, text, ty);
  }
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
  return fn_emit(fn, MOP_StrLit, NULL, 0, imm, MIR_STR); /* a text literal is a String, whether or not the checker typed it (a match arm's path) */
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

/* The position, among the call's arguments, of the callee parameter `ref` a default argument names: the checker numbers a
 * method's parameters after its receiver, as the call's arguments are. */
static uint32_t default_position(const LowerFn *fn, const MsRef *ref) {
  return fn->default_has_self && ref->local > 0 ? ref->local - 1 : ref->local;
}

bool fn_default_var_slot(const LowerFn *fn, const MsExpr *place, MirValue *slot) {
  const MsRef *ref = fn->default_call != NULL && place->kind == MS_E_NAME ? ms_facts_ref(fn->facts, place->id) : NULL;
  if (ref == NULL || ref->kind != MS_REF_PARAM) {
    return false;
  }
  const uint32_t at = default_position(fn, ref);
  if (at >= fn->default_call->arg_count || (fn->default_call->args[at].flags & MS_PARAM_VAR) == 0) {
    return false;
  }
  *slot = fn->default_args[at];
  return *slot != MIR_NONE;
}

/* A parameter named by a default argument: the value the call passes for it, which must already be known. A `var`
 * parameter is read from the slot the callee changes it in. */
static MirValue default_param(LowerFn *fn, const MsRef *ref) {
  const MsCall *call = fn->default_call;
  if (fn->default_has_self && ref->local == 0) {
    return fn->default_self; /* `self` in the default of a method called through a method value */
  }
  const uint32_t at = default_position(fn, ref);
  if (at >= call->arg_count) {
    (void)fn_fail(fn, "a default argument reads a parameter that has no value yet");
    return MIR_NONE;
  }
  const MirValue value = fn->default_args[at];
  if (value == MIR_NONE) {
    (void)fn_fail(fn, "a default argument reads a parameter that has no value yet");
    return MIR_NONE;
  }
  if ((call->args[at].flags & MS_PARAM_VAR) != 0) {
    const MsTyTable *types = &fn->cx->program->types;
    const MirTy ty = fn_type(fn, ms_ty_params(types, call->callee_ty)[default_position(fn, ref)].ty);
    return mir_b_emit(&fn->b, MOP_Load, &value, 1, (MirImm){.tag = MI_TY, .a = ty}, ty);
  }
  return value;
}

MirValue fn_name_ref(LowerFn *fn, const MsExpr *expr, const MsRef *ref) {
  MirValue captured = MIR_NONE;
  if (fn_lambda_name(fn, expr, ref, &captured)) {
    return captured;
  }
  if (fn_closing_read(fn, ref, expr != NULL && expr->kind == MS_E_NAME ? expr->u.sym : 0, &captured)) {
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
    return fn_emit(fn, MOP_OptNone, NULL, 0, (MirImm){0}, ty); /* `none`: owned only where taken, below */
  }
  if (data->kind == MK_ALT && ref != NULL && ref->kind == MS_REF_CASE) {
    const MirImm imm = {.tag = MI_CASE, .a = data->id, .b = ref->index};
    return fn_emit(fn, MOP_AltNew, NULL, 0, imm, ty); /* a case with no fields */
  }
  (void)fn_fail(fn, "a name does not refer to a parameter, a local or a function (at %u:%u, reference kind %d)", expr->pos.line, expr->pos.column,
                ref != NULL ? (int)ref->kind : -1);
  return MIR_NONE;
}

/* `__LINE__` and `__FILE__`: the position of the name itself, and the file it is written in. */
static MirValue source_constant(LowerFn *fn, const MsExpr *expr) {
  const MsSpan text = ms_names_span(fn->cx->program->names, expr->u.sym);
  if (ms_span_is_text(text, "__LINE__")) {
    return mir_b_iconst(&fn->b, (int64_t)expr->pos.line);
  }
  if (!ms_span_is_text(text, "__FILE__")) {
    return MIR_NONE;
  }
  const MsSpan file = ms_names_span(fn->cx->program->names, fn->cx->program->modules.ptr[fn->module_index].file);
  const MirImm imm = {.tag = MI_STR, .a = mir_add_string(fn->cx->module, file)};
  return fn_emit(fn, MOP_StrLit, NULL, 0, imm, MIR_STR);
}

static MirValue lower_name(LowerFn *fn, const MsExpr *expr) {
  const MsRef *named = ms_facts_ref(fn->facts, expr->id);
  if (named == NULL || named->kind == MS_REF_NONE) {
    const MirValue constant = source_constant(fn, expr);
    if (constant != MIR_NONE) {
      return constant;
    }
  }
  return fn_name_ref(fn, expr, ms_facts_ref(fn->facts, expr->id));
}

/* `self.value` in a method of a type set: `self` is the variable `Self`, so the checker knew no field. Once the call
 * binds `Self` to a member, the field is looked up by name in that member's record. */
static bool fn_late_field(LowerFn *fn, const MsExpr *expr, MsRef *out) {
  const MsTy left = ms_ty_subst(&fn->cx->program->types, ms_facts_type(fn->facts, expr->u.member.left->id), fn->subst.vars,
                                fn->subst.args, fn->subst.count);
  if (left == MS_TY_NONE || fn->subst.count == 0) {
    return false;
  }
  const MirTyData *data = mir_ty_data(fn->cx->module, fn_type(fn, left));
  if (data->kind != MK_TYPE) {
    return false;
  }
  const MirTypeDef *def = &fn->cx->module->type_defs.ptr[data->id];
  const MsSpan name = ms_names_span(fn->cx->program->names, expr->u.member.name);
  for (uint32_t index = 0; index < def->nfields; index++) {
    if (ms_span_equal(name, ms_names_span(&fn->cx->module->names, def->fields[index].name))) {
      out->kind = MS_REF_FIELD;
      out->index = index;
      return true;
    }
  }
  return false;
}

/* `value.field`: a field of a record, read from the value in place. */
static MirValue lower_member(LowerFn *fn, const MsExpr *expr) {
  const bool taking = fn->taking_member == expr;
  const MsRef *ref = ms_facts_ref(fn->facts, expr->id);
  if (ref != NULL && ref->kind == MS_REF_CASE) {
    return fn_name_ref(fn, expr, ref); /* `Type.Case`, a case with no fields */
  }
  if (ref != NULL && (ref->kind == MS_REF_METHOD || ref->kind == MS_REF_NATIVE || ref->kind == MS_REF_OPERATION)) {
    return fn_bound_method(fn, expr, ref, expr); /* `value.method`, a method used as a value */
  }
  MsRef late = {0};
  if ((ref == NULL || ref->kind == MS_REF_NONE) && fn_late_field(fn, expr, &late)) {
    ref = &late;
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
  const MirTy read_ty = late.kind == MS_REF_FIELD ? fn->cx->module->type_defs.ptr[data->id].fields[ref->index].ty
                                                   : fn_type(fn, ms_facts_type(fn->facts, expr->id));
  const MirValue field = fn_emit(fn, MOP_TypeGet, &base, 1, imm, read_ty);
  MirVar owner = 0;
  const bool taken_at_last = taking && ((fn->facts->last != NULL && fn->facts->last[expr->id] != 0) ||
                                        expr->u.member.left->kind == MS_E_CALL);
  const bool moves = (ms_facts_use(fn->facts, expr->id) == MS_USE_MOVE || taken_at_last) &&
                     mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, field));
  if (moves && fn_owned_local(fn, expr->u.member.left, &owner)) {
    fn_scope_var_moved(fn, owner, ref->index);
    /* The field leaves its owner: the value is the owner's no more, and the scope releases the rest. */
    return fn_emit(fn, MOP_MoveOut, &field, 1, (MirImm){0}, mir_b_ty(&fn->b, field));
  }
  const bool last_field = moves && expr->u.member.left->kind == MS_E_NAME && fn->facts->last != NULL &&
                          fn->facts->last[expr->id] != 0 && fn_fresh_owner(fn, base);
  if (moves && (expr->u.member.left->kind == MS_E_CALL || last_field) && fn_fresh_owner(fn, base)) {
    /* The field leaves a temporary that dies with the statement, or a name at its last use: the rest of the record is
     * released with it. */
    const MirTy field_ty = mir_b_ty(&fn->b, field);
    const MirValue taken = fn_emit(fn, MOP_MoveOut, &field, 1, (MirImm){0}, field_ty);
    const MirImm mask = {.tag = MI_TYPEMASK, .a = data->id, .b = ref->index < 32 ? UINT32_C(1) << ref->index : 0};
    (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &base, 1, (MirImm){0}, MIR_NONE);
    (void)mir_b_emit(&fn->b, MOP_TypeRelease, &base, 1, mask, MIR_NONE);
    return taken;
  }
  return field;
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
  const MirTyData *data = mir_ty_data(fn->cx->module, ty);
  return data->kind == MK_LIST || data->kind == MK_BYTES || data->kind == MK_OPT || data->kind == MK_TYPE ||
         data->kind == MK_ALT || (data->kind == MK_OBJ && data->obj_class == MIR_OBJ_COLLECTION);
}

/* `a == b` on a list, bytes, a map or set, an optional, a record or an alternative: the runtime compares the two by the type's descriptor. */
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
static MirValue record_fields_equal(LowerFn *fn, bool negate, MirValue left, MirValue right, MirTy ty) {
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

typedef MirValue (*FieldwiseEquality)(LowerFn *fn, bool negate, MirValue left, MirValue right, MirTy ty);

/* A record or alternative is compared field by field, once: a type that reaches itself (a list node) is compared by
 * the runtime through its descriptor where the walk meets it again. */
static MirValue compare_once(LowerFn *fn, bool negate, MirValue left, MirValue right, MirTy ty, FieldwiseEquality fieldwise) {
  for (uint32_t at = 0; at < fn->ncomparing; at++) {
    if (fn->comparing[at] == ty) {
      return structural_equality(fn, negate, left, right, ty);
    }
  }
  if (fn->ncomparing == sizeof fn->comparing / sizeof fn->comparing[0]) {
    return structural_equality(fn, negate, left, right, ty);
  }
  fn->comparing[fn->ncomparing++] = ty;
  const MirValue result = fieldwise(fn, negate, left, right, ty);
  fn->ncomparing--;
  return result;
}

static MirValue record_equality(LowerFn *fn, bool negate, MirValue left, MirValue right, MirTy ty) {
  return compare_once(fn, negate, left, right, ty, record_fields_equal);
}

/* `a == b` on two alternatives: the same case, then every field of it equal, so unused payload bytes never take
 * part (a runtime that compared the bytes would compare string pointers). */

static MirValue alt_equality_cases(LowerFn *fn, bool negate, MirValue left, MirValue right, MirTy ty) {
  const uint32_t id = mir_ty_data(fn->cx->module, ty)->id;
  const MirAltDef *alt = &fn->cx->module->alts.ptr[id];
  const MirValue left_tag = mir_b_emit(&fn->b, MOP_AltTag, &left, 1, (MirImm){0}, MIR_INT);
  const MirValue right_tag = mir_b_emit(&fn->b, MOP_AltTag, &right, 1, (MirImm){0}, MIR_INT);
  const MirBlock join = mir_b_new_block(&fn->b);
  const MirValue result = mir_b_add_block_param(&fn->b, join, MIR_BOOL, MM_BORROW);
  const MirBlock cases = mir_b_new_block(&fn->b);
  const MirBlock differ = mir_b_new_block(&fn->b);
  mir_b_br_if(&fn->b, mir_b_icmp(&fn->b, MCC_EQ, left_tag, right_tag), cases, NULL, 0, differ, NULL, 0);
  mir_b_seal_block(&fn->b, cases);
  mir_b_seal_block(&fn->b, differ);
  mir_b_switch_to(&fn->b, differ);
  const MirValue no = mir_b_bconst(&fn->b, false);
  mir_b_br(&fn->b, join, &no, 1);
  mir_b_switch_to(&fn->b, cases);
  for (uint32_t kase = 0; kase < alt->ncases; kase++) {
    const MirBlock here = mir_b_new_block(&fn->b);
    const MirBlock next = mir_b_new_block(&fn->b);
    mir_b_br_if(&fn->b, mir_b_icmp(&fn->b, MCC_EQ, left_tag, mir_b_iconst(&fn->b, kase)), here, NULL, 0, next, NULL, 0);
    mir_b_seal_block(&fn->b, here);
    mir_b_seal_block(&fn->b, next);
    mir_b_switch_to(&fn->b, here);
    MirValue all = mir_b_bconst(&fn->b, true);
    for (uint32_t at = 0; at < alt->cases[kase].nfields; at++) {
      const MirTy field_ty = alt->cases[kase].fields[at].ty;
      if (field_ty == MIR_VOID) {
        continue;
      }
      const MirImm imm = {.tag = MI_ALTFIELD, .a = id, .b = kase, .c = at};
      const MirValue l = mir_b_emit(&fn->b, MOP_AltGet, &left, 1, imm, field_ty);
      const MirValue r = mir_b_emit(&fn->b, MOP_AltGet, &right, 1, imm, field_ty);
      const MirValue same = fn_compare_values(fn, MS_B_EQ, l, r);
      if (same == MIR_NONE) {
        return MIR_NONE;
      }
      const MirValue pair[2] = {all, same};
      all = mir_b_emit(&fn->b, MOP_And, pair, 2, (MirImm){0}, MIR_BOOL);
    }
    mir_b_br(&fn->b, join, &all, 1);
    mir_b_switch_to(&fn->b, next);
  }
  const MirValue yes = mir_b_bconst(&fn->b, true);
  mir_b_br(&fn->b, join, &yes, 1);
  mir_b_seal_block(&fn->b, join);
  mir_b_switch_to(&fn->b, join);
  return negate ? mir_b_emit(&fn->b, MOP_Not, &result, 1, (MirImm){0}, MIR_BOOL) : result;
}

/* The equality of two alternatives, case by case. An alternative that holds itself (a tree) is written out once:
 * where its own equality is already being written, the comparison goes through the runtime's structural one. */
static MirValue alt_equality(LowerFn *fn, bool negate, MirValue left, MirValue right, MirTy ty) {
  return compare_once(fn, negate, left, right, ty, alt_equality_cases);
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
  if (equality && operand == MIR_VOID) { /* the unit has one value: any two are equal */
    return mir_b_bconst(&fn->b, op == MS_B_EQ);
  }
  if (equality && mir_ty_data(fn->cx->module, operand)->kind == MK_OPT) {
    return optional_equality(fn, op == MS_B_NE, left, right);
  }
  if (equality && mir_ty_data(fn->cx->module, operand)->kind == MK_TYPE) {
    return record_equality(fn, op == MS_B_NE, left, right, operand);
  }
  if (equality && mir_ty_data(fn->cx->module, operand)->kind == MK_ALT) {
    return alt_equality(fn, op == MS_B_NE, left, right, operand);
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
    return fn_string_concat(fn, left, right);
  }
  if (expr->op == MS_B_EQ || expr->op == MS_B_NE) {
    /* A type that declares its own `equals` compares through it. */
    const MsTy checked = lower_source_type(fn->cx, mir_b_ty(&fn->b, left));
    const uint32_t method = checked == MS_TY_NONE || mir_b_ty(&fn->b, left) != mir_b_ty(&fn->b, right)
                                ? MIR_NONE
                                : lower_own_method(fn->cx, checked, MS_PROPERTY_EQUAL);
    if (method != MIR_NONE) {
      const MirValue operands[2] = {left, right};
      const MirValue same = mir_b_call(&fn->b, method, operands, 2);
      return expr->op == MS_B_NE ? mir_b_emit(&fn->b, MOP_Not, &same, 1, (MirImm){0}, MIR_BOOL) : same;
    }
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
    case MS_E_MEMBER:
      fn->taking_member = want == LW_MOVE ? expr : NULL;
      return lower_member(fn, expr);
    case MS_E_MAP: return fn_map_literal(fn, expr);
    case MS_E_BINARY: return lower_binary(fn, expr);
    case MS_E_CALL: return fn_call(fn, expr, want);
    case MS_E_MATCH: return fn_match(fn, expr);
    case MS_E_LIST: return fn_list(fn, expr);
    case MS_E_INDEX:
    case MS_E_APPLY: {
      const MsRef *named = expr->kind == MS_E_APPLY && expr->u.apply.types.len != 0 ? ms_facts_ref(fn->facts, expr->id) : NULL;
      if (named != NULL && expr->u.apply.left->kind == MS_E_MEMBER &&
          (named->kind == MS_REF_METHOD || named->kind == MS_REF_NATIVE || named->kind == MS_REF_OPERATION)) {
        return fn_bound_method(fn, expr->u.apply.left, named, expr); /* `value.method[Args]`, instantiated */
      }
      return named != NULL && named->kind == MS_REF_FUNCTION ? fn_function_value(fn, expr, named) : fn_index(fn, expr, want);
    }
    case MS_E_LAMBDA: return fn_lambda(fn, expr);
    case MS_E_UNARY: return fn_unary(fn, expr, want);
    default:
      (void)fn_fail(fn, "this expression (kind %d) is not lowered yet at %u:%u", (int)expr->kind, expr->pos.line, expr->pos.column);
      return MIR_NONE;
  }
}

/* The callee's returns all name one parameter: the call answers that argument itself. */
typedef struct WholeReturn {
  const MsFacts *facts;
  uint32_t returns;
  uint32_t params; /* returns that name a parameter of the result type */
  uint32_t local;
  bool same;
  MsName payloads[8]; /* the names the arms of a match on the receiver bind */
  uint32_t npayloads;
  uint32_t payload_returns; /* returns that name one of them */
  const MsExpr *receiver; /* NULL until a match on it is found */
} WholeReturn;

static void note_payload_match(void *ctx, const MsExpr *expr) {
  WholeReturn *counts = ctx;
  if (expr->kind != MS_E_MATCH || expr->u.match.scrutinee->kind != MS_E_NAME) {
    return;
  }
  const MsRef *ref = ms_facts_ref(counts->facts, expr->u.match.scrutinee->id);
  if (ref == NULL || ref->kind != MS_REF_PARAM || ref->local != 0 || counts->receiver != NULL) {
    return;
  }
  counts->receiver = expr->u.match.scrutinee;
  for (uint32_t arm = 0; arm < expr->u.match.arms.len; arm++) {
    const MsArm *one = expr->u.match.arms.ptr[arm];
    for (uint32_t bound = 0; bound < one->bindings.len && counts->npayloads < 8; bound++) {
      counts->payloads[counts->npayloads++] = one->bindings.ptr[bound].name;
    }
  }
}

static void count_whole_returns(void *ctx, const MsStmt *stmt) {
  WholeReturn *counts = ctx;
  if (stmt->kind != MS_S_RETURN || stmt->u.expr == NULL) {
    return;
  }
  counts->returns++;
  const MsRef *ref = stmt->u.expr->kind == MS_E_NAME ? ms_facts_ref(counts->facts, stmt->u.expr->id) : NULL;
  if (ref != NULL && ref->kind == MS_REF_LOCAL) {
    for (uint32_t at = 0; at < counts->npayloads; at++) {
      counts->payload_returns += counts->payloads[at] == stmt->u.expr->u.sym ? 1u : 0u;
    }
  }
  if (ref == NULL || ref->kind != MS_REF_PARAM) {
    return;
  }
  counts->same = counts->params == 0 || counts->local == ref->local;
  counts->local = ref->local;
  counts->params++;
}

/* `var t = id(make())`, `make().get()`: a call that answers its dying temporary argument itself (`id`), or the payload
 * of a dying Optional or Result receiver (`get`), gives the new owner that temporary's value instead of a copy.
 * Returns the owned value, or MIR_NONE when the call answers something else. */
static bool leaves_binding(const LowerFn *fn, const MsExpr *expr);

MirValue fn_take_from_temporary(LowerFn *fn, const MsExpr *expr, MirValue value) {
  const MsCall *call = ms_facts_call(fn->facts, expr->id);
  if (call == NULL || (call->callee.kind != MS_REF_FUNCTION && call->callee.kind != MS_REF_METHOD)) {
    return MIR_NONE;
  }
  const MsFunc *callee = ms_own_find_func(fn->cx->program, &call->callee);
  if (callee == NULL || callee->bodiless || callee->external) {
    return MIR_NONE;
  }
  WholeReturn counts = {.facts = &fn->cx->program->modules.ptr[call->callee.decl.module].facts, .same = true};
  const MsVisitor visitor = {.ctx = &counts, .stmt = count_whole_returns, .expr = note_payload_match};
  ms_walk_block(&visitor, callee->body);
  const bool whole = counts.returns != 0 && counts.returns == counts.params && counts.same;
  const bool payload = counts.returns != 0 && counts.returns == counts.payload_returns && call->callee.kind == MS_REF_METHOD;
  const MirInstList *insts = &fn->b.func.blocks.ptr[fn->b.cur].insts;
  const MirInst *last = insts->len == 0 ? NULL : &insts->ptr[insts->len - 1];
  if (last == NULL || last->res != value) {
    return MIR_NONE;
  }
  const uint32_t position = whole ? counts.local + (call->callee.kind == MS_REF_METHOD ? 1u : 0u) : 0;
  if ((!whole && !payload) || position >= last->nargs) {
    return MIR_NONE;
  }
  /* A name read for the last time dies with the call too: its payload leaves it. */
  const MsExpr *dying = payload && !whole && fn_call_callee(expr)->kind == MS_E_MEMBER ? fn_call_callee(expr)->u.member.left : NULL;
  const MsRef *dying_ref = dying != NULL && dying->kind == MS_E_NAME ? ms_facts_ref(fn->facts, dying->id) : NULL;
  const bool name_dies = dying_ref != NULL && dying_ref->kind == MS_REF_LOCAL && leaves_binding(fn, dying);
  if (!name_dies && !fn_fresh_owner(fn, last->args[position])) {
    return MIR_NONE;
  }
  MirValue temporary = last->args[position];
  if (whole) {
    if (ms_check_holds_resource(fn->cx->program, ms_facts_type(fn->facts, expr->id)) ||
        mir_b_ty(&fn->b, temporary) != mir_b_ty(&fn->b, value)) {
      return MIR_NONE;
    }
    (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &temporary, 1, (MirImm){0}, MIR_NONE);
    return value;
  }
  const MsExpr *receiver = fn_call_callee(expr)->kind == MS_E_MEMBER ? fn_call_callee(expr)->u.member.left : NULL;
  const MsTyTable *types = &fn->cx->program->types;
  const MsTy held = receiver == NULL ? MS_TY_NONE : ms_facts_type(fn->facts, receiver->id);
  if (held == MS_TY_NONE || (!ms_ty_is(types, held, MS_BUILTIN_Optional) && !ms_ty_is(types, held, MS_BUILTIN_Result))) {
    return MIR_NONE;
  }
  if (ms_ty_args(types, held)[0] != ms_facts_type(fn->facts, expr->id)) {
    return MIR_NONE; /* not the success payload */
  }
  if (name_dies && !fn_fresh_owner(fn, temporary)) {
    temporary = fn_expr(fn, dying, LW_MOVE); /* the name hands its value on: its scope no longer releases it */
    if (temporary == MIR_NONE) {
      return MIR_NONE;
    }
  }
  MirTy ty = MIR_VOID;
  return fn_take_payload(fn, temporary, &ty);
}

/* Whether a read of `expr` leaves the binding: the checker's move, or an owner's last read (own/moves.c). */
static bool leaves_binding(const LowerFn *fn, const MsExpr *expr) {
  return ms_facts_use(fn->facts, expr->id) == MS_USE_MOVE ||
         (expr->kind == MS_E_NAME && fn->facts->last != NULL && expr->id < fn->facts->node_count && fn->facts->last[expr->id] != 0);
}

/* A field read at its record's last use, where the consumer takes ownership: it leaves the record. */
static bool field_leaves(const LowerFn *fn, const MsExpr *expr) {
  return expr->kind == MS_E_MEMBER && ((fn->facts->last != NULL && expr->id < fn->facts->node_count && fn->facts->last[expr->id] != 0) ||
                                       expr->u.member.left->kind == MS_E_CALL);
}

/* A name or field read where the consumer takes ownership: the value stays with its binding unless the use moves
 * it, so the consumer gets a copy. */
static MirValue take_ownership(LowerFn *fn, const MsExpr *expr, MirValue value, LowerWant want) {
  MirValue taken = MIR_NONE;
  if (want == LW_MOVE && value != MIR_NONE && fn_is_text_literal(expr)) {
    /* A literal is static, so what owns it holds a copy. */
    return fn_emit(fn, MOP_Clone, &value, 1, (MirImm){0}, mir_b_ty(&fn->b, value));
  }
  if (want == LW_MOVE && expr->kind == MS_E_NAME && value != MIR_NONE && leaves_binding(fn, expr) &&
      fn_closing_take(fn, ms_facts_ref(fn->facts, expr->id), value, &taken)) {
    return taken;
  }
  if (want == LW_MOVE && expr->kind == MS_E_CALL && value != MIR_NONE && fn_is_borrowed_view(fn, value) &&
      mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, value))) {
    const MirValue owned = fn_take_from_temporary(fn, expr, value);
    if (owned != MIR_NONE) {
      return owned;
    }
    /* A call that answers a view of something else (`list.get(i)`) gives its new owner a copy. */
    return fn_implicit_clone(fn, value, true);
  }
  const MsRef *name_ref = expr->kind == MS_E_NAME ? ms_facts_ref(fn->facts, expr->id) : NULL;
  /* `none` and a case name build a fresh value; only a binding, a parameter or a constant names storage. */
  const bool names_storage = name_ref != NULL && (name_ref->kind == MS_REF_LOCAL || name_ref->kind == MS_REF_PARAM ||
                                                  name_ref->kind == MS_REF_CONSTANT);
  /* `Color.Red` names a case, which builds a fresh value; a field read names storage. */
  const MsRef *member_ref = expr->kind == MS_E_MEMBER ? ms_facts_ref(fn->facts, expr->id) : NULL;
  const bool place = names_storage || (expr->kind == MS_E_MEMBER && (member_ref == NULL || member_ref->kind != MS_REF_CASE));
  if (want != LW_MOVE || !place || value == MIR_NONE || !mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, value))) {
    return value;
  }
  /* A parameter taken by borrow is never the callee's to give away. */
  const MsRef *ref = ms_facts_ref(fn->facts, expr->id);
  const uint32_t param_at = ref != NULL ? ref->local + (fn->lambda != NULL ? 1u : 0u) : 0; /* a closure's first parameter is its environment */
  MirVar param_var = 0;
  /* A `var` parameter the body owns while it runs (it is refilled before the caller sees it) may hand its value on. */
  const bool borrowed_param = ref != NULL && ref->kind == MS_REF_PARAM && param_at < fn->b.func.nparams &&
                              fn->b.func.params[param_at].mode != MM_MOVE &&
                              !(expr->kind == MS_E_NAME && fn_owned_local(fn, expr, &param_var));
  /* A field of a `var` binding stays in the record the binding puts back whole, so reading it as a move would free it
   * twice; it is copied. */
  MirVar root_var;
  const MsExpr *root = expr;
  while (root->kind == MS_E_MEMBER) {
    root = root->u.member.left;
  }
  const MsRef *root_ref = root->kind == MS_E_NAME ? ms_facts_ref(fn->facts, root->id) : NULL;
  const bool moved_param = root_ref != NULL && root_ref->kind == MS_REF_PARAM &&
                           root_ref->local + (fn->lambda != NULL ? 1u : 0u) < fn->b.func.nparams &&
                           fn->b.func.params[root_ref->local + (fn->lambda != NULL ? 1u : 0u)].mode == MM_MOVE;
  const bool in_var_record = expr->kind == MS_E_MEMBER && !moved_param && root->kind == MS_E_NAME &&
                             fn_owned_local(fn, root, &root_var);
  /* A field of a parameter taken by borrow is as much the caller's as the parameter. */
  const bool borrowed_root = expr->kind == MS_E_MEMBER && root_ref != NULL && root_ref->kind == MS_REF_PARAM && !moved_param &&
                             !in_var_record && root_ref->local + (fn->lambda != NULL ? 1u : 0u) < fn->b.func.nparams;
  /* A binding that only views another owner's value (a borrowed loop element, a name bound to a place) copies it. */
  const bool view_local = ref != NULL && ref->kind == MS_REF_LOCAL && expr->kind == MS_E_NAME && fn->local_owns != NULL &&
                          ref->local < fn->nvars && fn->local_owns[ref->local] == 2;
  if (in_var_record && fn->moving_field == expr && fn->nmoved_fields < 4 && !borrowed_param) {
    /* `old := self.f` followed by `self.f = g`: the field leaves the record and the assignment drops nothing. */
    fn->moved_fields[fn->nmoved_fields++] = expr;
    return fn_emit(fn, MOP_MoveOut, &value, 1, (MirImm){0}, mir_b_ty(&fn->b, value));
  }
  if (!borrowed_param && !borrowed_root && !in_var_record && !view_local && leaves_binding(fn, expr)) {
    if (expr->kind == MS_E_NAME && fn->nmoved_names < 8) {
      fn->moved_names[fn->nmoved_names++] = value;
    }
    return value;
  }
  if (expr->kind == MS_E_MEMBER && (ms_facts_use(fn->facts, expr->id) == MS_USE_MOVE || field_leaves(fn, expr)) &&
      fn_fresh_owner(fn, value)) {
    return value; /* the field was taken out of its record: nothing to copy */
  }
  return fn_implicit_clone(fn, value, true);
}

MirValue fn_expr(LowerFn *fn, const MsExpr *expr, LowerWant want) {
  for (uint32_t at = 0; at < fn->npresolved; at++) {
    if (fn->presolved[at].expr == expr) {
      return fn->presolved[at].value;
    }
  }
  const MirValue value = take_ownership(fn, expr, expr_value(fn, expr, want), want);
  return fn_convert(fn, expr, value);
}

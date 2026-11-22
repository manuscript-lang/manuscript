/* compiler/lower/lower_text.c: interpolated text. The pieces are evaluated left to right and joined by one
 * runtime call: `msrt_string_concatN`, or `msrt_string_fmtN` (a mask of the integer pieces first) when a piece is
 * an integer, which the join writes in decimal. At most six pieces go in one call; a longer text joins the
 * first group, then that result and the next pieces. */
#include "compiler/lower/lower_fn.h"
#include "compiler/lower/native_sigs.h"
#include "compiler/mir/mir_analysis.h"
#include "compiler/mir/mir_pass.h"

enum { TEXT_MAX_JOIN = 6 };

typedef struct TextPiece {
  MirValue value;
  bool is_int;
} TextPiece;

static MirValue call_join(LowerFn *fn, const char *prefix, uint32_t count, const MirTy *params, uint32_t nparams,
                          const MirValue *args, MirRole role) {
  MsStrBuild name = ms_strbuild_new();
  if (count == 0) {
    ms_strbuild_printf(&name, "%s", prefix);
  } else {
    ms_strbuild_printf(&name, "%s%u", prefix, count);
  }
  /* Each pattern of integer and string pieces is its own signature of the one runtime function. */
  MirParam *wanted = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, MirParam, (size_t)nparams + 1);
  for (uint32_t at = 0; at < nparams; at++) {
    wanted[at] = (MirParam){params[at], (uint8_t)MM_BORROW};
  }
  const MirExtern def = {.name = mir_name(fn->cx->module, ms_strbuild_span(&name)),
                         .params = wanted,
                         .nparams = nparams,
                         .ret = MIR_STR,
                         .fresh = true,
                         .leaf = true,
                         .role = (uint8_t)role};
  const uint32_t ext = mir_extern_intern(fn->cx->module, &def);
  ms_strbuild_free(&name);
  const MirValue result = mir_b_call_rt(&fn->b, ext, args, nparams);
  fn_own_result(fn, result);
  return result;
}

/* `left + right` on two Strings: the concat the string-growing pass recognises by its role. */
MirValue fn_string_concat(LowerFn *fn, MirValue left, MirValue right) {
  const MirTy params[2] = {MIR_STR, MIR_STR};
  const MirValue args[2] = {left, right};
  return call_join(fn, "msrt_string_concat", 0, params, 2, args, MR_STRING_CONCAT);
}

/* Joins up to six pieces. */
static MirValue join_group(LowerFn *fn, const TextPiece *group, uint32_t count) {
  MirTy params[TEXT_MAX_JOIN + 1];
  MirValue args[TEXT_MAX_JOIN + 1];
  uint32_t used = 0;
  int64_t mask = 0;
  bool ints = false;
  for (uint32_t index = 0; index < count; index++) {
    ints = ints || group[index].is_int;
    mask |= group[index].is_int ? (int64_t)1 << index : 0;
  }
  if (ints) {
    args[used] = mir_b_iconst(&fn->b, mask);
    params[used++] = MIR_INT;
  }
  for (uint32_t index = 0; index < count; index++) {
    args[used] = group[index].value;
    params[used++] = group[index].is_int ? MIR_INT : MIR_STR;
  }
  if (ints) {
    return call_join(fn, "msrt_string_fmt", count, params, used, args, MR_STRING_JOIN);
  }
  return call_join(fn, "msrt_string_concat", count == 2 ? 0 : count, params, used, args, MR_STRING_CONCAT);
}

static MirValue join_pieces(LowerFn *fn, const TextPiece *pieces, uint32_t count) {
  if (count == 1 && pieces[0].is_int) {
    const MirTy param = MIR_INT;
    return call_join(fn, "msrt_int_to_string", 0, &param, 1, &pieces[0].value, MR_INT_TO_STRING);
  }
  if (count == 1) {
    return pieces[0].value;
  }
  uint32_t taken = count < TEXT_MAX_JOIN ? count : TEXT_MAX_JOIN;
  MirValue joined = join_group(fn, pieces, taken);
  while (taken < count && joined != MIR_NONE) {
    TextPiece group[TEXT_MAX_JOIN] = {{joined, false}};
    uint32_t used = 1;
    while (used < TEXT_MAX_JOIN && taken < count) {
      group[used++] = pieces[taken++];
    }
    joined = join_group(fn, group, used);
  }
  return joined;
}

/* Any other value is written by the runtime's walker over the value's shape table: the value goes into a stack
 * slot (a borrow, so nothing is dropped) and the walker reads it through the table. */
static MirValue value_shown(LowerFn *fn, MirValue value, MirTy ty, const char *function) {
  const MirImm of_type = {.tag = MI_TY, .a = ty};
  const MirValue slot = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, of_type, MIR_PTR);
  const MirValue store[2] = {slot, value};
  (void)mir_b_emit(&fn->b, MOP_Store, store, 2, (MirImm){0}, MIR_NONE);
  const MirValue table = mir_b_emit(&fn->b, MOP_Shape, NULL, 0, of_type, MIR_PTR);
  const MirValue args[2] = {table, slot};
  return fn_runtime_call(fn, mir_name(fn->cx->module, ms_span_of_text(function)), args, 2, MIR_STR);
}

MirValue fn_value_text(LowerFn *fn, MirValue value, MirTy ty) {
  return value_shown(fn, value, ty, "msstd_value_text");
}

/* The quoted form a fault message shows (a String in quotes). */
MirValue fn_value_repr(LowerFn *fn, MirValue value, MirTy ty) {
  return value_shown(fn, value, ty, "msstd_test_repr");
}

static bool piece_of(LowerFn *fn, const MsTextPart *part, TextPiece *out) {
  if (part->expr == NULL) {
    const MirImm imm = {.tag = MI_STR, .a = mir_add_string(fn->cx->module, part->lit)};
    *out = (TextPiece){mir_b_emit(&fn->b, MOP_StrLit, NULL, 0, imm, MIR_STR), false};
    return true;
  }
  const MirValue value = fn_expr(fn, part->expr, LW_BORROW);
  if (value == MIR_NONE) {
    return false;
  }
  const MirTy ty = mir_b_ty(&fn->b, value);
  const MsTy source = ms_ty_subst(&fn->cx->program->types, ms_facts_type(fn->facts, part->expr->id), fn->subst.vars,
                                  fn->subst.args, fn->subst.count);
  const uint32_t own = lower_named_method(fn->cx, source, "to_string");
  if (own != MIR_NONE && fn->cx->module->funcs.ptr[own].ret == MIR_STR) { /* a type with its own text-valued `to_string` is written by it */
    const MirValue text = mir_b_call(&fn->b, own, &value, 1);
    fn_own_result(fn, text);
    *out = (TextPiece){text, false};
    return text != MIR_NONE;
  }
  if (ty == MIR_INT || ty == MIR_STR) {
    *out = (TextPiece){value, ty == MIR_INT};
    return true;
  }
  const MirValue text = fn_value_text(fn, value, ty);
  *out = (TextPiece){text, false};
  return text != MIR_NONE;
}

MirValue fn_text(LowerFn *fn, const MsExpr *expr) {
  const uint32_t count = expr->u.text.len;
  if (count == 0) {
    const MirImm imm = {.tag = MI_STR, .a = mir_add_string(fn->cx->module, ms_span_of_text(""))};
    return mir_b_emit(&fn->b, MOP_StrLit, NULL, 0, imm, MIR_STR);
  }
  TextPiece *pieces = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, TextPiece, count);
  for (uint32_t index = 0; index < count; index++) {
    if (!piece_of(fn, &expr->u.text.ptr[index], &pieces[index])) {
      return MIR_NONE;
    }
  }
  mir_b_set_loc(&fn->b, fn_loc(fn, expr->pos));
  return join_pieces(fn, pieces, count);
}

/* An interface operation the type has no method for, done by the runtime's walker over the type's shape
 * (`msstd_value_<operation>`, when the runtime has one): the operands go into stack slots, borrowed, and the
 * walker reads them through the shape table of the first. MIR_NONE when there is no such walker. */
MirValue fn_value_operation(LowerFn *fn, MsSpan operation, const MirValue *args, uint32_t nargs, MirTy ret) {
  if (nargs == 0 || nargs > 4) {
    return MIR_NONE;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "msstd_value_");
  ms_strbuild_append(&text, operation);
  const MsName name = mir_name(fn->cx->module, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  if (ms_native_sig_find(ms_names_span(&fn->cx->module->names, name)) == NULL) {
    return MIR_NONE;
  }
  const MirTy ty = mir_b_ty(&fn->b, args[0]);
  const MirImm of_type = {.tag = MI_TY, .a = ty};
  MirValue operands[5];
  operands[0] = mir_b_emit(&fn->b, MOP_Shape, NULL, 0, of_type, MIR_PTR);
  for (uint32_t at = 0; at < nargs; at++) {
    const MirValue slot = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, of_type, MIR_PTR);
    const MirValue store[2] = {slot, args[at]};
    (void)mir_b_emit(&fn->b, MOP_Store, store, 2, (MirImm){0}, MIR_NONE);
    operands[at + 1] = slot;
  }
  return fn_runtime_call(fn, name, operands, nargs + 1, ret);
}

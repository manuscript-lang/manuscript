/* compiler/lower/lower_text.c: interpolated text. The pieces are evaluated left to right and joined by one
 * runtime call: `msrt_string_concatN`, or `msrt_string_fmtN` (a mask of the integer pieces first) when a piece is
 * an integer, which the join writes in decimal. At most six pieces go in one call; a longer text joins the
 * first group, then that result and the next pieces. */
#include "compiler/lower/lower_fn.h"
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
  const uint32_t ext = mir_extern_get(fn->cx->module, ms_strbuild_span(&name), params, nparams, MIR_STR, true, role);
  ms_strbuild_free(&name);
  const MirValue result = mir_b_call_rt(&fn->b, ext, args, nparams);
  fn_own_result(fn, result);
  return result;
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

/* An integer type narrower than Int, widened so the join writes it in decimal. */
static bool is_sized_int(MirTy ty) {
  return ty == MIR_INT8 || ty == MIR_INT16 || ty == MIR_INT32 || ty == MIR_UINT8 || ty == MIR_UINT16 ||
         ty == MIR_UINT32;
}

/* The text of a scalar the join does not write itself: Bool, Float, Float32 and UInt64 through the runtime's
 * conversions. MIR_NONE for any other type. */
static MirValue scalar_text(LowerFn *fn, MirValue value, MirTy ty) {
  const char *name = NULL;
  switch (ty) {
  case MIR_BOOL:
    name = "msrt_bool_to_string";
    break;
  case MIR_FLOAT:
    name = "msrt_float_to_string";
    break;
  case MIR_FLOAT32:
    name = "msrt_float32_to_string";
    break;
  case MIR_UINT64:
    name = "msrt_uint_to_string";
    break;
  default:
    return MIR_NONE;
  }
  return fn_runtime_call(fn, mir_name(fn->cx->module, ms_span_of_text(name)), &value, 1, MIR_STR);
}

static bool piece_of(LowerFn *fn, const MsTextPart *part, TextPiece *out) {
  if (part->expr == NULL) {
    const MirImm imm = {.tag = MI_STR, .a = mir_add_string(fn->cx->module, part->lit)};
    *out = (TextPiece){mir_b_emit(&fn->b, MOP_StrLit, NULL, 0, imm, MIR_STR), false};
    return true;
  }
  MirValue value = fn_expr(fn, part->expr, LW_BORROW);
  if (value == MIR_NONE) {
    return false;
  }
  MirTy ty = mir_b_ty(&fn->b, value);
  if (is_sized_int(ty)) {
    value = mir_b_emit(&fn->b, MOP_Conv, &value, 1, (MirImm){0}, MIR_INT);
    ty = MIR_INT;
  }
  if (ty != MIR_INT && ty != MIR_STR) {
    const MirValue text = scalar_text(fn, value, ty);
    if (text == MIR_NONE) {
      return fn_fail(fn, "interpolating this type is not lowered yet");
    }
    *out = (TextPiece){text, false};
    return true;
  }
  *out = (TextPiece){value, ty == MIR_INT};
  return true;
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

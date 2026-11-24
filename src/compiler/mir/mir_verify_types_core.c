/* Rules for constants, arithmetic, comparisons, floats, types and alternatives. (see mir_verify_types.h) */
#include "compiler/mir/mir_layout.h"
#include "compiler/mir/mir_verify_types.h"

/* ---- constants ---- */

static const char *mvt_iconst(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 0));
  return mvt_want(c->in->imm.tag == MI_INT && c->has_res && mvt_is_int(c, c->res),
          "iconst yields an int type");
}

static const char *mvt_fconst(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 0));
  return mvt_want(c->in->imm.tag == MI_FLOAT && c->has_res && mvt_is_float(c, c->res),
          "fconst yields a float type");
}

static const char *mvt_bconst(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 0));
  return mvt_want(c->in->imm.tag == MI_BOOL && mvt_res_is(c, MIR_BOOL), "bconst yields bool");
}

static const char *mvt_voidconst(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 0));
  return mvt_want(mvt_res_is(c, MIR_VOID), "void yields void");
}

static const char *mvt_undef(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 0));
  return mvt_want(c->has_res, "undef yields a value");
}

static const char *mvt_strlit(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 0));
  if (c->in->imm.tag != MI_STR || c->in->imm.a >= ms_names_count(&c->m->strings)) {
    return "bad string literal";
  }
  return mvt_want(mvt_res_is(c, MIR_STR), "str yields string");
}

static const char *mvt_byteslit(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 0));
  const MirImm *im = &c->in->imm;
  if (im->tag != MI_INT || (uint64_t)im->i >= c->m->blobs.len) {
    return "bad bytes literal";
  }
  return mvt_want(mvt_res_is(c, MIR_BYTES), "bytes yields Bytes");
}

/* ---- integer and bit arithmetic ---- */

static const char *mvt_int_binary(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 2));
  return mvt_want(mvt_is_int(c, mvt_t(c, 0)) && mvt_t(c, 1) == mvt_t(c, 0) &&
            mvt_res_is(c, mvt_t(c, 0)),
          "operands and result must be one int type");
}

static const char *mvt_overflow_flag(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 2));
  return mvt_want(mvt_t(c, 0) == MIR_INT && mvt_t(c, 1) == MIR_INT && mvt_res_is(c, MIR_BOOL),
          "overflow flag takes two ints and yields bool");
}

static const char *mvt_fault_site(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  return mvt_want(mvt_res_is(c, MIR_BOOL), "a fault site yields bool");
}

static const char *mvt_overflow_if(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  return mvt_want(mvt_t(c, 0) == MIR_BOOL && !c->has_res,
          "overflow guard takes bool and has no result");
}

static const char *mvt_narrow_chk(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  uint32_t bits = c->has_res ? mvt_int_bits(c, c->res) : 0;
  return mvt_want(mvt_t(c, 0) == MIR_INT && bits != 0 && bits < 64,
          "narrow.chk takes an Int and yields a sized int");
}

static const char *mvt_conv(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  MirTy from = mvt_t(c, 0);
  bool ints = c->has_res && mvt_is_int(c, from) && mvt_is_int(c, c->res);
  bool floats = c->has_res && mvt_is_float(c, from) && mvt_is_float(c, c->res);
  return mvt_want(ints || floats,
          "conv takes an int or float and yields another type of the same kind");
}

static const char *mvt_inarrow_opt(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  MirTy inner = 0;
  bool ok = c->has_res && mvt_opt_inner(c, c->res, &inner) && mvt_is_int(c, inner);
  return mvt_want(mvt_is_int(c, mvt_t(c, 0)) && ok,
          "inarrow.opt takes an int and yields an optional int");
}

static const char *mvt_f32_round(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  return mvt_want(mvt_t(c, 0) == MIR_FLOAT32 && mvt_res_is(c, MIR_FLOAT32),
          "operand and result must be float32");
}

static const char *mvt_ineg(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  return mvt_want(mvt_is_int(c, mvt_t(c, 0)) && mvt_res_is(c, mvt_t(c, 0)),
          "operand and result must be one int type");
}

static const char *mvt_bitwise(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 2));
  MirTy t = mvt_t(c, 0);
  return mvt_want((mvt_is_int(c, t) || t == MIR_BOOL) && t == mvt_t(c, 1) && mvt_res_is(c, t),
          "operands and result must be both int or both bool");
}

static const char *mvt_bit_count(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  return mvt_want(mvt_t(c, 0) == MIR_INT && mvt_res_is(c, MIR_INT),
          "operand and result must be int");
}

static const char *mvt_not(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  return mvt_want(mvt_t(c, 0) == MIR_BOOL && mvt_res_is(c, MIR_BOOL),
          "operand and result must be bool");
}

/* ---- comparisons ---- */

static const char *mvt_uicmp(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 2));
  return mvt_want(c->in->imm.tag == MI_CC && mvt_t(c, 0) == mvt_t(c, 1) &&
            mvt_is_int(c, mvt_t(c, 0)) && mvt_res_is(c, MIR_BOOL),
          "uicmp compares two ints and yields bool");
}

static const char *mvt_icmp(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 2));
  if (c->in->imm.tag != MI_CC) {
    return "missing condition";
  }
  MirTy t = mvt_t(c, 0);
  bool equality = c->in->imm.a == MCC_EQ || c->in->imm.a == MCC_NE;
  /* A bool, a pointer or a value held by reference (an object handle, an interface value, a function value) is
   * equal to itself: eq/ne compare identity. */
  const MirTyKind kind = mvt_kind(c, t);
  const bool identity = t == MIR_BOOL || kind == MK_PTR || kind == MK_OBJ || kind == MK_IFACE || kind == MK_FN;
  bool ok = t == mvt_t(c, 1) && (mvt_is_int(c, t) || (identity && equality));
  return mvt_want(ok && mvt_res_is(c, MIR_BOOL),
          "icmp compares two ints (or bools and references for eq/ne) and yields bool");
}

static const char *mvt_fcmp(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 2));
  return mvt_want(c->in->imm.tag == MI_CC && mvt_is_float(c, mvt_t(c, 0)) &&
            mvt_t(c, 1) == mvt_t(c, 0) && mvt_res_is(c, MIR_BOOL),
          "fcmp compares two floats and yields bool");
}

static const char *mvt_select(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 3));
  return mvt_want(mvt_t(c, 0) == MIR_BOOL && mvt_t(c, 1) == mvt_t(c, 2) &&
            mvt_res_is(c, mvt_t(c, 1)) && !mvt_needs_drop(c, mvt_t(c, 1)),
          "select takes bool, two equal non-reference values");
}

/* ---- floats ---- */

static const char *mvt_float_binary(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 2));
  return mvt_want(mvt_is_float(c, mvt_t(c, 0)) && mvt_t(c, 1) == mvt_t(c, 0) &&
            mvt_res_is(c, mvt_t(c, 0)),
          "operands and result must be one float type");
}

static const char *mvt_float_unary(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  return mvt_want(mvt_is_float(c, mvt_t(c, 0)) && mvt_res_is(c, mvt_t(c, 0)),
          "operand and result must be one float type");
}

static const char *mvt_i2f(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  return mvt_want(mvt_is_int(c, mvt_t(c, 0)) && c->has_res && mvt_is_float(c, c->res),
          "i2f converts an int type to a float type");
}

static const char *mvt_u2f(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  return mvt_want(mvt_t(c, 0) == MIR_UINT64 && c->has_res && mvt_is_float(c, c->res),
          "u2f converts a UInt64 to a float type");
}

static const char *mvt_f_bits(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  return mvt_want(mvt_is_float(c, mvt_t(c, 0)) && mvt_res_is(c, MIR_INT), "f.bits reads the bits of a float as an int");
}

static const char *mvt_bits_f(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  return mvt_want(mvt_t(c, 0) == MIR_INT && c->has_res && mvt_is_float(c, c->res), "bits.f makes a float of the bits of an int");
}

static const char *mvt_f2i_opt(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  return mvt_want(mvt_is_float(c, mvt_t(c, 0)) && mvt_res_opt_of(c, MIR_INT),
          "f2i.opt converts float to opt<int>");
}

static const char *mvt_b2i(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  return mvt_want(mvt_t(c, 0) == MIR_BOOL && mvt_res_is(c, MIR_INT),
          "b2i converts bool to int");
}

/* ---- types ---- */

static const char *mvt_type_new(const MvtCx *c) {
  const MirImm *im = &c->in->imm;
  if (im->tag != MI_TYPE) {
    return "missing type";
  }
  if (im->a >= c->m->type_defs.len) {
    return "bad type";
  }
  const MirTypeDef *def = &c->m->type_defs.ptr[im->a];
  if (c->n != def->nfields) {
    return mvt_fmt(c->v->arena, "type %s has %u fields, found %u operands",
              mvt_name(c, def->name), def->nfields, c->n);
  }
  for (uint32_t i = 0; i < c->n; i++) {
    if (mvt_t(c, i) != def->fields[i].ty) {
      const char *what = mvt_fmt(c->v->arena, "field %s", mvt_name(c, def->fields[i].name));
      return mvt_mismatch(c, what, mvt_t(c, i), def->fields[i].ty);
    }
  }
  return mvt_want(c->has_res && mvt_is_kind_id(c, c->res, MK_TYPE, im->a), "type.new yields the type");
}

static const char *mvt_type_field(const MvtCx *c) {
  const MirImm *im = &c->in->imm;
  if (im->tag != MI_FIELD) {
    return "missing field";
  }
  if (im->a >= c->m->type_defs.len) {
    return "bad type";
  }
  const MirTypeDef *def = &c->m->type_defs.ptr[im->a];
  if (im->b >= def->nfields) {
    return "bad field index";
  }
  MirTy field_ty = def->fields[im->b].ty;
  if (c->n == 0 || !mvt_is_kind_id(c, mvt_t(c, 0), MK_TYPE, im->a)) {
    return mvt_fmt(c->v->arena, "operand 0 must be type %s", mvt_name(c, def->name));
  }
  if (c->in->op == MOP_TypeGet) {
    MVT_TRY(mvt_arity(c, 1));
    return mvt_want(mvt_res_is(c, field_ty), "type.get yields the field type");
  }
  MVT_TRY(mvt_arity(c, 2));
  return mvt_want(mvt_t(c, 1) == field_ty && mvt_res_is(c, mvt_t(c, 0)),
          "stored value must have the field type; yields the updated type");
}

static const char *mvt_type_release(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  const MirImm *im = &c->in->imm;
  if (im->tag != MI_TYPEMASK) {
    return "missing field mask";
  }
  bool ok = im->a < c->m->type_defs.len && c->m->type_defs.ptr[im->a].nfields <= 32 &&
       mvt_is_kind_id(c, mvt_t(c, 0), MK_TYPE, im->a) && !c->has_res;
  return mvt_want(ok, "type.release takes a type with at most 32 fields");
}

/* ---- alternatives ---- */

static const char *mvt_alt_ctor(const MvtCx *c) {
  const MirImm *im = &c->in->imm;
  if (im->tag != MI_CASE) {
    return "missing case";
  }
  if (im->a >= c->m->alts.len || im->b >= c->m->alts.ptr[im->a].ncases) {
    return "bad case";
  }
  const MirAltDef *alt = &c->m->alts.ptr[im->a];
  const MirCaseDef *kase = &alt->cases[im->b];
  if (c->n != kase->nfields) {
    return mvt_fmt(c->v->arena, "case %s has %u fields, found %u operands",
              mvt_name(c, kase->name), kase->nfields, c->n);
  }
  for (uint32_t i = 0; i < c->n; i++) {
    if (mvt_t(c, i) != kase->fields[i].ty) {
      return mvt_mismatch(c, mvt_label(c, "field", i), mvt_t(c, i), kase->fields[i].ty);
    }
  }
  MVT_TRY(mvt_want(c->has_res && mvt_is_kind_id(c, c->res, MK_ALT, im->a),
          "alt.new yields the alternative type"));
  /* A borrowing variant borrows exactly its borrowed cases: alt.view fills one, alt.new the others. */
  if (alt->borrowed != 0) {
    MVT_TRY(mvt_want(mvt_borrows(alt, im->b) == (c->in->op == MOP_AltView),
            "a borrowing variant is filled by alt.view in its borrowed cases and alt.new in the others"));
  }
  /* A boxed alternative holds its payload in a heap block, which a borrow cannot own. */
  return mvt_want(c->in->op == MOP_AltNew || !mir_layouts_alt_boxed(c->v->layouts, im->a),
          "alt.view cannot borrow a boxed alternative");
}

/* An alternative's name without the `$N` the printer adds to tell same-named declarations apart
 * (a borrowing variant has its ordinary alternative's name). */
static MsSpan mvt_base_name(const MvtCx *c, MsName s) {
  MsSpan n = ms_names_span(&c->m->names, s);
  size_t end = n.len;
  while (end > 0 && n.ptr[end - 1] >= '0' && n.ptr[end - 1] <= '9') {
    end--;
  }
  if (end > 0 && end < n.len && n.ptr[end - 1] == '$') {
    n.len = (uint32_t)(end - 1);
  }
  return n;
}

static bool mvt_same_alt_name(const MvtCx *c, MsName a, MsName b) {
  if (a == b) {
    return true;
  }
  const MsSpan x = mvt_base_name(c, a), y = mvt_base_name(c, b);
  return x.len == y.len && __builtin_memcmp(x.ptr, y.ptr, x.len) == 0;
}

/* alt.plain and alt.own read a borrowing variant as the ordinary alternative of the same cases. */
bool mvt_plain_of(const MvtCx *c) {
  const MirTyData *from = mvt_data(c, mvt_t(c, 0));
  const MirTyData *to = mvt_data(c, c->res);
  if (from->kind != MK_ALT || to->kind != MK_ALT) {
    return false;
  }
  const MirAltDef *dx = &c->m->alts.ptr[from->id];
  const MirAltDef *dy = &c->m->alts.ptr[to->id];
  if (dx->borrowed == 0 || dy->borrowed != 0 || !mvt_same_alt_name(c, dx->name, dy->name) || dx->ncases != dy->ncases) {
    return false;
  }
  for (uint32_t i = 0; i < dx->ncases; i++) {
    const MirCaseDef *a = &dx->cases[i], *b = &dy->cases[i];
    if (a->name != b->name || a->nfields != b->nfields) {
      return false;
    }
    for (uint32_t k = 0; k < a->nfields; k++) {
      if (a->fields[k].name != b->fields[k].name || a->fields[k].ty != b->fields[k].ty) {
        return false;
      }
    }
  }
  return true;
}

static const char *mvt_alt_plain(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  if (mvt_kind(c, mvt_t(c, 0)) != MK_ALT || !c->has_res) {
    return "alt.plain takes a borrowing variant";
  }
  if (mvt_kind(c, c->res) != MK_ALT) {
    return "alt.plain yields an alternative";
  }
  return mvt_want(mvt_plain_of(c), "alt.plain reads a borrowing variant as its ordinary alternative");
}

static const char *mvt_alt_tag(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  return mvt_want(mvt_kind(c, mvt_t(c, 0)) == MK_ALT && mvt_res_is(c, MIR_INT),
          "alt.tag takes an alternative and yields int");
}

static const char *mvt_alt_release(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  const MirImm *im = &c->in->imm;
  if (im->tag != MI_ALTMASK) {
    return "missing case mask";
  }
  if (im->a >= c->m->alts.len || im->b >= c->m->alts.ptr[im->a].ncases) {
    return "bad case";
  }
  const MirAltDef *alt = &c->m->alts.ptr[im->a];
  MVT_TRY(mvt_want(!mvt_borrows(alt, im->b),
          "alt.release of a borrowed case would free a payload another value owns"));
  return mvt_want(alt->cases[im->b].nfields <= 32 &&
            mvt_is_kind_id(c, mvt_t(c, 0), MK_ALT, im->a) && !c->has_res,
          "alt.release takes an alternative with at most 32 payload fields");
}

static const char *mvt_alt_field(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  const MirImm *im = &c->in->imm;
  if (im->tag != MI_ALTFIELD) {
    return "missing case field";
  }
  if (im->a >= c->m->alts.len || im->b >= c->m->alts.ptr[im->a].ncases) {
    return "bad case";
  }
  const MirAltDef *alt = &c->m->alts.ptr[im->a];
  const MirCaseDef *kase = &alt->cases[im->b];
  if (im->c >= kase->nfields) {
    return "bad field index";
  }
  bool takes = c->in->op == MOP_AltTake || c->in->op == MOP_AltUnbox;
  MVT_TRY(mvt_want(!takes || !mvt_borrows(alt, im->b),
          "a borrowed case cannot be taken: its payload belongs to another value"));
  return mvt_want(mvt_is_kind_id(c, mvt_t(c, 0), MK_ALT, im->a) &&
            mvt_res_is(c, kase->fields[im->c].ty),
          "alt.get yields the payload field type");
}

const MvtRule mvt_rules_core[MOP_COUNT] = {
  [MOP_IConst] = mvt_iconst, [MOP_FConst] = mvt_fconst, [MOP_BConst] = mvt_bconst,
  [MOP_VoidConst] = mvt_voidconst, [MOP_Undef] = mvt_undef, [MOP_StrLit] = mvt_strlit,
  [MOP_BytesLit] = mvt_byteslit, [MOP_IAdd] = mvt_int_binary, [MOP_ISub] = mvt_int_binary,
  [MOP_IMul] = mvt_int_binary, [MOP_IAddChk] = mvt_int_binary, [MOP_ISubChk] = mvt_int_binary,
  [MOP_IMulChk] = mvt_int_binary, [MOP_UAddChk] = mvt_int_binary, [MOP_USubChk] = mvt_int_binary,
  [MOP_UMulChk] = mvt_int_binary, [MOP_SDivChk] = mvt_int_binary, [MOP_SRemChk] = mvt_int_binary, [MOP_UDivChk] = mvt_int_binary,
  [MOP_URemChk] = mvt_int_binary,
  [MOP_SDiv] = mvt_int_binary, [MOP_SRem] = mvt_int_binary, [MOP_Shl] = mvt_int_binary,
  [MOP_Sshr] = mvt_int_binary, [MOP_Ushr] = mvt_int_binary, [MOP_Rotl] = mvt_int_binary,
  [MOP_Rotr] = mvt_int_binary, [MOP_UMulHi] = mvt_int_binary, [MOP_IAddOverflow] = mvt_overflow_flag,
  [MOP_IMulOverflow] = mvt_overflow_flag, [MOP_IntOverflowIf] = mvt_overflow_if, [MOP_FaultSite] = mvt_fault_site,
  [MOP_NarrowChk] = mvt_narrow_chk, [MOP_Conv] = mvt_conv, [MOP_INarrowOpt] = mvt_inarrow_opt,
  [MOP_F32Round] = mvt_f32_round, [MOP_INeg] = mvt_ineg, [MOP_INegChk] = mvt_ineg, [MOP_And] = mvt_bitwise,
  [MOP_Or] = mvt_bitwise, [MOP_Xor] = mvt_bitwise, [MOP_Clz] = mvt_bit_count, [MOP_Ctz] = mvt_bit_count,
  [MOP_Popcnt] = mvt_bit_count, [MOP_Not] = mvt_not, [MOP_UICmp] = mvt_uicmp, [MOP_ICmp] = mvt_icmp,
  [MOP_FCmp] = mvt_fcmp, [MOP_Select] = mvt_select, [MOP_FAdd] = mvt_float_binary,
  [MOP_FSub] = mvt_float_binary, [MOP_FMul] = mvt_float_binary, [MOP_FDiv] = mvt_float_binary,
  [MOP_FNeg] = mvt_float_unary, [MOP_FSqrt] = mvt_float_unary, [MOP_FAbs] = mvt_float_unary,
  [MOP_FFloor] = mvt_float_unary, [MOP_FCeil] = mvt_float_unary, [MOP_FTrunc] = mvt_float_unary,
  [MOP_I2F] = mvt_i2f, [MOP_U2F] = mvt_u2f, [MOP_FBits] = mvt_f_bits, [MOP_BitsF] = mvt_bits_f, [MOP_F2IOpt] = mvt_f2i_opt, [MOP_B2I] = mvt_b2i, [MOP_TypeNew] = mvt_type_new,
  [MOP_TypeGet] = mvt_type_field, [MOP_TypeSet] = mvt_type_field, [MOP_TypeFill] = mvt_type_field,
  [MOP_TypeRelease] = mvt_type_release, [MOP_AltNew] = mvt_alt_ctor, [MOP_AltView] = mvt_alt_ctor,
  [MOP_AltPlain] = mvt_alt_plain, [MOP_AltTag] = mvt_alt_tag, [MOP_AltRelease] = mvt_alt_release,
  [MOP_AltGet] = mvt_alt_field, [MOP_AltUnbox] = mvt_alt_field, [MOP_AltTake] = mvt_alt_field,
};

/* The operand and result type rules of each MIR instruction (verify/types.rs). Every op has one
 * rule in `mvt_rules`; a rule returns NULL when the instruction is well formed and the reason
 * otherwise. Rules for ops that share a shape share a function. */
#include <string.h>

#include "ms/mir_layout.h"
#include "ms/mir_verify.h"

typedef struct MvtCx {
    const MirVerifyCx *v;
    const MirModule *m;
    const MirFunc *f;
    const MirInst *in;
    uint32_t n;    /* operand count */
    bool has_res;
    MirTy res;
} MvtCx;

typedef const char *(*MvtRule)(const MvtCx *c);

#define MVT_TRY(expr) \
    do { \
        const char *mvt_err = (expr); \
        if (mvt_err != NULL) { \
            return mvt_err; \
        } \
    } while (0)

/* ---- helpers ---- */

static MirTy mvt_t(const MvtCx *c, uint32_t i) { return c->f->values[c->in->args[i]]; }

static const MirTyData *mvt_data(const MvtCx *c, MirTy t) { return mir_ty_data(c->m, t); }

static MirTyKind mvt_kind(const MvtCx *c, MirTy t) { return (MirTyKind)mvt_data(c, t)->kind; }

static bool mvt_res_is(const MvtCx *c, MirTy t) { return c->has_res && c->res == t; }

static bool mvt_needs_drop(const MvtCx *c, MirTy t) { return c->v->drops[t]; }

static const char *mvt_want(bool cond, const char *msg) { return cond ? NULL : msg; }

static const char *mvt_arity(const MvtCx *c, uint32_t k) {
    if (c->n == k) {
        return NULL;
    }
    return ms_arena_fmt(c->v->arena, "expected %u operands, found %u", k, c->n).ptr;
}

static const char *mvt_type_name(const MvtCx *c, MirTy t) {
    MsBuf b = {0};
    mir_print_ty(c->m, t, &b);
    const char *s = ms_arena_strndup(c->v->arena, b.data, b.len);
    ms_buf_free(&b);
    return s;
}

static const char *mvt_name(const MvtCx *c, MsSym s) {
    MsStr n = ms_name(&c->m->names, s);
    return ms_arena_strndup(c->v->arena, n.ptr, n.len);
}

static const char *mvt_mismatch(const MvtCx *c, const char *what, MirTy got, MirTy want) {
    return ms_arena_fmt(c->v->arena, "%s has type %s but %s is expected", what,
                        mvt_type_name(c, got), mvt_type_name(c, want))
        .ptr;
}

static const char *mvt_label(const MvtCx *c, const char *noun, uint32_t i) {
    return ms_arena_fmt(c->v->arena, "%s %u", noun, i).ptr;
}

static bool mvt_is_float(const MvtCx *c, MirTy t) {
    MirTyKind k = mvt_kind(c, t);
    return k == MK_FLOAT || k == MK_FLOAT32;
}

/* Bit width of an integer type, 0 for any other. */
static uint32_t mvt_int_bits(const MvtCx *c, MirTy t) {
    switch (mvt_kind(c, t)) {
    case MK_INT: case MK_UINT64: return 64;
    case MK_INT32: case MK_UINT32: return 32;
    case MK_INT16: case MK_UINT16: return 16;
    case MK_INT8: case MK_UINT8: return 8;
    case MK_VOID: case MK_BOOL: case MK_FLOAT: case MK_FLOAT32: case MK_STR: case MK_BYTES:
    case MK_PTR: case MK_TYPE: case MK_ALT: case MK_LIST: case MK_OPT: case MK_OBJ: case MK_FN:
    case MK_IFACE:
        return 0;
    }
    return 0;
}

static bool mvt_is_int(const MvtCx *c, MirTy t) { return mvt_int_bits(c, t) != 0; }

static bool mvt_is_kind_id(const MvtCx *c, MirTy t, MirTyKind kind, uint32_t id) {
    const MirTyData *d = mvt_data(c, t);
    return d->kind == kind && d->id == id;
}

static bool mvt_is_iface(const MvtCx *c, MirTy t) { return mvt_kind(c, t) == MK_IFACE; }

static bool mvt_list_elem(const MvtCx *c, MirTy t, MirTy *elem) {
    const MirTyData *d = mvt_data(c, t);
    if (d->kind != MK_LIST) {
        return false;
    }
    *elem = d->elem;
    return true;
}

/* The element of a list, or uint8 for bytes. */
static bool mvt_seq_elem(const MvtCx *c, MirTy t, MirTy *elem) {
    if (mvt_kind(c, t) == MK_BYTES) {
        *elem = MIR_UINT8;
        return true;
    }
    return mvt_list_elem(c, t, elem);
}

static bool mvt_opt_inner(const MvtCx *c, MirTy t, MirTy *inner) {
    const MirTyData *d = mvt_data(c, t);
    if (d->kind != MK_OPT) {
        return false;
    }
    *inner = d->elem;
    return true;
}

/* Whether the result is an optional of `want`. */
static bool mvt_res_opt_of(const MvtCx *c, MirTy want) {
    MirTy inner = 0;
    return c->has_res && mvt_opt_inner(c, c->res, &inner) && inner == want;
}

static bool mvt_borrows(const MirAltDef *a, uint32_t k) { return k < 64 && (a->borrowed >> k & 1); }

static bool mvt_alt_has_borrowed_cases(const MvtCx *c, MirTy t) {
    const MirTyData *d = mvt_data(c, t);
    return d->kind == MK_ALT && c->m->alts[d->id].borrowed != 0;
}

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
    if (c->in->imm.tag != MI_STR || c->in->imm.a >= c->m->strings.count) {
        return "bad string literal";
    }
    return mvt_want(mvt_res_is(c, MIR_STR), "str yields string");
}

static const char *mvt_byteslit(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 0));
    const MirImm *im = &c->in->imm;
    if (im->tag != MI_INT || (uint64_t)im->i >= c->m->nblobs) {
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
    bool ok = t == mvt_t(c, 1) && (mvt_is_int(c, t) || (t == MIR_BOOL && equality));
    return mvt_want(ok && mvt_res_is(c, MIR_BOOL),
                    "icmp compares two ints (or bools for eq/ne) and yields bool");
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
    if (im->a >= c->m->ntype_defs) {
        return "bad type";
    }
    const MirTypeDef *def = &c->m->type_defs[im->a];
    if (c->n != def->nfields) {
        return ms_arena_fmt(c->v->arena, "type %s has %u fields, found %u operands",
                            mvt_name(c, def->name), def->nfields, c->n)
            .ptr;
    }
    for (uint32_t i = 0; i < c->n; i++) {
        if (mvt_t(c, i) != def->fields[i].ty) {
            const char *what = ms_arena_fmt(c->v->arena, "field %s", mvt_name(c, def->fields[i].name)).ptr;
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
    if (im->a >= c->m->ntype_defs) {
        return "bad type";
    }
    const MirTypeDef *def = &c->m->type_defs[im->a];
    if (im->b >= def->nfields) {
        return "bad field index";
    }
    MirTy field_ty = def->fields[im->b].ty;
    if (c->n == 0 || !mvt_is_kind_id(c, mvt_t(c, 0), MK_TYPE, im->a)) {
        return ms_arena_fmt(c->v->arena, "operand 0 must be type %s", mvt_name(c, def->name)).ptr;
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
    bool ok = im->a < c->m->ntype_defs && c->m->type_defs[im->a].nfields <= 32 &&
              mvt_is_kind_id(c, mvt_t(c, 0), MK_TYPE, im->a) && !c->has_res;
    return mvt_want(ok, "type.release takes a type with at most 32 fields");
}

/* ---- alternatives ---- */

static const char *mvt_alt_ctor(const MvtCx *c) {
    const MirImm *im = &c->in->imm;
    if (im->tag != MI_CASE) {
        return "missing case";
    }
    if (im->a >= c->m->nalts || im->b >= c->m->alts[im->a].ncases) {
        return "bad case";
    }
    const MirAltDef *alt = &c->m->alts[im->a];
    const MirCaseDef *kase = &alt->cases[im->b];
    if (c->n != kase->nfields) {
        return ms_arena_fmt(c->v->arena, "case %s has %u fields, found %u operands",
                            mvt_name(c, kase->name), kase->nfields, c->n)
            .ptr;
    }
    for (uint32_t i = 0; i < c->n; i++) {
        if (mvt_t(c, i) != kase->fields[i].ty) {
            return mvt_mismatch(c, mvt_label(c, "field", i), mvt_t(c, i), kase->fields[i].ty);
        }
    }
    MVT_TRY(mvt_want(c->has_res && mvt_is_kind_id(c, c->res, MK_ALT, im->a),
                     "alt.new yields the alternative type"));
    /* A borrowing variant lends exactly its borrowed cases: alt.view fills one, alt.new the others. */
    if (alt->borrowed != 0) {
        MVT_TRY(mvt_want(mvt_borrows(alt, im->b) == (c->in->op == MOP_AltView),
                         "a borrowing variant is filled by alt.view in its borrowed cases and alt.new in the others"));
    }
    /* A boxed alternative holds its payload in a heap block, which a borrow cannot own. */
    return mvt_want(c->in->op == MOP_AltNew || !mir_alt_is_boxed(c->m, im->a),
                    "alt.view cannot borrow a boxed alternative");
}

/* An alternative's name without the `$N` the printer adds to tell same-named declarations apart
 * (a borrowing variant has its ordinary alternative's name). */
static MsStr mvt_base_name(const MvtCx *c, MsSym s) {
    MsStr n = ms_name(&c->m->names, s);
    size_t end = n.len;
    while (end > 0 && n.ptr[end - 1] >= '0' && n.ptr[end - 1] <= '9') {
        end--;
    }
    if (end > 0 && end < n.len && n.ptr[end - 1] == '$') {
        n.len = (uint32_t)(end - 1);
    }
    return n;
}

static bool mvt_same_alt_name(const MvtCx *c, MsSym a, MsSym b) {
    if (a == b) {
        return true;
    }
    const MsStr x = mvt_base_name(c, a), y = mvt_base_name(c, b);
    return x.len == y.len && memcmp(x.ptr, y.ptr, x.len) == 0;
}

/* alt.plain and alt.own read a borrowing variant as the ordinary alternative of the same cases. */
static bool mvt_plain_of(const MvtCx *c) {
    const MirTyData *from = mvt_data(c, mvt_t(c, 0));
    const MirTyData *to = mvt_data(c, c->res);
    if (from->kind != MK_ALT || to->kind != MK_ALT) {
        return false;
    }
    const MirAltDef *dx = &c->m->alts[from->id];
    const MirAltDef *dy = &c->m->alts[to->id];
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
    if (im->a >= c->m->nalts || im->b >= c->m->alts[im->a].ncases) {
        return "bad case";
    }
    const MirAltDef *alt = &c->m->alts[im->a];
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
    if (im->a >= c->m->nalts || im->b >= c->m->alts[im->a].ncases) {
        return "bad case";
    }
    const MirAltDef *alt = &c->m->alts[im->a];
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

/* ---- lists ---- */

static const char *mvt_list_new(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    MirTy elem = 0;
    return mvt_want(mvt_t(c, 0) == MIR_INT && c->has_res && mvt_list_elem(c, c->res, &elem),
                    "list.new takes a capacity and yields a list");
}

static const char *mvt_list_lit(const MvtCx *c) {
    MirTy elem = 0;
    if (!c->has_res || !mvt_list_elem(c, c->res, &elem)) {
        return "list.lit yields a list";
    }
    for (uint32_t i = 0; i < c->n; i++) {
        if (mvt_t(c, i) != elem) {
            return mvt_mismatch(c, "element", mvt_t(c, i), elem);
        }
    }
    return NULL;
}

static bool mvt_is_scalar_elem(const MvtCx *c, MirTy t) {
    MirTyKind k = mvt_kind(c, t);
    return k == MK_BOOL || k == MK_FLOAT || k == MK_FLOAT32 || mvt_is_int(c, t);
}

static const char *mvt_list_const(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 0));
    MirTy elem = 0;
    if (!c->has_res || !mvt_list_elem(c, c->res, &elem)) {
        return "list.const yields a list";
    }
    const MirImm *im = &c->in->imm;
    bool ok = im->tag == MI_INT && mvt_is_scalar_elem(c, elem) &&
              (uint64_t)im->i < c->m->nlist_consts;
    return mvt_want(ok, "list.const names constant data of a scalar element type");
}

static const char *mvt_list_len(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    MirTy elem = 0;
    bool seq = mvt_list_elem(c, mvt_t(c, 0), &elem) || mvt_t(c, 0) == MIR_BYTES;
    return mvt_want(seq && mvt_res_is(c, MIR_INT), "list.len takes a list (or bytes) and yields int");
}

static const char *mvt_list_get(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 2));
    MirTy elem = 0;
    if (!mvt_seq_elem(c, mvt_t(c, 0), &elem)) {
        return "operand 0 must be a list";
    }
    return mvt_want(mvt_t(c, 1) == MIR_INT && mvt_res_is(c, elem),
                    "index must be int; result is the element type");
}

static const char *mvt_list_release(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 2));
    MirTy elem = 0;
    if (!mvt_list_elem(c, mvt_t(c, 0), &elem)) {
        return "operand 0 must be a list";
    }
    return mvt_want(mvt_t(c, 1) == MIR_INT && !c->has_res,
                    "the first kept index must be int; no result");
}

static const char *mvt_list_store(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 3));
    MirTy elem = 0;
    if (!mvt_list_elem(c, mvt_t(c, 0), &elem)) {
        return "operand 0 must be a list";
    }
    return mvt_want(mvt_t(c, 1) == MIR_INT && mvt_t(c, 2) == elem && mvt_res_is(c, mvt_t(c, 0)),
                    "index must be int; value must be the element type; yields the updated list");
}

static const char *mvt_list_cap(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    MirTy elem = 0;
    if (!mvt_list_elem(c, mvt_t(c, 0), &elem)) {
        return "operand 0 must be a list";
    }
    return mvt_want(mvt_res_is(c, MIR_INT), "list.cap yields int");
}

static const char *mvt_list_grow(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 2));
    MirTy elem = 0;
    if (!mvt_list_elem(c, mvt_t(c, 0), &elem)) {
        return "operand 0 must be a list";
    }
    return mvt_want(mvt_t(c, 1) == MIR_INT && mvt_res_is(c, mvt_t(c, 0)),
                    "the new capacity must be int; yields the list with room for it");
}

static const char *mvt_list_push(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 2));
    MirTy elem = 0;
    if (!mvt_list_elem(c, mvt_t(c, 0), &elem)) {
        return "operand 0 must be a list";
    }
    return mvt_want(mvt_t(c, 1) == elem && mvt_res_is(c, mvt_t(c, 0)),
                    "value must be the element type; yields the updated list");
}

static const char *mvt_list_drop_last(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    MirTy elem = 0;
    if (!mvt_list_elem(c, mvt_t(c, 0), &elem)) {
        return "operand 0 must be a list";
    }
    return mvt_want(mvt_res_is(c, mvt_t(c, 0)), "yields the shortened list");
}

/* ---- optionals ---- */

static const char *mvt_opt_wrap(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    MVT_TRY(mvt_want(mvt_res_opt_of(c, mvt_t(c, 0)), "optional constructors wrap their operand"));
    /* A boxed optional holds its payload in a heap block, which a borrow cannot own. */
    return mvt_want(c->in->op == MOP_OptSome || !mir_opt_is_boxed(c->m, mvt_t(c, 0)),
                    "opt.view cannot borrow a boxed optional");
}

static const char *mvt_opt_view_at(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    MVT_TRY(mvt_want(mvt_t(c, 0) == MIR_PTR, "opt.view_at takes an address"));
    MirTy inner = 0;
    bool boxed = c->has_res && mvt_opt_inner(c, c->res, &inner) && mir_opt_is_boxed(c->m, inner);
    return mvt_want(boxed, "opt.view_at yields a boxed optional");
}

static const char *mvt_opt_none(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 0));
    MirTy inner = 0;
    return mvt_want(c->has_res && mvt_opt_inner(c, c->res, &inner), "opt.none yields an optional");
}

static const char *mvt_opt_is_some(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    MirTy inner = 0;
    return mvt_want(mvt_opt_inner(c, mvt_t(c, 0), &inner) && mvt_res_is(c, MIR_BOOL),
                    "opt.is_some takes an optional and yields bool");
}

static const char *mvt_opt_payload(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    MirTy inner = 0;
    return mvt_want(mvt_opt_inner(c, mvt_t(c, 0), &inner) && mvt_res_is(c, inner),
                    "yields the payload type");
}

static const char *mvt_opt_addr(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    MirTy inner = 0;
    return mvt_want(mvt_opt_inner(c, mvt_t(c, 0), &inner) && mvt_res_is(c, MIR_PTR),
                    "opt.addr takes a present optional and yields a ptr to its payload");
}

/* ---- strings ---- */

/* A rule for `str -> int` ops: only the message differs. */
static const char *mvt_str_to_int(const MvtCx *c, const char *msg) {
    MVT_TRY(mvt_arity(c, 1));
    return mvt_want(mvt_t(c, 0) == MIR_STR && mvt_res_is(c, MIR_INT), msg);
}

static const char *mvt_str_len(const MvtCx *c) {
    return mvt_str_to_int(c, "str.len takes a string and yields int");
}

static const char *mvt_str_ascii_len(const MvtCx *c) {
    return mvt_str_to_int(c, "str.ascii_len takes a string and yields int");
}

static const char *mvt_str_bytes(const MvtCx *c) {
    return mvt_str_to_int(c, "str.bytes takes a string and yields its byte length");
}

static const char *mvt_str_byte(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 2));
    return mvt_want(mvt_t(c, 0) == MIR_STR && mvt_t(c, 1) == MIR_INT && mvt_res_is(c, MIR_INT),
                    "str.byte takes a string and a byte offset and yields int");
}

/* The literal of str.eq_lit is 1 to 8 bytes with no NUL. */
static bool mvt_eq_lit_ok(const MvtCx *c, const MirImm *im) {
    if (im->tag != MI_STR || im->a >= c->m->strings.count) {
        return false;
    }
    MsStr s = ms_name(&c->m->strings, im->a);
    return s.len >= 1 && s.len <= 8 && memchr(s.ptr, 0, s.len) == NULL;
}

static const char *mvt_str_eq_lit(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    return mvt_want(mvt_t(c, 0) == MIR_STR && mvt_res_is(c, MIR_BOOL) && mvt_eq_lit_ok(c, &c->in->imm),
                    "str.eq_lit takes a string and a literal of 1 to 8 bytes without NUL and yields bool");
}

static const char *mvt_str_ascii(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    return mvt_want(mvt_t(c, 0) == MIR_INT && mvt_res_is(c, MIR_STR),
                    "str.ascii takes an ASCII byte and yields the shared one-character string");
}

static const char *mvt_bytes_push(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 2));
    return mvt_want(mvt_t(c, 0) == MIR_PTR && mvt_is_int(c, mvt_t(c, 1)) && mvt_res_is(c, MIR_BOOL),
                    "bytes.push takes a builder address and a byte value and yields bool");
}

/* ---- closures and interfaces ---- */

/* The parameters after the environment, as a function type lists them. */
static bool mvt_closure_type_matches(const MvtCx *c, const MirFunc *callee) {
    const MirTyData *fn = mvt_data(c, c->res);
    uint32_t visible = callee->nparams > 0 ? callee->nparams - 1 : 0;
    if (fn->nargs != visible || fn->elem != callee->ret) {
        return false;
    }
    for (uint32_t i = 0; i < visible; i++) {
        if (fn->args[i] != callee->params[i + 1].ty) {
            return false;
        }
    }
    return true;
}

static const char *mvt_closure_params(const MvtCx *c, const MirFunc *callee) {
    const MirTyData *fn = mvt_data(c, c->res);
    for (uint32_t i = 1; i < callee->nparams; i++) {
        if ((callee->params[i].mode == MM_MOVE) != mir_owns(fn->owned, i - 1)) {
            return ms_arena_fmt(c->v->arena,
                                "%s parameter %u must be `move` exactly where its function type passes it owned",
                                mvt_name(c, callee->name), i - 1)
                .ptr;
        }
    }
    return NULL;
}

static const char *mvt_closure_new(const MvtCx *c) {
    const MirImm *im = &c->in->imm;
    if (im->tag != MI_FUNC) {
        return "missing function";
    }
    if (im->a >= c->m->nfuncs) {
        return "bad function";
    }
    const MirFunc *callee = &c->m->funcs[im->a];
    if (callee->kind != MFK_CLOSURE) {
        return ms_arena_fmt(c->v->arena, "%s is not a closure function", mvt_name(c, callee->name)).ptr;
    }
    if (c->n != callee->ncaptures) {
        return ms_arena_fmt(c->v->arena, "%s captures %u values, found %u", mvt_name(c, callee->name),
                            callee->ncaptures, c->n)
            .ptr;
    }
    for (uint32_t i = 0; i < c->n; i++) {
        if (mvt_t(c, i) != callee->captures[i]) {
            return mvt_mismatch(c, "capture", mvt_t(c, i), callee->captures[i]);
        }
    }
    if (!c->has_res || mvt_kind(c, c->res) != MK_FN) {
        return "closure.new yields a function type";
    }
    if (!mvt_closure_type_matches(c, callee)) {
        return "closure.new yields a function type matching the closure code";
    }
    return mvt_closure_params(c, callee);
}

/* The captures of the enclosing closure function and the index into them, or the error. */
static const char *mvt_capture_index(const MvtCx *c, const char *op, uint32_t *index) {
    if (c->in->imm.tag != MI_IDX) {
        return "missing index";
    }
    if (c->f->kind != MFK_CLOSURE) {
        return ms_arena_fmt(c->v->arena, "%s outside a closure function", op).ptr;
    }
    *index = c->in->imm.a;
    return NULL;
}

static const char *mvt_closure_cap(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    uint32_t i = 0;
    MVT_TRY(mvt_capture_index(c, "closure.cap", &i));
    if (i >= c->f->ncaptures) {
        return "capture index out of range";
    }
    return mvt_want(mvt_t(c, 0) == MIR_PTR && mvt_res_is(c, c->f->captures[i]),
                    "closure.cap reads the environment (ptr) and yields the capture type");
}

static const char *mvt_closure_cap_addr(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    uint32_t i = 0;
    MVT_TRY(mvt_capture_index(c, "closure.cap_addr", &i));
    return mvt_want(mvt_t(c, 0) == MIR_PTR && mvt_res_is(c, MIR_PTR) && i < c->f->ncaptures,
                    "closure.cap_addr takes the environment (ptr) and yields the capture's address");
}

static const char *mvt_iface_wrap(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    if (c->in->imm.tag != MI_VTABLE) {
        return "missing vtable";
    }
    if (c->in->imm.a >= c->m->nvtables) {
        return "bad vtable";
    }
    const MirVtable *vt = &c->m->vtables[c->in->imm.a];
    return mvt_want(mvt_t(c, 0) == vt->data_ty && c->has_res &&
                        mvt_is_kind_id(c, c->res, MK_IFACE, vt->iface),
                    "iface.new and iface.borrow wrap the vtable's data type");
}

static const char *mvt_iface_view(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    return mvt_want(mvt_is_iface(c, mvt_t(c, 0)) && mvt_res_is(c, mvt_t(c, 0)),
                    "iface.view takes an interface value and yields the same type");
}

static const char *mvt_iface_is(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    if (c->in->imm.tag != MI_VTABLE) {
        return "missing vtable";
    }
    if (c->in->imm.a >= c->m->nvtables) {
        return "bad vtable";
    }
    const MirVtable *vt = &c->m->vtables[c->in->imm.a];
    return mvt_want(mvt_is_kind_id(c, mvt_t(c, 0), MK_IFACE, vt->iface) && mvt_res_is(c, MIR_BOOL),
                    "iface.is tests an interface value of the vtable's interface and yields bool");
}

static const char *mvt_iface_data(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    return mvt_want(mvt_is_iface(c, mvt_t(c, 0)) && mvt_res_is(c, MIR_PTR),
                    "iface.data takes an interface and yields ptr");
}

static const char *mvt_iface_tag(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    return mvt_want(mvt_is_iface(c, mvt_t(c, 0)) && mvt_res_is(c, MIR_INT),
                    "iface.tag takes an interface and yields int: 0 owns the box and payload, 1 only the box, 2 nothing");
}

static const char *mvt_iface_destroy(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    return mvt_want(mvt_is_iface(c, mvt_t(c, 0)) && !c->has_res,
                    "iface.destroy takes an interface and runs its payload destructor");
}

/* ---- calls ---- */

/* Operands `first..` against the parameter types `types`, reporting a count or type mismatch. */
static const char *mvt_args_match(const MvtCx *c, const char *callee, uint32_t first,
                                  const MirTy *types, uint32_t count) {
    if (c->n - first != count) {
        return ms_arena_fmt(c->v->arena, "%s takes %u arguments, found %u", callee, count, c->n - first).ptr;
    }
    for (uint32_t i = 0; i < count; i++) {
        if (mvt_t(c, first + i) != types[i]) {
            return mvt_mismatch(c, mvt_label(c, "argument", i), mvt_t(c, first + i), types[i]);
        }
    }
    return NULL;
}

static const char *mvt_param_types(const MvtCx *c, const MirParam *params, uint32_t n,
                                   const char *callee, uint32_t first) {
    if (c->n - first != n) {
        return ms_arena_fmt(c->v->arena, "%s takes %u arguments, found %u", callee, n, c->n - first).ptr;
    }
    for (uint32_t i = 0; i < n; i++) {
        if (mvt_t(c, first + i) != params[i].ty) {
            return mvt_mismatch(c, mvt_label(c, "argument", i), mvt_t(c, first + i), params[i].ty);
        }
    }
    return NULL;
}

static const char *mvt_call(const MvtCx *c) {
    if (c->in->imm.tag != MI_FUNC) {
        return "missing callee";
    }
    if (c->in->imm.a >= c->m->nfuncs) {
        return "bad callee";
    }
    const MirFunc *callee = &c->m->funcs[c->in->imm.a];
    MVT_TRY(mvt_param_types(c, callee->params, callee->nparams, mvt_name(c, callee->name), 0));
    return mvt_want(mvt_res_is(c, callee->ret), "call yields the callee's result type");
}

static const char *mvt_call_ind(const MvtCx *c) {
    if (c->n == 0) {
        return "call.ind needs a closure";
    }
    const MirTyData *fn = mvt_data(c, mvt_t(c, 0));
    if (fn->kind != MK_FN) {
        return "operand 0 must be a closure";
    }
    if (c->n - 1 != fn->nargs) {
        return ms_arena_fmt(c->v->arena, "closure takes %u arguments, found %u", fn->nargs, c->n - 1).ptr;
    }
    for (uint32_t i = 0; i < fn->nargs; i++) {
        if (mvt_t(c, i + 1) != fn->args[i]) {
            return mvt_mismatch(c, mvt_label(c, "argument", i), mvt_t(c, i + 1), fn->args[i]);
        }
    }
    return mvt_want(mvt_res_is(c, fn->elem), "call.ind yields the closure's result type");
}

static const char *mvt_call_rt(const MvtCx *c) {
    if (c->in->imm.tag != MI_EXT) {
        return "missing runtime function";
    }
    if (c->in->imm.a >= c->m->nexterns) {
        return "bad runtime function";
    }
    const MirExtern *ext = &c->m->externs[c->in->imm.a];
    MVT_TRY(mvt_param_types(c, ext->params, ext->nparams, mvt_name(c, ext->name), 0));
    return mvt_want(mvt_res_is(c, ext->ret), "call.rt yields the declared result type");
}

static const char *mvt_call_method(const MvtCx *c) {
    const MirImm *im = &c->in->imm;
    if (im->tag != MI_METHOD) {
        return "missing method";
    }
    if (im->a >= c->m->nifaces || im->b >= c->m->ifaces[im->a].nmethods) {
        return "bad method";
    }
    const MirMethodSig *sig = &c->m->ifaces[im->a].methods[im->b];
    if (c->n == 0 || !mvt_is_kind_id(c, mvt_t(c, 0), MK_IFACE, im->a)) {
        return "operand 0 must be the interface value";
    }
    MVT_TRY(mvt_args_match(c, mvt_name(c, sig->name), 1, sig->params, sig->nparams));
    return mvt_want(mvt_res_is(c, sig->ret), "call.method yields the method's result type");
}

/* ---- ownership ---- */

static const char *mvt_clone(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    /* Copying a borrowing variant into itself would own what it must not drop: use alt.own. */
    bool ok = mvt_res_is(c, mvt_t(c, 0)) && mvt_needs_drop(c, mvt_t(c, 0)) &&
              !mvt_alt_has_borrowed_cases(c, mvt_t(c, 0));
    return mvt_want(ok, "copy duplicates a droppable value");
}

static const char *mvt_alt_own(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    if (mvt_kind(c, mvt_t(c, 0)) != MK_ALT || !c->has_res) {
        return "alt.own takes a borrowing variant";
    }
    if (mvt_kind(c, c->res) != MK_ALT) {
        return "alt.own yields an alternative";
    }
    return mvt_want(mvt_plain_of(c) && mvt_needs_drop(c, c->res),
                    "alt.own copies a borrowing variant into its ordinary alternative");
}

static const char *mvt_move_out(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    return mvt_want(mvt_res_is(c, mvt_t(c, 0)) && mvt_needs_drop(c, mvt_t(c, 0)),
                    "move.out takes ownership of a droppable value");
}

static const char *mvt_drop(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    return mvt_want(mvt_needs_drop(c, mvt_t(c, 0)), "drop takes a droppable value");
}

static const char *mvt_one_operand(const MvtCx *c) { return mvt_arity(c, 1); }

static const char *mvt_drop_if(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 2));
    return mvt_want(mvt_t(c, 0) == MIR_BOOL && mvt_needs_drop(c, mvt_t(c, 1)),
                    "drop.if takes a flag and a droppable value");
}

/* ---- raw memory ---- */

static const char *mvt_slot(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 0));
    return mvt_want(c->in->imm.tag == MI_TY && mvt_res_is(c, MIR_PTR), "slot yields ptr");
}

static const char *mvt_list_addr(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 2));
    MirTy elem = 0;
    return mvt_want(mvt_list_elem(c, mvt_t(c, 0), &elem) && mvt_t(c, 1) == MIR_INT &&
                        mvt_res_is(c, MIR_PTR),
                    "list.addr takes a list and an index and yields a ptr to the element");
}

static bool mvt_access_width(const MirImm *im) {
    return im->tag == MI_INT && (im->i == 1 || im->i == 2 || im->i == 4 || im->i == 8);
}

static const char *mvt_ptr_load_u(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    return mvt_want(mvt_t(c, 0) == MIR_PTR && mvt_access_width(&c->in->imm) && mvt_res_is(c, MIR_INT),
                    "ptr.loadu reads 1, 2, 4 or 8 unaligned bytes at a ptr into an int");
}

static const char *mvt_ptr_store_u(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 2));
    return mvt_want(mvt_t(c, 0) == MIR_PTR && mvt_t(c, 1) == MIR_INT &&
                        mvt_access_width(&c->in->imm) && !c->has_res,
                    "ptr.storeu writes the low 1, 2, 4 or 8 bytes of an int unaligned at a ptr");
}

static const char *mvt_ptr_null(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 0));
    return mvt_want(mvt_res_is(c, MIR_PTR), "ptr.null yields a ptr");
}

static const char *mvt_ptr_add(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 2));
    return mvt_want(mvt_t(c, 0) == MIR_PTR && mvt_t(c, 1) == MIR_INT && mvt_res_is(c, MIR_PTR),
                    "ptr.add takes a ptr and a byte offset and yields a ptr");
}

static const char *mvt_ptr_is_null(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    return mvt_want(mvt_t(c, 0) == MIR_PTR && mvt_res_is(c, MIR_BOOL),
                    "ptr.is_null tests a ptr and yields bool");
}

static const char *mvt_ptr_field(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    const MirImm *im = &c->in->imm;
    if (im->tag != MI_FIELD) {
        return "missing field";
    }
    if (im->a >= c->m->ntype_defs) {
        return "bad type";
    }
    if (im->b >= c->m->type_defs[im->a].nfields) {
        return "bad field index";
    }
    return mvt_want(mvt_t(c, 0) == MIR_PTR && mvt_res_is(c, MIR_PTR),
                    "ptr.field takes a ptr and yields a ptr");
}

static const char *mvt_load(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    if (c->in->imm.tag != MI_TY) {
        return "missing type";
    }
    return mvt_want(mvt_t(c, 0) == MIR_PTR && mvt_res_is(c, c->in->imm.a),
                    "load reads a value through a ptr; a droppable result is a borrow");
}

static const char *mvt_take(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    if (c->in->imm.tag != MI_TY) {
        return "missing type";
    }
    return mvt_want(mvt_t(c, 0) == MIR_PTR && mvt_res_is(c, c->in->imm.a),
                    "take moves a value out of memory through a ptr; the result is owned");
}

static const char *mvt_put(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 2));
    return mvt_want(mvt_t(c, 0) == MIR_PTR, "put moves an owned value into memory through a ptr");
}

static const char *mvt_store(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 2));
    return mvt_want(mvt_t(c, 0) == MIR_PTR,
                    "store writes a value through a ptr; the memory does not own a droppable value, it holds a borrow");
}

static const char *mvt_func_addr(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 0));
    if (c->in->imm.tag != MI_FUNC) {
        return "missing function";
    }
    return mvt_want(c->in->imm.a < c->m->nfuncs && mvt_res_is(c, MIR_PTR),
                    "func.addr yields the ptr of a function");
}

static const char *mvt_type_desc(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 0));
    return mvt_want(c->in->imm.tag == MI_TY && mvt_res_is(c, MIR_PTR), "typedesc yields ptr");
}

/* ---- runtime services ---- */

static const char *mvt_no_operands(const MvtCx *c) { return mvt_arity(c, 0); }

static const char *mvt_stack_low(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 0));
    return mvt_want(mvt_res_is(c, MIR_BOOL),
                    "stack.low yields whether the stack pointer is below the stack segment's limit");
}

static const char *mvt_stack_near(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 0));
    return mvt_want(c->in->imm.tag == MI_INT && c->in->imm.i >= 0 && mvt_res_is(c, MIR_BOOL),
                    "stack.near N yields whether the stack pointer is within N bytes of the stack segment's limit");
}

static const char *mvt_cleanup_run(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    return mvt_want(mvt_t(c, 0) == MIR_INT, "cleanup.run takes the handle returned by cleanup.push");
}

static const char *mvt_cleanup_push(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    if (c->in->imm.tag != MI_FUNC) {
        return "missing closer";
    }
    if (c->in->imm.a >= c->m->nfuncs) {
        return "bad closer";
    }
    const MirFunc *callee = &c->m->funcs[c->in->imm.a];
    return mvt_want(callee->nparams == 1 && callee->params[0].ty == mvt_t(c, 0) &&
                        mvt_res_is(c, MIR_INT),
                    "closer takes the registered value; cleanup.push yields an int handle");
}

static const char *mvt_global_get(const MvtCx *c) {
    if (c->in->imm.tag != MI_GLOBAL) {
        return "missing global";
    }
    if (c->in->imm.a >= c->m->nglobals) {
        return "bad global";
    }
    MVT_TRY(mvt_arity(c, 0));
    return mvt_want(mvt_res_is(c, c->m->globals[c->in->imm.a].ty),
                    "global.get yields the global's type");
}

static const char *mvt_global_set(const MvtCx *c) {
    if (c->in->imm.tag != MI_GLOBAL) {
        return "missing global";
    }
    if (c->in->imm.a >= c->m->nglobals) {
        return "bad global";
    }
    MVT_TRY(mvt_arity(c, 1));
    return mvt_want(mvt_t(c, 0) == c->m->globals[c->in->imm.a].ty,
                    "stored value must have the global's type");
}

/* ---- scope markers: `begin S P`, `own v S K`, `end S` ---- */

static const char *mvt_scope_marker(const MvtCx *c) {
    if (c->in->imm.tag != MI_SCOPE) {
        return "a scope marker takes scope numbers";
    }
    MVT_TRY(mvt_want(!c->has_res, "a scope marker has no result"));
    if (c->in->op != MOP_ScopeOwn) {
        return mvt_arity(c, 0);
    }
    MVT_TRY(mvt_arity(c, 1));
    if (c->in->imm.b >= 2 && mvt_t(c, 0) == MIR_PTR) { // a close function (its index plus two) runs on a slot address
        return NULL;
    }
    return mvt_want(mvt_needs_drop(c, mvt_t(c, 0)), "scope.own takes a value that needs a drop");
}

static const char *mvt_scope_disown(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    return mvt_want(!c->has_res, "scope.disown has no result");
}

static const char *mvt_scope_mark(const MvtCx *c) {
    MVT_TRY(mvt_arity(c, 1));
    return mvt_want(!c->has_res, "scope.mark has no result");
}

/* ---- dispatch ---- */

static const MvtRule mvt_rules[MOP_COUNT] = {
    [MOP_IConst] = mvt_iconst, [MOP_FConst] = mvt_fconst, [MOP_BConst] = mvt_bconst,
    [MOP_VoidConst] = mvt_voidconst, [MOP_Undef] = mvt_undef, [MOP_StrLit] = mvt_strlit,
    [MOP_BytesLit] = mvt_byteslit,
    [MOP_IAdd] = mvt_int_binary, [MOP_ISub] = mvt_int_binary, [MOP_IMul] = mvt_int_binary,
    [MOP_IAddChk] = mvt_int_binary, [MOP_ISubChk] = mvt_int_binary, [MOP_IMulChk] = mvt_int_binary,
    [MOP_UAddChk] = mvt_int_binary, [MOP_USubChk] = mvt_int_binary, [MOP_UMulChk] = mvt_int_binary,
    [MOP_SDivChk] = mvt_int_binary, [MOP_SRemChk] = mvt_int_binary, [MOP_SDiv] = mvt_int_binary,
    [MOP_SRem] = mvt_int_binary, [MOP_Shl] = mvt_int_binary, [MOP_Sshr] = mvt_int_binary,
    [MOP_Ushr] = mvt_int_binary, [MOP_Rotl] = mvt_int_binary, [MOP_Rotr] = mvt_int_binary,
    [MOP_UMulHi] = mvt_int_binary,
    [MOP_IAddOverflow] = mvt_overflow_flag, [MOP_IMulOverflow] = mvt_overflow_flag,
    [MOP_IntOverflowIf] = mvt_overflow_if, [MOP_NarrowChk] = mvt_narrow_chk, [MOP_Conv] = mvt_conv,
    [MOP_INarrowOpt] = mvt_inarrow_opt, [MOP_F32Round] = mvt_f32_round,
    [MOP_INeg] = mvt_ineg, [MOP_INegChk] = mvt_ineg,
    [MOP_And] = mvt_bitwise, [MOP_Or] = mvt_bitwise, [MOP_Xor] = mvt_bitwise,
    [MOP_Clz] = mvt_bit_count, [MOP_Ctz] = mvt_bit_count, [MOP_Popcnt] = mvt_bit_count,
    [MOP_Not] = mvt_not,
    [MOP_UICmp] = mvt_uicmp, [MOP_ICmp] = mvt_icmp, [MOP_FCmp] = mvt_fcmp, [MOP_Select] = mvt_select,
    [MOP_FAdd] = mvt_float_binary, [MOP_FSub] = mvt_float_binary, [MOP_FMul] = mvt_float_binary,
    [MOP_FDiv] = mvt_float_binary,
    [MOP_FNeg] = mvt_float_unary, [MOP_FSqrt] = mvt_float_unary, [MOP_FAbs] = mvt_float_unary,
    [MOP_FFloor] = mvt_float_unary, [MOP_FCeil] = mvt_float_unary, [MOP_FTrunc] = mvt_float_unary,
    [MOP_I2F] = mvt_i2f, [MOP_F2IOpt] = mvt_f2i_opt, [MOP_B2I] = mvt_b2i,
    [MOP_TypeNew] = mvt_type_new, [MOP_TypeGet] = mvt_type_field, [MOP_TypeSet] = mvt_type_field,
    [MOP_TypeFill] = mvt_type_field, [MOP_TypeRelease] = mvt_type_release,
    [MOP_AltNew] = mvt_alt_ctor, [MOP_AltView] = mvt_alt_ctor, [MOP_AltPlain] = mvt_alt_plain,
    [MOP_AltTag] = mvt_alt_tag, [MOP_AltRelease] = mvt_alt_release, [MOP_AltGet] = mvt_alt_field,
    [MOP_AltUnbox] = mvt_alt_field, [MOP_AltTake] = mvt_alt_field,
    [MOP_ListNew] = mvt_list_new, [MOP_ListLit] = mvt_list_lit, [MOP_ListConst] = mvt_list_const,
    [MOP_ListConstView] = mvt_list_const, [MOP_ListLen] = mvt_list_len,
    [MOP_ListGet] = mvt_list_get, [MOP_ListGetNn] = mvt_list_get, [MOP_ListGetU] = mvt_list_get,
    [MOP_ListTake] = mvt_list_get, [MOP_ListRelease] = mvt_list_release,
    [MOP_ListSet] = mvt_list_store, [MOP_ListSetNn] = mvt_list_store, [MOP_ListSetU] = mvt_list_store,
    [MOP_ListFill] = mvt_list_store, [MOP_ListFillU] = mvt_list_store,
    [MOP_ListPush] = mvt_list_push, [MOP_ListPushU] = mvt_list_push, [MOP_ListCap] = mvt_list_cap,
    [MOP_ListGrow] = mvt_list_grow, [MOP_ListDropLast] = mvt_list_drop_last,
    [MOP_OptSome] = mvt_opt_wrap, [MOP_OptView] = mvt_opt_wrap, [MOP_OptViewAt] = mvt_opt_view_at,
    [MOP_OptNone] = mvt_opt_none, [MOP_OptNoneOwned] = mvt_opt_none, [MOP_OptIsSome] = mvt_opt_is_some,
    [MOP_OptGet] = mvt_opt_payload, [MOP_OptUnwrap] = mvt_opt_payload, [MOP_OptUnbox] = mvt_opt_payload,
    [MOP_OptAddr] = mvt_opt_addr,
    [MOP_StrLen] = mvt_str_len, [MOP_StrByte] = mvt_str_byte, [MOP_StrAscii] = mvt_str_ascii,
    [MOP_StrAsciiLen] = mvt_str_ascii_len, [MOP_StrEqLit] = mvt_str_eq_lit,
    [MOP_StrBytes] = mvt_str_bytes, [MOP_BytesPush] = mvt_bytes_push,
    [MOP_ClosureNew] = mvt_closure_new, [MOP_ClosureCap] = mvt_closure_cap,
    [MOP_ClosureCapAddr] = mvt_closure_cap_addr, [MOP_IfaceNew] = mvt_iface_wrap,
    [MOP_IfaceBorrow] = mvt_iface_wrap, [MOP_IfaceView] = mvt_iface_view, [MOP_IfaceIs] = mvt_iface_is,
    [MOP_IfaceTag] = mvt_iface_tag, [MOP_IfaceDestroy] = mvt_iface_destroy,
    [MOP_IfaceData] = mvt_iface_data,
    [MOP_Call] = mvt_call, [MOP_CallInd] = mvt_call_ind, [MOP_CallRt] = mvt_call_rt,
    [MOP_CallMethod] = mvt_call_method,
    [MOP_Clone] = mvt_clone, [MOP_AltOwn] = mvt_alt_own, [MOP_MoveOut] = mvt_move_out,
    [MOP_Drop] = mvt_drop, [MOP_Forget] = mvt_one_operand, [MOP_DropIf] = mvt_drop_if,
    [MOP_Free] = mvt_one_operand,
    [MOP_Slot] = mvt_slot, [MOP_ListAddr] = mvt_list_addr, [MOP_ListAddrU] = mvt_list_addr,
    [MOP_PtrIsNull] = mvt_ptr_is_null, [MOP_PtrAdd] = mvt_ptr_add, [MOP_PtrNull] = mvt_ptr_null,
    [MOP_PtrLoadU] = mvt_ptr_load_u, [MOP_PtrStoreU] = mvt_ptr_store_u, [MOP_PtrField] = mvt_ptr_field,
    [MOP_Load] = mvt_load, [MOP_Take] = mvt_take, [MOP_Put] = mvt_put, [MOP_Store] = mvt_store,
    [MOP_FuncAddr] = mvt_func_addr, [MOP_TypeDesc] = mvt_type_desc,
    [MOP_Poll] = mvt_no_operands, [MOP_DepthEnter] = mvt_no_operands,
    [MOP_DepthLeave] = mvt_no_operands, [MOP_StackLow] = mvt_stack_low,
    [MOP_StackNear] = mvt_stack_near, [MOP_CleanupRun] = mvt_cleanup_run,
    [MOP_CleanupPush] = mvt_cleanup_push, [MOP_GlobalGet] = mvt_global_get,
    [MOP_GlobalSet] = mvt_global_set,
    [MOP_ScopeBegin] = mvt_scope_marker, [MOP_ScopeOwn] = mvt_scope_marker,
    [MOP_ScopeEnd] = mvt_scope_marker, [MOP_ScopeDisown] = mvt_scope_disown,
    [MOP_ScopeMark] = mvt_scope_mark,
};

const char *mir_verify_inst_types(const MirVerifyCx *cx, const MirInst *in) {
    MvtCx c = {.v = cx,
               .m = cx->m,
               .f = cx->f,
               .in = in,
               .n = in->nargs,
               .has_res = in->res != MIR_NONE,
               .res = in->res != MIR_NONE ? cx->f->values[in->res] : 0};
    return mvt_rules[in->op](&c);
}

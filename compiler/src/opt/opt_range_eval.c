/* range: the transfer function, the interval an instruction's result lies in given the intervals of
 * its operands. Port of `eval`, `arithmetic`, `bitwise` and `other_ops` in
 * the former Rust crates/ms-mir/src/opt/range.rs. */
#include "opt/opt_range.h"

enum { RGE_LEN_MAX_SHIFT = 47 }; /* no address space holds more list elements than 2^47 */

static RgItv rg_type_top(MirTy ty) { return ty == MIR_BOOL ? (RgItv){0, 1} : RG_TOP; }

/* Whether the unchecked operation that defines `v` was proved not to wrap. */
static bool rg_is_exact(const MirFunc *f, MirValue v) {
    return (v >> 6) < f->nexact && ((f->exact[v >> 6] >> (v & 63)) & 1) != 0;
}

/* The result of an operation that is exact when checked (or proved so) and wraps to top otherwise. */
static RgItv rg_wrapped(bool exact, RgWide lo, RgWide hi) {
    return exact ? rg_clamp(lo, hi) : rg_exact_itv(lo, hi);
}

/* ---- arithmetic ---- */

static bool rg_eval_add_sub_mul(const RgFa *fa, const MirInst *inst, const RgEnv *env, RgItv *out) {
    RgItv x, y;
    if (!rg_get(fa, inst->args[0], env, &x) || !rg_get(fa, inst->args[1], env, &y)) {
        return false;
    }
    const bool checked = inst->op == MOP_IAddChk || inst->op == MOP_ISubChk || inst->op == MOP_IMulChk;
    const bool exact = checked || rg_is_exact(fa->f, inst->res);
    RgWide lo, hi;
    if (inst->op == MOP_IAdd || inst->op == MOP_IAddChk) {
        lo = (RgWide)x.lo + y.lo;
        hi = (RgWide)x.hi + y.hi;
    } else if (inst->op == MOP_ISub || inst->op == MOP_ISubChk) {
        lo = (RgWide)x.lo - y.hi;
        hi = (RgWide)x.hi - y.lo;
    } else {
        rg_corners(RG_MUL, x, y, &lo, &hi);
    }
    *out = rg_wrapped(exact, lo, hi);
    return true;
}

static bool rg_eval_unsigned(const RgFa *fa, const MirInst *inst, const RgEnv *env, RgItv *out) {
    RgItv x, y;
    if (!rg_get(fa, inst->args[0], env, &x) || !rg_get(fa, inst->args[1], env, &y)) {
        return false;
    }
    if (x.lo < 0 || y.lo < 0) {
        *out = RG_TOP;
        return true;
    }
    RgWide lo, hi;
    if (inst->op == MOP_UAddChk) {
        lo = (RgWide)x.lo + y.lo;
        hi = (RgWide)x.hi + y.hi;
    } else if (inst->op == MOP_USubChk) {
        /* A faulting subtraction leaves a difference between zero and `x`. */
        lo = (RgWide)x.lo - y.hi;
        lo = lo > 0 ? lo : 0;
        hi = x.hi;
    } else {
        rg_corners(RG_MUL, x, y, &lo, &hi);
    }
    *out = rg_exact_itv(lo, hi);
    return true;
}

static bool rg_eval_div(const RgFa *fa, const MirInst *inst, const RgEnv *env, RgItv *out) {
    RgItv x, y;
    if (!rg_get(fa, inst->args[0], env, &x) || !rg_get(fa, inst->args[1], env, &y)) {
        return false;
    }
    if (inst->op == MOP_SDiv || inst->op == MOP_SDivChk) {
        RgWide lo, hi;
        if (y.lo > 0 || y.hi < 0) {
            rg_corners(RG_DIV, x, y, &lo, &hi);
            *out = rg_clamp(lo, hi);
        } else {
            *out = RG_TOP;
        }
        return true;
    }
    const RgWide ylo = y.lo < 0 ? -(RgWide)y.lo : y.lo, yhi = y.hi < 0 ? -(RgWide)y.hi : y.hi;
    const RgWide m = ylo > yhi ? ylo : yhi;
    if (m == 0) {
        *out = RG_TOP;
        return true;
    }
    RgWide lo = -(m - 1), hi = m - 1;
    if (x.lo >= 0) {
        lo = 0;
        hi = x.hi < hi ? x.hi : hi;
    } else if (x.hi <= 0) {
        hi = 0;
        lo = x.lo > lo ? x.lo : lo;
    }
    *out = rg_clamp(lo, hi);
    return true;
}

static bool rg_eval_neg(const RgFa *fa, const MirInst *inst, const RgEnv *env, RgItv *out) {
    RgItv x;
    if (!rg_get(fa, inst->args[0], env, &x)) {
        return false;
    }
    *out = rg_wrapped(inst->op == MOP_INegChk || rg_is_exact(fa->f, inst->res), -(RgWide)x.hi, -(RgWide)x.lo);
    return true;
}

/* Constants, additions, multiplications and divisions. */
static bool rg_eval_arithmetic(const RgFa *fa, const MirInst *inst, const RgEnv *env, RgItv top,
                            RgItv *out) {
    switch ((MirOp)inst->op) {
    case MOP_IConst:
        *out = inst->imm.tag == MI_INT ? rg_point(inst->imm.i) : top;
        return true;
    case MOP_BConst:
        *out = inst->imm.tag == MI_BOOL ? rg_point(inst->imm.a != 0 ? 1 : 0) : top;
        return true;
    case MOP_IAdd: case MOP_IAddChk: case MOP_ISub: case MOP_ISubChk: case MOP_IMul:
    case MOP_IMulChk:
        return rg_eval_add_sub_mul(fa, inst, env, out);
    case MOP_INeg: case MOP_INegChk:
        return rg_eval_neg(fa, inst, env, out);
    case MOP_UAddChk: case MOP_USubChk: case MOP_UMulChk:
        return rg_eval_unsigned(fa, inst, env, out);
    default:
        return rg_eval_div(fa, inst, env, out);
    }
}

/* ---- bitwise ---- */

/* Boolean `and`, `or`, `xor` and `not`. */
static bool rg_eval_bool_logic(const RgFa *fa, const MirInst *inst, const RgEnv *env, RgItv *out) {
    RgItv x, y = rg_point(0);
    if (!rg_get(fa, inst->args[0], env, &x) || (inst->op != MOP_Not && !rg_get(fa, inst->args[1], env, &y))) {
        return false;
    }
    const bool points = rg_is_point(x) && rg_is_point(y);
    *out = RG_BOOL;
    switch ((MirOp)inst->op) {
    case MOP_And:
        if (points) {
            *out = rg_point(x.lo & y.lo);
        } else if (x.hi == 0 || y.hi == 0) {
            *out = rg_point(0);
        }
        break;
    case MOP_Or:
        if (points) {
            *out = rg_point(x.lo | y.lo);
        } else if (x.lo == 1 || y.lo == 1) {
            *out = rg_point(1);
        }
        break;
    case MOP_Xor:
        if (points) {
            *out = rg_point(x.lo ^ y.lo);
        }
        break;
    default: /* not */
        if (rg_is_point(x)) {
            *out = rg_point(1 - x.lo);
        }
        break;
    }
    return true;
}

/* `and`, `or` and `xor` of integers: non-negative operands give a non-negative result. */
static bool rg_eval_int_bits(const RgFa *fa, const MirInst *inst, const RgEnv *env, RgItv *out) {
    RgItv x, y;
    if (!rg_get(fa, inst->args[0], env, &x) || !rg_get(fa, inst->args[1], env, &y)) {
        return false;
    }
    *out = RG_TOP;
    if (inst->op == MOP_And) {
        if (x.lo >= 0 && y.lo >= 0) {
            *out = (RgItv){0, x.hi < y.hi ? x.hi : y.hi};
        } else if (x.lo >= 0) {
            *out = (RgItv){0, x.hi};
        } else if (y.lo >= 0) {
            *out = (RgItv){0, y.hi};
        }
    } else if (x.lo >= 0 && y.lo >= 0) {
        const uint64_t m = (uint64_t)(x.hi > y.hi ? x.hi : y.hi);
        *out = (RgItv){0, m == 0 ? 0 : (int64_t)(UINT64_MAX >> __builtin_clzll(m))};
    }
    return true;
}

static bool rg_eval_shift(const RgFa *fa, const MirInst *inst, const RgEnv *env, RgItv *out) {
    RgItv x, y;
    if (!rg_get(fa, inst->args[0], env, &x) || !rg_get(fa, inst->args[1], env, &y)) {
        return false;
    }
    *out = RG_TOP;
    if (inst->op == MOP_Shl && rg_is_point(y) && y.lo >= 0 && y.lo < 63) {
        const RgWide scale = (RgWide)1 << y.lo;
        *out = rg_wrapped(rg_is_exact(fa->f, inst->res), (RgWide)x.lo * scale, (RgWide)x.hi * scale);
    } else if (inst->op == MOP_Sshr && rg_is_point(y) && y.lo >= 0 && y.lo < 64) {
        *out = (RgItv){x.lo >> y.lo, x.hi >> y.lo};
    }
    return true;
}

/* Boolean and bitwise operations and shifts. */
static bool rg_eval_bitwise(const RgFa *fa, const MirInst *inst, const RgEnv *env, MirTy ty,
                         RgItv *out) {
    switch ((MirOp)inst->op) {
    case MOP_And: case MOP_Or: case MOP_Xor:
        return ty == MIR_BOOL ? rg_eval_bool_logic(fa, inst, env, out) : rg_eval_int_bits(fa, inst, env, out);
    case MOP_Not:
        return rg_eval_bool_logic(fa, inst, env, out);
    default:
        return rg_eval_shift(fa, inst, env, out);
    }
}

/* ---- the rest ---- */

/* The range of values an integer type holds, when it lies within `i64`. */
static bool rg_int_range(const MirModule *m, MirTy ty, RgItv *out) {
    switch ((MirTyKind)mir_ty_data(m, ty)->kind) {
    case MK_INT: *out = RG_TOP; return true;
    case MK_INT8: *out = (RgItv){INT8_MIN, INT8_MAX}; return true;
    case MK_INT16: *out = (RgItv){INT16_MIN, INT16_MAX}; return true;
    case MK_INT32: *out = (RgItv){INT32_MIN, INT32_MAX}; return true;
    case MK_UINT8: *out = (RgItv){0, UINT8_MAX}; return true;
    case MK_UINT16: *out = (RgItv){0, UINT16_MAX}; return true;
    case MK_UINT32: *out = (RgItv){0, UINT32_MAX}; return true;
    default: return false; /* `UInt64` passes `i64::MAX`; other types are not integers */
    }
}

static bool rg_eval_cmp(const RgFa *fa, const MirInst *inst, const RgEnv *env, RgItv top, RgItv *out) {
    if (inst->imm.tag != MI_CC || !rg_tracked(fa->f->values[inst->args[0]]) ||
        !rg_tracked(fa->f->values[inst->args[1]])) {
        *out = top;
        return true;
    }
    RgItv x, y;
    if (!rg_get(fa, inst->args[0], env, &x) || !rg_get(fa, inst->args[1], env, &y)) {
        return false;
    }
    bool holds = false;
    const bool known = rg_decide(fa, (MirCc)inst->imm.a, inst->args[0], inst->args[1], x, y, env, &holds);
    *out = known ? rg_point(holds ? 1 : 0) : RG_BOOL;
    return true;
}

static bool rg_eval_select(const RgFa *fa, const MirInst *inst, const RgEnv *env, RgItv *out) {
    RgItv c, x, y;
    if (!rg_get(fa, inst->args[0], env, &c) || !rg_get(fa, inst->args[1], env, &x) ||
        !rg_get(fa, inst->args[2], env, &y)) {
        return false;
    }
    if (rg_is_point(c)) {
        *out = c.lo != 0 ? x : y;
    } else {
        *out = rg_join(x, y);
    }
    return true;
}

/* A narrow integer widened to `Int` keeps the range of its type. */
static RgItv rg_eval_conv(const RgFa *fa, const MirInst *inst, MirTy ty, RgItv top) {
    RgItv r;
    if (ty == MIR_INT && rg_int_range(fa->m, fa->f->values[inst->args[0]], &r)) {
        return r;
    }
    return top;
}

static RgItv rg_eval_alt_tag(const RgFa *fa, const MirInst *inst, RgItv top) {
    const MirTyData *d = mir_ty_data(fa->m, fa->f->values[inst->args[0]]);
    if (d->kind != MK_ALT) {
        return top;
    }
    const int64_t n = fa->m->alts[d->id].ncases;
    return (RgItv){0, n - 1 > 0 ? n - 1 : 0};
}

/* Comparisons, `select`, lengths, bytes and alternative tags. */
static bool rg_eval_other(const RgFa *fa, const MirInst *inst, const RgEnv *env, MirTy ty, RgItv top,
                       RgItv *out) {
    const RgItv len = {0, (int64_t)1 << RGE_LEN_MAX_SHIFT};
    int64_t n = 0;
    switch ((MirOp)inst->op) {
    case MOP_ICmp:
        return rg_eval_cmp(fa, inst, env, top, out);
    case MOP_B2I: /* a runtime status is a `u8` typed `bool`: the widened value is not 0 or 1 */
        *out = (RgItv){0, 255};
        return true;
    case MOP_Select:
        return rg_eval_select(fa, inst, env, out);
    case MOP_ListLen:
        *out = rg_list_length(fa, inst->args[0], &n) ? rg_point(n) : len;
        return true;
    case MOP_ListGet: case MOP_ListGetNn: case MOP_ListGetU:
        *out = fa->byte_lists[inst->args[0]] != 0 ? (RgItv){0, 255} : top;
        return true;
    case MOP_Conv:
        *out = rg_eval_conv(fa, inst, ty, top);
        return true;
    case MOP_StrLen: case MOP_StrBytes:
        *out = len;
        return true;
    case MOP_StrAsciiLen:
        *out = (RgItv){-1, len.hi};
        return true;
    default: /* alt.tag */
        *out = rg_eval_alt_tag(fa, inst, top);
        return true;
    }
}

/* The interval of the result of `inst`; false when an operand has no interval yet or the result is
 * not tracked. */
bool rg_eval(const RgFa *fa, const MirInst *inst, const RgEnv *env, RgItv *out) {
    if (inst->res == MIR_NONE) {
        return false;
    }
    const MirTy ty = fa->f->values[inst->res];
    if (!rg_tracked(ty)) {
        return false;
    }
    const RgItv top = rg_type_top(ty);
    switch ((MirOp)inst->op) {
    case MOP_IConst: case MOP_BConst: case MOP_IAdd: case MOP_IAddChk: case MOP_ISub:
    case MOP_ISubChk: case MOP_IMul: case MOP_IMulChk: case MOP_INeg: case MOP_INegChk:
    case MOP_UAddChk: case MOP_USubChk: case MOP_UMulChk: case MOP_SDiv: case MOP_SDivChk:
    case MOP_SRem: case MOP_SRemChk:
        return rg_eval_arithmetic(fa, inst, env, top, out);
    case MOP_And: case MOP_Or: case MOP_Xor: case MOP_Not: case MOP_Shl: case MOP_Sshr:
        return rg_eval_bitwise(fa, inst, env, ty, out);
    case MOP_ICmp: case MOP_B2I: case MOP_Select: case MOP_ListLen: case MOP_ListGet:
    case MOP_ListGetNn: case MOP_ListGetU: case MOP_StrLen: case MOP_StrAsciiLen:
    case MOP_StrBytes: case MOP_Conv: case MOP_AltTag:
        return rg_eval_other(fa, inst, env, ty, top, out);
    default:
        *out = top;
        return true;
    }
}

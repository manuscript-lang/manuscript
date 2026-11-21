/* What each MIR instruction does when interpreted. `ip_step` routes an instruction to the
 * function for its family. An operand of the wrong kind, an immediate of the wrong tag or a
 * missing operand is an internal fault, never undefined behaviour: the interpreter also runs
 * modules the verifier has not seen. */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "mir/mir_interp_impl.h"
#include "ms_rt/chars.h"

#define IP_I64_RANGE 9223372036854775808.0 /* 2^63: Int values are the floats in [-2^63, 2^63) */

/* ---- errors ---- */

IpFlow ip_raise(MirInterp *it, MirFault kind, const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    it->raw.kind = kind;
    it->raw.message = ms_arena_vfmt(&it->arena, fmt, args);
    it->raw.fuel = false;
    va_end(args);
    return IP_RAISE;
}

/* A fault whose message is arbitrary bytes (may hold NUL), copied into the arena. */
IpFlow ip_raise_text(MirInterp *it, MirFault kind, MsStr message) {
    it->raw.kind = kind;
    it->raw.message = (MsStr){.ptr = ms_arena_strndup(&it->arena, message.ptr, message.len),
                              .len = message.len};
    it->raw.fuel = false;
    return IP_RAISE;
}

IpFlow ip_internal(MirInterp *it, const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    MsStr detail = ms_arena_vfmt(&it->arena, fmt, args);
    va_end(args);
    return ip_raise(it, MF_UNREACHABLE, "interpreter: %.*s", (int)detail.len, detail.ptr);
}

const char *ip_depth_message(void) {
    return "call depth limit exceeded (200000 nested calls); check the recursion for a missing "
           "base case, or iterate instead";
}

static IpFlow ip_overflow(MirInterp *it) {
    return ip_raise(it, MF_INT_OVERFLOW, "integer overflow");
}

static IpFlow ip_div0(MirInterp *it) {
    return ip_raise(it, MF_DIV_BY_ZERO, "division by zero");
}

/* ---- operands ---- */

static const char *ip_op_name(const IpCtx *c) {
    return mir_op_info[c->inst->op].name;
}

/* Operand `i` of the instruction, or a void stand-in when it has none. */
static MirVal *ip_slot(IpCtx *c, uint32_t i) {
    if (i >= c->inst->nargs || c->inst->args[i] >= c->func->nvalues) {
        c->it->dummy = ip_void();
        return &c->it->dummy;
    }
    return &c->regs[c->inst->args[i]];
}

static IpFlow ip_wrong(IpCtx *c, const char *expected) {
    return ip_internal(c->it, "%s: expected %s", ip_op_name(c), expected);
}

static bool ip_int_at(IpCtx *c, uint32_t i, int64_t *out, IpFlow *flow) {
    const MirVal *v = ip_slot(c, i);
    if (v->tag != MV_INT) {
        *flow = ip_wrong(c, "int");
        return false;
    }
    *out = v->as.i;
    return true;
}

static bool ip_float_at(IpCtx *c, uint32_t i, double *out, IpFlow *flow) {
    const MirVal *v = ip_slot(c, i);
    if (v->tag != MV_FLOAT) {
        *flow = ip_wrong(c, "float");
        return false;
    }
    *out = v->as.f;
    return true;
}

static bool ip_bool_at(IpCtx *c, uint32_t i, bool *out, IpFlow *flow) {
    const MirVal *v = ip_slot(c, i);
    if (v->tag != MV_BOOL) {
        *flow = ip_wrong(c, "bool");
        return false;
    }
    *out = v->as.i != 0;
    return true;
}

/* Stores the instruction's result, if it has one; the old content of the register goes. */
static IpFlow ip_set(IpCtx *c, MirVal value) {
    if (c->inst->res == MIR_NONE || c->inst->res >= c->func->nvalues) {
        mir_val_release(&value);
        return IP_NEXT;
    }
    mir_val_release(&c->regs[c->inst->res]);
    c->regs[c->inst->res] = value;
    return IP_NEXT;
}

static bool ip_needs_drop(MirInterp *it, MirTy ty) {
    if (ty >= it->module->types.len) {
        return false;
    }
    if (it->drop_cache[ty] == 0) {
        it->drop_cache[ty] = mir_needs_drop(it->module, ty) ? 2 : 1;
    }
    return it->drop_cache[ty] == 2;
}

/* Reads an operand: moves it out when the position owns a droppable value, so that a unique
 * owner keeps mutating in place; shares it otherwise. */
MirVal ip_take_arg(MirInterp *it, const MirFunc *func, MirVal *regs, uint32_t value, bool own) {
    if (value >= func->nvalues) {
        return ip_void();
    }
    if (own && ip_needs_drop(it, func->values[value])) {
        MirVal moved = regs[value];
        regs[value] = ip_void();
        return moved;
    }
    return ip_retain(regs[value]);
}

static MirVal ip_arg(IpCtx *c, uint32_t i, bool own) {
    if (i >= c->inst->nargs) {
        return ip_void();
    }
    return ip_take_arg(c->it, c->func, c->regs, c->inst->args[i], own);
}

/* A block holding every operand, moved in. */
static MirBlob *ip_take_all(IpCtx *c) {
    MirBlob *blob = ip_blob_new(c->inst->nargs);
    for (uint32_t i = 0; i < c->inst->nargs; i++) {
        blob->items[i] = ip_arg(c, i, true);
    }
    return blob;
}

static MirTyKind ip_kind_of(const IpCtx *c, MirTy ty) {
    return ty < c->it->module->types.len ? (MirTyKind)mir_ty_data(c->it->module, ty)->kind : MK_VOID;
}

static MirTy ip_result_ty(const IpCtx *c) {
    if (c->inst->res >= c->func->nvalues) {
        return MIR_NONE;
    }
    return c->func->values[c->inst->res];
}

static MirTy ip_operand_ty(const IpCtx *c, uint32_t i) {
    if (i >= c->inst->nargs || c->inst->args[i] >= c->func->nvalues) {
        return MIR_NONE;
    }
    return c->func->values[c->inst->args[i]];
}

static bool ip_has_imm(IpCtx *c, uint8_t tag, IpFlow *flow) {
    if (c->inst->imm.tag != tag) {
        *flow = ip_internal(c->it, "%s: missing immediate", ip_op_name(c));
        return false;
    }
    return true;
}

/* ---- integers ---- */

typedef struct IpIntType {
    unsigned bits;
    bool is_unsigned;
} IpIntType;

static bool ip_int_type(MirTyKind kind, IpIntType *out) {
    switch (kind) {
    case MK_INT: *out = (IpIntType){64, false}; return true;
    case MK_UINT64: *out = (IpIntType){64, true}; return true;
    case MK_INT8: *out = (IpIntType){8, false}; return true;
    case MK_INT16: *out = (IpIntType){16, false}; return true;
    case MK_INT32: *out = (IpIntType){32, false}; return true;
    case MK_UINT8: *out = (IpIntType){8, true}; return true;
    case MK_UINT16: *out = (IpIntType){16, true}; return true;
    case MK_UINT32: *out = (IpIntType){32, true}; return true;
    case MK_VOID: case MK_BOOL: case MK_FLOAT: case MK_FLOAT32: case MK_STR: case MK_BYTES:
    case MK_PTR: case MK_TYPE: case MK_ALT: case MK_LIST: case MK_OPT: case MK_OBJ: case MK_FN:
    case MK_IFACE:
        return false;
    }
    return false;
}

/* The values of an integer type as an inclusive range of i64 (a UInt64 above i64::MAX is not
 * representable and is left out, as the register holds it as a negative number). */
static void ip_range_of(IpIntType type, int64_t *low, int64_t *high) {
    if (type.bits == 64) {
        *low = type.is_unsigned ? 0 : INT64_MIN;
        *high = INT64_MAX;
    } else if (type.is_unsigned) {
        *low = 0;
        *high = (int64_t)((UINT64_C(1) << type.bits) - 1);
    } else {
        *low = -(int64_t)(UINT64_C(1) << (type.bits - 1));
        *high = (int64_t)((UINT64_C(1) << (type.bits - 1)) - 1);
    }
}

/* A checked result: `fits` is false when the operation overflowed, and the value must also lie in
 * the range of the result's sized type. */
static IpFlow ip_sized(IpCtx *c, bool fits, int64_t value) {
    if (!fits) {
        return ip_overflow(c->it);
    }
    IpIntType type = {0};
    if (ip_int_type(ip_kind_of(c, ip_result_ty(c)), &type) && type.bits < 64) {
        int64_t low = 0, high = 0;
        ip_range_of(type, &low, &high);
        if (value < low || value > high) {
            return ip_overflow(c->it);
        }
    }
    return ip_set(c, mir_val_int(value));
}

static uint64_t ip_mul_high(uint64_t x, uint64_t y) {
    uint64_t x_low = x & 0xffffffffu, x_high = x >> 32, y_low = y & 0xffffffffu, y_high = y >> 32;
    uint64_t cross1 = x_high * y_low + ((x_low * y_low) >> 32);
    uint64_t cross2 = x_low * y_high + (cross1 & 0xffffffffu);
    return x_high * y_high + (cross1 >> 32) + (cross2 >> 32);
}

static IpFlow ip_op_wrapping(IpCtx *c, int64_t x, int64_t y) {
    uint64_t ux = (uint64_t)x, uy = (uint64_t)y;
    switch ((MirOp)c->inst->op) {
    case MOP_IAdd: return ip_set(c, mir_val_int((int64_t)(ux + uy)));
    case MOP_ISub: return ip_set(c, mir_val_int((int64_t)(ux - uy)));
    case MOP_IMul: return ip_set(c, mir_val_int((int64_t)(ux * uy)));
    case MOP_Shl: return ip_set(c, mir_val_int((int64_t)(ux << (uy & 63))));
    case MOP_Sshr: return ip_set(c, mir_val_int(x >> (uy & 63)));
    case MOP_Ushr: return ip_set(c, mir_val_int((int64_t)(ux >> (uy & 63))));
    case MOP_Rotl: {
        unsigned by = (unsigned)(uy & 63);
        return ip_set(c, mir_val_int((int64_t)(by == 0 ? ux : (ux << by) | (ux >> (64 - by)))));
    }
    case MOP_Rotr: {
        unsigned by = (unsigned)(uy & 63);
        return ip_set(c, mir_val_int((int64_t)(by == 0 ? ux : (ux >> by) | (ux << (64 - by)))));
    }
    case MOP_UMulHi: return ip_set(c, mir_val_int((int64_t)ip_mul_high(ux, uy)));
    case MOP_IAddOverflow: {
        int64_t sum = 0;
        return ip_set(c, mir_val_bool(__builtin_add_overflow(x, y, &sum)));
    }
    case MOP_IMulOverflow: {
        int64_t product = 0;
        return ip_set(c, mir_val_bool(__builtin_mul_overflow(x, y, &product)));
    }
    default: return ip_internal(c->it, "not a wrapping operation");
    }
}

static IpFlow ip_op_checked(IpCtx *c, int64_t x, int64_t y) {
    int64_t r = 0;
    uint64_t u = 0;
    switch ((MirOp)c->inst->op) {
    case MOP_IAddChk: {
        bool wrapped = __builtin_add_overflow(x, y, &r);
        return ip_sized(c, !wrapped, r);
    }
    case MOP_ISubChk: {
        bool wrapped = __builtin_sub_overflow(x, y, &r);
        return ip_sized(c, !wrapped, r);
    }
    case MOP_IMulChk: {
        bool wrapped = __builtin_mul_overflow(x, y, &r);
        return ip_sized(c, !wrapped, r);
    }
    case MOP_UAddChk:
        if (__builtin_add_overflow((uint64_t)x, (uint64_t)y, &u)) return ip_overflow(c->it);
        return ip_set(c, mir_val_int((int64_t)u));
    case MOP_USubChk:
        if (__builtin_sub_overflow((uint64_t)x, (uint64_t)y, &u)) return ip_overflow(c->it);
        return ip_set(c, mir_val_int((int64_t)u));
    case MOP_UMulChk:
        if (__builtin_mul_overflow((uint64_t)x, (uint64_t)y, &u)) return ip_overflow(c->it);
        return ip_set(c, mir_val_int((int64_t)u));
    default: return ip_internal(c->it, "not a checked operation");
    }
}

/* Division and remainder: zero faults; the minimum divided by -1 wraps unless the form checks. */
static IpFlow ip_op_divide(IpCtx *c, int64_t x, int64_t y) {
    if (y == 0) {
        return ip_div0(c->it);
    }
    bool minimum = x == INT64_MIN && y == -1;
    switch ((MirOp)c->inst->op) {
    case MOP_SDivChk: return ip_sized(c, !minimum, minimum ? 0 : x / y);
    case MOP_SRemChk: case MOP_SRem: return ip_set(c, mir_val_int(y == -1 ? 0 : x % y));
    case MOP_SDiv: return ip_set(c, mir_val_int(minimum ? INT64_MIN : x / y));
    default: return ip_internal(c->it, "not a division");
    }
}

static IpFlow ip_op_bitwise(IpCtx *c) {
    const MirVal *a = ip_slot(c, 0), *b = ip_slot(c, 1);
    MirOp op = (MirOp)c->inst->op;
    if (a->tag == MV_INT && b->tag == MV_INT) {
        int64_t x = a->as.i, y = b->as.i;
        int64_t bits = x ^ y;
        if (op == MOP_And) bits = x & y;
        if (op == MOP_Or) bits = x | y;
        return ip_set(c, mir_val_int(bits));
    }
    if (a->tag == MV_BOOL && b->tag == MV_BOOL) {
        bool x = a->as.i != 0, y = b->as.i != 0;
        bool flag = x != y;
        if (op == MOP_And) flag = x && y;
        if (op == MOP_Or) flag = x || y;
        return ip_set(c, mir_val_bool(flag));
    }
    return ip_internal(c->it, "bitwise operands must be both int or both bool");
}

static IpFlow ip_op_unary_int(IpCtx *c, int64_t x) {
    uint64_t ux = (uint64_t)x;
    switch ((MirOp)c->inst->op) {
    case MOP_INeg: return ip_set(c, mir_val_int((int64_t)(0 - ux)));
    case MOP_INegChk: return ip_sized(c, x != INT64_MIN, x == INT64_MIN ? 0 : -x);
    case MOP_Clz: return ip_set(c, mir_val_int(ux == 0 ? 64 : __builtin_clzll(ux)));
    case MOP_Ctz: return ip_set(c, mir_val_int(ux == 0 ? 64 : __builtin_ctzll(ux)));
    case MOP_Popcnt: return ip_set(c, mir_val_int(__builtin_popcountll(ux)));
    case MOP_B2I: return ip_internal(c->it, "b2i takes a bool");
    default: return ip_internal(c->it, "not a unary operation");
    }
}

static IpFlow ip_op_narrow(IpCtx *c, int64_t value) {
    IpIntType type = {0};
    int64_t low = INT64_MIN, high = INT64_MAX;
    if (c->inst->op == MOP_NarrowChk) {
        if (ip_int_type(ip_kind_of(c, ip_result_ty(c)), &type)) {
            ip_range_of(type, &low, &high);
        }
        return value < low || value > high ? ip_overflow(c->it) : ip_set(c, mir_val_int(value));
    }
    /* inarrow.opt: some when the value fits the optional's inner type. */
    MirTy result = ip_result_ty(c);
    if (ip_kind_of(c, result) == MK_OPT) {
        MirTy inner = mir_ty_data(c->it->module, result)->elem;
        if (ip_int_type(ip_kind_of(c, inner), &type)) {
            ip_range_of(type, &low, &high);
        }
        if (ip_kind_of(c, ip_operand_ty(c, 0)) == MK_UINT64 && low < 0) {
            low = 0;
        }
    }
    bool fits = value >= low && value <= high;
    return ip_set(c, fits ? ip_opt_some(mir_val_int(value)) : ip_aggregate(MV_OPT, 0, NULL));
}

static IpFlow ip_op_constants(IpCtx *c) {
    const MirInst *inst = c->inst;
    switch ((MirOp)inst->op) {
    case MOP_IConst: return ip_set(c, mir_val_int(inst->imm.tag == MI_INT ? inst->imm.i : 0));
    case MOP_FConst: {
        double value = 0;
        if (inst->imm.tag == MI_FLOAT) {
            memcpy(&value, &inst->imm.i, sizeof value);
        }
        return ip_set(c, ip_float(value));
    }
    case MOP_BConst: return ip_set(c, mir_val_bool(inst->imm.tag == MI_BOOL && inst->imm.a != 0));
    case MOP_VoidConst: return ip_set(c, ip_void());
    case MOP_Undef: return ip_set(c, ip_default_val(c->it, ip_result_ty(c), 0));
    case MOP_StrLit: {
        IpFlow flow = IP_NEXT;
        if (!ip_has_imm(c, MI_STR, &flow)) return flow;
        if (inst->imm.a >= c->it->nstrings) return ip_internal(c->it, "str: unknown literal");
        return ip_set(c, ip_retain(c->it->strings[inst->imm.a]));
    }
    case MOP_BytesLit: {
        int64_t index = inst->imm.tag == MI_INT ? inst->imm.i : 0;
        if (index < 0 || index >= (int64_t)c->it->module->nblobs) return ip_internal(c->it, "bytes: unknown blob");
        MsStr data = c->it->module->blobs[index];
        MirBlob *blob = ip_blob_new(data.len);
        for (uint32_t i = 0; i < data.len; i++) {
            blob->items[i] = mir_val_int((uint8_t)data.ptr[i]);
        }
        return ip_set(c, ip_aggregate(MV_LIST, 0, blob));
    }
    default: return ip_internal(c->it, "not a constant");
    }
}

/* Conversions that read one operand of any kind or a float. */
static IpFlow ip_op_convert(IpCtx *c) {
    const MirVal *v = ip_slot(c, 0);
    bool to32 = ip_kind_of(c, ip_result_ty(c)) == MK_FLOAT32;
    if (c->inst->op == MOP_Conv && v->tag == MV_FLOAT && to32) {
        return ip_set(c, ip_float((double)(float)v->as.f));
    }
    return ip_set(c, ip_retain(*v));
}

static IpFlow ip_op_integers(IpCtx *c) {
    IpFlow flow = IP_NEXT;
    int64_t x = 0, y = 0;
    bool flag = false;
    switch ((MirOp)c->inst->op) {
    case MOP_IConst: case MOP_FConst: case MOP_BConst: case MOP_VoidConst: case MOP_Undef:
    case MOP_StrLit: case MOP_BytesLit:
        return ip_op_constants(c);
    case MOP_Conv:
        return ip_op_convert(c);
    case MOP_And: case MOP_Or: case MOP_Xor:
        return ip_op_bitwise(c);
    case MOP_Not:
        return ip_bool_at(c, 0, &flag, &flow) ? ip_set(c, mir_val_bool(!flag)) : flow;
    case MOP_IntOverflowIf:
        if (!ip_bool_at(c, 0, &flag, &flow)) return flow;
        return flag ? ip_overflow(c->it) : IP_NEXT;
    case MOP_F32Round: {
        double v = 0;
        return ip_float_at(c, 0, &v, &flow) ? ip_set(c, ip_float((double)(float)v)) : flow;
    }
    case MOP_NarrowChk: case MOP_INarrowOpt:
        return ip_int_at(c, 0, &x, &flow) ? ip_op_narrow(c, x) : flow;
    case MOP_INeg: case MOP_INegChk: case MOP_Clz: case MOP_Ctz: case MOP_Popcnt:
        return ip_int_at(c, 0, &x, &flow) ? ip_op_unary_int(c, x) : flow;
    default:
        break;
    }
    if (!ip_int_at(c, 0, &x, &flow) || !ip_int_at(c, 1, &y, &flow)) {
        return flow;
    }
    switch ((MirOp)c->inst->op) {
    case MOP_IAddChk: case MOP_ISubChk: case MOP_IMulChk: case MOP_UAddChk: case MOP_USubChk:
    case MOP_UMulChk:
        return ip_op_checked(c, x, y);
    case MOP_SDivChk: case MOP_SRemChk: case MOP_SDiv: case MOP_SRem:
        return ip_op_divide(c, x, y);
    default:
        return ip_op_wrapping(c, x, y);
    }
}

/* ---- comparisons and floats ---- */

static bool ip_compare(MirCc cc, int64_t x, int64_t y) {
    switch (cc) {
    case MCC_EQ: return x == y;
    case MCC_NE: return x != y;
    case MCC_LT: return x < y;
    case MCC_LE: return x <= y;
    case MCC_GT: return x > y;
    case MCC_GE: return x >= y;
    }
    return false;
}

static bool ip_compare_float(MirCc cc, double x, double y) {
    switch (cc) {
    case MCC_EQ: return x == y;
    case MCC_NE: return x != y;
    case MCC_LT: return x < y;
    case MCC_LE: return x <= y;
    case MCC_GT: return x > y;
    case MCC_GE: return x >= y;
    }
    return false;
}

static bool ip_word_at(IpCtx *c, uint32_t i, int64_t *out) {
    const MirVal *v = ip_slot(c, i);
    if (v->tag != MV_INT && v->tag != MV_BOOL) {
        return false;
    }
    *out = v->as.i;
    return true;
}

static IpFlow ip_op_compare(IpCtx *c) {
    IpFlow flow = IP_NEXT;
    if (c->inst->imm.tag != MI_CC) {
        return ip_internal(c->it, "%s: missing condition", ip_op_name(c));
    }
    MirCc cc = (MirCc)c->inst->imm.a;
    int64_t x = 0, y = 0;
    double fx = 0, fy = 0;
    if (c->inst->op == MOP_FCmp) {
        if (!ip_float_at(c, 0, &fx, &flow) || !ip_float_at(c, 1, &fy, &flow)) return flow;
        return ip_set(c, mir_val_bool(ip_compare_float(cc, fx, fy)));
    }
    if (c->inst->op == MOP_ICmp) {
        if (!ip_word_at(c, 0, &x) || !ip_word_at(c, 1, &y)) {
            return ip_internal(c->it, "icmp operands must be int or bool");
        }
        return ip_set(c, mir_val_bool(ip_compare(cc, x, y)));
    }
    if (!ip_int_at(c, 0, &x, &flow) || !ip_int_at(c, 1, &y, &flow)) return flow;
    /* Unsigned: flip the sign bit and compare as signed. */
    int64_t flip = INT64_MIN;
    return ip_set(c, mir_val_bool(ip_compare(cc, x ^ flip, y ^ flip)));
}

static IpFlow ip_op_float_unary(IpCtx *c, double x) {
    switch ((MirOp)c->inst->op) {
    case MOP_FNeg: return ip_set(c, ip_float(-x));
    case MOP_FSqrt: return ip_set(c, ip_float(sqrt(x)));
    case MOP_FFloor: return ip_set(c, ip_float(floor(x)));
    case MOP_FCeil: return ip_set(c, ip_float(ceil(x)));
    case MOP_FTrunc: return ip_set(c, ip_float(trunc(x)));
    case MOP_FAbs: return ip_set(c, ip_float(fabs(x)));
    case MOP_F2IOpt: {
        bool ok = isfinite(x) && x >= -IP_I64_RANGE && x < IP_I64_RANGE;
        return ip_set(c, ok ? ip_opt_some(mir_val_int((int64_t)x)) : ip_aggregate(MV_OPT, 0, NULL));
    }
    default: return ip_internal(c->it, "not a float operation");
    }
}

static IpFlow ip_op_floats(IpCtx *c) {
    IpFlow flow = IP_NEXT;
    double x = 0, y = 0;
    int64_t n = 0;
    bool flag = false;
    switch ((MirOp)c->inst->op) {
    case MOP_UICmp: case MOP_ICmp: case MOP_FCmp:
        return ip_op_compare(c);
    case MOP_I2F: {
        if (!ip_int_at(c, 0, &n, &flow)) return flow;
        bool narrow = ip_kind_of(c, ip_result_ty(c)) == MK_FLOAT32;
        return ip_set(c, ip_float(narrow ? (double)(float)n : (double)n));
    }
    case MOP_B2I:
        return ip_bool_at(c, 0, &flag, &flow) ? ip_set(c, mir_val_int(flag ? 1 : 0)) : flow;
    case MOP_Select: {
        if (!ip_bool_at(c, 0, &flag, &flow)) return flow;
        return ip_set(c, ip_retain(*ip_slot(c, flag ? 1 : 2)));
    }
    case MOP_FAdd: case MOP_FSub: case MOP_FMul: case MOP_FDiv: {
        if (!ip_float_at(c, 0, &x, &flow) || !ip_float_at(c, 1, &y, &flow)) return flow;
        MirOp op = (MirOp)c->inst->op;
        double result = x / y;
        if (op == MOP_FAdd) result = x + y;
        if (op == MOP_FSub) result = x - y;
        if (op == MOP_FMul) result = x * y;
        return ip_set(c, ip_float(result));
    }
    default:
        return ip_float_at(c, 0, &x, &flow) ? ip_op_float_unary(c, x) : flow;
    }
}

/* ---- zero values ---- */

MirVal ip_default_val(const MirInterp *it, MirTy ty, uint32_t depth) {
    if (ty >= it->module->types.len || depth > 64) {
        return ip_void();
    }
    const MirTyData *data = mir_ty_data(it->module, ty);
    IpIntType integer = {0};
    if (ip_int_type((MirTyKind)data->kind, &integer)) {
        return mir_val_int(0);
    }
    switch ((MirTyKind)data->kind) {
    case MK_BOOL: return mir_val_bool(false);
    case MK_FLOAT: case MK_FLOAT32: return ip_float(0.0);
    case MK_STR: return ip_aggregate(MV_STR, 0, NULL);
    case MK_PTR: return ip_ptr(0);
    case MK_LIST: return ip_aggregate(MV_LIST, 0, NULL);
    case MK_OPT: return ip_aggregate(MV_OPT, 0, NULL);
    case MK_OBJ:
        if (mir_name_is(it->module, data->name, "Map")) {
            return ip_aggregate(MV_MAP, 0, NULL);
        }
        break;
    case MK_TYPE: {
        const MirTypeDef *def = &it->module->type_defs[data->id];
        MirBlob *blob = ip_blob_new(def->nfields);
        for (uint32_t i = 0; i < def->nfields; i++) {
            blob->items[i] = ip_default_val(it, def->fields[i].ty, depth + 1);
        }
        return ip_aggregate(MV_TYPE, 0, blob);
    }
    case MK_VOID: case MK_INT: case MK_INT8: case MK_INT16: case MK_INT32: case MK_UINT8:
    case MK_UINT16: case MK_UINT32: case MK_UINT64: case MK_BYTES: case MK_ALT:
    case MK_FN: case MK_IFACE:
        break;
    }
    return ip_void();
}

/* ---- types and alternatives ---- */

/* Operand `i` as an aggregate of `tag`, or false with the fault raised. */
static bool ip_aggregate_at(IpCtx *c, uint32_t i, uint8_t tag, MirVal **out, IpFlow *flow) {
    MirVal *v = ip_slot(c, i);
    if (v->tag != tag) {
        *flow = ip_internal(c->it, "%s: operand of the wrong kind", ip_op_name(c));
        return false;
    }
    *out = v;
    return true;
}

static IpFlow ip_field_of(IpCtx *c, MirVal *aggregate, uint32_t index) {
    if (index >= ip_count(*aggregate)) {
        return ip_internal(c->it, "%s: field out of range", ip_op_name(c));
    }
    return ip_set(c, ip_retain(ip_items(*aggregate)[index]));
}

static IpFlow ip_op_type_set(IpCtx *c) {
    IpFlow flow = IP_NEXT;
    if (!ip_has_imm(c, MI_FIELD, &flow)) return flow;
    uint32_t index = c->inst->imm.b;
    MirVal value = ip_arg(c, 1, true);
    MirVal record = ip_arg(c, 0, true);
    if (record.tag != MV_TYPE || index >= ip_count(record)) {
        mir_val_release(&value);
        mir_val_release(&record);
        return ip_internal(c->it, "%s: not a record or field out of range", ip_op_name(c));
    }
    (void)ip_make_unique(&record);
    mir_val_release(&ip_items(record)[index]);
    ip_items(record)[index] = value;
    return ip_set(c, record);
}

static IpFlow ip_op_alt_field(IpCtx *c) {
    IpFlow flow = IP_NEXT;
    MirVal *alt = NULL;
    if (!ip_has_imm(c, MI_ALTFIELD, &flow) || !ip_aggregate_at(c, 0, MV_ALT, &alt, &flow)) return flow;
    if (alt->id != c->inst->imm.b) {
        return ip_internal(c->it, "%s of case %u on case %u", ip_op_name(c), c->inst->imm.b, alt->id);
    }
    return ip_field_of(c, alt, c->inst->imm.c);
}

static IpFlow ip_op_types(IpCtx *c) {
    IpFlow flow = IP_NEXT;
    MirVal *operand = NULL;
    switch ((MirOp)c->inst->op) {
    case MOP_TypeNew: return ip_set(c, ip_aggregate(MV_TYPE, 0, ip_take_all(c)));
    case MOP_TypeGet:
        if (!ip_has_imm(c, MI_FIELD, &flow) || !ip_aggregate_at(c, 0, MV_TYPE, &operand, &flow)) return flow;
        return ip_field_of(c, operand, c->inst->imm.b);
    case MOP_TypeSet: case MOP_TypeFill:
        return ip_op_type_set(c);
    case MOP_AltNew:
        if (!ip_has_imm(c, MI_CASE, &flow)) return flow;
        return ip_set(c, ip_aggregate(MV_ALT, c->inst->imm.b, ip_take_all(c)));
    case MOP_AltView: {
        if (!ip_has_imm(c, MI_CASE, &flow)) return flow;
        MirBlob *blob = ip_blob_new(c->inst->nargs);
        for (uint32_t i = 0; i < c->inst->nargs; i++) {
            blob->items[i] = ip_arg(c, i, false);
        }
        return ip_set(c, ip_aggregate(MV_ALT, c->inst->imm.b, blob));
    }
    case MOP_AltPlain: return ip_set(c, ip_retain(*ip_slot(c, 0)));
    case MOP_AltTag:
        if (!ip_aggregate_at(c, 0, MV_ALT, &operand, &flow)) return flow;
        return ip_set(c, mir_val_int(operand->id));
    default: return ip_op_alt_field(c);
    }
}

/* ---- lists ---- */

/* A checked position in a list; negative positions count from the end when `from_end`. */
static IpFlow ip_list_index(IpCtx *c, uint32_t length, int64_t index, bool from_end, uint32_t *out) {
    int64_t position = index < 0 && from_end ? index + (int64_t)length : index;
    if (position < 0 || position >= (int64_t)length) {
        return ip_raise(c->it, MF_INDEX_OUT_OF_RANGE, "index %lld out of range for length %u",
                        (long long)index, length);
    }
    *out = (uint32_t)position;
    return IP_NEXT;
}

static IpFlow ip_op_list_const(IpCtx *c) {
    int64_t index = c->inst->imm.tag == MI_INT ? c->inst->imm.i : 0;
    if (index < 0 || index >= (int64_t)c->it->module->nlist_consts) {
        return ip_internal(c->it, "list.const: unknown constant");
    }
    MirTy result = ip_result_ty(c);
    MirTyKind elem = MK_INT;
    if (ip_kind_of(c, result) == MK_LIST) {
        elem = ip_kind_of(c, mir_ty_data(c->it->module, result)->elem);
    }
    const MirConsts *consts = &c->it->module->list_consts[index];
    MirBlob *blob = ip_blob_new(consts->n);
    for (uint32_t i = 0; i < consts->n; i++) {
        int64_t raw = consts->v[i];
        if (elem == MK_FLOAT || elem == MK_FLOAT32) {
            double value = 0;
            memcpy(&value, &raw, sizeof value);
            blob->items[i] = ip_float(value);
        } else {
            blob->items[i] = elem == MK_BOOL ? mir_val_bool(raw != 0) : mir_val_int(raw);
        }
    }
    return ip_set(c, ip_aggregate(MV_LIST, 0, blob));
}

static IpFlow ip_op_list_get(IpCtx *c) {
    IpFlow flow = IP_NEXT;
    int64_t index = 0;
    MirVal *list = NULL;
    if (!ip_int_at(c, 1, &index, &flow) || !ip_aggregate_at(c, 0, MV_LIST, &list, &flow)) return flow;
    uint32_t at = 0;
    flow = ip_list_index(c, ip_count(*list), index, c->inst->op == MOP_ListGet, &at);
    return flow == IP_NEXT ? ip_set(c, ip_retain(ip_items(*list)[at])) : flow;
}

static IpFlow ip_op_list_set(IpCtx *c) {
    IpFlow flow = IP_NEXT;
    int64_t index = 0;
    if (!ip_int_at(c, 1, &index, &flow)) return flow;
    MirVal value = ip_arg(c, 2, true);
    MirVal list = ip_arg(c, 0, true);
    uint32_t at = 0;
    bool from_end = c->inst->op == MOP_ListSet || c->inst->op == MOP_ListFill;
    if (list.tag != MV_LIST) {
        flow = ip_internal(c->it, "%s: not a list", ip_op_name(c));
    } else {
        flow = ip_list_index(c, ip_count(list), index, from_end, &at);
    }
    if (flow != IP_NEXT) {
        mir_val_release(&value);
        mir_val_release(&list);
        return flow;
    }
    (void)ip_make_unique(&list);
    mir_val_release(&ip_items(list)[at]);
    ip_items(list)[at] = value;
    return ip_set(c, list);
}

/* push, droplast, grow, release: operations that take the list and hand it back changed. */
static IpFlow ip_op_list_shape(IpCtx *c) {
    IpFlow flow = IP_NEXT;
    int64_t amount = 0;
    MirOp op = (MirOp)c->inst->op;
    if ((op == MOP_ListGrow || op == MOP_ListRelease) && !ip_int_at(c, 1, &amount, &flow)) return flow;
    MirVal item = ip_void();
    if (op == MOP_ListPush || op == MOP_ListPushU) {
        item = ip_arg(c, 1, true);
    }
    MirVal list = ip_arg(c, 0, true);
    if (op == MOP_ListRelease) {
        mir_val_release(&list);
        return IP_NEXT;
    }
    if (list.tag != MV_LIST) {
        mir_val_release(&item);
        mir_val_release(&list);
        return ip_internal(c->it, "%s: not a list", ip_op_name(c));
    }
    if (op == MOP_ListPush || op == MOP_ListPushU) {
        (void)ip_make_unique(&list);
        ip_list_push(&list, item);
    } else if (op == MOP_ListDropLast) {
        (void)ip_make_unique(&list);
        ip_list_pop(&list);
    }
    return ip_set(c, list);
}

static IpFlow ip_op_lists(IpCtx *c) {
    IpFlow flow = IP_NEXT;
    int64_t n = 0;
    MirVal *list = NULL;
    switch ((MirOp)c->inst->op) {
    case MOP_ListNew:
        if (!ip_int_at(c, 0, &n, &flow)) return flow;
        return ip_set(c, ip_aggregate(MV_LIST, 0, NULL));
    case MOP_ListLit: return ip_set(c, ip_aggregate(MV_LIST, 0, ip_take_all(c)));
    case MOP_ListConst: case MOP_ListConstView: return ip_op_list_const(c);
    case MOP_ListLen:
        if (!ip_aggregate_at(c, 0, MV_LIST, &list, &flow)) return flow;
        return ip_set(c, mir_val_int(ip_count(*list)));
    case MOP_ListGet: case MOP_ListGetNn: case MOP_ListGetU: case MOP_ListTake:
        return ip_op_list_get(c);
    case MOP_ListSet: case MOP_ListSetNn: case MOP_ListSetU: case MOP_ListFill: case MOP_ListFillU:
        return ip_op_list_set(c);
    case MOP_ListCap: return ip_set(c, mir_val_int(INT64_MAX));
    default: return ip_op_list_shape(c);
    }
}

/* ---- optionals and strings ---- */

static uint32_t ip_scalar_count(MsStr text) {
    uint32_t scalars = 0;
    for (uint32_t i = 0; i < text.len; i++) {
        if (!ms_utf8_is_continuation((uint8_t)text.ptr[i])) {
            scalars++;
        }
    }
    return scalars;
}

static IpFlow ip_op_string(IpCtx *c) {
    IpFlow flow = IP_NEXT;
    MirVal *text = NULL;
    int64_t n = 0;
    if (c->inst->op == MOP_StrAscii) {
        if (!ip_int_at(c, 0, &n, &flow)) return flow;
        MsBuf encoded = {0};
        ms_utf8_put(&encoded, (uint32_t)(uint8_t)n);
        MirVal result = ip_str(encoded.data, encoded.len);
        ms_buf_free(&encoded);
        return ip_set(c, result);
    }
    if (!ip_aggregate_at(c, 0, MV_STR, &text, &flow)) return flow;
    MsStr view = ip_str_view(*text);
    switch ((MirOp)c->inst->op) {
    case MOP_StrLen: return ip_set(c, mir_val_int(ip_scalar_count(view)));
    case MOP_StrBytes: return ip_set(c, mir_val_int(view.len));
    case MOP_StrAsciiLen: {
        for (uint32_t i = 0; i < view.len; i++) {
            if ((uint8_t)view.ptr[i] >= 0x80) return ip_set(c, mir_val_int(-1));
        }
        return ip_set(c, mir_val_int(view.len));
    }
    case MOP_StrByte:
        if (!ip_int_at(c, 1, &n, &flow)) return flow;
        if (n < 0 || n >= (int64_t)view.len) return ip_internal(c->it, "str.byte: index out of range");
        return ip_set(c, mir_val_int((uint8_t)view.ptr[n]));
    case MOP_StrEqLit: {
        if (!ip_has_imm(c, MI_STR, &flow)) return flow;
        if (c->inst->imm.a >= c->it->nstrings) return ip_internal(c->it, "str.eq_lit: unknown literal");
        MsStr literal = ip_str_view(c->it->strings[c->inst->imm.a]);
        return ip_set(c, mir_val_bool(literal.len == view.len && memcmp(literal.ptr, view.ptr, view.len) == 0));
    }
    default: return ip_internal(c->it, "not a string operation");
    }
}

static IpFlow ip_op_optionals(IpCtx *c) {
    IpFlow flow = IP_NEXT;
    MirVal *opt = NULL;
    switch ((MirOp)c->inst->op) {
    case MOP_OptSome: return ip_set(c, ip_opt_some(ip_arg(c, 0, true)));
    case MOP_OptView: return ip_set(c, ip_opt_some(ip_arg(c, 0, false)));
    case MOP_OptNone: case MOP_OptNoneOwned: return ip_set(c, ip_aggregate(MV_OPT, 0, NULL));
    case MOP_OptIsSome:
        if (!ip_aggregate_at(c, 0, MV_OPT, &opt, &flow)) return flow;
        return ip_set(c, mir_val_bool(ip_count(*opt) > 0));
    case MOP_OptGet:
        if (!ip_aggregate_at(c, 0, MV_OPT, &opt, &flow)) return flow;
        if (ip_count(*opt) == 0) return ip_internal(c->it, "opt.get on none");
        return ip_set(c, ip_retain(ip_items(*opt)[0]));
    case MOP_BytesPush: return ip_set(c, mir_val_bool(false));
    case MOP_OptViewAt: case MOP_OptAddr:
        return ip_internal(c->it, "%s is not supported by the interpreter", ip_op_name(c));
    default: return ip_op_string(c);
    }
}

/* ---- closures and interfaces ---- */

static IpFlow ip_op_closures(IpCtx *c) {
    IpFlow flow = IP_NEXT;
    MirVal *operand = NULL;
    switch ((MirOp)c->inst->op) {
    case MOP_ClosureNew:
        if (!ip_has_imm(c, MI_FUNC, &flow)) return flow;
        return ip_set(c, ip_aggregate(MV_CLOSURE, c->inst->imm.a, ip_take_all(c)));
    case MOP_ClosureCap:
        if (!ip_has_imm(c, MI_IDX, &flow) || !ip_aggregate_at(c, 0, MV_CLOSURE, &operand, &flow)) return flow;
        return ip_field_of(c, operand, c->inst->imm.a);
    case MOP_IfaceNew: case MOP_IfaceBorrow: {
        if (!ip_has_imm(c, MI_VTABLE, &flow)) return flow;
        MirBlob *blob = ip_blob_new(1);
        blob->items[0] = ip_arg(c, 0, c->inst->op == MOP_IfaceNew);
        return ip_set(c, ip_aggregate(MV_IFACE, c->inst->imm.a, blob));
    }
    case MOP_IfaceView: return ip_set(c, ip_retain(*ip_slot(c, 0)));
    case MOP_IfaceIs:
        if (!ip_has_imm(c, MI_VTABLE, &flow) || !ip_aggregate_at(c, 0, MV_IFACE, &operand, &flow)) return flow;
        return ip_set(c, mir_val_bool(operand->id == c->inst->imm.a));
    case MOP_IfaceData:
        if (!ip_aggregate_at(c, 0, MV_IFACE, &operand, &flow)) return flow;
        return ip_field_of(c, operand, 0);
    default:
        return ip_internal(c->it, "%s is native only", ip_op_name(c));
    }
}

/* ---- ownership and memory ---- */

static IpFlow ip_op_memory(IpCtx *c) {
    IpFlow flow = IP_NEXT;
    MirInterp *it = c->it;
    const MirVal *pointer = ip_slot(c, 0);
    uint64_t index = pointer->as.p - 1;
    if (c->inst->op == MOP_Slot) {
        if (!ip_has_imm(c, MI_TY, &flow)) return flow;
        if (it->nmemory == it->cmemory) {
            uint32_t grown = ip_grow_cap(it->cmemory, 16);
            it->memory = ip_regrow(it->memory, sizeof(MirVal) * it->cmemory, sizeof(MirVal) * grown);
            it->cmemory = grown;
        }
        it->memory[it->nmemory++] = ip_default_val(it, c->inst->imm.a, 0);
        return ip_set(c, ip_ptr(it->nmemory));
    }
    if (pointer->tag != MV_PTR) {
        return ip_internal(it, "%s: not a pointer", ip_op_name(c));
    }
    if (c->inst->op == MOP_PtrIsNull) {
        return ip_set(c, mir_val_bool(pointer->as.p == 0));
    }
    if (index >= it->nmemory) {
        return ip_internal(it, "%s: invalid address", ip_op_name(c));
    }
    if (c->inst->op == MOP_Load || c->inst->op == MOP_Take) {
        return ip_set(c, ip_retain(it->memory[index]));
    }
    MirVal value = ip_retain(*ip_slot(c, 1));
    mir_val_release(&it->memory[index]);
    it->memory[index] = value;
    return IP_NEXT;
}

static IpFlow ip_op_ownership(IpCtx *c) {
    IpFlow flow = IP_NEXT;
    bool flag = false;
    MirVal dying = ip_void();
    switch ((MirOp)c->inst->op) {
    case MOP_Clone: case MOP_MoveOut: return ip_set(c, ip_retain(*ip_slot(c, 0)));
    case MOP_Drop:
        c->it->drops++;
        dying = ip_arg(c, 0, true);
        break;
    case MOP_DropIf:
        if (!ip_bool_at(c, 0, &flag, &flow)) return flow;
        if (flag) {
            c->it->drops++;
            dying = ip_arg(c, 1, true);
        }
        break;
    case MOP_Free:
        dying = ip_arg(c, 0, true);
        break;
    case MOP_Forget:
        break;
    case MOP_Slot: case MOP_PtrIsNull: case MOP_Load: case MOP_Take: case MOP_Store: case MOP_Put:
        return ip_op_memory(c);
    default:
        return ip_internal(c->it, "interior pointers are not supported by the interpreter");
    }
    mir_val_release(&dying);
    return IP_NEXT;
}

/* ---- calls and runtime services ---- */

MirVal *ip_stage(MirInterp *it, uint32_t count) {
    if (count > it->ccall_args) {
        free(it->call_args);
        it->call_args = calloc(count, sizeof(MirVal));
        if (it->call_args == NULL) ip_oom();
        it->ccall_args = count;
    }
    if (count > 0) {
        memset(it->call_args, 0, sizeof(MirVal) * count);
    }
    it->ncall_args = count;
    return it->call_args;
}

static IpFlow ip_call(IpCtx *c, uint32_t callee) {
    c->it->callee = callee;
    return IP_CALL;
}

/* The arguments after the first, for an indirect call: owned where `owned` says so. */
static void ip_stage_rest(IpCtx *c, MirVal *staged, uint64_t owned) {
    for (uint32_t i = 1; i < c->inst->nargs; i++) {
        staged[i] = ip_arg(c, i, mir_owns(owned, i - 1));
    }
}

static IpFlow ip_op_call_direct(IpCtx *c) {
    IpFlow flow = IP_NEXT;
    if (!ip_has_imm(c, MI_FUNC, &flow)) return flow;
    uint32_t callee = c->inst->imm.a;
    if (callee >= c->it->module->nfuncs) return ip_internal(c->it, "call: unknown function");
    const MirFunc *target = &c->it->module->funcs[callee];
    uint32_t count = c->inst->nargs < target->nparams ? c->inst->nargs : target->nparams;
    MirVal *staged = ip_stage(c->it, count);
    for (uint32_t i = 0; i < count; i++) {
        staged[i] = ip_arg(c, i, target->params[i].mode != MM_BORROW);
    }
    return ip_call(c, callee);
}

static IpFlow ip_op_call_closure(IpCtx *c) {
    const MirVal *closure = ip_slot(c, 0);
    if (closure->tag != MV_CLOSURE) return ip_internal(c->it, "call.ind on a non-closure");
    uint32_t callee = closure->id;
    if (callee >= c->it->module->nfuncs) return ip_internal(c->it, "call.ind: unknown function");
    uint64_t owned = 0;
    MirTy type = ip_operand_ty(c, 0);
    if (ip_kind_of(c, type) == MK_FN) owned = mir_ty_data(c->it->module, type)->owned;
    MirVal *staged = ip_stage(c->it, c->inst->nargs);
    staged[0] = ip_retain(*closure);
    ip_stage_rest(c, staged, owned);
    return ip_call(c, callee);
}

static IpFlow ip_op_call_method(IpCtx *c) {
    const MirModule *module = c->it->module;
    IpFlow flow = IP_NEXT;
    if (!ip_has_imm(c, MI_METHOD, &flow)) return flow;
    const MirVal *view = ip_slot(c, 0);
    uint32_t iface = c->inst->imm.a, slot = c->inst->imm.b;
    if (view->tag != MV_IFACE || view->id >= module->nvtables || ip_count(*view) == 0) {
        return ip_internal(c->it, "call.method on a non-interface");
    }
    const MirVtable *table = &module->vtables[view->id];
    if (slot >= table->nmethods || table->methods[slot] >= module->nfuncs) {
        return ip_internal(c->it, "call.method: no such method");
    }
    uint64_t owned = 0;
    if (iface < module->nifaces && slot < module->ifaces[iface].nmethods) {
        owned = module->ifaces[iface].methods[slot].owned;
    }
    MirVal *staged = ip_stage(c->it, c->inst->nargs);
    staged[0] = ip_retain(ip_items(*view)[0]);
    ip_stage_rest(c, staged, owned);
    return ip_call(c, table->methods[slot]);
}

static const IpHost *ip_find_host(const MirInterp *it, MsStr name) {
    for (uint32_t i = 0; i < it->nhosts; i++) {
        if (strlen(it->hosts[i].name) == name.len && memcmp(it->hosts[i].name, name.ptr, name.len) == 0) {
            return &it->hosts[i];
        }
    }
    return NULL;
}

static IpFlow ip_op_call_runtime(IpCtx *c) {
    MirInterp *it = c->it;
    IpFlow flow = IP_NEXT;
    if (!ip_has_imm(c, MI_EXT, &flow)) return flow;
    if (c->inst->imm.a >= it->module->nexterns) return ip_internal(it, "call.rt: unknown extern");
    const MirExtern *ext = &it->module->externs[c->inst->imm.a];
    uint32_t count = c->inst->nargs < ext->nparams ? c->inst->nargs : ext->nparams;
    MirVal *args = calloc(count + 1, sizeof(MirVal));
    if (args == NULL) ip_oom();
    for (uint32_t i = 0; i < count; i++) {
        args[i] = ip_arg(c, i, ext->params[i].mode != MM_BORROW);
    }
    MsStr name = ms_name(&it->module->names, ext->name);
    const IpHost *host = ip_find_host(it, name);
    MirVal result = ip_void();
    MsStr error = {.ptr = "", .len = 0};
    if (ip_map_runtime(it, name, args, count, &result, &flow)) {
        // a map function: the interpreter keeps maps itself
    } else if (host == NULL) {
        flow = ip_internal(it, "unregistered runtime function %.*s", (int)name.len, name.ptr);
    } else if (!host->fn(host->context, &it->out, args, count, &result, &error)) {
        flow = ip_raise_text(it, MF_UNREACHABLE, error);
    }
    for (uint32_t i = 0; i < count; i++) {
        mir_val_release(&args[i]);
    }
    free(args);
    return flow == IP_NEXT ? ip_set(c, result) : flow;
}

static IpFlow ip_op_cleanup(IpCtx *c) {
    MirInterp *it = c->it;
    IpFlow flow = IP_NEXT;
    int64_t handle = 0;
    if (c->inst->op == MOP_CleanupPush) {
        if (!ip_has_imm(c, MI_FUNC, &flow)) return flow;
        if (it->ncleanup == it->ccleanup) {
            uint32_t grown = ip_grow_cap(it->ccleanup, 8);
            it->cleanup = ip_regrow(it->cleanup, sizeof(IpCleanup) * it->ccleanup, sizeof(IpCleanup) * grown);
            it->ccleanup = grown;
        }
        it->cleanup[it->ncleanup++] = (IpCleanup){c->inst->imm.a, ip_retain(*ip_slot(c, 0))};
        return ip_set(c, mir_val_int(it->ncleanup));
    }
    if (!ip_int_at(c, 0, &handle, &flow)) return flow;
    while (handle > 0 && (int64_t)it->ncleanup >= handle) {
        IpCleanup action = it->cleanup[--it->ncleanup];
        MirVal result = ip_void();
        if (!ip_exec(it, action.closer, &action.value, 1, &result)) {
            it->raw = (IpRaw){it->fault.kind, it->fault.message, false};
            return IP_RAISE;
        }
        mir_val_release(&result);
    }
    return IP_NEXT;
}

static IpFlow ip_op_runtime(IpCtx *c) {
    MirInterp *it = c->it;
    IpFlow flow = IP_NEXT;
    switch ((MirOp)c->inst->op) {
    case MOP_FuncAddr:
        return ip_has_imm(c, MI_FUNC, &flow) ? ip_set(c, ip_ptr(c->inst->imm.a)) : flow;
    case MOP_TypeDesc:
        return ip_has_imm(c, MI_TY, &flow) ? ip_set(c, ip_ptr(c->inst->imm.a)) : flow;
    case MOP_Poll:
        return it->cancelled ? ip_raise(it, MF_CANCELLED, "cancelled") : IP_NEXT;
    case MOP_DepthEnter:
        it->depth++;
        return it->depth > MIR_INTERP_MAX_CALL_DEPTH ? ip_raise(it, MF_CALL_DEPTH, "%s", ip_depth_message()) : IP_NEXT;
    case MOP_DepthLeave:
        it->depth--;
        return IP_NEXT;
    case MOP_StackLow: case MOP_StackNear:
        return ip_set(c, mir_val_bool(false));
    case MOP_GlobalGet: case MOP_GlobalSet: {
        if (!ip_has_imm(c, MI_GLOBAL, &flow)) return flow;
        if (c->inst->imm.a >= it->module->nglobals) return ip_internal(it, "unknown global");
        MirVal *global = &it->globals[c->inst->imm.a];
        if (c->inst->op == MOP_GlobalGet) return ip_set(c, ip_retain(*global));
        MirVal value = ip_arg(c, 0, true);
        mir_val_release(global);
        *global = value;
        return IP_NEXT;
    }
    default:
        return ip_op_cleanup(c);
    }
}

/* Executes one instruction by routing it to the function for its op family. */
IpFlow ip_step(MirInterp *it, const MirFunc *func, MirVal *regs, const MirInst *inst) {
    IpCtx ctx = {it, func, regs, inst};
    switch ((MirOp)inst->op) {
    case MOP_IConst: case MOP_FConst: case MOP_BConst: case MOP_VoidConst: case MOP_Undef:
    case MOP_StrLit: case MOP_BytesLit: case MOP_IAdd: case MOP_ISub: case MOP_IMul: case MOP_INeg:
    case MOP_IAddOverflow: case MOP_IMulOverflow: case MOP_IntOverflowIf: case MOP_NarrowChk:
    case MOP_Conv: case MOP_INarrowOpt: case MOP_F32Round: case MOP_IAddChk: case MOP_ISubChk:
    case MOP_IMulChk: case MOP_UAddChk: case MOP_USubChk: case MOP_UMulChk: case MOP_INegChk:
    case MOP_SDivChk: case MOP_SRemChk: case MOP_SDiv: case MOP_SRem: case MOP_And: case MOP_Or:
    case MOP_Xor: case MOP_Shl: case MOP_Sshr: case MOP_Ushr: case MOP_Rotl: case MOP_Rotr:
    case MOP_UMulHi: case MOP_Clz: case MOP_Ctz: case MOP_Popcnt: case MOP_Not:
        return ip_op_integers(&ctx);
    case MOP_UICmp: case MOP_ICmp: case MOP_FCmp: case MOP_FAdd: case MOP_FSub: case MOP_FMul:
    case MOP_FDiv: case MOP_FNeg: case MOP_FSqrt: case MOP_FFloor: case MOP_FCeil: case MOP_FTrunc:
    case MOP_FAbs: case MOP_I2F: case MOP_F2IOpt: case MOP_B2I: case MOP_Select:
        return ip_op_floats(&ctx);
    case MOP_TypeNew: case MOP_TypeGet: case MOP_TypeSet: case MOP_TypeFill: case MOP_AltNew:
    case MOP_AltView: case MOP_AltPlain: case MOP_AltTag: case MOP_AltGet: case MOP_AltTake:
        return ip_op_types(&ctx);
    case MOP_ListNew: case MOP_ListLit: case MOP_ListConst: case MOP_ListConstView:
    case MOP_ListLen: case MOP_ListGet: case MOP_ListGetNn: case MOP_ListGetU: case MOP_ListTake:
    case MOP_ListRelease: case MOP_ListSet: case MOP_ListSetNn: case MOP_ListSetU:
    case MOP_ListFill: case MOP_ListPush: case MOP_ListCap: case MOP_ListGrow: case MOP_ListFillU:
    case MOP_ListPushU: case MOP_ListDropLast:
        return ip_op_lists(&ctx);
    case MOP_OptSome: case MOP_OptView: case MOP_OptViewAt: case MOP_OptNone:
    case MOP_OptNoneOwned: case MOP_OptIsSome: case MOP_OptGet: case MOP_OptAddr: case MOP_StrLen:
    case MOP_StrByte: case MOP_StrAsciiLen: case MOP_StrBytes: case MOP_StrEqLit: case MOP_StrAscii:
    case MOP_BytesPush:
        return ip_op_optionals(&ctx);
    case MOP_ClosureNew: case MOP_ClosureCap: case MOP_ClosureCapAddr: case MOP_IfaceNew:
    case MOP_IfaceBorrow: case MOP_IfaceView: case MOP_IfaceIs: case MOP_IfaceTag:
    case MOP_IfaceDestroy: case MOP_IfaceData:
        return ip_op_closures(&ctx);
    case MOP_Clone: case MOP_MoveOut: case MOP_Drop: case MOP_Forget: case MOP_Free: case MOP_DropIf:
    case MOP_Slot: case MOP_PtrIsNull: case MOP_PtrAdd: case MOP_PtrNull: case MOP_PtrLoadU:
    case MOP_PtrStoreU: case MOP_ListAddr: case MOP_ListAddrU: case MOP_PtrField: case MOP_Load:
    case MOP_Take: case MOP_Store: case MOP_Put:
        return ip_op_ownership(&ctx);
    case MOP_Call: return ip_op_call_direct(&ctx);
    case MOP_CallInd: return ip_op_call_closure(&ctx);
    case MOP_CallMethod: return ip_op_call_method(&ctx);
    case MOP_CallRt: return ip_op_call_runtime(&ctx);
    case MOP_FuncAddr: case MOP_TypeDesc: case MOP_Poll: case MOP_DepthEnter: case MOP_DepthLeave:
    case MOP_StackLow: case MOP_StackNear: case MOP_CleanupPush: case MOP_CleanupRun:
    case MOP_GlobalGet: case MOP_GlobalSet:
        return ip_op_runtime(&ctx);
    case MOP_AltOwn: case MOP_AltUnbox: case MOP_AltRelease: case MOP_TypeRelease: case MOP_OptUnbox:
    case MOP_OptUnwrap:
        return ip_internal(it, "%s survived expand_owned", mir_op_info[inst->op].name);
    case MOP_ScopeBegin: case MOP_ScopeOwn: case MOP_ScopeEnd: case MOP_ScopeDisown:
    case MOP_ScopeMark:
        return IP_NEXT;
    case MOP_COUNT:
        break;
    }
    return ip_internal(it, "unknown instruction");
}

/* Structural equality of aggregates in the lowering (crates/ms-lower/src/eq.rs): `a == b` on two
 * records, enums, optionals or lists calls a generated function `equal(a, b) -> Bool`, made on first use
 * for each type. It compares field by field (a record), tag then payload (an enum), presence then
 * payload (an optional) or length then element by element (a list), leaving at the first difference. */
#include <string.h>

#include "ms/hints.h"
#include "ms/lower_internal.h"
#include "ms/mir_analysis.h"
#include "ms/mir_pass.h"
#include "ms/rt_ops.h"

static MirValue lq_element(Lb *lb, MirBuilder *b, MirTy ty, MirValue x, MirValue y);
static uint32_t lq_function(Lb *lb, MirTy ty);

/* A call of the runtime's `symbol(a, b) -> Bool` on two values of `ty`. */
static MirValue lq_runtime(Lb *lb, MirBuilder *b, const char *symbol, MirTy ty, MirValue x, MirValue y) {
    const MsRtFn *fn = ms_rt_fn_find(symbol, strlen(symbol));
    if (fn == NULL) {
        return MIR_NONE;
    }
    const MirTy types[2] = {ty, ty};
    const uint32_t ext = mir_extern_get(lb->m, fn->symbol, types, 2, MIR_BOOL, fn->leaf, MR_NONE);
    const MirValue args[2] = {x, y};
    return mir_b_call_rt(b, ext, args, 2);
}

/* Compares two borrowed operands of type `ty`; MIR_NONE when the type cannot be compared here. */
static MirValue lq_element(Lb *lb, MirBuilder *b, MirTy ty, MirValue x, MirValue y) {
    if (ty == MIR_VOID) {
        return mir_b_bconst(b, true);
    }
    if (ty == MIR_STR) {
        return lq_runtime(lb, b, "msrt_string_eq", ty, x, y);
    }
    const MirTyData *data = mir_ty_data(lb->m, ty);
    switch (data->kind) {
    case MK_BOOL:
    case MK_INT:
    case MK_INT8:
    case MK_INT16:
    case MK_INT32:
    case MK_UINT8:
    case MK_UINT16:
    case MK_UINT32:
    case MK_UINT64:
        return mir_b_icmp(b, MCC_EQ, x, y);
    case MK_FLOAT:
    case MK_FLOAT32: {
        const MirValue args[2] = {x, y};
        return mir_b_emit(b, MOP_FCmp, args, 2, (MirImm){.tag = MI_CC, .a = (uint32_t)MCC_EQ}, MIR_BOOL);
    }
    case MK_BYTES:
        return lq_runtime(lb, b, "msrt_bytes_eq", ty, x, y);
    case MK_TYPE:
    case MK_ALT:
    case MK_OPT:
    case MK_LIST: {
        const uint32_t func = lq_function(lb, ty);
        const MirValue args[2] = {x, y};
        return func == MIR_NONE ? MIR_NONE : mir_b_call(b, func, args, 2);
    }
    default:
        return MIR_NONE; // an interface, a function or a runtime object is not compared structurally
    }
}

/* Leaves the current block for `no` unless `same`, else continues in a fresh block. */
static void lq_continue_if(MirBuilder *b, MirValue same, MirBlock no) {
    const MirBlock next = mir_b_new_block(b);
    mir_b_br_if(b, same, next, NULL, 0, no, NULL, 0);
    mir_b_seal_block(b, next);
    mir_b_switch_to(b, next);
}

/* Compares the fields of one record or enum case: `get(i)` reads field `i` of the operand. */
static bool lq_fields(Lb *lb, MirBuilder *b, const MirField *fields, uint32_t count, MirImm (*imm)(const void *, uint32_t),
                      const void *where, MirOp get, MirValue x, MirValue y, MirBlock no) {
    for (uint32_t i = 0; i < count; i++) {
        const MirImm at = imm(where, i);
        const MirValue l = mir_b_emit(b, get, &x, 1, at, fields[i].ty);
        const MirValue r = mir_b_emit(b, get, &y, 1, at, fields[i].ty);
        const MirValue same = lq_element(lb, b, fields[i].ty, l, r);
        if (same == MIR_NONE) {
            return false;
        }
        lq_continue_if(b, same, no);
    }
    return true;
}

typedef struct LqCase {
    uint32_t alt, which;
} LqCase;

static MirImm lq_record_field(const void *where, uint32_t i) {
    return (MirImm){.tag = MI_FIELD, .a = *(const uint32_t *)where, .b = i};
}

static MirImm lq_case_field(const void *where, uint32_t i) {
    const LqCase *c = where;
    return (MirImm){.tag = MI_ALTFIELD, .a = c->alt, .b = c->which, .c = i};
}

/* The body comparing two records, field by field. */
static bool lq_body_record(Lb *lb, MirBuilder *b, const MirTyData *data, MirValue x, MirValue y, MirBlock yes, MirBlock no) {
    const MirTypeDef *def = &lb->m->type_defs[data->id];
    if (!lq_fields(lb, b, def->fields, def->nfields, lq_record_field, &data->id, MOP_TypeGet, x, y, no)) {
        return false;
    }
    mir_b_br(b, yes, NULL, 0);
    return true;
}

/* The body comparing two values of an enum: the tags, then the fields of the case. */
static bool lq_body_alt(Lb *lb, MirBuilder *b, const MirTyData *data, MirValue x, MirValue y, MirBlock yes, MirBlock no) {
    const MirAltDef *alt = &lb->m->alts[data->id];
    const MirValue tx = mir_b_emit(b, MOP_AltTag, &x, 1, (MirImm){0}, MIR_INT);
    const MirValue other_tag = mir_b_emit(b, MOP_AltTag, &y, 1, (MirImm){0}, MIR_INT);
    const MirValue same = mir_b_icmp(b, MCC_EQ, tx, other_tag);
    const MirBlock dispatch = mir_b_new_block(b);
    mir_b_br_if(b, same, dispatch, NULL, 0, no, NULL, 0);
    mir_b_seal_block(b, dispatch);
    mir_b_switch_to(b, dispatch);
    MirBlock *blocks = MS_NEW_N(&b->scratch, MirBlock, (size_t)alt->ncases + 1);
    MirCase *arms = MS_NEW_N(&b->scratch, MirCase, (size_t)alt->ncases + 1);
    for (uint32_t i = 0; i < alt->ncases; i++) {
        blocks[i] = mir_b_new_block(b);
        arms[i] = (MirCase){(int64_t)i, {blocks[i], NULL, 0}};
    }
    mir_b_switch(b, tx, arms, alt->ncases, yes);
    for (uint32_t i = 0; i < alt->ncases; i++) {
        mir_b_seal_block(b, blocks[i]);
        mir_b_switch_to(b, blocks[i]);
        const LqCase at = {data->id, i};
        if (!lq_fields(lb, b, alt->cases[i].fields, alt->cases[i].nfields, lq_case_field, &at, MOP_AltGet, x, y, no)) {
            return false;
        }
        mir_b_br(b, yes, NULL, 0);
    }
    return true;
}

/* The body comparing two optionals: both empty, or both set and equal inside. */
static bool lq_body_opt(Lb *lb, MirBuilder *b, const MirTyData *data, MirValue x, MirValue y, MirBlock yes, MirBlock no) {
    const MirValue sx = mir_b_emit(b, MOP_OptIsSome, &x, 1, (MirImm){0}, MIR_BOOL);
    const MirValue sy = mir_b_emit(b, MOP_OptIsSome, &y, 1, (MirImm){0}, MIR_BOOL);
    const MirValue same = mir_b_icmp(b, MCC_EQ, sx, sy);
    const MirBlock both = mir_b_new_block(b);
    const MirBlock check = mir_b_new_block(b);
    mir_b_br_if(b, same, check, NULL, 0, no, NULL, 0);
    mir_b_seal_block(b, check);
    mir_b_switch_to(b, check);
    mir_b_br_if(b, sx, both, NULL, 0, yes, NULL, 0);
    mir_b_seal_block(b, both);
    mir_b_switch_to(b, both);
    const MirValue l = mir_b_emit(b, MOP_OptGet, &x, 1, (MirImm){0}, data->elem);
    const MirValue r = mir_b_emit(b, MOP_OptGet, &y, 1, (MirImm){0}, data->elem);
    const MirValue equal = lq_element(lb, b, data->elem, l, r);
    if (equal == MIR_NONE) {
        return false;
    }
    mir_b_br_if(b, equal, yes, NULL, 0, no, NULL, 0);
    return true;
}

/* The body comparing two lists: the lengths, then the elements in order. */
static bool lq_body_list(Lb *lb, MirBuilder *b, const MirTyData *data, MirValue x, MirValue y, MirBlock yes, MirBlock no) {
    const MirValue nx = mir_b_emit(b, MOP_ListLen, &x, 1, (MirImm){0}, MIR_INT);
    const MirValue ny = mir_b_emit(b, MOP_ListLen, &y, 1, (MirImm){0}, MIR_INT);
    const MirValue same = mir_b_icmp(b, MCC_EQ, nx, ny);
    const MirBlock header = mir_b_new_block(b);
    const MirBlock body = mir_b_new_block(b);
    const MirBlock latch = mir_b_new_block(b);
    const MirVar index = mir_b_declare_var(b, MIR_INT, MM_BORROW);
    mir_b_def_var(b, index, mir_b_iconst(b, 0));
    mir_b_br_if(b, same, header, NULL, 0, no, NULL, 0);
    mir_b_switch_to(b, header);
    const MirValue more = mir_b_icmp(b, MCC_LT, mir_b_use_var(b, index), nx);
    mir_b_br_if(b, more, body, NULL, 0, yes, NULL, 0);
    mir_b_seal_block(b, body);
    mir_b_switch_to(b, body);
    const MirValue at = mir_b_use_var(b, index);
    const MirValue lx[2] = {x, at};
    const MirValue ly[2] = {y, at};
    const MirValue l = mir_b_emit(b, MOP_ListGet, lx, 2, (MirImm){0}, data->elem);
    const MirValue r = mir_b_emit(b, MOP_ListGet, ly, 2, (MirImm){0}, data->elem);
    const MirValue equal = lq_element(lb, b, data->elem, l, r);
    if (equal == MIR_NONE) {
        return false;
    }
    mir_b_br_if(b, equal, latch, NULL, 0, no, NULL, 0);
    mir_b_seal_block(b, latch);
    mir_b_switch_to(b, latch);
    const MirValue next = mir_b_binop(b, MOP_IAdd, mir_b_use_var(b, index), mir_b_iconst(b, 1));
    mir_b_def_var(b, index, next);
    mir_b_br(b, header, NULL, 0);
    mir_b_seal_block(b, header);
    return true;
}

/* The body after the entry block: false when a part cannot be compared. */
static bool lq_body(Lb *lb, MirBuilder *b, MirTy ty, MirValue x, MirValue y, MirBlock yes, MirBlock no) {
    const MirTyData *data = mir_ty_data(lb->m, ty);
    switch (data->kind) {
    case MK_TYPE: return lq_body_record(lb, b, data, x, y, yes, no);
    case MK_ALT: return lq_body_alt(lb, b, data, x, y, yes, no);
    case MK_OPT: return lq_body_opt(lb, b, data, x, y, yes, no);
    case MK_LIST: return lq_body_list(lb, b, data, x, y, yes, no);
    default: return false;
    }
}

/* The function comparing two values of `ty`, made on first use; MIR_NONE when `ty` cannot be compared. */
static uint32_t lq_function(Lb *lb, MirTy ty) {
    for (uint32_t i = 0; i < lb->neqs; i++) {
        if (lb->eqs[i].ty == ty) {
            return lb->eqs[i].func;
        }
    }
    const MirParam params[2] = {{ty, MM_BORROW}, {ty, MM_BORROW}};
    MirBuilder b;
    mir_b_init(&b, lb->m, lb_unique_name(lb, (MsStr){"equal", 5}), params, 2, MIR_BOOL);
    MirValue operands[2];
    mir_b_params(&b, operands, 2);
    (void)mir_b_emit(&b, MOP_DepthEnter, NULL, 0, (MirImm){0}, MIR_NONE); // a comparison of recursive data recurses
    const MirBlock no = mir_b_new_block(&b);
    const MirBlock yes = mir_b_new_block(&b);
    const bool built = lq_body(lb, &b, ty, operands[0], operands[1], yes, no);
    uint32_t id = MIR_NONE;
    if (built) {
        mir_b_seal_block(&b, no);
        mir_b_seal_block(&b, yes);
        mir_b_switch_to(&b, no);
        mir_b_ret(&b, mir_b_bconst(&b, false));
        mir_b_switch_to(&b, yes);
        mir_b_ret(&b, mir_b_bconst(&b, true));
    }
    MirFunc f = {0};
    const bool done = mir_b_into_func(&b, &f);
    if (built && done) {
        mir_func_compact_blocks(&f);
        id = mir_add_func(lb->m, &f);
    }
    MIR_PUSH(lb->m, lb->eqs, lb->neqs, lb->ceqs, LbEq, ((LbEq){ty, id}));
    return id;
}

/* Whether a user wrote `impl Equal`: its `equals` decides for its type, which the generated function does not call. */
static bool lq_has_custom(const Lb *lb) {
    const MsMethods *methods = lb->facts->methods;
    for (uint32_t i = 0; i < methods->count; i++) {
        const MsTy contract = methods->contract[i];
        if (contract != MS_TY_NONE && ms_str_equal(ms_name(lb->c->names, lb->c->tys.name[contract]), (MsStr){"Equal", 5})) {
            return true;
        }
    }
    return false;
}

/* `x == y` on two borrowed aggregates; false when the operands are not ones this compares. */
LbVal lq_equal(Lb *lb, LbVal x, LbVal y, bool negate) {
    const MirTy ty = mir_b_ty(&lb->b, x.v);
    if (x.owned || y.owned || mir_b_ty(&lb->b, y.v) != ty || lq_has_custom(lb)) {
        return lb_unsupported(lb); // an owned temporary needs its drop placed
    }
    const uint32_t func = lq_function(lb, ty);
    if (func == MIR_NONE) {
        return lb_unsupported(lb);
    }
    const MirValue args[2] = {x.v, y.v};
    MirValue same = mir_b_call(&lb->b, func, args, 2);
    if (negate) {
        same = mir_b_emit(&lb->b, MOP_Not, &same, 1, (MirImm){0}, MIR_BOOL);
    }
    return (LbVal){same, false};
}

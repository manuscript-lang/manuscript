/* A native call that reports failure by a status, as a `Result[T, Error]`: `ok(value)` for status 0, else the `Error`
 * the module's status table names (stdlib `// ms: status`, `// ms: words`; rt_ops.h `ms_rt_status_rows`). One helper
 * per table builds the error, so a call site is a call and a branch (crates/ms-lower `status_result`). */
#include <string.h>

#include "ms/lower_internal.h"
#include "ms/mir_analysis.h"
#include "ms/rt_ops.h"

enum { LS_OK = 0, LS_ERROR = 1, LS_MAX_ROWS = 32 };

static MirValue ls_str(Lb *lb, MirBuilder *b, MsStr text) {
    const MirImm imm = {.tag = MI_STR, .a = mir_add_string(lb->m, text.ptr, text.len)};
    return mir_b_emit(b, MOP_StrLit, NULL, 0, imm, MIR_STR);
}

/* A copy of a literal the function owns. */
static MirValue ls_owned_str(Lb *lb, MirBuilder *b, MsStr text) {
    const MirValue lit = ls_str(lb, b, text);
    const MirImm one = {.tag = MI_INT, .i = 1};
    return mir_b_emit(b, MOP_Clone, &lit, 1, one, MIR_STR);
}

static void ls_drop(MirBuilder *b, MirValue v) {
    (void)mir_b_emit(b, MOP_Drop, &v, 1, (MirImm){0}, MIR_NONE);
}

static MsStr ls_cstr(const char *text) {
    return (MsStr){text, (uint32_t)strlen(text)};
}

/* The text a native said, joined to the status words: the words alone when it said nothing, its text alone when the
 * row's words are `-`. Returns the message. */
static MirValue ls_message(Lb *lb, MirBuilder *b, MirValue said, MirValue fallback, MirValue head, MirValue alone) {
    const MirBlock own = mir_b_new_block(b);
    const MirBlock extra = mir_b_new_block(b);
    mir_b_br_if(b, alone, own, NULL, 0, extra, NULL, 0);
    mir_b_seal_block(b, own);
    mir_b_seal_block(b, extra);
    mir_b_switch_to(b, own);
    ls_drop(b, fallback);
    const MirBlock outer = mir_b_new_block(b);
    const MirValue text = mir_b_add_block_param(b, outer, MIR_STR, MM_MOVE);
    mir_b_br(b, outer, &said, 1);
    mir_b_switch_to(b, extra);
    const MirValue length = mir_b_emit(b, MOP_StrLen, &said, 1, (MirImm){0}, MIR_INT);
    const MirValue has = mir_b_icmp(b, MCC_GT, length, mir_b_iconst(b, 0));
    const MirBlock both = mir_b_new_block(b);
    const MirBlock none = mir_b_new_block(b);
    mir_b_br_if(b, has, both, NULL, 0, none, NULL, 0);
    mir_b_seal_block(b, both);
    mir_b_seal_block(b, none);
    const MirBlock inner = mir_b_new_block(b);
    const MirValue joined = mir_b_add_block_param(b, inner, MIR_STR, MM_MOVE);
    mir_b_switch_to(b, both);
    const MirValue pair[2] = {head, said};
    const MirValue concat = mir_b_call_rt(b, lb_string_concat(lb), pair, 2);
    ls_drop(b, said);
    ls_drop(b, fallback);
    mir_b_br(b, inner, &concat, 1);
    mir_b_switch_to(b, none);
    ls_drop(b, said);
    mir_b_br(b, inner, &fallback, 1);
    mir_b_seal_block(b, inner);
    mir_b_switch_to(b, inner);
    mir_b_br(b, outer, &joined, 1);
    mir_b_seal_block(b, outer);
    mir_b_switch_to(b, outer);
    return text;
}

/* The function `(status[, text]) -> Error` for the rows: a chain of tests picks the row's strings, and the `Error`
 * is built once after it. MIR_NONE when the type is not the `Error` record. */
static uint32_t ls_build(Lb *lb, MirTy error, const MsStatusRow *rows, uint32_t count, const char *domain, bool said) {
    const MirTyData *data = mir_ty_data(lb->m, error);
    if (data->kind != MK_TYPE || lb->m->type_defs[data->id].nfields != 3) {
        return MIR_NONE;
    }
    const MirField *fields = lb->m->type_defs[data->id].fields;
    const MirParam params[2] = {{MIR_INT, MM_BORROW}, {MIR_STR, MM_MOVE}};
    MirBuilder b;
    mir_b_init(&b, lb->m, lb_unique_name(lb, (MsStr){"status_error", 12}), params, said ? 2 : 1, error);
    MirValue args[2];
    mir_b_params(&b, args, said ? 2 : 1);
    const MirVar kind = mir_b_declare_var(&b, MIR_STR, MM_MOVE);
    const MirVar fallback = mir_b_declare_var(&b, MIR_STR, MM_MOVE);
    const MirVar head = said ? mir_b_declare_var(&b, MIR_STR, MM_BORROW) : 0;
    const MirVar alone = said ? mir_b_declare_var(&b, MIR_BOOL, MM_BORROW) : 0;
    const MirBlock join = mir_b_new_block(&b);
    for (uint32_t i = 0; i < count; i++) {
        MirBlock next = MIR_NONE;
        if (i + 1 < count) {
            const MirValue hit = mir_b_icmp(&b, MCC_EQ, args[0], mir_b_iconst(&b, rows[i].status));
            const MirBlock yes = mir_b_new_block(&b);
            const MirBlock no = mir_b_new_block(&b);
            mir_b_br_if(&b, hit, yes, NULL, 0, no, NULL, 0);
            mir_b_seal_block(&b, yes);
            mir_b_seal_block(&b, no);
            mir_b_switch_to(&b, yes);
            next = no;
        }
        const bool own_text = strcmp(rows[i].words, "-") == 0;
        const MsStr text = own_text ? ms_arena_fmt(&lb->m->arena, "%s: failed", domain)
                                    : ms_arena_fmt(&lb->m->arena, "%s: %s", domain, rows[i].words);
        mir_b_def_var(&b, kind, ls_owned_str(lb, &b, ls_cstr(rows[i].kind)));
        mir_b_def_var(&b, fallback, ls_owned_str(lb, &b, text));
        if (said) {
            mir_b_def_var(&b, head, ls_str(lb, &b, ms_arena_fmt(&lb->m->arena, "%.*s: ", (int)text.len, text.ptr)));
            mir_b_def_var(&b, alone, mir_b_bconst(&b, own_text));
        }
        mir_b_br(&b, join, NULL, 0);
        if (next != MIR_NONE) {
            mir_b_switch_to(&b, next);
        }
    }
    mir_b_seal_block(&b, join);
    mir_b_switch_to(&b, join);
    const MirValue kind_value = mir_b_use_var(&b, kind);
    const MirValue fallback_value = mir_b_use_var(&b, fallback);
    MirValue message = fallback_value;
    if (said) {
        const MirValue head_value = mir_b_use_var(&b, head); // in this order: it is the order of the join's parameters
        const MirValue alone_value = mir_b_use_var(&b, alone);
        message = ls_message(lb, &b, args[1], fallback_value, head_value, alone_value);
    }
    const MirValue kind_opt = mir_b_emit(&b, MOP_OptSome, &kind_value, 1, (MirImm){0}, fields[1].ty);
    const uint32_t make = lb_runtime_extern(lb, "msrt_map_new", NULL, 0, fields[2].ty, MR_MAP_NEW, false);
    const MirValue details = mir_b_call_rt(&b, make, NULL, 0);
    const MirValue values[3] = {message, kind_opt, details};
    const MirImm imm = {.tag = MI_TYPE, .a = data->id};
    mir_b_ret(&b, mir_b_emit(&b, MOP_TypeNew, values, 3, imm, error));
    MirFunc f = {0};
    if (!mir_b_into_func(&b, &f)) {
        return MIR_NONE;
    }
    mir_func_compact_blocks(&f);
    return mir_add_func(lb->m, &f);
}

/* The error-building function of `fn`'s module for `error`, made on first use. */
static uint32_t ls_error_fn(Lb *lb, MirTy error, const MsRtFn *fn, bool said) {
    MsStatusRow rows[LS_MAX_ROWS];
    const size_t count = ms_rt_status_rows(fn, rows, LS_MAX_ROWS);
    if (count == 0 || count > LS_MAX_ROWS) {
        return MIR_NONE;
    }
    const char *domain = fn->domain[0] != '\0' ? fn->domain : "runtime";
    for (uint32_t i = 0; i < lb->nstatus_fns; i++) {
        const LbStatusFn *known = &lb->status_fns[i];
        bool same = known->error == error && known->said == said && known->nrows == count &&
                    strcmp(known->domain, domain) == 0;
        for (uint32_t k = 0; same && k < count; k++) {
            same = known->rows[k].status == rows[k].status && strcmp(known->rows[k].words, rows[k].words) == 0;
        }
        if (same) {
            return known->func;
        }
    }
    const uint32_t func = ls_build(lb, error, rows, (uint32_t)count, domain, said);
    MsStatusRow *kept = MS_NEW_N(&lb->m->arena, MsStatusRow, count);
    memcpy(kept, rows, count * sizeof *kept);
    MIR_PUSH(lb->m, lb->status_fns, lb->nstatus_fns, lb->cstatus_fns, LbStatusFn,
             ((LbStatusFn){error, said, domain, (uint32_t)count, kept, func}));
    return func;
}

/* Whether a call of `fn` for a `result_ty` is a status: the native returns one and the caller wants a `Result`. */
bool ls_reports_status(Lb *lb, const MsRtFn *fn, MirTy result_ty) {
    if (fn->ret != MS_RT_RET_BOOL || result_ty == MIR_VOID) {
        return false;
    }
    const MirTyData *data = mir_ty_data(lb->m, result_ty);
    return data->kind == MK_ALT && lb->m->alts[data->id].std == MSTD_RESULT;
}

/* `ok(value)` for status 0, else `error(...)` built from the status (and the text the native stored): the call of `fn`
 * on the evaluated `args`, whose result type is `result_ty` (a `Result[T, Error]`). Bare statuses and values written
 * through an `out` slot (a handle included) are lowered; a payload another shape builds (an interface, an Optional) is not, and
 * the call is left to the Rust lowering. */
LbVal ls_call(Lb *lb, const MsRtFn *fn, const MirValue *args, uint32_t nargs, MirTy result_ty) {
    const MirTyData *data = mir_ty_data(lb->m, result_ty);
    if (data->kind != MK_ALT || lb->m->alts[data->id].std != MSTD_RESULT || fn->ret != MS_RT_RET_BOOL) {
        return LB_UNSUPPORTED(lb);
    }
    const MirAltDef *alt = &lb->m->alts[data->id];
    const MirTy payload = alt->cases[LS_OK].fields[0].ty;
    const MirTy error = alt->cases[LS_ERROR].fields[0].ty;
    bool has_out = false;
    bool out_handle = false;
    bool out_record = false;
    for (uint32_t i = 0; i < fn->nparams; i++) {
        out_handle = out_handle || fn->params[i] == MS_RT_OUT_HANDLE;
        out_record = out_record || fn->params[i] == MS_RT_OUT_RECORD;
        has_out = has_out || fn->params[i] == MS_RT_OUT_STR || fn->params[i] == MS_RT_OUT_LIST ||
                  fn->params[i] == MS_RT_OUT_HANDLE || fn->params[i] == MS_RT_OUT_SCALAR || fn->params[i] == MS_RT_OUT_RECORD;
    }
    const bool plain = payload == MIR_STR || payload == MIR_BYTES || payload == MIR_INT || payload == MIR_FLOAT || payload == MIR_BOOL ||
                       payload == MIR_UINT64 || mir_ty_data(lb->m, payload)->kind == MK_LIST ||
                       (out_handle && mir_ty_data(lb->m, payload)->kind == MK_OBJ) ||
                       (out_record && mir_ty_data(lb->m, payload)->kind == MK_TYPE);
    if ((payload == MIR_VOID) == has_out || (has_out && !plain)) {
        return LB_UNSUPPORTED(lb);
    }
    const LbNativeStatus status = {.out_ty = has_out ? payload : MIR_NONE};
    LbNativeSlots slots;
    const MirValue raw = lb_native_status_call(lb, fn, args, nargs, &status, &slots);
    if (!lb->ok) {
        return LB_FAIL;
    }
    const uint32_t build = ls_error_fn(lb, error, fn, slots.err != MIR_NONE);
    if (build == MIR_NONE) {
        return LB_UNSUPPORTED(lb);
    }
    MirBuilder *b = &lb->b;
    const MirValue code = mir_b_binop(b, MOP_And, raw, mir_b_iconst(b, 0xff));
    const MirValue good = mir_b_icmp(b, MCC_EQ, code, mir_b_iconst(b, 0));
    const MirBlock yes = mir_b_new_block(b);
    const MirBlock no = mir_b_new_block(b);
    mir_b_br_if(b, good, yes, NULL, 0, no, NULL, 0);
    mir_b_seal_block(b, yes);
    mir_b_seal_block(b, no);
    const MirBlock join = mir_b_new_block(b);
    const bool owns = lb_owns(lb, result_ty);
    const MirValue result = mir_b_add_block_param(b, join, result_ty, owns ? MM_MOVE : MM_BORROW);
    mir_b_switch_to(b, yes);
    const MirValue value = has_out ? lo_take_out(lb, slots.out, payload) : mir_b_unit(b);
    const MirImm ok = {.tag = MI_CASE, .a = data->id, .b = LS_OK};
    const MirValue good_result = mir_b_emit(b, MOP_AltNew, &value, 1, ok, result_ty);
    mir_b_br(b, join, &good_result, 1);
    mir_b_switch_to(b, no);
    MirValue build_args[2] = {code, MIR_NONE};
    uint32_t nbuild = 1;
    if (slots.err != MIR_NONE) {
        build_args[nbuild++] = lo_take_out(lb, slots.err, MIR_STR);
    }
    const MirValue cause = mir_b_call(b, build, build_args, nbuild);
    const MirImm err = {.tag = MI_CASE, .a = data->id, .b = LS_ERROR};
    const MirValue bad_result = mir_b_emit(b, MOP_AltNew, &cause, 1, err, result_ty);
    mir_b_br(b, join, &bad_result, 1);
    mir_b_seal_block(b, join);
    mir_b_switch_to(b, join);
    return (LbVal){result, owns};
}

/* Whether `elem` is what the out parameter `kind` writes: a scalar, a String, or a list. */
static bool ls_out_matches(const Lb *lb, MsRtParam kind, MirTy elem) {
    switch (kind) {
    case MS_RT_OUT_SCALAR: return elem == MIR_INT || elem == MIR_FLOAT || elem == MIR_BOOL;
    case MS_RT_OUT_STR: return elem == MIR_STR;
    case MS_RT_OUT_LIST: return elem == MIR_BYTES || lb_is_list(lb, elem);
    case MS_RT_LIST: case MS_RT_LIST_VAR: case MS_RT_STR: case MS_RT_INT: case MS_RT_FLOAT: case MS_RT_BOOL:
    case MS_RT_UINT64: case MS_RT_MAP: case MS_RT_ALT: case MS_RT_ELEMENT: case MS_RT_DESC: case MS_RT_KEY_DESC:
    case MS_RT_VAL_DESC: case MS_RT_KEY_REF: case MS_RT_HANDLE: case MS_RT_OUT_HANDLE: case MS_RT_OUT_RECORD:
    case MS_RT_RECORD: case MS_RT_ERR: case MS_RT_HAS: case MS_RT_OTHER: return false;
    }
    return false;
}

bool ls_reports_found(Lb *lb, const MsRtFn *fn, MirTy result_ty) {
    if (fn->ret != MS_RT_RET_BOOL || result_ty == MIR_VOID || mir_ty_data(lb->m, result_ty)->kind != MK_OPT) {
        return false;
    }
    const MirTy elem = mir_ty_data(lb->m, result_ty)->elem;
    for (uint32_t i = 0; i < fn->nparams; i++) {
        if (ls_out_matches(lb, fn->params[i], elem)) {
            return true;
        }
    }
    return false;
}

/* `some(value)` when the native reports it found one, else `none`. */
LbVal ls_found_call(Lb *lb, const MsRtFn *fn, const MirValue *args, uint32_t nargs, MirTy result_ty) {
    const MirTy elem = mir_ty_data(lb->m, result_ty)->elem;
    const LbNativeStatus status = {.out_ty = elem, .found = true};
    LbNativeSlots slots;
    const MirValue found = lb_native_status_call(lb, fn, args, nargs, &status, &slots);
    if (!lb->ok) {
        return LB_FAIL;
    }
    MirBuilder *b = &lb->b;
    const MirBlock yes = mir_b_new_block(b);
    const MirBlock no = mir_b_new_block(b);
    mir_b_br_if(b, found, yes, NULL, 0, no, NULL, 0);
    mir_b_seal_block(b, yes);
    mir_b_seal_block(b, no);
    const MirBlock join = mir_b_new_block(b);
    const bool owns = lb_owns(lb, result_ty);
    const MirValue result = mir_b_add_block_param(b, join, result_ty, owns ? MM_MOVE : MM_BORROW);
    mir_b_switch_to(b, yes);
    const MirValue value = lo_take_out(lb, slots.out, elem);
    const MirValue some = mir_b_emit(b, MOP_OptSome, &value, 1, (MirImm){0}, result_ty);
    mir_b_br(b, join, &some, 1);
    mir_b_switch_to(b, no);
    const MirValue none = mir_b_emit(b, MOP_OptNoneOwned, NULL, 0, (MirImm){0}, result_ty);
    mir_b_br(b, join, &none, 1);
    mir_b_seal_block(b, join);
    mir_b_switch_to(b, join);
    return (LbVal){result, owns};
}

/* A call of a bodiless method the runtime implements. The runtime function is named by the
 * receiver's type and the method (`msrt_list_append` for `List.append`, `msrt_int_to_string` for
 * `Int.to_string`) and its parameters come from its `ms-sig` declaration (rt_ops.h): the receiver is
 * the first, the others are the call's arguments, an element descriptor is a `typedesc`, and an
 * `out` string or list is the result. A function tagged `@op=<mnemonic>` is that MIR instruction on
 * the arguments; any other is a runtime call. No type or method is named here. A method whose
 * signature the table cannot marshal (a handle, a slot, an error slot) is left to the Rust lowering. */
#include <ctype.h>
#include <stdlib.h>
#include <string.h>

#include "ms/lower_internal.h"
#include "ms/rt_ops.h"

/* `msrt_<type>_<method>`, the type in lower case. */
const MsRtFn *lb_native_function(Lb *lb, MsTy receiver, MsSym method) {
    return ms_rt_method_fn(lb->c, receiver, method);
}

/* The MIR type a value of parameter kind `kind` has, given the value passed (for a list). */
static MirTy ln_param_ty(MsRtParam kind, MirTy given) {
    switch (kind) {
    case MS_RT_INT: return MIR_INT;
    case MS_RT_FLOAT: return MIR_FLOAT;
    case MS_RT_BOOL: return MIR_BOOL;
    case MS_RT_STR: return MIR_STR;
    case MS_RT_DESC:
    case MS_RT_KEY_DESC:
    case MS_RT_VAL_DESC:
    case MS_RT_KEY_REF: return MIR_PTR;
    default: return given;
    }
}

static MirTy ln_ret_ty(MsRtRet ret) {
    switch (ret) {
    case MS_RT_RET_INT: return MIR_INT;
    case MS_RT_RET_FLOAT: return MIR_FLOAT;
    case MS_RT_RET_BOOL: return MIR_BOOL;
    default: return MIR_VOID;
    }
}

/* Which type a descriptor of role `kind` describes: 0 the element, 1 the key, 2 the value. */
static uint32_t ln_described(MsRtParam kind) {
    if (kind == MS_RT_KEY_DESC) {
        return 1;
    }
    return kind == MS_RT_VAL_DESC ? 2 : 0;
}

/* An optional scalar argument as the runtime takes it, `has, value` (`HasRaw` and the parameter after it): an optional
 * yields its presence and payload, a plain value is present. False when `value` is not a `want`. */
static bool ln_flatten_optional(Lb *lb, MirValue value, MirTy want, MirValue *has, MirValue *payload) {
    const MirTy given = mir_b_ty(&lb->b, value);
    if (given != MIR_NONE && mir_ty_data(lb->m, given)->kind == MK_OPT) {
        if (mir_ty_data(lb->m, given)->elem != want) {
            return false;
        }
        *has = mir_b_emit(&lb->b, MOP_OptIsSome, &value, 1, (MirImm){0}, MIR_BOOL);
        *payload = mir_b_emit(&lb->b, MOP_OptGet, &value, 1, (MirImm){0}, want);
        return true;
    }
    if (given != want) {
        return false;
    }
    *payload = value;
    *has = mir_b_bconst(&lb->b, true);
    return true;
}

/* Descriptors and key slots, made once the arguments are evaluated, in operand order; `kinds` is the parameter
 * kind of each operand. `of` is the type a descriptor describes by role (element, key, value). */
static bool ln_make_addresses(Lb *lb, MirValue *operands, uint32_t count, const MsRtParam *kinds, const bool *is_desc,
                              const bool *is_key_ref, const MirTy *of) {
    for (uint32_t i = 0; i < count; i++) {
        if (is_desc[i]) {
            const MirTy described = of[ln_described(kinds[i])];
            if (described == MIR_NONE) {
                return false;
            }
            operands[i] = mir_b_emit(&lb->b, MOP_TypeDesc, NULL, 0, (MirImm){.tag = MI_TY, .a = described}, MIR_PTR);
        } else if (is_key_ref[i]) {
            if (mir_b_ty(&lb->b, operands[i]) != of[1]) {
                return false;
            }
            const MirValue slot = mir_b_emit(&lb->b, MOP_Slot, NULL, 0, (MirImm){.tag = MI_TY, .a = of[1]}, MIR_PTR);
            lb_store(lb, slot, operands[i]);
            operands[i] = slot;
        }
    }
    return true;
}

/* The type a step of a `@seq=` tag names: `int`, `float` or `bool`. */
static MirTy ln_seq_ty(const char *name, size_t length) {
    if (length == 3 && memcmp(name, "int", 3) == 0) {
        return MIR_INT;
    }
    if (length == 5 && memcmp(name, "float", 5) == 0) {
        return MIR_FLOAT;
    }
    return length == 4 && memcmp(name, "bool", 4) == 0 ? MIR_BOOL : MIR_NONE;
}

/* A `@seq=` tag: comma-separated steps `mnemonic:operand:..>type`, each operand `$N` (argument N), `%N` (step N's
 * result) or `#value` (the immediate of an `iconst` or `fconst`). The last step is the result and takes `result_ty`. It
 * is the instruction sequence Rust's lowering emits for the same method, so the two compare equal. */
static bool ln_sequence(Lb *lb, const char *seq, const MirValue *args, uint32_t nargs, MirTy result_ty, MirValue *out) {
    MirValue steps[MS_RT_MAX_PARAMS * 2];
    uint32_t nsteps = 0;
    const char *p = seq;
    while (*p != '\0') {
        const char *end = strchr(p, ',');
        const char *stop = end != NULL ? end : p + strlen(p);
        const char *arrow = memchr(p, '>', (size_t)(stop - p));
        if (arrow == NULL || nsteps == sizeof steps / sizeof *steps) {
            return false;
        }
        const char *colon = memchr(p, ':', (size_t)(arrow - p));
        const char *name_end = colon != NULL ? colon : arrow;
        int op = mir_op_from_name(p, (size_t)(name_end - p));
        MirImm imm = {0};
        if (op < 0) { // `icmp.eq`: the comparison and its condition
            const char *dot = memchr(p, '.', (size_t)(name_end - p));
            const int head = dot != NULL ? mir_op_from_name(p, (size_t)(dot - p)) : -1;
            for (int cc = 0; head >= 0 && cc < 6; cc++) {
                if (strlen(mir_cc_name[cc]) == (size_t)(name_end - dot - 1) &&
                    memcmp(mir_cc_name[cc], dot + 1, (size_t)(name_end - dot - 1)) == 0) {
                    op = head;
                    imm = (MirImm){.tag = MI_CC, .a = (uint32_t)cc};
                }
            }
        }
        MirTy ty = ln_seq_ty(arrow + 1, (size_t)(stop - arrow - 1));
        if (op < 0 || ty == MIR_NONE) {
            return false;
        }
        MirValue operands[3];
        uint32_t noperands = 0;
        for (const char *q = colon; q != NULL && q < arrow;) {
            const char *item = q + 1;
            const char *item_end = memchr(item, ':', (size_t)(arrow - item));
            item_end = item_end != NULL ? item_end : arrow;
            char *tail = NULL;
            const long n = item[0] == '#' ? 0 : strtol(item + 1, &tail, 10);
            if (item[0] == '#') {
                if (op == MOP_FConst) {
                    const double value = strtod(item + 1, NULL);
                    imm.tag = MI_FLOAT;
                    memcpy(&imm.i, &value, sizeof value);
                } else {
                    imm.tag = MI_INT;
                    imm.i = strtoll(item + 1, NULL, 10);
                }
            } else if (noperands == 3 || tail != item_end) {
                return false;
            } else if (item[0] == '$' && (uint32_t)n < nargs) {
                operands[noperands++] = args[n];
            } else if (item[0] == '%' && (uint32_t)n < nsteps) {
                operands[noperands++] = steps[n];
            } else {
                return false;
            }
            q = item_end < arrow ? item_end : NULL;
        }
        if (end == NULL) {
            ty = result_ty;
        }
        steps[nsteps++] = mir_b_emit(&lb->b, (MirOp)op, operands, noperands, imm, ty);
        p = end != NULL ? end + 1 : stop;
    }
    if (nsteps == 0) {
        return false;
    }
    *out = steps[nsteps - 1];
    return true;
}

/* Calls `fn` on `args` (the receiver first, then the call's arguments, already evaluated), yielding
 * `result_ty`. A call in `status` mode yields the status the runtime returns (an int); the value it creates is
 * written through the `out` parameter into a slot of `out_ty`, and the slots are handed back in `slots` for the caller's
 * success and failure paths. False when the signature cannot be marshalled. */
static bool ln_marshal(Lb *lb, const MsRtFn *fn, const MirValue *args, uint32_t nargs, MirTy result_ty,
                       const LbNativeStatus *status, LbNativeSlots *slots, MirValue *out) {
    MirValue operands[MS_RT_MAX_PARAMS];
    MirTy types[MS_RT_MAX_PARAMS];
    MsRtParam kinds[MS_RT_MAX_PARAMS];
    bool is_desc[MS_RT_MAX_PARAMS] = {false};
    bool is_key_ref[MS_RT_MAX_PARAMS] = {false};
    MirTy map_ty = MIR_NONE;
    uint32_t count = 0;
    uint32_t next = 0;
    MirTy element = MIR_NONE;
    bool has_out = false;
    if (status != NULL) {
        *slots = (LbNativeSlots){MIR_NONE, MIR_NONE};
    }
    for (uint32_t i = 0; i < fn->nparams; i++) {
        const MsRtParam kind = fn->params[i];
        const bool needs_op = kind == MS_RT_LIST_VAR || kind == MS_RT_ELEMENT; // passed by address: only an instruction takes the value
        if (kind == MS_RT_OTHER || (needs_op && fn->op[0] == '\0')) {
            return false;
        }
        kinds[count] = kind;
        const bool is_out = kind == MS_RT_OUT_STR || kind == MS_RT_OUT_LIST || kind == MS_RT_OUT_HANDLE;
        if (kind == MS_RT_ERR || (is_out && status != NULL)) {
            if (status == NULL || (kind != MS_RT_ERR && status->out_ty == MIR_NONE)) {
                return false;
            }
            const MirValue slot = lo_out_slot(lb, kind == MS_RT_ERR ? MIR_STR : status->out_ty);
            *(kind == MS_RT_ERR ? &slots->err : &slots->out) = slot;
            types[count] = MIR_PTR;
            operands[count++] = slot;
        } else if (kind == MS_RT_OUT_HANDLE) {
            return false; // a handle written through a pointer needs the status split
        } else if (kind == MS_RT_OUT_STR || kind == MS_RT_OUT_LIST) {
            has_out = true;
        } else if (kind == MS_RT_DESC || kind == MS_RT_KEY_DESC || kind == MS_RT_VAL_DESC) {
            types[count] = MIR_PTR;
            is_desc[count] = true;
            operands[count++] = MIR_NONE; // the descriptor is made once the arguments are evaluated
        } else if (kind == MS_RT_HAS) {
            const MsRtParam payload = i + 1 < fn->nparams ? fn->params[i + 1] : MS_RT_OTHER;
            if (next == nargs || (payload != MS_RT_INT && payload != MS_RT_FLOAT && payload != MS_RT_BOOL) ||
                !ln_flatten_optional(lb, args[next++], ln_param_ty(payload, MIR_NONE), &operands[count],
                                     &operands[count + 1])) {
                return false;
            }
            types[count] = MIR_BOOL;
            kinds[count + 1] = payload;
            types[count + 1] = ln_param_ty(payload, MIR_NONE);
            count += 2;
            i++; // the payload parameter belongs to this argument
        } else {
            if (next == nargs) {
                return false;
            }
            const MirValue value = args[next++];
            const MirTy given = mir_b_ty(&lb->b, value);
            const bool list = kind == MS_RT_LIST || kind == MS_RT_LIST_VAR;
            if ((list && !lb_is_list(lb, given)) || (kind == MS_RT_MAP && !lb_is_map(lb, given))) {
                return false;
            }
            if (list) {
                element = mir_ty_data(lb->m, given)->elem;
            }
            if (kind == MS_RT_MAP) {
                map_ty = given;
            }
            is_key_ref[count] = kind == MS_RT_KEY_REF;
            operands[count] = value;
            types[count++] = ln_param_ty(kind, given);
        }
    }
    if (next != nargs || (has_out && (result_ty == MIR_NONE || result_ty == MIR_VOID))) {
        return false;
    }
    if (fn->twinned) {
        return false; // the result may be a view into an argument; choosing the twin is not lowered here yet
    }
    const bool is_op = fn->op[0] != '\0';
    const int op = is_op ? mir_op_from_name(fn->op, strlen(fn->op)) : -1;
    if (is_op && op < 0) {
        return false;
    }
    MirTy of[3] = {element, MIR_NONE, MIR_NONE}; // the type a descriptor describes: element, key, value
    const MsRtFn *entry = fn;
    uint8_t role = MR_NONE;
    if (map_ty != MIR_NONE) { // a function with a specialisation for the map's layout is called as that
        of[1] = mir_ty_data(lb->m, map_ty)->args[0];
        of[2] = mir_ty_data(lb->m, map_ty)->args[1];
        entry = lm_specialize(lb, fn, of[1], of[2], &role);
    }
    if (!ln_make_addresses(lb, operands, count, kinds, is_desc, is_key_ref, of)) {
        return false;
    }
    if (fn->seq[0] != '\0') { // a short sequence of instructions over the arguments, not the descriptors
        uint32_t kept = 0;
        for (uint32_t i = 0; i < count; i++) {
            if (!is_desc[i]) {
                operands[kept++] = operands[i];
            }
        }
        return ln_sequence(lb, fn->seq, operands, kept, result_ty, out);
    }
    if (is_op) { // an instruction takes the arguments, not the descriptor
        uint32_t kept = 0;
        for (uint32_t i = 0; i < count; i++) {
            if (!is_desc[i]) {
                operands[kept++] = operands[i];
            }
        }
        const MirImm imm = fn->has_imm ? (MirImm){.tag = MI_INT, .i = fn->imm} : (MirImm){0};
        *out = mir_b_emit(&lb->b, (MirOp)op, operands, kept, imm, result_ty);
        return true;
    }
    MirTy ret = has_out ? result_ty : ln_ret_ty(fn->ret);
    if (status != NULL) {
        ret = MIR_INT;
    }
    const uint32_t ext = lb_runtime_extern(lb, entry->symbol, types, count, ret, role, entry->pure);
    *out = mir_b_call_rt(&lb->b, ext, operands, count);
    return true;
}

/* A call of `fn` for the evaluated arguments; the result is owned when its type is. */
LbVal lb_native_call(Lb *lb, const MsRtFn *fn, const MirValue *args, uint32_t nargs, MirTy result_ty) {
    MirValue result = MIR_NONE;
    if (!ln_marshal(lb, fn, args, nargs, result_ty, NULL, NULL, &result)) {
        return lb_unsupported(lb);
    }
    return (LbVal){result, lb_owns(lb, result_ty)};
}

/* A call of a function that reports failure by a status (`-> u8`, 0 for success): the status, an int, is the
 * result, and `slots` holds the frame room the call wrote its value (`status->out_ty`) and failure text to. */
MirValue lb_native_status_call(Lb *lb, const struct MsRtFn *fn, const MirValue *args, uint32_t nargs,
                               const LbNativeStatus *status, LbNativeSlots *slots) {
    MirValue result = MIR_NONE;
    if (!ln_marshal(lb, fn, args, nargs, MIR_INT, status, slots, &result)) {
        (void)lb_unsupported(lb);
        return MIR_NONE;
    }
    return result;
}

/* The receiver of a by-reference list parameter: a `var` list local the function owns, whose
 * variable then holds what the instruction yields. */
static uint32_t ln_var_receiver(Lb *lb, const MsExpr *receiver) {
    if (receiver->kind != MS_E_NAME || lb->facts->res_kind[receiver->id] != MS_RES_BINDING) {
        return MS_NONE;
    }
    const uint32_t binding = lb->facts->res_ref[receiver->id];
    return lb->var_of[binding] != MIR_NONE && lb_var_owned(lb, binding) ? binding : MS_NONE;
}

/* A method call the runtime implements: evaluates the receiver and arguments, then calls. */
LbVal lb_native_method(Lb *lb, const MsExpr *e) {
    const MsExpr *callee = e->u.call.callee;
    const MsTy receiver_ty = lb->facts->call_receiver[e->id];
    const MsRtFn *fn = lb_native_function(lb, receiver_ty, callee->u.member.name);
    const uint32_t nargs = e->u.call.args.len;
    if (fn == NULL || fn->nparams == 0 || nargs + 1 > MS_RT_MAX_PARAMS) {
        return lb_unsupported(lb);
    }
    const MsExpr *receiver = callee->u.member.left;
    const bool by_reference = fn->params[0] == MS_RT_LIST_VAR;
    uint32_t binding = MS_NONE;
    LbVal first;
    if (by_reference) {
        binding = ln_var_receiver(lb, receiver);
        if (binding == MS_NONE) {
            return lb_unsupported(lb);
        }
        first = (LbVal){mir_b_use_var(&lb->b, lb->var_of[binding]), false};
    } else {
        first = lb_expr(lb, receiver);
    }
    if (!lb->ok) {
        return LB_FAIL;
    }
    const MirTy first_ty = mir_b_ty(&lb->b, first.v);
    const MirTy element = lb_is_list(lb, first_ty) ? mir_ty_data(lb->m, first_ty)->elem : MIR_NONE;
    MirValue args[MS_RT_MAX_PARAMS];
    args[0] = first.v;
    MsRtParam kinds[MS_RT_MAX_PARAMS];
    uint32_t value_params = 0;
    for (uint32_t i = 1; i < fn->nparams; i++) {
        const MsRtParam kind = fn->params[i];
        if (kind == MS_RT_HAS) {
            kinds[value_params++] = kind;
            i++; // its payload parameter takes no argument of its own
        } else if (kind != MS_RT_DESC && kind != MS_RT_KEY_DESC && kind != MS_RT_VAL_DESC && kind != MS_RT_OUT_STR &&
            kind != MS_RT_OUT_LIST) {
            kinds[value_params++] = fn->params[i];
        }
    }
    if (value_params != nargs) {
        return lb_unsupported(lb);
    }
    for (uint32_t i = 0; i < nargs && lb->ok; i++) {
        const MsExpr *argument = e->u.call.args.ptr[i].value;
        if (kinds[i] == MS_RT_ELEMENT && lb_owns(lb, element)) {
            args[i + 1] = lb_move_argument(lb, argument);
            continue;
        }
        const LbVal value = lb_expr(lb, argument);
        args[i + 1] = value.v;
        if (lb->ok && value.owned) {
            lb_hold_temp(lb, value.v); // a borrowed argument lives to the end of the statement
        }
    }
    const MirTy result_ty = by_reference ? first_ty : lb_mir_ty(lb, lb->facts->expr_ty[e->id]);
    if (!lb->ok) {
        return LB_FAIL;
    }
    const LbVal call = lb_native_call(lb, fn, args, nargs + 1, result_ty);
    if (!lb->ok) {
        return LB_FAIL;
    }
    if (by_reference) {
        mir_b_def_var(&lb->b, lb->var_of[binding], call.v);
        return (LbVal){mir_b_unit(&lb->b), false};
    }
    if (first.owned) {
        lb_hold_temp(lb, first.v); // a temporary receiver lives to the end of the statement
    }
    return call;
}

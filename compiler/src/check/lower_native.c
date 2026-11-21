/* A call of a bodiless method the runtime implements. The runtime function is named by the
 * receiver's type and the method (`msrt_list_append` for `List.append`, `msrt_int_to_string` for
 * `Int.to_string`) and its parameters come from its `ms-sig` declaration (rt_ops.h): the receiver is
 * the first, the others are the call's arguments, an element descriptor is a `typedesc`, and an
 * `out` string or list is the result. A function tagged `@op=<mnemonic>` is that MIR instruction on
 * the arguments; any other is a runtime call. No type or method is named here. A method whose
 * signature the table cannot marshal (a handle, a slot, an error slot) is left to the Rust lowering. */
#include <ctype.h>

#include "ms/lower_internal.h"
#include "ms/mir_pass.h"
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

/* Descriptors and key slots, made once the arguments are evaluated, in parameter order. `of` is the type a
 * descriptor describes by role (element, key, value). */
static bool ln_make_addresses(Lb *lb, const MsRtFn *fn, MirValue *operands, uint32_t count, const bool *is_desc,
                              const bool *is_key_ref, const MirTy *of) {
    for (uint32_t i = 0, param = 0; i < count; i++, param++) {
        while (param < fn->nparams && (fn->params[param] == MS_RT_OUT_STR || fn->params[param] == MS_RT_OUT_LIST)) {
            param++;
        }
        const MsRtParam kind = fn->params[param];
        if (is_desc[i]) {
            const MirTy described = of[ln_described(kind)];
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

/* Calls `fn` on `args` (the receiver first, then the call's arguments, already evaluated), yielding
 * `result_ty`. `variable` is the variable that holds a by-reference list, which then holds what the
 * function yields. Null when the signature cannot be marshalled. */
static bool ln_marshal(Lb *lb, const MsRtFn *fn, const MirValue *args, uint32_t nargs, MirTy result_ty, MirValue *out) {
    MirValue operands[MS_RT_MAX_PARAMS];
    MirTy types[MS_RT_MAX_PARAMS];
    bool is_desc[MS_RT_MAX_PARAMS] = {false};
    bool is_key_ref[MS_RT_MAX_PARAMS] = {false};
    MirTy map_ty = MIR_NONE;
    uint32_t count = 0;
    uint32_t next = 0;
    MirTy element = MIR_NONE;
    bool has_out = false;
    for (uint32_t i = 0; i < fn->nparams; i++) {
        const MsRtParam kind = fn->params[i];
        const bool needs_op = kind == MS_RT_LIST_VAR || kind == MS_RT_ELEMENT; // passed by address: only an instruction takes the value
        if (kind == MS_RT_OTHER || (needs_op && fn->op[0] == '\0')) {
            return false;
        }
        if (kind == MS_RT_OUT_STR || kind == MS_RT_OUT_LIST) {
            has_out = true;
        } else if (kind == MS_RT_DESC || kind == MS_RT_KEY_DESC || kind == MS_RT_VAL_DESC) {
            types[count] = MIR_PTR;
            is_desc[count] = true;
            operands[count++] = MIR_NONE; // the descriptor is made once the arguments are evaluated
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
    if (!ln_make_addresses(lb, fn, operands, count, is_desc, is_key_ref, of)) {
        return false;
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
    const MirTy ret = has_out ? result_ty : ln_ret_ty(fn->ret);
    const uint32_t ext = lb_runtime_extern(lb, entry->symbol, types, count, ret, role, entry->pure);
    *out = mir_b_call_rt(&lb->b, ext, operands, count);
    return true;
}

/* A call of `fn` for the evaluated arguments; the result is owned when its type is. */
LbVal lb_native_call(Lb *lb, const MsRtFn *fn, const MirValue *args, uint32_t nargs, MirTy result_ty) {
    MirValue result = MIR_NONE;
    if (!ln_marshal(lb, fn, args, nargs, result_ty, &result)) {
        return lb_unsupported(lb);
    }
    return (LbVal){result, lb_owns(lb, result_ty)};
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
        if (kind != MS_RT_DESC && kind != MS_RT_KEY_DESC && kind != MS_RT_VAL_DESC && kind != MS_RT_OUT_STR &&
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

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
    case MS_RT_UINT64: return MIR_UINT64;
    case MS_RT_STR: return MIR_STR;
    case MS_RT_DESC:
    case MS_RT_KEY_DESC:
    case MS_RT_VAL_DESC:
    case MS_RT_KEY_REF:
    case MS_RT_RECORD: return MIR_PTR;
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

/* The values a `@seq=` step can name: the call's arguments (`$N`) and the results of the steps before it (`%N`). */
typedef struct LnOperands {
    const MirValue *args;
    uint32_t nargs;
    const MirValue *steps;
    uint32_t nsteps;
} LnOperands;

static bool ln_operand(char sigil, long n, LnOperands from, MirValue *out) {
    if (sigil == '$' && n >= 0 && (uint32_t)n < from.nargs) {
        *out = from.args[n];
        return true;
    }
    if (sigil == '%' && n >= 0 && (uint32_t)n < from.nsteps) {
        *out = from.steps[n];
        return true;
    }
    return false;
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
            } else if (noperands == 3 || tail != item_end ||
                       !ln_operand(item[0], n, (LnOperands){args, nargs, steps, nsteps}, &operands[noperands])) {
                return false;
            } else {
                noperands++;
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

/* What the parameters of a runtime function make of the evaluated arguments: one operand per runtime parameter, in
 * order (`kinds` and `types` say what each is), and what the descriptors and the result need to know. */
typedef struct LnCall {
    MirValue operands[MS_RT_MAX_PARAMS];
    MirTy types[MS_RT_MAX_PARAMS];
    MsRtParam kinds[MS_RT_MAX_PARAMS];
    bool is_desc[MS_RT_MAX_PARAMS];
    bool is_key_ref[MS_RT_MAX_PARAMS];
    uint32_t count;
    uint32_t next; // the next argument
    MirTy element; // the element type of a list argument
    MirTy map_ty;
    bool has_out; // a string or list result written through a pointer
} LnCall;

static void ln_push(LnCall *call, MsRtParam kind, MirValue operand, MirTy type) {
    call->kinds[call->count] = kind;
    call->types[call->count] = type;
    call->operands[call->count++] = operand;
}

/* A value stored in a fresh slot of `ty`, whose address the call takes. */
static MirValue ln_slot_of(Lb *lb, MirTy ty, MirValue value) {
    const MirValue slot = mir_b_emit(&lb->b, MOP_Slot, NULL, 0, (MirImm){.tag = MI_TY, .a = ty}, MIR_PTR);
    lb_store(lb, slot, value);
    return slot;
}

/* Descriptors and slots for keys and records, made once the arguments are evaluated, in operand order. `of` is the
 * type a descriptor describes by role (element, key, value). */
static bool ln_make_addresses(Lb *lb, LnCall *call, const MirTy *of) {
    for (uint32_t i = 0; i < call->count; i++) {
        MirValue *operand = &call->operands[i];
        if (call->is_desc[i]) {
            const MirTy described = of[ln_described(call->kinds[i])];
            if (described == MIR_NONE) {
                return false;
            }
            *operand = mir_b_emit(&lb->b, MOP_TypeDesc, NULL, 0, (MirImm){.tag = MI_TY, .a = described}, MIR_PTR);
        } else if (call->is_key_ref[i]) {
            if (mir_b_ty(&lb->b, *operand) != of[1]) {
                return false;
            }
            *operand = ln_slot_of(lb, of[1], *operand);
        } else if (call->kinds[i] == MS_RT_RECORD) {
            *operand = ln_slot_of(lb, mir_b_ty(&lb->b, *operand), *operand);
        }
    }
    return true;
}

/* The frame room for the `out` value or the failure text of a status call. */
static bool ln_slot_param(Lb *lb, LnCall *call, MsRtParam kind, const LbNativeStatus *status, LbNativeSlots *slots) {
    if (status == NULL || (kind != MS_RT_ERR && status->out_ty == MIR_NONE)) {
        return false; // an out handle or an error slot needs the status split
    }
    const MirValue slot = lo_out_slot(lb, kind == MS_RT_ERR ? MIR_STR : status->out_ty);
    if (kind == MS_RT_ERR) {
        slots->err = slot;
    } else {
        slots->out = slot;
    }
    ln_push(call, kind, slot, MIR_PTR);
    return true;
}

/* `HasRaw` and the parameter after it, which take one optional scalar argument. */
static bool ln_has_param(Lb *lb, LnCall *call, const MsRtFn *fn, uint32_t at, const MirValue *args, uint32_t nargs) {
    const MsRtParam payload = at + 1 < fn->nparams ? fn->params[at + 1] : MS_RT_OTHER;
    if (call->next == nargs || (payload != MS_RT_INT && payload != MS_RT_FLOAT && payload != MS_RT_BOOL)) {
        return false;
    }
    const MirValue value = args[call->next];
    call->next++;
    MirValue has = MIR_NONE;
    MirValue scalar = MIR_NONE;
    if (!ln_flatten_optional(lb, value, ln_param_ty(payload, MIR_NONE), &has, &scalar)) {
        return false;
    }
    ln_push(call, MS_RT_HAS, has, MIR_BOOL);
    ln_push(call, payload, scalar, ln_param_ty(payload, MIR_NONE));
    return true;
}

/* A parameter that takes the next argument as it is. */
static bool ln_value_param(Lb *lb, LnCall *call, MsRtParam kind, const MirValue *args, uint32_t nargs) {
    if (call->next == nargs) {
        return false;
    }
    const MirValue value = args[call->next];
    call->next++;
    const MirTy given = mir_b_ty(&lb->b, value);
    const bool list = kind == MS_RT_LIST || kind == MS_RT_LIST_VAR;
    const bool bytes = kind == MS_RT_LIST && given == MIR_BYTES; // a `Bytes` is a list of bytes to a borrowing native
    if ((list && !bytes && !lb_is_list(lb, given)) || (kind == MS_RT_MAP && !lb_is_map(lb, given))) {
        return false;
    }
    const bool scalar = kind == MS_RT_INT || kind == MS_RT_FLOAT || kind == MS_RT_BOOL || kind == MS_RT_STR ||
                        kind == MS_RT_UINT64;
    if (scalar && given != ln_param_ty(kind, given)) {
        return false; // an optional or a sized integer for a plain word: the call converts it, and this does not
    }
    if (kind == MS_RT_RECORD && (given == MIR_NONE || mir_ty_data(lb->m, given)->kind != MK_TYPE)) {
        return false;
    }
    if (bytes) {
        call->element = MIR_UINT8;
    } else if (list) {
        call->element = mir_ty_data(lb->m, given)->elem;
    }
    if (kind == MS_RT_MAP) {
        call->map_ty = given;
    }
    call->is_key_ref[call->count] = kind == MS_RT_KEY_REF;
    ln_push(call, kind, value, ln_param_ty(kind, given));
    return true;
}

/* The operand of parameter `at` of `fn` (two, for a `HasRaw` pair); false when it cannot be made. `*at` moves past
 * the parameters used. */
static bool ln_param(Lb *lb, LnCall *call, const MsRtFn *fn, uint32_t *at, const MirValue *args, uint32_t nargs,
                     const LbNativeStatus *status, LbNativeSlots *slots) {
    const MsRtParam kind = fn->params[*at];
    const bool needs_op = kind == MS_RT_LIST_VAR || kind == MS_RT_ELEMENT; // passed by address: only an instruction takes the value
    if (kind == MS_RT_OTHER || (needs_op && fn->op[0] == '\0')) {
        return false;
    }
    if (kind == MS_RT_ERR || kind == MS_RT_OUT_HANDLE || kind == MS_RT_OUT_SCALAR ||
        (status != NULL && (kind == MS_RT_OUT_STR || kind == MS_RT_OUT_LIST || kind == MS_RT_OUT_RECORD))) {
        return ln_slot_param(lb, call, kind, status, slots);
    }
    if (kind == MS_RT_OUT_STR || kind == MS_RT_OUT_LIST || (kind == MS_RT_OUT_RECORD && status == NULL)) {
        call->has_out = true;
        return true;
    }
    if (kind == MS_RT_DESC || kind == MS_RT_KEY_DESC || kind == MS_RT_VAL_DESC) {
        call->is_desc[call->count] = true;
        ln_push(call, kind, MIR_NONE, MIR_PTR); // the descriptor is made once the arguments are evaluated
        return true;
    }
    if (kind == MS_RT_HAS) {
        (*at)++; // the payload parameter belongs to this argument
        return ln_has_param(lb, call, fn, *at - 1, args, nargs);
    }
    return ln_value_param(lb, call, kind, args, nargs);
}

/* Compacts the operands the instruction takes: the descriptors are not among them. Returns their number. */
static uint32_t ln_without_descriptors(LnCall *call) {
    uint32_t kept = 0;
    for (uint32_t i = 0; i < call->count; i++) {
        if (!call->is_desc[i]) {
            call->operands[kept] = call->operands[i];
            kept++;
        }
    }
    return kept;
}

/* A call of a function that returns a view of its receiver: it writes the view through a slot, and the load yields a
 * value the MIR does not own, so nothing releases it. */
static bool ln_emit_view(Lb *lb, const MsRtFn *fn, LnCall *call, MirTy result_ty, MirValue *out) {
    const MirValue slot = mir_b_emit(&lb->b, MOP_Slot, NULL, 0, (MirImm){.tag = MI_TY, .a = result_ty}, MIR_PTR);
    ln_push(call, MS_RT_OUT_STR, slot, MIR_PTR);
    const uint32_t ext = lb_runtime_extern(lb, fn->symbol, call->types, call->count, MIR_VOID, MR_NONE, false);
    (void)mir_b_call_rt(&lb->b, ext, call->operands, call->count);
    *out = lb_load(lb, slot, result_ty);
    return true;
}

/* Emits the call, instruction or sequence the operands of `call` make for `fn`. */
static bool ln_emit(Lb *lb, const MsRtFn *fn, LnCall *call, MirTy result_ty, const LbNativeStatus *status, MirValue *out) {
    const bool is_op = fn->op[0] != '\0';
    const int op = is_op ? mir_op_from_name(fn->op, strlen(fn->op)) : -1;
    if (is_op && op < 0) {
        return false;
    }
    MirTy of[3] = {call->element, MIR_NONE, MIR_NONE}; // the type a descriptor describes: element, key, value
    const MsRtFn *entry = fn;
    uint8_t role = MR_NONE;
    if (call->map_ty != MIR_NONE) { // a function with a specialisation for the map's layout is called as that
        of[1] = mir_ty_data(lb->m, call->map_ty)->args[0];
        of[2] = mir_ty_data(lb->m, call->map_ty)->args[1];
        entry = lm_specialize(lb, fn, of[1], of[2], &role);
    }
    if (!ln_make_addresses(lb, call, of)) {
        return false;
    }
    if (fn->seq[0] != '\0') { // a short sequence of instructions over the arguments, not the descriptors
        const uint32_t kept = ln_without_descriptors(call);
        return ln_sequence(lb, fn->seq, call->operands, kept, result_ty, out);
    }
    if (is_op) { // an instruction takes the arguments, not the descriptor
        const uint32_t kept = ln_without_descriptors(call);
        const MirImm imm = fn->has_imm ? (MirImm){.tag = MI_INT, .i = fn->imm} : (MirImm){0};
        *out = mir_b_emit(&lb->b, (MirOp)op, call->operands, kept, imm, result_ty);
        return true;
    }
    if (fn->borrows && call->has_out && status == NULL) {
        return ln_emit_view(lb, fn, call, result_ty, out);
    }
    MirTy ret = call->has_out || fn->ret == MS_RT_RET_HANDLE ? result_ty : ln_ret_ty(fn->ret);
    if (status != NULL) {
        ret = status->found ? MIR_BOOL : MIR_INT;
    }
    const uint32_t ext = lb_runtime_extern(lb, entry->symbol, call->types, call->count, ret, role, entry->pure);
    *out = mir_b_call_rt(&lb->b, ext, call->operands, call->count);
    return true;
}

/* Calls `fn` on `args` (the receiver first, then the call's arguments, already evaluated), yielding
 * `result_ty`. A call in `status` mode yields the status the runtime returns (an int); the value it creates is
 * written through the `out` parameter into a slot of `out_ty`, and the slots are handed back in `slots` for the caller's
 * success and failure paths. False when the signature cannot be marshalled. */
static bool ln_marshal(Lb *lb, const MsRtFn *fn, const MirValue *args, uint32_t nargs, MirTy result_ty,
                       const LbNativeStatus *status, LbNativeSlots *slots, MirValue *out) {
    LnCall call = {.element = MIR_NONE, .map_ty = MIR_NONE};
    if (status != NULL) {
        *slots = (LbNativeSlots){MIR_NONE, MIR_NONE};
    }
    for (uint32_t i = 0; i < fn->nparams; i++) {
        if (!ln_param(lb, &call, fn, &i, args, nargs, status, slots)) {
            return false;
        }
    }
    const bool missing_result = call.has_out && (result_ty == MIR_NONE || result_ty == MIR_VOID);
    if (call.next != nargs || missing_result || (fn->twinned && !lb->twin_ok)) { // a twinned result may be a view into an argument; choosing the twin is not lowered here yet
        return false;
    }
    return ln_emit(lb, fn, &call, result_ty, status, out);
}

/* A call of `fn` for the evaluated arguments; the result is owned when its type is, unless `fn` returns a view of its receiver. */
LbVal lb_native_call(Lb *lb, const MsRtFn *fn, const MirValue *args, uint32_t nargs, MirTy result_ty) {
    MirValue result = MIR_NONE;
    if (!ln_marshal(lb, fn, args, nargs, result_ty, NULL, NULL, &result)) {
        return LB_UNSUPPORTED(lb);
    }
    return (LbVal){result, lb_owns(lb, result_ty) && !fn->borrows};
}

/* A call of a function that reports failure by a status (`-> u8`, 0 for success): the status, an int, is the
 * result, and `slots` holds the frame room the call wrote its value (`status->out_ty`) and failure text to. */
MirValue lb_native_status_call(Lb *lb, const struct MsRtFn *fn, const MirValue *args, uint32_t nargs,
                               const LbNativeStatus *status, LbNativeSlots *slots) {
    MirValue result = MIR_NONE;
    if (!ln_marshal(lb, fn, args, nargs, MIR_INT, status, slots, &result)) {
        (void)LB_UNSUPPORTED(lb);
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

/* A method of a number that no runtime function implements: a conversion to another number. */
static LbVal ln_conversion_method(Lb *lb, const MsExpr *e) {
    if (!lb_is_conversion_name(lb, e->u.call.callee->u.member.name)) {
        return LB_UNSUPPORTED(lb);
    }
    const LbVal receiver = lb_expr(lb, e->u.call.callee->u.member.left);
    LbVal converted;
    if (!lb->ok || !lb_numeric_conversion(lb, receiver.v, lb->facts->expr_ty[e->id], &converted)) {
        return LB_UNSUPPORTED(lb);
    }
    return converted;
}

/* A method no runtime function implements: `abs` or `sign` of an Int, `to_string`, or a conversion to another number. */
static LbVal ln_method_without_function(Lb *lb, const MsExpr *e, MsTy receiver_ty) {
    const MsExpr *callee = e->u.call.callee;
    LbVal int_result;
    if (lb_int_method(lb, e, receiver_ty, &int_result)) {
        return int_result;
    }
    if (e->u.call.args.len != 0) {
        return LB_UNSUPPORTED(lb);
    }
    if (ms_name_is(lb->c->names, callee->u.member.name, "to_string")) {
        const LbVal value = lb_expr(lb, callee->u.member.left); // a String is its own text, a scalar prints through its runtime form
        return lb->ok ? lt_to_string(lb, value, receiver_ty) : LB_FAIL;
    }
    return ln_conversion_method(lb, e);
}

/* A method call the runtime implements: evaluates the receiver and arguments, then calls. */
LbVal lb_native_method(Lb *lb, const MsExpr *e) {
    const MsExpr *callee = e->u.call.callee;
    const MsTy receiver_ty = lb_ty(lb, lb->facts->call_receiver[e->id]); // a generic's receiver is its instance's type
    const MsRtFn *fn = lb_native_function(lb, receiver_ty, callee->u.member.name);
    const uint32_t nargs = e->u.call.args.len;
    if (fn == NULL) {
        return ln_method_without_function(lb, e, receiver_ty);
    }
    if (fn->nparams == 0 || nargs + 1 > MS_RT_MAX_PARAMS) {
        return LB_UNSUPPORTED(lb);
    }
    if (lb->facts->call_borrows[e->id] && !fn->borrows && lb->iterable != e) {
        return LB_UNSUPPORTED(lb); // a borrowed list used outside a `for` is lent by a twin that is not lowered yet
    }
    const MsExpr *receiver = callee->u.member.left;
    const bool by_reference = fn->params[0] == MS_RT_LIST_VAR;
    uint32_t binding = MS_NONE;
    LbVal first;
    if (by_reference) {
        binding = ln_var_receiver(lb, receiver);
        if (binding == MS_NONE) {
            return LB_UNSUPPORTED(lb);
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
        return LB_UNSUPPORTED(lb);
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
    lb->twin_ok = lb->iterable == e;
    const LbVal call = lb_native_call(lb, fn, args, nargs + 1, result_ty);
    lb->twin_ok = false;
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

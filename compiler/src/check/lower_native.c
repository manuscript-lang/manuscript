/* A call of a bodiless method the runtime implements: the runtime function is named by the
 * receiver's type and the method (`msrt_list_append` for `List.append`), and when its `ms-sig` is
 * tagged `@op=<mnemonic>` (runtime/include/ms_rt) the call is that MIR instruction on the receiver
 * and the arguments. Each parameter's role comes from its declared type (rt_ops.h), so no type or
 * method is named here. A method with no tagged function is left to the Rust lowering. */
#include <ctype.h>

#include "ms/lower_internal.h"
#include "ms/rt_ops.h"

/* `msrt_<type>_<method>`, the type in lower case. */
static const MsRtOp *ln_function(Lb *lb, MsTy receiver, MsSym method) {
    const MsStr type = ms_name(lb->c->names, lb->c->tys.name[receiver]);
    const MsStr name = ms_name(lb->c->names, method);
    const size_t size = type.len + name.len + 8;
    char *symbol = MS_NEW_N(&lb->b.scratch, char, size);
    size_t length = 0;
    for (const char *part = "msrt_"; *part != '\0'; part++) {
        symbol[length++] = *part;
    }
    for (size_t i = 0; i < type.len; i++) {
        symbol[length++] = (char)tolower((unsigned char)type.ptr[i]);
    }
    symbol[length++] = '_';
    for (size_t i = 0; i < name.len; i++) {
        symbol[length++] = name.ptr[i];
    }
    return ms_rt_op_find(symbol, length);
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

LbVal lb_native_method(Lb *lb, const MsExpr *e) {
    const MsExpr *callee = e->u.call.callee;
    const MsTy receiver_ty = lb->facts->call_receiver[e->id];
    const MsRtOp *fn = ln_function(lb, receiver_ty, callee->u.member.name);
    if (fn != NULL && fn->op[0] == '\0') {
        return lm_runtime_method(lb, e, fn); // a runtime call, not one instruction
    }
    const int op = fn == NULL ? -1 : mir_op_from_name(fn->op, strlen(fn->op));
    if (op < 0 || !lb_is_list(lb, lb_mir_ty(lb, receiver_ty))) {
        return lb_unsupported(lb);
    }
    uint32_t wanted = 0;
    for (uint32_t i = 0; i < fn->nparams; i++) {
        wanted += fn->params[i] == MS_RT_VALUE ? 1u : 0u;
    }
    if (e->u.call.args.len != wanted || fn->nparams == 0) {
        return lb_unsupported(lb);
    }
    const MsExpr *receiver = callee->u.member.left;
    const bool by_reference = fn->params[0] == MS_RT_LIST_VAR;
    uint32_t binding = MS_NONE;
    LbVal list;
    if (by_reference) {
        binding = ln_var_receiver(lb, receiver);
        if (binding == MS_NONE) {
            return lb_unsupported(lb);
        }
        list = (LbVal){mir_b_use_var(&lb->b, lb->var_of[binding]), false};
    } else {
        list = lb_expr(lb, receiver);
    }
    if (!lb->ok) {
        return LB_FAIL;
    }
    const MirTy list_ty = mir_b_ty(&lb->b, list.v);
    const MirTy element = lb_is_list(lb, list_ty) ? mir_ty_data(lb->m, list_ty)->elem : MIR_NONE;
    MirValue operands[MS_RT_MAX_PARAMS];
    uint32_t count = 0;
    uint32_t next_argument = 0;
    for (uint32_t i = 0; i < fn->nparams && lb->ok; i++) {
        if (fn->params[i] == MS_RT_LIST || fn->params[i] == MS_RT_LIST_VAR) {
            operands[count++] = list.v;
        } else if (fn->params[i] != MS_RT_DESC) {
            const MsExpr *argument = e->u.call.args.ptr[next_argument++].value;
            const MirValue value = lb_owns(lb, element) ? lb_move_argument(lb, argument) : lb_expr(lb, argument).v;
            operands[count++] = value;
        }
    }
    if (!lb->ok || element == MIR_NONE) {
        return lb_unsupported(lb);
    }
    for (uint32_t i = 0; i < fn->nparams; i++) { // the descriptor of the element type follows the arguments
        if (fn->params[i] == MS_RT_DESC) {
            (void)mir_b_emit(&lb->b, MOP_TypeDesc, NULL, 0, (MirImm){.tag = MI_TY, .a = element}, MIR_PTR);
        }
    }
    const MirTy result_ty = by_reference ? list_ty : lb_mir_ty(lb, lb->facts->expr_ty[e->id]);
    LbVal result;
    if (by_reference) {
        mir_b_def_var(&lb->b, lb->var_of[binding], mir_b_emit(&lb->b, (MirOp)op, operands, count, (MirImm){0}, result_ty));
        result = (LbVal){mir_b_unit(&lb->b), false};
    } else {
        result = (LbVal){mir_b_emit(&lb->b, (MirOp)op, operands, count, (MirImm){0}, result_ty), false};
        if (list.owned) {
            lb_hold_temp(lb, list.v); // a temporary receiver lives to the end of the statement
        }
    }
    return result;
}

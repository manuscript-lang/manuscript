/* Interface values in the lowering: an `interface` without type parameters is a MIR `dyn` type with
 * one method signature per operation, and `value.operation(args)` on a value of that type is
 * `call.method`, dispatched at run time through the value's vtable. Operations with type variables
 * of their own are static dispatch only, so the interface has no slot for them; an operation that
 * takes or gives `Self`, moves or changes an argument, or has a type this pass does not lower leaves
 * the interface to the Rust lowering. Values enter an interface (`iface.new` and the vtables) where a
 * concrete value is passed as one, which the checker does not record yet. */
#include <stdio.h>
#include <string.h>

#include "ms/lower_internal.h"
#include "ms/methods.h"

/* The operations of the interface `ty`, in declaration order. */
static const MsOperations *li_operations(const Lb *lb, MsTy ty) {
    const MsTyTable *tys = &lb->c->tys;
    // `facts->methods` is the first member of the program's method table.
    const MsMethodTable *table = (const MsMethodTable *)lb->facts->methods;
    return ms_interface_operations(table, tys->def[ty] - 1);
}

/* The slot of operation `index` among the ones the interface keeps, or MS_NONE for one it skips. */
static uint32_t li_slot(const MsOperations *ops, uint32_t index) {
    uint32_t slot = 0;
    for (uint32_t i = 0; i < index; i++) {
        slot += ops->items[i].nvars == 0 ? 1u : 0u;
    }
    return ops->items[index].nvars == 0 ? slot : MS_NONE;
}

/* One operation's signature (receiver left out); false when this pass does not lower it. */
static bool li_signature(Lb *lb, const MsOperation *op, MirMethodSig *out) {
    const MsTyTable *tys = &lb->c->tys;
    if (ms_ty_kind(tys, op->ty) != MS_K_FUNCTION || op->decl->consuming) {
        return false;
    }
    const uint32_t count = tys->nparams[op->ty];
    MirTy *params = MS_NEW_N(&lb->m->arena, MirTy, (size_t)count + 1);
    for (uint32_t i = 0; i < count; i++) {
        const MsTyParam *param = &ms_ty_params(tys, op->ty)[i];
        params[i] = param->flags == 0 || param->flags == MS_PARAM_POSITIONAL ? lb_mir_ty(lb, param->ty) : MIR_NONE;
        if (params[i] == MIR_NONE) {
            return false;
        }
    }
    const MsTy result = tys->result[op->ty];
    const MirTy ret = result == lb->void_ty ? MIR_VOID : lb_mir_ty(lb, result);
    const MsStr name = ms_name(lb->c->names, op->decl->func.name);
    *out = (MirMethodSig){.name = mir_name(lb->m, name.ptr, name.len), .params = params, .nparams = count, .ret = ret};
    return ret != MIR_NONE;
}

MirTy li_type(Lb *lb, MsTy ty) {
    const MsTyTable *tys = &lb->c->tys;
    if (ms_ty_kind(tys, ty) != MS_K_CONTRACT || tys->nargs[ty] != 0 || tys->def[ty] == 0 || tys->builtin[ty] != 0) {
        return MIR_NONE;
    }
    if (lb->type_of[ty] == LB_TYPE_PENDING) {
        return MIR_NONE; // an operation that mentions its own interface is not lowered
    }
    if (lb->type_of[ty] != MIR_NONE) {
        return lb->type_of[ty];
    }
    const MsOperations *ops = li_operations(lb, ty);
    if (ops == NULL) {
        return MIR_NONE;
    }
    lb->type_of[ty] = LB_TYPE_PENDING;
    MirMethodSig *methods = MS_NEW_N(&lb->m->arena, MirMethodSig, (size_t)ops->count + 1);
    uint32_t kept = 0;
    for (uint32_t i = 0; i < ops->count; i++) {
        if (ops->items[i].nvars != 0) {
            continue;
        }
        if (!li_signature(lb, &ops->items[i], &methods[kept++])) {
            lb->type_of[ty] = MIR_NONE;
            return MIR_NONE;
        }
    }
    MsBuf text = {0};
    ms_ty_show(&text, lb->c->names, tys, ty);
    const uint32_t id = mir_add_iface(lb->m, mir_name(lb->m, text.data, text.len));
    ms_buf_free(&text);
    lb->m->ifaces[id].methods = methods;
    lb->m->ifaces[id].nmethods = kept;
    lb->type_of[ty] = mir_ty_iface(lb->m, id);
    return lb->type_of[ty];
}

/* `receiver.operation(args)` where the receiver is an interface value: the operation's slot in the
 * interface, called with the receiver first. Arguments are borrowed. */
LbVal li_call(Lb *lb, const MsExpr *e) {
    const MsExpr *callee = e->u.call.callee;
    const MsTy contract = lb->facts->call_receiver[e->id];
    const MirTy iface = li_type(lb, contract);
    const MsOperations *ops = iface == MIR_NONE ? NULL : li_operations(lb, contract);
    uint32_t slot = MS_NONE;
    for (uint32_t i = 0; ops != NULL && i < ops->count && slot == MS_NONE; i++) {
        slot = ops->items[i].decl->func.name == callee->u.member.name ? li_slot(ops, i) : MS_NONE;
    }
    const uint32_t count = e->u.call.args.len;
    if (slot == MS_NONE || count != lb->m->ifaces[mir_ty_data(lb->m, iface)->id].methods[slot].nparams) {
        return LB_UNSUPPORTED(lb);
    }
    MirValue *args = MS_NEW_N(&lb->b.scratch, MirValue, (size_t)count + 2);
    const LbVal receiver = lb_expr(lb, callee->u.member.left);
    args[0] = receiver.v;
    if (receiver.owned) {
        lb_hold_temp(lb, receiver.v); // dropped where the statement ends
    }
    for (uint32_t i = 0; i < count && lb->ok; i++) {
        const LbVal value = lb_expr(lb, e->u.call.args.ptr[i].value);
        args[i + 1] = value.v;
        if (value.owned) {
            lb_hold_temp(lb, value.v);
        }
    }
    if (!lb->ok) {
        return LB_FAIL;
    }
    const MirMethodSig *sig = &lb->m->ifaces[mir_ty_data(lb->m, iface)->id].methods[slot];
    const MirImm imm = {.tag = MI_METHOD, .a = mir_ty_data(lb->m, iface)->id, .b = slot};
    return (LbVal){mir_b_emit(&lb->b, MOP_CallMethod, args, count + 1, imm, sig->ret), false};
}

/* The method row of `receiver` that satisfies operation `op`: a method of that name with the
 * operation's exact signature that neither changes nor consumes its receiver, MS_NONE when none. */
static uint32_t li_row(const Lb *lb, MsTy receiver, const MsOperation *op) {
    const MsMethods *methods = lb->facts->methods;
    for (uint32_t i = 0; i < methods->count; i++) {
        if (methods->receiver[i] == receiver && methods->decl[i] != NULL && methods->decl[i]->name == op->decl->func.name &&
            methods->nvars[i] == 0 && methods->access[i] == 0 && methods->ty[i] == op->ty) {
            return i;
        }
    }
    return MS_NONE;
}

/* The function a vtable slot holds: it takes the address of the boxed value, loads it and calls the
 * method with the rest of the arguments. */
static uint32_t li_thunk(Lb *lb, const MsOperation *op, const MirMethodSig *sig, MirTy data_ty, uint32_t method) {
    MirParam *params = MS_NEW_N(&lb->m->arena, MirParam, (size_t)sig->nparams + 2);
    params[0] = (MirParam){MIR_PTR, MM_BORROW};
    for (uint32_t i = 0; i < sig->nparams; i++) {
        params[i + 1] = (MirParam){sig->params[i], MM_BORROW};
    }
    const MsStr op_name = ms_name(lb->c->names, op->decl->func.name);
    char *text = MS_NEW_N(&lb->m->arena, char, op_name.len + 4);
    const int len = snprintf(text, op_name.len + 4, "vt.%.*s", (int)op_name.len, op_name.ptr);
    MirBuilder thunk;
    mir_b_init(&thunk, lb->m, mir_name(lb->m, text, (size_t)len), params, sig->nparams + 1, sig->ret);
    thunk.f.kind = MFK_METHOD;
    MirValue *values = MS_NEW_N(&thunk.scratch, MirValue, (size_t)sig->nparams + 2);
    mir_b_params(&thunk, values, sig->nparams + 1);
    MirValue *args = MS_NEW_N(&thunk.scratch, MirValue, (size_t)sig->nparams + 2);
    args[0] = mir_b_emit(&thunk, MOP_Load, &values[0], 1, (MirImm){.tag = MI_TY, .a = data_ty}, data_ty);
    for (uint32_t i = 0; i < sig->nparams; i++) {
        args[i + 1] = values[i + 1];
    }
    const MirValue result = mir_b_call(&thunk, lb->method_func[method], args, sig->nparams + 1);
    mir_b_ret(&thunk, sig->ret == MIR_VOID ? MIR_NONE : result);
    MirFunc f = {0};
    if (!mir_b_into_func(&thunk, &f)) {
        return MIR_NONE;
    }
    return mir_add_func(lb->m, &f);
}

/* The vtable of `data_ty` for interface `iface` (checker type `contract`), made on first use; MS_NONE
 * when a method is missing or not lowered. */
static uint32_t li_vtable(Lb *lb, MsTy concrete, MsTy contract, MirTy data_ty, MirTy iface) {
    const uint32_t iface_id = mir_ty_data(lb->m, iface)->id;
    for (uint32_t i = 0; i < lb->m->nvtables; i++) {
        if (lb->m->vtables[i].iface == iface_id && lb->m->vtables[i].data_ty == data_ty) {
            return i;
        }
    }
    const MsOperations *ops = li_operations(lb, contract);
    uint32_t *methods = MS_NEW_N(&lb->m->arena, uint32_t, (size_t)ops->count + 1);
    uint32_t kept = 0;
    for (uint32_t i = 0; i < ops->count; i++) {
        if (ops->items[i].nvars != 0) {
            continue;
        }
        const uint32_t row = li_row(lb, concrete, &ops->items[i]);
        if (row == MS_NONE || !lm_has(lb, row) || lb->method_func[row] == MIR_NONE) {
            return MS_NONE;
        }
        methods[kept] = li_thunk(lb, &ops->items[i], &lb->m->ifaces[iface_id].methods[kept], data_ty, row);
        if (methods[kept++] == MIR_NONE) {
            return MS_NONE;
        }
    }
    char text[48];
    const int len = snprintf(text, sizeof text, "impl_%u_%u", (unsigned)mir_ty_data(lb->m, data_ty)->id, (unsigned)iface_id);
    const MirVtable table = {.name = mir_name(lb->m, text, (size_t)len),
                             .iface = iface_id,
                             .methods = methods,
                             .nmethods = kept,
                             .data_ty = data_ty};
    return mir_add_vtable(lb->m, &table);
}

/* A value of a concrete type passed where an interface is expected: boxed behind the vtable of the
 * methods that satisfy it. The box owns the value: a value that needs a drop must arrive as an
 * owned temporary, one that does not is copied in. */
LbVal li_box(Lb *lb, const MsExpr *e, LbVal value) {
    const MsTy concrete = lb->facts->coerce_iface[e->id];
    const MsTy contract = lb->facts->expr_ty[e->id];
    const MirTy iface = li_type(lb, contract);
    const MirTy data_ty = lb_mir_ty(lb, concrete);
    if (iface == MIR_NONE || data_ty == MIR_NONE || (!value.owned && lb_owns(lb, data_ty))) {
        return LB_UNSUPPORTED(lb);
    }
    const uint32_t table = li_vtable(lb, concrete, contract, data_ty, iface);
    if (table == MS_NONE) {
        return LB_UNSUPPORTED(lb);
    }
    const MirImm imm = {.tag = MI_VTABLE, .a = table};
    return (LbVal){mir_b_emit(&lb->b, MOP_IfaceNew, &value.v, 1, imm, iface), true};
}

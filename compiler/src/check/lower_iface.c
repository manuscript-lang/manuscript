/* Interface values in the lowering: an `interface` without type parameters is a MIR `dyn` type with
 * one method signature per operation, and `value.operation(args)` on a value of that type is
 * `call.method`, dispatched at run time through the value's vtable. Operations with type variables
 * of their own are static dispatch only, so the interface has no slot for them; an operation that
 * takes or gives `Self`, moves or changes an argument, or has a type this pass does not lower leaves
 * the interface to the Rust lowering. Values enter an interface (`iface.new` and the vtables) where a
 * concrete value is passed as one, which the checker does not record yet. */
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
        return lb_unsupported(lb);
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

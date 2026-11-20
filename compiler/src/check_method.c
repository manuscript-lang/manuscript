/* Method calls and interface calls in function bodies: `receiver.name(args)` where the receiver is
 * a local of a type or enum the module declares (a method row of its impls), or of an interface
 * type (an operation, dispatched at run time). Handled: methods and operations without type
 * variables, positional primitive arguments, a primitive result, and a receiver that is borrowed
 * (a `var` method on a binding that is not `var`, a moving receiver and every other form leave
 * the function to the Rust checker). Records `call_method` or `call_interface`, and
 * `call_receiver`. */
#include "check_body.h"

typedef struct Target {
    MsTy sig;             /* the signature, receiver not included */
    uint32_t method;      /* the method row, or MS_NONE for an interface operation */
    bool mutating, consuming;
} Target;

/* The row of the impls that gives `receiver` a method `name`; false when none or ambiguous. */
static bool method_row(const MsBody *b, MsTy receiver, MsSym name, Target *out) {
    const MsMethods *m = &b->methods->methods;
    bool found = false;
    for (uint32_t i = 0; i < m->count; i++) {
        if (m->receiver[i] != receiver || m->decl[i] == NULL || m->decl[i]->name != name) {
            continue;
        }
        if (found || m->nvars[i] != 0) {
            return false;
        }
        *out = (Target){.sig = m->ty[i],
                        .method = i,
                        .mutating = (m->access[i] & MS_METHOD_MUTATING) != 0,
                        .consuming = (m->access[i] & MS_METHOD_CONSUMING) != 0};
        found = true;
    }
    return found;
}

/* The operation of the interface `contract` called `name`. */
static bool operation_of(const MsBody *b, MsTy contract, MsSym name, Target *out) {
    const MsTyTable *tys = &b->c->tys;
    if (ms_ty_kind(tys, contract) != MS_K_CONTRACT || tys->def[contract] == 0 || tys->nargs[contract] != 0) {
        return false;
    }
    const MsOperations *ops = ms_interface_operations(b->methods, tys->def[contract] - 1);
    for (uint32_t i = 0; ops != NULL && i < ops->count; i++) {
        const MsOperation *op = &ops->items[i];
        if (op->name == name) {
            *out = (Target){.sig = op->ty,
                            .method = MS_NONE,
                            .mutating = op->decl->mutating,
                            .consuming = op->decl->consuming};
            return op->nvars == 0;
        }
    }
    return false;
}

static bool arguments_fit(MsBody *b, const MsExpr *e, MsTy sig) {
    const MsTyTable *tys = &b->c->tys;
    if (ms_ty_kind(tys, sig) != MS_K_FUNCTION || tys->nparams[sig] != e->u.call.args.len) {
        return false;
    }
    const MsTyParam *params = ms_ty_params(tys, sig);
    for (uint32_t i = 0; i < e->u.call.args.len; i++) {
        const MsArg *arg = &e->u.call.args.ptr[i];
        const bool primitive = params[i].ty == b->int_ty || params[i].ty == b->float_ty ||
                               params[i].ty == b->bool_ty || params[i].ty == b->string_ty;
        if (arg->has_name || params[i].flags != 0 || !primitive ||
            ms_body_expr(b, arg->value, params[i].ty) == MS_TY_NONE) {
            return false;
        }
    }
    const MsTy result = tys->result[sig];
    return result == b->int_ty || result == b->float_ty || result == b->bool_ty || result == b->string_ty;
}

/* The receiver's type and whether it is a mutable place: a binding declared `var`. Any other
 * receiver expression is a temporary, which a mutating method cannot change. */
static MsTy receiver_type(MsBody *b, const MsExpr *receiver, bool *mutable_place) {
    *mutable_place = false;
    if (receiver->kind != MS_E_NAME) {
        return ms_body_expr(b, receiver, MS_TY_NONE);
    }
    const uint32_t binding = ms_body_find_binding(b, receiver->u.sym);
    if (binding == MS_NONE) {
        return MS_TY_NONE;
    }
    *mutable_place = (b->facts->bindings.flags[binding] & MS_BIND_MUTABLE) != 0;
    return ms_body_expr(b, receiver, b->facts->bindings.ty[binding]);
}

MsTy ms_body_method_call(MsBody *b, const MsExpr *e) {
    const MsExpr *callee = e->u.call.callee;
    if (b->methods == NULL || e->u.call.args.len > 16) {
        return ms_body_unsupported(b);
    }
    bool mutable_place = false;
    const MsTy receiver_ty = receiver_type(b, callee->u.member.left, &mutable_place);
    if (receiver_ty == MS_TY_NONE) {
        return ms_body_unsupported(b);
    }
    Target target;
    const bool resolved = ms_ty_kind(&b->c->tys, receiver_ty) == MS_K_CONTRACT
                              ? operation_of(b, receiver_ty, callee->u.member.name, &target)
                              : method_row(b, receiver_ty, callee->u.member.name, &target);
    if (!resolved || target.consuming || (target.mutating && !mutable_place) ||
        !arguments_fit(b, e, target.sig)) {
        return ms_body_unsupported(b);
    }
    if (target.method == MS_NONE) {
        b->facts->call_interface[e->id] = receiver_ty;
    } else {
        b->facts->call_method[e->id] = target.method;
    }
    b->facts->call_receiver[e->id] = receiver_ty;
    return b->c->tys.result[target.sig];
}

/* Method calls and interface calls in function bodies: `receiver.name(args)` where the receiver is
 * a local of a type or enum the module declares (a method row of its impls), or of an interface
 * type (an operation, dispatched at run time). Handled: methods and operations without type
 * variables, positional primitive arguments, a primitive result, and a receiver that is borrowed
 * (a `var` method on a binding that is not `var`, a moving receiver and every other form leave
 * the function to the Rust checker). Records `call_method` or `call_interface`, and
 * `call_receiver`. */
#include "check/check_body.h"

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

/* The operation `name` of the interface `iface_name` of `@std/intrinsics.ms`: what a primitive
 * receiver offers beyond the methods of impls. Only operations without type variables. */
static bool intrinsic_in(const MsBody *b, const char *iface_name, MsSym name, Target *out) {
    MsCheck *c = b->c;
    const uint32_t module = ms_map_get(&c->module_by_path, ms_intern_cstr(c->names, "@std/intrinsics.ms"));
    if (module == MS_NONE) {
        return false;
    }
    const MsSymId sym = ms_map_get(&c->mods[module].names, ms_intern_cstr(c->names, iface_name));
    const MsOperations *ops = sym == MS_NONE ? NULL : ms_interface_operations(b->methods, sym);
    for (uint32_t i = 0; ops != NULL && i < ops->count; i++) {
        const MsOperation *op = &ops->items[i];
        if (op->name == name) {
            *out = (Target){.sig = op->ty, .method = MS_NONE, .mutating = op->decl->mutating, .consuming = op->decl->consuming};
            return op->nvars == 0;
        }
    }
    return false;
}

/* An operation of a primitive receiver: its own interface, then the one every value has. */
static bool intrinsic_operation(const MsBody *b, MsTy receiver, MsSym name, Target *out) {
    const char *own = receiver == b->string_ty ? "StringOperations"
                      : receiver == b->int_ty  ? "IntOperations"
                      : receiver == b->float_ty ? "FloatOperations"
                                                : NULL;
    return (own != NULL && intrinsic_in(b, own, name, out)) || intrinsic_in(b, "ValueOperations", name, out);
}

static bool body_is_primitive(const MsBody *b, MsTy ty) {
    return ty == b->string_ty || ty == b->int_ty || ty == b->float_ty || ty == b->bool_ty;
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

/* `receiver.name(args)` on a primitive receiver of any shape (a local, a literal, another call):
 * an intrinsic operation that borrows its receiver, recorded as a call through the interface
 * `call_interface` names. */
static MsTy body_intrinsic_call(MsBody *b, const MsExpr *e, MsTy receiver_ty) {
    const MsExpr *callee = e->u.call.callee;
    Target target;
    // A String result may be a view of the receiver (`view`), which the ownership walk does not follow yet.
    if (!intrinsic_operation(b, receiver_ty, callee->u.member.name, &target) || target.consuming || target.mutating ||
        b->c->tys.result[target.sig] == b->string_ty || !arguments_fit(b, e, target.sig)) {
        return ms_body_unsupported(b);
    }
    b->facts->call_interface[e->id] = receiver_ty;
    b->facts->call_receiver[e->id] = receiver_ty;
    return b->c->tys.result[target.sig];
}

MsTy ms_body_method_call(MsBody *b, const MsExpr *e) {
    const MsExpr *callee = e->u.call.callee;
    const MsExpr *receiver = callee->u.member.left;
    if (b->methods == NULL || e->u.call.args.len > 16) {
        return ms_body_unsupported(b);
    }
    const uint32_t binding = receiver->kind == MS_E_NAME ? ms_body_find_binding(b, receiver->u.sym) : MS_NONE;
    if (receiver->kind == MS_E_NAME && binding == MS_NONE) {
        return ms_body_unsupported(b);
    }
    const MsTy local_ty = binding == MS_NONE ? MS_TY_NONE : b->facts->bindings.ty[binding];
    Target row;
    if (binding == MS_NONE || (body_is_primitive(b, local_ty) && !method_row(b, local_ty, callee->u.member.name, &row))) {
        const MsTy receiver_ty = ms_body_expr(b, receiver, MS_TY_NONE);
        return body_is_primitive(b, receiver_ty) ? body_intrinsic_call(b, e, receiver_ty) : ms_body_unsupported(b);
    }
    const MsTy receiver_ty = local_ty;
    Target target;
    const bool resolved = ms_ty_kind(&b->c->tys, receiver_ty) == MS_K_CONTRACT
                              ? operation_of(b, receiver_ty, callee->u.member.name, &target)
                              : method_row(b, receiver_ty, callee->u.member.name, &target);
    if (!resolved || target.consuming || (target.mutating && (b->facts->bindings.flags[binding] & MS_BIND_MUTABLE) == 0) ||
        ms_body_expr(b, receiver, receiver_ty) == MS_TY_NONE || !arguments_fit(b, e, target.sig)) {
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

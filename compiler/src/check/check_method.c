/* Method calls and interface calls in function bodies: `receiver.name(args)` where the receiver is
 * a local of a type or enum the module declares (a method row of its impls), or of an interface
 * type (an operation, dispatched at run time). Handled: methods and operations without type
 * variables, positional primitive arguments, a primitive result, and a receiver that is borrowed
 * (a `var` method on a binding that is not `var`, a moving receiver and every other form leave
 * the function to the Rust checker). Records `call_method` or `call_interface`, and
 * `call_receiver`. */
#include "check/check_body.h"

#include <stdio.h>
#include <string.h>

#include "ms/implements.h"
#include "ms/infer.h"

typedef struct Target {
    MsTy sig;             /* the signature, receiver not included */
    const MsFunc *func;   /* its declaration: parameter defaults; NULL when none is at hand */
    uint32_t method;      /* the method row, or MS_NONE for an interface operation */
    bool mutating, consuming;
} Target;

/* Binds the row's variables by matching its receiver type against the actual one. A built-in
 * type (`List[T]`) is declared by its standard module as a type and written elsewhere as the
 * native built-in: they are one type when the name and the arguments agree. */
static bool row_receiver_fits(const MsBody *b, MsInfer *in, MsTy pattern, MsTy actual) {
    const MsTyTable *tys = &b->c->tys;
    // The standard type as the program writes it (`List[Int]`, `Int?`) is the one its module declares
    // (`List[T]`, `Optional[T]`) when both have the same standard identity (`@std/Optional`).
    const MsBuiltin declared = ms_body_standard_identity(b, pattern);
    const bool same_native = declared != MS_B_NONE && declared == ms_body_standard_identity(b, actual) &&
                             tys->id[pattern] != tys->id[actual] && tys->nargs[pattern] == tys->nargs[actual];
    if (!same_native) {
        return ms_infer_match(in, pattern, actual) == MS_MATCH_OK;
    }
    for (uint32_t i = 0; i < tys->nargs[pattern]; i++) {
        if (ms_infer_match(in, ms_ty_args(tys, pattern)[i], ms_ty_args(tys, actual)[i]) != MS_MATCH_OK) {
            return false;
        }
    }
    return true;
}

/* Whether each variable the match bound meets the interfaces that bound it (`T: Numeric`); a bound
 * the tables cannot answer counts as unmet, which leaves the call to the Rust checker. */
static bool row_bounds_met(const MsBody *b, MsInfer *in) {
    for (uint32_t i = 0; i < in->nvars; i++) {
        const MsVarInfo *info = ms_var_info(b->c, in->vars[i]);
        for (uint32_t k = 0; k < info->nbounds; k++) {
            const MsTy contract = ms_infer_apply(in, info->bounds[k]);
            if (in->bound[i] == MS_TY_NONE || ms_implements(b->c, b->methods, in->bound[i], contract) != MS_FIT_YES) {
                return false;
            }
        }
    }
    return true;
}

/* The signature of row `i` for `receiver`: the row's own when it has no type variables, else with
 * the variables its receiver type binds (`WriteStream[T]` against `WriteStream[String]`) applied.
 * MS_TY_NONE when the row does not fit or leaves a variable open. */
static MsTy row_signature(const MsBody *b, uint32_t i, MsTy receiver) {
    const MsMethods *m = &b->methods->methods;
    if (m->nvars[i] == 0) {
        return m->receiver[i] == receiver ? m->ty[i] : MS_TY_NONE;
    }
    MsInfer in;
    ms_infer_init(&in, b->c, &b->c->arena, m->vars + m->vars_at[i], m->nvars[i]);
    uint32_t first = 0;
    if (!row_receiver_fits(b, &in, m->receiver[i], receiver) || ms_infer_defaults(&in, &first) != 0 ||
        !row_bounds_met(b, &in)) {
        return MS_TY_NONE;
    }
    return ms_infer_apply(&in, m->ty[i]);
}

/* The row of the impls that gives `receiver` a method `name`; false when none or ambiguous. */
static bool method_row(const MsBody *b, MsTy receiver, MsSym name, Target *out) {
    const MsMethods *m = &b->methods->methods;
    bool found = false;
    for (uint32_t i = 0; i < m->count; i++) {
        if (m->decl[i] == NULL || m->decl[i]->name != name) {
            continue;
        }
        const MsTy sig = row_signature(b, i, receiver);
        if (sig == MS_TY_NONE) {
            continue;
        }
        if (found) {
            return false;
        }
        *out = (Target){.sig = sig,
                        .func = m->decl[i],
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
                            .func = &op->decl->func,
                            .method = MS_NONE,
                            .mutating = op->decl->mutating,
                            .consuming = op->decl->consuming};
            return op->nvars == 0;
        }
    }
    return false;
}

/* The operation `name` of the interface `iface_name` of `@std/intrinsics.ms`: what a primitive
 * receiver offers beyond the methods of impls. An interface over the receiver type (`CloneOperations[T]`)
 * is applied to `receiver`; operations with type variables of their own are left out. */
static bool intrinsic_in(const MsBody *b, const char *iface_name, MsTy receiver, MsSym name, Target *out) {
    MsCheck *c = b->c;
    const uint32_t module = ms_map_get(&c->module_by_path, ms_intern_cstr(c->names, "@std/intrinsics.ms"));
    if (module == MS_NONE) {
        return false;
    }
    const MsSymId sym = ms_map_get(&c->mods[module].names, ms_intern_cstr(c->names, iface_name));
    const MsOperations *ops = sym == MS_NONE ? NULL : ms_interface_operations(b->methods, sym);
    for (uint32_t i = 0; ops != NULL && i < ops->count; i++) {
        const MsOperation *op = &ops->items[i];
        if (op->name != name || op->nvars != 0) {
            continue;
        }
        MsTy sig = op->ty;
        const MsDef *definition = ms_def(c, sym);
        if (definition != NULL && definition->nvars != 0) {
            MsInfer in;
            ms_infer_init(&in, c, &c->arena, definition->vars, definition->nvars);
            if (definition->nvars != 1 || !ms_infer_give(&in, &receiver, 1)) {
                return false;
            }
            sig = ms_infer_apply(&in, sig);
        }
        *out = (Target){.sig = sig, .func = &op->decl->func, .method = MS_NONE, .mutating = op->decl->mutating, .consuming = op->decl->consuming};
        return true;
    }
    return false;
}

/* An operation of a primitive receiver: its own interface, then the one every value has. */
static bool intrinsic_operation(const MsBody *b, MsTy receiver, MsSym name, Target *out) {
    const char *own = NULL;
    if (receiver == b->string_ty) {
        own = "StringOperations";
    } else if (receiver == b->int_ty) {
        own = "IntOperations";
    } else if (receiver == b->float_ty) {
        own = "FloatOperations";
    }
    return (own != NULL && intrinsic_in(b, own, receiver, name, out)) ||
           intrinsic_in(b, "ValueOperations", receiver, name, out) || intrinsic_in(b, "CloneOperations", receiver, name, out);
}

/* The natives whose result points into their receiver (`view`, `split`, `chars`, ...): the
 * ownership walk does not follow those borrows yet, so a call of one leaves the function to the Rust
 * checker. Mirrors `native_borrow` of the Rust checker, the one place a method name decides ownership. */
static bool native_result_borrows(const MsBody *b, MsTy receiver, MsSym name, uint32_t nargs) {
    static const struct {
        const char *name;
        uint32_t min_args, max_args;
    } derived[] = {{"view", 2, 2}, {"view_bytes", 0, 0}, {"split", 1, 2}, {"lines", 0, 0}, {"chars", 0, 0}};
    const MsStr text = ms_name(b->c->names, name);
    for (size_t i = 0; i < sizeof derived / sizeof *derived; i++) {
        if (strlen(derived[i].name) == text.len && memcmp(derived[i].name, text.ptr, text.len) == 0 &&
            nargs >= derived[i].min_args && nargs <= derived[i].max_args) {
            return receiver == b->string_ty;
        }
    }
    return false;
}

static bool body_is_primitive(const MsBody *b, MsTy ty) {
    return ty == b->string_ty || ty == b->int_ty || ty == b->float_ty || ty == b->bool_ty;
}

/* The arguments of a method call against its signature, paired with parameters by position or
 * label; parameters left out must have a default in the declaration. A label or a count that does
 * not fit is a diagnostic the Rust checker reports. `e`'s `call_reordered` fact is set when some
 * argument is not at its parameter's index. */
static bool arguments_fit(MsBody *b, const MsExpr *e, const Target *target) {
    const MsTyTable *tys = &b->c->tys;
    const MsTy sig = target->sig;
    const uint32_t given = e->u.call.args.len;
    const uint32_t nparams = ms_ty_kind(tys, sig) == MS_K_FUNCTION ? tys->nparams[sig] : 0;
    if (ms_ty_kind(tys, sig) != MS_K_FUNCTION || given > nparams) {
        return false;
    }
    const MsTyParam *params = ms_ty_params(tys, sig);
    MsSym *names = MS_NEW_N(&b->c->arena, MsSym, nparams + 1);
    bool *positional = MS_NEW_N(&b->c->arena, bool, nparams + 1);
    bool *covered = MS_NEW_N(&b->c->arena, bool, nparams + 1);
    uint32_t *slot = MS_NEW_N(&b->c->arena, uint32_t, given + 1);
    for (uint32_t i = 0; i < nparams; i++) {
        names[i] = params[i].name;
        positional[i] = (params[i].flags & MS_PARAM_POSITIONAL) != 0;
    }
    const MsFunc *func = target->func;
    const bool declared = func != NULL && func->params.len == nparams;
    if (!ms_body_bind_arguments(e, names, positional, nparams, slot, covered)) {
        return false;
    }
    for (uint32_t i = 0; i < nparams; i++) {
        if (!covered[i] && (!declared || func->params.ptr[i]->def == NULL)) {
            return false;
        }
    }
    for (uint32_t i = 0; i < given; i++) {
        const MsTyParam *param = &params[slot[i]];
        MsTy payload = MS_TY_NONE;
        const bool optional = ms_body_optional_payload(b, param->ty, &payload);
        if ((param->flags & ~(MS_PARAM_MOVE | MS_PARAM_POSITIONAL)) != 0 || (!ms_body_is_admitted(b, param->ty) && !optional) ||
            ms_body_expr(b, e->u.call.args.ptr[i].value, param->ty) == MS_TY_NONE) {
            return false;
        }
    }
    b->facts->call_reordered[e->id] = ms_body_reordered(e, slot);
    const MsTy result = tys->result[sig];
    return result == b->int_ty || result == b->float_ty || result == b->bool_ty || result == b->string_ty ||
           result == b->void_ty || ms_body_is_bindable(b, result);
}

/* `receiver.name(args)` on a primitive receiver of any shape (a local, a literal, another call):
 * an intrinsic operation that borrows its receiver, recorded as a call through the interface
 * `call_interface` names. */
static MsTy body_intrinsic_call(MsBody *b, const MsExpr *e, MsTy receiver_ty) {
    const MsExpr *callee = e->u.call.callee;
    Target target;
    if (!intrinsic_operation(b, receiver_ty, callee->u.member.name, &target) || target.consuming || target.mutating ||
        native_result_borrows(b, receiver_ty, callee->u.member.name, e->u.call.args.len) ||
        !arguments_fit(b, e, &target)) {
        return ms_body_unsupported(b);
    }
    b->facts->call_interface[e->id] = receiver_ty;
    b->facts->call_receiver[e->id] = receiver_ty;
    return b->c->tys.result[target.sig];
}

/* The operation `name` of the interfaces that bound the type variable `var`: its own, found in
 * exactly one bound. `contract` is the bound it comes from. */
static bool bound_operation(const MsBody *b, MsTy var, MsSym name, Target *out, MsTy *contract) {
    const MsVarInfo *info = ms_var_info(b->c, var);
    bool found = false;
    for (uint32_t i = 0; info != NULL && i < info->nbounds; i++) {
        Target candidate;
        if (!operation_of(b, info->bounds[i], name, &candidate)) {
            continue;
        }
        if (found) {
            return false; /* two bounds offer it */
        }
        *out = candidate;
        *contract = info->bounds[i];
        found = true;
    }
    return found;
}

/* A call on a receiver of the invalid type (its own error is reported): the arguments are still
 * checked, without an expected type, and the call is invalid, which silences what uses it. */
static MsTy invalid_receiver_call(MsBody *b, const MsExpr *e, uint32_t binding) {
    if (binding != MS_NONE && ms_body_expr(b, e->u.call.callee->u.member.left, b->invalid_ty) == MS_TY_NONE) {
        return ms_body_unsupported(b);
    }
    for (uint32_t i = 0; i < e->u.call.args.len; i++) {
        if (ms_body_expr(b, e->u.call.args.ptr[i].value, MS_TY_NONE) == MS_TY_NONE) {
            return ms_body_unsupported(b);
        }
    }
    return b->invalid_ty;
}

/* A method of `receiver_ty` (a type with impls) or an operation of an interface, called on the
 * receiver expression; `binding` is the local it names, or MS_NONE for a temporary, which a
 * mutating method may change. */
static MsTy body_resolved_call(MsBody *b, const MsExpr *e, MsTy receiver_ty, uint32_t binding) {
    const MsExpr *callee = e->u.call.callee;
    if (receiver_ty == b->invalid_ty) {
        return invalid_receiver_call(b, e, binding);
    }
    Target target;
    MsTy dispatch = receiver_ty; /* the interface an operation is called through */
    bool resolved;
    if (ms_ty_kind(&b->c->tys, receiver_ty) == MS_K_VARIABLE) {
        resolved = bound_operation(b, receiver_ty, callee->u.member.name, &target, &dispatch);
    } else if (ms_ty_kind(&b->c->tys, receiver_ty) == MS_K_CONTRACT) {
        resolved = operation_of(b, receiver_ty, callee->u.member.name, &target);
    } else {
        resolved = method_row(b, receiver_ty, callee->u.member.name, &target);
    }
    const bool immutable = binding != MS_NONE && (b->facts->bindings.flags[binding] & MS_BIND_MUTABLE) == 0;
    if (!resolved || target.consuming || (target.mutating && immutable) ||
        (binding != MS_NONE && ms_body_expr(b, callee->u.member.left, receiver_ty) == MS_TY_NONE) ||
        !arguments_fit(b, e, &target)) {
        return ms_body_unsupported(b);
    }
    if (target.method == MS_NONE) {
        b->facts->call_interface[e->id] = dispatch;
    } else {
        b->facts->call_method[e->id] = target.method;
    }
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
        if (body_is_primitive(b, receiver_ty)) {
            return body_intrinsic_call(b, e, receiver_ty);
        }
        return receiver_ty != MS_TY_NONE && (ms_body_is_handle(b, receiver_ty) || ms_body_is_bindable(b, receiver_ty))
                   ? body_resolved_call(b, e, receiver_ty, MS_NONE)
                   : ms_body_unsupported(b);
    }
    return body_resolved_call(b, e, local_ty, binding);
}

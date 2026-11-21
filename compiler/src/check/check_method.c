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

#include "ms/doc.h"
#include "ms/implements.h"
#include "ms/infer.h"
#include "ms/parse.h"

typedef struct Target {
    MsTy sig;             /* the signature, receiver not included */
    const MsFunc *func;   /* its declaration: parameter defaults; NULL when none is at hand */
    uint32_t method;      /* the method row, or MS_NONE for an interface operation */
    bool mutating, consuming;
    MsTy self;            /* the receiver type an operation's `Self` stands for, or MS_TY_NONE */
    bool borrows;         /* the result points into the receiver (`// ms: borrows` above the declaration) */
    bool open;            /* variables of the method itself are still unbound: the arguments bind them */
    MsInfer in;           /* the bindings of an open row */
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
 * A variable the receiver leaves open belongs to the method itself (`map[U]`): the row is then
 * `open` and `*in` keeps the bindings for the arguments to extend. MS_TY_NONE when the row does not fit. */
static MsTy row_signature(const MsBody *b, uint32_t i, MsTy receiver, MsInfer *in, bool *open) {
    const MsMethods *m = &b->methods->methods;
    *open = false;
    if (m->nvars[i] == 0) {
        return m->receiver[i] == receiver ? m->ty[i] : MS_TY_NONE;
    }
    ms_infer_init(in, b->c, &b->c->arena, m->vars + m->vars_at[i], m->nvars[i]);
    if (!row_receiver_fits(b, in, m->receiver[i], receiver)) {
        return MS_TY_NONE;
    }
    MsTy *receiver_bound = MS_NEW_N(&b->c->arena, MsTy, m->nvars[i]);
    memcpy(receiver_bound, in->bound, m->nvars[i] * sizeof *receiver_bound);
    // A variable the receiver leaves unbound is the method's own: the arguments may bind it (`ok_or(cause)`
    // binds `E` to the cause's type), and only what they leave unbound takes its default.
    for (uint32_t v = 0; v < m->nvars[i]; v++) {
        if (receiver_bound[v] == MS_TY_NONE) {
            *open = true;
            return ms_infer_apply(in, m->ty[i]);
        }
    }
    return row_bounds_met(b, in) ? ms_infer_apply(in, m->ty[i]) : MS_TY_NONE;
}

/* Whether a call of `given` arguments fits the signature `sig` of `func`: every parameter without a
 * default is supplied. Methods of one name may differ in their parameters (`sorted()` and
 * `sorted(compare)`); the call's argument count picks among them, as the Rust checker's does. */
static bool row_arity_fits(const MsBody *b, MsTy sig, const MsFunc *func, uint32_t given) {
    const MsTyTable *tys = &b->c->tys;
    if (given == UINT32_MAX) {
        return true;
    }
    if (ms_ty_kind(tys, sig) != MS_K_FUNCTION || given > tys->nparams[sig]) {
        return false;
    }
    uint32_t required = tys->nparams[sig];
    if (func != NULL && func->params.len == required) {
        required = 0;
        for (uint32_t i = 0; i < func->params.len; i++) {
            required += func->params.ptr[i]->def == NULL ? 1u : 0u;
        }
    }
    return given >= required;
}

/* The row of the impls that gives `receiver` a method `name`, among those a call of `given`
 * arguments fits (UINT32_MAX: any); false when none or ambiguous. */
static bool method_row(const MsBody *b, MsTy receiver, MsSym name, uint32_t given, Target *out) {
    const MsMethods *m = &b->methods->methods;
    bool found = false;
    for (uint32_t i = 0; i < m->count; i++) {
        if (m->decl[i] == NULL || m->decl[i]->name != name) {
            continue;
        }
        MsInfer in = {0};
        bool open = false;
        const MsTy sig = row_signature(b, i, receiver, &in, &open);
        if (sig == MS_TY_NONE || !row_arity_fits(b, sig, m->decl[i], given)) {
            continue;
        }
        if (found) {
            return false;
        }
        *out = (Target){.sig = sig,
                        .open = open,
                        .in = in,
                        .func = m->decl[i],
                        .method = i,
                        .mutating = (m->access[i] & MS_METHOD_MUTATING) != 0,
                        .consuming = (m->access[i] & MS_METHOD_CONSUMING) != 0};
        found = true;
    }
    return found;
}

/* The operation of the interface `contract` called `name`. An interface with type arguments
 * (`Sink[String]`) gives the operation's signature with them in place of the interface's variables. */
static bool operation_of(const MsBody *b, MsTy contract, MsSym name, Target *out) {
    MsCheck *c = b->c;
    const MsTyTable *tys = &c->tys;
    if (ms_ty_kind(tys, contract) != MS_K_CONTRACT || tys->def[contract] == 0) {
        return false;
    }
    const MsSymId sym = tys->def[contract] - 1;
    const MsOperations *ops = ms_interface_operations(b->methods, sym);
    for (uint32_t i = 0; ops != NULL && i < ops->count; i++) {
        const MsOperation *op = &ops->items[i];
        if (op->name != name || op->nvars != 0) {
            continue;
        }
        MsTy sig = op->ty;
        if (tys->nargs[contract] != 0) {
            const MsDef *definition = ms_def(c, sym);
            if (definition == NULL || definition->nvars != tys->nargs[contract]) {
                return false;
            }
            const MsTySubst subst = {.vars = definition->vars, .args = ms_ty_args(tys, contract), .count = definition->nvars};
            sig = ms_ty_subst(&c->tys, &c->arena, sig, &subst);
        }
        *out = (Target){.sig = sig,
                        .func = &op->decl->func,
                        .method = MS_NONE,
                        .mutating = op->decl->mutating,
                        .consuming = op->decl->consuming};
        return true;
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
        *out = (Target){.sig = sig,
                        .func = &op->decl->func,
                        .method = MS_NONE,
                        .mutating = op->decl->mutating,
                        .consuming = op->decl->consuming,
                        .borrows = ms_doc_has_marker(c->mods[module].text, op->decl->pos.offset, "borrows")};
        return true;
    }
    return false;
}

/* Whether `name` is one of the `members`: the primitives a shared interface of intrinsics.ms covers. */
static bool primitive_in(MsStr name, const char *const *members) {
    for (; *members != NULL; members++) {
        if (strlen(*members) == name.len && memcmp(*members, name.ptr, name.len) == 0) {
            return true;
        }
    }
    return false;
}

/* An operation of a primitive receiver: its own `<Type>Operations` interface, the generic ones its
 * family shares (applied to itself), then the ones every value has. Mirrors `SHARED_OPERATIONS`. */
static bool intrinsic_operation(const MsBody *b, MsTy receiver, MsSym name, Target *out) {
    static const char *const integers[] = {"Int", "Int8", "Int16", "Int32", "UInt8", "UInt16", "UInt32", "UInt64", NULL};
    static const char *const signed_integers[] = {"Int", "Int8", "Int16", "Int32", NULL};
    if (ms_ty_kind(&b->c->tys, receiver) == MS_K_PRIMITIVE) {
        const MsStr type = ms_name(b->c->names, b->c->tys.name[receiver]);
        const char *own = ms_arena_fmt(&b->c->arena, "%.*sOperations", (int)type.len, type.ptr).ptr;
        if (intrinsic_in(b, own, receiver, name, out) ||
            (primitive_in(type, integers) && intrinsic_in(b, "IntegerOperations", receiver, name, out)) ||
            (primitive_in(type, signed_integers) && intrinsic_in(b, "SignedIntegerOperations", receiver, name, out))) {
            return true;
        }
    }
    return intrinsic_in(b, "ValueOperations", receiver, name, out) || intrinsic_in(b, "CloneOperations", receiver, name, out);
}

/* `to_string` and `clone`, which exist without an impl: every non-generic value shows as text, and
 * data values (types, alternatives, lists, maps, sets, bytes) clone deeply (`native_method` of the
 * Rust checker). */
static bool value_operation(const MsBody *b, MsTy receiver, MsSym name, Target *out) {
    const MsTyTable *tys = &b->c->tys;
    const MsKind kind = ms_ty_kind(tys, receiver);
    if (kind == MS_K_VARIABLE) {
        return intrinsic_in(b, "ValueOperations", receiver, name, out); // every value shows as text
    }
    if (kind != MS_K_TYPE && kind != MS_K_ALTERNATIVE && kind != MS_K_NATIVE) {
        return false;
    }
    if (intrinsic_in(b, "ValueOperations", receiver, name, out)) {
        return true;
    }
    return ms_implements_property(b->c, b->methods, receiver, MS_PROP_CLONABLE) == MS_FIT_YES && intrinsic_in(b, "CloneOperations", receiver, name, out);
}

/* The function-typed field `name` of a record `receiver`, with the receiver's type arguments in place of the
 * record's variables: `value.operation(x)` calls the function the field holds. */
static MsTy function_field(const MsBody *b, MsTy receiver, MsSym name) {
    MsCheck *c = b->c;
    const MsTyTable *tys = &c->tys;
    if (ms_ty_kind(tys, receiver) != MS_K_TYPE || tys->def[receiver] == 0) {
        return MS_TY_NONE;
    }
    const MsDef *def = ms_def(c, tys->def[receiver] - 1);
    if (def->nvars != tys->nargs[receiver]) {
        return MS_TY_NONE;
    }
    for (uint32_t i = 0; i < def->nfields; i++) {
        if (def->fields[i].name != name) {
            continue;
        }
        MsTy field = def->fields[i].ty;
        if (def->nvars != 0) {
            const MsTySubst subst = {.vars = def->vars, .args = ms_ty_args(tys, receiver), .count = def->nvars};
            field = ms_ty_subst(&c->tys, &c->arena, field, &subst);
        }
        return ms_body_is_function_value(b, field) ? field : MS_TY_NONE;
    }
    return MS_TY_NONE;
}

static bool body_is_primitive(const MsBody *b, MsTy ty) {
    // Every primitive with operations: `Void` and `Never` have none, the invalid type is an earlier error.
    return ty != MS_TY_NONE && ty != b->void_ty && ty != b->never_ty && ms_ty_kind(&b->c->tys, ty) == MS_K_PRIMITIVE;
}

/* A parameter or result type of `target`: `Self` of an interface operation is the receiver's type
 * (`Self` is limited to whole parameter and result types). */
static MsTy target_type(const MsBody *b, const Target *target, MsTy ty) {
    return target->self != MS_TY_NONE && ms_ty_is(&b->c->tys, ty, MS_BI_SELF) ? target->self : ty;
}

/* The arguments of a method call against its signature, paired with parameters by position or
 * label; parameters left out must have a default in the declaration. A label or a count that does
 * not fit is a diagnostic the Rust checker reports. `e`'s `call_reordered` fact is set when some
 * argument is not at its parameter's index. An open row is closed by the arguments: its bindings
 * must settle every variable and meet every bound, and `target->sig` becomes the signature at them. */
static bool arguments_fit(MsBody *b, const MsExpr *e, Target *target) {
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
        if ((param->flags & ~(MS_PARAM_MOVE | MS_PARAM_POSITIONAL)) != 0) {
            return false;
        }
        const MsExpr *value = e->u.call.args.ptr[i].value;
        if (target->open) {
            if (!ms_body_open_argument(b, value, param, &target->in)) {
                return false;
            }
            continue;
        }
        MsTy payload = MS_TY_NONE;
        const MsTy want = target_type(b, target, param->ty);
        const bool optional = ms_body_optional_payload(b, want, &payload);
        if ((!ms_body_is_admitted(b, want) && !ms_body_is_callback_type(b, want) && !optional) || ms_body_expr(b, value, want) == MS_TY_NONE) {
            return false;
        }
    }
    b->facts->call_reordered[e->id] = ms_body_reordered(e, slot);
    if (target->open) {
        uint32_t first = 0;
        if (ms_infer_defaults(&target->in, &first) != 0 || !row_bounds_met(b, &target->in)) {
            return false;
        }
        target->sig = ms_infer_apply(&target->in, sig);
        ms_body_record_function_arguments(b, e, target->sig, slot);
    }
    const MsTy result = target_type(b, target, tys->result[target->sig]);
    return result == b->int_ty || result == b->float_ty || result == b->bool_ty || result == b->string_ty ||
           result == b->void_ty || ms_body_is_bindable(b, result);
}

/* `receiver.name(args)` on a primitive receiver of any shape (a local, a literal, another call):
 * an intrinsic operation that borrows its receiver, recorded as a call through the interface
 * `call_interface` names. */
/* A borrowing call whose result the context uses in place, on a receiver that is a local: the ownership walk
 * pins that local while the result is in use. A result that is kept or passed on is left to the Rust checker. */
static bool body_borrow_in_place(const MsBody *b, const MsExpr *e) {
    return b->borrow_ok == e && e->u.call.callee->u.member.left->kind == MS_E_NAME;
}

static MsTy body_intrinsic_call(MsBody *b, const MsExpr *e, MsTy receiver_ty) {
    const MsExpr *callee = e->u.call.callee;
    Target target = {0};
    if (!intrinsic_operation(b, receiver_ty, callee->u.member.name, &target) || target.consuming || target.mutating ||
        (target.borrows && !body_borrow_in_place(b, e)) ||
        !arguments_fit(b, e, &target)) {
        return ms_body_unsupported(b);
    }
    b->facts->call_interface[e->id] = receiver_ty;
    b->facts->call_receiver[e->id] = receiver_ty;
    b->facts->call_borrows[e->id] = target.borrows;
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
    Target target = {0};
    MsSym name = callee->u.member.name;
    if (ms_is_index_store(b->c->names, e)) {
        // `m[key] = value` is `m.add(key, value)` and `xs[i] = value` is `xs.set(i, value)`.
        name = ms_intern_cstr(b->c->names, ms_ty_is(&b->c->tys, receiver_ty, MS_BI_MAP) ? "add" : "set");
    }
    MsTy dispatch = receiver_ty; /* the interface an operation is called through */
    bool resolved;
    if (ms_ty_kind(&b->c->tys, receiver_ty) == MS_K_VARIABLE) {
        resolved = bound_operation(b, receiver_ty, name, &target, &dispatch) ||
                   value_operation(b, receiver_ty, name, &target);
    } else if (ms_ty_kind(&b->c->tys, receiver_ty) == MS_K_CONTRACT) {
        resolved = operation_of(b, receiver_ty, name, &target);
    } else {
        resolved = method_row(b, receiver_ty, name, e->u.call.args.len, &target) ||
                   value_operation(b, receiver_ty, name, &target);
    }
    if (resolved && target.method == MS_NONE) {
        target.self = receiver_ty; // an interface operation's `Self` is the receiver's type
    }
    const bool immutable = binding != MS_NONE && (b->facts->bindings.flags[binding] & MS_BIND_MUTABLE) == 0;
    if (!resolved) {
        const MsTy field = function_field(b, receiver_ty, name);
        return field == MS_TY_NONE ? ms_body_unsupported(b) : ms_body_call_function(b, e, field);
    }
    if ((target.consuming && target.method == MS_NONE) || (target.mutating && immutable)) {
        return ms_body_unsupported(b);
    }
    if (binding != MS_NONE && ms_body_expr(b, callee->u.member.left, receiver_ty) == MS_TY_NONE) {
        return ms_body_unsupported(b);
    }
    if (!arguments_fit(b, e, &target)) {
        return ms_body_unsupported(b);
    }
    if (target.method == MS_NONE) {
        b->facts->call_interface[e->id] = dispatch;
    } else {
        b->facts->call_method[e->id] = target.method;
    }
    b->facts->call_receiver[e->id] = receiver_ty;
    return target_type(b, &target, b->c->tys.result[target.sig]);
}

void ms_body_text_method(MsBody *b, const MsExpr *part, MsTy ty) {
    Target target = {0};
    if (b->methods == NULL || ms_ty_kind(&b->c->tys, ty) == MS_K_VARIABLE ||
        !method_row(b, ty, ms_intern_cstr(b->c->names, "to_string"), 0, &target)) {
        return;
    }
    const MsTyTable *tys = &b->c->tys;
    if (target.mutating || target.consuming || tys->nparams[target.sig] != 0 || tys->result[target.sig] != b->string_ty) {
        return; // an ordinary method of that name: the type prints structurally
    }
    b->facts->text_method[part->id] = target.method;
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
    if (binding == MS_NONE || (body_is_primitive(b, local_ty) && !method_row(b, local_ty, callee->u.member.name, e->u.call.args.len, &row))) {
        if (receiver->kind == MS_E_CALL) {
            b->borrow_ok = receiver; // `s.view(a, b).clone()`: a borrowing receiver is used in place
        }
        const MsTy receiver_ty = ms_body_expr(b, receiver, MS_TY_NONE);
        if (b->facts->call_borrows[receiver->id] && !body_is_primitive(b, receiver_ty)) {
            return ms_body_unsupported(b); // a borrowed list or map is not followed through a method
        }
        if (body_is_primitive(b, receiver_ty) && !method_row(b, receiver_ty, callee->u.member.name, e->u.call.args.len, &row)) {
            return body_intrinsic_call(b, e, receiver_ty);
        }
        return receiver_ty != MS_TY_NONE && (ms_body_is_handle(b, receiver_ty) || ms_body_is_bindable(b, receiver_ty))
                   ? body_resolved_call(b, e, receiver_ty, MS_NONE)
                   : ms_body_unsupported(b);
    }
    return body_resolved_call(b, e, local_ty, binding);
}

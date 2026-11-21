/* Calls of generic functions of the module: `identity(3)`, `larger(a, b)`. The type arguments are
 * inferred from the argument types (infer.h), every bound must hold (implements.h), and the call
 * has the result type with them applied. Handled: positional arguments of a type the body pass admits, each
 * variable bound to one, bounds that are certainly met. Explicit type arguments, defaults
 * that are needed, bounds whose answer is unknown and every other form leave the function to the
 * Rust checker. Records `call_callee` and the type arguments (`call_type_args_*`). */
#include <stdlib.h>
#include <string.h>

#include "check_body.h"

#include "ms/implements.h"
#include "ms/infer.h"
#include "ms/ty_algebra.h"
#include "ms/walk.h"

/* Whether `ty` mentions the type variable `var` (variables are the same by their id, as in infer.c). */
static bool ty_mentions(const MsTyTable *tys, MsTy ty, MsTy var) {
    if (ty == var || (ms_ty_kind(tys, ty) == MS_K_VARIABLE && tys->id[ty] == tys->id[var])) {
        return true;
    }
    for (uint32_t i = 0; i < tys->nargs[ty]; i++) {
        if (ty_mentions(tys, ms_ty_args(tys, ty)[i], var)) {
            return true;
        }
    }
    if (ms_ty_kind(tys, ty) != MS_K_FUNCTION) {
        return false;
    }
    for (uint32_t i = 0; i < tys->nparams[ty]; i++) {
        if (ty_mentions(tys, ms_ty_params(tys, ty)[i].ty, var)) {
            return true;
        }
    }
    return ty_mentions(tys, tys->result[ty], var);
}

/* Whether `ty` mentions a variable of the open row that no argument has bound yet. */
bool ms_body_mentions_unbound(const MsBody *b, const MsInfer *in, MsTy ty) {
    for (uint32_t k = 0; k < in->nvars; k++) {
        if (in->bound[k] == MS_TY_NONE && ty_mentions(&b->c->tys, ty, in->vars[k])) {
            return true;
        }
    }
    return false;
}

/* One argument of an open row: against its parameter when that is settled, else its type binds the
 * parameter's variables. A function literal whose parameters are settled gets them and takes its
 * result from its body, which binds the variables of the parameter's result. */
bool ms_body_open_argument(MsBody *b, const MsExpr *value, const MsTyParam *param, MsInfer *in) {
    const MsTyTable *tys = &b->c->tys;
    const MsTy want = ms_infer_apply(in, param->ty);
    if (!ms_body_mentions_unbound(b, in, want)) {
        return (ms_body_is_admitted(b, want) || ms_body_is_callback_type(b, want)) && ms_body_expr(b, value, want) != MS_TY_NONE;
    }
    MsTy actual = MS_TY_NONE;
    if (value->kind == MS_E_LAMBDA) {
        bool settled = ms_ty_kind(tys, want) == MS_K_FUNCTION;
        for (uint32_t i = 0; settled && i < tys->nparams[want]; i++) {
            settled = !ms_body_mentions_unbound(b, in, ms_ty_params(tys, want)[i].ty);
        }
        actual = settled ? ms_body_lambda_inferred(b, value, want) : MS_TY_NONE;
        if (actual != MS_TY_NONE) {
            (void)ms_body_record(b, value->id, actual);
        }
    } else {
        actual = ms_body_expr(b, value, MS_TY_NONE);
    }
    if (actual == MS_TY_NONE || !ms_body_is_admitted(b, actual)) {
        return false;
    }
    if (ms_infer_match(in, param->ty, actual) == MS_MATCH_OK) {
        return true;
    }
    // A plain value where an Optional of a variable is expected (`ok_or(cause)` with `cause: E?`): the
    // value is the payload, and the call wraps it in `some`.
    if (!ms_ty_is(tys, param->ty, MS_BI_OPTIONAL) || tys->nargs[param->ty] != 1 || ms_ty_is(tys, actual, MS_BI_OPTIONAL) ||
        ms_infer_match(in, ms_ty_args(tys, param->ty)[0], actual) != MS_MATCH_OK) {
        return false;
    }
    b->facts->some_wrap[value->id] = true; // the expression keeps its own type, as the Rust checker records it
    return true;
}

/* A function passed for a parameter has the parameter's type (`fn(move T) U`), as the Rust checker
 * records it, whatever ownership mode the function's own type spells. `slot[i]` is the parameter
 * of argument i. */
void ms_body_record_function_arguments(MsBody *b, const MsExpr *call, MsTy sig, const uint32_t *slot) {
    const MsTyTable *tys = &b->c->tys;
    const MsTyParam *params = ms_ty_params(tys, sig);
    for (uint32_t i = 0; i < call->u.call.args.len; i++) {
        const MsTy want = params[slot[i]].ty;
        if (ms_ty_kind(tys, want) == MS_K_FUNCTION) {
            (void)ms_body_record(b, call->u.call.args.ptr[i].value->id, want);
        }
    }
}

/* Matches each argument against its parameter, binding the variables. Arguments pair with
 * parameters by label or position; a parameter left out must have a default in `func`, the callee's
 * declaration. */
static bool generic_arguments(MsBody *b, const MsExpr *e, MsTy sig, const MsFunc *func, MsInfer *in, uint32_t *slot) {
    const MsTyTable *tys = &b->c->tys;
    const uint32_t given = e->u.call.args.len;
    if (ms_ty_kind(tys, sig) != MS_K_FUNCTION) {
        return false;
    }
    const uint32_t nparams = tys->nparams[sig];
    if (given > nparams || nparams > 16 || func->params.len != nparams) {
        return false;
    }
    const MsTyParam *params = ms_ty_params(tys, sig);
    MsSym names[16] = {0};
    bool positional[16] = {false}, covered[16] = {false};
    for (uint32_t i = 0; i < nparams; i++) {
        names[i] = params[i].name;
        positional[i] = (params[i].flags & MS_PARAM_POSITIONAL) != 0;
    }
    if (!ms_body_bind_arguments(e, names, positional, nparams, slot, covered)) {
        return false;
    }
    for (uint32_t i = 0; i < nparams; i++) {
        if (!covered[i] && func->params.ptr[i]->def == NULL) {
            return false;
        }
    }
    for (uint32_t i = 0; i < given; i++) {
        const MsTyParam *param = &params[slot[i]];
        if ((param->flags & ~(MS_PARAM_POSITIONAL | MS_PARAM_VAR | MS_PARAM_MOVE)) != 0 ||
            !ms_body_open_argument(b, e->u.call.args.ptr[i].value, param, in)) {
            return false;
        }
    }
    b->facts->call_reordered[e->id] = ms_body_reordered(e, slot);
    return true;
}

typedef struct CallBack {
    const MsCheck *c;
    MsModId home;
    bool found;
} CallBack;

/* A call that is not to a native function (an extern or builtin): it may reach any function. */
static void generic_scan_call(void *ctx, const MsExpr *e) {
    CallBack *scan = ctx;
    if (e->kind != MS_E_CALL) {
        return;
    }
    const MsExpr *callee = e->u.call.callee;
    const MsSymId sym = callee->kind == MS_E_NAME ? ms_map_get(&scan->c->mods[scan->home].names, callee->u.sym) : MS_NONE;
    scan->found = scan->found || sym == MS_NONE || scan->c->syms.native[sym] == MS_NATIVE_SOURCE;
}

/* Whether a call into `callee` can come back to the module being checked: its body calls something
 * other than natives and it is in the module, or in a module that imports it (transitively). A growing
 * application needs such a cycle of calls. */
static bool generic_calls_back(MsBody *b, MsSymId callee) {
    const MsModId home = b->c->syms.module[callee];
    if (home == b->module) {
        if (b->c->syms.decl[callee]->kind != MS_D_FN) {
            return true; // a type's defaults are not scanned
        }
        CallBack scan = {.c = b->c, .home = home};
        const MsVisitor visitor = {.ctx = &scan, .expr = generic_scan_call};
        const MsFunc *func = &b->c->syms.decl[callee]->u.fn;
        ms_walk_callable(&visitor, func->params, func->body);
        return scan.found;
    }
    const size_t count = (size_t)b->c->nmods + 1;
    MsModId *reached = calloc(count, sizeof *reached);
    bool *seen = calloc(count, sizeof *seen);
    if (reached == NULL || seen == NULL) {
        free(reached);
        free(seen);
        return true; // cannot tell: assume it can
    }
    uint32_t n = 0;
    ms_module_reach(b->c, home, seen, reached, &n);
    const bool back = seen[b->module];
    free(reached);
    free(seen);
    return back;
}

/* A variable bound to a type built from variables (`T` as `List[T]`) can grow without end through a
 * cycle of applications, which the Rust checker reports (recursion.rs); the graph is not built here, so a
 * callee that cannot call back (generic_calls_back) is the only one let through. A variable passed on as
 * itself cannot grow. */
static bool generic_grows(MsBody *b, const MsInfer *in, MsSymId callee) {
    for (uint32_t i = 0; i < in->nvars; i++) {
        if (ms_ty_kind(&b->c->tys, in->bound[i]) != MS_K_VARIABLE && ms_ty_has_variable(&b->c->tys, in->bound[i]) &&
            generic_calls_back(b, callee)) {
            return true;
        }
    }
    return false;
}

/* Whether a field of the type declaration has a default value, an expression that can call back. */
static bool generic_has_defaults(const MsDecl *decl) {
    for (uint32_t i = 0; i < decl->u.type.fields.len; i++) {
        if (decl->u.type.fields.ptr[i]->def != NULL) {
            return true;
        }
    }
    return false;
}

/* Every variable is bound to an admitted type and each of its bounds, with the bindings applied, is met. */
static bool generic_bounds(MsBody *b, MsInfer *in) {
    if (b->methods == NULL) {
        return false;
    }
    for (uint32_t i = 0; i < in->nvars; i++) {
        // A type built from the caller's variables is declined by the growth guard in the caller.
        if (in->bound[i] == MS_TY_NONE || (in->bound[i] != b->void_ty && !ms_body_is_admitted(b, in->bound[i]))) {
            return false;
        }
        const MsVarInfo *info = ms_var_info(b->c, in->vars[i]);
        for (uint32_t k = 0; k < info->nbounds; k++) {
            const MsTy bound = ms_infer_apply(in, info->bounds[k]);
            if (ms_implements(b->c, b->methods, in->bound[i], bound) != MS_FIT_YES) {
                return false;
            }
        }
    }
    return true;
}

/* The type arguments the call was inferred at, in the order of the callee's variables: the lowering
 * makes one copy of the callee per list. */
static void generic_record_type_args(MsBody *b, const MsExpr *e, const MsInfer *in) {
    MsFacts *facts = b->facts;
    if (facts->ntype_args + in->nvars > facts->ctype_args) {
        uint32_t cap = facts->ctype_args == 0 ? 16 : facts->ctype_args * 2;
        while (cap < facts->ntype_args + in->nvars) {
            cap *= 2;
        }
        MsTy *grown = MS_NEW_N(&b->c->arena, MsTy, cap);
        if (facts->ntype_args != 0) {
            memcpy(grown, facts->type_args, facts->ntype_args * sizeof *grown);
        }
        facts->type_args = grown;
        facts->ctype_args = cap;
    }
    facts->call_type_args_at[e->id] = facts->ntype_args;
    facts->call_type_args_len[e->id] = in->nvars;
    for (uint32_t i = 0; i < in->nvars; i++) {
        facts->type_args[facts->ntype_args++] = in->bound[i];
    }
}

/* Variables the arguments left unbound take their type from the type the context expects of the
 * call's result (`x: List[Int] := empty()`). A variable with a default keeps it when it already fits
 * the expected type, which this does not judge: those calls, and a result the expected type
 * contradicts (Rust reports a conflict), stay declined. */
static bool generic_from_expected(MsBody *b, MsInfer *in, MsTy result, MsTy expected) {
    uint32_t unbound = 0;
    for (uint32_t i = 0; i < in->nvars; i++) {
        const MsVarInfo *info = ms_var_info(b->c, in->vars[i]);
        if (in->bound[i] != MS_TY_NONE) {
            continue;
        }
        if (info != NULL && info->def != MS_TY_NONE) {
            return false;
        }
        unbound++;
    }
    if (unbound == 0 || expected == MS_TY_NONE || expected == b->invalid_ty || ms_body_has_invalid(b, expected)) {
        return unbound == 0;
    }
    MsInfer trial = *in;
    trial.bound = MS_NEW_N(&b->c->arena, MsTy, (size_t)in->nvars + 1);
    memcpy(trial.bound, in->bound, in->nvars * sizeof *trial.bound);
    if (ms_infer_match(&trial, result, expected) != MS_MATCH_OK) {
        return false;
    }
    memcpy(in->bound, trial.bound, in->nvars * sizeof *trial.bound);
    return true;
}

MsTy ms_body_generic_call(MsBody *b, const MsExpr *e, MsSymId sym, const MsTypeRefs *written, MsTy expected) {
    const MsDef *def = ms_def(b->c, sym);
    const MsTy sig = b->c->syms.ty[sym];
    MsInfer in;
    ms_infer_init(&in, b->c, &b->c->arena, def->vars, def->nvars);
    if (written != NULL) {
        // `f[Int](x)`: the written arguments bind the first variables, the rest are inferred.
        MsTy given[16];
        if (written->len == 0 || written->len > 16 || written->len > def->nvars) {
            return ms_body_unsupported(b);
        }
        for (uint32_t i = 0; i < written->len; i++) {
            given[i] = ms_body_type_argument(b, written->ptr[i]);
            if (given[i] == MS_TY_NONE) {
                return MS_TY_NONE;
            }
        }
        if (!ms_infer_give(&in, given, written->len)) {
            return ms_body_unsupported(b);
        }
    }
    uint32_t first = 0;
    uint32_t slot[16];
    if (!generic_arguments(b, e, sig, &b->c->syms.decl[sym]->u.fn, &in, slot)) {
        return ms_body_unsupported(b);
    }
    if (!generic_from_expected(b, &in, b->c->tys.result[sig], expected)) {
        return ms_body_unsupported(b);
    }
    if (ms_infer_defaults(&in, &first) != 0) {
        return ms_body_unsupported(b);
    }
    if (!generic_bounds(b, &in)) {
        return ms_body_unsupported(b);
    }
    if (generic_grows(b, &in, sym)) {
        return ms_body_unsupported(b);
    }
    const MsTy result = ms_infer_apply(&in, b->c->tys.result[sig]);
    if (ms_body_has_invalid(b, result)) {
        return b->invalid_ty;
    }
    if (!ms_body_is_bindable(b, result) && result != b->void_ty && !ms_body_is_handle(b, result)) {
        return ms_body_unsupported(b);
    }
    b->facts->call_callee[e->id] = sym;
    ms_body_record_function_arguments(b, e, ms_infer_apply(&in, sig), slot);
    generic_record_type_args(b, e, &in);
    return result;
}

static bool generic_is_native(const MsBody *b, MsSymId sym) {
    return ms_ty_kind(&b->c->tys, b->c->syms.ty[sym]) == MS_K_NATIVE;
}

static bool generic_is_nominal(const MsBody *b, MsSymId sym) {
    const MsKind kind = ms_ty_kind(&b->c->tys, b->c->syms.ty[sym]);
    return kind == MS_K_TYPE || kind == MS_K_NATIVE;
}

/* `Name[Args](fields)` or `Name(fields)` for a generic type: the written arguments give the first
 * variables, each field argument binds the rest, bounds must hold, and the call has the type
 * applied to them. Arguments pair with fields by label or position (ms_body_bind_arguments);
 * fields left out take their default. Natives (`Map[K, V]()`) have no fields to give. */
MsTy ms_body_generic_construct(MsBody *b, const MsExpr *e, MsSymId sym, const MsTypeRefs *written) {
    const MsSyms *syms = &b->c->syms;
    ms_module_resolve_types(b->c, syms->module[sym]); // the declaring module's fields and variables
    const MsDef *def = ms_def(b->c, sym);
    const MsDecl *decl = syms->decl[sym];
    const uint32_t nargs = e->u.call.args.len;
    if (decl == NULL || decl->kind != MS_D_TYPE || (syms->module[sym] != b->module && decl->u.type.opaque) ||
        !generic_is_nominal(b, sym) || (generic_is_native(b, sym) && nargs != 0) || def->nvars == 0 || nargs > def->nfields ||
        def->nfields != decl->u.type.fields.len || nargs > 16) {
        return ms_body_unsupported(b);
    }
    MsInfer in;
    ms_infer_init(&in, b->c, &b->c->arena, def->vars, def->nvars);
    if (written != NULL) {
        MsTy given[16];
        if (written->len == 0 || written->len > 16 || written->len > def->nvars) {
            return ms_body_unsupported(b);
        }
        for (uint32_t i = 0; i < written->len; i++) {
            given[i] = ms_body_type_argument(b, written->ptr[i]);
            if (given[i] == MS_TY_NONE) {
                return MS_TY_NONE;
            }
        }
        if (!ms_infer_give(&in, given, written->len)) {
            return ms_body_unsupported(b);
        }
    }
    MsSym *names = MS_NEW_N(&b->c->arena, MsSym, def->nfields + 1);
    bool *covered = MS_NEW_N(&b->c->arena, bool, def->nfields + 1);
    uint32_t slot[16] = {0};
    for (uint32_t i = 0; i < def->nfields; i++) {
        names[i] = def->fields[i].name;
    }
    if (!ms_body_bind_arguments(e, names, NULL, def->nfields, slot, covered)) {
        return ms_body_unsupported(b);
    }
    for (uint32_t i = 0; i < def->nfields; i++) {
        if (!covered[i] && decl->u.type.fields.ptr[i]->def == NULL) {
            return ms_body_unsupported(b);
        }
    }
    for (uint32_t i = 0; i < nargs; i++) {
        const MsTyParam *field = &def->fields[slot[i]];
        const MsExpr *value = e->u.call.args.ptr[i].value;
        const MsTy want = ms_infer_apply(&in, field->ty);
        if (field->flags != 0) {
            return ms_body_unsupported(b);
        }
        if (!ms_body_mentions_unbound(b, &in, want)) {
            if (!ms_body_is_bindable(b, want) || ms_body_expr(b, value, want) == MS_TY_NONE) {
                return ms_body_unsupported(b);
            }
            continue;
        }
        const MsTy actual = ms_body_expr(b, value, MS_TY_NONE);
        if (actual == MS_TY_NONE || !ms_body_is_bindable(b, actual) || ms_infer_match(&in, field->ty, actual) != MS_MATCH_OK) {
            return ms_body_unsupported(b);
        }
    }
    uint32_t first = 0;
    if (ms_infer_defaults(&in, &first) != 0 || !generic_bounds(b, &in)) {
        return ms_body_unsupported(b);
    }
    const MsTy result = ms_ty_apply(b->c, syms->ty[sym], in.bound, def->nvars);
    // A type applied to the caller's own variables may be a cycle of applications that never ends: its
    // defaults call back into the caller, or an argument grows. The Rust checker reports both (recursion.rs).
    if (result == MS_TY_NONE || !ms_body_is_bindable(b, result) || generic_grows(b, &in, sym) ||
        (generic_has_defaults(decl) && ms_ty_has_variable(&b->c->tys, result))) {
        return ms_body_unsupported(b);
    }
    b->facts->call_reordered[e->id] = ms_body_reordered(e, slot);
    b->facts->call_callee[e->id] = sym;
    return result;
}

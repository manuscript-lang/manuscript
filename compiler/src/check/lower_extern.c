/* A call of a bodiless `extern fn` (`msstd_math_sqrt` in stdlib/internal/math.ms): the runtime function
 * of the same name, found in the ms-sig table (rt_ops.h) and marshalled as a native method is. The
 * call's arguments are the function's parameters in order. A function the table does not list, or
 * whose signature `lb_native_call` cannot marshal, leaves the caller to the Rust lowering. */
#include "ms/lower_internal.h"
#include "ms/doc.h"
#include "ms/rt_ops.h"

/* The field names an `extern type` declares its runtime layout with (`// ms: fields lo hi exp` above it): the type is plain
 * data of that many integer fields, passed by value. False for a type that declares none. */
static bool lx_field_names(const Lb *lb, MsTy ty, MsStr *names) {
    if (lb->c->tys.def[ty] == 0) {
        return false;
    }
    const MsSymId sym = lb->c->tys.def[ty] - 1;
    const MsDecl *decl = lb->c->syms.decl[sym];
    const MsModId owner = lb->c->syms.module[sym];
    return decl != NULL && owner != MS_NONE &&
           ms_doc_marker_args(lb->c->mods[owner].text, decl->pos.offset, "fields", names);
}

/* The record of an extern type that declares its fields: one integer field per name, built once. */
static MirTy lx_record(Lb *lb, MsTy ty, MsStr names) {
    if (lb->type_of[ty] != MIR_NONE) {
        return lb->type_of[ty];
    }
    MirField fields[MS_RT_MAX_PARAMS];
    uint32_t count = 0;
    while (names.len > 0 && count < MS_RT_MAX_PARAMS) {
        size_t end = 0;
        while (end < names.len && names.ptr[end] != ' ') {
            end++;
        }
        fields[count++] = (MirField){mir_name(lb->m, names.ptr, end), MIR_INT};
        const size_t next = end < names.len ? end + 1 : end; // past the space
        names = (MsStr){names.ptr + next, (uint32_t)(names.len - next)};
    }
    const MsStr name = ms_name(lb->c->names, lb->c->tys.name[ty]);
    const uint32_t id = mir_add_type(lb->m, mir_name(lb->m, name.ptr, name.len));
    lb->m->type_defs[id].fields = MS_NEW_N(&lb->m->arena, MirField, (size_t)count + 1);
    memcpy(lb->m->type_defs[id].fields, fields, count * sizeof *fields);
    lb->m->type_defs[id].nfields = count;
    lb->type_of[ty] = mir_ty_type(lb->m, id);
    return lb->type_of[ty];
}

/* The MIR type of an `extern type` the runtime owns (`NativeScope`, `HttpHeaders`): a runtime object named by it, a
 * record when it declares its fields (`Decimal`), or MIR_NONE for any other type or a generic native. */
MirTy lx_type(Lb *lb, MsTy ty) {
    if (ms_ty_kind(&lb->c->tys, ty) != MS_K_NATIVE || lb->c->tys.nargs[ty] != 0) {
        return MIR_NONE;
    }
    MsStr names = {0};
    if (lx_field_names(lb, ty, &names)) {
        return lx_record(lb, ty, names);
    }
    const MsStr name = ms_name(lb->c->names, lb->c->tys.name[ty]);
    return mir_ty_obj(lb->m, mir_name(lb->m, name.ptr, name.len), NULL, 0);
}

/* Whether `callee` names an `extern fn`. */
bool lx_is_extern(const Lb *lb, MsSymId callee) {
    const MsDecl *decl = lb->c->syms.decl[callee];
    return lb->c->syms.kind[callee] == MS_SYM_FN && decl != NULL && decl->kind == MS_D_FN && decl->u.fn.external;
}

LbVal lx_call(Lb *lb, const MsExpr *e, MsSymId callee) {
    const MsStr name = ms_name(lb->c->names, lb->c->syms.decl[callee]->u.fn.name);
    const MsRtFn *fn = ms_rt_fn_find(name.ptr, name.len);
    const uint32_t nargs = e->u.call.args.len;
    if (fn == NULL || nargs > MS_RT_MAX_PARAMS) {
        return LB_UNSUPPORTED(lb);
    }
    MirValue args[MS_RT_MAX_PARAMS];
    for (uint32_t i = 0; i < nargs && lb->ok; i++) {
        const LbVal value = lb_expr(lb, e->u.call.args.ptr[i].value);
        args[i] = value.v;
        if (lb->ok && value.owned) {
            lb_hold_temp(lb, value.v); // a borrowed argument lives to the end of the statement
        }
    }
    const MsTy result = lb->facts->expr_ty[e->id];
    const MirTy result_ty = result == lb->void_ty ? MIR_VOID : lb_mir_ty(lb, result);
    if (!lb->ok || result_ty == MIR_NONE) {
        return LB_UNSUPPORTED(lb);
    }
    if (ls_reports_status(lb, fn, result_ty)) {
        return ls_call(lb, fn, args, nargs, result_ty);
    }
    if (ls_reports_found(lb, fn, result_ty)) {
        return ls_found_call(lb, fn, args, nargs, result_ty);
    }
    const LbVal call = lb_native_call(lb, fn, args, nargs, result_ty);
    if (lb->ok && result_ty != MIR_VOID && mir_b_ty(&lb->b, call.v) != result_ty) {
        return LB_UNSUPPORTED(lb); // the marshalled call yields something else (a handle written through `out`)
    }
    return call;
}

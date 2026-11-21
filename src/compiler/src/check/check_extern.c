/* Extern signatures (ms/extern_sig.h). */
#include <string.h>

#include "ms/check.h"
#include "ms/extern_sig.h"

enum { MS_EXTERN_MAX_CALLBACK_PARAMS = 6 };

static const char extern_crossing_text[] =
    "sized numbers, Bool, String, Bytes, extern types this program declares, and Lists of them";

static bool extern_text_is(MsStr text, const char *expected) {
    return text.len == strlen(expected) && memcmp(text.ptr, expected, text.len) == 0;
}

static bool extern_has_prefix(MsStr text, const char *prefix) {
    const size_t length = strlen(prefix);
    return text.len >= length && memcmp(text.ptr, prefix, length) == 0;
}

static void extern_error(MsCheck *c, MsModId module, MsPos pos, MsStr message) {
    const MsCheckDiag diag = {.diag = {.pos = pos, .message = message}, .phase = MS_PHASE_TYPE};
    ms_report(c, module, &diag);
}

/* An `extern type` declared outside the standard library. */
static bool extern_is_user_type(const MsCheck *c, MsTy ty) {
    if (ms_ty_kind(&c->tys, ty) != MS_K_NATIVE || c->tys.nargs[ty] != 0 || c->tys.def[ty] == 0) {
        return false;
    }
    const MsSymId sym = c->tys.def[ty] - 1;
    const MsDecl *decl = c->syms.decl[sym];
    const MsModId owner = c->syms.module[sym];
    return decl != NULL && decl->kind == MS_D_TYPE && decl->u.type.external && owner != MS_NONE &&
           !extern_has_prefix(ms_name(c->names, c->mods[owner].path), "@std/");
}

static bool extern_is_element(const MsCheck *c, MsTy ty) {
    static const char *const scalars[] = {"Int",   "Int8",   "Int16",  "Int32",   "Int64",
                                          "UInt8", "UInt16", "UInt32", "UInt64",  "Float",
                                          "Float32", "Bool", "String"};
    const MsStr id = ms_name(c->names, c->tys.id[ty]);
    for (size_t i = 0; i < MS_COUNT_OF(scalars); i++) {
        if (extern_text_is(id, scalars[i])) {
            return true;
        }
    }
    return ms_ty_is(&c->tys, ty, MS_BI_BYTES) || extern_is_user_type(c, ty);
}

/* A value that crosses to a user extern: an element, or a List of one. */
static bool extern_crosses(const MsCheck *c, MsTy ty) {
    if (ms_ty_is(&c->tys, ty, MS_BI_LIST) && c->tys.nargs[ty] == 1) {
        return extern_is_element(c, ms_ty_args(&c->tys, ty)[0]);
    }
    return extern_is_element(c, ty);
}

/* A function an extern takes as an `ms_fn`. */
static bool extern_crosses_callback(const MsCheck *c, MsTy ty) {
    const MsTy result = c->tys.result[ty];
    const bool result_ok = result == MS_TY_NONE || ms_ty_is(&c->tys, result, MS_BI_VOID) ||
                           (extern_is_element(c, result) && !extern_is_user_type(c, result));
    if (c->tys.nparams[ty] > MS_EXTERN_MAX_CALLBACK_PARAMS || !result_ok) {
        return false;
    }
    const MsTyParam *params = ms_ty_params(&c->tys, ty);
    for (uint32_t i = 0; i < c->tys.nparams[ty]; i++) {
        if (!extern_is_element(c, params[i].ty)) {
            return false;
        }
    }
    return true;
}

static MsStr extern_name(const MsCheck *c, MsTy ty) {
    return ms_name(c->names, c->tys.name[ty]);
}

static void extern_check_parameter(MsCheck *c, MsModId module, const MsParam *p, MsTy ty) {
    const MsStr name = ms_name(c->names, p->name);
    if (p->is_mutable) {
        extern_error(c, module, p->pos,
                     ms_arena_fmt(&c->arena, "extern parameter %.*s cannot be var; a native borrows its arguments",
                                  (int)name.len, name.ptr));
    } else if (p->def != NULL) {
        extern_error(c, module, p->pos,
                     ms_arena_fmt(&c->arena,
                                  "extern parameter %.*s cannot have a default; the native symbol takes every argument",
                                  (int)name.len, name.ptr));
    } else if (ms_ty_kind(&c->tys, ty) == MS_K_FUNCTION) {
        if (!extern_crosses_callback(c, ty)) {
            MsBuf shown = {0};
            ms_ty_show(&shown, c->names, &c->tys, ty);
            extern_error(c, module, p->pos,
                         ms_arena_fmt(&c->arena,
                                      "extern parameter %.*s has type %.*s, which cannot cross the native boundary; a "
                                      "function an extern takes has at most %d parameters of sized numbers, Bool, "
                                      "String, Bytes or extern types this program declares, and returns a number, "
                                      "Bool, String, Bytes or Void",
                                      (int)name.len, name.ptr, (int)shown.len, shown.data,
                                      MS_EXTERN_MAX_CALLBACK_PARAMS));
            ms_buf_free(&shown);
        }
    } else if (ms_ty_kind(&c->tys, ty) != MS_K_INVALID && !extern_crosses(c, ty)) {
        const MsStr type_name = extern_name(c, ty);
        extern_error(c, module, p->pos,
                     ms_arena_fmt(&c->arena,
                                  "extern parameter %.*s has type %.*s, which cannot cross the native boundary; an "
                                  "extern takes sized numbers, Bool, String, Bytes, extern types this program "
                                  "declares, Lists of them, and functions of them",
                                  (int)name.len, name.ptr, (int)type_name.len, type_name.ptr));
    }
}

/* Whether every case of the error type carries nothing, `code: Int`, `message: String`, or both. */
static bool extern_error_type_ok(MsCheck *c, MsTy error) {
    if (c->tys.def[error] == 0) {
        return false;
    }
    const MsDef *def = ms_def(c, c->tys.def[error] - 1);
    if (def->ncases == 0) {
        return false;
    }
    for (uint32_t i = 0; i < def->ncases; i++) {
        for (uint32_t k = 0; k < def->cases[i].nfields; k++) {
            const MsTyParam *field = &def->cases[i].fields[k];
            const MsStr name = ms_name(c->names, field->name);
            const bool code = extern_text_is(name, "code") && ms_ty_is(&c->tys, field->ty, MS_BI_INT);
            const bool message = extern_text_is(name, "message") && ms_ty_is(&c->tys, field->ty, MS_BI_STRING);
            if (!code && !message) {
                return false;
            }
        }
    }
    return true;
}

static void extern_check_result(MsCheck *c, MsModId module, const MsFunc *f, MsTy result) {
    if (result == MS_TY_NONE || ms_ty_kind(&c->tys, result) == MS_K_INVALID) {
        return;
    }
    const MsPos pos = f->result->pos;
    if (ms_ty_is(&c->tys, result, MS_BI_RESULT) && c->tys.nargs[result] == 2) {
        const MsTy ok = ms_ty_args(&c->tys, result)[0];
        const MsTy error = ms_ty_args(&c->tys, result)[1];
        if (!ms_ty_is(&c->tys, ok, MS_BI_VOID) && !extern_crosses(c, ok)) {
            const MsStr name = extern_name(c, ok);
            extern_error(c, module, pos,
                         ms_arena_fmt(&c->arena,
                                      "extern Result value has type %.*s, which cannot cross the native boundary; an "
                                      "extern Result holds %s, or Void",
                                      (int)name.len, name.ptr, extern_crossing_text));
        } else if (!extern_error_type_ok(c, error)) {
            const MsStr name = extern_name(c, error);
            extern_error(c, module, pos,
                         ms_arena_fmt(&c->arena,
                                      "extern error type %.*s must be an alternative whose cases carry nothing, `code: "
                                      "Int`, `message: String`, or both; the native returns the status 1 + the case "
                                      "index and fills code_out and message_out",
                                      (int)name.len, name.ptr));
        }
    } else if (!ms_ty_is(&c->tys, result, MS_BI_VOID) && !extern_crosses(c, result)) {
        const MsStr name = extern_name(c, result);
        extern_error(c, module, pos,
                     ms_arena_fmt(&c->arena,
                                  "extern result has type %.*s, which cannot cross the native boundary; an extern "
                                  "returns %s, Void, or a Result of one",
                                  (int)name.len, name.ptr, extern_crossing_text));
    }
}

static void extern_check_function(MsCheck *c, MsModId module, const MsDecl *d, MsSymId sym) {
    const MsFunc *f = &d->u.fn;
    const MsStr name = ms_name(c->names, f->name);
    if (extern_has_prefix(name, "msrt_") || extern_has_prefix(name, "msstd_")) {
        extern_error(c, module, d->pos,
                     ms_arena_fmt(&c->arena,
                                  "extern fn %.*s names a runtime-internal symbol; msrt_ and msstd_ natives are "
                                  "reserved for bundled standard modules, so call the standard library instead",
                                  (int)name.len, name.ptr));
    }
    if (f->type_params.len != 0) {
        extern_error(c, module, d->pos,
                     ms_arena_fmt(&c->arena, "%s",
                                  "an extern fn cannot be generic; declare the concrete types the native symbol takes"));
    }
    const MsTy ty = c->syms.ty[sym];
    const bool is_function = ty != MS_TY_NONE && ms_ty_kind(&c->tys, ty) == MS_K_FUNCTION;
    const MsTyParam *types = is_function ? ms_ty_params(&c->tys, ty) : NULL;
    for (uint32_t i = 0; is_function && i < f->params.len && i < c->tys.nparams[ty]; i++) {
        extern_check_parameter(c, module, f->params.ptr[i], types[i].ty);
    }
    extern_check_result(c, module, f, is_function ? c->tys.result[ty] : MS_TY_NONE);
}

void ms_module_check_externs(MsCheck *c, MsModId module) {
    if (extern_has_prefix(ms_name(c->names, c->mods[module].path), "@std/")) {
        return;
    }
    const MsModule *syntax = c->mods[module].syntax;
    for (uint32_t i = 0; i < syntax->ndecls; i++) {
        const MsDecl *d = syntax->decls[i];
        if (d->kind == MS_D_TYPE && d->u.type.external && d->u.type.type_params.len != 0) {
            const MsStr name = ms_name(c->names, d->u.type.name);
            extern_error(c, module, d->pos,
                         ms_arena_fmt(&c->arena,
                                      "extern type %.*s cannot be generic; declare one extern type per native handle",
                                      (int)name.len, name.ptr));
        }
        if (d->kind != MS_D_FN || !d->u.fn.external) {
            continue;
        }
        const MsSymId sym = ms_decl_own_symbol(c, module, d);
        if (sym != MS_NONE) {
            extern_check_function(c, module, d, sym);
        }
    }
}

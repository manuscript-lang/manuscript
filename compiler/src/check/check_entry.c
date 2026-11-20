/* Entry validation (ms/entry.h): reads the entry module's `main` from the tables the checker
 * filled and builds the diagnostic the Rust driver prints. */
#include <string.h>

#include "ms/entry.h"

static bool entry_id_is(const MsCheck *c, MsTy ty, const char *name) {
    MsStr id = ms_name(c->names, c->tys.id[ty]);
    return id.len == strlen(name) && memcmp(id.ptr, name, id.len) == 0;
}

/* `Void!`: a Result of Void and Error. */
static bool entry_is_close_result(const MsCheck *c, MsTy ty) {
    const MsTyTable *t = &c->tys;
    return ms_ty_is(t, ty, MS_BI_RESULT) && t->nargs[ty] == 2 && entry_id_is(c, ms_ty_args(t, ty)[0], "Void") &&
           ms_ty_is(t, ms_ty_args(t, ty)[1], MS_BI_ERROR);
}

/* `Int?!`: a Result of an optional Int and Error. */
static bool entry_is_status_result(const MsCheck *c, MsTy ty) {
    const MsTyTable *t = &c->tys;
    if (!ms_ty_is(t, ty, MS_BI_RESULT) || t->nargs[ty] != 2) {
        return false;
    }
    MsTy value = ms_ty_args(t, ty)[0];
    return ms_ty_is(t, value, MS_BI_OPTIONAL) && t->nargs[value] == 1 &&
           entry_id_is(c, ms_ty_args(t, value)[0], "Int") && ms_ty_is(t, ms_ty_args(t, ty)[1], MS_BI_ERROR);
}

static bool entry_result_ok(const MsCheck *c, MsTy result) {
    return result == MS_TY_NONE || entry_id_is(c, result, "Int") || entry_id_is(c, result, "Void") ||
           entry_is_close_result(c, result) || entry_is_status_result(c, result);
}

static const char *entry_detail(MsCheck *c, MsSymId main, bool constant, uint32_t parameters, MsTy result) {
    if (constant) {
        return "main is a constant, so rename it and declare 'fn main() Void:'";
    }
    if (c->syms.kind[main] != MS_SYM_FN) {
        return "main is declared as a type, so rename it and declare 'fn main() Void:'";
    }
    if (c->syms.nvars[main] != 0) {
        return "main cannot be generic, so remove its type parameters";
    }
    if (parameters > 0) {
        return "main takes no parameters, so remove them (read program arguments through the standard cli module)";
    }
    MsBuf shown = {0};
    if (result == MS_TY_NONE) {
        ms_buf_puts(&shown, "<invalid>");
    } else {
        ms_ty_show(&shown, c->names, &c->tys, result);
    }
    MsStr text = ms_arena_fmt(&c->arena,
                              "main returns %.*s, so return Void, Void! (an error prints and exits 1), Int?!, or an Int exit status",
                              (int)shown.len, shown.data);
    ms_buf_free(&shown);
    return text.ptr;
}

bool ms_check_entry(MsCheck *c, MsModId entry, bool only_if_declared, MsCheckDiag *out) {
    uint32_t found = ms_map_get(&c->mods[entry].scope, ms_intern_cstr(c->names, "main"));
    bool declared = found != MS_NONE;
    if (only_if_declared && !declared) {
        return false;
    }
    MsPos position = {.offset = 0, .line = 1, .column = 1};
    const char *detail = "no main function is declared, so add 'fn main() Void:' with an indented body";
    if (declared) {
        MsSymId main = found;
        const MsDecl *decl = c->syms.decl[main];
        MsTy ty = c->syms.ty[main];
        bool constant = c->syms.kind[main] == MS_SYM_FN && decl != NULL && decl->kind == MS_D_CONST;
        uint32_t parameters = ty != MS_TY_NONE && ms_ty_kind(&c->tys, ty) == MS_K_FUNCTION ? c->tys.nparams[ty] : 0;
        MsTy result = ty != MS_TY_NONE && ms_ty_kind(&c->tys, ty) == MS_K_FUNCTION ? c->tys.result[ty] : MS_TY_NONE;
        if (c->syms.kind[main] == MS_SYM_FN && !constant && c->syms.nvars[main] == 0 && parameters == 0 &&
            entry_result_ok(c, result)) {
            return false;
        }
        if (decl != NULL) {
            position = decl->pos;
        }
        detail = entry_detail(c, main, constant, parameters, result);
    }
    MsStr message = ms_arena_fmt(&c->arena, "entry must declare fn main; %s", detail);
    *out = (MsCheckDiag){.diag = {.pos = position, .message = message}, .phase = MS_PHASE_TYPE};
    return true;
}

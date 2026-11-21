/* Unread local bindings (`unused.rs`): a `let`, `var` or match payload name that nothing reads is
 * a diagnostic, unless it begins with `_`. The body checker counts the reads; this pass reports
 * from those counts, for the functions whose bodies it accepted. */
#include "ms/check.h"
#include "ms/facts.h"

#define UNUSED_REMEDY "name it with a leading '_' to ignore it"

static bool unused_is_local(MsBindRole role) {
    return role == MS_ROLE_LET || role == MS_ROLE_VAR || role == MS_ROLE_ARM || role == MS_ROLE_PATTERN;
}

static void unused_report(MsCheck *c, MsModId module, uint32_t binding) {
    const MsBindings *bindings = &c->mods[module].facts->bindings;
    const MsStr name = ms_name(c->names, bindings->name[binding]);
    const bool fed = (bindings->flags[binding] & MS_BIND_FED) != 0;
    const MsStr message =
        fed ? ms_arena_fmt(&c->arena,
                           "local binding %.*s is never read: it is only read to compute its own next value, so "
                           "nothing observes it; remove it, use it elsewhere, or " UNUSED_REMEDY,
                           (int)name.len, name.ptr)
            : ms_arena_fmt(&c->arena, "local binding %.*s is never read; remove it, use it, or " UNUSED_REMEDY,
                           (int)name.len, name.ptr);
    const MsCheckDiag diag = {.diag = {.pos = bindings->pos[binding], .message = message}, .phase = MS_PHASE_TYPE};
    ms_report(c, module, &diag);
}

/* Whether every function and constant of the module has been checked. The Rust checker reports
 * unread bindings only for a program without errors, and an unchecked function may have some. */
static bool unused_all_checked(const MsModuleRow *row) {
    for (uint32_t i = 0; i < row->syntax->ndecls; i++) {
        const MsDecl *d = row->syntax->decls[i];
        const bool callable = (d->kind == MS_D_FN && !d->u.fn.external) || d->kind == MS_D_CONST;
        if (callable && !d->synthetic && !row->facts->body_checked[d->id]) {
            return false;
        }
    }
    return true;
}

void ms_module_check_unused(MsCheck *c, MsModId module) {
    const MsModuleRow *row = &c->mods[module];
    const MsFacts *facts = row->facts;
    // Unfinished code (a buffer with a parse error) has bindings it has not read yet.
    if (facts == NULL || facts->body_checked == NULL || row->ndiags != 0 || !unused_all_checked(row)) {
        return;
    }
    const MsBindings *bindings = &facts->bindings;
    for (uint32_t i = 0; i < bindings->count; i++) {
        const MsStr name = ms_name(c->names, bindings->name[i]);
        const bool ignored = name.len != 0 && name.ptr[0] == '_';
        const bool checked = facts->body_checked[bindings->callable[i]];
        // A payload name that shadows a case or a type is explained by the lint MSL106.
        const bool shadows = bindings->conflict[i] != MS_CONFLICT_NONE;
        if (checked && unused_is_local(bindings->role[i]) && !ignored && !shadows && bindings->reads[i] == 0) {
            unused_report(c, module, i);
        }
    }
}

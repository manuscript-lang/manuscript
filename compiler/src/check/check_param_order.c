/* Optional parameters and fields come last (ms/param_order.h). */
#include <string.h>

#include "ms/check.h"
#include "ms/param_order.h"

/* A `T?` parameter or field defaults to none, so a written type of that shape makes it optional. */
static bool param_order_is_optional_type(const MsCheck *c, const MsTypeRef *ty) {
    if (ty == NULL || ty->kind != MS_TYPE_NAMED || ty->args.len != 1) {
        return false;
    }
    const MsStr name = ms_name(c->names, ty->name);
    return name.len == 8 && memcmp(name.ptr, "Optional", 8) == 0;
}

static void param_order_check(MsCheck *c, MsModId module, MsParams params) {
    uint32_t first = 0;
    while (first < params.len && params.ptr[first]->def == NULL) {
        first++;
    }
    if (first == params.len) {
        return;
    }
    const MsStr optional = ms_name(c->names, params.ptr[first]->name);
    const char *why = param_order_is_optional_type(c, params.ptr[first]->ty)
                          ? " (a `T?` parameter or field defaults to none, so it counts as optional)"
                          : "";
    for (uint32_t i = first; i < params.len; i++) {
        if (params.ptr[i]->def != NULL) {
            continue;
        }
        const MsStr name = ms_name(c->names, params.ptr[i]->name);
        const MsStr message = ms_arena_fmt(&c->arena, "required %.*s follows optional %.*s%s; put optional parameters and fields last",
                                           (int)name.len, name.ptr, (int)optional.len, optional.ptr, why);
        const MsCheckDiag diag = {.diag = {.pos = params.ptr[i]->pos, .message = message}, .phase = MS_PHASE_TYPE};
        ms_report(c, module, &diag);
    }
}

void ms_module_check_param_order(MsCheck *c, MsModId module) {
    const MsStr path = ms_name(c->names, c->mods[module].path);
    if (path.len >= 5 && memcmp(path.ptr, "@std/", 5) == 0) {
        return;
    }
    const MsModule *syntax = c->mods[module].syntax;
    for (uint32_t i = 0; i < syntax->ndecls; i++) {
        const MsDecl *d = syntax->decls[i];
        if (d->kind == MS_D_FN) {
            param_order_check(c, module, d->u.fn.params);
        } else if (d->kind == MS_D_TYPE) {
            param_order_check(c, module, d->u.type.fields);
        } else if (d->kind == MS_D_IMPL) {
            for (uint32_t m = 0; m < d->u.impl.methods.len; m++) {
                param_order_check(c, module, d->u.impl.methods.ptr[m]->func.params);
            }
        }
    }
}

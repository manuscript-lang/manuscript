/* Interfaces without operations (ms/interface_sig.h). */
#include <string.h>

#include "ms/check.h"
#include "ms/interface_sig.h"

static const char interface_empty_message[] =
    "an interface declares at least one operation; only the standard library declares a property without "
    "operations, like `Data`";

void ms_module_check_interfaces(MsCheck *c, MsModId module) {
    const MsStr path = ms_name(c->names, c->mods[module].path);
    if (path.len >= 5 && memcmp(path.ptr, "@std/", 5) == 0) {
        return;
    }
    const MsModule *syntax = c->mods[module].syntax;
    for (uint32_t i = 0; i < syntax->ndecls; i++) {
        const MsDecl *d = syntax->decls[i];
        if (d->kind != MS_D_INTERFACE || d->u.iface.methods.len != 0) {
            continue;
        }
        const MsStr message = {interface_empty_message, (uint32_t)(sizeof interface_empty_message - 1)};
        const MsCheckDiag diag = {.diag = {.pos = d->pos, .message = message}, .phase = MS_PHASE_TYPE};
        ms_report(c, module, &diag);
    }
}

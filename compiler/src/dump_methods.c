/* Canonical text form of the operations and methods, compared with the Rust checker's
 * (crates/ms-check/examples/c_oracle_methods.rs). */
#include "ms/dump.h"
#include "ms/methods.h"

static void put_text(MsBuf *out, const MsCheck *c, MsSym name) {
    const MsStr text = ms_name(c->names, name);
    ms_buf_put(out, text.ptr, text.len);
}

static void put_ty(MsBuf *out, const MsCheck *c, MsTy ty) { ms_ty_show(out, c->names, &c->tys, ty); }

/* `[T default=- bounds=A,B; U default=Int bounds=]` */
static void put_variables(MsBuf *out, const MsCheck *c, const MsTy *vars, uint32_t count) {
    ms_buf_putc(out, '[');
    for (uint32_t i = 0; i < count; i++) {
        const MsVarInfo *info = vars[i] < c->var_info_cap ? &c->var_info[vars[i]] : NULL;
        ms_buf_puts(out, i == 0 ? "" : "; ");
        put_text(out, c, c->tys.name[vars[i]]);
        ms_buf_puts(out, " default=");
        if (info != NULL && info->def != MS_TY_NONE) {
            put_ty(out, c, info->def);
        } else {
            ms_buf_putc(out, '-');
        }
        ms_buf_puts(out, " bounds=");
        for (uint32_t k = 0; info != NULL && k < info->nbounds; k++) {
            ms_buf_puts(out, k == 0 ? "" : ",");
            put_ty(out, c, info->bounds[k]);
        }
    }
    ms_buf_putc(out, ']');
}

static void put_labels(MsBuf *out, const MsCheck *c, MsTy signature) {
    const MsTyParam *params = ms_ty_params(&c->tys, signature);
    for (uint32_t i = 0; i < c->tys.nparams[signature]; i++) {
        ms_buf_puts(out, i == 0 ? "" : ",");
        ms_buf_puts(out, (params[i].flags & MS_PARAM_VAR) != 0 ? "var " : "");
        ms_buf_puts(out, (params[i].flags & MS_PARAM_MOVE) != 0 ? "move " : "");
        put_text(out, c, params[i].name);
    }
}

void ms_dump_operations(MsBuf *out, const MsCheck *c, MsModId module, const MsMethodTable *table) {
    const MsModuleRow *row = &c->mods[module];
    for (uint32_t i = 0; i < row->norder; i++) {
        const MsSymId sym = row->order[i];
        const MsDecl *d = c->syms.decl[sym];
        const MsOperations *operations = d != NULL && d->kind == MS_D_INTERFACE ? ms_interface_operations(table, sym) : NULL;
        for (uint32_t k = 0; operations != NULL && k < operations->count; k++) {
            const MsOperation *op = &operations->items[k];
            ms_buf_puts(out, "op ");
            put_text(out, c, c->syms.name[sym]);
            ms_buf_putc(out, '.');
            put_text(out, c, op->name);
            ms_buf_puts(out, ": ");
            put_ty(out, c, op->ty);
            ms_buf_puts(out, " params=");
            put_labels(out, c, op->ty);
            ms_buf_puts(out, " vars=");
            put_variables(out, c, op->vars, op->nvars);
            ms_buf_putc(out, '\n');
        }
    }
}

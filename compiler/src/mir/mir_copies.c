/* copies: the places where a clone copies an object (`ms check --copies`). Port of copies.rs. */
#include <string.h>

#include "ms/mir_pass.h"


static bool cp_holds_in(const MirModule *m, MirTy t, MsBuf *seen);

static bool cp_any(const MirModule *m, const MirField *fields, uint32_t n, MsBuf *seen) {
    for (uint32_t i = 0; i < n; i++) {
        if (cp_holds_in(m, fields[i].ty, seen)) {
            return true;
        }
    }
    return false;
}

static bool cp_holds_kind(const MirModule *m, const MirTyData *d, MsBuf *seen) {
    switch (d->kind) {
    case MK_OBJ:
        if (d->obj_class == MIR_OBJ_COLLECTION) {
            for (uint32_t i = 0; i < d->nargs; i++) {
                if (cp_holds_in(m, d->args[i], seen)) {
                    return true;
                }
            }
            return false;
        }
        return true;
    case MK_FN: case MK_IFACE: return true;
    case MK_OPT: case MK_LIST: return cp_holds_in(m, d->elem, seen);
    case MK_TYPE: return cp_any(m, m->type_defs[d->id].fields, m->type_defs[d->id].nfields, seen);
    case MK_ALT: {
        const MirAltDef *a = &m->alts[d->id];
        for (uint32_t c = 0; c < a->ncases; c++) {
            if (cp_any(m, a->cases[c].fields, a->cases[c].nfields, seen)) {
                return true;
            }
        }
        return false;
    }
    default: return false;
    }
}

/* `t` is on the stack of types being looked into while it is being looked into, so a recursive type
 * answers false for itself. */
static bool cp_holds_in(const MirModule *m, MirTy t, MsBuf *seen) {
    for (size_t i = 0; i < MS_VEC_LEN(*seen, MirTy); i++) {
        if (MS_VEC_AT(*seen, MirTy, i) == t) {
            return false;
        }
    }
    MS_VEC_PUSH(*seen, MirTy, t);
    const bool held = cp_holds_kind(m, mir_ty_data(m, t), seen);
    MS_VEC_POP(*seen, MirTy);
    return held;
}

bool mir_holds_object(const MirModule *m, MirTy t) {
    MsBuf seen = {0};
    const bool held = cp_holds_in(m, t, &seen);
    ms_buf_free(&seen);
    return held;
}

/* Whether `v` is the result of an `opt.none` in `f`. */
static bool cp_is_none(const MirFunc *f, MirValue v) {
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        for (uint32_t k = 0; k < f->blocks[bi].ninsts; k++) {
            const MirInst *in = &f->blocks[bi].insts[k];
            if ((in->op == MOP_OptNone || in->op == MOP_OptNoneOwned) && in->res == v) {
                return true;
            }
        }
    }
    return false;
}

/* One line per copy: `func<TAB>type<TAB>file:line`. */
void mir_object_copies(const MirModule *m, MsBuf *out) {
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        const MirFunc *f = &m->funcs[fi];
        for (uint32_t bi = 0; bi < f->nblocks; bi++) {
            for (uint32_t k = 0; k < f->blocks[bi].ninsts; k++) {
                const MirInst *in = &f->blocks[bi].insts[k];
                if (in->op != MOP_Clone || (in->imm.tag == MI_INT && in->imm.i == 1)) {
                    continue;
                }
                const MirTy t = mir_value_ty(f, in->args[0]);
                if (cp_is_none(f, in->args[0]) || !mir_holds_object(m, t)) {
                    continue;
                }
                const MsStr name = ms_name(&m->names, f->name);
                ms_buf_printf(out, "%.*s\t", (int)name.len, name.ptr);
                mir_print_ty(m, t, out);
                const MsStr file = in->loc.file < m->nfiles ? m->files[in->loc.file] : (MsStr){"", 0};
                ms_buf_printf(out, "\t%.*s:%u\n", (int)file.len, file.ptr, in->loc.line);
            }
        }
    }
}

/* Helpers shared by the MIR passes: extern declaration, plain-memory classification, instruction
 * constructors. Everything is built in the module's arena. */
#include <string.h>

#include "ms/mir_pass.h"

uint32_t mir_extern_get(MirModule *m, const char *name, const MirTy *params, uint32_t nparams,
                        MirTy ret, bool leaf, MirRole role) {
    MsSym sym = mir_name(m, name, strlen(name));
    uint32_t found = mir_extern_by_name(m, sym);
    if (found != MIR_NONE) {
        return found;
    }
    MirExtern e = {.name = sym, .params = MS_NEW_N(&m->arena, MirParam, nparams ? nparams : 1),
                   .nparams = nparams, .ret = ret, .leaf = leaf, .role = (uint8_t)role};
    for (uint32_t i = 0; i < nparams; i++) {
        e.params[i] = (MirParam){params[i], MM_BORROW};
    }
    return mir_add_extern(m, &e);
}

static bool pass_name_is(const MirModule *m, MsSym sym, const char *text) {
    MsStr s = ms_name(&m->names, sym);
    return s.len == strlen(text) && memcmp(s.ptr, text, s.len) == 0;
}

static bool pass_plain_in(const MirModule *m, MirTy ty, MirTy *seen, uint32_t *nseen);

static bool pass_plain_all(const MirModule *m, MirTy ty, const MirTy *tys, uint32_t n, MirTy *seen,
                      uint32_t *nseen) {
    seen[(*nseen)++] = ty;
    bool out = true;
    for (uint32_t i = 0; i < n && out; i++) {
        out = pass_plain_in(m, tys[i], seen, nseen);
    }
    (*nseen)--;
    return out;
}

static bool pass_plain_fields(const MirModule *m, MirTy ty, const MirField *fields, uint32_t n,
                         MirTy *seen, uint32_t *nseen) {
    seen[(*nseen)++] = ty;
    bool out = true;
    for (uint32_t i = 0; i < n && out; i++) {
        out = pass_plain_in(m, fields[i].ty, seen, nseen);
    }
    (*nseen)--;
    return out;
}

/* `seen` is the path of types being examined, so a recursive type counts as plain on its second
 * visit; the path holds distinct types, so it never outgrows the type table. */
static bool pass_plain_in(const MirModule *m, MirTy ty, MirTy *seen, uint32_t *nseen) {
    for (uint32_t i = 0; i < *nseen; i++) {
        if (seen[i] == ty) {
            return true;
        }
    }
    const MirTyData *d = mir_ty_data(m, ty);
    switch ((MirTyKind)d->kind) {
    case MK_FN:
    case MK_IFACE:
        return false;
    case MK_OBJ:
        if (!pass_name_is(m, d->name, "Map") && !pass_name_is(m, d->name, "Set") &&
            !pass_name_is(m, d->name, "BigInt")) {
            return false;
        }
        return pass_plain_all(m, ty, d->args, d->nargs, seen, nseen);
    case MK_LIST:
    case MK_OPT:
        return pass_plain_all(m, ty, &d->elem, 1, seen, nseen);
    case MK_TYPE:
        return pass_plain_fields(m, ty, m->type_defs[d->id].fields, m->type_defs[d->id].nfields, seen,
                            nseen);
    case MK_ALT: {
        const MirAltDef *def = &m->alts[d->id];
        bool out = true;
        for (uint32_t c = 0; c < def->ncases && out; c++) {
            out = pass_plain_fields(m, ty, def->cases[c].fields, def->cases[c].nfields, seen, nseen);
        }
        return out;
    }
    case MK_VOID: case MK_BOOL: case MK_INT: case MK_FLOAT: case MK_INT8: case MK_INT16:
    case MK_INT32: case MK_FLOAT32: case MK_UINT8: case MK_UINT16: case MK_UINT32:
    case MK_UINT64: case MK_STR: case MK_BYTES: case MK_PTR:
        return true;
    }
    return true;
}

bool mir_drops_plain_memory(const MirModule *m, MirTy ty) {
    MsArena scratch = {0};
    MirTy *seen = MS_NEW_N(&scratch, MirTy, (size_t)m->types.len + 1);
    uint32_t nseen = 0;
    bool plain = pass_plain_in(m, ty, seen, &nseen);
    ms_arena_free(&scratch);
    return plain;
}

MirValue *mir_args_copy(MirModule *m, const MirValue *args, uint32_t n) {
    MirValue *copy = MS_NEW_N(&m->arena, MirValue, n ? n : 1);
    if (n > 0) {
        memcpy(copy, args, sizeof(MirValue) * n);
    }
    return copy;
}

MirInst mir_inst(MirOp op, MirImm imm, MirValue res, MirLoc loc, MirValue *args,
                 uint32_t n) {
    return (MirInst){.op = (uint8_t)op, .imm = imm, .res = res, .loc = loc, .args = args,
                     .nargs = n};
}

MirImm mir_imm_none(void) { return (MirImm){.tag = MI_NONE}; }
MirImm mir_imm_int(int64_t v) { return (MirImm){.tag = MI_INT, .i = v}; }
MirImm mir_imm_cc(MirCc cc) { return (MirImm){.tag = MI_CC, .a = (uint32_t)cc}; }
MirImm mir_imm_ext(uint32_t ext) { return (MirImm){.tag = MI_EXT, .a = ext}; }

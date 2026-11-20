/* expand_owned: expansion of the ownership shorthands into plain loads, drops and frees. Port of
 * expand_owned.rs.
 *
 * Lowering and the optimizer use ops that bundle a layout decision with a release or a copy:
 * `alt.own`, `alt.unbox`, `alt.release`, `type.release`, `opt.unbox`, `opt.unwrap`. After the last
 * pass that reads them (`unwind`), each becomes `alt.get`/`type.get`/`opt.get` reads, `drop`s of
 * the fields that stay, and one `free` of the heap block when the value lives behind one. */
#include <string.h>

#include "ms/mir_layout.h"
#include "ms/mir_pass.h"

static bool eo_expands(MirOp op) {
    return op == MOP_AltOwn || op == MOP_AltUnbox || op == MOP_AltRelease ||
           op == MOP_TypeRelease || op == MOP_OptUnbox || op == MOP_OptUnwrap;
}

static bool eo_has_shorthand(const MirFunc *f) {
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            if (eo_expands((MirOp)f->blocks[b].insts[i].op)) {
                return true;
            }
        }
    }
    return false;
}

bool mir_expand_owned_needed(const MirModule *m) {
    for (uint32_t i = 0; i < m->nfuncs; i++) {
        if (eo_has_shorthand(&m->funcs[i])) {
            return true;
        }
    }
    return false;
}

typedef struct EoCx {
    MirModule *m;
    MirLayouts *lay;
    MirFunc *f;
    MirBlockData *out; /* the block being rebuilt */
    MirLoc loc;
} EoCx;

static void eo_push(EoCx *cx, MirOp op, const MirValue *args, uint32_t nargs, MirImm imm,
                    MirValue res) {
    MirInst inst = mir_inst(op, imm, res, cx->loc, mir_args_copy(cx->m, args, nargs), nargs);
    MIR_PUSH(cx->m, cx->out->insts, cx->out->ninsts, cx->out->cinsts, MirInst, inst);
}

/* `bit k` of a mask, 0 past the width of the mask. */
static bool eo_bit(uint32_t mask, uint32_t k) { return k < 32 && (mask >> k & 1) != 0; }

/* Drops every payload field of case `c` of `v` that is not in `skip` (`alt.release` passes the
 * moved fields, `alt.unbox` every field but the one it returns), then frees the box. */
static void eo_release_alt_fields(EoCx *cx, MirValue v, uint32_t alt, uint32_t c, uint32_t skip) {
    const MirCaseDef *def = &cx->m->alts[alt].cases[c];
    for (uint32_t k = 0; k < def->nfields; k++) {
        MirTy fty = def->fields[k].ty;
        if (eo_bit(skip, k) || !mir_needs_drop(cx->m, fty)) {
            continue;
        }
        MirValue x = mir_new_value(cx->m, cx->f, fty);
        eo_push(cx, MOP_AltGet, &v, 1, (MirImm){.tag = MI_ALTFIELD, .a = alt, .b = c, .c = k}, x);
        eo_push(cx, MOP_Drop, &x, 1, mir_imm_none(), MIR_NONE);
    }
    /* A case without payload is one shared static block: nothing to free. */
    if (mir_layouts_alt_boxed(cx->lay, alt) && def->nfields > 0) {
        eo_push(cx, MOP_Free, &v, 1, mir_imm_none(), MIR_NONE);
    }
}

/* An indirect type is one pointer to a heap block whose map and set fields sit behind their own
 * nullable boxes: each box is freed, kept field or not, then the block. */
static void eo_release_type(EoCx *cx, MirValue v, uint32_t type, uint32_t mask) {
    const MirTypeDef *def = &cx->m->type_defs[type];
    for (uint32_t k = 0; k < def->nfields; k++) {
        MirTy fty = def->fields[k].ty;
        MirImm field = {.tag = MI_FIELD, .a = type, .b = k};
        if (!eo_bit(mask, k) && mir_needs_drop(cx->m, fty)) {
            MirValue x = mir_new_value(cx->m, cx->f, fty);
            eo_push(cx, MOP_TypeGet, &v, 1, field, x);
            eo_push(cx, MOP_Drop, &x, 1, mir_imm_none(), MIR_NONE);
        }
        if (def->indirect && mir_type_field_boxed(cx->lay, fty)) {
            eo_push(cx, MOP_Free, &v, 1, field, MIR_NONE);
        }
    }
    if (def->indirect) {
        eo_push(cx, MOP_Free, &v, 1, mir_imm_none(), MIR_NONE);
    }
}

/* `alt.own` and `opt.unwrap` read the payload and clone it: a copy of the borrowing variant read
 * as its ordinary alternative, or the owned payload of an optional known to be some. */
static void eo_clone_of(EoCx *cx, MirOp read, MirValue v, MirValue res) {
    MirValue plain = mir_new_value(cx->m, cx->f, mir_value_ty(cx->f, res));
    eo_push(cx, read, &v, 1, mir_imm_none(), plain);
    eo_push(cx, MOP_Clone, &plain, 1, mir_imm_none(), res);
}

static void eo_expand_inst(EoCx *cx, const MirInst *i) {
    cx->loc = i->loc;
    MirValue v = i->args[0];
    switch ((MirOp)i->op) {
    case MOP_AltOwn:
        eo_clone_of(cx, MOP_AltPlain, v, i->res);
        break;
    case MOP_OptUnwrap:
        eo_clone_of(cx, MOP_OptGet, v, i->res);
        break;
    case MOP_OptUnbox: {
        /* The payload leaves the box; the box is freed, the payload lives on. */
        eo_push(cx, MOP_OptGet, &v, 1, mir_imm_none(), i->res);
        MirTy inner = mir_ty_data(cx->m, mir_value_ty(cx->f, v))->elem;
        if (mir_layouts_opt_boxed(cx->lay, inner)) {
            eo_push(cx, MOP_Free, &v, 1, mir_imm_none(), MIR_NONE);
        }
        break;
    }
    case MOP_AltUnbox:
        eo_push(cx, MOP_AltGet, &v, 1, i->imm, i->res);
        eo_release_alt_fields(cx, v, i->imm.a, i->imm.b, i->imm.c < 32 ? 1u << i->imm.c : 0);
        break;
    case MOP_AltRelease:
        eo_release_alt_fields(cx, v, i->imm.a, i->imm.b, i->imm.c);
        break;
    default: /* MOP_TypeRelease: only eo_expands ops reach here */
        eo_release_type(cx, v, i->imm.a, i->imm.b);
        break;
    }
}

static void eo_expand_func(MirModule *m, MirLayouts *lay, MirFunc *f) {
    for (uint32_t b = 0; b < f->nblocks; b++) {
        MirBlockData *block = &f->blocks[b];
        MirBlockData rebuilt = {0};
        EoCx cx = {.m = m, .lay = lay, .f = f, .out = &rebuilt};
        bool any = false;
        for (uint32_t i = 0; i < block->ninsts && !any; i++) {
            any = eo_expands((MirOp)block->insts[i].op);
        }
        if (!any) {
            continue;
        }
        for (uint32_t i = 0; i < block->ninsts; i++) {
            const MirInst *inst = &block->insts[i];
            if (eo_expands((MirOp)inst->op)) {
                eo_expand_inst(&cx, inst);
            } else {
                MIR_PUSH(m, rebuilt.insts, rebuilt.ninsts, rebuilt.cinsts, MirInst, *inst);
            }
        }
        block->insts = rebuilt.insts;
        block->ninsts = rebuilt.ninsts;
        block->cinsts = rebuilt.cinsts;
    }
}

bool mir_expand_owned(MirModule *m) {
    if (!mir_expand_owned_needed(m)) {
        return false;
    }
    MirLayouts lay;
    mir_layouts_init(&lay, m);
    for (uint32_t i = 0; i < m->nfuncs; i++) {
        if (eo_has_shorthand(&m->funcs[i])) {
            eo_expand_func(m, &lay, &m->funcs[i]);
        }
    }
    mir_layouts_free(&lay);
    return true;
}

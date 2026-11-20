/* lower_ops: rewrites the ownership ops a backend would otherwise write itself (`clone`, `drop`,
 * `move.out`, `forget`, and `str.len`, a runtime call that counts scalars) into plain calls and copies, so every emitter prints scalars, memory, calls
 * and data only (proposals/lower-ops-to-runtime-calls.md, stage 1).
 *
 * A value that needs no drop is its own clone, so its uses are renamed to the operand. A string is
 * cloned and freed by the runtime, which tests the tag itself, so no block is split. Any other
 * owned type calls its glue function. `opt.none_owned` becomes `opt.none`. Runs last, after every
 * pass that reads the ownership ops. */
#include <string.h>

#include "ms/mir_layout.h"
#include "ms/mir_pass.h"

typedef struct LoCx {
    MirModule *m;
    const MirGlue *glue;
    MirLayouts layouts;
    uint32_t string_clone, string_free; /* extern ids, MIR_NONE until first used */
    uint32_t obj_clone, obj_drop;
    uint32_t string_length; /* msrt_string_scalar_length */
} LoCx;

typedef enum LoKind { LO_PLAIN, LO_STR, LO_OBJ, LO_GLUE } LoKind;

/* A value that is one pointer to a runtime object: a function (closure), an object other than a
 * map or set, or an optional of one that is null when absent. */
static bool lo_is_obj_like(LoCx *c, MirTy ty) {
    const MirTyData *data = mir_ty_data(c->m, ty);
    switch ((MirTyKind)data->kind) {
    case MK_FN:
        return true;
    case MK_OBJ:
        return !mir_name_is(c->m, data->name, "Map") && !mir_name_is(c->m, data->name, "Set");
    case MK_OPT:
        return mir_opt_is_nullable(&c->layouts, data->elem) && !mir_opt_is_boxed(c->m, data->elem);
    default:
        return false;
    }
}

static LoKind lo_kind(LoCx *c, MirTy ty) {
    if (!mir_needs_drop(c->m, ty)) {
        return LO_PLAIN;
    }
    if (mir_is_str_like(&c->layouts, ty)) {
        return LO_STR;
    }
    return lo_is_obj_like(c, ty) ? LO_OBJ : LO_GLUE;
}

static uint32_t lo_extern(LoCx *c, const char *name, MirTy param, MirTy ret) {
    MirExtern def = {.name = mir_name(c->m, name, strlen(name)), .nparams = 1, .ret = ret,
                     .fresh = ret != MIR_VOID, .leaf = true, .role = MR_NONE};
    def.params = MS_NEW_N(&c->m->arena, MirParam, 1);
    def.params[0] = (MirParam){param, MM_BORROW};
    return mir_add_extern(c->m, &def);
}

static void lo_use(MirValue *use, MirValue from, MirValue to) {
    if (*use == from) {
        *use = to;
    }
}

static void lo_target_uses(MirTarget *t, MirValue from, MirValue to) {
    for (uint32_t i = 0; i < t->nargs; i++) {
        lo_use(&t->args[i], from, to);
    }
}

/* Every use of `from` in `f` becomes `to` (the same type). */
static void lo_replace_uses(MirFunc *f, MirValue from, MirValue to) {
    for (uint32_t b = 0; b < f->nblocks; b++) {
        MirBlockData *blk = &f->blocks[b];
        for (uint32_t k = 0; k < blk->ninsts; k++) {
            for (uint32_t a = 0; a < blk->insts[k].nargs; a++) {
                lo_use(&blk->insts[k].args[a], from, to);
            }
        }
        MirTerm *t = &blk->term;
        lo_use(&t->value, from, to);
        lo_target_uses(&t->a, from, to);
        lo_target_uses(&t->b, from, to);
        for (uint32_t i = 0; i < t->ncases; i++) {
            lo_target_uses(&t->cases[i].target, from, to);
        }
    }
}

static void lo_to_call_rt(MirInst *inst, uint32_t ext) {
    inst->op = MOP_CallRt;
    inst->imm = mir_imm_ext(ext);
}

static void lo_to_call(MirInst *inst, uint32_t func) {
    inst->op = MOP_Call;
    inst->imm = (MirImm){.tag = MI_FUNC, .a = func};
}

/* Rewrites `inst` in place, or returns true when it is to be removed. `f` is the function. */
static bool lo_inst(LoCx *c, MirFunc *f, MirInst *inst) {
    switch ((MirOp)inst->op) {
    case MOP_MoveOut:
        lo_replace_uses(f, inst->res, inst->args[0]);
        return true;
    case MOP_Forget:
        return true;
    case MOP_OptNoneOwned: /* ownership-only distinction (the optimiser reads it); emitters see opt.none */
        inst->op = MOP_OptNone;
        return false;
    case MOP_Clone: {
        const MirTy ty = f->values[inst->args[0]];
        const LoKind kind = lo_kind(c, ty);
        if (kind == LO_PLAIN) {
            lo_replace_uses(f, inst->res, inst->args[0]);
            return true;
        }
        if (kind == LO_STR) {
            if (c->string_clone == MIR_NONE) {
                c->string_clone = lo_extern(c, "msrt_string_clone", MIR_STR, MIR_STR);
            }
            lo_to_call_rt(inst, c->string_clone);
            return false;
        }
        if (kind == LO_OBJ) {
            if (c->obj_clone == MIR_NONE) {
                c->obj_clone = lo_extern(c, "msrt_obj_clone", MIR_PTR, MIR_PTR);
            }
            lo_to_call_rt(inst, c->obj_clone);
            return false;
        }
        const uint32_t glue = mir_glue_find(c->glue, MG_CLONE, ty, 0, 0);
        if (glue != MIR_NONE) {
            lo_to_call(inst, glue);
        }
        return false;
    }
    case MOP_Drop: {
        const MirTy ty = f->values[inst->args[0]];
        const LoKind kind = lo_kind(c, ty);
        if (kind == LO_PLAIN) {
            return true;
        }
        if (kind == LO_STR) {
            if (c->string_free == MIR_NONE) {
                c->string_free = lo_extern(c, "msrt_string_free", MIR_STR, MIR_VOID);
            }
            lo_to_call_rt(inst, c->string_free);
            return false;
        }
        if (kind == LO_OBJ) {
            if (c->obj_drop == MIR_NONE) {
                c->obj_drop = lo_extern(c, "msrt_obj_drop", MIR_PTR, MIR_VOID);
            }
            lo_to_call_rt(inst, c->obj_drop);
            return false;
        }
        const uint32_t glue = mir_glue_find(c->glue, MG_DROP, ty, 0, 0);
        if (glue != MIR_NONE) {
            lo_to_call(inst, glue);
        }
        return false;
    }
    case MOP_StrLen:
        if (c->string_length == MIR_NONE) {
            c->string_length = lo_extern(c, "msrt_string_scalar_length", MIR_STR, MIR_INT);
        }
        lo_to_call_rt(inst, c->string_length);
        return false;
    default:
        return false;
    }
}

/* `drop.if flag v` ends its block with a branch on `flag` to a block that drops `v` and on to a
 * block holding the rest, so the drop that remains is a plain `drop`. Blocks the split makes are
 * visited too, for a second `drop.if`. */
static void lo_split_drop_ifs(MirModule *m, MirFunc *f) {
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t k = 0; k < f->blocks[b].ninsts; k++) {
            if (f->blocks[b].insts[k].op != MOP_DropIf) {
                continue;
            }
            const MirInst held = f->blocks[b].insts[k];
            const uint32_t nrest = f->blocks[b].ninsts - (k + 1);
            MirInst *rest = MS_NEW_N(&m->arena, MirInst, nrest ? nrest : 1);
            if (nrest > 0) {
                memcpy(rest, &f->blocks[b].insts[k + 1], sizeof(MirInst) * nrest);
            }
            const MirTerm term = f->blocks[b].term;
            const MirLoc term_loc = f->blocks[b].term_loc;
            f->blocks[b].ninsts = k;
            const MirBlock drop = mir_new_block(m, f);
            const MirBlock next = mir_new_block(m, f);
            const MirValue victim = held.args[1];
            MirInst *only = MS_NEW_N(&m->arena, MirInst, 1);
            *only = mir_inst(MOP_Drop, mir_imm_none(), MIR_NONE, held.loc,
                             mir_args_copy(m, &victim, 1), 1);
            f->blocks[drop].insts = only;
            f->blocks[drop].ninsts = f->blocks[drop].cinsts = 1;
            f->blocks[drop].term = (MirTerm){.kind = MT_BR, .value = MIR_NONE, .a = {.block = next}};
            f->blocks[drop].term_loc = held.loc;
            f->blocks[next].insts = rest;
            f->blocks[next].ninsts = f->blocks[next].cinsts = nrest;
            f->blocks[next].term = term;
            f->blocks[next].term_loc = term_loc;
            f->blocks[b].term = (MirTerm){.kind = MT_CONDBR, .value = held.args[0],
                                          .a = {.block = drop}, .b = {.block = next}};
            f->blocks[b].term_loc = held.loc;
            break;
        }
    }
}

static void lo_function(LoCx *c, MirFunc *f) {
    lo_split_drop_ifs(c->m, f);
    for (uint32_t b = 0; b < f->nblocks; b++) {
        MirBlockData *blk = &f->blocks[b];
        uint32_t kept = 0;
        for (uint32_t k = 0; k < blk->ninsts; k++) {
            if (!lo_inst(c, f, &blk->insts[k])) {
                blk->insts[kept++] = blk->insts[k];
            }
        }
        blk->ninsts = kept;
    }
}

void mir_lower_ops(MirModule *m, const MirGlue *glue) {
    LoCx c = {.m = m, .glue = glue, .string_clone = MIR_NONE, .string_free = MIR_NONE,
            .obj_clone = MIR_NONE, .obj_drop = MIR_NONE, .string_length = MIR_NONE};
    mir_layouts_init(&c.layouts, m);
    for (uint32_t i = 0; i < m->nfuncs; i++) {
        lo_function(&c, &m->funcs[i]);
    }
    mir_layouts_free(&c.layouts);
}

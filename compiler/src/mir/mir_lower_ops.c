/* lower_ops: rewrites the ownership ops a backend would otherwise write itself (`clone`, `drop`,
 * `move.out`, `forget`, and `str.len`, a runtime call that counts scalars) into plain calls and copies, so every emitter prints scalars, memory, calls
 * and data only (proposals/lower-ops-to-runtime-calls.md, stage 1).
 *
 * A value that needs no drop is its own clone, so its uses are renamed to the operand. A string is
 * cloned and freed by the runtime, which tests the tag itself, so no block is split. Any other
 * owned type calls its glue function. `opt.none_owned` becomes `opt.none`. Runs last, after every
 * pass that reads the ownership ops. */
#include <string.h>

#include "ms/mir_builder.h"
#include "ms/mir_layout.h"
#include "ms/mir_analysis.h"
#include "ms/mir_pass.h"

typedef struct LoCx {
    MirModule *m;
    const MirGlue *glue;
    MirLayouts layouts;
    uint32_t string_clone, string_free; /* extern ids, MIR_NONE until first used */
    uint32_t obj_clone, obj_drop;
    uint32_t cleanup_push, cleanup_run, fault_string, string_eq;
    uint32_t *thunks; /* by function: the cleanup thunk that calls it, MIR_NONE until made */
    uint32_t nthunks;
    uint32_t string_length; /* msrt_string_scalar_length */
    MirTy *release_tys; /* the list types `list.release` is applied to, and the function made for each */
    uint32_t *release_fns;
    uint32_t nreleases;
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
        return data->obj_class != MIR_OBJ_COLLECTION;
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

/* `list.release l, from` calls the function made for the type of `l`. */
static void lo_list_release(const LoCx *c, const MirFunc *f, MirInst *inst) {
    const MirTy ty = f->values[inst->args[0]];
    for (uint32_t i = 0; i < c->nreleases; i++) {
        if (c->release_tys[i] == ty) {
            lo_to_call(inst, c->release_fns[i]);
            return;
        }
    }
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
    case MOP_ListRelease:
        lo_list_release(c, f, inst);
        return false;
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

/* A runtime function of the given scalar parameter types, interned once. */
static uint32_t lo_rt(LoCx *c, uint32_t *cache, const char *name, const MirTy *params, uint32_t n,
                      MirTy ret) {
    if (*cache != MIR_NONE) {
        return *cache;
    }
    MirExtern def = {.name = mir_name(c->m, name, strlen(name)), .nparams = n, .ret = ret,
                     .fresh = ret != MIR_VOID, .leaf = true, .role = MR_NONE};
    def.params = MS_NEW_N(&c->m->arena, MirParam, n);
    for (uint32_t k = 0; k < n; k++) {
        def.params[k] = (MirParam){params[k], MM_BORROW};
    }
    *cache = mir_extern_intern(c->m, &def);
    return *cache;
}

/* `msrt_cleanup_push(thunk, slot)`. The runtime keeps `slot` until the cleanup is discarded or run,
 * which another block may do, so the slot is not a one-block temporary (`mir_confined_slots`). */
static uint32_t lo_cleanup_push_rt(LoCx *c) {
    const MirTy ptr_pair[2] = {MIR_PTR, MIR_PTR};
    const uint32_t push = lo_rt(c, &c->cleanup_push, "msrt_cleanup_push", ptr_pair, 2, MIR_INT);
    c->m->externs[push].retains = true;
    return push;
}

/* The function `cleanup.thunk` the runtime calls with the address of a spilled value: it loads
 * the value and calls closer `closer`. */
static uint32_t lo_cleanup_thunk(LoCx *c, uint32_t closer) {
    if (c->thunks[closer] != MIR_NONE) {
        return c->thunks[closer];
    }
    const MirTy ty = c->m->funcs[closer].params[0].ty;
    const MirParam param = {MIR_PTR, MM_BORROW};
    MirBuilder b;
    const MsStr thunk_name = ms_arena_fmt(&c->m->arena, "cleanup.thunk.%u", closer);
    mir_b_init(&b, c->m, mir_name(c->m, thunk_name.ptr, thunk_name.len), &param, 1, MIR_VOID);
    mir_b_func(&b)->linkage = ML_INTERNAL;
    MirValue p = 0;
    mir_b_params(&b, &p, 1);
    MirValue value = mir_b_emit(&b, MOP_Load, &p, 1, (MirImm){.tag = MI_TY, .a = ty}, ty);
    (void)mir_b_call(&b, closer, &value, 1);
    mir_b_ret(&b, mir_b_unit(&b));
    uint32_t id = 0;
    if (!mir_b_finish(&b, &id)) {
        ms_oom();
    }
    c->thunks[closer] = id;
    return id;
}

/* The thunk of every closer a `cleanup.push` registers, made before any function is rewritten
 * because adding one may move the function table. */
static void lo_make_thunks(LoCx *c) {
    for (uint32_t i = 0; i < c->nthunks; i++) {
        const MirFunc *f = &c->m->funcs[i];
        for (uint32_t b = 0; b < f->nblocks; b++) {
            for (uint32_t k = 0; k < f->blocks[b].ninsts; k++) {
                const MirInst *inst = &f->blocks[b].insts[k];
                if (inst->op == MOP_CleanupPush) {
                    (void)lo_cleanup_thunk(c, inst->imm.a);
                    f = &c->m->funcs[i];
                }
            }
        }
    }
}

/* The function behind `list.release` of every list type that has one, made before any function is rewritten for the
 * same reason as the thunks. */
static void lo_make_releases(LoCx *c) {
    const uint32_t count = c->nthunks;
    uint32_t total = 0;
    for (uint32_t i = 0; i < count; i++) {
        for (uint32_t b = 0; b < c->m->funcs[i].nblocks; b++) {
            for (uint32_t k = 0; k < c->m->funcs[i].blocks[b].ninsts; k++) {
                total += c->m->funcs[i].blocks[b].insts[k].op == MOP_ListRelease;
            }
        }
    }
    c->release_tys = MS_NEW_N(&c->m->arena, MirTy, total ? total : 1);
    c->release_fns = MS_NEW_N(&c->m->arena, uint32_t, total ? total : 1);
    for (uint32_t i = 0; i < count; i++) {
        for (uint32_t b = 0; b < c->m->funcs[i].nblocks; b++) {
            for (uint32_t k = 0; k < c->m->funcs[i].blocks[b].ninsts; k++) {
                const MirInst *inst = &c->m->funcs[i].blocks[b].insts[k];
                if (inst->op != MOP_ListRelease) {
                    continue;
                }
                const MirTy ty = c->m->funcs[i].values[inst->args[0]];
                bool known = false;
                for (uint32_t r = 0; r < c->nreleases && !known; r++) {
                    known = c->release_tys[r] == ty;
                }
                if (!known) {
                    const uint32_t fn = mir_glue_list_release(c->m, ty);
                    c->release_tys[c->nreleases] = ty;
                    c->release_fns[c->nreleases++] = fn;
                }
            }
        }
    }
}

/* `cleanup.push v` becomes a spill of `v` to a frame slot and `msrt_cleanup_push(thunk, slot)`;
 * `cleanup.run h` becomes `msrt_cleanup_run(h)`. */
static void lo_expand_cleanups(LoCx *c, MirFunc *f) {
    for (uint32_t b = 0; b < f->nblocks; b++) {
        uint32_t pushes = 0;
        for (uint32_t k = 0; k < f->blocks[b].ninsts; k++) {
            pushes += f->blocks[b].insts[k].op == MOP_CleanupPush;
        }
        for (uint32_t k = 0; k < f->blocks[b].ninsts; k++) {
            MirInst *inst = &f->blocks[b].insts[k];
            if (inst->op == MOP_CleanupRun) {
                const MirTy one[1] = {MIR_INT};
                lo_to_call_rt(inst, lo_rt(c, &c->cleanup_run, "msrt_cleanup_run", one, 1, MIR_VOID));
            }
        }
        if (pushes == 0) {
            continue;
        }
        const uint32_t before = f->blocks[b].ninsts;
        MirInst *out = MS_NEW_N(&c->m->arena, MirInst, before + 3 * pushes);
        uint32_t n = 0;
        for (uint32_t k = 0; k < before; k++) {
            const MirInst held = f->blocks[b].insts[k];
            if (held.op != MOP_CleanupPush) {
                out[n++] = held;
                continue;
            }
            const MirTy ty = f->values[held.args[0]];
            const MirValue slot = mir_new_value(c->m, f, MIR_PTR);
            const MirValue addr = mir_new_value(c->m, f, MIR_PTR);
            MirValue stored[2] = {slot, held.args[0]};
            MirValue pushed[2] = {addr, slot};
            const MirImm thunk = {.tag = MI_FUNC, .a = c->thunks[held.imm.a]};
            out[n++] = mir_inst(MOP_Slot, (MirImm){.tag = MI_TY, .a = ty}, slot, held.loc, NULL, 0);
            out[n++] = mir_inst(MOP_Store, mir_imm_none(), MIR_NONE, held.loc,
                                mir_args_copy(c->m, stored, 2), 2);
            out[n++] = mir_inst(MOP_FuncAddr, thunk, addr, held.loc, NULL, 0);
            out[n++] = mir_inst(MOP_CallRt, mir_imm_ext(lo_cleanup_push_rt(c)), held.res, held.loc,
                                mir_args_copy(c->m, pushed, 2), 2);
        }
        f->blocks[b].insts = out;
        f->blocks[b].ninsts = f->blocks[b].cinsts = n;
    }
}

/* A fault with a message ends in `msrt_fault_string(message)`, which does not return. */
static void lo_fault_messages(LoCx *c, MirFunc *f) {
    for (uint32_t b = 0; b < f->nblocks; b++) {
        if (f->blocks[b].term.kind != MT_FAULT || f->blocks[b].term.fault != MF_MESSAGE) {
            continue;
        }
        const MirLoc loc = f->blocks[b].term_loc;
        const MirValue text = mir_new_value(c->m, f, MIR_STR);
        const MirTy one[1] = {MIR_STR};
        MirValue arg = text;
        MirBlockData *blk = &f->blocks[b];
        MirInst *out = MS_NEW_N(&c->m->arena, MirInst, blk->ninsts + 2);
        if (blk->ninsts > 0) {
            memcpy(out, blk->insts, sizeof(MirInst) * blk->ninsts);
        }
        const MirImm lit = {.tag = MI_STR, .a = blk->term.fault_str};
        out[blk->ninsts] = mir_inst(MOP_StrLit, lit, text, loc, NULL, 0);
        out[blk->ninsts + 1] = mir_inst(
            MOP_CallRt, mir_imm_ext(lo_rt(c, &c->fault_string, "msrt_fault_string", one, 1, MIR_VOID)),
            MIR_NONE, loc, mir_args_copy(c->m, &arg, 1), 1);
        blk->insts = out;
        blk->ninsts = blk->cinsts = blk->ninsts + 2;
        blk->term = (MirTerm){.kind = MT_UNREACHABLE, .value = MIR_NONE};
    }
}

/* `list.set.u` and `list.droplast` drop the element they overwrite or remove. The emitters only
 * write memory, so the old element is read and dropped first and the op becomes its plain form
 * (`list.fill.u`, `list.droplast 1`). */
static void lo_list_drops(LoCx *c, MirFunc *f) {
    for (uint32_t b = 0; b < f->nblocks; b++) {
        uint32_t extra = 0;
        for (uint32_t k = 0; k < f->blocks[b].ninsts; k++) {
            const MirInst *inst = &f->blocks[b].insts[k];
            extra += (inst->op == MOP_ListSetU || inst->op == MOP_ListDropLast) ? 5 : 0;
        }
        if (extra == 0) {
            continue;
        }
        const uint32_t before = f->blocks[b].ninsts;
        MirInst *out = MS_NEW_N(&c->m->arena, MirInst, before + extra);
        uint32_t n = 0;
        for (uint32_t k = 0; k < before; k++) {
            MirInst inst = f->blocks[b].insts[k];
            const bool set = inst.op == MOP_ListSetU;
            const bool last = inst.op == MOP_ListDropLast && !(inst.imm.tag == MI_INT && inst.imm.i == 1);
            const MirTy list = (set || last) ? f->values[inst.args[0]] : MIR_NONE;
            const MirTy elem = (set || last) ? mir_ty_data(c->m, list)->elem : MIR_NONE;
            if ((!set && !last) || !mir_needs_drop(c->m, elem)) {
                if (set) {
                    inst.op = MOP_ListFillU;
                }
                out[n++] = inst;
                continue;
            }
            MirValue at = inst.args[1];
            if (last) {
                const MirValue len = mir_new_value(c->m, f, MIR_INT);
                const MirValue one = mir_new_value(c->m, f, MIR_INT);
                at = mir_new_value(c->m, f, MIR_INT);
                MirValue arg = inst.args[0];
                MirValue pair[2] = {len, one};
                out[n++] = mir_inst(MOP_ListLen, mir_imm_none(), len, inst.loc, mir_args_copy(c->m, &arg, 1), 1);
                out[n++] = mir_inst(MOP_IConst, (MirImm){.tag = MI_INT, .i = 1}, one, inst.loc, NULL, 0);
                out[n++] = mir_inst(MOP_ISub, mir_imm_none(), at, inst.loc, mir_args_copy(c->m, pair, 2), 2);
            }
            const MirValue old = mir_new_value(c->m, f, elem);
            MirValue get[2] = {inst.args[0], at};
            out[n++] = mir_inst(MOP_ListGetU, mir_imm_none(), old, inst.loc, mir_args_copy(c->m, get, 2), 2);
            MirValue victim = old;
            out[n++] = mir_inst(MOP_Drop, mir_imm_none(), MIR_NONE, inst.loc, mir_args_copy(c->m, &victim, 1), 1);
            if (set) {
                inst.op = MOP_ListFillU;
            } else {
                inst.imm = (MirImm){.tag = MI_INT, .i = 1};
            }
            out[n++] = inst;
        }
        f->blocks[b].insts = out;
        f->blocks[b].ninsts = f->blocks[b].cinsts = n;
    }
}

/* `str.eq_lit s` with literal L becomes `msrt_string_eq(s, str L)`. */
static void lo_str_eq_lits(LoCx *c, MirFunc *f) {
    static const MirTy two_strs[2] = {MIR_STR, MIR_STR};
    for (uint32_t b = 0; b < f->nblocks; b++) {
        uint32_t lits = 0;
        for (uint32_t k = 0; k < f->blocks[b].ninsts; k++) {
            lits += f->blocks[b].insts[k].op == MOP_StrEqLit;
        }
        if (lits == 0) {
            continue;
        }
        MirInst *out = MS_NEW_N(&c->m->arena, MirInst, f->blocks[b].ninsts + lits);
        uint32_t n = 0;
        for (uint32_t k = 0; k < f->blocks[b].ninsts; k++) {
            const MirInst held = f->blocks[b].insts[k];
            if (held.op != MOP_StrEqLit) {
                out[n++] = held;
                continue;
            }
            const MirValue lit = mir_new_value(c->m, f, MIR_STR);
            MirValue args[2] = {held.args[0], lit};
            out[n++] = mir_inst(MOP_StrLit, held.imm, lit, held.loc, NULL, 0);
            out[n++] = mir_inst(MOP_CallRt,
                                mir_imm_ext(lo_rt(c, &c->string_eq, "msrt_string_eq", two_strs, 2, MIR_BOOL)),
                                held.res, held.loc, mir_args_copy(c->m, args, 2), 2);
        }
        f->blocks[b].insts = out;
        f->blocks[b].ninsts = f->blocks[b].cinsts = n;
    }
}

/* A clone of bytes, or of a list whose elements own nothing, is one block copy by the runtime.
 * A list's copy needs the element descriptor, which this pass makes a value of its own. */
static bool lo_is_block_clone(LoCx *c, const MirFunc *f, const MirInst *inst) {
    if (inst->op != MOP_Clone || inst->nargs == 0) {
        return false;
    }
    const MirTyData *d = mir_ty_data(c->m, f->values[inst->args[0]]);
    return d->kind == MK_BYTES || (d->kind == MK_LIST && !mir_needs_drop(c->m, d->elem));
}

static uint32_t lo_block_copy_extern(LoCx *c, MirTy list, bool bytes) {
    MirExtern def = {.name = mir_name(c->m, bytes ? "msrt_bytes_copy" : "msrt_list_copy", bytes ? 15 : 14),
                     .nparams = bytes ? 1 : 2, .ret = list, .fresh = true, .leaf = true, .role = MR_NONE};
    def.params = MS_NEW_N(&c->m->arena, MirParam, def.nparams);
    def.params[0] = (MirParam){list, MM_BORROW};
    if (!bytes) {
        def.params[1] = (MirParam){MIR_PTR, MM_BORROW};
    }
    return mir_extern_intern(c->m, &def);
}

static void lo_block_clones(LoCx *c, MirFunc *f) {
    for (uint32_t b = 0; b < f->nblocks; b++) {
        uint32_t extra = 0;
        for (uint32_t k = 0; k < f->blocks[b].ninsts; k++) {
            extra += lo_is_block_clone(c, f, &f->blocks[b].insts[k]) ? 1 : 0;
        }
        if (extra == 0) {
            continue;
        }
        MirInst *out = MS_NEW_N(&c->m->arena, MirInst, f->blocks[b].ninsts + extra);
        uint32_t n = 0;
        for (uint32_t k = 0; k < f->blocks[b].ninsts; k++) {
            MirInst inst = f->blocks[b].insts[k];
            if (!lo_is_block_clone(c, f, &inst)) {
                out[n++] = inst;
                continue;
            }
            const MirTy list = f->values[inst.args[0]];
            const MirTyData *d = mir_ty_data(c->m, list);
            MirValue args[2] = {inst.args[0], MIR_NONE};
            uint32_t nargs = 1;
            if (d->kind == MK_LIST) {
                args[1] = mir_new_value(c->m, f, MIR_PTR);
                out[n++] = mir_inst(MOP_TypeDesc, (MirImm){.tag = MI_TY, .a = d->elem}, args[1], inst.loc, NULL, 0);
                nargs = 2;
            }
            inst.op = MOP_CallRt;
            inst.imm = mir_imm_ext(lo_block_copy_extern(c, list, d->kind == MK_BYTES));
            inst.args = mir_args_copy(c->m, args, nargs);
            inst.nargs = nargs;
            out[n++] = inst;
        }
        f->blocks[b].insts = out;
        f->blocks[b].ninsts = f->blocks[b].cinsts = n;
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

/* Whether `inst` is a `type.set` of a field that owns something, on a record behind a pointer. */
static bool lo_is_dropping_set(const LoCx *c, const MirFunc *f, const MirInst *inst) {
    if (inst->op != MOP_TypeSet) {
        return false;
    }
    const MirTyData *data = mir_ty_data(c->m, f->values[inst->args[0]]);
    return data->kind == MK_TYPE && c->m->type_defs[data->id].indirect &&
           mir_needs_drop(c->m, c->m->type_defs[data->id].fields[inst->imm.b].ty);
}

/* `type.set` of an owning field of a record behind a pointer drops the old value first; the emitters
 * only write the field (`type.fill`), so the drop becomes `type.get` and `drop` before it. */
static void lo_expand_sets(LoCx *c, MirFunc *f) {
    for (uint32_t b = 0; b < f->nblocks; b++) {
        MirBlockData *blk = &f->blocks[b];
        uint32_t sets = 0;
        for (uint32_t k = 0; k < blk->ninsts; k++) {
            sets += lo_is_dropping_set(c, f, &blk->insts[k]);
        }
        if (sets == 0) {
            continue;
        }
        MirInst *out = MS_NEW_N(&c->m->arena, MirInst, blk->ninsts + 2 * sets);
        uint32_t n = 0;
        for (uint32_t k = 0; k < blk->ninsts; k++) {
            MirInst held = blk->insts[k];
            if (lo_is_dropping_set(c, f, &held)) {
                const MirTyData *data = mir_ty_data(c->m, f->values[held.args[0]]);
                const MirValue old = mir_new_value(c->m, f, c->m->type_defs[data->id].fields[held.imm.b].ty);
                out[n++] = mir_inst(MOP_TypeGet, held.imm, old, held.loc, mir_args_copy(c->m, held.args, 1), 1);
                out[n++] = mir_inst(MOP_Drop, mir_imm_none(), MIR_NONE, held.loc, mir_args_copy(c->m, &old, 1), 1);
                held.op = MOP_TypeFill;
            }
            out[n++] = held;
        }
        blk->insts = out;
        blk->ninsts = blk->cinsts = n;
    }
}

static void lo_function(LoCx *c, MirFunc *f) {
    lo_list_drops(c, f);
    lo_str_eq_lits(c, f);
    lo_block_clones(c, f);
    lo_expand_sets(c, f);
    lo_split_drop_ifs(c->m, f);
    lo_expand_cleanups(c, f);
    lo_fault_messages(c, f);
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
            .obj_clone = MIR_NONE, .obj_drop = MIR_NONE, .string_length = MIR_NONE,
            .cleanup_push = MIR_NONE,
            .cleanup_run = MIR_NONE, .fault_string = MIR_NONE, .string_eq = MIR_NONE, .nthunks = m->nfuncs};
    c.thunks = MS_NEW_N(&m->arena, uint32_t, m->nfuncs ? m->nfuncs : 1);
    for (uint32_t i = 0; i < m->nfuncs; i++) {
        c.thunks[i] = MIR_NONE;
    }
    lo_make_thunks(&c);
    lo_make_releases(&c);
    mir_layouts_init(&c.layouts, m);
    for (uint32_t i = 0; i < c.nthunks; i++) {
        lo_function(&c, &m->funcs[i]);
    }
    for (uint32_t i = 0; i < c.nreleases; i++) {
        lo_function(&c, &m->funcs[c.release_fns[i]]);
    }
    mir_layouts_free(&c.layouts);
}

/* unwind: the cleanup functions the pass registers, and the passes that prepare a function for
 * them (holes, shielded closes). Port of the first half of unwind.rs. */
#include "mir/mir_unwind.h"

static MirImm uw_imm_func(uint32_t g) { return (MirImm){.tag = MI_FUNC, .a = g}; }
static MirImm uw_imm_ty(MirTy ty) { return (MirImm){.tag = MI_TY, .a = ty}; }

static uint32_t uw_gate(UwCx *cx) {
    const MirExtern e = {.name = mir_name(cx->m, "msrt_unwind_drops", 17), .ret = MIR_BOOL,
                         .leaf = true, .role = MR_NONE};
    return mir_extern_intern(cx->m, &e);
}

/* Starts a cleanup function: internal, one parameter, and `unwind_only` when it runs only while
 * unwinding. */
static void uw_start(UwCx *cx, MirBuilder *b, const char *name, MirTy ty, MirMode mode,
                     bool unwind_only) {
    const MirParam p = {ty, (uint8_t)mode};
    mir_b_init(b, cx->m, mir_name(cx->m, name, strlen(name)), &p, 1, MIR_VOID);
    mir_b_func(b)->linkage = ML_INTERNAL;
    mir_b_func(b)->unwind_only = unwind_only;
}

static void uw_ret_unit(MirBuilder *b) {
    mir_b_ret(b, mir_b_unit(b));
}

/* Adds the function built; building these bodies cannot fail (they use no variables). */
static uint32_t uw_finish(MirBuilder *b) {
    uint32_t id = 0;
    if (!mir_b_finish(b, &id)) {
        ms_oom();
    }
    return id;
}

static MirValue uw_param0(const MirBuilder *b) {
    MirValue v = 0;
    mir_b_params(b, &v, 1);
    return v;
}

/* The function that frees the buffer of a raw slot copy while an unwind runs. */
uint32_t uw_raw_closer(UwCx *cx, MirTy ty) {
    uint64_t id = 0;
    if (uh_get(&cx->raw_closers, ty, &id)) {
        return (uint32_t)id;
    }
    MirParam fp = {ty, MM_MOVE};
    MirExtern e = {.name = mir_name(cx->m, "msrt_list_free_raw", 18), .params = &fp, .nparams = 1,
                   .ret = MIR_VOID, .leaf = true, .role = MR_RAW_FREE};
    const uint32_t free_fn = mir_extern_intern(cx->m, &e);
    MirBuilder b;
    uw_start(cx, &b, "unwind.free_raw", ty, MM_MOVE, true);
    MirValue v = uw_param0(&b);
    (void)mir_b_call_rt(&b, free_fn, &v, 1);
    uw_ret_unit(&b);
    id = uw_finish(&b);
    (void)uh_put(&cx->pass, &cx->raw_closers, ty, id);
    return (uint32_t)id;
}

/* The function that frees the box of an interface value while an unwind runs, leaving the payload
 * to the method that took it. */
uint32_t uw_box_closer(UwCx *cx, MirTy ty) {
    uint64_t id = 0;
    if (uh_get(&cx->box_closers, ty, &id)) {
        return (uint32_t)id;
    }
    const uint32_t gate = uw_gate(cx);
    MirBuilder b;
    uw_start(cx, &b, "unwind.free_box", ty, MM_MOVE, true);
    MirValue v = uw_param0(&b);
    const MirBlock run = mir_b_new_block(&b), skip = mir_b_new_block(&b);
    MirValue on = mir_b_call_rt(&b, gate, NULL, 0);
    mir_b_br_if(&b, on, run, NULL, 0, skip, NULL, 0);
    mir_b_switch_to(&b, run);
    MirValue data = mir_b_emit(&b, MOP_IfaceData, &v, 1, mir_imm_none(), MIR_PTR);
    (void)mir_b_emit(&b, MOP_Free, &data, 1, mir_imm_none(), MIR_NONE);
    (void)mir_b_emit(&b, MOP_Forget, &v, 1, mir_imm_none(), MIR_NONE);
    uw_ret_unit(&b);
    mir_b_switch_to(&b, skip);
    (void)mir_b_emit(&b, MOP_Forget, &v, 1, mir_imm_none(), MIR_NONE);
    uw_ret_unit(&b);
    id = uw_finish(&b);
    (void)uh_put(&cx->pass, &cx->box_closers, ty, id);
    return (uint32_t)id;
}

/* The function that drops every field of its argument but `field` when a cancellation is
 * unwinding: the field was moved out, and its new owner drops it. */
uint32_t uw_partial_closer(UwCx *cx, MirTy ty, uint32_t r, uint32_t field) {
    const uint64_t key = (uint64_t)ty << 32 | field;
    uint64_t id = 0;
    if (uh_get(&cx->partial_closers, key, &id)) {
        return (uint32_t)id;
    }
    const uint32_t gate = uw_gate(cx);
    MirBuilder b;
    uw_start(cx, &b, "unwind.drop_rest", ty, MM_MOVE, true);
    MirValue v = uw_param0(&b);
    const MirBlock run = mir_b_new_block(&b), skip = mir_b_new_block(&b);
    MirValue on = mir_b_call_rt(&b, gate, NULL, 0);
    mir_b_br_if(&b, on, run, NULL, 0, skip, NULL, 0);
    mir_b_switch_to(&b, run);
    (void)mir_b_emit(&b, MOP_TypeRelease, &v, 1,
                     (MirImm){.tag = MI_TYPEMASK, .a = r, .b = 1u << field}, MIR_NONE);
    uw_ret_unit(&b);
    mir_b_switch_to(&b, skip);
    (void)mir_b_emit(&b, MOP_Forget, &v, 1, mir_imm_none(), MIR_NONE);
    uw_ret_unit(&b);
    id = uw_finish(&b);
    (void)uh_put(&cx->pass, &cx->partial_closers, key, id);
    return (uint32_t)id;
}

/* `drop.if gate, v`, then return. */
static void uw_gated_drop(UwCx *cx, MirBuilder *b, MirValue v) {
    MirValue on = mir_b_call_rt(b, uw_gate(cx), NULL, 0);
    MirValue args[2] = {on, v};
    (void)mir_b_emit(b, MOP_DropIf, args, 2, mir_imm_none(), MIR_NONE);
    uw_ret_unit(b);
}

/* The function that drops its argument when a cancellation is unwinding. */
uint32_t uw_closer(UwCx *cx, MirTy ty) {
    uint64_t id = 0;
    if (uh_get(&cx->closers, ty, &id)) {
        return (uint32_t)id;
    }
    MirBuilder b;
    uw_start(cx, &b, "unwind.drop", ty, MM_MOVE, true);
    uw_gated_drop(cx, &b, uw_param0(&b));
    id = uw_finish(&b);
    (void)uh_put(&cx->pass, &cx->closers, ty, id);
    return (uint32_t)id;
}

/* The function that drops what the slot at its argument holds when a cancellation or fault is
 * unwinding. */
uint32_t uw_slot_dropper(UwCx *cx, MirTy ty) {
    uint64_t id = 0;
    if (uh_get(&cx->slot_droppers, ty, &id)) {
        return (uint32_t)id;
    }
    MirBuilder b;
    uw_start(cx, &b, "unwind.drop_slot", MIR_PTR, MM_BORROW, false);
    MirValue p = uw_param0(&b);
    MirValue on = mir_b_call_rt(&b, uw_gate(cx), NULL, 0);
    MirValue held = mir_b_emit(&b, MOP_Take, &p, 1, uw_imm_ty(ty), ty);
    MirValue args[2] = {on, held};
    (void)mir_b_emit(&b, MOP_DropIf, args, 2, mir_imm_none(), MIR_NONE);
    uw_ret_unit(&b);
    id = uw_finish(&b);
    (void)uh_put(&cx->pass, &cx->slot_droppers, ty, id);
    return (uint32_t)id;
}

/* [`with_closer`] for a slot-held value: runs the thunk, then drops what the slot still holds.
 * The thunk closes the value in place, so it is still there for this drop. */
static uint32_t uw_slot_with_closer(UwCx *cx, uint32_t close, MirTy ty) {
    const uint32_t dropper = uw_slot_dropper(cx, ty);
    UwHash memo = {0};
    MsArena tmp = {0};
    const bool covers = !uw_takes_from_slot_in(cx->m, close, &memo, &tmp);
    ms_arena_free(&tmp);
    const uint32_t gate = uw_gate(cx);
    MirBuilder b;
    uw_start(cx, &b, "unwind.close_drop_slot", MIR_PTR, MM_BORROW, false);
    MirValue p = uw_param0(&b);
    /* A fault inside the close ends this cleanup, so the slot is registered for its duration
     * unless the close takes parts out of it. */
    MirValue covering = MIR_NONE;
    if (covers) {
        covering = mir_b_emit(&b, MOP_CleanupPush, &p, 1, uw_imm_func(dropper), MIR_INT);
    }
    (void)mir_b_call(&b, close, &p, 1);
    if (covers) {
        (void)mir_b_call_rt(&b, cx->discard, &covering, 1);
    }
    MirValue on = mir_b_call_rt(&b, gate, NULL, 0);
    MirValue held = mir_b_emit(&b, MOP_Take, &p, 1, uw_imm_ty(ty), ty);
    MirValue args[2] = {on, held};
    (void)mir_b_emit(&b, MOP_DropIf, args, 2, mir_imm_none(), MIR_NONE);
    uw_ret_unit(&b);
    const uint32_t id = uw_finish(&b);
    (void)uh_put(&cx->pass, &cx->with_closers, close, id);
    return id;
}

/* The cleanup that runs `close` on a scope-closed value and then drops it while a cancellation
 * unwinds. A cancelled task never reaches the drop after the block, and the per-call drops leave
 * this value to its close so that nothing closes a freed value. */
static bool uw_with_closer(UwCx *cx, uint32_t close, uint32_t *out) {
    uint64_t id = 0;
    if (uh_get(&cx->with_closers, close, &id)) {
        *out = (uint32_t)id;
        return true;
    }
    if (close >= cx->m->nfuncs || cx->m->funcs[close].nparams != 1) {
        return false;
    }
    const MirParam param = cx->m->funcs[close].params[0];
    MirTy slot_ty = 0;
    if (uw_slot_close_value(cx->m, close, &slot_ty)) {
        *out = uw_slot_with_closer(cx, close, slot_ty);
        return true;
    }
    /* Closing that moves the value, or yields one that needs a drop, leaves nothing to add. */
    if (param.mode == MM_MOVE || cx->m->funcs[close].ret != MIR_VOID ||
        !mir_needs_drop(cx->m, param.ty)) {
        return false;
    }
    const uint32_t gate = uw_gate(cx);
    MirBuilder b;
    uw_start(cx, &b, "unwind.close_drop", param.ty, MM_MOVE, false);
    MirValue v = uw_param0(&b);
    (void)mir_b_call(&b, close, &v, 1);
    MirValue on = mir_b_call_rt(&b, gate, NULL, 0);
    MirValue args[2] = {on, v};
    (void)mir_b_emit(&b, MOP_DropIf, args, 2, mir_imm_none(), MIR_NONE);
    uw_ret_unit(&b);
    *out = uw_finish(&b);
    (void)uh_put(&cx->pass, &cx->with_closers, close, *out);
    return true;
}

/* Points every scope close registered in `f` at its closing-then-dropping variant. */
bool uw_wrap_with_closers(UwCx *cx, MirFunc *f) {
    bool changed = false;
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        for (uint32_t ii = 0; ii < f->blocks[bi].ninsts; ii++) {
            MirInst *inst = &f->blocks[bi].insts[ii];
            uint32_t g = 0, w = 0;
            if (uw_is_func(inst, MOP_CleanupPush, &g) && uw_with_closer(cx, g, &w)) {
                inst->imm.a = w;
                changed = true;
            }
        }
    }
    return changed;
}

/* Names the half-emptied owners of `f`: each move-out of a field of a struct value opens a hole
 * in it, and a stand-in value (never defined) stands for the owner's other fields while the hole
 * is open, so a cancellation inside the window drops them and leaves the moved field to its new
 * owner. */
void uw_name_holes(UwCx *cx, MirFunc *f, const UwHash *in_slots) {
    cx->holes = (UwHash){0};
    cx->partials = (UwHash){0};
    cx->proj = (UwHash){0};
    UwHash taken_from = {0};
    uint64_t *found = MS_NEW_N(&cx->fn, uint64_t, 1);
    uint32_t nfound = 0, cfound = 1;
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        const MirBlockData *blk = &f->blocks[bi];
        for (uint32_t k = 0; k < blk->ninsts; k++) {
            const MirInst *inst = &blk->insts[k];
            if (inst->op == MOP_Take && inst->res != MIR_NONE && inst->nargs > 0) {
                (void)uh_put(&cx->fn, &taken_from, inst->res, inst->args[0]);
            } else if (inst->op == MOP_TypeGet && inst->imm.tag == MI_FIELD &&
                       inst->res != MIR_NONE && inst->nargs > 0) {
                (void)uh_put(&cx->fn, &cx->proj, inst->res, (uint64_t)inst->args[0] << 32 | inst->imm.b);
            } else if (inst->op == MOP_MoveOut) {
                const bool released = k + 1 < blk->ninsts && blk->insts[k + 1].op == MOP_TypeRelease;
                uint64_t base = 0;
                if (!released && inst->nargs > 0 && uh_get(&cx->proj, inst->args[0], &base)) {
                    if (nfound == cfound) {
                        uint64_t *grown = MS_NEW_N(&cx->fn, uint64_t, cfound * 2);
                        memcpy(grown, found, sizeof(uint64_t) * nfound);
                        found = grown;
                        cfound *= 2;
                    }
                    found[nfound++] = base;
                }
            }
        }
    }
    for (uint32_t i = 0; i < nfound; i++) {
        const uint32_t base = (uint32_t)(found[i] >> 32), fk = (uint32_t)found[i];
        const MirTy ty = mir_value_ty(f, base);
        const MirTyData *d = mir_ty_data(cx->m, ty);
        if (d->kind != MK_TYPE) {
            continue;
        }
        uint64_t slot = 0;
        /* A value taken from a slot whose close is registered is dropped whole by that close, and
         * one taken from a slot this function does not own (a closure's capture) by its owner. */
        const bool foreign = uh_get(&taken_from, base, &slot) && !uh_has(&cx->cells, slot);
        if (cx->m->type_defs[d->id].nfields > 32 || foreign || uh_has(in_slots, base) ||
            uh_has(&cx->holes, found[i])) {
            continue;
        }
        const MirValue pseudo = mir_new_value(cx->m, f, ty);
        (void)uh_put(&cx->fn, &cx->holes, found[i], pseudo);
        (void)uh_put(&cx->fn, &cx->partials, pseudo, found[i]);
        (void)fk;
    }
}

/* Whether every path from the entry to block `to` passes through block `d`. */
static bool uw_dominates(MsArena *a, const MirFunc *f, uint32_t d, uint32_t to) {
    if (d == to) {
        return true;
    }
    bool *seen = MS_NEW_N(a, bool, f->nblocks);
    memset(seen, 0, f->nblocks);
    uint32_t *stack = MS_NEW_N(a, uint32_t, (size_t)f->nblocks * 2 + 2);
    uint32_t n = 0;
    stack[n++] = 0;
    while (n > 0) {
        const uint32_t b = stack[--n];
        if (b == d || seen[b]) {
            continue;
        }
        seen[b] = true;
        if (b == to) {
            return false;
        }
        for (uint32_t k = 0; k < mir_term_ntargets(&f->blocks[b].term); k++) {
            stack[n++] = mir_term_target_const(&f->blocks[b].term, k)->block;
        }
    }
    return true;
}

/* A call inside a shield window that closes a slot in place. */
typedef struct UwShieldCall {
    uint32_t block, at;
    MirValue slot;
    MirTy ty;
} UwShieldCall;

typedef struct UwShield {
    UwCx *cx;
    MirFunc *f;
    UwHash slots, roots, memo;
    uint32_t path[10];
    uint32_t npath;
    UwShieldCall *calls;
    uint32_t ncalls, ccalls;
} UwShield;

static void uw_shield_collect(UwShield *s, uint32_t cur, uint32_t start, uint32_t end) {
    const MirBlockData *blk = &s->f->blocks[cur];
    for (uint32_t k = start; k < end; k++) {
        const MirInst *inst = &blk->insts[k];
        uint64_t root = 0, ty = 0;
        uint32_t g = 0;
        if (inst->op == MOP_Call && inst->nargs > 0 && uh_get(&s->roots, inst->args[0], &root) &&
            uh_get(&s->slots, root, &ty) && uw_is_func(inst, MOP_Call, &g) &&
            !uw_takes_from_slot_in(s->cx->m, g, &s->memo, &s->cx->fn)) {
            if (s->ncalls == s->ccalls) {
                UwShieldCall *grown = MS_NEW_N(&s->cx->fn, UwShieldCall, s->ccalls * 2);
                memcpy(grown, s->calls, sizeof(UwShieldCall) * s->ncalls);
                s->calls = grown;
                s->ccalls *= 2;
            }
            s->calls[s->ncalls++] = (UwShieldCall){cur, k, (MirValue)root, (MirTy)ty};
        }
    }
}

/* Walks from `bi`/`ii` along unconditional branches to the matching shield exit, collecting the
 * calls on the way; whether an exit was found. */
static bool uw_shield_window(UwShield *s, uint32_t bi, uint32_t ii) {
    uint32_t cur = bi, start = ii + 1, hops = 0;
    s->npath = 1;
    s->path[0] = bi;
    for (;;) {
        const MirBlockData *blk = &s->f->blocks[cur];
        uint32_t end = start;
        while (end < blk->ninsts && !uw_ext_named(s->cx->m, &blk->insts[end], "msrt_shield_exit")) {
            end++;
        }
        uw_shield_collect(s, cur, start, end);
        if (end < blk->ninsts) {
            return true;
        }
        if (blk->term.kind != MT_BR) {
            return false;
        }
        const MirBlock next = blk->term.a.block;
        hops++;
        bool again = false;
        for (uint32_t i = 0; i < s->npath; i++) {
            again = again || s->path[i] == next;
        }
        if (hops > 8 || again) {
            return false;
        }
        cur = next;
        start = 0;
        s->path[s->npath++] = cur;
    }
}

/* Whether an entry still registered for `slot` covers it at instruction `upto` of block `blk` on
 * the window's path. */
static bool uw_shield_registered(UwShield *s, MirValue slot, uint32_t blk, uint32_t upto) {
    const MirFunc *f = s->f;
    uint32_t at = 0;
    for (uint32_t i = 0; i < s->npath; i++) {
        if (s->path[i] == blk) {
            at = i;
            break;
        }
    }
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t k = 0; k < f->blocks[b].ninsts; k++) {
            const MirInst *push = &f->blocks[b].insts[k];
            if (push->op != MOP_CleanupPush || uw_arg(push, 0) != slot) {
                continue;
            }
            /* An entry covers the slot until its discard: one pushed on the window's path from
             * its push on, one pushed before the path from the path's start. */
            uint32_t from = MIR_NONE;
            for (uint32_t i = 0; i <= at; i++) {
                if (s->path[i] == b) {
                    from = i;
                    break;
                }
            }
            if (from == MIR_NONE && !uw_dominates(&s->cx->fn, f, b, s->path[0])) {
                continue;
            }
            bool discarded = false;
            for (uint32_t n = from == MIR_NONE ? 0 : from; n <= at && !discarded; n++) {
                const uint32_t pb = s->path[n];
                const uint32_t hi = pb == blk ? upto : f->blocks[pb].ninsts;
                uint32_t lo = 0;
                if (n == from && from != MIR_NONE) {
                    lo = k + 1 < hi ? k + 1 : hi;
                }
                for (uint32_t j = lo; j < hi && !discarded; j++) {
                    const MirInst *i = &f->blocks[pb].insts[j];
                    discarded = i->op == MOP_CallRt && uw_arg(i, 0) == push->res;
                }
            }
            if (!discarded) {
                return true;
            }
        }
    }
    return false;
}

static void uw_insert_call(UwCx *cx, MirFunc *f, uint32_t blk, uint32_t at, MirOp op, MirValue arg,
                           MirImm imm, MirValue res, MirLoc loc) {
    const MirInst inst = mir_inst(op, imm, res, loc, mir_args_copy(cx->m, &arg, 1), 1);
    mir_block_insert(cx->m, &f->blocks[blk], at, &inst);
}

/* Covers the calls of one closed window that close a slot in place and have no entry yet. */
static bool uw_shield_cover(UwShield *s) {
    UwCx *cx = s->cx;
    MirFunc *f = s->f;
    uint32_t *shifts = MS_NEW_N(&cx->fn, uint32_t, f->nblocks);
    memset(shifts, 0, sizeof(uint32_t) * f->nblocks);
    bool changed = false;
    for (uint32_t c = 0; c < s->ncalls; c++) {
        const UwShieldCall call = s->calls[c];
        const uint32_t k = call.at + shifts[call.block];
        if (uw_shield_registered(s, call.slot, call.block, k)) {
            continue;
        }
        const MirLoc loc = f->blocks[call.block].insts[k].loc;
        const uint32_t dropper = uw_slot_dropper(cx, call.ty);
        const MirValue handle = mir_new_value(cx->m, f, MIR_INT);
        const MirValue unit = mir_new_value(cx->m, f, MIR_VOID);
        uw_insert_call(cx, f, call.block, k + 1, MOP_CallRt, handle, mir_imm_ext(cx->discard), unit,
                       loc);
        uw_insert_call(cx, f, call.block, k, MOP_CleanupPush, call.slot, uw_imm_func(dropper),
                       handle, loc);
        shifts[call.block] += 2;
        changed = true;
    }
    return changed;
}

/* Covers a slot-held value while a shielded close works on it in place. A fault inside the close
 * never returns to its caller, and the entry the scope registered for the value is gone by then,
 * so a drop is registered around the close call. */
bool uw_cover_shielded_slots(UwCx *cx, MirFunc *f) {
    UwShield s = {.cx = cx, .f = f, .ccalls = 4};
    UW_INSTS(f, b, i, inst) {
        if (inst->op == MOP_Slot && inst->imm.tag == MI_TY && inst->res != MIR_NONE &&
            mir_needs_drop(cx->m, inst->imm.a)) {
            (void)uh_put(&cx->fn, &s.slots, inst->res, inst->imm.a);
            (void)uh_put(&cx->fn, &s.roots, inst->res, inst->res);
        }
    }
    if (s.slots.n == 0) {
        return false;
    }
    /* A part of a slot's value (an inlined close hands its helpers the address of a field) names
     * the slot it lies in. */
    UW_INSTS(f, b2, i2, inst2) {
        uint64_t root = 0;
        if (inst2->op == MOP_PtrField && inst2->res != MIR_NONE && inst2->nargs > 0 &&
            uh_get(&s.roots, inst2->args[0], &root)) {
            (void)uh_put(&cx->fn, &s.roots, inst2->res, root);
        }
    }
    bool changed = false;
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        for (uint32_t ii = 0; ii < f->blocks[bi].ninsts; ii++) {
            if (!uw_ext_named(cx->m, &f->blocks[bi].insts[ii], "msrt_shield_enter")) {
                continue;
            }
            s.calls = MS_NEW_N(&cx->fn, UwShieldCall, s.ccalls);
            s.ncalls = 0;
            if (uw_shield_window(&s, bi, ii)) {
                changed = uw_shield_cover(&s) || changed;
            }
        }
    }
    return changed;
}

/* Keeps a slot-held value covered after its scope close ran inline. Scope end discards the close
 * entry and then runs the close in place; when the close returns an error the program faults
 * with the value still in its slot, so a drop is registered from the close's return until the
 * result is known to be good. */
static bool uw_inline_close_at(UwCx *cx, MirFunc *f, uint32_t bi, uint32_t *ii, MirValue slot,
                               MirTy ty) {
    const MirBlockData *blk = &f->blocks[bi];
    const MirLoc loc = blk->insts[*ii].loc;
    uint32_t exit = *ii + 1;
    while (exit < blk->ninsts && !uw_ext_named(cx->m, &blk->insts[exit], "msrt_shield_exit")) {
        exit++;
    }
    if (exit == blk->ninsts) {
        return false;
    }
    const uint32_t dropper = uw_slot_dropper(cx, ty);
    const MirValue handle = mir_new_value(cx->m, f, MIR_INT);
    const MirPreds preds = mir_preds(&cx->fn, f);
    const uint32_t ntargets = mir_term_ntargets(&blk->term);
    for (uint32_t k = 0; k < ntargets; k++) {
        if (mir_preds_count(&preds, mir_term_target_const(&blk->term, k)->block) != 1) {
            return false;
        }
    }
    if (ntargets == 0) {
        return false;
    }
    /* The close's own result is checked next: a failed close faults with the value back in its
     * slot, so only the edges that go on leave it unregistered. */
    for (uint32_t k = 0; k < ntargets; k++) {
        const MirBlock t = mir_term_target_const(&blk->term, k)->block;
        if (f->blocks[t].term.kind != MT_FAULT && f->blocks[t].term.kind != MT_UNREACHABLE) {
            const MirValue unit = mir_new_value(cx->m, f, MIR_VOID);
            uw_insert_call(cx, f, t, 0, MOP_CallRt, handle, mir_imm_ext(cx->discard), unit, loc);
        }
    }
    uw_insert_call(cx, f, bi, exit + 1, MOP_CleanupPush, slot, uw_imm_func(dropper), handle, loc);
    *ii = exit + 1;
    return true;
}

bool uw_cover_inline_closes(UwCx *cx, MirFunc *f) {
    UwHash slot_types = {0}, pushes = {0};
    for (uint32_t i = 0; i < cx->with_closers.cap; i++) {
        MirTy ty = 0;
        if (cx->with_closers.used[i] && uw_slot_close_value(cx->m, (uint32_t)cx->with_closers.key[i], &ty)) {
            (void)uh_put(&cx->fn, &slot_types, cx->with_closers.val[i], ty);
        }
    }
    if (slot_types.n == 0) {
        return false;
    }
    UW_INSTS(f, b, i, inst) {
        uint32_t g = 0;
        uint64_t ty = 0;
        if (uw_is_func(inst, MOP_CleanupPush, &g) && inst->res != MIR_NONE && inst->nargs > 0 &&
            uh_get(&slot_types, g, &ty)) {
            (void)uh_put(&cx->fn, &pushes, inst->res, (uint64_t)inst->args[0] << 32 | ty);
        }
    }
    bool changed = false;
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        for (uint32_t ii = 0; ii < f->blocks[bi].ninsts; ii++) {
            const MirInst *inst = &f->blocks[bi].insts[ii];
            uint64_t push = 0;
            if (inst->op == MOP_CallRt && inst->imm.tag == MI_EXT && inst->imm.a == cx->discard &&
                uh_get(&pushes, uw_arg(inst, 0), &push)) {
                changed = uw_inline_close_at(cx, f, bi, &ii, (MirValue)(push >> 32), (MirTy)(uint32_t)push) ||
                          changed;
            }
        }
    }
    return changed;
}

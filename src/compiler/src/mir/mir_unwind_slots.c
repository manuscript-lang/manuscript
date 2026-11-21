/* unwind: which stack slots a callee only borrows from, and which a function owns. Port of the
 * slot analyses in unwind.rs (`slot_safe_params`, `slot_owned_params`, `find_cells`, ...). */
#include "mir/mir_unwind.h"

bool uw_ext_named(const MirModule *m, const MirInst *inst, const char *name) {
    if (inst->op != MOP_CallRt || inst->imm.tag != MI_EXT) {
        return false;
    }
    const MsStr s = ms_name(&m->names, m->externs[inst->imm.a].name);
    return s.len == strlen(name) && memcmp(s.ptr, name, s.len) == 0;
}

bool uw_slot_close_value(const MirModule *m, uint32_t close, MirTy *ty) {
    if (close >= m->nfuncs || !m->funcs[close].has_slot_close) {
        return false;
    }
    *ty = m->funcs[close].slot_close;
    return true;
}

static UwTable uw_table_new(MsArena *a, const MirModule *m) {
    UwTable t = {.v = MS_NEW_N(a, bool *, m->nfuncs ? m->nfuncs : 1),
                 .len = MS_NEW_N(a, uint32_t, m->nfuncs ? m->nfuncs : 1), .n = m->nfuncs};
    for (uint32_t f = 0; f < m->nfuncs; f++) {
        t.len[f] = m->funcs[f].nparams;
        t.v[f] = MS_NEW_N(a, bool, t.len[f] ? t.len[f] : 1);
        memset(t.v[f], 0, t.len[f] ? t.len[f] : 1);
    }
    return t;
}

uint32_t *uw_closure_targets(MsArena *a, const MirModule *m, uint32_t *n) {
    uint32_t *out = MS_NEW_N(a, uint32_t, m->nfuncs ? m->nfuncs : 1);
    MirBits seen = mir_bits_new(a, m->nfuncs);
    *n = 0;
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        const MirFunc *f = &m->funcs[fi];
        UW_INSTS(f, b, i, inst) {
            uint32_t g = 0;
            if (uw_is_func(inst, MOP_ClosureNew, &g) && !mir_bits_test(&seen, g)) {
                mir_bits_set(&seen, g);
                out[(*n)++] = g;
            }
        }
    }
    if (*n > 1) {
        qsort(out, *n, sizeof *out, ms_cmp_u32);
    }
    return out;
}

/* ---- takes_from_slot ---- */

/* Whether `callee` can take a value out of the slot it is given, or out of a part of it, leaving
 * a hole that dropping the whole slot would free twice. */
static bool uw_next_refills(const MirBlockData *blk, uint32_t n, const UwHash *nones) {
    if (n + 1 >= blk->ninsts) {
        return false;
    }
    const MirInst *inst = &blk->insts[n], *next = &blk->insts[n + 1];
    return next->op == MOP_Put && uw_arg(next, 0) == uw_arg(inst, 0) && next->nargs > 1 &&
           uh_has(nones, next->args[1]);
}

static bool uw_args_touch(const MirInst *inst, const UwHash *derived) {
    for (uint32_t i = 0; i < inst->nargs; i++) {
        if (uh_has(derived, inst->args[i])) {
            return true;
        }
    }
    return false;
}

typedef struct UwTake {
    const MirModule *m;
    MsArena *a;
    UwHash derived, nones;
} UwTake;

static void uw_take_prepare(UwTake *t, const MirFunc *f) {
    for (uint32_t k = 0; k < f->nparams && k < f->blocks[0].nparams; k++) {
        if (f->params[k].ty == MIR_PTR) {
            (void)uh_put(t->a, &t->derived, f->blocks[0].params[k].value, 0);
        }
    }
    UW_INSTS(f, b, i, inst) {
        const bool copy = inst->op == MOP_Clone && inst->nargs > 0 && uh_has(&t->nones, inst->args[0]);
        if (inst->res != MIR_NONE &&
            (inst->op == MOP_OptNone || inst->op == MOP_OptNoneOwned || copy)) {
            (void)uh_put(t->a, &t->nones, inst->res, 0);
        }
    }
}

static bool uw_take_inst(UwTake *t, UwHash *memo, MsArena *ma, const MirBlockData *blk,
                         uint32_t n) {
    const MirInst *inst = &blk->insts[n];
    const bool from_slot = uw_args_touch(inst, &t->derived);
    bool found = false;
    uint32_t g = 0;
    if (inst->op == MOP_Call && from_slot) {
        found = !uw_is_func(inst, MOP_Call, &g) || uw_takes_from_slot_in(t->m, g, memo, ma);
    } else if (from_slot) {
        found = (inst->op == MOP_Take && !uw_next_refills(blk, n, &t->nones)) ||
                inst->op == MOP_CallInd || inst->op == MOP_CallMethod;
    }
    return found;
}

bool uw_takes_from_slot_in(const MirModule *m, uint32_t callee, UwHash *memo, MsArena *ma) {
    uint64_t known = 0;
    if (uh_get(memo, callee, &known)) {
        return known != 0;
    }
    (void)uh_put(ma, memo, callee, 0); /* a cycle is assumed to take nothing */
    const MirFunc *f = &m->funcs[callee];
    MsArena tmp = {0};
    UwTake t = {.m = m, .a = &tmp};
    bool found = false;
    if (f->nblocks > 0) {
        uw_take_prepare(&t, f);
        for (uint32_t b = 0; b < f->nblocks; b++) {
            for (uint32_t n = 0; n < f->blocks[b].ninsts; n++) {
                found = uw_take_inst(&t, memo, ma, &f->blocks[b], n) || found;
                const MirInst *inst = &f->blocks[b].insts[n];
                if (inst->res != MIR_NONE && uh_has(&t.derived, uw_arg(inst, 0)) &&
                    mir_value_ty(f, inst->res) == MIR_PTR) {
                    (void)uh_put(&tmp, &t.derived, inst->res, 0);
                }
            }
        }
    }
    ms_arena_free(&tmp);
    (void)uh_put(ma, memo, callee, found ? 1 : 0);
    return found;
}

/* ---- slot_safe_params ---- */

typedef struct UwBsv {
    const MirModule *m;
    const UwTable *safe;
    const bool *parks;
    const MirFunc *f;
    MirValue p;
    MsArena *a;
    UwHash taken, derived, fwd, local;
} UwBsv;

static bool uw_safe_at(const UwTable *t, uint32_t g, uint32_t i) { return uw_flag(t, g, i); }

static bool uw_holds(const UwBsv *s, MirValue r) {
    const MirTy ty = mir_value_ty(s->f, r);
    return mir_needs_drop(s->m, ty) || ty == MIR_PTR;
}

/* One sweep of the fixpoint: which values hold the slot's contents or borrow them. */
static bool uw_bsv_grow(UwBsv *s) {
    bool grew = false;
    const MirFunc *f = s->f;
    UW_INSTS(f, b, i, inst) {
        const bool put = inst->op == MOP_Put && inst->nargs == 2 &&
                         uh_has(&s->local, inst->args[0]) && uh_has(&s->taken, inst->args[1]) &&
                         uh_put(s->a, &s->fwd, inst->args[0], 0);
        const bool take = inst->op == MOP_Take && inst->res != MIR_NONE &&
                          uh_has(&s->fwd, uw_arg(inst, 0)) && uh_put(s->a, &s->taken, inst->res, 0);
        grew = grew || put || take;
    }
    UW_INSTS(f, b2, i2, inst2) {
        if (inst2->res == MIR_NONE) {
            continue;
        }
        bool from_held = false;
        for (uint32_t k = 0; k < inst2->nargs; k++) {
            from_held = from_held || uh_has(&s->taken, inst2->args[k]) ||
                        uh_has(&s->derived, inst2->args[k]);
        }
        const bool view = inst2->op == MOP_Load && uw_arg(inst2, 0) == s->p;
        MirMode mode = MM_BORROW;
        const bool owned = mir_result_mode(s->m, f, inst2, &mode) && mode == MM_MOVE;
        if ((from_held || view) && uw_holds(s, inst2->res) && !uh_has(&s->taken, inst2->res) &&
            !owned && uh_put(s->a, &s->derived, inst2->res, 0)) {
            grew = true;
        }
    }
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t k = 0; k < mir_term_ntargets(&f->blocks[b].term); k++) {
            const MirTarget *t = mir_term_target_const(&f->blocks[b].term, k);
            const MirBlockData *dest = &f->blocks[t->block];
            for (uint32_t j = 0; j < t->nargs && j < dest->nparams; j++) {
                if (uh_has(&s->taken, t->args[j]) &&
                    uh_put(s->a, &s->taken, dest->params[j].value, 0)) {
                    grew = true;
                }
            }
        }
    }
    return grew;
}

/* A parameter that takes the value on some edges takes it on all, or it could swap values. */
static bool uw_bsv_mixed(const UwBsv *s) {
    const MirFunc *f = s->f;
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t k = 0; k < mir_term_ntargets(&f->blocks[b].term); k++) {
            const MirTarget *t = mir_term_target_const(&f->blocks[b].term, k);
            const MirBlockData *dest = &f->blocks[t->block];
            for (uint32_t j = 0; j < t->nargs && j < dest->nparams; j++) {
                if (uh_has(&s->taken, dest->params[j].value) && !uh_has(&s->taken, t->args[j])) {
                    return true;
                }
            }
        }
    }
    return false;
}

static bool uw_every_method_safe(const UwBsv *s, uint32_t iface, uint32_t slot) {
    for (uint32_t v = 0; v < s->m->nvtables; v++) {
        const MirVtable *vt = &s->m->vtables[v];
        if (vt->iface == iface && !(slot < vt->nmethods && uw_safe_at(s->safe, vt->methods[slot], 0))) {
            return false;
        }
    }
    return true;
}

/* Whether use `i` of the slot pointer or a local slot forwarding its value is one a borrower may
 * make: a take, a load, a put of the taken value, or a call whose callee only borrows. */
static bool uw_bsv_slot_use_ok(const UwBsv *s, const MirInst *inst, uint32_t i, bool via_fwd) {
    uint32_t g = 0;
    const bool put_taken = i == 0 && uh_has(&s->taken, uw_arg(inst, 1));
    if (inst->op == MOP_Call && uw_is_func(inst, MOP_Call, &g)) {
        return uw_safe_at(s->safe, g, i);
    }
    if (inst->op == MOP_Put) {
        return put_taken;
    }
    if (inst->op == MOP_Take) {
        return i == 0;
    }
    if (via_fwd) {
        return false;
    }
    if (inst->op == MOP_Load) {
        return i == 0;
    }
    return uw_is_func(inst, MOP_ClosureNew, &g) &&
           uw_closure_borrows_capture(s->m, s->safe, s->parks, g, i);
}

/* Whether use `i` of a value read from the slot, or a borrow of it, leaves the slot's contents
 * where they were. */
static bool uw_bsv_value_use_ok(const UwBsv *s, const MirInst *inst, uint32_t i,
                                const MirMode *modes) {
    const bool putback = inst->op == MOP_Put && i == 1 &&
                         (inst->args[0] == s->p || uh_has(&s->fwd, inst->args[0]));
    /* A method call hands its receiver to every implementation of the method. */
    const bool method = !(inst->op == MOP_CallMethod && inst->imm.tag == MI_METHOD && i == 0) ||
                        uw_every_method_safe(s, inst->imm.a, inst->imm.b);
    const bool scalar_write = inst->op == MOP_Store && i == 0 && inst->nargs > 1 &&
                              !mir_needs_drop(s->m, mir_value_ty(s->f, inst->args[1]));
    const bool moves_out = inst->op == MOP_MoveOut || inst->op == MOP_Store ||
                           inst->op == MOP_Put || inst->op == MOP_CleanupPush ||
                           inst->op == MOP_TypeFill || inst->op == MOP_ListFill ||
                           inst->op == MOP_CallInd;
    const bool borrowed = modes[i] == MM_BORROW && method && (scalar_write || !moves_out);
    return putback || borrowed;
}

static bool uw_bsv_insts_ok(UwBsv *s, const MirBlockData *blk) {
    for (uint32_t n = 0; n < blk->ninsts; n++) {
        const MirInst *inst = &blk->insts[n];
        MirMode *modes = MS_NEW_N(s->a, MirMode, inst->nargs ? inst->nargs : 1);
        mir_arg_modes(s->m, s->f, inst, modes);
        for (uint32_t i = 0; i < inst->nargs; i++) {
            const MirValue a = inst->args[i];
            bool ok = true;
            if (uh_has(&s->fwd, a)) {
                ok = uw_bsv_slot_use_ok(s, inst, i, true);
            } else if (a == s->p) {
                ok = uw_bsv_slot_use_ok(s, inst, i, false);
            } else if (uh_has(&s->taken, a) || uh_has(&s->derived, a)) {
                ok = uw_bsv_value_use_ok(s, inst, i, modes);
            }
            if (!ok) {
                return false;
            }
        }
    }
    return true;
}

static bool uw_bsv_leaves(const UwBsv *s, const MirTerm *term) {
    if (term->kind == MT_RET && term->value != MIR_NONE &&
        (term->value == s->p || uh_has(&s->taken, term->value) ||
         uh_has(&s->derived, term->value))) {
        return true;
    }
    /* An edge may pass only the value itself on, never a borrow of it or the slot. */
    for (uint32_t k = 0; k < mir_term_ntargets(term); k++) {
        const MirTarget *t = mir_term_target_const(term, k);
        for (uint32_t j = 0; j < t->nargs; j++) {
            if (t->args[j] == s->p || uh_has(&s->derived, t->args[j])) {
                return true;
            }
        }
    }
    return false;
}

/* Whether `f` only borrows the contents of the slot that the pointer `p` names (a parameter or a
 * capture): it `take`s them, uses them as borrows, and `put`s the same value back. */
static bool uw_borrows_slot_value(const MirModule *m, const UwTable *safe, const bool *parks,
                                  const MirFunc *f, MirValue p) {
    MsArena tmp = {0};
    UwBsv s = {.m = m, .safe = safe, .parks = parks, .f = f, .p = p, .a = &tmp};
    UW_INSTS(f, b, i, inst) {
        if (inst->op == MOP_Slot && inst->res != MIR_NONE) {
            (void)uh_put(&tmp, &s.local, inst->res, 0);
        }
        if (inst->op == MOP_Take && inst->res != MIR_NONE && uw_arg(inst, 0) == p) {
            (void)uh_put(&tmp, &s.taken, inst->res, 0);
        }
    }
    while (uw_bsv_grow(&s)) {
    }
    bool ok = !uw_bsv_mixed(&s);
    for (uint32_t b = 0; b < f->nblocks && ok; b++) {
        ok = uw_bsv_insts_ok(&s, &f->blocks[b]) && !uw_bsv_leaves(&s, &f->blocks[b].term);
    }
    ms_arena_free(&tmp);
    return ok;
}

bool uw_closure_borrows_capture(const MirModule *m, const UwTable *safe, const bool *parks,
                                uint32_t g, uint32_t idx) {
    /* A closure that never parks cannot be cancelled while it holds the slot's value out. */
    if (parks != NULL && g < m->nfuncs && !parks[g]) {
        return true;
    }
    if (g >= m->nfuncs) {
        return false;
    }
    const MirFunc *f = &m->funcs[g];
    bool any = false;
    UW_INSTS(f, b, i, inst) {
        if (inst->op == MOP_ClosureCap && inst->imm.tag == MI_IDX && inst->imm.a == idx &&
            inst->res != MIR_NONE) {
            any = true;
            if (!uw_borrows_slot_value(m, safe, parks, f, inst->res)) {
                return false;
            }
        }
    }
    return any;
}

UwTable uw_slot_safe_params(MsArena *a, const MirModule *m) {
    UwTable safe = uw_table_new(a, m);
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        for (uint32_t k = 0; k < m->funcs[fi].nparams; k++) {
            safe.v[fi][k] = m->funcs[fi].params[k].ty == MIR_PTR;
        }
    }
    for (bool changed = true; changed;) {
        changed = false;
        for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
            const MirFunc *f = &m->funcs[fi];
            for (uint32_t k = 0; k < f->nparams; k++) {
                if (!safe.v[fi][k] ||
                    (f->nblocks > 0 && k < f->blocks[0].nparams &&
                     uw_borrows_slot_value(m, &safe, NULL, f, f->blocks[0].params[k].value))) {
                    continue;
                }
                safe.v[fi][k] = false;
                changed = true;
            }
        }
    }
    return safe;
}

/* ---- slot_owned_params ---- */

/* The position of `v` among the entry block's parameters, or MIR_NONE. */
static uint32_t uw_param_pos(const MirFunc *f, MirValue v) {
    for (uint32_t k = 0; k < f->blocks[0].nparams; k++) {
        if (f->blocks[0].params[k].value == v) {
            return k;
        }
    }
    return MIR_NONE;
}

static UwHash uw_push_entries(MsArena *a, const MirFunc *f) {
    UwHash entries = {0};
    UW_INSTS(f, b, i, inst) {
        if (inst->op == MOP_CleanupPush && inst->nargs > 0) {
            (void)uh_put(a, &entries, inst->args[0], 0);
        }
    }
    return entries;
}

/* Per function and parameter, whether some direct call passes a slot that has a cleanup entry, or
 * the caller's own parameter that is covered in turn. */
static UwTable uw_covered_slot_params(MsArena *a, const MirModule *m) {
    UwTable covered = uw_table_new(a, m);
    for (uint32_t v = 0; v < m->nvtables; v++) {
        for (uint32_t k = 0; k < m->vtables[v].nmethods; k++) {
            const MirFunc *f = &m->funcs[m->vtables[v].methods[k]];
            for (uint32_t p = 0; p < f->nparams; p++) {
                covered.v[m->vtables[v].methods[k]][p] = f->params[p].ty == MIR_PTR;
            }
        }
    }
    for (bool changed = true; changed;) {
        changed = false;
        for (uint32_t ci = 0; ci < m->nfuncs; ci++) {
            const MirFunc *caller = &m->funcs[ci];
            MsArena tmp = {0};
            const UwHash entries = uw_push_entries(&tmp, caller);
            UW_INSTS(caller, b, i, inst) {
                uint32_t g = 0;
                if (!uw_is_func(inst, MOP_Call, &g)) {
                    continue;
                }
                for (uint32_t k = 0; k < inst->nargs; k++) {
                    const uint32_t kp = caller->nblocks ? uw_param_pos(caller, inst->args[k]) : MIR_NONE;
                    const bool held = uh_has(&entries, inst->args[k]) ||
                                      (kp != MIR_NONE && uw_flag(&covered, ci, kp));
                    if (held && k < covered.len[g] && !covered.v[g][k]) {
                        covered.v[g][k] = true;
                        changed = true;
                    }
                }
            }
            ms_arena_free(&tmp);
        }
    }
    return covered;
}

/* The local slots of `f` that are filled with a value taken out of a slot that something else
 * covers. */
static UwHash uw_refilled_from_covered(MsArena *a, const MirModule *m, const MirFunc *f,
                                       const UwTable *covered, uint32_t fi, const UwHash *entries) {
    UwHash params = uh_clone(a, entries), taken = {0}, out = {0};
    for (uint32_t k = 0; k < f->blocks[0].nparams; k++) {
        if (uw_flag(covered, fi, k)) {
            (void)uh_put(a, &params, f->blocks[0].params[k].value, 0);
        }
    }
    MirBlock *order = NULL;
    const uint32_t norder = mir_rpo(a, f, &order);
    for (uint32_t oi = 0; oi < norder; oi++) {
        const MirBlockData *blk = &f->blocks[order[oi]];
        for (uint32_t n = 0; n < blk->ninsts; n++) {
            const MirInst *inst = &blk->insts[n];
            const bool owns = inst->res != MIR_NONE && mir_needs_drop(m, mir_value_ty(f, inst->res));
            if (inst->op == MOP_Put && uh_has(&taken, uw_arg(inst, 1))) {
                (void)uh_put(a, &out, inst->args[0], 0);
            } else if (owns && ((inst->op == MOP_Take && uh_has(&params, uw_arg(inst, 0))) ||
                                ((inst->op == MOP_TypeGet || inst->op == MOP_AltGet ||
                                  inst->op == MOP_MoveOut) && uh_has(&taken, uw_arg(inst, 0))))) {
                (void)uh_put(a, &taken, inst->res, 0);
            }
        }
    }
    return out;
}

typedef struct UwOwned {
    const MirModule *m;
    UwTable *owns;
    const UwTable *covered;
    const uint32_t *targets;
    uint32_t ntargets;
    bool *used;
} UwOwned;

/* The functions `inst` calls: every closure of its shape for a `call.ind`, none for a
 * `closure.new`. */
static uint32_t uw_reached(const UwOwned *o, const MirInst *inst, uint32_t *out, bool *skip) {
    uint32_t n = 0;
    *skip = false;
    if (inst->op == MOP_CallInd) {
        for (uint32_t t = 0; t < o->ntargets; t++) {
            if (o->m->funcs[o->targets[t]].nparams == inst->nargs) {
                out[n++] = o->targets[t];
            }
        }
    } else if (inst->op == MOP_ClosureNew || inst->imm.tag != MI_FUNC) {
        *skip = true;
    } else {
        out[n++] = inst->imm.a;
    }
    return n;
}

/* Whether argument `k` of a call is a slot of the caller's own that nothing covers, or its own
 * owned slot parameter passed on. */
static bool uw_owned_arg(const UwOwned *o, const MirFunc *caller, uint32_t ci, const MirInst *inst,
                         uint32_t k, const UwHash *slots, const UwHash *entries, const bool *mine) {
    if (k >= inst->nargs) {
        return false;
    }
    const MirValue a = inst->args[k];
    uint64_t ty = 0;
    if (uh_get(slots, a, &ty) && mir_needs_drop(o->m, (MirTy)ty) && !uh_has(entries, a)) {
        return true;
    }
    const uint32_t kp = uw_param_pos(caller, a);
    return kp != MIR_NONE && o->used[ci] && mine[kp];
}

static bool uw_owned_caller(UwOwned *o, uint32_t ci) {
    const MirFunc *caller = &o->m->funcs[ci];
    if (caller->nblocks == 0) {
        return false;
    }
    MsArena tmp = {0};
    UwHash slots = {0};
    UW_INSTS(caller, b, i, inst) {
        if (inst->op == MOP_Slot && inst->imm.tag == MI_TY && inst->res != MIR_NONE) {
            (void)uh_put(&tmp, &slots, inst->res, inst->imm.a);
        }
    }
    UwHash entries = uw_push_entries(&tmp, caller);
    const UwHash refilled = uw_refilled_from_covered(&tmp, o->m, caller, o->covered, ci, &entries);
    for (uint32_t i = 0; i < refilled.cap; i++) {
        if (refilled.used[i]) {
            (void)uh_put(&tmp, &entries, refilled.key[i], 0);
        }
    }
    uint32_t *reached = MS_NEW_N(&tmp, uint32_t, o->m->nfuncs + 1);
    bool *mine = MS_NEW_N(&tmp, bool, caller->nparams + 1);
    bool changed = false;
    UW_INSTS(caller, b2, i2, inst2) {
        bool skip = false;
        const uint32_t n = uw_reached(o, inst2, reached, &skip);
        if (skip) {
            continue;
        }
        const bool direct = inst2->op == MOP_Call || inst2->op == MOP_CallInd;
        memcpy(mine, o->owns->v[ci], caller->nparams);
        for (uint32_t r = 0; r < n; r++) {
            bool *flags = o->owns->v[reached[r]];
            for (uint32_t k = 0; k < o->owns->len[reached[r]]; k++) {
                if (flags[k] && !(direct && uw_owned_arg(o, caller, ci, inst2, k, &slots, &entries, mine))) {
                    flags[k] = false;
                    changed = true;
                }
            }
        }
    }
    ms_arena_free(&tmp);
    return changed;
}

UwTable uw_slot_owned_params(MsArena *a, const MirModule *m, const UwTable *safe) {
    UwTable owns = uw_table_new(a, m);
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        for (uint32_t k = 0; k < m->funcs[fi].nparams; k++) {
            owns.v[fi][k] = m->funcs[fi].params[k].ty == MIR_PTR && !uw_flag(safe, fi, k);
        }
    }
    uint32_t ntargets = 0;
    const uint32_t *targets = uw_closure_targets(a, m, &ntargets);
    bool *used = MS_NEW_N(a, bool, m->nfuncs ? m->nfuncs : 1);
    memset(used, 0, m->nfuncs ? m->nfuncs : 1);
    UwOwned o = {.m = m, .owns = &owns, .targets = targets, .ntargets = ntargets, .used = used};
    /* The functions some call reaches; a function nothing calls directly is reached some other way
     * (a method table, a function value), so its callers do not cover its slot parameters. */
    for (uint32_t ci = 0; ci < m->nfuncs; ci++) {
        const MirFunc *caller = &m->funcs[ci];
        uint32_t *reached = MS_NEW_N(a, uint32_t, m->nfuncs + 1);
        UW_INSTS(caller, b, i, inst) {
            bool skip = false;
            const uint32_t n = uw_reached(&o, inst, reached, &skip);
            for (uint32_t r = 0; r < n && !skip; r++) {
                used[reached[r]] = true;
            }
        }
    }
    for (uint32_t v = 0; v < m->nvtables; v++) {
        for (uint32_t k = 0; k < m->vtables[v].nmethods; k++) {
            memset(owns.v[m->vtables[v].methods[k]], 0, owns.len[m->vtables[v].methods[k]]);
        }
    }
    const UwTable covered = uw_covered_slot_params(a, m);
    o.covered = &covered;
    for (bool changed = true; changed;) {
        changed = false;
        for (uint32_t ci = 0; ci < m->nfuncs; ci++) {
            changed = uw_owned_caller(&o, ci) || changed;
        }
    }
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        if (!used[fi]) {
            memset(owns.v[fi], 0, owns.len[fi]);
        }
    }
    return owns;
}

/* ---- hands_off ---- */

/* Whether a call hands the slot at argument `k` to a callee that owns it while it runs: the
 * callee covers what it takes, so the caller's cover pauses for the call. */
bool uw_hands_off(const UwCx *cx, const MirInst *inst, uint32_t k) {
    uint32_t g = 0;
    if (uw_is_func(inst, MOP_Call, &g)) {
        return uw_flag(&cx->owns, g, k);
    }
    if (inst->op != MOP_CallInd || k == 0) {
        return false;
    }
    bool any = false;
    for (uint32_t t = 0; t < cx->ntargets; t++) {
        const uint32_t h = cx->targets[t];
        if (cx->safe.len[h] != inst->nargs || !uw_flag(&cx->pointer, h, k)) {
            continue;
        }
        if (!uw_flag(&cx->owns, h, k)) {
            return false;
        }
        any = true;
    }
    return any;
}

/* Whether every closure that takes `arity` parameters and a pointer at position `k` only borrows
 * what that pointer's slot holds. False when there is no such closure. */
static bool uw_closures_borrow(const UwCx *cx, uint32_t arity, uint32_t k) {
    bool any = false, unsafe = false;
    for (uint32_t t = 0; t < cx->ntargets; t++) {
        const uint32_t g = cx->targets[t];
        if (cx->safe.len[g] != arity) {
            continue;
        }
        any = any || uw_flag(&cx->safe, g, k);
        /* A candidate whose parameter at `k` is a pointer that it may consume makes the call unsafe. */
        unsafe = unsafe || (!uw_flag(&cx->safe, g, k) && uw_flag(&cx->pointer, g, k));
    }
    return any && !unsafe;
}

/* ---- find_cells ---- */

typedef struct UwCells {
    UwCx *cx;
    const MirFunc *f;
    MsArena *a;
    const UwHash *params;
    UwHash slots, bad, captured, guarded;
} UwCells;

static bool uw_fresh_def_op(MirOp op) {
    return op == MOP_ListLit || op == MOP_ListFill || op == MOP_TypeNew || op == MOP_AltNew ||
           op == MOP_IfaceNew || op == MOP_Clone || op == MOP_Call || op == MOP_TypeFill;
}

static bool uw_hands_a_call(MirOp op) {
    return op == MOP_Call || op == MOP_CallInd || op == MOP_CallMethod || op == MOP_CallRt ||
           op == MOP_Poll;
}

/* The slots a closure captures by reference or that stay within a block (see the Rust comment). */
static void uw_cells_captured(UwCells *c) {
    const MirFunc *f = c->f;
    UwHash handed = {0}, fresh = {0}, stale = {0};
    UW_INSTS(f, b, i, inst) {
        for (uint32_t k = 0; k < inst->nargs && uw_hands_a_call(inst->op); k++) {
            (void)uh_put(c->a, &handed, inst->args[k], 0);
        }
        if (inst->res != MIR_NONE && uw_fresh_def_op(inst->op)) {
            (void)uh_put(c->a, &fresh, inst->res, 0);
        }
    }
    UW_INSTS(f, b2, i2, inst2) {
        if (inst2->op == MOP_Put && inst2->nargs > 1 && !uh_has(&fresh, inst2->args[1])) {
            (void)uh_put(c->a, &stale, inst2->args[0], 0);
        }
        for (uint32_t k = 0; k < inst2->nargs && inst2->op == MOP_ClosureNew; k++) {
            (void)uh_put(c->a, &c->captured, inst2->args[k], 0);
        }
    }
    /* A slot parameter that is only refilled with fresh values; one refilled with the very value
     * taken out of it stays within a block. */
    for (uint32_t i = 0; i < c->params->cap; i++) {
        if (c->params->used[i] && !uh_has(&stale, c->params->key[i])) {
            (void)uh_put(c->a, &c->captured, c->params->key[i], 0);
        }
    }
    for (uint32_t i = 0; i < c->slots.cap; i++) {
        const uint64_t s = c->slots.key[i];
        if (c->slots.used[i] && !uh_has(&handed, s) && !uh_has(&stale, s)) {
            (void)uh_put(c->a, &c->captured, s, 0);
        }
    }
}

/* The values that only feed the condition of a `drop.if`. */
static void uw_cells_guarded(UwCells *c) {
    UwHash other = {0}, cond = {0};
    const MirFunc *f = c->f;
    UW_INSTS(f, b, i, inst) {
        for (uint32_t k = 0; k < inst->nargs; k++) {
            if (inst->op == MOP_DropIf && k == 1) {
                (void)uh_put(c->a, &cond, inst->args[k], 0);
            } else {
                (void)uh_put(c->a, &other, inst->args[k], 0);
            }
        }
    }
    for (uint32_t i = 0; i < cond.cap; i++) {
        if (cond.used[i] && !uh_has(&other, cond.key[i])) {
            (void)uh_put(c->a, &c->guarded, cond.key[i], 0);
        }
    }
}

/* Whether use `k` of slot `a` by `inst` keeps the slot a cell; `full` holds the slots that hold a
 * value now. */
static bool uw_cell_use_ok(UwCells *c, UwHash *full, const MirInst *inst, uint32_t k, MirTy ty) {
    const MirValue a = inst->args[k];
    const UwCx *cx = c->cx;
    uint32_t g = 0;
    switch ((MirOp)inst->op) {
    case MOP_Put:
        if (k == 0) {
            return uh_put(c->a, full, a, 0) && mir_value_ty(c->f, inst->args[1]) == ty;
        }
        return false;
    case MOP_Take:
        /* A take whose result only feeds `drop.if` runs after a move emptied the slot. */
        return uh_del(full, a) || (inst->res != MIR_NONE && uh_has(&c->guarded, inst->res));
    case MOP_Load:
        return uh_has(full, a);
    case MOP_Call:
    case MOP_CallInd:
        if (uw_hands_off(cx, inst, k)) {
            return uh_has(full, a);
        }
        if (inst->op == MOP_Call && uw_is_func(inst, MOP_Call, &g)) {
            return uh_has(full, a) && uw_flag(&cx->safe, g, k);
        }
        /* The callee is some closure of this arity; the slot stays covered when every one that
         * could receive it at this position only borrows it. */
        return inst->op == MOP_CallInd && k > 0 && uh_has(full, a) &&
               uw_closures_borrow(cx, inst->nargs, k);
    case MOP_ClosureNew:
        return uw_is_func(inst, MOP_ClosureNew, &g) && uh_has(full, a) &&
               uw_closure_borrows_capture(cx->m, &cx->safe, cx->parks, g, k);
    default:
        return false;
    }
}

static void uw_cells_insts(UwCells *c, const MirBlockData *blk, UwHash *full) {
    for (uint32_t n = 0; n < blk->ninsts; n++) {
        const MirInst *inst = &blk->insts[n];
        for (uint32_t k = 0; k < inst->nargs; k++) {
            uint64_t ty = 0;
            if (uh_get(&c->slots, inst->args[k], &ty) &&
                !uw_cell_use_ok(c, full, inst, k, (MirTy)ty)) {
                (void)uh_put(c->a, &c->bad, inst->args[k], 0);
            }
        }
    }
}

/* Marks slots that disagree across an edge, leak out of the block, or are returned. */
static void uw_cells_edges(UwCells *c, const MirBlockData *blk, UwHash *full, UwHash *entry,
                           bool *have) {
    for (uint32_t i = 0; i < full->cap; i++) {
        if (full->used[i] && !uh_has(&c->captured, full->key[i])) {
            (void)uh_put(c->a, &c->bad, full->key[i], 0);
        }
    }
    const uint32_t ntargets = mir_term_ntargets(&blk->term);
    for (uint32_t k = 0; k < ntargets; k++) {
        const MirTarget *t = mir_term_target_const(&blk->term, k);
        for (uint32_t j = 0; j < t->nargs; j++) {
            if (uh_has(&c->slots, t->args[j])) {
                (void)uh_put(c->a, &c->bad, t->args[j], 0);
            }
        }
        if (!have[t->block]) {
            entry[t->block] = uh_clone(c->a, full);
            have[t->block] = true;
            continue;
        }
        const UwHash *seen = &entry[t->block];
        for (uint32_t i = 0; i < seen->cap; i++) {
            if (seen->used[i] && !uh_has(full, seen->key[i])) {
                (void)uh_put(c->a, &c->bad, seen->key[i], 0);
            }
        }
        for (uint32_t i = 0; i < full->cap; i++) {
            if (full->used[i] && !uh_has(seen, full->key[i])) {
                (void)uh_put(c->a, &c->bad, full->key[i], 0);
            }
        }
    }
    if (ntargets == 0) {
        /* A `put` left unmatched when the function ends is not followed; a slot parameter goes
         * back to the caller holding its value. */
        for (uint32_t i = 0; i < full->cap; i++) {
            if (full->used[i] && !uh_has(c->params, full->key[i])) {
                (void)uh_put(c->a, &c->bad, full->key[i], 0);
            }
        }
    }
    if (blk->term.kind == MT_RET && blk->term.value != MIR_NONE) {
        (void)uh_put(c->a, &c->bad, blk->term.value, 0);
    }
}

/* The slots of `f` that hold an owned value across calls, each with the type it holds, in
 * `cx->cells`. A slot qualifies when every use is a `put` into it, a `take` out of it, a `load`,
 * or a call whose callee only borrows what it takes from the slot, and each such use sits between
 * a `put` and its `take`. */
void uw_find_cells(UwCx *cx, const MirFunc *f, const UwHash *params) {
    MsArena tmp = {0};
    UwCells c = {.cx = cx, .f = f, .a = &tmp, .params = params};
    c.slots = uh_clone(&tmp, params);
    UW_INSTS(f, b, i, inst) {
        if (inst->op == MOP_Slot && inst->imm.tag == MI_TY && inst->res != MIR_NONE &&
            mir_needs_drop(cx->m, inst->imm.a)) {
            (void)uh_put(&tmp, &c.slots, inst->res, inst->imm.a);
        }
    }
    if (c.slots.n > 0) {
        uw_cells_captured(&c);
        uw_cells_guarded(&c);
        UwHash *entry = MS_NEW_N(&tmp, UwHash, f->nblocks);
        bool *have = MS_NEW_N(&tmp, bool, f->nblocks);
        memset(entry, 0, sizeof(UwHash) * f->nblocks);
        memset(have, 0, f->nblocks);
        entry[0] = uh_clone(&tmp, params);
        have[0] = true;
        MirBlock *order = NULL;
        const uint32_t norder = mir_rpo(&tmp, f, &order);
        for (uint32_t oi = 0; oi < norder; oi++) {
            if (!have[order[oi]]) {
                continue;
            }
            UwHash full = uh_clone(&tmp, &entry[order[oi]]);
            uw_cells_insts(&c, &f->blocks[order[oi]], &full);
            uw_cells_edges(&c, &f->blocks[order[oi]], &full, entry, have);
        }
    }
    cx->cells = (UwHash){0};
    for (uint32_t i = 0; i < c.slots.cap; i++) {
        if (c.slots.used[i] && !uh_has(&c.bad, c.slots.key[i])) {
            (void)uh_put(&cx->fn, &cx->cells, c.slots.key[i], c.slots.val[i]);
        }
    }
    ms_arena_free(&tmp);
}

/* ---- covered_slot_takes ---- */

/* Whether every use of `taken` borrows it or puts it back into `slot`. */
static bool uw_only_borrowed_until_put(const MirModule *m, MsArena *a, const MirFunc *f,
                                       MirValue taken, MirValue slot) {
    for (uint32_t b = 0; b < f->nblocks; b++) {
        const MirBlockData *blk = &f->blocks[b];
        for (uint32_t n = 0; n < blk->ninsts; n++) {
            const MirInst *inst = &blk->insts[n];
            MirMode *modes = MS_NEW_N(a, MirMode, inst->nargs ? inst->nargs : 1);
            mir_arg_modes(m, f, inst, modes);
            for (uint32_t i = 0; i < inst->nargs; i++) {
                if (inst->args[i] != taken) {
                    continue;
                }
                const bool putback = inst->op == MOP_Put && i == 1 && inst->args[0] == slot;
                const bool moves_out = inst->op == MOP_MoveOut || inst->op == MOP_Store ||
                                       inst->op == MOP_Put || inst->op == MOP_CleanupPush ||
                                       inst->op == MOP_TypeFill || inst->op == MOP_ListFill ||
                                       inst->op == MOP_CallInd;
                if (!putback && !(modes[i] == MM_BORROW && !moves_out)) {
                    return false;
                }
            }
        }
        if (blk->term.kind == MT_RET && blk->term.value == taken) {
            return false;
        }
        for (uint32_t k = 0; k < mir_term_ntargets(&blk->term); k++) {
            const MirTarget *t = mir_term_target_const(&blk->term, k);
            for (uint32_t j = 0; j < t->nargs; j++) {
                if (t->args[j] == taken) {
                    return false;
                }
            }
        }
    }
    return true;
}

typedef struct UwCovered {
    const MirModule *m;
    MsArena *a;
    UwHash handle; /* cleanup handle -> slot */
} UwCovered;

static bool uw_slot_push(const UwCovered *c, const MirInst *inst, MirValue *slot) {
    MirTy ty = 0;
    uint32_t g = 0;
    if (!uw_is_func(inst, MOP_CleanupPush, &g) || !uw_slot_close_value(c->m, g, &ty) ||
        inst->nargs == 0) {
        return false;
    }
    *slot = inst->args[0];
    return true;
}

static void uw_covered_step(UwCovered *c, UwHash *covered, const MirInst *inst) {
    MirValue slot = 0;
    uint64_t via = 0;
    if (inst->op == MOP_CleanupRun) {
        *covered = (UwHash){0};
    } else if (inst->op == MOP_CallRt && inst->imm.tag == MI_EXT && inst->nargs == 1) {
        if (c->m->externs[inst->imm.a].role == MR_CLEANUP_DISCARD &&
            uh_get(&c->handle, inst->args[0], &via)) {
            (void)uh_del(covered, via);
        }
    } else if (uw_slot_push(c, inst, &slot)) {
        (void)uh_put(c->a, covered, slot, 0);
    }
}

/* Slots covered on entry to each block: covered on every path that reaches it. */
static void uw_covered_flow(UwCovered *c, const MirFunc *f, const MirBlock *order, uint32_t norder,
                            UwHash *entry, bool *have) {
    have[0] = true;
    for (bool changed = true; changed;) {
        changed = false;
        for (uint32_t oi = 0; oi < norder; oi++) {
            const MirBlockData *blk = &f->blocks[order[oi]];
            if (!have[order[oi]]) {
                continue;
            }
            UwHash covered = uh_clone(c->a, &entry[order[oi]]);
            for (uint32_t n = 0; n < blk->ninsts; n++) {
                uw_covered_step(c, &covered, &blk->insts[n]);
            }
            for (uint32_t k = 0; k < mir_term_ntargets(&blk->term); k++) {
                const MirBlock t = mir_term_target_const(&blk->term, k)->block;
                UwHash next = {0};
                for (uint32_t i = 0; i < covered.cap; i++) {
                    if (covered.used[i] && (!have[t] || uh_has(&entry[t], covered.key[i]))) {
                        (void)uh_put(c->a, &next, covered.key[i], 0);
                    }
                }
                if (!have[t] || !uh_equal_sets(&entry[t], &next)) {
                    changed = true;
                    have[t] = true;
                    entry[t] = next;
                }
            }
        }
    }
}

/* The results of `take`s from a local slot whose scope close is registered and not yet
 * discarded, when the value is only borrowed until it is put back (when `borrowed_only`). The
 * close drops what the slot holds, and the slot still holds the same value while the call runs. */
UwHash uw_covered_slot_takes(MsArena *a, const MirModule *m, const MirFunc *f, bool borrowed_only) {
    UwHash out = {0};
    UwCovered c = {.m = m, .a = a};
    bool any = false;
    UW_INSTS(f, b, i, inst) {
        MirValue slot = 0;
        if (uw_slot_push(&c, inst, &slot)) {
            any = true;
            if (inst->res != MIR_NONE) {
                (void)uh_put(a, &c.handle, inst->res, slot);
            }
        }
    }
    if (!any) {
        return out;
    }
    UwHash *entry = MS_NEW_N(a, UwHash, f->nblocks);
    bool *have = MS_NEW_N(a, bool, f->nblocks);
    memset(entry, 0, sizeof(UwHash) * f->nblocks);
    memset(have, 0, f->nblocks);
    MirBlock *order = NULL;
    const uint32_t norder = mir_rpo(a, f, &order);
    uw_covered_flow(&c, f, order, norder, entry, have);
    for (uint32_t oi = 0; oi < norder; oi++) {
        if (!have[order[oi]]) {
            continue;
        }
        UwHash covered = uh_clone(a, &entry[order[oi]]);
        const MirBlockData *blk = &f->blocks[order[oi]];
        for (uint32_t n = 0; n < blk->ninsts; n++) {
            const MirInst *inst = &blk->insts[n];
            if (inst->op == MOP_Take && inst->nargs > 0 && inst->res != MIR_NONE &&
                uh_has(&covered, inst->args[0]) &&
                (!borrowed_only || uw_only_borrowed_until_put(m, a, f, inst->res, inst->args[0]))) {
                (void)uh_put(a, &out, inst->res, 0);
            }
            uw_covered_step(&c, &covered, inst);
        }
    }
    return out;
}

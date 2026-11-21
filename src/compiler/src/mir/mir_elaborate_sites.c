/* elaborate, cancel exits: the parking calls of a function and what each exit must release. Port of
 * `sites` in cancel_exit.rs. A site is dropped from the function (the function stays hybrid) when a
 * value live at a park has no rule: a value taken from a memory slot or moved out of a field, or a
 * slot handed to a call that can park and may keep it. */
#include <stddef.h>

#include "mir/mir_elaborate.h"

typedef struct ElFwd { MirValue slot, whole; MirTy ty; } ElFwd;

/* What the walk reads about the function before it starts. */
typedef struct ElSiteCx {
    const ElCancel *all;
    const MirModule *m;
    const MirFunc *f;
    ElCx *cx;
    MsArena *a;
    const MirInst **defs; /* the instruction defining each value, or NULL */
    bool *isparam;        /* a block parameter */
    bool *varp;           /* a `var` slot parameter of the function */
    bool *alias;          /* a slot, or a pointer derived from one */
    bool *holed;          /* some part was moved out of it */
    MirValue *taken;      /* the slot each taken value came from */
    MirValue *refilled_by; /* the `var` slot a local slot's value is put back into */
    bool *shielded;       /* per instruction, indexed through `ibase` */
    uint32_t *ibase;
    ElFwd *fwd;
    uint32_t nfwd, cfwd;
    MirBlock *order;
    uint32_t norder;
} ElSiteCx;

/* What a walk knows at a point: the owned values live, the scopes open, the values a
 * `scope.disown` took from their scope, and the slots a `take` emptied and a `put` filled. */
typedef struct ElWalk { ElIds live, scopes, disowned, empty, full; } ElWalk;

static ElWalk es_walk_clone(MsArena *a, const ElWalk *w) {
    return (ElWalk){el_ids_clone(a, &w->live), el_ids_clone(a, &w->scopes),
                    el_ids_clone(a, &w->disowned), el_ids_clone(a, &w->empty),
                    el_ids_clone(a, &w->full)};
}

static bool es_tagged(const ElSiteCx *s, MirValue v) {
    return v < s->cx->nvalues0 && s->cx->tag_scope[v] >= 0;
}

static bool es_owned(const ElSiteCx *s, MirValue v) {
    return mir_needs_drop(s->m, mir_value_ty(s->f, v));
}

static const MirInst *es_def(const ElSiteCx *s, MirValue v) {
    return v < s->f->nvalues ? s->defs[v] : NULL;
}

/* Whether `v` is a `var` slot parameter of `f`: the function takes its value out and puts the final
 * value back by its normal exit. */
static bool es_var_param(const MirFunc *f, MirValue v) {
    for (uint32_t k = 0; k < f->blocks[0].nparams; k++) {
        if (f->blocks[0].params[k].value != v) {
            continue;
        }
        for (uint32_t j = 0; j < f->nnoalias; j++) {
            if (f->noalias[j] == k) {
                return true;
            }
        }
        return false;
    }
    return false;
}

/* Values a cancel exit can drop without knowing more: fresh results and constructions. */
static bool es_droppable(MirOp op) {
    switch (op) {
    case MOP_Call: case MOP_CallRt: case MOP_CallInd: case MOP_CallMethod: case MOP_Clone:
    case MOP_ListLit: case MOP_AltNew: case MOP_OptSome: case MOP_ClosureNew: case MOP_TypeNew:
    case MOP_TypeFill: case MOP_OptNoneOwned: case MOP_AltTake:
        return true;
    default:
        return false;
    }
}

/* The content type of a local slot that holds an owned value no scope owns. */
static bool es_owned_slot(const ElSiteCx *s, MirValue v, MirTy *ty) {
    const MirInst *d = es_def(s, v);
    if (d == NULL || d->op != MOP_Slot || d->imm.tag != MI_TY || es_tagged(s, v)) {
        return false;
    }
    *ty = d->imm.a;
    return mir_needs_drop(s->m, d->imm.a);
}

/* ---- setup ---- */

static void es_setup_defs(ElSiteCx *s) {
    const MirFunc *f = s->f;
    s->defs = MS_NEW_N(s->a, const MirInst *, f->nvalues + 1);
    memset(s->defs, 0, sizeof(MirInst *) * (f->nvalues + 1));
    s->isparam = MS_NEW_N(s->a, bool, f->nvalues + 1);
    memset(s->isparam, 0, f->nvalues + 1);
    s->varp = MS_NEW_N(s->a, bool, f->nvalues + 1);
    memset(s->varp, 0, f->nvalues + 1);
    s->ibase = MS_NEW_N(s->a, uint32_t, f->nblocks + 1);
    uint32_t total = 0;
    for (uint32_t b = 0; b < f->nblocks; b++) {
        s->ibase[b] = total;
        total += f->blocks[b].ninsts;
        for (uint32_t i = 0; i < f->blocks[b].nparams; i++) {
            s->isparam[f->blocks[b].params[i].value] = true;
        }
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            const MirInst *inst = &f->blocks[b].insts[i];
            if (inst->res != MIR_NONE) {
                s->defs[inst->res] = inst;
            }
        }
    }
    for (uint32_t k = 0; k < f->blocks[0].nparams; k++) {
        s->varp[f->blocks[0].params[k].value] = es_var_param(f, f->blocks[0].params[k].value);
    }
    s->shielded = MS_NEW_N(s->a, bool, total + 1);
    memset(s->shielded, 0, total + 1);
}

/* The instructions between a shield enter and its exit in one block: cancellation is held back
 * there, so a call inside is no cancel point. */
static void es_setup_shields(ElSiteCx *s) {
    const MirFunc *f = s->f;
    for (uint32_t b = 0; b < f->nblocks; b++) {
        uint32_t depth = 0;
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            const MirInst *inst = &f->blocks[b].insts[i];
            const MirRole role = inst->op == MOP_CallRt && inst->imm.tag == MI_EXT
                                     ? (MirRole)s->m->externs[inst->imm.a].role
                                     : MR_NONE;
            if (role == MR_SHIELD_ENTER) {
                depth++;
            } else if (role == MR_SHIELD_EXIT) {
                depth -= depth > 0;
            } else if (depth > 0) {
                s->shielded[s->ibase[b] + i] = true;
            }
        }
    }
}

static bool es_is_shielded(const ElSiteCx *s, uint32_t b, uint32_t i) {
    return s->shielded[s->ibase[b] + i];
}

/* A pointer derived from a slot stands for the slot. Deriving one is not an escape: only a
 * parking call or a closure that receives it can take a part out. */
static void es_setup_alias(ElSiteCx *s) {
    const MirFunc *f = s->f;
    s->alias = MS_NEW_N(s->a, bool, f->nvalues + 1);
    memset(s->alias, 0, f->nvalues + 1);
    for (uint32_t v = 0; v < s->cx->nvalues0; v++) {
        s->alias[v] = s->cx->tag_scope[v] >= 0 && s->cx->tag_kind[v] >= 2;
    }
    for (uint32_t k = 0; k < f->blocks[0].nparams; k++) {
        const MirValue p = f->blocks[0].params[k].value;
        s->alias[p] = s->alias[p] || s->varp[p];
    }
    for (uint32_t k = 0; k < s->norder; k++) {
        const MirBlockData *blk = &f->blocks[s->order[k]];
        for (uint32_t i = 0; i < blk->ninsts; i++) {
            const MirInst *inst = &blk->insts[i];
            if ((inst->op == MOP_PtrField || inst->op == MOP_PtrAdd) && inst->res != MIR_NONE &&
                inst->nargs > 0 && s->alias[inst->args[0]]) {
                s->alias[inst->res] = true;
            }
        }
    }
}

/* Whether the call or closure `inst` only borrows the slot at argument `k`: the callee leaves the
 * contents in place for the scope end, or its exits restore a `var` slot as its normal exit does. */
static bool es_borrows_slot(const ElSiteCx *s, const MirInst *inst, uint32_t k) {
    if (inst->op == MOP_Call && inst->imm.tag == MI_FUNC) {
        return uw_flag(&s->all->safe, inst->imm.a, k) ||
               el_restoring_callee(s->all, s->m, s->f, inst, k);
    }
    if (inst->op == MOP_CallInd) {
        return el_restoring_callee(s->all, s->m, s->f, inst, k);
    }
    if (inst->op == MOP_ClosureNew && inst->imm.tag == MI_FUNC) {
        return uw_closure_borrows_capture(s->m, &s->all->safe, s->all->parks, inst->imm.a, k);
    }
    return false;
}

/* A slot handed to a parking callee that only borrows it is fine. A slot handed to anything else
 * that can park or keep it (a closure, a derived pointer) keeps the function hybrid. */
static bool es_slots_stay(const ElSiteCx *s) {
    const MirFunc *f = s->f;
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            const MirInst *inst = &f->blocks[b].insts[i];
            if (es_is_shielded(s, b, i) ||
                !(mir_inst_parks(s->m, s->all->parks, inst) || inst->op == MOP_ClosureNew)) {
                continue;
            }
            for (uint32_t k = 0; k < inst->nargs; k++) {
                const MirValue a = inst->args[k];
                if (s->alias[a] && !((es_tagged(s, a) || s->varp[a]) && es_borrows_slot(s, inst, k))) {
                    return false;
                }
            }
        }
    }
    return true;
}

/* The value each `take` produced and the slot it came from, and the values some part was moved
 * out of. */
static void es_setup_taken(ElSiteCx *s) {
    const MirFunc *f = s->f;
    s->taken = MS_NEW_N(s->a, MirValue, f->nvalues + 1);
    s->refilled_by = MS_NEW_N(s->a, MirValue, f->nvalues + 1);
    s->holed = MS_NEW_N(s->a, bool, f->nvalues + 1);
    memset(s->holed, 0, f->nvalues + 1);
    for (uint32_t v = 0; v <= f->nvalues; v++) {
        s->taken[v] = s->refilled_by[v] = MIR_NONE;
    }
    UW_INSTS(f, b, i, inst) {
        if (inst->op == MOP_Take && inst->res != MIR_NONE && inst->nargs > 0) {
            s->taken[inst->res] = inst->args[0];
        } else if (inst->op == MOP_MoveOut && inst->nargs > 0) {
            const MirInst *g = es_def(s, inst->args[0]);
            if (g != NULL && g->op == MOP_TypeGet && g->nargs > 0) {
                s->holed[g->args[0]] = true;
            }
        }
    }
}

/* A taken value handed to a block parameter that owns it stays the slot's value. */
static bool es_taken_through(ElSiteCx *s, const MirTarget *t, const MirBlockData *to) {
    bool changed = false;
    for (uint32_t k = 0; k < t->nargs && k < to->nparams; k++) {
        const MirValue a = t->args[k], p = to->params[k].value;
        if (to->params[k].mode != MM_MOVE) {
            continue;
        }
        if (s->taken[a] != MIR_NONE && s->taken[p] == MIR_NONE) {
            s->taken[p] = s->taken[a];
            changed = true;
        }
        if (s->holed[a] && !s->holed[p]) {
            s->holed[p] = true;
            changed = true;
        }
    }
    return changed;
}

static void es_setup_taken_flow(ElSiteCx *s) {
    const MirFunc *f = s->f;
    for (bool changed = true; changed;) {
        changed = false;
        for (uint32_t b = 0; b < f->nblocks; b++) {
            const MirTerm *term = &f->blocks[b].term;
            for (uint32_t k = 0; k < mir_term_ntargets(term); k++) {
                const MirTarget *t = mir_term_target_const(term, k);
                changed = es_taken_through(s, t, &f->blocks[t->block]) || changed;
            }
        }
    }
}

static void es_fwd_push(ElSiteCx *s, MirValue slot, MirValue whole, MirTy ty) {
    if (s->nfwd == s->cfwd) {
        const uint32_t cap = s->cfwd ? s->cfwd * 2 : 8;
        ElFwd *grown = MS_NEW_N(s->a, ElFwd, cap);
        if (s->nfwd > 0) {
            memcpy(grown, s->fwd, sizeof(ElFwd) * s->nfwd);
        }
        s->fwd = grown;
        s->cfwd = cap;
    }
    s->fwd[s->nfwd++] = (ElFwd){slot, whole, ty};
}

/* A `var` slot whose value lives in a local slot while the function runs (the variable is handed
 * on to a callee there): the exit takes it back out of that slot. The normal exit refills the slot
 * from one. */
static void es_setup_fwd(ElSiteCx *s) {
    const MirFunc *f = s->f;
    UW_INSTS(f, b, i, inst) {
        if (inst->op != MOP_Put || inst->nargs < 2) {
            continue;
        }
        const MirValue dst = inst->args[0], val = inst->args[1];
        const MirValue from = s->taken[val];
        const MirInst *dd = es_def(s, dst);
        if (from != MIR_NONE && s->varp[from] && dd != NULL && dd->op == MOP_Slot) {
            es_fwd_push(s, from, dst, mir_value_ty(f, val));
        }
        const MirInst *wd = from != MIR_NONE ? es_def(s, from) : NULL;
        if (s->varp[dst] && from != MIR_NONE && wd != NULL && wd->op == MOP_Slot) {
            es_fwd_push(s, dst, from, mir_value_ty(f, val));
            s->refilled_by[from] = dst;
        }
    }
}

/* ---- the refill window ---- */

/* The one window a taken value `v` opens: a part moved out into a local slot, taken back and
 * filled in by a single `type.fill` before the value goes back. Returns that slot, the part's
 * type, and the fill; false when `v` has no such window. */
static bool es_refill_pattern(const ElSiteCx *s, MirValue v, MirValue *w, MirTy *part_ty,
                              const MirInst **fill) {
    const MirFunc *f = s->f;
    const MirInst *moved = NULL, *put = NULL;
    *fill = NULL;
    uint32_t nmoved = 0, nfills = 0, nputs = 0;
    UW_INSTS(f, b, i, inst) {
        const MirInst *g = inst->op == MOP_MoveOut && inst->nargs > 0 ? es_def(s, inst->args[0]) : NULL;
        if (g != NULL && g->op == MOP_TypeGet && g->nargs > 0 && g->args[0] == v) {
            moved = inst;
            nmoved++;
        }
        if (inst->op == MOP_TypeFill && inst->nargs > 0 && inst->args[0] == v) {
            *fill = inst;
            nfills++;
        }
    }
    if (nmoved != 1 || nfills != 1 || (*fill)->nargs < 2) {
        return false;
    }
    UW_INSTS(f, b, i, inst) {
        if (inst->op == MOP_Put && inst->nargs > 1 && moved->res != MIR_NONE &&
            inst->args[1] == moved->res) {
            put = inst;
            nputs++;
        }
    }
    const MirInst *back = nputs == 1 ? es_def(s, (*fill)->args[1]) : NULL;
    if (back == NULL || back->op != MOP_Take || back->nargs == 0 || back->args[0] != put->args[0]) {
        return false;
    }
    *w = put->args[0];
    *part_ty = mir_value_ty(f, (*fill)->args[1]);
    return true;
}

/* Whether the parking call `inst` leaves slot `w` as its normal return would: it is not handed to
 * the call, or every callee it may run restores the `var` slot it gets. */
static bool es_handed_ok(const ElSiteCx *s, const MirInst *inst, MirValue w) {
    for (uint32_t k = 0; k < inst->nargs; k++) {
        if (inst->args[k] == w && !el_restoring_callee(s->all, s->m, s->f, inst, k)) {
            return false;
        }
    }
    return true;
}

/* ---- one site ---- */

typedef struct ElBuild {
    ElSite site;
    uint32_t cputback, crefills, creturns, cdrops, cexplicit;
    ElIds handled;
} ElBuild;

/* Grows `arr` (holding `n` elements of `elem` bytes, room for `*cap`) for one more. */
static void *es_grow(MsArena *a, void *arr, uint32_t n, uint32_t *cap, size_t elem) {
    if (n < *cap) {
        return arr;
    }
    const uint32_t ncap = *cap ? *cap * 2 : 4;
    void *grown = ms_alloc(a, elem * ncap, _Alignof(max_align_t));
    if (n > 0) {
        memcpy(grown, arr, elem * n);
    }
    *cap = ncap;
    return grown;
}

#define EL_GROW(a, arr, n, cap, x)                                                                 \
    do {                                                                                           \
        (arr) = es_grow((a), (arr), (n), &(cap), sizeof *(arr));                                   \
        (arr)[(n)++] = (x);                                                                        \
    } while (0)

/* The value the normal exit puts back into a `var` slot, taken out of the local slot it lived in:
 * the exit puts it there. */
static bool es_try_putback_local(const ElSiteCx *s, ElBuild *bd, const ElWalk *w, MirValue v) {
    const MirValue from = s->taken[v];
    const MirValue slot = from != MIR_NONE ? s->refilled_by[from] : MIR_NONE;
    if (slot == MIR_NONE || !el_ids_has(&w->empty, slot) || el_ids_has(&bd->handled, slot) ||
        s->holed[v]) {
        return false;
    }
    el_ids_add(s->a, &bd->handled, slot);
    EL_GROW(s->a, bd->site.putback, bd->site.nputback, bd->cputback, ((ElPair){slot, v, 0}));
    return true;
}

/* A value taken from a slot a scope owns goes back into it, unless a part was moved out of it (the
 * slot would then hold a hole the scope end drops twice). A slot parameter is not put back: a
 * callee may own what it holds. */
static bool es_try_putback_owned(const ElSiteCx *s, ElBuild *bd, const ElWalk *w, const MirInst *call,
                                 MirValue v) {
    const MirValue slot = s->taken[v];
    if (slot == MIR_NONE || !el_ids_has(&w->empty, slot) ||
        !((es_tagged(s, slot) && el_ids_contains(&w->scopes, (uint32_t)s->cx->tag_scope[slot])) ||
          s->varp[slot])) {
        return false;
    }
    MirValue part_slot = MIR_NONE;
    MirTy part_ty = 0;
    const MirInst *fill = NULL;
    if (es_refill_pattern(s, v, &part_slot, &part_ty, &fill) && el_ids_has(&w->full, part_slot) &&
        s->varp[slot] && es_handed_ok(s, call, part_slot)) {
        el_ids_add(s->a, &bd->handled, slot);
        ElRefill r = {.slot = slot, .whole = v, .part_slot = part_slot, .part_ty = part_ty,
                      .whole_ty = mir_value_ty(s->f, v), .fill = *fill};
        EL_GROW(s->a, bd->site.refills, bd->site.nrefills, bd->crefills, r);
        return true;
    }
    if (s->holed[v]) {
        return false;
    }
    el_ids_add(s->a, &bd->handled, slot);
    EL_GROW(s->a, bd->site.putback, bd->site.nputback, bd->cputback, ((ElPair){slot, v, 0}));
    return true;
}

/* Whether the exit may drop `v` itself: a fresh result, a value taken from a local slot no scope
 * owns, or an entry parameter. */
static bool es_exit_drops(const ElSiteCx *s, MirValue v) {
    const MirInst *d = es_def(s, v);
    if (d == NULL) {
        return s->isparam[v];
    }
    const MirValue slot = s->taken[v];
    const MirInst *sd = slot != MIR_NONE ? es_def(s, slot) : NULL;
    const bool local = sd != NULL && sd->op == MOP_Slot && !es_tagged(s, slot) && !s->holed[v];
    return es_droppable((MirOp)d->op) || local;
}

/* Sorts one live value into what the exit does with it; false when no rule fits. */
static bool es_site_value(const ElSiteCx *s, ElBuild *bd, const ElWalk *w, const MirInst *call,
                          MirValue v) {
    if (v == call->res) {
        return true;
    }
    /* A scope owner releases it at the scope end, if that scope is open here; one that is not is
     * begun by the normal path only at its exits. */
    if (!el_ids_has(&w->disowned, v) && es_tagged(s, v) &&
        el_ids_contains(&w->scopes, (uint32_t)s->cx->tag_scope[v])) {
        return true;
    }
    if (es_try_putback_local(s, bd, w, v) || es_try_putback_owned(s, bd, w, call, v)) {
        return true;
    }
    if (!es_exit_drops(s, v)) {
        return false;
    }
    EL_GROW(s->a, bd->site.explicit_drops, bd->site.nexplicit, bd->cexplicit, v);
    return true;
}

/* A `var` slot parameter the function has taken from must be restored by this exit: only a live
 * taken value (put back or refilled above) can be. */
static bool es_site_returns(const ElSiteCx *s, ElBuild *bd, const ElWalk *w, const MirInst *call) {
    for (uint32_t k = 0; k < w->empty.n; k++) {
        const MirValue slot = w->empty.v[k];
        if (!s->varp[slot] || el_ids_has(&bd->handled, slot)) {
            continue;
        }
        for (uint32_t j = 0; j < s->nfwd; j++) {
            const ElFwd *e = &s->fwd[j];
            if (e->slot == slot && el_ids_has(&w->full, e->whole) && es_handed_ok(s, call, e->whole)) {
                el_ids_add(s->a, &bd->handled, slot);
                EL_GROW(s->a, bd->site.returns, bd->site.nreturns, bd->creturns, ((ElPair){slot, e->whole, e->ty}));
                break;
            }
        }
    }
    for (uint32_t k = 0; k < w->empty.n; k++) {
        if (s->varp[w->empty.v[k]] && !el_ids_has(&bd->handled, w->empty.v[k])) {
            return false;
        }
    }
    return true;
}

/* Local slots still holding a value nothing else releases: the exit takes it out and drops it. */
static void es_site_slot_drops(const ElSiteCx *s, ElBuild *bd, const ElWalk *w) {
    for (uint32_t k = 0; k < w->full.n; k++) {
        const MirValue slot = w->full.v[k];
        bool used = false;
        for (uint32_t j = 0; j < bd->site.nreturns; j++) {
            used = used || bd->site.returns[j].b == slot;
        }
        for (uint32_t j = 0; j < bd->site.nrefills; j++) {
            used = used || bd->site.refills[j].part_slot == slot;
        }
        MirTy ty = 0;
        if (!used && es_owned_slot(s, slot, &ty)) {
            EL_GROW(s->a, bd->site.slot_drops, bd->site.nslot_drops, bd->cdrops, ((ElPair){slot, 0, ty}));
        }
    }
}

/* Builds the site of the parking call at `bi`/`k`; false when the function stays hybrid. */
static bool es_make_site(const ElSiteCx *s, ElWalk *w, uint32_t bi, uint32_t k, ElSites *out) {
    const MirInst *call = &s->f->blocks[bi].insts[k];
    ElBuild bd = {.site = {.block = bi, .inst = k}};
    for (uint32_t j = 0; j < w->live.n; j++) {
        if (!es_site_value(s, &bd, w, call, w->live.v[j])) {
            return false;
        }
    }
    if (!es_site_returns(s, &bd, w, call)) {
        return false;
    }
    es_site_slot_drops(s, &bd, w);
    /* The result a scope takes right after the call is forgotten here, and that scope still ends
     * so a drop flag it carries sees the value gone. */
    ElIds open = el_ids_clone(s->a, &w->scopes);
    if (call->res != MIR_NONE && es_tagged(s, call->res) &&
        !el_ids_contains(&open, (uint32_t)s->cx->tag_scope[call->res])) {
        el_ids_push(s->a, &open, (uint32_t)s->cx->tag_scope[call->res]);
    }
    bd.site.scopes = open.v;
    bd.site.nscopes = open.n;
    uint32_t cap = out->cap;
    EL_GROW(s->a, out->v, out->n, cap, bd.site);
    out->cap = cap;
    return true;
}

/* ---- the walk ---- */

/* The effect of `inst` on what the walk knows: the arguments it consumes, scope markers, slots
 * emptied and filled, and the owned result. */
static void es_walk_inst(const ElSiteCx *s, ElWalk *w, const MirInst *inst) {
    MirMode *modes = MS_NEW_N(s->a, MirMode, inst->nargs + 1);
    mir_arg_modes(s->m, s->f, inst, modes);
    for (uint32_t k = 0; k < inst->nargs; k++) {
        if (modes[k] == MM_MOVE) {
            el_ids_del(&w->live, inst->args[k]);
        }
    }
    switch ((MirOp)inst->op) {
    case MOP_ScopeBegin:
        el_ids_push(s->a, &w->scopes, inst->imm.a);
        break;
    case MOP_ScopeEnd: {
        el_ids_remove_all(&w->scopes, inst->imm.a);
        /* The scope released what it owned. */
        uint32_t kept = 0;
        for (uint32_t j = 0; j < w->live.n; j++) {
            const MirValue v = w->live.v[j];
            if (el_ids_has(&w->disowned, v) || !es_tagged(s, v) ||
                s->cx->tag_scope[v] != (int64_t)inst->imm.a) {
                w->live.v[kept++] = v;
            }
        }
        w->live.n = kept;
        break;
    }
    case MOP_ScopeDisown:
        el_ids_add(s->a, &w->disowned, inst->args[0]);
        break;
    case MOP_ScopeOwn:
        el_ids_del(&w->disowned, inst->args[0]);
        break;
    case MOP_Take:
        el_ids_add(s->a, &w->empty, inst->args[0]);
        el_ids_del(&w->full, inst->args[0]);
        break;
    case MOP_Put:
        el_ids_del(&w->empty, inst->args[0]);
        el_ids_add(s->a, &w->full, inst->args[0]);
        break;
    default:
        break;
    }
    MirMode mode = MM_BORROW;
    if (inst->res != MIR_NONE && mir_result_mode(s->m, s->f, inst, &mode) && mode == MM_MOVE &&
        es_owned(s, inst->res)) {
        el_ids_add(s->a, &w->live, inst->res);
    }
}

/* Whether a callee leaves the slot at argument `k` as its normal path would find it. */
static bool es_leaves_alone(const ElSiteCx *s, const MirInst *inst, uint32_t k) {
    if (inst->op != MOP_Call && inst->op != MOP_CallInd) {
        return false;
    }
    return (inst->op == MOP_Call && inst->imm.tag == MI_FUNC &&
            uw_flag(&s->all->safe, inst->imm.a, k)) ||
           el_restoring_callee(s->all, s->m, s->f, inst, k);
}

/* A local slot holding an owned value no scope owns is released by the exit, when the callees it
 * was handed to left its contents as the normal path would find them. Returns false when the call
 * parks with such a slot some callee may take from. */
static bool es_call_slots(const ElSiteCx *s, ElWalk *w, const MirInst *inst, bool parking) {
    for (uint32_t k = 0; k < inst->nargs; k++) {
        const MirValue a = inst->args[k];
        MirTy ty = 0;
        if (!el_ids_has(&w->full, a) || !es_owned_slot(s, a, &ty) || es_leaves_alone(s, inst, k)) {
            continue;
        }
        if (parking) {
            return false;
        }
        /* A callee that may consume it leaves the slot's contents unknown. */
        el_ids_del(&w->full, a);
    }
    return true;
}

static bool es_walk_block(const ElSiteCx *s, ElWalk *w, uint32_t bi, ElSites *out) {
    const MirBlockData *blk = &s->f->blocks[bi];
    for (uint32_t k = 0; k < blk->ninsts; k++) {
        const MirInst *inst = &blk->insts[k];
        es_walk_inst(s, w, inst);
        const bool last_unreachable = k + 1 == blk->ninsts && blk->term.kind == MT_UNREACHABLE;
        const bool parking = mir_inst_parks(s->m, s->all->parks, inst) && inst->op != MOP_Poll &&
                             !last_unreachable && !es_is_shielded(s, bi, k);
        if (mir_op_is_call(inst->op) && !es_call_slots(s, w, inst, parking)) {
            return false;
        }
        if (parking && !es_make_site(s, w, bi, k, out)) {
            return false;
        }
    }
    return true;
}

/* The state at the start of a successor: what flows along the edge, or, when another edge got
 * there first, what every path agrees on. */
static void es_walk_edge(const ElSiteCx *s, ElWalk *entry, bool *has, const ElWalk *w,
                         const MirTarget *t, const ElIds *after) {
    const MirBlockData *to = &s->f->blocks[t->block];
    if (has[t->block]) {
        ElWalk *known = &entry[t->block];
        uint32_t kept = 0;
        for (uint32_t j = 0; j < known->full.n; j++) {
            if (el_ids_has(&w->full, known->full.v[j])) {
                known->full.v[kept++] = known->full.v[j];
            }
        }
        known->full.n = kept;
        for (uint32_t j = 0; j < w->empty.n; j++) {
            el_ids_add(s->a, &known->empty, w->empty.v[j]);
        }
        return;
    }
    ElWalk e = es_walk_clone(s->a, w);
    e.live = el_ids_clone(s->a, after);
    for (uint32_t k = 0; k < t->nargs && k < to->nparams; k++) {
        if (to->params[k].mode == MM_MOVE) {
            el_ids_del(&e.live, t->args[k]);
        }
    }
    entry[t->block] = e;
    has[t->block] = true;
}

static bool es_walk_function(const ElSiteCx *s, ElSites *out) {
    const MirFunc *f = s->f;
    ElWalk *entry = MS_NEW_N(s->a, ElWalk, f->nblocks + 1);
    bool *has = MS_NEW_N(s->a, bool, f->nblocks + 1);
    memset(entry, 0, sizeof(ElWalk) * (f->nblocks + 1));
    memset(has, 0, f->nblocks + 1);
    has[0] = true;
    for (uint32_t k = 0; k < f->blocks[0].nparams; k++) {
        const MirBlockParam *p = &f->blocks[0].params[k];
        if (p->mode == MM_MOVE && es_owned(s, p->value)) {
            el_ids_add(s->a, &entry[0].live, p->value);
        }
    }
    for (uint32_t r = 0; r < s->norder; r++) {
        const uint32_t bi = s->order[r];
        if (!has[bi]) {
            continue;
        }
        ElWalk w = entry[bi];
        w.live = el_ids_clone(s->a, &entry[bi].live);
        w.scopes = el_ids_clone(s->a, &entry[bi].scopes);
        w.disowned = el_ids_clone(s->a, &entry[bi].disowned);
        w.empty = el_ids_clone(s->a, &entry[bi].empty);
        w.full = el_ids_clone(s->a, &entry[bi].full);
        for (uint32_t k = 0; bi != 0 && k < f->blocks[bi].nparams; k++) {
            const MirBlockParam *p = &f->blocks[bi].params[k];
            if (p->mode == MM_MOVE && es_owned(s, p->value)) {
                el_ids_add(s->a, &w.live, p->value);
            }
        }
        if (!es_walk_block(s, &w, bi, out)) {
            return false;
        }
        const MirTerm *term = &f->blocks[bi].term;
        ElIds after = el_ids_clone(s->a, &w.live);
        if (term->kind == MT_RET && term->value != MIR_NONE) {
            el_ids_del(&after, term->value);
        }
        for (uint32_t k = 0; k < mir_term_ntargets(term); k++) {
            es_walk_edge(s, entry, has, &w, mir_term_target_const(term, k), &after);
        }
    }
    return true;
}

bool el_cancel_sites(const ElCancel *all, const MirModule *m, const MirFunc *f, ElCx *cx,
                     ElSites *out) {
    ElSiteCx s = {.all = all, .m = m, .f = f, .cx = cx, .a = cx->ma};
    s.norder = mir_rpo(s.a, f, &s.order);
    es_setup_defs(&s);
    es_setup_shields(&s);
    es_setup_alias(&s);
    if (!es_slots_stay(&s)) {
        return false;
    }
    es_setup_taken(&s);
    es_setup_taken_flow(&s);
    es_setup_fwd(&s);
    return es_walk_function(&s, out);
}

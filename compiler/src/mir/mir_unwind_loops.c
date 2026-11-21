/* unwind: registers values that stay owned and live across a whole loop once, before the loop,
 * and discards them where the loop is left. Port of `hoist_loops` and its helpers. */
#include "mir/mir_unwind.h"

typedef struct UwLoop {
    uint32_t header;
    uint32_t *body; /* the header first */
    uint32_t nbody, cbody;
} UwLoop;

typedef struct UwChosen {
    uint32_t header;
    MirValue *held;
    uint32_t nheld;
    uint32_t *stable;
    uint32_t nstable;
} UwChosen;

static void uw_body_push(UwCx *cx, UwLoop *l, uint32_t b) {
    if (l->nbody == l->cbody) {
        const uint32_t cap = l->cbody ? l->cbody * 2 : 8;
        uint32_t *grown = MS_NEW_N(&cx->fn, uint32_t, cap);
        if (l->nbody > 0) {
            memcpy(grown, l->body, sizeof(uint32_t) * l->nbody);
        }
        l->body = grown;
        l->cbody = cap;
    }
    l->body[l->nbody++] = b;
}

/* Owned values consumed by an instruction in `body`, or passed on an edge that stays inside it. */
static UwHash uw_consumed_inside(UwCx *cx, const MirFunc *f, const bool *def, uint32_t ndef,
                                 const UwLoop *l) {
    UwHash used = {0};
    for (uint32_t i = 0; i < l->nbody; i++) {
        const MirBlockData *blk = &f->blocks[l->body[i]];
        for (uint32_t n = 0; n < blk->ninsts; n++) {
            const MirInst *inst = &blk->insts[n];
            MirMode *modes = MS_NEW_N(&cx->fn, MirMode, inst->nargs ? inst->nargs : 1);
            mir_arg_modes(cx->m, f, inst, modes);
            for (uint32_t k = 0; k < inst->nargs; k++) {
                if (modes[k] == MM_MOVE && inst->args[k] < ndef && def[inst->args[k]]) {
                    (void)uh_put(&cx->fn, &used, inst->args[k], 0);
                }
            }
        }
        for (uint32_t k = 0; k < mir_term_ntargets(&blk->term); k++) {
            const MirTarget *t = mir_term_target_const(&blk->term, k);
            const MirBlockData *dest = &f->blocks[t->block];
            if (!ms_u32_contains(l->body, l->nbody, t->block)) {
                continue;
            }
            for (uint32_t j = 0; j < t->nargs && j < dest->nparams; j++) {
                if (dest->params[j].mode == MM_MOVE && t->args[j] < ndef && def[t->args[j]]) {
                    (void)uh_put(&cx->fn, &used, t->args[j], 0);
                }
            }
        }
    }
    return used;
}

/* How many times each value is consumed by an instruction or an edge inside the loop, and the
 * list updates that return their own list. */
typedef struct UwChain {
    UwHash sets;  /* list.set result -> its list argument */
    UwHash moves; /* value -> uses taken by move */
} UwChain;

static UwChain uw_chain_facts(UwCx *cx, const MirFunc *f, const UwLoop *l) {
    UwChain c = {0};
    MsArena *a = &cx->fn;
    for (uint32_t i = 0; i < l->nbody; i++) {
        const MirBlockData *blk = &f->blocks[l->body[i]];
        for (uint32_t n = 0; n < blk->ninsts; n++) {
            const MirInst *inst = &blk->insts[n];
            if ((inst->op == MOP_ListSet || inst->op == MOP_ListSetNn || inst->op == MOP_ListSetU) &&
                inst->res != MIR_NONE) {
                (void)uh_put(a, &c.sets, inst->res, inst->args[0]);
            }
            MirMode *modes = MS_NEW_N(a, MirMode, inst->nargs ? inst->nargs : 1);
            mir_arg_modes(cx->m, f, inst, modes);
            for (uint32_t k = 0; k < inst->nargs; k++) {
                uint64_t cnt = 0;
                if (modes[k] == MM_MOVE) {
                    (void)uh_get(&c.moves, inst->args[k], &cnt);
                    (void)uh_put(a, &c.moves, inst->args[k], cnt + 1);
                }
            }
        }
        for (uint32_t k = 0; k < mir_term_ntargets(&blk->term); k++) {
            const MirTarget *t = mir_term_target_const(&blk->term, k);
            const MirBlockData *dest = &f->blocks[t->block];
            if (!ms_u32_contains(l->body, l->nbody, t->block)) {
                continue;
            }
            for (uint32_t j = 0; j < t->nargs && j < dest->nparams; j++) {
                uint64_t cnt = 0;
                if (dest->params[j].mode == MM_MOVE) {
                    (void)uh_get(&c.moves, t->args[j], &cnt);
                    (void)uh_put(a, &c.moves, t->args[j], cnt + 1);
                }
            }
        }
    }
    return c;
}

/* A growable list of values in the function's arena. */
typedef struct UwVec {
    uint32_t *v;
    uint32_t n, cap;
} UwVec;

static void uw_vec_push(UwCx *cx, UwVec *vec, uint32_t x) {
    if (vec->n == vec->cap) {
        const uint32_t cap = vec->cap ? vec->cap * 2 : 8;
        uint32_t *grown = MS_NEW_N(&cx->fn, uint32_t, cap);
        if (vec->n > 0) {
            memcpy(grown, vec->v, sizeof(uint32_t) * vec->n);
        }
        vec->v = grown;
        vec->cap = cap;
    }
    vec->v[vec->n++] = x;
}

/* The chain of `list.set`s from the parameter `p` that latch value `v` passes on, appended to
 * `chain`; false when the latch passes something else. */
static bool uw_chain_walk(UwCx *cx, const UwChain *c, MirValue p, MirValue v, UwVec *chain) {
    while (v != p) {
        uint64_t from = 0;
        if (!uh_get(&c->sets, v, &from)) {
            return false;
        }
        uw_vec_push(cx, chain, v);
        v = (MirValue)from;
    }
    return true;
}

/* Whether header parameter `k` only ever carries one list updated in place: each latch passes
 * the result of a chain of `list.set`s that starts at it, no chain value has another consumer. */
static bool uw_stable_param(UwCx *cx, const MirFunc *f, const UwLoop *l, const UwChain *c,
                            uint32_t k, UwVec *chain) {
    const MirValue p = f->blocks[l->header].params[k].value;
    uint32_t latches = 0;
    uw_vec_push(cx, chain, p);
    for (uint32_t i = 0; i < l->nbody; i++) {
        const MirBlockData *blk = &f->blocks[l->body[i]];
        for (uint32_t t = 0; t < mir_term_ntargets(&blk->term); t++) {
            const MirTarget *tg = mir_term_target_const(&blk->term, t);
            if (tg->block != l->header) {
                continue;
            }
            latches++;
            if (!uw_chain_walk(cx, c, p, tg->args[k], chain)) {
                return false;
            }
        }
    }
    bool once = true, distinct = true;
    for (uint32_t i = 0; i < chain->n; i++) {
        uint64_t cnt = 0;
        once = once && uh_get(&c->moves, chain->v[i], &cnt) && cnt == 1;
        for (uint32_t j = 0; j < i; j++) {
            distinct = distinct && chain->v[i] != chain->v[j];
        }
    }
    return latches > 0 && once && distinct;
}

typedef struct UwStable {
    UwVec params; /* the header parameters that qualify */
    UwVec values; /* the values of their chains */
} UwStable;

/* Header parameters of the loop that only ever carry one list updated in place, and the values of
 * those chains (the parameter and each `list.set` result). `list.set` stores into the list's own
 * storage and returns the same pointer, so one registration made before the loop names the live
 * list for every value of the chain. A `set` drops the old element before the store, so the
 * elements must need no drop. */
static UwStable uw_stable_params(UwCx *cx, const MirFunc *f, const bool *def, uint32_t ndef,
                                 const UwLoop *l) {
    const UwChain c = uw_chain_facts(cx, f, l);
    const MirBlockData *h = &f->blocks[l->header];
    UwStable out = {0};
    for (uint32_t k = 0; k < h->nparams; k++) {
        const MirValue p = h->params[k].value;
        const MirTyData *d = mir_ty_data(cx->m, mir_value_ty(f, p));
        const bool elem_plain = d->kind == MK_LIST && !mir_needs_drop(cx->m, d->elem);
        UwVec chain = {0};
        if (h->params[k].mode != MM_MOVE || p >= ndef || !def[p] || !elem_plain ||
            !uw_stable_param(cx, f, l, &c, k, &chain)) {
            continue;
        }
        uw_vec_push(cx, &out.params, k);
        for (uint32_t i = 0; i < chain.n; i++) {
            uw_vec_push(cx, &out.values, chain.v[i]);
        }
    }
    return out;
}

/* ---- finding the loops ---- */

typedef struct UwHoist {
    UwCx *cx;
    MirFunc *f;
    MirPreds preds;
    const MirBlock *idom;
    uint32_t *holes;
    UwLoop *loops;
    uint32_t nloops;
} UwHoist;

static bool uw_dom(const UwHoist *h, uint32_t a, uint32_t b) {
    if (h->idom[b] == MIR_NONE) {
        return false;
    }
    while (b != a) {
        if (b == 0) {
            return false;
        }
        b = h->idom[b];
    }
    return true;
}

/* The natural loop of header `hd` whose only way in is its header, or an empty body. */
static UwLoop uw_natural_loop(UwHoist *h, uint32_t hd) {
    UwCx *cx = h->cx;
    UwLoop l = {.header = hd};
    UwVec work = {0};
    for (uint32_t i = 0; i < mir_preds_count(&h->preds, hd); i++) {
        const MirBlock p = mir_pred(&h->preds, hd, i);
        if (uw_dom(h, hd, p)) {
            uw_vec_push(cx, &work, p);
        }
    }
    if (work.n == 0) {
        return l;
    }
    uw_body_push(cx, &l, hd);
    while (work.n > 0) {
        const uint32_t b = work.v[--work.n];
        if (ms_u32_contains(l.body, l.nbody, b)) {
            continue;
        }
        uw_body_push(cx, &l, b);
        for (uint32_t i = 0; i < mir_preds_count(&h->preds, b); i++) {
            uw_vec_push(cx, &work, mir_pred(&h->preds, b, i));
        }
    }
    for (uint32_t i = 0; i < l.nbody; i++) {
        const uint32_t b = l.body[i];
        bool ok = h->holes[b] == 0;
        for (uint32_t n = 0; n < h->f->blocks[b].ninsts && ok; n++) {
            ok = h->f->blocks[b].insts[n].op != MOP_MoveOut;
        }
        for (uint32_t k = 0; k < mir_preds_count(&h->preds, b) && ok && b != hd; k++) {
            ok = ms_u32_contains(l.body, l.nbody, mir_pred(&h->preds, b, k));
        }
        if (!ok) {
            l.nbody = 0;
            break;
        }
    }
    return l;
}

/* (header, body) per natural loop whose only way in is its header, outermost first. */
static void uw_find_loops(UwHoist *h) {
    UwCx *cx = h->cx;
    h->loops = MS_NEW_N(&cx->fn, UwLoop, h->f->nblocks);
    h->nloops = 0;
    for (uint32_t hd = 1; hd < h->f->nblocks; hd++) {
        UwLoop l = uw_natural_loop(h, hd);
        if (l.nbody > 0) {
            h->loops[h->nloops++] = l;
        }
    }
    /* A stable sort, longest body first. */
    for (uint32_t i = 1; i < h->nloops; i++) {
        const UwLoop x = h->loops[i];
        uint32_t j = i;
        for (; j > 0 && h->loops[j - 1].nbody < x.nbody; j--) {
            h->loops[j] = h->loops[j - 1];
        }
        h->loops[j] = x;
    }
}

/* ---- choosing what each loop registers ---- */

typedef struct UwBlockSets {
    UwHash *v; /* by block */
    uint32_t n, cap;
} UwBlockSets;

static void uw_sets_push(UwCx *cx, UwBlockSets *s, UwHash x) {
    if (s->n == s->cap) {
        const uint32_t cap = s->cap ? s->cap * 2 : 16;
        UwHash *grown = MS_NEW_N(&cx->fn, UwHash, cap);
        if (s->n > 0) {
            memcpy(grown, s->v, sizeof(UwHash) * s->n);
        }
        s->v = grown;
        s->cap = cap;
    }
    s->v[s->n++] = x;
}

typedef struct UwPick {
    uint32_t header;
    MirValue *held;
    uint32_t nheld;
    UwVec stable;
} UwPick;

/* What the loop `l` registers once: the owned values live into its header and consumed nowhere
 * inside, and the stable list parameters. */
static UwPick uw_pick(UwCx *cx, const MirFunc *f, const bool *def, uint32_t ndef, const UwLoop *l,
                      const OwnerSet *live, const UwHash *closed_by_with, UwBlockSets *covered) {
    UwPick pick = {.header = l->header};
    const UwHash used = uw_consumed_inside(cx, f, def, ndef, l);
    UwStable st = uw_stable_params(cx, f, def, ndef, l);
    uint32_t nlive = 0;
    const uint32_t *vals = owner_to_vec(&cx->fn, live, &nlive);
    pick.held = MS_NEW_N(&cx->fn, MirValue, nlive + 1);
    for (uint32_t i = 0; i < nlive; i++) {
        if (!uh_has(closed_by_with, vals[i]) && !uh_has(&covered->v[l->header], vals[i]) &&
            !uh_has(&used, vals[i]) && !uh_has(&cx->cells, vals[i])) {
            pick.held[pick.nheld++] = vals[i];
        }
    }
    if (pick.nheld == 0 && st.params.n == 0) {
        return pick;
    }
    for (uint32_t i = 0; i < l->nbody; i++) {
        UwHash *set = &covered->v[l->body[i]];
        for (uint32_t k = 0; k < pick.nheld; k++) {
            (void)uh_put(&cx->fn, set, pick.held[k], 0);
        }
        for (uint32_t k = 0; k < st.values.n; k++) {
            (void)uh_put(&cx->fn, set, st.values.v[k], 0);
        }
    }
    pick.stable = st.params;
    return pick;
}

/* ---- rewriting a chosen loop ---- */

typedef struct UwApply {
    UwCx *cx;
    MirFunc *f;
    UwBlockSets *covered;
    UwLoop *bodies;
    uint32_t nbodies;
} UwApply;

static void uw_retarget(MirTerm *t, uint32_t from, uint32_t to) {
    for (uint32_t k = 0; k < mir_term_ntargets(t); k++) {
        MirTarget *tg = mir_term_target(t, k);
        if (tg->block == from) {
            tg->block = to;
        }
    }
}

/* Every other loop that contains `a` and `b` gets `fresh` too. */
static void uw_widen(UwApply *ap, uint32_t li, uint32_t a, uint32_t b, uint32_t fresh) {
    for (uint32_t lj = 0; lj < ap->nbodies; lj++) {
        UwLoop *o = &ap->bodies[lj];
        if (lj != li && ms_u32_contains(o->body, o->nbody, a) && ms_u32_contains(o->body, o->nbody, b)) {
            uw_body_push(ap->cx, o, fresh);
        }
    }
}

static MirInst uw_discard_of(UwApply *ap, MirValue first, MirLoc loc) {
    return uw_discard_inst(ap->cx, ap->f, first, loc);
}

/* Every way out of the loop discards the registrations first. */
static void uw_loop_exits(UwApply *ap, uint32_t li, const UwLoop *body, MirValue first) {
    MirFunc *f = ap->f;
    for (uint32_t i = 0; i < body->nbody; i++) {
        const uint32_t b = body->body[i];
        const MirLoc loc = f->blocks[b].term_loc;
        if (f->blocks[b].term.kind == MT_RET) {
            const MirInst inst = uw_discard_of(ap, first, loc);
            mir_block_insert(ap->cx->m, &f->blocks[b], f->blocks[b].ninsts, &inst);
        }
        const uint32_t nt = mir_term_ntargets(&f->blocks[b].term);
        for (uint32_t slot = 0; slot < nt; slot++) {
            const MirTarget t = *mir_term_target(&f->blocks[b].term, slot);
            if (ms_u32_contains(body->body, body->nbody, t.block)) {
                continue;
            }
            const uint32_t out = mir_new_block(ap->cx->m, f);
            /* The discard runs with the loop's registrations still in place. */
            uw_sets_push(ap->cx, ap->covered, uh_clone(&ap->cx->fn, &ap->covered->v[b]));
            const MirInst inst = uw_discard_of(ap, first, f->blocks[b].term_loc);
            mir_block_insert(ap->cx->m, &f->blocks[out], 0, &inst);
            f->blocks[out].term = (MirTerm){.kind = MT_BR, .value = MIR_NONE, .a = t};
            f->blocks[out].term_loc = f->blocks[b].term_loc;
            MirTarget *x = mir_term_target(&f->blocks[b].term, slot);
            x->block = out;
            x->args = NULL;
            x->nargs = 0;
            uw_widen(ap, li, b, t.block, out);
        }
    }
}

static void uw_apply_one(UwApply *ap, uint32_t li, const UwPick *pick) {
    UwCx *cx = ap->cx;
    MirFunc *f = ap->f;
    MirModule *m = cx->m;
    const uint32_t h = pick->header;
    UwLoop body = ap->bodies[li];
    const MirLoc loc = f->blocks[h].term_loc;
    const MirPreds preds = mir_preds(&cx->fn, f);
    uint32_t *outside = MS_NEW_N(&cx->fn, uint32_t, (size_t)mir_preds_count(&preds, h) + 1);
    uint32_t noutside = 0;
    for (uint32_t i = 0; i < mir_preds_count(&preds, h); i++) {
        if (!ms_u32_contains(body.body, body.nbody, mir_pred(&preds, h, i))) {
            outside[noutside++] = mir_pred(&preds, h, i);
        }
    }
    /* The registering block takes over the header's entry edges. */
    const uint32_t pre = mir_new_block(m, f);
    uw_sets_push(cx, ap->covered, (UwHash){0});
    const uint32_t np = f->blocks[h].nparams;
    MirBlockParam *params = MS_NEW_N(&m->arena, MirBlockParam, np + 1);
    MirValue *args = MS_NEW_N(&m->arena, MirValue, np + 1);
    for (uint32_t k = 0; k < np; k++) {
        const MirBlockParam hp = f->blocks[h].params[k];
        params[k] = (MirBlockParam){mir_new_value(m, f, mir_value_ty(f, hp.value)), hp.mode};
        args[k] = params[k].value;
    }
    MirValue *regs = MS_NEW_N(&cx->fn, MirValue, pick->nheld + pick->stable.n + 1);
    uint32_t nregs = 0;
    for (uint32_t k = 0; k < pick->nheld; k++) {
        regs[nregs++] = pick->held[k];
    }
    for (uint32_t k = 0; k < pick->stable.n; k++) {
        regs[nregs++] = params[pick->stable.v[k]].value;
    }
    UwOut insts = {0};
    MirValue *handles = MS_NEW_N(&cx->fn, MirValue, nregs);
    uw_push_each(cx, f, &insts, regs, nregs, loc, handles);
    f->blocks[pre].params = params;
    f->blocks[pre].nparams = f->blocks[pre].cparams = np;
    f->blocks[pre].insts = insts.v;
    f->blocks[pre].ninsts = insts.n;
    f->blocks[pre].cinsts = insts.cap;
    f->blocks[pre].term = (MirTerm){.kind = MT_BR, .value = MIR_NONE,
                                    .a = {.block = h, .args = args, .nargs = np}};
    f->blocks[pre].term_loc = loc;
    for (uint32_t i = 0; i < noutside; i++) {
        uw_retarget(&f->blocks[outside[i]].term, h, pre);
    }
    for (uint32_t lj = 0; lj < ap->nbodies; lj++) {
        UwLoop *o = &ap->bodies[lj];
        bool enters = false;
        for (uint32_t i = 0; i < noutside; i++) {
            enters = enters || ms_u32_contains(o->body, o->nbody, outside[i]);
        }
        if (lj != li && ms_u32_contains(o->body, o->nbody, h) && enters) {
            uw_body_push(cx, o, pre);
        }
    }
    uw_loop_exits(ap, li, &body, handles[0]);
}

/* Registers values that stay owned and live across a whole loop once, before the loop, and
 * discards them where the loop is left, instead of around every faulting instruction inside.
 *
 * A loop is rewritten when it has a single entry (its header), no moved-out projection, and some
 * owned value that is live into the header and consumed nowhere inside the loop (an exit edge or
 * a `ret` may consume it: the discard comes first). Entry edges are redirected through a new
 * block that registers the values; every exit edge gets a block that discards them, and a `ret`
 * inside the loop discards them just before it. Outer loops are rewritten first.
 *
 * `*hoisted` is, per block, the values a loop registration covers. Returns whether anything
 * changed. */
bool uw_hoist_loops(UwCx *cx, MirFunc *f, bool **def, uint32_t *ndef, const UwHash *closed_by_with,
                    UwHash **hoisted) {
    const uint32_t n = f->nblocks;
    UwBlockSets covered = {0};
    for (uint32_t b = 0; b < n; b++) {
        uw_sets_push(cx, &covered, (UwHash){0});
    }
    uint32_t *holes = uw_hole_states(cx, f);
    UwHash *none = MS_NEW_N(&cx->fn, UwHash, n);
    memset(none, 0, sizeof(UwHash) * n);
    const UwFacts facts = {.cx = cx, .f = f, .owned_def = *def, .nowned = *ndef,
                           .closed_by_with = closed_by_with, .holes = holes, .hoisted = none};
    const UwWalk walk = uw_analyze(&facts);
    MirBlock *rpo = NULL;
    const uint32_t nrpo = mir_rpo(&cx->fn, f, &rpo);
    const MirPreds preds = mir_preds(&cx->fn, f);
    const MirBlock *idom = mir_dominators(&cx->fn, f, rpo, nrpo, &preds);
    UwHoist h = {.cx = cx, .f = f, .preds = preds, .idom = idom, .holes = holes};
    uw_find_loops(&h);
    UwPick *chosen = MS_NEW_N(&cx->fn, UwPick, h.nloops + 1);
    uint32_t nchosen = 0;
    for (uint32_t li = 0; li < h.nloops; li++) {
        const uint32_t hd = h.loops[li].header;
        if (walk.has[hd]) {
            chosen[nchosen++] = uw_pick(cx, f, *def, *ndef, &h.loops[li], &walk.entry[hd],
                                        closed_by_with, &covered);
        }
    }
    UwApply ap = {.cx = cx, .f = f, .covered = &covered, .bodies = h.loops, .nbodies = h.nloops};
    bool changed = false;
    for (uint32_t li = 0; li < nchosen; li++) {
        if (chosen[li].nheld > 0 || chosen[li].stable.n > 0) {
            changed = true;
            uw_apply_one(&ap, li, &chosen[li]);
        }
    }
    uw_own_resize(cx, def, ndef, f->nvalues);
    *hoisted = covered.v;
    return changed;
}

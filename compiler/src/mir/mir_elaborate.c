/* elaborate: places the scope-exit cleanup of every Raw function. Port of elaborate.rs (see
 * mir_elaborate.h); this file reads the scope markers, runs the move-state dataflow and drives the
 * emitter. */
#include "mir/mir_elaborate.h"

#define EL_DISCARD "msrt_cleanup_discard"
#define EL_CANCEL "msrt_cleanup_cancel"
#define EL_SHIELD_ENTER "msrt_shield_enter"
#define EL_SHIELD_EXIT "msrt_shield_exit"

static bool el_is_raw(const MirFunc *f) {
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            const MirOp op = (MirOp)f->blocks[b].insts[i].op;
            if (op == MOP_ScopeBegin || op == MOP_ScopeOwn || op == MOP_ScopeEnd ||
                op == MOP_ScopeDisown || op == MOP_ScopeMark) {
                return true;
            }
        }
    }
    return false;
}

/* ---- scope tags ---- */

static void el_list_push(MsArena *a, ElList *l, MirValue v) {
    if (l->n == l->cap) {
        const uint32_t cap = l->cap ? l->cap * 2 : 4;
        MirValue *grown = MS_NEW_N(a, MirValue, cap);
        if (l->n > 0) {
            memcpy(grown, l->v, sizeof(MirValue) * l->n);
        }
        l->v = grown;
        l->cap = cap;
    }
    l->v[l->n++] = v;
}

static void el_list_remove(ElList *l, MirValue v) {
    uint32_t kept = 0;
    for (uint32_t i = 0; i < l->n; i++) {
        if (l->v[i] != v) {
            l->v[kept++] = l->v[i];
        }
    }
    l->n = kept;
}

static bool el_scope_op(const MirInst *i) {
    return i->op == MOP_ScopeBegin || i->op == MOP_ScopeOwn || i->op == MOP_ScopeEnd;
}

/* Sizes the per-scope tables and reads each scope's parent from its `scope.begin`. */
static void el_scopes(ElCx *cx, const MirFunc *f) {
    uint32_t top = 0;
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            const MirInst *inst = &f->blocks[b].insts[i];
            if (el_scope_op(inst) && inst->imm.a + 1 > top) {
                top = inst->imm.a + 1;
            }
        }
    }
    cx->nscopes = top;
    cx->owners = MS_NEW_N(cx->ma, ElList, top + 1);
    memset(cx->owners, 0, sizeof(ElList) * (top + 1));
    cx->parent = MS_NEW_N(cx->ma, int64_t, top + 1);
    cx->has_parent = MS_NEW_N(cx->ma, bool, top + 1);
    memset(cx->has_parent, 0, top + 1);
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            const MirInst *inst = &f->blocks[b].insts[i];
            if (inst->op == MOP_ScopeBegin) {
                cx->parent[inst->imm.a] = (int64_t)inst->imm.b - 1;
                cx->has_parent[inst->imm.a] = true;
            }
        }
    }
}

/* Whether scope `outer` encloses scope `inner`. */
static bool el_is_ancestor(const ElCx *cx, int64_t outer, int64_t inner) {
    int64_t cur = (uint64_t)inner < cx->nscopes && cx->has_parent[inner] ? cx->parent[inner] : -1;
    while (cur >= 0) {
        if (cur == outer) {
            return true;
        }
        cur = (uint64_t)cur < cx->nscopes && cx->has_parent[cur] ? cx->parent[cur] : -1;
    }
    return false;
}

typedef struct ElDom {
    const MirBlock *idom; /* NULL until a check needs it */
} ElDom;

static bool el_dominates(const MirBlock *idom, MirBlock def, MirBlock at) {
    for (;;) {
        if (at == def) {
            return true;
        }
        if (at == 0 || idom[at] == MIR_NONE || idom[at] == at) {
            return false;
        }
        at = idom[at];
    }
}

/* Whether the definition of `v` dominates every block that ends `scope`, so the scope can still
 * hold `v` there on every path. */
static bool el_defined_before_every_end(ElCx *cx, ElDom *dom, MirValue v, int64_t scope) {
    const MirFunc *f = cx->f;
    MirBlock def = MIR_NONE;
    for (uint32_t b = 0; b < f->nblocks && def == MIR_NONE; b++) {
        for (uint32_t i = 0; i < f->blocks[b].nparams; i++) {
            if (f->blocks[b].params[i].value == v) {
                def = b;
            }
        }
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            if (f->blocks[b].insts[i].res == v) {
                def = b;
            }
        }
    }
    if (def == MIR_NONE) {
        return true;
    }
    if (dom->idom == NULL) {
        MirBlock *order;
        const uint32_t n = mir_rpo(cx->ma, f, &order);
        const MirPreds preds = mir_preds(cx->ma, f);
        dom->idom = mir_dominators(cx->ma, f, order, n, &preds);
    }
    for (uint32_t b = 0; b < f->nblocks; b++) {
        bool ends = false;
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            ends = ends || (f->blocks[b].insts[i].op == MOP_ScopeEnd &&
                            (int64_t)f->blocks[b].insts[i].imm.a == scope);
        }
        if (ends && !el_dominates(dom->idom, def, b)) {
            return false;
        }
    }
    return true;
}

/* `scope.own S K v`: tags `v` with its scope and kind. A value an inner scope owns again (a
 * statement's temporary holding a moved local) stays the outer scope's: the path that never reaches
 * the inner scope still holds it there, and the inner scope's end finds it moved. That holds only
 * while the outer scope can still hold it at its own end: a value defined inside a branch and
 * handed to a binding there (`var kept = outer`) belongs to the inner scope, which must drop it
 * where the branch ends. */
static void el_tag_owner(ElCx *cx, ElDom *dom, const MirBits *disowned, const MirInst *inst) {
    const MirValue v = inst->args[0];
    const int64_t scope = inst->imm.a, kind = inst->imm.b;
    if (el_tagged(cx, v)) {
        const int64_t old = cx->tag_scope[v];
        if (old != scope && el_is_ancestor(cx, old, scope) &&
            (!mir_bits_test(disowned, v) || el_defined_before_every_end(cx, dom, v, old))) {
            return;
        }
        /* A value owned again by a later scope leaves the earlier scope's list. */
        el_list_remove(&cx->owners[old], v);
    }
    cx->tag_scope[v] = scope;
    cx->tag_kind[v] = kind;
    el_list_push(cx->ma, &cx->owners[scope], v);
}

/* Whether `v` is disowned in block `b` or in the blocks that lead to it without a join. */
static bool el_disowned_before(const ElCx *cx, const MirPreds *preds, MirBits *seen, MirBlock b,
                               MirValue v) {
    const MirFunc *f = cx->f;
    memset(seen->words, 0, sizeof(uint64_t) * ((seen->nbits + 63) / 64));
    MirBlock cur = b;
    while (!mir_bits_test(seen, cur)) {
        mir_bits_set(seen, cur);
        for (uint32_t i = 0; i < f->blocks[cur].ninsts; i++) {
            const MirInst *inst = &f->blocks[cur].insts[i];
            if (inst->op == MOP_ScopeDisown && inst->args[0] == v) {
                return true;
            }
        }
        if (mir_preds_count(preds, cur) != 1) {
            return false;
        }
        cur = mir_pred(preds, cur, 0);
    }
    return false;
}

/* A value that flows through a moving block parameter keeps its scope. */
static void el_tag_params(ElCx *cx) {
    const MirFunc *f = cx->f;
    const MirPreds preds = mir_preds(cx->ma, f);
    MirBits seen = mir_bits_new(cx->ma, f->nblocks);
    for (bool changed = true; changed;) {
        changed = false;
        for (uint32_t b = 0; b < f->nblocks; b++) {
            const MirTerm *term = &f->blocks[b].term;
            for (uint32_t t = 0; t < mir_term_ntargets(term); t++) {
                const MirTarget *target = mir_term_target_const(term, t);
                const MirBlockData *dest = &f->blocks[target->block];
                for (uint32_t k = 0; k < target->nargs && k < dest->nparams; k++) {
                    const MirValue a = target->args[k], p = dest->params[k].value;
                    /* A disowned value left its scope: the parameter it feeds is the new owner's.
                     * The disown may sit in a block this one follows without a join. */
                    if (dest->params[k].mode != MM_MOVE || !el_tagged(cx, a) ||
                        el_disowned_before(cx, &preds, &seen, b, a)) {
                        continue;
                    }
                    const bool fresh = !el_tagged(cx, p);
                    cx->tag_scope[p] = cx->tag_scope[a];
                    cx->tag_kind[p] = cx->tag_kind[a];
                    if (fresh) {
                        el_list_push(cx->ma, &cx->owners[cx->tag_scope[a]], p);
                        changed = true;
                    }
                }
            }
        }
    }
}

void el_tags(ElCx *cx) {
    const MirFunc *f = cx->f;
    cx->tag_scope = MS_NEW_N(cx->ma, int64_t, f->nvalues + 1);
    cx->tag_kind = MS_NEW_N(cx->ma, int64_t, f->nvalues + 1);
    for (uint32_t i = 0; i <= f->nvalues; i++) {
        cx->tag_scope[i] = -1;
        cx->tag_kind[i] = -1;
    }
    cx->nvalues0 = f->nvalues;
    el_scopes(cx, f);
    MirBits disowned = mir_bits_new(cx->ma, f->nvalues);
    ElDom dom = {0};
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            const MirInst *inst = &f->blocks[b].insts[i];
            if (inst->op == MOP_ScopeDisown) {
                mir_bits_set(&disowned, inst->args[0]);
            }
            if (inst->op == MOP_ScopeOwn) {
                el_tag_owner(cx, &dom, &disowned, inst);
            }
        }
    }
    el_tag_params(cx);
}

/* ---- flags ---- */

/* The owners some block entry holds in a state that needs a flag. */
static UwHash el_flagged_owners(ElCx *cx, const ElState *entry, const bool *has) {
    UwHash maybe = {0};
    for (uint32_t b = 0; b < cx->f->nblocks; b++) {
        if (!has[b]) {
            continue;
        }
        uint32_t n;
        const ElOwner *odd = el_odd(cx, &entry[b], &n);
        for (uint32_t i = 0; i < n; i++) {
            if (odd[i].st == EL_MAYBE || odd[i].st == EL_CLOSED_OR_MOVED) {
                uh_put(cx->ma, &maybe, odd[i].v, 0);
            }
        }
    }
    return maybe;
}

/* The key of the closed-by-hand flag of each owner a join leaves possibly closed. */
static UwHash el_closed_keys(ElCx *cx, MirModule *m, MirFunc *f, const ElState *entry,
                             const bool *has) {
    UwHash ckeys = {0};
    for (uint32_t b = 0; b < f->nblocks; b++) {
        uint32_t n;
        const ElOwner *odd = has[b] ? el_odd(cx, &entry[b], &n) : NULL;
        for (uint32_t i = 0; odd != NULL && i < n; i++) {
            if ((odd[i].st == EL_MAYBE_CLOSED || odd[i].st == EL_CLOSED_OR_MOVED) &&
                !uh_has(&ckeys, odd[i].v)) {
                uh_put(cx->ma, &ckeys, odd[i].v, mir_new_value(m, f, MIR_BOOL));
            }
        }
    }
    return ckeys;
}

/* A slot owner refilled after a move, or handed on to another scope, registers a new cleanup entry:
 * the entry a later move cancels travels in a block parameter under a key of its own. */
static UwHash el_handle_keys(ElCx *cx, MirModule *m, MirFunc *f) {
    UwHash hkeys = {0};
    UwHash owned_at = {0};
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            const MirInst *inst = &f->blocks[b].insts[i];
            uint64_t n = 0;
            if (inst->op == MOP_ScopeOwn) {
                uh_get(&owned_at, inst->args[0], &n);
                uh_put(cx->ma, &owned_at, inst->args[0], n + 1);
            }
            if (inst->op == MOP_ScopeMark && inst->imm.tag == MI_INT && inst->imm.i == 2 &&
                !uh_has(&hkeys, inst->args[0])) {
                uh_put(cx->ma, &hkeys, inst->args[0], mir_new_value(m, f, MIR_INT));
            }
        }
    }
    uint64_t *owners = uh_keys(cx->ma, &owned_at);
    for (uint32_t i = 0; i < owned_at.n; i++) {
        uint64_t n = 0;
        uh_get(&owned_at, owners[i], &n);
        if (n > 1 && el_is_slot_owner(cx, (MirValue)owners[i]) && !uh_has(&hkeys, owners[i])) {
            uh_put(cx->ma, &hkeys, owners[i], mir_new_value(m, f, MIR_INT));
        }
    }
    return hkeys;
}

static void el_fparam_push(ElCx *cx, ElFparams *fp, MirValue key, MirValue param) {
    if (fp->n == fp->cap) {
        const uint32_t cap = fp->cap ? fp->cap * 2 : 4;
        MirValue *keys = MS_NEW_N(cx->ma, MirValue, cap);
        MirValue *params = MS_NEW_N(cx->ma, MirValue, cap);
        if (fp->n > 0) {
            memcpy(keys, fp->key, sizeof(MirValue) * fp->n);
            memcpy(params, fp->param, sizeof(MirValue) * fp->n);
        }
        fp->key = keys;
        fp->param = params;
        fp->cap = cap;
    }
    fp->key[fp->n] = key;
    fp->param[fp->n++] = param;
}

static void el_add_fparam(ElCx *cx, MirModule *m, MirFunc *f, uint32_t b, ElFparams *fp,
                          MirValue key, MirTy ty) {
    const MirValue p = mir_new_value(m, f, ty);
    const MirBlockParam bp = {p, MM_BORROW};
    MirBlockData *blk = &f->blocks[b];
    MIR_PUSH(m, blk->params, blk->nparams, blk->cparams, MirBlockParam, bp);
    el_fparam_push(cx, fp, key, p);
}

/* The flag parameters of every block: one per flagged owner that is live on entry. Only an owner
 * with a flag, a closed flag or a handle key has a parameter, so a block looks at those instead of
 * every owner live on entry. */
static void el_flag_params(ElCx *cx, MirModule *m, MirFunc *f, const ElEm *em, const MirBlock *order,
                           uint32_t norder, const ElState *entry, const bool *has, ElFparams *out) {
    UwHash all = {0};
    const UwHash *sets[3] = {&em->flagged, &em->ckeys, &em->hkeys};
    for (uint32_t s = 0; s < 3; s++) {
        uint64_t *keys = uh_keys(cx->ma, sets[s]);
        for (uint32_t i = 0; i < sets[s]->n; i++) {
            uh_put(cx->ma, &all, keys[i], 0);
        }
    }
    uint64_t *candidates = uh_keys(cx->ma, &all);
    for (uint32_t k = 0; k < norder; k++) {
        const MirBlock b = order[k];
        if (!has[b]) {
            continue;
        }
        ElOwner *live = MS_NEW_N(cx->ma, ElOwner, all.n + 1);
        uint32_t n = 0;
        for (uint32_t i = 0; i < all.n; i++) {
            ElOwner o = {0, (MirValue)candidates[i], 0};
            if (el_position_of(&entry[b], o.v, &o.pos) && el_get(&entry[b], o.v, &o.st)) {
                live[n++] = o;
            }
        }
        qsort(live, n, sizeof *live, el_by_position_cmp);
        for (uint32_t i = 0; i < n; i++) {
            uint64_t key;
            if (uh_has(&em->flagged, live[i].v)) {
                el_add_fparam(cx, m, f, b, &out[b], live[i].v, MIR_BOOL);
            }
            if ((live[i].st == EL_MAYBE_CLOSED || live[i].st == EL_CLOSED_OR_MOVED) &&
                uh_get(&em->ckeys, live[i].v, &key)) {
                el_add_fparam(cx, m, f, b, &out[b], (MirValue)key, MIR_BOOL);
            }
            if (uh_get(&em->hkeys, live[i].v, &key)) {
                el_add_fparam(cx, m, f, b, &out[b], (MirValue)key, MIR_INT);
            }
        }
    }
}

/* ---- one function ---- */

/* The values a `scope.disown` names. */
static UwHash el_disowned_values(ElCx *cx, const MirFunc *f) {
    UwHash set = {0};
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            if (f->blocks[b].insts[i].op == MOP_ScopeDisown) {
                uh_put(cx->ma, &set, f->blocks[b].insts[i].args[0], 0);
            }
        }
    }
    return set;
}

/* The move state on entry to every block. A flagged owner that is disowned before the op consuming
 * it needs the moved state, so the exits after the move do not release it again. */
static bool el_states(ElCx *cx, const MirBlock *order, uint32_t norder, ElState *entry, bool *has,
                      UwHash *flagged) {
    if (!el_analyze(cx, order, norder, entry, has)) {
        return false;
    }
    UwHash maybe = el_flagged_owners(cx, entry, has);
    UwHash disowned = el_disowned_values(cx, cx->f);
    uint64_t *keys = uh_keys(cx->ma, &maybe);
    for (uint32_t i = 0; i < maybe.n; i++) {
        if (uh_has(&disowned, keys[i])) {
            uh_put(cx->ma, &cx->disown_moves, keys[i], 0);
        }
    }
    if (cx->disown_moves.n > 0) {
        if (!el_analyze(cx, order, norder, entry, has)) {
            return false;
        }
        maybe = el_flagged_owners(cx, entry, has);
    }
    *flagged = maybe;
    return true;
}

bool el_function(ElCx *cx, MirModule *m, MirFunc *f) {
    cx->f = f;
    el_tags(cx);
    if (cx->all != NULL && !f->explicit_cancel) {
        el_cancel_convert(cx->all, m, f, cx);
    }
    MirBlock *order;
    const uint32_t norder = mir_rpo(cx->ma, f, &order);
    ElState *entry = MS_NEW_N(cx->ma, ElState, f->nblocks + 1);
    bool *has = MS_NEW_N(cx->ma, bool, f->nblocks + 1);
    ElEm em = {.cx = cx, .m = m, .f = f, .pending = MIR_NONE};
    if (!el_states(cx, order, norder, entry, has, &em.flagged)) {
        return false;
    }
    em.ckeys = el_closed_keys(cx, m, f, entry, has);
    em.hkeys = el_handle_keys(cx, m, f);
    ElFparams *fparams = MS_NEW_N(cx->ma, ElFparams, f->nblocks + 1);
    memset(fparams, 0, sizeof(ElFparams) * (f->nblocks + 1));
    el_flag_params(cx, m, f, &em, order, norder, entry, has, fparams);
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            em.counts_depth = em.counts_depth || f->blocks[b].insts[i].op == MOP_DepthEnter;
        }
    }
    for (uint32_t k = 0; k < norder; k++) {
        if (has[order[k]] && !el_emit_block(&em, order[k], &entry[order[k]], fparams)) {
            return false;
        }
    }
    return true;
}

/* ---- the pass ---- */

static void el_report(const MirModule *m, const MirFunc *f, const char *message, MsBuf *error) {
    const MsStr name = ms_name(&m->names, f->name);
    ms_buf_printf(error, "%.*s: %s", (int)name.len, name.ptr, message);
}

/* `scratch` holds what the rewrite of one function needs and is reset on return. */
static bool el_run_one(MirModule *m, uint32_t fi, const ElCx *shared, MsArena *scratch, MsBuf *error) {
    ElCx cx = *shared;
    cx.ma = scratch;
    cx.m = m;
    cx.fi = fi;
    /* The function is out of the module while it is rewritten; a stand-in with its signature stays,
     * so a recursive call still reads which arguments the callee consumes. */
    MirFunc f = m->funcs[fi];
    m->funcs[fi] = mir_func_stand_in(m, &f);
    const bool ok = el_function(&cx, m, &f);
    m->funcs[fi] = f;
    if (!ok) {
        el_report(m, &f, cx.err, error);
    }
    ms_arena_reset(scratch);
    return ok;
}

/* Declares the runtime entries scope closing calls. */
static void el_declare_runtime(MirModule *m, ElCx *shared) {
    const MirTy one = MIR_INT;
    shared->discard = mir_extern_get(m, EL_DISCARD, &one, 1, MIR_VOID, true, MR_CLEANUP_DISCARD);
    shared->cancel = mir_extern_get(m, EL_CANCEL, &one, 1, MIR_VOID, true, MR_NONE);
    shared->shield_enter = mir_extern_get(m, EL_SHIELD_ENTER, NULL, 0, MIR_VOID, true, MR_SHIELD_ENTER);
    shared->shield_exit = mir_extern_get(m, EL_SHIELD_EXIT, NULL, 0, MIR_VOID, true, MR_SHIELD_EXIT);
}

/* Whether any Raw function closes by hand, and whether any is Raw at all. */
static bool el_scan(const MirModule *m, bool *closes) {
    bool any_raw = false;
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        const MirFunc *f = &m->funcs[fi];
        const bool raw = el_is_raw(f);
        any_raw = any_raw || raw;
        for (uint32_t b = 0; raw && b < f->nblocks; b++) {
            for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
                const MirInst *inst = &f->blocks[b].insts[i];
                *closes = *closes || (inst->op == MOP_ScopeOwn && inst->imm.b >= 1);
            }
        }
    }
    return any_raw;
}

/* Runs the pass over every function that needs it, callee first when cancel exits are built. */
static bool el_run_all(MirModule *m, const ElCx *shared, MsBuf *error) {
    const ElCancel *all = shared->all;
    MsArena arena = {0}, scratch = {0};
    const uint32_t *order = el_callee_first(&arena, m, all);
    const uint32_t nfuncs = m->nfuncs;
    bool ok = true;
    if (all != NULL) {
        el_settle_restores(shared->all, m, order, shared);
    }
    for (uint32_t k = 0; k < nfuncs && ok; k++) {
        const uint32_t fi = order[k];
        /* A function with `var` slots gets cancel exits even without owners of its own. */
        const bool slots = all != NULL && m->funcs[fi].nnoalias > 0;
        if (!el_is_raw(&m->funcs[fi]) && !slots) {
            continue;
        }
        const bool restores = all != NULL && all->restores[fi];
        ok = el_run_one(m, fi, shared, &scratch, error);
        if (ok && slots && all->restores[fi] != restores) {
            const MirFunc *f = &m->funcs[fi];
            el_report(m, f, "cancel exits disagree with the restore set", error);
            ok = false;
        }
    }
    ms_arena_free(&arena);
    ms_arena_free(&scratch);
    return ok;
}

bool mir_elaborate_with(MirModule *m, bool cancel_exits, MsBuf *error) {
    ElCx shared = {.close = MIR_NONE, .discard = MIR_NONE, .cancel = MIR_NONE,
                   .shield_enter = MIR_NONE, .shield_exit = MIR_NONE};
    shared.close = m->close;
    if (cancel_exits) {
        shared.all = el_cancel_new(m);
    }
    bool closes = false;
    bool ok = true;
    if (el_scan(m, &closes)) {
        if (closes) {
            el_declare_runtime(m, &shared);
        }
        ok = el_run_all(m, &shared, error);
        /* The helper references are consumed: later passes renumber functions. */
        for (uint32_t fi = 0; ok && fi < m->nfuncs; fi++) {
            m->funcs[fi].has_slot_result = false;
            m->funcs[fi].has_close_exit = false;
        }
    }
    el_cancel_free(shared.all);
    return ok;
}

bool mir_elaborate(MirModule *m, MsBuf *error) { return mir_elaborate_with(m, false, error); }

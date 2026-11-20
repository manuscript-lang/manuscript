/* elaborate, cancel exits: what the conversion reads about the whole module, the order functions
 * convert in, and the fixpoint of which functions restore their `var` slots. Port of the module
 * half of cancel_exit.rs; the walk is in mir_elaborate_sites.c, the rewrite in
 * mir_elaborate_convert.c. */
#include "mir/mir_elaborate.h"

/* ---- ids ---- */

static uint32_t eid_lower(const ElIds *s, uint32_t x) {
    uint32_t lo = 0, hi = s->n;
    while (lo < hi) {
        const uint32_t mid = lo + (hi - lo) / 2;
        if (s->v[mid] < x) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    return lo;
}

bool el_ids_has(const ElIds *s, uint32_t x) {
    const uint32_t at = eid_lower(s, x);
    return at < s->n && s->v[at] == x;
}

void el_ids_push(MsArena *a, ElIds *s, uint32_t x) {
    if (s->n == s->cap) {
        const uint32_t cap = s->cap ? s->cap * 2 : 4;
        uint32_t *grown = MS_NEW_N(a, uint32_t, cap);
        if (s->n > 0) {
            memcpy(grown, s->v, sizeof(uint32_t) * s->n);
        }
        s->v = grown;
        s->cap = cap;
    }
    s->v[s->n++] = x;
}

void el_ids_add(MsArena *a, ElIds *s, uint32_t x) {
    const uint32_t at = eid_lower(s, x);
    if (at < s->n && s->v[at] == x) {
        return;
    }
    el_ids_push(a, s, x);
    memmove(&s->v[at + 1], &s->v[at], sizeof(uint32_t) * (s->n - 1 - at));
    s->v[at] = x;
}

void el_ids_del(ElIds *s, uint32_t x) {
    const uint32_t at = eid_lower(s, x);
    if (at < s->n && s->v[at] == x) {
        memmove(&s->v[at], &s->v[at + 1], sizeof(uint32_t) * (s->n - 1 - at));
        s->n--;
    }
}

ElIds el_ids_clone(MsArena *a, const ElIds *s) {
    ElIds out = {0};
    if (s->n > 0) {
        out.v = MS_NEW_N(a, uint32_t, s->n);
        memcpy(out.v, s->v, sizeof(uint32_t) * s->n);
        out.n = out.cap = s->n;
    }
    return out;
}

bool el_ids_contains(const ElIds *s, uint32_t x) {
    for (uint32_t i = 0; i < s->n; i++) {
        if (s->v[i] == x) {
            return true;
        }
    }
    return false;
}

void el_ids_remove_all(ElIds *s, uint32_t x) {
    uint32_t kept = 0;
    for (uint32_t i = 0; i < s->n; i++) {
        if (s->v[i] != x) {
            s->v[kept++] = s->v[i];
        }
    }
    s->n = kept;
}

/* ---- the module context ---- */

/* Orders by type, then function, then first sight, so a duplicate follows the first. */
static int ek_target_by_func(const void *x, const void *y) {
    const ElTarget *a = x, *b = y;
    if (a->ty != b->ty) {
        return a->ty < b->ty ? -1 : 1;
    }
    if (a->func != b->func) {
        return a->func < b->func ? -1 : 1;
    }
    return a->seq < b->seq ? -1 : a->seq > b->seq;
}

static int ek_target_by_seq(const void *x, const void *y) {
    const ElTarget *a = x, *b = y;
    if (a->ty != b->ty) {
        return a->ty < b->ty ? -1 : 1;
    }
    return a->seq < b->seq ? -1 : a->seq > b->seq;
}

/* The functions a closure value of each function type may run: every `closure.new` result of that
 * type, each once, in the order they were first made. */
static void ek_closure_map(ElCancel *all, const MirModule *m) {
    uint32_t total = 0;
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        UW_INSTS(&m->funcs[fi], b, i, inst) {
            total += inst->op == MOP_ClosureNew && inst->imm.tag == MI_FUNC && inst->res != MIR_NONE;
        }
    }
    ElTarget *all_t = MS_NEW_N(&all->arena, ElTarget, total ? total : 1);
    uint32_t n = 0;
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        const MirFunc *f = &m->funcs[fi];
        UW_INSTS(f, b, i, inst) {
            if (inst->op == MOP_ClosureNew && inst->imm.tag == MI_FUNC && inst->res != MIR_NONE) {
                all_t[n] = (ElTarget){mir_value_ty(f, inst->res), n, inst->imm.a};
                n++;
            }
        }
    }
    qsort(all_t, n, sizeof *all_t, ek_target_by_func);
    uint32_t kept = 0;
    for (uint32_t i = 0; i < n; i++) {
        if (kept == 0 || all_t[kept - 1].ty != all_t[i].ty || all_t[kept - 1].func != all_t[i].func) {
            all_t[kept++] = all_t[i];
        }
    }
    qsort(all_t, kept, sizeof *all_t, ek_target_by_seq);
    all->closures = all_t;
    all->nclosures = kept;
}

/* The targets of closures of type `ty`: a run of `closures`. */
static const ElTarget *ek_targets_of(const ElCancel *all, MirTy ty, uint32_t *n) {
    uint32_t lo = 0, hi = all->nclosures;
    while (lo < hi) {
        const uint32_t mid = lo + (hi - lo) / 2;
        if (all->closures[mid].ty < ty) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    uint32_t end = lo;
    while (end < all->nclosures && all->closures[end].ty == ty) {
        end++;
    }
    *n = end - lo;
    return &all->closures[lo];
}

static void ek_cancel_externs(ElCancel *all, MirModule *m) {
    MirTy int_param = MIR_INT;
    all->unwinding = mir_extern_get(m, "msrt_unwinding", NULL, 0, MIR_UINT8, true, MR_UNWINDING);
    all->base = mir_extern_get(m, "msrt_cleanup_base", NULL, 0, MIR_INT, true, MR_NONE);
    all->truncate = mir_extern_get(m, "msrt_cleanup_truncate", &int_param, 1, MIR_VOID, true, MR_NONE);
    all->pause = mir_extern_get(m, "msrt_unwinding_pause", NULL, 0, MIR_VOID, true, MR_NONE);
    all->resume = mir_extern_get(m, "msrt_unwinding_resume", NULL, 0, MIR_VOID, true, MR_NONE);
}

ElCancel *el_cancel_new(MirModule *m) {
    if (!mir_starts_tasks(m)) {
        return NULL;
    }
    ElCancel *all = calloc(1, sizeof *all);
    if (all == NULL) {
        return NULL;
    }
    all->nfuncs = m->nfuncs;
    ek_closure_map(all, m);
    all->parks = mir_parking_funcs(&all->arena, m);
    all->safe = uw_slot_safe_params(&all->arena, m);
    all->restores = MS_NEW_N(&all->arena, bool, m->nfuncs ? m->nfuncs : 1);
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        all->restores[fi] = m->funcs[fi].nnoalias > 0;
    }
    ek_cancel_externs(all, m);
    return all;
}

void el_cancel_free(ElCancel *all) {
    if (all != NULL) {
        ms_arena_free(&all->arena);
        free(all);
    }
}

/* ---- restoring callees ---- */

static bool ek_noalias_has(const MirFunc *g, uint32_t k) {
    for (uint32_t i = 0; i < g->nnoalias; i++) {
        if (g->noalias[i] == k) {
            return true;
        }
    }
    return false;
}

static bool ek_restores_slot(const ElCancel *all, const MirModule *m, uint32_t g, uint32_t k) {
    return g < all->nfuncs && all->restores[g] && ek_noalias_has(&m->funcs[g], k);
}

bool el_restoring_callee(const ElCancel *all, const MirModule *m, const MirFunc *f,
                         const MirInst *inst, uint32_t k) {
    if (inst->op == MOP_Call && inst->imm.tag == MI_FUNC) {
        return ek_restores_slot(all, m, inst->imm.a, k);
    }
    if (inst->op != MOP_CallInd || inst->nargs == 0) {
        return false;
    }
    uint32_t n = 0;
    const ElTarget *ts = ek_targets_of(all, mir_value_ty(f, inst->args[0]), &n);
    for (uint32_t i = 0; i < n; i++) {
        if (!ek_restores_slot(all, m, ts[i].func, k)) {
            return false;
        }
    }
    return n > 0;
}

/* ---- conversion order ---- */

/* The functions each function calls, a closure call counting every closure of its type. */
static ElIds *ek_call_lists(MsArena *a, const MirModule *m, const ElCancel *all) {
    ElIds *calls = MS_NEW_N(a, ElIds, m->nfuncs ? m->nfuncs : 1);
    memset(calls, 0, sizeof(ElIds) * (m->nfuncs ? m->nfuncs : 1));
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        const MirFunc *f = &m->funcs[fi];
        UW_INSTS(f, b, i, inst) {
            if (inst->op == MOP_Call && inst->imm.tag == MI_FUNC) {
                el_ids_push(a, &calls[fi], inst->imm.a);
            } else if (inst->op == MOP_CallInd && inst->nargs > 0) {
                uint32_t n = 0;
                const ElTarget *ts = ek_targets_of(all, mir_value_ty(f, inst->args[0]), &n);
                for (uint32_t k = 0; k < n; k++) {
                    el_ids_push(a, &calls[fi], ts[k].func);
                }
            }
        }
    }
    return calls;
}

typedef struct ElFrame { uint32_t func, next; } ElFrame;

uint32_t *el_callee_first(MsArena *a, const MirModule *m, const ElCancel *all) {
    const uint32_t n = m->nfuncs;
    uint32_t *order = MS_NEW_N(a, uint32_t, n ? n : 1);
    if (all == NULL) {
        for (uint32_t i = 0; i < n; i++) {
            order[i] = i;
        }
        return order;
    }
    const ElIds *calls = ek_call_lists(a, m, all);
    uint8_t *state = MS_NEW_N(a, uint8_t, n ? n : 1);
    memset(state, 0, n ? n : 1);
    ElFrame *stack = MS_NEW_N(a, ElFrame, (size_t)n + 1);
    uint32_t norder = 0;
    for (uint32_t root = 0; root < n; root++) {
        if (state[root] != 0) {
            continue;
        }
        uint32_t depth = 0;
        stack[depth++] = (ElFrame){root, 0};
        state[root] = 1;
        while (depth > 0) {
            ElFrame *top = &stack[depth - 1];
            if (top->next < calls[top->func].n) {
                const uint32_t g = calls[top->func].v[top->next++];
                if (state[g] == 0) {
                    state[g] = 1;
                    stack[depth++] = (ElFrame){g, 0};
                }
            } else {
                state[top->func] = 2;
                order[norder++] = top->func;
                depth--;
            }
        }
    }
    return order;
}

/* ---- the restore set ---- */

/* The functions that keep their `var` slots, found by walking each one's sites under the current
 * assumption. Nothing is rewritten. */
static bool ek_restores_once(ElCancel *all, MirModule *m, const uint32_t *order, const ElCx *shared,
                             MsArena *scratch) {
    bool changed = false;
    for (uint32_t k = 0; k < m->nfuncs; k++) {
        const uint32_t fi = order[k];
        const MirFunc *f = &m->funcs[fi];
        if (f->nnoalias == 0 || f->nblocks == 0 || f->unwind_only || f->explicit_cancel) {
            continue;
        }
        ElCx cx = *shared;
        cx.ma = scratch;
        cx.m = m;
        cx.fi = fi;
        cx.f = f;
        el_tags(&cx);
        ElSites sites = {0};
        const bool ok = el_cancel_sites(all, m, f, &cx, &sites);
        changed = changed || all->restores[fi] != ok;
        all->restores[fi] = ok;
        ms_arena_reset(scratch);
    }
    return changed;
}

void el_settle_restores(ElCancel *all, MirModule *m, const uint32_t *order, const ElCx *shared) {
    MsArena scratch = {0};
    while (ek_restores_once(all, m, order, shared, &scratch)) {
    }
    ms_arena_free(&scratch);
}

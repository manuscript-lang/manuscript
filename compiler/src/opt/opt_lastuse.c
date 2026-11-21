/* The `lastuse` pass: drops a plain-memory owned value right after its last use instead of where
 * lowering put the drop (the end of the enclosing scope).
 *
 * A candidate `v` is a value of a type whose drop only frees memory (strings, lists, maps, sets and
 * types, alternatives and optionals of those) that is dropped with `drop v`. Everything that may
 * point into `v` forms its family: results of instructions that take a family member (string views,
 * interior pointers, projections, runtime calls), out-pointers of calls that take one, and block
 * parameters that receive one. `v` lives until the last use of any family member on every path; the
 * drop moves there (a new block on an edge that leaves the family's live range, e.g. a loop exit).
 *
 * The family only ever extends `v`'s life, never past its original drop. A candidate is left alone
 * when a family member is stored to memory, captured, kept by a cleanup, or when `v` takes part in a
 * conditional drop. Port of the former Rust crates/ms-mir/src/opt/lastuse.rs; every id it creates, and the order of
 * every drop it places, is the Rust pass's. */
#include <stdlib.h>
#include <string.h>

#include "ms/mir_analysis.h"
#include "ms/mir_opt.h"

/* ---- small growable arrays in the pass arena ---- */

typedef struct LuList {
    uint64_t *v;
    uint32_t n, cap;
} LuList;

static void *lu_regrow(MsArena *a, void *old, uint32_t oldn, uint32_t newcap, size_t elem) {
    void *p = ms_alloc(a, elem * ((size_t)newcap + 1), 16);
    memset(p, 0, elem * ((size_t)newcap + 1));
    if (oldn > 0) {
        memcpy(p, old, elem * oldn);
    }
    return p;
}

/* Zeroed storage for `n` elements of `elem` bytes (an arena returns it as it was). */
static void *lu_zeroed(MsArena *a, size_t n, size_t elem) {
    return lu_regrow(a, NULL, 0, (uint32_t)n, elem);
}

static void lu_push(MsArena *a, LuList *l, uint64_t x) {
    if (l->n == l->cap) {
        const uint32_t cap = l->cap ? l->cap * 2 : 4;
        l->v = lu_regrow(a, l->v, l->n, cap, sizeof(uint64_t));
        l->cap = cap;
    }
    l->v[l->n++] = x;
}

static bool lu_has(const LuList *l, uint64_t x) {
    for (uint32_t i = 0; i < l->n; i++) {
        if (l->v[i] == x) {
            return true;
        }
    }
    return false;
}

/* A position inside a block: an original instruction (`idx` is its index plus one, 0 for the
 * block start), or the `after`-th drop this pass has appended behind it (0 is the instruction). */
typedef struct LuPos {
    uint64_t idx;
    uint32_t after;
} LuPos;

static LuPos lu_at(uint32_t i) { return (LuPos){(uint64_t)i + 1, 0}; }
static LuPos lu_start(void) { return (LuPos){0, 0}; }
static LuPos lu_end(void) { return (LuPos){UINT64_MAX, UINT32_MAX}; }

static int lu_cmp(LuPos a, LuPos b) {
    if (a.idx != b.idx) {
        return a.idx < b.idx ? -1 : 1;
    }
    if (a.after == b.after) {
        return 0;
    }
    return a.after < b.after ? -1 : 1;
}

/* The drops to insert behind one anchor, in emission order. */
typedef struct LuGroup {
    uint64_t anchor;
    MirValue *v;
    uint32_t n, cap;
} LuGroup;

/* The groups of one block, sorted by anchor. */
typedef struct LuPending {
    LuGroup *g;
    uint32_t n, cap;
} LuPending;

/* Where a value is read, built once per function so each candidate costs its own footprint rather
 * than a scan of the function. Instruction indices are those of the original function: the pass
 * never inserts or removes instructions while it analyses, it types the drops it removes and the
 * drops it adds and rewrites every block at the end. New edge blocks are added at once. */
typedef struct LuCtx {
    MirModule *m;
    MirFunc *f;
    MsArena *arena;
    MirMode *modes;
    uint32_t nvcap, nbcap;
    /* per value */
    LuList *uses;           /* block << 32 | instruction, including drops */
    LuList *term_uses;      /* blocks whose terminator passes the value on */
    LuList *pending_blocks; /* blocks holding a pending drop of the value */
    bool *slots;
    uint32_t *fam_gen;
    /* per block */
    bool **removed;
    LuPending *pending;
    LuList *preds; /* once per edge */
    uint32_t *lid_gen, *lid, *drop_gen, *drop_at, *cons_gen, *cons_at;
    uint32_t gen;
} LuCtx;

static void lu_fit(LuCtx *x) {
    const MirFunc *f = x->f;
    if (f->nvalues > x->nvcap) {
        const uint32_t cap = f->nvalues + f->nvalues / 2 + 8;
        x->uses = lu_regrow(x->arena, x->uses, x->nvcap, cap, sizeof(LuList));
        x->term_uses = lu_regrow(x->arena, x->term_uses, x->nvcap, cap, sizeof(LuList));
        x->pending_blocks = lu_regrow(x->arena, x->pending_blocks, x->nvcap, cap, sizeof(LuList));
        x->slots = lu_regrow(x->arena, x->slots, x->nvcap, cap, sizeof(bool));
        x->fam_gen = lu_regrow(x->arena, x->fam_gen, x->nvcap, cap, sizeof(uint32_t));
        x->nvcap = cap;
    }
    if (f->nblocks > x->nbcap) {
        const uint32_t cap = f->nblocks + f->nblocks / 2 + 8;
        x->removed = lu_regrow(x->arena, x->removed, x->nbcap, cap, sizeof(bool *));
        x->pending = lu_regrow(x->arena, x->pending, x->nbcap, cap, sizeof(LuPending));
        x->preds = lu_regrow(x->arena, x->preds, x->nbcap, cap, sizeof(LuList));
        x->lid_gen = lu_regrow(x->arena, x->lid_gen, x->nbcap, cap, sizeof(uint32_t));
        x->lid = lu_regrow(x->arena, x->lid, x->nbcap, cap, sizeof(uint32_t));
        x->drop_gen = lu_regrow(x->arena, x->drop_gen, x->nbcap, cap, sizeof(uint32_t));
        x->drop_at = lu_regrow(x->arena, x->drop_at, x->nbcap, cap, sizeof(uint32_t));
        x->cons_gen = lu_regrow(x->arena, x->cons_gen, x->nbcap, cap, sizeof(uint32_t));
        x->cons_at = lu_regrow(x->arena, x->cons_at, x->nbcap, cap, sizeof(uint32_t));
        x->nbcap = cap;
    }
}

typedef struct LuTermCtx {
    LuCtx *x;
    uint32_t block;
} LuTermCtx;

static void lu_note_term_use(void *ctx, MirValue v) {
    LuTermCtx *t = ctx;
    lu_push(t->x->arena, &t->x->term_uses[v], t->block);
}

static void lu_index(LuCtx *x) {
    MirFunc *f = x->f;
    uint32_t maxargs = 1;
    lu_fit(x);
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        const MirBlockData *b = &f->blocks[bi];
        x->removed[bi] = lu_regrow(x->arena, NULL, 0, b->ninsts, sizeof(bool));
        for (uint32_t ii = 0; ii < b->ninsts; ii++) {
            const MirInst *inst = &b->insts[ii];
            if (inst->nargs > maxargs) {
                maxargs = inst->nargs;
            }
            if (inst->op == MOP_Slot && inst->res != MIR_NONE) {
                x->slots[inst->res] = true;
            }
            for (uint32_t k = 0; k < inst->nargs; k++) {
                lu_push(x->arena, &x->uses[inst->args[k]], ((uint64_t)bi << 32) | ii);
            }
        }
        LuTermCtx tc = {x, bi};
        mir_term_each_value(&b->term, lu_note_term_use, &tc);
        for (uint32_t s = 0; s < mir_term_ntargets(&b->term); s++) {
            lu_push(x->arena, &x->preds[mir_term_target_const(&b->term, s)->block], bi);
        }
    }
    x->modes = MS_NEW_N(x->arena, MirMode, maxargs);
}

static bool lu_live(const LuCtx *x, uint32_t bi, uint32_t ii) { return !x->removed[bi][ii]; }
static uint32_t lu_use_block(uint64_t u) { return (uint32_t)(u >> 32); }
static uint32_t lu_use_inst(uint64_t u) { return (uint32_t)u; }

/* The group of `anchor` in `p`, creating it when `create`; NULL when absent. */
static LuGroup *lu_group(MsArena *a, LuPending *p, uint64_t anchor, bool create) {
    uint32_t lo = 0, hi = p->n;
    while (lo < hi) {
        const uint32_t mid = lo + (hi - lo) / 2;
        if (p->g[mid].anchor < anchor) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    if (lo < p->n && p->g[lo].anchor == anchor) {
        return &p->g[lo];
    }
    if (!create) {
        return NULL;
    }
    if (p->n == p->cap) {
        const uint32_t cap = p->cap ? p->cap * 2 : 2;
        p->g = lu_regrow(a, p->g, p->n, cap, sizeof(LuGroup));
        p->cap = cap;
    }
    memmove(&p->g[lo + 1], &p->g[lo], sizeof(LuGroup) * (p->n - lo));
    p->g[lo] = (LuGroup){anchor, NULL, 0, 0};
    p->n++;
    return &p->g[lo];
}

/* Types a drop of `v` directly behind `pos`: behind the instruction, ahead of the drops already
 * placed there, or behind the pending drop `pos` names. */
static void lu_insert_pending(LuCtx *x, uint32_t bi, LuPos pos, MirValue v) {
    LuGroup *g = lu_group(x->arena, &x->pending[bi], pos.idx, true);
    if (g->n == g->cap) {
        const uint32_t cap = g->cap ? g->cap * 2 : 2;
        g->v = lu_regrow(x->arena, g->v, g->n, cap, sizeof(MirValue));
        g->cap = cap;
    }
    const uint32_t at = pos.after < g->n ? pos.after : g->n;
    memmove(&g->v[at + 1], &g->v[at], sizeof(MirValue) * (g->n - at));
    g->v[at] = v;
    g->n++;
    if (!lu_has(&x->pending_blocks[v], bi)) {
        lu_push(x->arena, &x->pending_blocks[v], bi);
    }
}

/* Writes the recorded removals and insertions into the function. */
static MirInst lu_drop_inst(MirModule *m, MirValue v, MirLoc loc) {
    MirInst d = {.op = MOP_Drop, .res = MIR_NONE, .loc = loc, .nargs = 1};
    d.args = MS_NEW_N(&m->arena, MirValue, 1);
    d.args[0] = v;
    return d;
}

static void lu_apply(LuCtx *x) {
    MirModule *m = x->m;
    MirFunc *f = x->f;
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        MirBlockData *b = &f->blocks[bi];
        const LuPending *p = &x->pending[bi];
        bool any_removed = false;
        for (uint32_t k = 0; k < b->ninsts; k++) {
            any_removed |= x->removed[bi][k];
        }
        if (p->n == 0 && !any_removed) {
            continue;
        }
        uint32_t total = b->ninsts;
        for (uint32_t gi = 0; gi < p->n; gi++) {
            total += p->g[gi].n;
        }
        MirInst *out = MS_NEW_N(&m->arena, MirInst, total);
        uint32_t n = 0, gi = 0;
        if (gi < p->n && p->g[gi].anchor == 0) {
            for (uint32_t d = 0; d < p->g[gi].n; d++) {
                out[n++] = lu_drop_inst(m, p->g[gi].v[d], b->term_loc);
            }
            gi++;
        }
        for (uint32_t k = 0; k < b->ninsts; k++) {
            const MirInst inst = b->insts[k];
            if (!x->removed[bi][k]) {
                out[n++] = inst;
            }
            if (gi < p->n && p->g[gi].anchor == (uint64_t)k + 1) {
                for (uint32_t d = 0; d < p->g[gi].n; d++) {
                    out[n++] = lu_drop_inst(m, p->g[gi].v[d], inst.loc);
                }
                gi++;
            }
        }
        b->insts = out;
        b->ninsts = n;
        b->cinsts = total;
    }
}

/* ---- classification ---- */

/* Whether dropping a value of `t` only frees memory. `seen` holds every type and alternative
 * already entered (stamped with `gen`): revisiting one counts as plain, so each is classified once. */
static bool lu_plain(const MirModule *m, MirTy t, uint32_t *seen, uint32_t gen) {
    const MirTyData *d = mir_ty_data(m, t);
    switch ((MirTyKind)d->kind) {
    case MK_VOID: case MK_BOOL: case MK_INT: case MK_INT8: case MK_INT16: case MK_INT32:
    case MK_UINT8: case MK_UINT16: case MK_UINT32: case MK_UINT64: case MK_FLOAT:
    case MK_FLOAT32: case MK_STR: case MK_BYTES:
        return true;
    case MK_PTR: case MK_FN: case MK_IFACE:
        return false;
    case MK_LIST: case MK_OPT:
        return lu_plain(m, d->elem, seen, gen);
    case MK_OBJ: {
        if (d->obj_class != MIR_OBJ_COLLECTION) {
            return false;
        }
        for (uint32_t i = 0; i < d->nargs; i++) {
            if (!lu_plain(m, d->args[i], seen, gen)) {
                return false;
            }
        }
        return true;
    }
    case MK_TYPE: {
        if (seen[t] == gen) {
            return true;
        }
        seen[t] = gen;
        const MirTypeDef *def = &m->type_defs[d->id];
        for (uint32_t i = 0; i < def->nfields; i++) {
            if (!lu_plain(m, def->fields[i].ty, seen, gen)) {
                return false;
            }
        }
        return true;
    }
    case MK_ALT: {
        if (seen[t] == gen) {
            return true;
        }
        seen[t] = gen;
        const MirAltDef *def = &m->alts[d->id];
        for (uint32_t c = 0; c < def->ncases; c++) {
            for (uint32_t i = 0; i < def->cases[c].nfields; i++) {
                if (!lu_plain(m, def->cases[c].fields[i].ty, seen, gen)) {
                    return false;
                }
            }
        }
        return true;
    }
    }
    return false;
}

static bool lu_is_scalar(const MirModule *m, MirTy t) {
    return mir_ty_data(m, t)->kind == MK_VOID || mir_is_scalar(m, t);
}

/* ---- the family of a candidate ---- */

typedef struct LuFamily {
    MirValue *v; /* members, in discovery order */
    uint32_t n;
    MirValue *work;
    uint32_t nwork;
} LuFamily;

static bool lu_in_family(const LuCtx *x, MirValue w) { return x->fam_gen[w] == x->gen; }

static void lu_add(LuCtx *x, LuFamily *fam, MirValue r) {
    if (x->fam_gen[r] == x->gen) {
        return;
    }
    x->fam_gen[r] = x->gen;
    fam->v[fam->n++] = r;
    fam->work[fam->nwork++] = r;
}

/* Grows the family of `v` (everything that may point into it) to a fixed point over the use
 * index. `param_of` is the block `v` is a parameter of (MIR_NONE otherwise): its sibling
 * parameters may be views into it that the predecessors derived from the value they passed (an
 * owned optional passed beside its payload), so they join the family. */
static void lu_family(LuCtx *x, MsArena *ca, LuFamily *fam, MirValue v, uint32_t param_of) {
    const MirModule *m = x->m;
    const MirFunc *f = x->f;
    fam->v = MS_NEW_N(ca, MirValue, f->nvalues);
    fam->work = MS_NEW_N(ca, MirValue, f->nvalues);
    fam->n = fam->nwork = 0;
    lu_add(x, fam, v);
    if (param_of != MIR_NONE) {
        const MirBlockData *pb = &f->blocks[param_of];
        for (uint32_t k = 0; k < pb->nparams; k++) {
            const MirValue pv = pb->params[k].value;
            if (pv != v && !lu_is_scalar(m, f->values[pv])) {
                lu_add(x, fam, pv);
            }
        }
    }
    while (fam->nwork > 0) {
        const MirValue w = fam->work[--fam->nwork];
        for (uint32_t k = 0; k < x->uses[w].n; k++) {
            const uint32_t bi = lu_use_block(x->uses[w].v[k]), ii = lu_use_inst(x->uses[w].v[k]);
            if (!lu_live(x, bi, ii)) {
                continue;
            }
            const MirInst *i = &f->blocks[bi].insts[ii];
            if (i->op == MOP_Drop || i->op == MOP_Clone) {
                continue;
            }
            if (mir_op_is_call(i->op)) {
                /* A fresh result, through the return value or an out-pointer, points into no
                 * borrowed argument, so it does not extend the family. */
                const bool fresh = i->imm.tag == MI_EXT && m->externs[i->imm.a].fresh;
                if (!fresh) {
                    for (uint32_t a = 0; a < i->nargs; a++) {
                        if (x->slots[i->args[a]]) {
                            lu_add(x, fam, i->args[a]);
                        }
                    }
                }
                MirMode mode = MM_MOVE;
                const bool has_mode = mir_result_mode(m, f, i, &mode);
                const bool borrowed =
                    (has_mode && mode == MM_BORROW && (i->op == MOP_Call || i->op == MOP_CallMethod)) ||
                    mir_result_views(m, f, i);
                if (((i->op == MOP_CallRt && !fresh) || borrowed) && i->res != MIR_NONE &&
                    !lu_is_scalar(m, f->values[i->res])) {
                    lu_add(x, fam, i->res);
                }
                continue;
            }
            if (i->res != MIR_NONE && !lu_is_scalar(m, f->values[i->res])) {
                lu_add(x, fam, i->res);
            }
        }
        for (uint32_t k = 0; k < x->term_uses[w].n; k++) {
            const MirTerm *t = &f->blocks[x->term_uses[w].v[k]].term;
            for (uint32_t s = 0; s < mir_term_ntargets(t); s++) {
                const MirTarget *tg = mir_term_target_const(t, s);
                for (uint32_t a = 0; a < tg->nargs; a++) {
                    if (tg->args[a] == w) {
                        lu_add(x, fam, f->blocks[tg->block].params[a].value);
                    }
                }
            }
        }
    }
}

/* ---- edges ---- */

/* Whether the `slot`-th edge of `bi` hands `v` to an owning block parameter. */
static bool lu_edge_consumes(const MirFunc *f, uint32_t bi, uint32_t slot, MirValue v) {
    const MirTarget *tg = mir_term_target_const(&f->blocks[bi].term, slot);
    for (uint32_t k = 0; k < tg->nargs; k++) {
        if (tg->args[k] == v && f->blocks[tg->block].params[k].mode == MM_MOVE) {
            return true;
        }
    }
    return false;
}

/* A new block holding the drop of `v`, forwarding the edge's arguments. */
static void lu_add_edge(LuCtx *x, MirValue v, uint32_t pred, uint32_t slot) {
    MirModule *m = x->m;
    MirFunc *f = x->f;
    const MirBlock dest = mir_term_target(&f->blocks[pred].term, slot)->block;
    const MirLoc loc = f->blocks[pred].term_loc;
    const uint32_t np = f->blocks[dest].nparams;
    MirTy *tys = MS_NEW_N(x->arena, MirTy, np + 1);
    uint8_t *modes = MS_NEW_N(x->arena, uint8_t, np + 1);
    for (uint32_t k = 0; k < np; k++) {
        tys[k] = f->values[f->blocks[dest].params[k].value];
        modes[k] = f->blocks[dest].params[k].mode;
    }
    const MirBlock nbk = mir_new_block(m, f);
    lu_fit(x); /* the new block's rows; values are fitted as they are added */
    /* The edge now runs from `pred` through `nbk` to `dest`. */
    lu_push(x->arena, &x->preds[nbk], pred);
    for (uint32_t k = 0; k < x->preds[dest].n; k++) {
        if (x->preds[dest].v[k] == pred) {
            x->preds[dest].v[k] = nbk;
            break;
        }
    }
    MirValue *fwd = MS_NEW_N(&m->arena, MirValue, np + 1);
    for (uint32_t k = 0; k < np; k++) {
        const MirValue val = mir_new_value(m, f, tys[k]);
        lu_fit(x);
        lu_push(x->arena, &x->term_uses[val], nbk);
        MirBlockData *nb = &f->blocks[nbk];
        const MirBlockParam bp = {val, modes[k]};
        MIR_PUSH(m, nb->params, nb->nparams, nb->cparams, MirBlockParam, bp);
        fwd[k] = val;
    }
    MirBlockData *nb = &f->blocks[nbk];
    const MirInst drop = lu_drop_inst(m, v, loc);
    MIR_PUSH(m, nb->insts, nb->ninsts, nb->cinsts, MirInst, drop);
    x->removed[nbk] = lu_regrow(x->arena, NULL, 0, 1, sizeof(bool));
    lu_push(x->arena, &x->uses[v], ((uint64_t)nbk << 32) | 0);
    nb->term.kind = MT_BR;
    nb->term.value = MIR_NONE;
    nb->term.a = (MirTarget){dest, fwd, np};
    nb->term_loc = loc;
    mir_term_target(&f->blocks[pred].term, slot)->block = nbk;
}

/* ---- one candidate ---- */

typedef struct LuPlace {
    uint32_t block;
    LuPos pos;
} LuPlace;

static int lu_cmp_u32(const void *a, const void *b) {
    const uint32_t x = *(const uint32_t *)a, y = *(const uint32_t *)b;
    if (x == y) {
        return 0;
    }
    return x < y ? -1 : 1;
}

static uint32_t lu_local(const LuCtx *x, uint32_t b) {
    return x->lid_gen[b] == x->gen ? x->lid[b] : MIR_NONE;
}

static bool lu_ret_of(const MirFunc *f, uint32_t bi, MirValue v) {
    return f->blocks[bi].term.kind == MT_RET && f->blocks[bi].term.value == v;
}

/* Per-block facts of the region the analysis reads. */
typedef struct LuRegion {
    uint32_t nb;
    uint32_t *order; /* block of each local index, ascending */
    LuPos *end, *lo, *last;
    bool *any, *has_last;
} LuRegion;

static void lu_note_use(LuRegion *r, uint32_t l, LuPos p) {
    if (lu_cmp(p, r->end[l]) >= 0) {
        return;
    }
    r->any[l] = true;
    if (lu_cmp(p, r->lo[l]) >= 0 && (!r->has_last[l] || lu_cmp(p, r->last[l]) > 0)) {
        r->last[l] = p;
        r->has_last[l] = true;
    }
}

static bool lu_passes(const LuCtx *x, uint32_t bi) {
    const MirTerm *t = &x->f->blocks[bi].term;
    for (uint32_t s = 0; s < mir_term_ntargets(t); s++) {
        const MirTarget *tg = mir_term_target_const(t, s);
        for (uint32_t a = 0; a < tg->nargs; a++) {
            if (lu_in_family(x, tg->args[a])) {
                return true;
            }
        }
    }
    return false;
}

/* One candidate's analysis: the family, the region it is read over and the facts per block. */
typedef struct LuRun {
    LuCtx *x;
    MsArena *ca;
    MirValue v;
    uint32_t db, di; /* defining block, instruction (MIR_NONE for a block parameter) */
    LuFamily fam;
    uint32_t nexisting;
    uint64_t *existing; /* the live drops of `v` */
    LuRegion r;
    uint32_t dl;
    bool *live_in, *live_out, *owned_in, *owned_out, *consumed;
} LuRun;

/* Whether a family member leaks into memory the pass cannot follow. */
static bool lu_leaks(const LuRun *run) {
    const LuCtx *x = run->x;
    for (uint32_t fi = 0; fi < run->fam.n; fi++) {
        const MirValue w = run->fam.v[fi];
        for (uint32_t k = 0; k < x->uses[w].n; k++) {
            const uint32_t bi = lu_use_block(x->uses[w].v[k]), ii = lu_use_inst(x->uses[w].v[k]);
            if (!lu_live(x, bi, ii)) {
                continue;
            }
            const MirInst *i = &x->f->blocks[bi].insts[ii];
            switch ((MirOp)i->op) {
            case MOP_Store: case MOP_Put:
                if (i->nargs > 1 && i->args[1] == w && (w != run->v || i->op == MOP_Store)) {
                    return true;
                }
                break;
            case MOP_GlobalSet: case MOP_CleanupPush: case MOP_DropIf: case MOP_ClosureNew:
            case MOP_IfaceNew:
                return true;
            default:
                break;
            }
        }
    }
    return false;
}

/* Records where the original drops of `v` sit in each block (nothing after one counts) and the
 * earliest real consumption of `v` (not its drops) per block. */
static void lu_scan_drops(LuRun *run) {
    LuCtx *x = run->x;
    const MirValue v = run->v;
    run->existing = MS_NEW_N(run->ca, uint64_t, x->uses[v].n + 1);
    for (uint32_t k = 0; k < x->uses[v].n; k++) {
        const uint32_t bi = lu_use_block(x->uses[v].v[k]), ii = lu_use_inst(x->uses[v].v[k]);
        if (!lu_live(x, bi, ii)) {
            continue;
        }
        const MirInst *i = &x->f->blocks[bi].insts[ii];
        if (i->op == MOP_Drop) {
            run->existing[run->nexisting++] = x->uses[v].v[k];
            if (x->drop_gen[bi] != x->gen || ii < x->drop_at[bi]) {
                x->drop_gen[bi] = x->gen;
                x->drop_at[bi] = ii;
            }
            continue;
        }
        mir_arg_modes(x->m, x->f, i, x->modes);
        bool consumes = false;
        for (uint32_t a = 0; a < i->nargs; a++) {
            consumes |= i->args[a] == v && x->modes[a] == MM_MOVE;
        }
        if (consumes && (x->cons_gen[bi] != x->gen || ii < x->cons_at[bi])) {
            x->cons_gen[bi] = x->gen;
            x->cons_at[bi] = ii;
        }
    }
}

/* Adds block `b` to the region, and to the walk's stack, unless it is already in. */
static void lu_enter(LuRun *run, uint32_t *stack, uint32_t *nstack, uint32_t b) {
    LuCtx *x = run->x;
    if (x->lid_gen[b] != x->gen) {
        x->lid_gen[b] = x->gen;
        run->r.order[run->r.nb++] = b;
        stack[(*nstack)++] = b;
    }
}

/* The region the analysis needs: the blocks on a path from the definition to a place the family
 * is used or passed on, not through a block that holds the original drop or consumes `v`. Found
 * by walking back from those places: the definition dominates them, so the walk stops at it. A
 * value used only near its definition costs those few blocks, not the rest of the function. */
static void lu_walk_region(LuRun *run) {
    LuCtx *x = run->x;
    const MirFunc *f = x->f;
    LuRegion *r = &run->r;
    r->order = MS_NEW_N(run->ca, uint32_t, f->nblocks);
    uint32_t *stack = MS_NEW_N(run->ca, uint32_t, f->nblocks);
    uint32_t nstack = 0;
    r->order[r->nb++] = run->db;
    x->lid_gen[run->db] = x->gen;
    for (uint32_t fi = 0; fi < run->fam.n; fi++) {
        const MirValue w = run->fam.v[fi];
        for (uint32_t k = 0; k < x->uses[w].n; k++) {
            const uint32_t bi = lu_use_block(x->uses[w].v[k]), ii = lu_use_inst(x->uses[w].v[k]);
            const MirInst *i = &f->blocks[bi].insts[ii];
            if (lu_live(x, bi, ii) && !(i->op == MOP_Drop && i->args[0] == run->v)) {
                lu_enter(run, stack, &nstack, bi);
            }
        }
        for (uint32_t k = 0; k < x->pending_blocks[w].n; k++) {
            lu_enter(run, stack, &nstack, (uint32_t)x->pending_blocks[w].v[k]);
        }
        for (uint32_t k = 0; k < x->term_uses[w].n; k++) {
            lu_enter(run, stack, &nstack, (uint32_t)x->term_uses[w].v[k]);
        }
    }
    while (nstack > 0) {
        const uint32_t b = stack[--nstack];
        for (uint32_t k = 0; k < x->preds[b].n; k++) {
            const uint32_t p = (uint32_t)x->preds[b].v[k];
            if (p != run->db && x->drop_gen[p] != x->gen && x->cons_gen[p] != x->gen) {
                lu_enter(run, stack, &nstack, p);
            }
        }
    }
    qsort(r->order, r->nb, sizeof(uint32_t), lu_cmp_u32);
    for (uint32_t l = 0; l < r->nb; l++) {
        x->lid[r->order[l]] = l;
    }
    run->dl = x->lid[run->db];
}

/* Per block of the region: where the original drop cuts the uses off, where the definition lets
 * them start, and the last family use between; including drops of family members this pass has
 * already placed. */
static void lu_fill_uses(LuRun *run) {
    LuCtx *x = run->x;
    LuRegion *r = &run->r;
    const uint32_t nb = r->nb;
    r->end = MS_NEW_N(run->ca, LuPos, nb);
    r->lo = MS_NEW_N(run->ca, LuPos, nb);
    r->last = MS_NEW_N(run->ca, LuPos, nb);
    r->any = lu_zeroed(run->ca, nb, sizeof(bool));
    r->has_last = lu_zeroed(run->ca, nb, sizeof(bool));
    for (uint32_t l = 0; l < nb; l++) {
        const uint32_t bi = r->order[l];
        r->end[l] = x->drop_gen[bi] == x->gen ? lu_at(x->drop_at[bi]) : lu_end();
        r->lo[l] = bi == run->db ? lu_at(run->di == MIR_NONE ? 0 : run->di + 1) : lu_start();
        r->last[l] = lu_start();
    }
    for (uint32_t fi = 0; fi < run->fam.n; fi++) {
        const MirValue w = run->fam.v[fi];
        for (uint32_t k = 0; k < x->uses[w].n; k++) {
            const uint32_t bi = lu_use_block(x->uses[w].v[k]), ii = lu_use_inst(x->uses[w].v[k]);
            const uint32_t l = lu_local(x, bi);
            if (!lu_live(x, bi, ii) || l == MIR_NONE) {
                continue;
            }
            const MirInst *i = &x->f->blocks[bi].insts[ii];
            if (!(i->op == MOP_Drop && i->args[0] == run->v)) {
                lu_note_use(r, l, lu_at(ii));
            }
        }
        for (uint32_t k = 0; k < x->pending_blocks[w].n; k++) {
            const uint32_t bi = (uint32_t)x->pending_blocks[w].v[k];
            const uint32_t l = lu_local(x, bi);
            const LuPending *p = &x->pending[bi];
            for (uint32_t gi = 0; l != MIR_NONE && gi < p->n; gi++) {
                for (uint32_t d = 0; d < p->g[gi].n; d++) {
                    if (p->g[gi].v[d] == w) {
                        lu_note_use(r, l, (LuPos){p->g[gi].anchor, d + 1});
                    }
                }
            }
        }
    }
}

/* Backward liveness of the family over the region. */
static void lu_liveness(LuRun *run) {
    const LuCtx *x = run->x;
    const uint32_t nb = run->r.nb;
    run->live_in = lu_zeroed(run->ca, nb, sizeof(bool));
    run->live_out = lu_zeroed(run->ca, nb, sizeof(bool));
    for (bool again = true; again;) {
        again = false;
        for (uint32_t l = nb; l-- > 0;) {
            const uint32_t bi = run->r.order[l];
            bool out = false;
            if (x->drop_gen[bi] != x->gen) {
                out = lu_passes(x, bi);
                const MirTerm *t = &x->f->blocks[bi].term;
                for (uint32_t s = 0; s < mir_term_ntargets(t) && !out; s++) {
                    const uint32_t sl = lu_local(x, mir_term_target_const(t, s)->block);
                    out = sl != MIR_NONE && run->live_in[sl];
                }
            }
            /* Nothing of the family is live before `v` is defined. */
            const bool used = run->r.any[l] || lu_ret_of(x->f, run->r.order[l], run->v);
            const bool inn = l != run->dl && (out || used);
            if (out != run->live_out[l] || inn != run->live_in[l]) {
                run->live_out[l] = out;
                run->live_in[l] = inn;
                again = true;
            }
        }
    }
}

/* Incoming edges of the region per block, as (predecessor, successor slot): `start` has nb + 1
 * entries, the edges of block l are `edge[start[l]..start[l + 1]]`. */
static void lu_incoming(LuRun *run, uint32_t **start, uint64_t **edge) {
    const LuCtx *x = run->x;
    const uint32_t nb = run->r.nb;
    uint32_t *st = lu_zeroed(run->ca, (size_t)nb + 2, sizeof(uint32_t));
    for (uint32_t p = 0; p < nb; p++) {
        const MirTerm *t = &x->f->blocks[run->r.order[p]].term;
        for (uint32_t s = 0; s < mir_term_ntargets(t); s++) {
            const uint32_t sl = lu_local(x, mir_term_target_const(t, s)->block);
            if (sl != MIR_NONE) {
                st[sl + 1]++;
            }
        }
    }
    for (uint32_t l = 0; l < nb; l++) {
        st[l + 1] += st[l];
    }
    uint32_t *fill = lu_zeroed(run->ca, (size_t)nb + 1, sizeof(uint32_t));
    memcpy(fill, st, sizeof(uint32_t) * nb);
    uint64_t *e = lu_zeroed(run->ca, (size_t)st[nb] + 1, sizeof(uint64_t));
    for (uint32_t p = 0; p < nb; p++) {
        const MirTerm *t = &x->f->blocks[run->r.order[p]].term;
        for (uint32_t s = 0; s < mir_term_ntargets(t); s++) {
            const uint32_t sl = lu_local(x, mir_term_target_const(t, s)->block);
            if (sl != MIR_NONE) {
                e[fill[sl]++] = ((uint64_t)p << 32) | s;
            }
        }
    }
    *start = st;
    *edge = e;
}

/* Forward: blocks where `v` is owned on entry and not consumed. */
static void lu_ownership(LuRun *run) {
    const LuCtx *x = run->x;
    const uint32_t nb = run->r.nb;
    run->owned_in = lu_zeroed(run->ca, nb, sizeof(bool));
    run->owned_out = lu_zeroed(run->ca, nb, sizeof(bool));
    run->consumed = lu_zeroed(run->ca, nb, sizeof(bool));
    for (uint32_t l = 0; l < nb; l++) {
        const uint32_t bi = run->r.order[l];
        run->consumed[l] = x->cons_gen[bi] == x->gen || lu_ret_of(x->f, bi, run->v);
    }
    run->owned_out[run->dl] = !run->consumed[run->dl] && x->drop_gen[run->db] != x->gen;
    uint32_t *start;
    uint64_t *edge;
    lu_incoming(run, &start, &edge);
    for (bool again = true; again;) {
        again = false;
        for (uint32_t l = 0; l < nb; l++) {
            bool inn = false;
            for (uint32_t k = start[l]; l != run->dl && !inn && k < start[l + 1]; k++) {
                const uint32_t p = (uint32_t)(edge[k] >> 32), si = (uint32_t)edge[k];
                inn = run->owned_out[p] && !lu_edge_consumes(x->f, run->r.order[p], si, run->v);
            }
            const bool out = (inn || l == run->dl) && !run->consumed[l] &&
                             x->drop_gen[run->r.order[l]] != x->gen;
            if (inn != run->owned_in[l] || out != run->owned_out[l]) {
                run->owned_in[l] = inn;
                run->owned_out[l] = out;
                again = true;
            }
        }
    }
}

/* The drops of `v` to place: (block, position the drop follows) and edges (block << 32 | slot). */
typedef struct LuPlan {
    LuPlace *place;
    uint32_t nplace;
    uint64_t *edges;
    uint32_t nedges;
} LuPlan;

/* Where block `l` of the region ends the life of `v`; false when it needs no drop in the block. */
static bool lu_place_in_block(const LuRun *run, uint32_t l, LuPlace *out) {
    const uint32_t bi = run->r.order[l];
    const uint8_t tk = run->x->f->blocks[bi].term.kind;
    if (tk == MT_FAULT || tk == MT_UNREACHABLE) {
        return false;
    }
    /* After the last use (or the definition) in this block. A block with no use and no
     * definition is entered with `v` owned only from predecessors that left it live; their
     * edges place the drop. */
    if (run->r.has_last[l]) {
        *out = (LuPlace){bi, run->r.last[l]};
        return true;
    }
    if (bi != run->db) {
        return false;
    }
    *out = (LuPlace){bi, run->di == MIR_NONE ? lu_start() : lu_at(run->di)};
    return true;
}

static void lu_plan(const LuRun *run, LuPlan *plan) {
    const LuCtx *x = run->x;
    uint32_t total_succ = 0;
    for (uint32_t l = 0; l < run->r.nb; l++) {
        total_succ += mir_term_ntargets(&x->f->blocks[run->r.order[l]].term);
    }
    plan->place = MS_NEW_N(run->ca, LuPlace, (size_t)run->r.nb + 1);
    plan->edges = MS_NEW_N(run->ca, uint64_t, (size_t)total_succ + 1);
    for (uint32_t l = 0; l < run->r.nb; l++) {
        const uint32_t bi = run->r.order[l];
        const bool in_region = l == run->dl || (run->owned_in[l] && run->live_in[l]);
        if (!in_region || run->consumed[l]) {
            continue;
        }
        if (!run->live_out[l]) {
            LuPlace at;
            if (lu_place_in_block(run, l, &at)) {
                plan->place[plan->nplace++] = at;
            }
            continue;
        }
        const MirTerm *t = &x->f->blocks[bi].term;
        for (uint32_t s = 0; s < mir_term_ntargets(t); s++) {
            /* A successor outside the region reaches no use of the family. */
            const uint32_t sl = lu_local(x, mir_term_target_const(t, s)->block);
            const bool live_next = sl != MIR_NONE && run->live_in[sl];
            if (!live_next && !lu_edge_consumes(x->f, bi, s, run->v)) {
                plan->edges[plan->nedges++] = ((uint64_t)bi << 32) | s;
            }
        }
    }
}

/* Moves the drops of `v`; false when the candidate is left as it was. `di` is the defining
 * instruction, MIR_NONE for a block parameter. */
static bool lu_candidate(LuCtx *x, MirValue v, uint32_t db, uint32_t di) {
    MsArena ca = {0};
    LuRun run = {.x = x, .ca = &ca, .v = v, .db = db, .di = di};
    bool result = false;
    x->gen++;
    lu_fit(x);
    lu_family(x, &ca, &run.fam, v, di == MIR_NONE ? db : MIR_NONE);
    if (!lu_leaks(&run)) {
        lu_scan_drops(&run);
    }
    if (run.nexisting > 0) {
        LuPlan plan = {0};
        lu_walk_region(&run);
        lu_fill_uses(&run);
        lu_liveness(&run);
        lu_ownership(&run);
        lu_plan(&run, &plan);
        /* Apply: type the removed drops and the new ones. */
        for (uint32_t k = 0; k < run.nexisting; k++) {
            x->removed[lu_use_block(run.existing[k])][lu_use_inst(run.existing[k])] = true;
        }
        for (uint32_t k = 0; k < plan.nplace; k++) {
            lu_insert_pending(x, plan.place[k].block, plan.place[k].pos, v);
        }
        for (uint32_t k = 0; k < plan.nedges; k++) {
            lu_add_edge(x, v, (uint32_t)(plan.edges[k] >> 32), (uint32_t)plan.edges[k]);
        }
        result = true;
    }
    ms_arena_free(&ca);
    return result;
}

/* ---- the pass ---- */

typedef struct LuCand {
    MirValue v;
    uint32_t block, inst; /* inst is MIR_NONE for a block parameter */
} LuCand;

bool mir_opt_lastuse_func(MirModule *m, MirFunc *f) {
    if (f->nblocks == 0) {
        return false;
    }
    MsArena arena = {0};
    bool changed = false;
    bool *dropped = lu_zeroed(&arena, (size_t)f->nvalues + 1, sizeof(bool));
    uint32_t ncands = 0;
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        for (uint32_t ii = 0; ii < f->blocks[bi].ninsts; ii++) {
            const MirInst *inst = &f->blocks[bi].insts[ii];
            if (inst->op == MOP_Drop) {
                dropped[inst->args[0]] = true;
            }
            ncands += inst->res != MIR_NONE;
        }
        ncands += f->blocks[bi].nparams;
    }
    LuCand *cands = MS_NEW_N(&arena, LuCand, (size_t)ncands + 1);
    uint32_t *seen = lu_zeroed(&arena, (size_t)m->types.len + 1, sizeof(uint32_t));
    uint32_t stamp = 0, n = 0;
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        const MirBlockData *b = &f->blocks[bi];
        for (uint32_t k = 0; k < b->nparams; k++) {
            const MirValue p = b->params[k].value;
            const MirTy t = f->values[p];
            if (b->params[k].mode == MM_MOVE && dropped[p] && lu_plain(m, t, seen, ++stamp) &&
                mir_needs_drop(m, t)) {
                cands[n++] = (LuCand){p, bi, MIR_NONE};
            }
        }
        for (uint32_t ii = 0; ii < b->ninsts; ii++) {
            const MirInst *inst = &b->insts[ii];
            MirMode mode = MM_BORROW;
            if (inst->res == MIR_NONE || !dropped[inst->res] ||
                !mir_result_mode(m, f, inst, &mode) || mode != MM_MOVE) {
                continue;
            }
            const MirTy t = f->values[inst->res];
            if (lu_plain(m, t, seen, ++stamp) && mir_needs_drop(m, t)) {
                cands[n++] = (LuCand){inst->res, bi, ii};
            }
        }
    }
    if (n > 0) {
        LuCtx x = {.m = m, .f = f, .arena = &arena};
        lu_index(&x);
        /* Latest definitions first: a family member's own drop has moved before its source's is
         * placed. */
        for (uint32_t k = n; k-- > 0;) {
            changed |= lu_candidate(&x, cands[k].v, cands[k].block, cands[k].inst);
        }
        lu_apply(&x);
    }
    ms_arena_free(&arena);
    return changed;
}

bool mir_opt_lastuse(MirModule *m) {
    bool changed = false;
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        changed |= mir_opt_lastuse_func(m, &m->funcs[fi]);
    }
    return changed;
}

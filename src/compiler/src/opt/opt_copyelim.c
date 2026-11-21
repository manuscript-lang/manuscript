/* The `copyelim` pass: removes deep copies that only feed read-only uses.
 *
 * Lowering copies a value when it binds a pattern payload or a field out of a borrowed parameter,
 * then drops the copy at scope end. When every use of the copy is a borrowing operand, the copy is
 * the same value as its source for the whole function, provided the source cannot change or die
 * before the copy would: a borrowed parameter is neither mutated nor released by its callee, and
 * neither is anything projected out of one. The pass also turns a copy of a dying source into a
 * move, and a copy of a payload of a dying alternative, option or type into a move out of it.
 * Port of the former Rust crates/ms-mir/src/opt/copyelim.rs; the order of every rewrite is the Rust pass's. */
#include <stdlib.h>
#include <string.h>

#include "ms/mir_analysis.h"
#include "ms/mir_opt.h"

/* ---- shared facts ---- */

/* A position (block, instruction). */
typedef struct CpePos {
    uint32_t block, index;
} CpePos;

/* Operand uses of each value as positions in program order; a value used twice by one
 * instruction appears twice. Terminator uses are not listed. In one arena. */
typedef struct CpeUses {
    uint32_t *start; /* nvalues + 2 entries */
    CpePos *at;
} CpeUses;

static CpeUses cpe_operand_uses(MsArena *arena, const MirFunc *f) {
    CpeUses u = {MS_NEW_N(arena, uint32_t, (size_t)f->nvalues + 2), NULL};
    memset(u.start, 0, sizeof(uint32_t) * ((size_t)f->nvalues + 2));
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            const MirInst *inst = &f->blocks[b].insts[i];
            for (uint32_t k = 0; k < inst->nargs; k++) {
                u.start[inst->args[k] + 1]++;
            }
        }
    }
    for (uint32_t v = 0; v <= f->nvalues; v++) {
        u.start[v + 1] += u.start[v];
    }
    u.at = MS_NEW_N(arena, CpePos, (size_t)u.start[f->nvalues + 1] + 1);
    uint32_t *fill = MS_NEW_N(arena, uint32_t, (size_t)f->nvalues + 1);
    memcpy(fill, u.start, sizeof(uint32_t) * ((size_t)f->nvalues + 1));
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            const MirInst *inst = &f->blocks[b].insts[i];
            for (uint32_t k = 0; k < inst->nargs; k++) {
                u.at[fill[inst->args[k]]++] = (CpePos){b, i};
            }
        }
    }
    return u;
}

static uint32_t cpe_nuses(const CpeUses *u, MirValue v) { return u->start[v + 1] - u->start[v]; }
static CpePos cpe_use(const CpeUses *u, MirValue v, uint32_t k) { return u->at[u->start[v] + k]; }

/* The first use of `v` after instruction `i` of block `bi`; false when there is none. */
static bool cpe_next_use(const CpeUses *u, MirValue v, uint32_t bi, uint32_t i, CpePos *out) {
    for (uint32_t k = 0; k < cpe_nuses(u, v); k++) {
        const CpePos p = cpe_use(u, v, k);
        if (p.block > bi || (p.block == bi && p.index > i)) {
            *out = p;
            return true;
        }
    }
    return false;
}

/* Operand uses of each value within one block's instructions, sorted by value then position. */
typedef struct CpeBlockUses {
    uint64_t *keys; /* value << 32 | instruction */
    uint32_t n;
} CpeBlockUses;

static int cpe_cmp_key(const void *a, const void *b) {
    const uint64_t x = *(const uint64_t *)a, y = *(const uint64_t *)b;
    if (x == y) {
        return 0;
    }
    return x < y ? -1 : 1;
}

static CpeBlockUses cpe_block_uses(MsArena *arena, const MirBlockData *b) {
    uint32_t n = 0;
    for (uint32_t i = 0; i < b->ninsts; i++) {
        n += b->insts[i].nargs;
    }
    CpeBlockUses u = {MS_NEW_N(arena, uint64_t, (size_t)n + 1), 0};
    for (uint32_t i = 0; i < b->ninsts; i++) {
        for (uint32_t k = 0; k < b->insts[i].nargs; k++) {
            u.keys[u.n++] = ((uint64_t)b->insts[i].args[k] << 32) | i;
        }
    }
    if (u.n > 1) {
        qsort(u.keys, u.n, sizeof(uint64_t), cpe_cmp_key);
    }
    return u;
}

/* The index of the first key above `(v, i)`. */
static uint32_t cpe_after_start(const CpeBlockUses *u, MirValue v, uint32_t i) {
    const uint64_t key = ((uint64_t)v << 32) | i;
    uint32_t lo = 0, hi = u->n;
    while (lo < hi) {
        const uint32_t mid = lo + (hi - lo) / 2;
        if (u->keys[mid] <= key) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    return lo;
}

/* The next position after `*cursor` that uses `v`, advancing it. */
static bool cpe_after_next(const CpeBlockUses *u, MirValue v, uint32_t *cursor, uint32_t *at) {
    if (*cursor >= u->n || (MirValue)(u->keys[*cursor] >> 32) != v) {
        return false;
    }
    *at = (uint32_t)(u->keys[*cursor] & 0xFFFFFFFFu);
    (*cursor)++;
    return true;
}

/* The first use of `v` after instruction `i` that is an `op`; false when there is none. */
static bool cpe_first_after(const CpeBlockUses *u, const MirBlockData *b, MirValue v, uint32_t i,
                           MirOp op, uint32_t *out) {
    uint32_t cursor = cpe_after_start(u, v, i), at = 0;
    while (cpe_after_next(u, v, &cursor, &at)) {
        if (b->insts[at].op == op) {
            *out = at;
            return true;
        }
    }
    return false;
}

/* The values each value is borrowed by: results that borrow from their operands (or, with
 * `all`, every result that is not an owned non-view one). In one arena, as CSR. */
typedef struct CpeBorrows {
    uint32_t *start;
    MirValue *list;
} CpeBorrows;

static CpeBorrows cpe_borrows_of(MsArena *arena, const MirModule *m, const MirFunc *f,
                               bool strict) {
    CpeBorrows br = {MS_NEW_N(arena, uint32_t, (size_t)f->nvalues + 2), NULL};
    memset(br.start, 0, sizeof(uint32_t) * ((size_t)f->nvalues + 2));
    for (int pass = 0; pass < 2; pass++) {
        uint32_t *fill = NULL;
        if (pass == 1) {
            for (uint32_t v = 0; v <= f->nvalues; v++) {
                br.start[v + 1] += br.start[v];
            }
            br.list = MS_NEW_N(arena, MirValue, (size_t)br.start[f->nvalues + 1] + 1);
            fill = MS_NEW_N(arena, uint32_t, (size_t)f->nvalues + 1);
            memcpy(fill, br.start, sizeof(uint32_t) * ((size_t)f->nvalues + 1));
        }
        for (uint32_t b = 0; b < f->nblocks; b++) {
            for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
                const MirInst *inst = &f->blocks[b].insts[i];
                MirMode mode = MM_BORROW;
                const bool has = mir_result_mode(m, f, inst, &mode);
                /* A result that borrows, or (loosely) an owned view; strictly, only an owned one that
                 * has a result mode at all. */
                const bool borrows = strict ? has && (mode != MM_MOVE || mir_result_views(m, f, inst))
                                            : (has && mode != MM_MOVE) || mir_result_views(m, f, inst);
                if (inst->res == MIR_NONE || !borrows) {
                    continue;
                }
                for (uint32_t k = 0; k < inst->nargs; k++) {
                    if (pass == 0) {
                        br.start[inst->args[k] + 1]++;
                    } else {
                        br.list[fill[inst->args[k]]++] = inst->res;
                    }
                }
            }
        }
    }
    return br;
}

/* Marks `v` and everything transitively borrowed out of it in `held` (cleared first). */
static void cpe_hold(const CpeBorrows *br, MirValue v, uint32_t nvalues, bool *held,
                    MirValue *stack) {
    memset(held, 0, sizeof(bool) * ((size_t)nvalues + 1));
    uint32_t top = 0;
    stack[top++] = v;
    while (top > 0) {
        const MirValue x = stack[--top];
        if (held[x]) {
            continue;
        }
        held[x] = true;
        for (uint32_t k = br->start[x]; k < br->start[x + 1]; k++) {
            stack[top++] = br->list[k];
        }
    }
}

/* Values that may be interface views (`iface.borrow`, `iface.view`, a view returner's result) or
 * hold one: an owned value whose payload is borrowed from elsewhere. A copy of such a value owns
 * its payload, so the copy is never turned into a move or a take of the source. */
static void cpe_taint_view_returners(const MirModule *m, const MirFunc *f, bool *tainted) {
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            const MirInst *inst = &f->blocks[b].insts[i];
            if (inst->op != MOP_CallRt || inst->imm.tag != MI_EXT ||
                m->externs[inst->imm.a].role != MR_VIEW_RESULT) {
                continue;
            }
            for (uint32_t k = 0; k < inst->nargs; k++) {
                if (mir_value_ty(f, inst->args[k]) == MIR_PTR) {
                    tainted[inst->args[k]] = true;
                }
            }
        }
    }
}

static bool cpe_taint_inst(const MirModule *m, const MirFunc *f, const MirInst *inst, bool *tainted) {
    bool changed = false;
    if ((inst->op == MOP_Put || inst->op == MOP_Store) && inst->nargs >= 2 &&
        tainted[inst->args[1]] && !tainted[inst->args[0]]) {
        tainted[inst->args[0]] = true;
        changed = true;
    }
    if (inst->res == MIR_NONE || tainted[inst->res]) {
        return changed;
    }
    bool hit = mir_result_views(m, f, inst);
    if (!hit && inst->op != MOP_Clone && !mir_op_is_call((MirOp)inst->op)) {
        for (uint32_t k = 0; k < inst->nargs && !hit; k++) {
            hit = tainted[inst->args[k]];
        }
    }
    if (hit) {
        tainted[inst->res] = true;
        changed = true;
    }
    return changed;
}

static bool cpe_taint_block(const MirModule *m, const MirFunc *f, const MirBlockData *blk,
                           bool *tainted) {
    bool changed = false;
    for (uint32_t i = 0; i < blk->ninsts; i++) {
        changed |= cpe_taint_inst(m, f, &blk->insts[i], tainted);
    }
    for (uint32_t t = 0; t < mir_term_ntargets(&blk->term); t++) {
        const MirTarget *target = mir_term_target_const(&blk->term, t);
        const MirBlockData *dest = &f->blocks[target->block];
        for (uint32_t k = 0; k < target->nargs && k < dest->nparams; k++) {
            if (tainted[target->args[k]] && !tainted[dest->params[k].value]) {
                tainted[dest->params[k].value] = true;
                changed = true;
            }
        }
    }
    return changed;
}

static bool *cpe_view_tainted(MsArena *arena, const MirModule *m, const MirFunc *f) {
    bool *tainted = MS_NEW_N(arena, bool, (size_t)f->nvalues + 1);
    memset(tainted, 0, sizeof(bool) * ((size_t)f->nvalues + 1));
    cpe_taint_view_returners(m, f, tainted);
    bool changed = true;
    while (changed) {
        changed = false;
        for (uint32_t b = 0; b < f->nblocks; b++) {
            changed |= cpe_taint_block(m, f, &f->blocks[b], tainted);
        }
    }
    return tainted;
}

/* ---- editing ---- */

static int cpe_cmp_pos(const void *a, const void *b) {
    const CpePos *x = a, *y = b;
    if (x->block != y->block) {
        return x->block < y->block ? -1 : 1;
    }
    if (x->index == y->index) {
        return 0;
    }
    return x->index < y->index ? -1 : 1;
}

/* A growing list of positions. */
typedef struct CpeDead {
    CpePos *at;
    uint32_t n, cap;
} CpeDead;

static void cpe_dead_push(MsArena *arena, CpeDead *d, uint32_t block, uint32_t index) {
    if (d->n == d->cap) {
        const uint32_t next = d->cap ? d->cap * 2 : 16;
        CpePos *grown = MS_NEW_N(arena, CpePos, next);
        if (d->n > 0) {
            memcpy(grown, d->at, sizeof(CpePos) * d->n);
        }
        d->at = grown;
        d->cap = next;
    }
    d->at[d->n++] = (CpePos){block, index};
}

/* Removes the instructions at the positions in `dead`. */
static void cpe_remove_insts(MsArena *arena, MirFunc *f, CpeDead *dead) {
    if (dead->n > 1) {
        qsort(dead->at, dead->n, sizeof(CpePos), cpe_cmp_pos);
    }
    uint32_t *ks = MS_NEW_N(arena, uint32_t, (size_t)dead->n + 1);
    uint32_t k = 0;
    while (k < dead->n) {
        const uint32_t block = dead->at[k].block;
        uint32_t n = 0;
        for (; k < dead->n && dead->at[k].block == block; k++) {
            if (n == 0 || ks[n - 1] != dead->at[k].index) {
                ks[n++] = dead->at[k].index;
            }
        }
        mir_block_remove(&f->blocks[block], ks, n);
    }
}

static void cpe_rename_term(void *ctx, MirValue *v) {
    const MirValue *rename = ctx;
    if (rename[*v] != MIR_NONE) {
        *v = rename[*v];
    }
}

/* Rewrites every operand with a rename (and, with `terms`, the terminators' too). */
static void cpe_apply_rename(MirFunc *f, MirValue *rename, bool terms) {
    for (uint32_t b = 0; b < f->nblocks; b++) {
        MirBlockData *blk = &f->blocks[b];
        for (uint32_t i = 0; i < blk->ninsts; i++) {
            for (uint32_t k = 0; k < blk->insts[i].nargs; k++) {
                const MirValue s = rename[blk->insts[i].args[k]];
                if (s != MIR_NONE) {
                    blk->insts[i].args[k] = s;
                }
            }
        }
        if (terms) {
            mir_term_each_use(&blk->term, cpe_rename_term, rename);
        }
    }
}

static MirValue *cpe_new_values(MsArena *arena, const MirFunc *f, MirValue fill) {
    MirValue *v = MS_NEW_N(arena, MirValue, (size_t)f->nvalues + 1);
    for (uint32_t i = 0; i <= f->nvalues; i++) {
        v[i] = fill;
    }
    return v;
}

static bool *cpe_new_flags(MsArena *arena, const MirFunc *f) {
    bool *v = MS_NEW_N(arena, bool, (size_t)f->nvalues + 1);
    memset(v, 0, sizeof(bool) * ((size_t)f->nvalues + 1));
    return v;
}

/* ---- a copy of a source that dies right after ---- */

/* Whether some instruction in `(i, j)` of `b` reads, other than through `v`, what was borrowed out
 * of `v` before the copy (a projection another pass merged into an earlier one): the copy's drop
 * would free `v` under it. */
static bool cpe_reads_held(const MirBlockData *b, uint32_t i, uint32_t j, MirValue v,
                          const bool *held) {
    for (uint32_t k = i + 1; k < j; k++) {
        for (uint32_t a = 0; a < b->insts[k].nargs; a++) {
            const MirValue arg = b->insts[k].args[a];
            if (arg != v && held[arg]) {
                return true;
            }
        }
    }
    return false;
}

/* Turns `c = clone v; ...; drop v` into a move when `v` is not touched in between: the copy and
 * the drop cancel, and `c` is `v`. This is the shape of `l = More(l)` in a loop, which would
 * otherwise deep-copy the old value on every iteration. */
static bool cpe_move_dead_sources(MsArena *arena, const MirModule *m, MirFunc *f) {
    const CpeBorrows borrows = cpe_borrows_of(arena, m, f, false);
    bool *tainted = cpe_view_tainted(arena, m, f);
    MirValue *rename = cpe_new_values(arena, f, MIR_NONE);
    bool *touched = cpe_new_flags(arena, f);
    bool *held = cpe_new_flags(arena, f);
    MirValue *stack = MS_NEW_N(arena, MirValue, (size_t)f->nvalues + (size_t)borrows.start[f->nvalues + 1] + 2);
    CpeDead dead = {0};
    const CpeUses at = cpe_operand_uses(arena, f);
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        const MirBlockData *b = &f->blocks[bi];
        for (uint32_t i = 0; i < b->ninsts; i++) {
            const MirInst *inst = &b->insts[i];
            if (inst->op != MOP_Clone || inst->res == MIR_NONE) {
                continue;
            }
            const MirValue c = inst->res, v = inst->args[0];
            CpePos next = {0, 0};
            if (touched[c] || touched[v] || tainted[v] || !cpe_next_use(&at, v, bi, i, &next) ||
                next.block != bi || b->insts[next.index].op != MOP_Drop) {
                continue;
            }
            cpe_hold(&borrows, v, f->nvalues, held, stack);
            if (cpe_reads_held(b, i, next.index, v, held)) {
                continue;
            }
            touched[c] = true;
            touched[v] = true;
            rename[c] = v;
            cpe_dead_push(arena, &dead, bi, i);
            cpe_dead_push(arena, &dead, bi, next.index);
        }
    }
    if (dead.n == 0) {
        return false;
    }
    cpe_remove_insts(arena, f, &dead);
    cpe_apply_rename(f, rename, true);
    return true;
}

/* ---- a copy that is the last use of its source on every path ---- */

/* What a scan of one block's instructions found for the source `v`: a drop ending the path at
 * `*drop_at`, an instruction reading what was borrowed from `v` (the path is not clean), or
 * nothing (the block passes `v` on untouched). */
typedef enum CpeScan { CE_SCAN_PASSES, CE_SCAN_DROP, CE_SCAN_READ } CpeScan;

static CpeScan cpe_scan(const MirBlockData *blk, uint32_t from, MirValue v, const bool *held,
                      uint32_t *drop_at) {
    for (uint32_t k = from; k < blk->ninsts; k++) {
        const MirInst *n = &blk->insts[k];
        if (n->op == MOP_Drop && n->args[0] == v) {
            *drop_at = k;
            return CE_SCAN_DROP;
        }
        for (uint32_t a = 0; a < n->nargs; a++) {
            if (held[n->args[a]]) {
                return CE_SCAN_READ;
            }
        }
    }
    return CE_SCAN_PASSES;
}

typedef struct CpeHeld {
    const bool *held;
    bool used;
} CpeHeld;

static void cpe_term_reads(void *ctx, MirValue v) {
    CpeHeld *h = ctx;
    h->used |= h->held[v];
}

/* The facts `cpe_move_across` reads about a function. */
typedef struct CpeFlow {
    bool *owned;
    uint32_t *home;
    CpeBorrows borrows;
    bool *tainted;
    MirPreds preds;
} CpeFlow;

/* The owned values of `f`, where each is defined, and what borrows from each (an owned result
 * that is a view borrows from its operands too). */
static CpeFlow cpe_flow(MsArena *arena, const MirModule *m, const MirFunc *f) {
    CpeFlow fl = {cpe_new_flags(arena, f), MS_NEW_N(arena, uint32_t, (size_t)f->nvalues + 1), {0},
                 NULL, {0}};
    for (uint32_t v = 0; v <= f->nvalues; v++) {
        fl.home[v] = UINT32_MAX;
    }
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        const MirBlockData *b = &f->blocks[bi];
        for (uint32_t p = 0; p < b->nparams; p++) {
            fl.home[b->params[p].value] = bi;
            fl.owned[b->params[p].value] = b->params[p].mode == MM_MOVE;
        }
        for (uint32_t i = 0; i < b->ninsts; i++) {
            if (b->insts[i].res != MIR_NONE) {
                fl.home[b->insts[i].res] = bi;
                MirMode mode = MM_BORROW;
                if (mir_result_mode(m, f, &b->insts[i], &mode) && mode == MM_MOVE) {
                    fl.owned[b->insts[i].res] = true;
                }
            }
        }
    }
    fl.borrows = cpe_borrows_of(arena, m, f, true);
    fl.tainted = cpe_view_tainted(arena, m, f);
    fl.preds = mir_preds(arena, f);
    return fl;
}

/* The paths from the copy `(bc, i)` of `v`: each ends in a drop of `v` and reads nothing borrowed
 * from it. Collects the drops; `*seen` marks the blocks reached. False when a path is not clean. */
static bool cpe_paths(MsArena *arena, const MirFunc *f, const CpeFlow *fl, uint32_t bc, uint32_t i,
                     MirValue v, const bool *held, bool *seen, CpeDead *drops) {
    CpePos *work = MS_NEW_N(arena, CpePos, (size_t)f->nblocks * 2 + 2);
    uint32_t top = 0;
    work[top++] = (CpePos){bc, i + 1};
    while (top > 0) {
        const CpePos w = work[--top];
        const MirBlockData *blk = &f->blocks[w.block];
        uint32_t drop_at = 0;
        const CpeScan scan = cpe_scan(blk, w.index, v, held, &drop_at);
        if (scan == CE_SCAN_READ) {
            return false;
        }
        if (scan == CE_SCAN_DROP) {
            cpe_dead_push(arena, drops, w.block, drop_at);
            continue;
        }
        CpeHeld h = {held, false};
        mir_term_each_value(&blk->term, cpe_term_reads, &h);
        if (h.used || blk->term.kind == MT_RET) {
            return false;
        }
        for (uint32_t t = 0; t < mir_term_ntargets(&blk->term); t++) {
            const uint32_t s = mir_term_target_const(&blk->term, t)->block;
            if (s == bc || s == fl->home[v]) {
                return false;
            }
            if (!seen[s]) {
                seen[s] = true;
                work[top++] = (CpePos){s, 0};
            }
        }
    }
    return true;
}

/* Whether a block reached by the paths is also entered from outside them. */
static bool cpe_entered_elsewhere(const MirFunc *f, const CpeFlow *fl, uint32_t bc,
                                 const bool *seen) {
    for (uint32_t x = 0; x < f->nblocks; x++) {
        if (!seen[x]) {
            continue;
        }
        for (uint32_t k = 0; k < mir_preds_count(&fl->preds, x); k++) {
            const MirBlock p = mir_pred(&fl->preds, x, k);
            if (p != bc && !seen[p]) {
                return true;
            }
        }
    }
    return false;
}

/* Turns `c = clone v` into a move when every path from the copy reaches `v` again only to drop
 * it: the copy is `v`'s last use, like `keys.append(key)` before a loop body ends or returns. The
 * copy and the drops cancel, and `c` is `v`. Nothing borrowed out of `v` may be read after the
 * copy, and each block on those paths is entered only from them, so a path that skipped the copy
 * keeps its drop. */
static bool cpe_move_across(MsArena *arena, const MirModule *m, MirFunc *f) {
    const CpeFlow fl = cpe_flow(arena, m, f);
    bool *touched = cpe_new_flags(arena, f), *held = cpe_new_flags(arena, f);
    MirValue *rename = cpe_new_values(arena, f, MIR_NONE);
    MirValue *stack = MS_NEW_N(arena, MirValue, (size_t)f->nvalues + (size_t)fl.borrows.start[f->nvalues + 1] + 2);
    bool *seen = MS_NEW_N(arena, bool, (size_t)f->nblocks + 1);
    CpeDead dead = {0};
    for (uint32_t bc = 0; bc < f->nblocks; bc++) {
        for (uint32_t i = 0; i < f->blocks[bc].ninsts; i++) {
            const MirInst *inst = &f->blocks[bc].insts[i];
            if (inst->op != MOP_Clone || inst->res == MIR_NONE) {
                continue;
            }
            const MirValue c = inst->res, v = inst->args[0];
            if (!fl.owned[v] || fl.tainted[v] || touched[v] || touched[c]) {
                continue;
            }
            cpe_hold(&fl.borrows, v, f->nvalues, held, stack);
            memset(seen, 0, sizeof(bool) * f->nblocks);
            CpeDead drops = {0};
            if (!cpe_paths(arena, f, &fl, bc, i, v, held, seen, &drops) || drops.n == 0 ||
                cpe_entered_elsewhere(f, &fl, bc, seen)) {
                continue;
            }
            touched[v] = true;
            touched[c] = true;
            rename[c] = v;
            cpe_dead_push(arena, &dead, bc, i);
            for (uint32_t k = 0; k < drops.n; k++) {
                cpe_dead_push(arena, &dead, drops.at[k].block, drops.at[k].index);
            }
        }
    }
    if (dead.n == 0) {
        return false;
    }
    cpe_remove_insts(arena, f, &dead);
    cpe_apply_rename(f, rename, true);
    return true;
}

/* ---- a copy that only lives next to its source ---- */

/* Where each value is defined, as (block, instruction) with `block == UINT32_MAX` for a parameter
 * or a value no instruction defines. */
static CpePos *cpe_defs(MsArena *arena, const MirFunc *f) {
    CpePos *defs = MS_NEW_N(arena, CpePos, (size_t)f->nvalues + 1);
    for (uint32_t v = 0; v <= f->nvalues; v++) {
        defs[v] = (CpePos){UINT32_MAX, 0};
    }
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            if (f->blocks[b].insts[i].res != MIR_NONE) {
                defs[f->blocks[b].insts[i].res] = (CpePos){b, i};
            }
        }
    }
    return defs;
}

static const MirInst *cpe_def_inst(const MirFunc *f, const CpePos *defs, MirValue v) {
    return defs[v].block == UINT32_MAX ? NULL : &f->blocks[defs[v].block].insts[defs[v].index];
}

/* The owned value (or parameter) `v` is ultimately read out of, followed through every kind of
 * projection: field, list element, optional payload, alternative payload, and a map entry (`load`
 * of the pointer a map lookup returns). False when the chain reaches a borrow it cannot see
 * through (a call returning a reference, a global), so the caller keeps its copy. */
static bool cpe_projection_owner(const MirModule *m, const MirFunc *f, const CpePos *defs, MirValue v,
                                MirValue *owner) {
    for (const MirInst *def = cpe_def_inst(f, defs, v); def != NULL; def = cpe_def_inst(f, defs, v)) {
        switch ((MirOp)def->op) {
        case MOP_TypeGet: case MOP_ListGet: case MOP_ListGetU: case MOP_ListGetNn:
        case MOP_OptGet: case MOP_AltGet:
            v = def->args[0];
            break;
        case MOP_Load: {
            const MirInst *ptr_def = cpe_def_inst(f, defs, def->args[0]);
            if (ptr_def == NULL || ptr_def->op != MOP_CallRt || ptr_def->nargs == 0) {
                return false;
            }
            v = ptr_def->args[0];
            break;
        }
        default: {
            MirMode mode = MM_BORROW;
            if (mir_result_mode(m, f, def, &mode) && mode == MM_MOVE) {
                *owner = v;
                return true;
            }
            return false;
        }
        }
    }
    *owner = v;
    return true;
}

/* What a string copy of `v` may borrow instead of copying: the owner (`*root`, MIR_NONE when `v`
 * is a parameter or a literal) of an element read out of a list, which stays valid while that owner
 * is only borrowed. False for any other source or when the owner cannot be traced. */
static bool cpe_str_source(const MirModule *m, const MirFunc *f, const CpePos *defs, MirValue v,
                          MirValue *root) {
    *root = MIR_NONE;
    const MirInst *def = cpe_def_inst(f, defs, v);
    if (def == NULL || def->op == MOP_StrLit) {
        return true;
    }
    if (def->op == MOP_ListGet || def->op == MOP_ListGetU || def->op == MOP_ListGetNn) {
        return cpe_projection_owner(m, f, defs, def->args[0], root);
    }
    return false;
}

/* The owner at the end of the field projections that produced `v`, or MIR_NONE when `v` is not
 * a projection. */
static MirValue cpe_field_root(const MirFunc *f, const CpePos *defs, MirValue v) {
    MirValue root = MIR_NONE;
    for (const MirInst *def = cpe_def_inst(f, defs, v); def != NULL && def->op == MOP_TypeGet;
         def = cpe_def_inst(f, defs, v)) {
        v = def->args[0];
        root = v;
    }
    return root;
}

/* What the copy-elimination of one function reads. */
typedef struct CpeLocal {
    const MirModule *m;
    const MirFunc *f;
    CpeUses at;
    CpePos *defs;
    uint32_t *uses;     /* operand and terminator uses per value */
    uint32_t *unstable; /* per block, prefix counts of memory-writing instructions; see `cpe_unstable` */
    uint32_t *unstable_base;
    MirMode *modes;     /* scratch for one instruction's argument modes */
} CpeLocal;

/* The number of the first `k` instructions of block `b` that write memory or touch reference
 * counts (other than `str.len` and `clone`), so a span is checked without a scan. */
static uint32_t cpe_unstable(const CpeLocal *l, uint32_t b, uint32_t k) {
    return l->unstable[l->unstable_base[b] + k];
}

static CpeLocal cpe_local(MsArena *arena, const MirModule *m, const MirFunc *f) {
    CpeLocal l = {m, f, cpe_operand_uses(arena, f), cpe_defs(arena, f), mir_use_counts(arena, f), NULL,
                 MS_NEW_N(arena, uint32_t, (size_t)f->nblocks + 1), NULL};
    uint32_t total = 0, most = 0;
    for (uint32_t b = 0; b < f->nblocks; b++) {
        l.unstable_base[b] = total;
        total += f->blocks[b].ninsts + 1;
        most = f->blocks[b].ninsts > most ? f->blocks[b].ninsts : most;
    }
    l.unstable = MS_NEW_N(arena, uint32_t, (size_t)total + 1);
    for (uint32_t b = 0; b < f->nblocks; b++) {
        uint32_t n = 0;
        l.unstable[l.unstable_base[b]] = 0;
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            const MirInst *inst = &f->blocks[b].insts[i];
            const uint8_t e = mir_op_info[inst->op].effects;
            if (((e & MIR_E_WRITES) != 0 && inst->op != MOP_StrLen) ||
                ((e & MIR_E_OWNERSHIP) != 0 && inst->op != MOP_Clone)) {
                n++;
            }
            l.unstable[l.unstable_base[b] + i + 1] = n;
        }
    }
    uint32_t widest = 1;
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            widest = f->blocks[b].insts[i].nargs > widest ? f->blocks[b].insts[i].nargs : widest;
        }
    }
    l.modes = MS_NEW_N(arena, MirMode, (size_t)widest + 1);
    (void)most;
    return l;
}

/* Whether an instruction of block `bi` strictly between `lo` and `hi` takes `x` other than by
 * borrow. */
static bool cpe_consumes(CpeLocal *l, MirValue x, uint32_t bi, uint32_t lo, uint32_t hi) {
    for (uint32_t u = 0; u < cpe_nuses(&l->at, x); u++) {
        const CpePos p = cpe_use(&l->at, x, u);
        if (p.block != bi || p.index <= lo || p.index >= hi) {
            continue;
        }
        const MirInst *n = &l->f->blocks[bi].insts[p.index];
        mir_arg_modes(l->m, l->f, n, l->modes);
        for (uint32_t a = 0; a < n->nargs; a++) {
            if (n->args[a] == x && l->modes[a] != MM_BORROW) {
                return true;
            }
        }
    }
    return false;
}

/* The first drop of `c` after instruction `i` of block `bi`; false when there is none. */
static bool cpe_first_drop(const CpeLocal *l, MirValue c, uint32_t bi, uint32_t i, uint32_t *j) {
    for (uint32_t u = 0; u < cpe_nuses(&l->at, c); u++) {
        const CpePos p = cpe_use(&l->at, c, u);
        if (p.block == bi && p.index > i && l->f->blocks[bi].insts[p.index].op == MOP_Drop) {
            *j = p.index;
            return true;
        }
    }
    return false;
}

static uint32_t cpe_uses_between(const CpeLocal *l, MirValue c, uint32_t bi, uint32_t i, uint32_t j) {
    uint32_t n = 0;
    for (uint32_t u = 0; u < cpe_nuses(&l->at, c); u++) {
        const CpePos p = cpe_use(&l->at, c, u);
        n += (p.block == bi && p.index > i && p.index < j) ? 1u : 0u;
    }
    return n;
}

/* Whether the copy `c = clone v` at `(bi, i)` dropped at `j` can be replaced by `v`. */
static bool cpe_local_copy_ok(CpeLocal *l, MirValue v, MirValue c, uint32_t bi, uint32_t i,
                             uint32_t j) {
    const MirModule *m = l->m;
    const MirFunc *f = l->f;
    const uint8_t kind = mir_ty_data(m, mir_value_ty(f, v))->kind;
    const bool is_str = kind == MK_STR;
    const bool composite = kind == MK_TYPE || kind == MK_ALT || kind == MK_OPT || kind == MK_LIST ||
                           kind == MK_BYTES;
    if (is_str) {
        /* Strings are immutable, so the copy can only differ from `v` once `v`'s owner releases or
         * replaces it. */
        MirValue root = MIR_NONE;
        if (!cpe_str_source(m, f, l->defs, v, &root) ||
            (root != MIR_NONE && cpe_consumes(l, root, bi, i, j))) {
            return false;
        }
    }
    if (composite && cpe_unstable(l, bi, j) > cpe_unstable(l, bi, i + 1)) {
        return false;
    }
    if (kind == MK_FN) {
        const MirValue root = cpe_field_root(f, l->defs, v);
        if (root != MIR_NONE && cpe_consumes(l, root, bi, i, j)) {
            return false; /* a closure read out of a type dies with the type */
        }
    }
    if (cpe_uses_between(l, c, bi, i, j) + 1 != l->uses[c]) {
        return false;
    }
    return !cpe_consumes(l, v, bi, i, j) && !cpe_consumes(l, c, bi, i, j);
}

/* Removes `c = clone v; ...; drop c` when the span only borrows the copy and its source stays
 * alive. Composite values additionally require a span without writes that could change or
 * release a projection's owner. String length may cache its result, but cannot release or
 * replace data. This includes read-only iteration over a list of types, which otherwise copies
 * every type on every visit. */
static bool cpe_borrow_local_copies(MsArena *arena, const MirModule *m, MirFunc *f) {
    CpeLocal l = cpe_local(arena, m, f);
    MirValue *alias = cpe_new_values(arena, f, MIR_NONE);
    CpeDead dead = {0};
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        for (uint32_t i = 0; i < f->blocks[bi].ninsts; i++) {
            const MirInst *inst = &f->blocks[bi].insts[i];
            if (inst->op != MOP_Clone || inst->res == MIR_NONE) {
                continue;
            }
            const MirValue c = inst->res, v = inst->args[0];
            const uint8_t kind = mir_ty_data(m, mir_value_ty(f, v))->kind;
            const bool wanted = kind == MK_FN || kind == MK_STR || kind == MK_TYPE ||
                                kind == MK_ALT || kind == MK_OPT || kind == MK_LIST ||
                                kind == MK_BYTES;
            uint32_t j = 0;
            if (!wanted || alias[v] != MIR_NONE || !cpe_first_drop(&l, c, bi, i, &j) ||
                !cpe_local_copy_ok(&l, v, c, bi, i, j)) {
                continue;
            }
            alias[c] = v;
            cpe_dead_push(arena, &dead, bi, i);
            cpe_dead_push(arena, &dead, bi, j);
        }
    }
    if (dead.n == 0) {
        return false;
    }
    cpe_remove_insts(arena, f, &dead);
    cpe_apply_rename(f, alias, false);
    return true;
}

/* ---- a copy of a value that never changes ---- */

/* Values that stay valid and unchanged for the whole function: borrowed parameters and borrowed
 * projections of them. */
static bool *cpe_stable_values(MsArena *arena, const MirFunc *f) {
    bool *stable = cpe_new_flags(arena, f);
    for (uint32_t p = 0; p < f->blocks[0].nparams; p++) {
        stable[f->blocks[0].params[p].value] = f->blocks[0].params[p].mode == MM_BORROW;
    }
    MirBlock *order = NULL;
    const uint32_t n = mir_rpo(arena, f, &order);
    /* Definitions precede uses in reverse post-order, so one sweep suffices. */
    for (uint32_t k = 0; k < n; k++) {
        const MirBlockData *b = &f->blocks[order[k]];
        for (uint32_t i = 0; i < b->ninsts; i++) {
            const MirInst *inst = &b->insts[i];
            const bool projection = inst->op == MOP_TypeGet || inst->op == MOP_AltGet ||
                                    inst->op == MOP_OptGet || inst->op == MOP_ListGet ||
                                    inst->op == MOP_ListGetNn || inst->op == MOP_ListGetU;
            if (projection && inst->res != MIR_NONE && stable[inst->args[0]]) {
                stable[inst->res] = true;
            }
        }
    }
    return stable;
}

/* Keeps an alias only while every use of the copy is a read-only operand or one of its drops. */
static void cpe_prune_aliases(MsArena *arena, const MirModule *m, const MirFunc *f,
                             MirValue *alias) {
    uint32_t widest = 1;
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            widest = f->blocks[b].insts[i].nargs > widest ? f->blocks[b].insts[i].nargs : widest;
        }
    }
    MirMode *modes = MS_NEW_N(arena, MirMode, (size_t)widest + 1);
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            const MirInst *inst = &f->blocks[b].insts[i];
            mir_arg_modes(m, f, inst, modes);
            for (uint32_t k = 0; k < inst->nargs; k++) {
                if (alias[inst->args[k]] != MIR_NONE && modes[k] != MM_BORROW &&
                    inst->op != MOP_Drop) {
                    alias[inst->args[k]] = MIR_NONE;
                }
            }
            if (inst->op == MOP_DropIf && inst->nargs > 1) {
                alias[inst->args[1]] = MIR_NONE;
            }
        }
    }
}

static void cpe_clear_term(void *ctx, MirValue v) {
    ((MirValue *)ctx)[v] = MIR_NONE;
}

/* Replaces each copy of a stable value by its source and removes the copies and their drops. */
static bool cpe_alias_stable(MsArena *arena, const MirModule *m, MirFunc *f) {
    const bool *stable = cpe_stable_values(arena, f);
    MirValue *alias = cpe_new_values(arena, f, MIR_NONE);
    bool any = false;
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            const MirInst *inst = &f->blocks[b].insts[i];
            if (inst->op == MOP_Clone && inst->res != MIR_NONE && stable[inst->args[0]]) {
                alias[inst->res] = inst->args[0];
                any = true;
            }
        }
    }
    if (!any) {
        return false;
    }
    cpe_prune_aliases(arena, m, f, alias);
    for (uint32_t b = 0; b < f->nblocks; b++) {
        mir_term_each_value(&f->blocks[b].term, cpe_clear_term, alias);
    }
    bool changed = false;
    for (uint32_t b = 0; b < f->nblocks; b++) {
        MirBlockData *blk = &f->blocks[b];
        uint32_t kept = 0;
        for (uint32_t i = 0; i < blk->ninsts; i++) {
            const MirInst *inst = &blk->insts[i];
            const bool gone = (inst->op == MOP_Clone && inst->res != MIR_NONE &&
                               alias[inst->res] != MIR_NONE) ||
                              (inst->op == MOP_Drop && alias[inst->args[0]] != MIR_NONE);
            changed |= gone;
            if (!gone) {
                blk->insts[kept++] = *inst;
            }
        }
        blk->ninsts = kept;
    }
    cpe_apply_rename(f, alias, false);
    return changed;
}

/* ---- moving a payload out of a dying shell ---- */

typedef struct CpeFind {
    MirValue v;
    bool hit;
} CpeFind;

static void cpe_term_find(void *ctx, MirValue v) {
    CpeFind *f = ctx;
    f->hit |= v == f->v;
}

static bool cpe_term_uses(const MirBlockData *b, MirValue v) {
    CpeFind find = {v, false};
    mir_term_each_value(&b->term, cpe_term_find, &find);
    return find.hit;
}

/* Replaces `insts[at]`'s operands by one value. */
static void cpe_set_single_arg(MirModule *m, MirInst *inst, MirValue v) {
    inst->args = MS_NEW_N(&m->arena, MirValue, 1);
    inst->args[0] = v;
    inst->nargs = 1;
}

/* Turns `p = opt.get v; c = clone p; ...; drop v` into `c = opt.unbox v` when `v` is not touched in
 * between and `p` has no other use: the payload moves out and the shell is freed instead of the
 * payload being deep-copied and then dropped with its source. This is the shape of unwrapping a
 * recursive result, which would otherwise copy every subtree once per level. */
static bool cpe_unbox_dead_options(MsArena *arena, MirModule *m, MirFunc *f) {
    const bool *tainted = cpe_view_tainted(arena, m, f);
    const uint32_t *uses = mir_use_counts(arena, f);
    bool changed = false;
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        MirBlockData *b = &f->blocks[bi];
        bool again = true;
        while (again) {
            again = false;
            const CpeBlockUses idx = cpe_block_uses(arena, b);
            for (uint32_t gi = 0; gi < b->ninsts && !again; gi++) {
                const MirInst *get = &b->insts[gi];
                if (get->op != MOP_OptGet || get->res == MIR_NONE) {
                    continue;
                }
                const MirValue p = get->res, v = get->args[0];
                uint32_t ci = 0, di = 0;
                if (uses[p] != 1 || tainted[v] || !cpe_first_after(&idx, b, p, gi, MOP_Clone, &ci) ||
                    !cpe_first_after(&idx, b, v, ci, MOP_Drop, &di)) {
                    continue;
                }
                /* The drop must be the only use of `v` after the load (`ci` reads `p`). */
                uint32_t cursor = cpe_after_start(&idx, v, gi), at = 0;
                bool other = cpe_term_uses(b, v);
                while (!other && cpe_after_next(&idx, v, &cursor, &at)) {
                    other = at != di;
                }
                if (other) {
                    continue;
                }
                b->insts[ci].op = MOP_OptUnbox;
                cpe_set_single_arg(m, &b->insts[ci], v);
                const uint32_t dead[2] = {gi, di};
                mir_block_remove(b, dead, 2);
                changed = true;
                again = true;
            }
        }
    }
    return changed;
}

/* The positions after `gi` that use `v` apart from the copy and the drop: each must be an
 * `alt.get` of a field that needs no drop (those are hoisted above the unbox). Collected in
 * `hoist`; false when another use exists, or one comes after the drop. */
static bool cpe_hoistable_loads(const MirBlockData *b, const CpeBlockUses *idx, const bool *nd,
                               MirValue v, uint32_t gi, uint32_t ci, uint32_t di, CpeDead *hoist,
                               MsArena *arena) {
    bool ok = true;
    uint32_t cursor = cpe_after_start(idx, v, gi), k = 0, last = UINT32_MAX;
    while (cpe_after_next(idx, v, &cursor, &k)) {
        if (last == k) {
            continue;
        }
        last = k;
        if (k > di) {
            return false;
        }
        if (k == ci || k == di) {
            continue;
        }
        const MirInst *n = &b->insts[k];
        if (n->op == MOP_AltGet && n->res != MIR_NONE && !nd[n->res]) {
            cpe_dead_push(arena, hoist, 0, k);
        } else {
            ok = false;
        }
    }
    return ok;
}

/* Rebuilds the block with the hoisted loads where the original `alt.get` was and the drop gone:
 * the unbox frees the block. */
static void cpe_hoist_rebuild(MirModule *m, MirBlockData *b, uint32_t gi, uint32_t di,
                             const CpeDead *hoist) {
    MirInst *out = MS_NEW_N(&m->arena, MirInst, (size_t)b->ninsts + 1);
    uint32_t n = 0;
    for (uint32_t k = 0; k < b->ninsts; k++) {
        bool hoisted = false;
        for (uint32_t h = 0; h < hoist->n; h++) {
            hoisted |= hoist->at[h].index == k;
        }
        if (k == gi) {
            for (uint32_t h = 0; h < hoist->n; h++) {
                out[n++] = b->insts[hoist->at[h].index];
            }
        } else if (k != di && !hoisted) {
            out[n++] = b->insts[k];
        }
    }
    b->insts = out;
    b->ninsts = n;
    b->cinsts = b->ninsts + 1;
}

/* Turns `p = alt.get f v; c = clone p; ...; drop v` into `c = alt.unbox f v` when `v` is otherwise
 * only read through `alt.get`s of fields that need no drop (those are hoisted above it). This is
 * the shape of `match cur: Link(_, next): cur = next` in a loop, which would otherwise deep-copy
 * the whole tail on every iteration. */
static bool cpe_unbox_dead_sources(MsArena *arena, MirModule *m, MirFunc *f) {
    const bool *tainted = cpe_view_tainted(arena, m, f);
    const uint32_t *uses = mir_use_counts(arena, f);
    bool *nd = cpe_new_flags(arena, f);
    for (uint32_t v = 0; v < f->nvalues; v++) {
        nd[v] = mir_needs_drop(m, f->values[v]);
    }
    bool changed = false;
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        MirBlockData *b = &f->blocks[bi];
        bool again = true;
        while (again) {
            again = false;
            const CpeBlockUses idx = cpe_block_uses(arena, b);
            for (uint32_t gi = 0; gi < b->ninsts && !again; gi++) {
                const MirInst *get = &b->insts[gi];
                if (get->op != MOP_AltGet || get->res == MIR_NONE) {
                    continue;
                }
                const MirValue p = get->res, v = get->args[0];
                uint32_t ci = 0, di = 0;
                CpeDead hoist = {0};
                if (uses[p] != 1 || !nd[p] || tainted[v] ||
                    !cpe_first_after(&idx, b, p, gi, MOP_Clone, &ci) ||
                    !cpe_first_after(&idx, b, v, ci, MOP_Drop, &di) ||
                    !cpe_hoistable_loads(b, &idx, nd, v, gi, ci, di, &hoist, arena)) {
                    continue;
                }
                b->insts[ci].op = MOP_AltUnbox;
                b->insts[ci].imm = get->imm;
                cpe_set_single_arg(m, &b->insts[ci], v);
                cpe_hoist_rebuild(m, b, gi, di, &hoist);
                changed = true;
                again = true;
            }
        }
    }
    return changed;
}

/* ---- taking fields out of a dying type ---- */

/* A field taken out of the dying type: the load, its copy, and the field. */
typedef struct CpeTaken {
    uint32_t get, copy, field;
} CpeTaken;

static uint32_t cpe_field_of(const MirInst *inst) {
    return inst->imm.tag == MI_FIELD ? inst->imm.b : UINT32_MAX;
}

/* The `type.get`s of `v` before its drop at `di`, in order; false when another instruction reads
 * `v` first or nothing can be taken (no get, a read between the first get and the drop that can
 * fault or unwind). */
static bool cpe_type_gets(const MirBlockData *b, MirValue v, uint32_t di, uint32_t *gets,
                         uint32_t *ngets) {
    *ngets = 0;
    for (uint32_t k = 0; k < di; k++) {
        bool reads = false;
        for (uint32_t a = 0; a < b->insts[k].nargs; a++) {
            reads |= b->insts[k].args[a] == v;
        }
        if (!reads) {
            continue;
        }
        if (b->insts[k].op != MOP_TypeGet) {
            return false;
        }
        gets[(*ngets)++] = k;
    }
    if (*ngets == 0) {
        return false;
    }
    for (uint32_t k = gets[0]; k < di; k++) {
        if (b->insts[k].op != MOP_TypeGet && b->insts[k].op != MOP_Clone) {
            return false;
        }
    }
    return true;
}

/* The loads whose copy can become a move out of the dying type. */
static uint32_t cpe_taken_fields(const MirBlockData *b, const CpeBlockUses *idx, const uint32_t *uses,
                                const bool *nd, const uint32_t *gets, uint32_t ngets, uint32_t di,
                                CpeTaken *taken) {
    uint32_t n = 0;
    for (uint32_t g = 0; g < ngets; g++) {
        const uint32_t gi = gets[g];
        const MirValue p = b->insts[gi].res;
        uint32_t ci = 0;
        if (p == MIR_NONE || uses[p] != 1 || !nd[p] || !cpe_first_after(idx, b, p, gi, MOP_Clone, &ci)) {
            continue;
        }
        const uint32_t fld = cpe_field_of(&b->insts[gi]);
        uint32_t same = 0;
        for (uint32_t h = 0; h < ngets; h++) {
            same += cpe_field_of(&b->insts[gets[h]]) == fld ? 1u : 0u;
        }
        /* A field taken once must not also be read through another `type.get`. */
        if (ci < di && same == 1) {
            taken[n++] = (CpeTaken){gi, ci, fld};
        }
    }
    return n;
}

/* Turns `p = type.get f v; c = clone p; ...; drop v` into `c = type.get f v` plus drops of the
 * other droppable fields of `v`, when `v` is only read through `type.get`s until its drop. The
 * field moves out of the dying type instead of being deep-copied and then freed with it, so
 * `w.inner.clone()` on a type that is dead afterwards costs no allocation. Nothing that can fault
 * or unwind may sit between the first load and the drop, so no cleanup sees the field both moved
 * and still owned by the type. Rewrites the first site found. */
static bool cpe_take_type_fields(MsArena *arena, const MirModule *m, MirFunc *f) {
    const bool *tainted = cpe_view_tainted(arena, m, f);
    const uint32_t *uses = mir_use_counts(arena, f);
    bool *nd = cpe_new_flags(arena, f);
    for (uint32_t v = 0; v < f->nvalues; v++) {
        nd[v] = mir_needs_drop(m, f->values[v]);
    }
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        MirBlockData *b = &f->blocks[bi];
        const CpeBlockUses idx = cpe_block_uses(arena, b);
        uint32_t *gets = MS_NEW_N(arena, uint32_t, (size_t)b->ninsts + 1);
        CpeTaken *taken = MS_NEW_N(arena, CpeTaken, (size_t)b->ninsts + 1);
        for (uint32_t di = 0; di < b->ninsts; di++) {
            const MirInst *drop = &b->insts[di];
            if (drop->op != MOP_Drop || drop->nargs == 0) {
                continue;
            }
            const MirValue v = drop->args[0];
            uint32_t ngets = 0, cursor = cpe_after_start(&idx, v, di), at = 0;
            if (mir_ty_data(m, mir_value_ty(f, v))->kind != MK_TYPE || tainted[v] ||
                cpe_after_next(&idx, v, &cursor, &at) || !cpe_type_gets(b, v, di, gets, &ngets)) {
                continue;
            }
            const uint32_t n = cpe_taken_fields(b, &idx, uses, nd, gets, ngets, di, taken);
            if (n == 0 || b->insts[taken[0].get].imm.tag != MI_FIELD) {
                continue;
            }
            const uint32_t type = b->insts[taken[0].get].imm.a;
            uint32_t mask = 0;
            for (uint32_t k = 0; k < n; k++) {
                b->insts[taken[k].copy].op = MOP_MoveOut;
                mask |= UINT32_C(1) << taken[k].field;
            }
            b->insts[di].op = MOP_TypeRelease;
            b->insts[di].imm = (MirImm){.tag = MI_TYPEMASK, .a = type, .b = mask};
            return true;
        }
    }
    return false;
}

/* ---- the pass ---- */

bool mir_opt_copyelim_func(MirModule *m, MirFunc *f) {
    MsArena arena = {0};
    bool changed = cpe_alias_stable(&arena, m, f);
    changed |= cpe_move_dead_sources(&arena, m, f);
    changed |= cpe_move_across(&arena, m, f);
    changed |= cpe_borrow_local_copies(&arena, m, f);
    changed |= cpe_unbox_dead_sources(&arena, m, f);
    changed |= cpe_unbox_dead_options(&arena, m, f);
    ms_arena_free(&arena);
    return changed;
}

bool mir_opt_copyelim(MirModule *m) {
    bool changed = false;
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        changed |= mir_opt_copyelim_func(m, &m->funcs[fi]);
    }
    return changed;
}

bool mir_opt_copyelim_takes(MirModule *m) {
    bool changed = false;
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        for (;;) {
            MsArena arena = {0};
            const bool took = cpe_take_type_fields(&arena, m, &m->funcs[fi]);
            ms_arena_free(&arena);
            if (!took) {
                break;
            }
            changed = true;
        }
    }
    return changed;
}

/* The control-flow half of `simplify`: block merging and jump threading, dominator-scoped value
 * numbering, and the two rewrites of repeated map probes. Port of `branches`,
 * `thread_flag_branches`, `cse`, `map_probes` and `fuse_contains` of
 * crates/ms-mir/src/opt/simplify.rs; the order of every rewrite and of every value it makes is the
 * Rust pass's. */
#include <stdlib.h>
#include <string.h>

#include "opt/opt_simplify.h"

/* ---- small helpers ---- */

/* A growable list of block or value ids in a scratch arena. */
typedef struct SbList {
    uint32_t *v;
    uint32_t n, cap;
} SbList;

static void sb_push(MsArena *a, SbList *l, uint32_t x) {
    if (l->n == l->cap) {
        const uint32_t cap = l->cap ? l->cap * 2 : 4;
        uint32_t *grown = ms_alloc(a, sizeof(uint32_t) * cap, _Alignof(uint32_t));
        if (l->n > 0) {
            memcpy(grown, l->v, sizeof(uint32_t) * l->n);
        }
        l->v = grown;
        l->cap = cap;
    }
    l->v[l->n++] = x;
}

/* Removes the instructions flagged in `dead[bi][ii]` from every block. */
static bool sb_has_value(const MirValue *v, uint32_t n, MirValue x) {
    for (uint32_t k = 0; k < n; k++) {
        if (v[k] == x) {
            return true;
        }
    }
    return false;
}

/* ---- block merging and jump threading ---- */

/* Merges a block into its unique predecessor when that predecessor falls into it; true when it
 * merged anything. */
static bool sb_merge_blocks(MirModule *m, MirFunc *f) {
    MsArena arena = {0};
    uint32_t *edges = ms_alloc_zeroed(&arena, f->nblocks, sizeof(uint32_t));
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        const MirTerm *t = &f->blocks[bi].term;
        for (uint32_t s = 0; s < mir_term_ntargets(t); s++) {
            edges[mir_term_target_const(t, s)->block]++;
        }
    }
    MirSubst subst = mir_subst_new(&arena, f->nvalues);
    bool merged = false;
    for (uint32_t p = 0; p < f->nblocks; p++) {
        /* A consumed block was emptied and ends in `unreachable`, so it is skipped. */
        while (f->blocks[p].term.kind == MT_BR) {
            const MirTarget t = f->blocks[p].term.a;
            const uint32_t b = t.block;
            if (b == 0 || b == p || edges[b] != 1) {
                break;
            }
            merged = true;
            const MirBlockData bd = f->blocks[b];
            f->blocks[b] = mir_block_empty();
            mir_block_append(m, &f->blocks[p], bd.insts, bd.ninsts);
            f->blocks[p].term = bd.term;
            f->blocks[p].term_loc = bd.term_loc;
            for (uint32_t k = 0; k < bd.nparams && k < t.nargs; k++) {
                mir_subst_set(&subst, bd.params[k].value, t.args[k]);
            }
        }
    }
    if (merged) {
        mir_subst_apply(f, &subst);
        mir_func_compact_blocks(f);
    }
    ms_arena_free(&arena);
    return merged;
}

/* Redirects the edges into empty block `b`, which only forwards its arguments to `t`. */
static bool sb_thread_block(MirModule *m, MirFunc *f, SbList *preds, MsArena *arena, uint32_t b,
                            const uint32_t *uses) {
    if (f->blocks[b].ninsts != 0 || f->blocks[b].term.kind != MT_BR) {
        return false;
    }
    const MirTarget t = f->blocks[b].term.a;
    if (t.block == b) {
        return false;
    }
    const MirBlockData *blk = &f->blocks[b];
    for (uint32_t k = 0; k < blk->nparams; k++) {
        uint32_t in_args = 0;
        for (uint32_t a = 0; a < t.nargs; a++) {
            in_args += t.args[a] == blk->params[k].value;
        }
        if (uses[blk->params[k].value] != in_args) {
            return false;
        }
    }
    bool did = false;
    const SbList taken = preds[b];
    preds[b] = (SbList){0};
    for (uint32_t k = 0; k < taken.n; k++) {
        const uint32_t pb = taken.v[k];
        if (pb == b) {
            sb_push(arena, &preds[b], pb);
            continue;
        }
        MirTerm *term = &f->blocks[pb].term;
        for (uint32_t s = 0; s < mir_term_ntargets(term); s++) {
            MirTarget *e = mir_term_target(term, s);
            if (e->block != b) {
                continue;
            }
            MirValue *args = MS_NEW_N(&m->arena, MirValue, t.nargs + 1);
            for (uint32_t a = 0; a < t.nargs; a++) {
                uint32_t pos = 0;
                while (pos < blk->nparams && blk->params[pos].value != t.args[a]) {
                    pos++;
                }
                args[a] = pos < blk->nparams ? e->args[pos] : t.args[a];
            }
            e->block = t.block;
            e->args = args;
            e->nargs = t.nargs;
            did = true;
        }
        /* A repeated entry only revisits a block whose edges already moved. */
        sb_push(arena, &preds[t.block], pb);
    }
    return did;
}

/* Threads edges through empty blocks that only forward their arguments. */
static bool sb_thread_edges(MirModule *m, MirFunc *f) {
    MsArena arena = {0};
    uint32_t *uses = mir_use_counts(&arena, f);
    /* The blocks whose terminator targets each block, kept current as edges move. */
    SbList *preds = ms_alloc_zeroed(&arena, f->nblocks, sizeof(SbList));
    for (uint32_t pb = 0; pb < f->nblocks; pb++) {
        const MirTerm *t = &f->blocks[pb].term;
        for (uint32_t s = 0; s < mir_term_ntargets(t); s++) {
            SbList *l = &preds[mir_term_target_const(t, s)->block];
            if (l->n == 0 || l->v[l->n - 1] != pb) {
                sb_push(&arena, l, pb);
            }
        }
    }
    bool changed = false;
    for (uint32_t b = 1; b < f->nblocks; b++) {
        changed |= sb_thread_block(m, f, preds, &arena, b, uses);
    }
    ms_arena_free(&arena);
    return changed;
}

/* Jump threading through a flag join: an empty block whose only parameter is a `Bool` that its
 * terminator branches on (the join of `a and b` or `a or b` used as a condition). An edge that
 * passes a constant goes straight to the target that constant selects. Values the targets read
 * dominate the join, hence its predecessors. */
static bool sb_thread_flag_branches(MirModule *m, MirFunc *f) {
    MsArena arena = {0};
    uint8_t *flag = ms_alloc_zeroed(&arena, f->nvalues, 1); /* 0 unknown, 1 false, 2 true */
    bool any = false;
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        for (uint32_t ii = 0; ii < f->blocks[bi].ninsts; ii++) {
            const MirInst *i = &f->blocks[bi].insts[ii];
            if (i->op == MOP_BConst && i->imm.tag == MI_BOOL && i->res != MIR_NONE) {
                flag[i->res] = i->imm.a != 0 ? 2 : 1;
                any = true;
            }
        }
    }
    uint32_t *uses = any ? mir_use_counts(&arena, f) : NULL;
    bool changed = false;
    for (uint32_t j = 1; any && j < f->nblocks; j++) {
        const MirBlockData *blk = &f->blocks[j];
        if (blk->nparams != 1 || blk->term.kind != MT_CONDBR) {
            continue;
        }
        const MirBlockParam param = blk->params[0];
        const MirTarget then = blk->term.a, els = blk->term.b;
        /* The flag must feed only this branch: a bypassing edge no longer defines it. */
        if (blk->ninsts != 0 || blk->term.value != param.value || param.mode != MM_BORROW ||
            uses[param.value] != 1) {
            continue;
        }
        if (then.block == j || els.block == j || sb_has_value(then.args, then.nargs, param.value) ||
            sb_has_value(els.args, els.nargs, param.value)) {
            continue;
        }
        for (uint32_t pb = 0; pb < f->nblocks; pb++) {
            MirTerm *term = &f->blocks[pb].term;
            for (uint32_t s = 0; pb != j && s < mir_term_ntargets(term); s++) {
                MirTarget *e = mir_term_target(term, s);
                if (e->block != j || e->nargs == 0 || flag[e->args[0]] == 0) {
                    continue;
                }
                *e = mir_target_clone(m, flag[e->args[0]] == 2 ? &then : &els);
                changed = true;
            }
        }
    }
    ms_arena_free(&arena);
    return changed;
}

bool mir_simplify_branches(MirModule *m, MirFunc *f) {
    bool changed = false;
    const uint32_t before = f->nblocks;
    mir_func_compact_blocks(f);
    changed |= f->nblocks != before;
    while (sb_merge_blocks(m, f)) {
        changed = true;
    }
    changed |= sb_thread_edges(m, f);
    changed |= sb_thread_flag_branches(m, f);
    const uint32_t after_threading = f->nblocks;
    mir_func_compact_blocks(f);
    return changed || f->nblocks != after_threading;
}

/* ---- value numbering ---- */

/* An expression table for value numbering over a dominator tree: entries are added on entering a
 * block and dropped, newest first, on leaving it. */
typedef struct SbEntry {
    uint64_t hash;
    uint8_t op;
    MirImm imm;
    MirTy ty;
    uint32_t arg_start, nargs;
    MirValue value;
    uint32_t next; /* the previous entry of the bucket plus one */
} SbEntry;

typedef struct SbTable {
    uint32_t *heads;
    uint32_t mask;
    SbEntry *entries;
    uint32_t nentries;
    MirValue *operands;
    uint32_t noperands;
} SbTable;

static uint64_t sb_mix(uint64_t h, uint64_t x) {
    h ^= x + UINT64_C(0x9E3779B97F4A7C15) + (h << 6) + (h >> 2);
    return h * UINT64_C(0xFF51AFD7ED558CCD);
}

static uint64_t sb_hash(uint8_t op, const MirImm *imm, MirTy ty, const MirValue *args,
                        uint32_t nargs) {
    uint64_t h = sb_mix(op, ty);
    h = sb_mix(h, imm->tag);
    h = sb_mix(h, ((uint64_t)imm->a << 32) | imm->b);
    h = sb_mix(h, ((uint64_t)imm->c << 32) | (uint64_t)imm->tag);
    h = sb_mix(h, (uint64_t)imm->i);
    for (uint32_t k = 0; k < nargs; k++) {
        h = sb_mix(h, args[k]);
    }
    return h ^ (h >> 29);
}

static SbTable sb_table_new(MsArena *arena, uint32_t expected, uint32_t operands) {
    uint32_t size = 16;
    while (size < expected * 2) {
        size *= 2;
    }
    SbTable t = {0};
    t.heads = ms_alloc_zeroed(arena, size, sizeof(uint32_t));
    t.mask = size - 1;
    t.entries = MS_NEW_N(arena, SbEntry, (size_t)expected + 1);
    t.operands = MS_NEW_N(arena, MirValue, (size_t)operands + 1);
    return t;
}

static bool sb_table_get(const SbTable *t, uint8_t op, const MirImm *imm, MirTy ty,
                         const MirValue *args, uint32_t nargs, MirValue *out) {
    const uint64_t hash = sb_hash(op, imm, ty, args, nargs);
    for (uint32_t at = t->heads[hash & t->mask]; at != 0;) {
        const SbEntry *e = &t->entries[at - 1];
        if (e->hash == hash && e->op == op && e->ty == ty && mir_imm_eq(&e->imm, imm) &&
            e->nargs == nargs &&
            (nargs == 0 || memcmp(&t->operands[e->arg_start], args, sizeof(MirValue) * nargs) == 0)) {
            *out = e->value;
            return true;
        }
        at = e->next;
    }
    return false;
}

static void sb_table_insert(SbTable *t, uint8_t op, const MirImm *imm, MirTy ty,
                            const MirValue *args, uint32_t nargs, MirValue value) {
    const uint64_t hash = sb_hash(op, imm, ty, args, nargs);
    const uint32_t bucket = (uint32_t)(hash & t->mask);
    SbEntry *e = &t->entries[t->nentries++];
    *e = (SbEntry){hash, op, *imm, ty, t->noperands, nargs, value, t->heads[bucket]};
    if (nargs > 0) {
        memcpy(&t->operands[t->noperands], args, sizeof(MirValue) * nargs);
    }
    t->noperands += nargs;
    t->heads[bucket] = t->nentries;
}

/* Drops every entry added since `mark`. */
static void sb_table_reset(SbTable *t, uint32_t mark) {
    while (t->nentries > mark) {
        const SbEntry *e = &t->entries[--t->nentries];
        t->heads[e->hash & t->mask] = e->next;
        t->noperands = e->arg_start;
    }
}

typedef struct SbCse {
    MirModule *m;
    MirFunc *f;
    SbTable table;
    MirSubst subst;
    bool **dead;
    MirValue *scratch; /* resolved operands of one instruction */
    bool any;
} SbCse;

static int sb_cmp_value(const void *a, const void *b) {
    const MirValue x = *(const MirValue *)a, y = *(const MirValue *)b;
    if (x == y) {
        return 0;
    }
    return x < y ? -1 : 1;
}

/* Whether instruction `inst` takes part in value numbering. */
static bool sb_numbered(const MirModule *m, const MirInst *inst, MirTy ty) {
    const bool checked = inst->op == MOP_IAddChk || inst->op == MOP_ISubChk ||
                         inst->op == MOP_IMulChk || inst->op == MOP_INegChk ||
                         inst->op == MOP_SDivChk || inst->op == MOP_SRemChk;
    /* A field read is a borrowed view of an immutable type value, so repeating it yields the
     * same view even when the field's type owns heap data. */
    const bool view = inst->op == MOP_TypeGet;
    const MirOpInfo *info = &mir_op_info[inst->op];
    const bool numberable = info->effects == 0 && info->has_result && inst->op != MOP_Slot &&
                            inst->op != MOP_Clone;
    if (!(numberable || inst->op == MOP_AltTag || checked || view)) {
        return false;
    }
    return !mir_needs_drop(m, ty) || view;
}

static void sb_number_block(SbCse *c, uint32_t b) {
    const MirBlockData *blk = &c->f->blocks[b];
    for (uint32_t ii = 0; ii < blk->ninsts; ii++) {
        const MirInst *inst = &blk->insts[ii];
        if (inst->res == MIR_NONE) {
            continue;
        }
        const MirTy ty = c->f->values[inst->res];
        if (!sb_numbered(c->m, inst, ty)) {
            continue;
        }
        for (uint32_t k = 0; k < inst->nargs; k++) {
            c->scratch[k] = mir_subst_resolve(&c->subst, inst->args[k]);
        }
        if (mir_op_commutative(inst->op, &inst->imm) && inst->nargs > 1) {
            qsort(c->scratch, inst->nargs, sizeof(MirValue), sb_cmp_value);
        }
        MirValue prev = 0;
        if (sb_table_get(&c->table, inst->op, &inst->imm, ty, c->scratch, inst->nargs, &prev)) {
            mir_subst_set(&c->subst, inst->res, prev);
            c->dead[b][ii] = true;
            c->any = true;
        } else {
            sb_table_insert(&c->table, inst->op, &inst->imm, ty, c->scratch, inst->nargs, inst->res);
        }
    }
}

bool mir_simplify_cse(MirModule *m, MirFunc *f) {
    MsArena arena = {0};
    MirBlock *order = NULL;
    const uint32_t count = mir_rpo(&arena, f, &order);
    const MirPreds preds = mir_preds(&arena, f);
    const MirBlock *idom = mir_dominators(&arena, f, order, count, &preds);
    /* The dominator tree: block b's children are `child[cstart[b]..cstart[b + 1]]`, in
     * reverse post-order. */
    uint32_t *cstart = ms_alloc_zeroed(&arena, (size_t)f->nblocks + 2, sizeof(uint32_t));
    for (uint32_t k = 0; k < count; k++) {
        const uint32_t i = order[k];
        if (i != 0 && idom[i] != MIR_NONE) {
            cstart[idom[i] + 1]++;
        }
    }
    for (uint32_t b = 0; b < f->nblocks; b++) {
        cstart[b + 1] += cstart[b];
    }
    uint32_t *fill = ms_alloc_zeroed(&arena, (size_t)f->nblocks + 1, sizeof(uint32_t));
    memcpy(fill, cstart, sizeof(uint32_t) * f->nblocks);
    uint32_t *child = ms_alloc_zeroed(&arena, (size_t)cstart[f->nblocks] + 1, sizeof(uint32_t));
    for (uint32_t k = 0; k < count; k++) {
        const uint32_t i = order[k];
        if (i != 0 && idom[i] != MIR_NONE) {
            child[fill[idom[i]]++] = i;
        }
    }
    uint32_t insts = 0, operands = 0, widest = 1;
    for (uint32_t b = 0; b < f->nblocks; b++) {
        insts += f->blocks[b].ninsts;
        for (uint32_t ii = 0; ii < f->blocks[b].ninsts; ii++) {
            operands += f->blocks[b].insts[ii].nargs;
            widest = f->blocks[b].insts[ii].nargs > widest ? f->blocks[b].insts[ii].nargs : widest;
        }
    }
    SbCse c = {.m = m, .f = f};
    c.table = sb_table_new(&arena, insts, operands);
    c.subst = mir_subst_new(&arena, f->nvalues);
    c.dead = mir_dead_flags(&arena, f);
    c.scratch = MS_NEW_N(&arena, MirValue, widest);
    /* An explicit walk of the dominator tree: an entry is a block to enter, or (high bit set) the
     * table mark to return to on leaving one. */
    const uint64_t exit_bit = UINT64_C(1) << 63;
    uint64_t *stack = MS_NEW_N(&arena, uint64_t, 2 * (size_t)f->nblocks + 2);
    uint32_t nstack = 0;
    stack[nstack++] = 0;
    while (nstack > 0) {
        const uint64_t s = stack[--nstack];
        if ((s & exit_bit) != 0) {
            sb_table_reset(&c.table, (uint32_t)s);
            continue;
        }
        const uint32_t b = (uint32_t)s;
        stack[nstack++] = exit_bit | c.table.nentries;
        sb_number_block(&c, b);
        for (uint32_t k = cstart[b + 1]; k-- > cstart[b];) {
            stack[nstack++] = child[k];
        }
    }
    if (c.any) {
        mir_sweep_dead(f, (bool *const *)c.dead, &arena);
        mir_subst_apply(f, &c.subst);
    }
    ms_arena_free(&arena);
    return c.any;
}

/* ---- repeated map probes ---- */

static bool sb_name_eq(const MirModule *m, MsSym sym, const char *text) {
    const MsStr s = ms_name(&m->names, sym);
    return s.len == strlen(text) && memcmp(s.ptr, text, s.len) == 0;
}

/* The runtime function a call instruction names; NULL when it is not a runtime call. */
static const MirExtern *sb_extern_of(const MirModule *m, const MirInst *i) {
    return i->op == MOP_CallRt && i->imm.tag == MI_EXT ? &m->externs[i->imm.a] : NULL;
}

/* The runtime lookups that return the address of a map entry (or null). */
static bool sb_is_map_probe(const MirModule *m, const MirInst *i) {
    const MirExtern *e = sb_extern_of(m, i);
    return e != NULL && (sb_name_eq(m, e->name, "msrt_map_get_ptr") ||
                         sb_name_eq(m, e->name, "msrt_map_get_ptr_w8") ||
                         sb_name_eq(m, e->name, "msrt_map_get_ptr_sw8"));
}

/* Whether `i` can insert into, remove from or move a map. A type update drops the field it
 * replaces, never a map being probed. */
static bool sb_clobbers(const MirInst *i) {
    const uint8_t e = mir_op_info[i->op].effects;
    return (e & (MIR_E_IO | MIR_E_OWNERSHIP | MIR_E_ALLOC)) != 0 && i->op != MOP_TypeSet;
}

typedef struct SbProbe {
    uint32_t ext;
    MirValue a0, a1, a2, key, value;
} SbProbe;

/* The probes of one point in a block and the entry each found. */
typedef struct SbProbes {
    SbProbe *v;
    uint32_t n, cap;
} SbProbes;

static SbProbes sb_probes_copy(MsArena *arena, const SbProbes *src) {
    SbProbes c = {0};
    if (src != NULL && src->n > 0) {
        c.v = ms_alloc(arena, sizeof(SbProbe) * src->n, _Alignof(SbProbe));
        memcpy(c.v, src->v, sizeof(SbProbe) * src->n);
        c.n = c.cap = src->n;
    }
    return c;
}

static bool sb_probes_get(const SbProbes *t, const SbProbe *key, MirValue *out) {
    for (uint32_t k = 0; k < t->n; k++) {
        const SbProbe *p = &t->v[k];
        if (p->ext == key->ext && p->a0 == key->a0 && p->a1 == key->a1 && p->a2 == key->a2 &&
            p->key == key->key) {
            *out = p->value;
            return true;
        }
    }
    return false;
}

static void sb_probes_add(MsArena *arena, SbProbes *t, SbProbe p) {
    if (t->n == t->cap) {
        const uint32_t cap = t->cap ? t->cap * 2 : 4;
        SbProbe *grown = ms_alloc(arena, sizeof(SbProbe) * cap, _Alignof(SbProbe));
        if (t->n > 0) {
            memcpy(grown, t->v, sizeof(SbProbe) * t->n);
        }
        t->v = grown;
        t->cap = cap;
    }
    t->v[t->n++] = p;
}

/* The value stored into each key slot of the block so far: a stamp per slot, valid while it equals
 * the current generation. */
typedef struct SbStored {
    uint32_t *stamp;
    MirValue *key;
    uint32_t gen;
} SbStored;

typedef struct SbProbeRun {
    MirModule *m;
    MirFunc *f;
    MsArena *arena;
    MirSubst subst;
    bool **removed;
    SbList slots_dropped;
    SbStored stored;
} SbProbeRun;

static void sb_stored_set(SbStored *s, MirValue slot, MirValue key) {
    s->stamp[slot] = s->gen;
    s->key[slot] = key;
}

static bool sb_stored_get(const SbStored *s, MirValue slot, MirValue *key) {
    if (s->stamp[slot] != s->gen) {
        return false;
    }
    *key = s->key[slot];
    return true;
}

/* A probe of a map seen before in the block, with the key it was stored under: reuse the earlier
 * address, or record this probe. */
static void sb_note_probe(SbProbeRun *run, SbProbes *table, uint32_t bi, uint32_t ii,
                          const MirInst *inst) {
    MirValue a[4];
    for (uint32_t k = 0; k < 4; k++) {
        a[k] = mir_subst_resolve(&run->subst, inst->args[k]);
    }
    MirValue key = 0;
    if (!sb_stored_get(&run->stored, a[3], &key) || inst->res == MIR_NONE) {
        return;
    }
    const SbProbe probe = {inst->imm.a, a[0], a[1], a[2], key, inst->res};
    MirValue prev = 0;
    if (sb_probes_get(table, &probe, &prev)) {
        mir_subst_set(&run->subst, inst->res, prev);
        run->removed[bi][ii] = true;
        sb_push(run->arena, &run->slots_dropped, a[3]);
    } else {
        sb_probes_add(run->arena, table, probe);
    }
}

static void sb_probe_inst(SbProbeRun *run, SbProbes *table, uint32_t bi, uint32_t ii) {
    const MirInst *inst = &run->f->blocks[bi].insts[ii];
    if (sb_is_map_probe(run->m, inst) && inst->nargs == 4) {
        sb_note_probe(run, table, bi, ii, inst);
        return;
    }
    if (inst->op == MOP_Store || inst->op == MOP_Put || inst->op == MOP_Take) {
        run->stored.stamp[inst->args[0]] = 0;
        if (inst->op == MOP_Store) {
            sb_stored_set(&run->stored, inst->args[0],
                          mir_subst_resolve(&run->subst, inst->args[1]));
        }
    } else if (sb_clobbers(inst)) {
        table->n = 0;
        run->stored.gen++;
    }
}

/* A probe of the same map for the same key, with nothing between that can change the map's
 * layout, finds the same entry: the later call reuses the earlier address. The key reaches the
 * runtime through a stack slot filled just before the call, so the key is the value stored there.
 * The table follows a block into its only successor (a fault branch or an `if` arm) and is dropped
 * at a join or loop header, and at any instruction that calls out, drops, clones or allocates. */
bool mir_simplify_map_probes(MirModule *m, MirFunc *f) {
    bool any = false;
    for (uint32_t bi = 0; bi < f->nblocks && !any; bi++) {
        for (uint32_t ii = 0; ii < f->blocks[bi].ninsts && !any; ii++) {
            any = sb_is_map_probe(m, &f->blocks[bi].insts[ii]);
        }
    }
    if (!any) {
        return false;
    }
    MsArena arena = {0};
    const MirPreds preds = mir_preds(&arena, f);
    SbProbes **ends = ms_alloc_zeroed(&arena, f->nblocks, sizeof(SbProbes *));
    SbProbeRun run = {.m = m, .f = f, .arena = &arena};
    run.subst = mir_subst_new(&arena, f->nvalues);
    run.removed = mir_dead_flags(&arena, f);
    run.stored.stamp = ms_alloc_zeroed(&arena, f->nvalues, sizeof(uint32_t));
    run.stored.key = ms_alloc_zeroed(&arena, f->nvalues, sizeof(MirValue));
    MirBlock *order = NULL;
    const uint32_t count = mir_rpo(&arena, f, &order);
    bool removed_any = false;
    for (uint32_t k = 0; k < count; k++) {
        const uint32_t bi = order[k];
        const bool single = mir_preds_count(&preds, bi) == 1 && mir_pred(&preds, bi, 0) != bi;
        SbProbes *table = MS_NEW(&arena, SbProbes);
        *table = sb_probes_copy(&arena, single ? ends[mir_pred(&preds, bi, 0)] : NULL);
        run.stored.gen++;
        for (uint32_t ii = 0; ii < f->blocks[bi].ninsts; ii++) {
            sb_probe_inst(&run, table, bi, ii);
        }
        ends[bi] = table;
    }
    removed_any = run.slots_dropped.n > 0 || run.subst.count > 0;
    if (removed_any) {
        /* The key slot of a removed probe is only filled and never read again: drop both. */
        uint32_t *uses = mir_use_counts(&arena, f);
        bool *dead_slot = ms_alloc_zeroed(&arena, f->nvalues, sizeof(bool));
        for (uint32_t k = 0; k < run.slots_dropped.n; k++) {
            dead_slot[run.slots_dropped.v[k]] = uses[run.slots_dropped.v[k]] == 2;
        }
        for (uint32_t bi = 0; bi < f->nblocks; bi++) {
            for (uint32_t ii = 0; ii < f->blocks[bi].ninsts; ii++) {
                const MirInst *i = &f->blocks[bi].insts[ii];
                const bool slot_store = i->op == MOP_Store && dead_slot[i->args[0]];
                const bool slot_def = i->op == MOP_Slot && i->res != MIR_NONE && dead_slot[i->res];
                run.removed[bi][ii] |= slot_store || slot_def;
            }
        }
        mir_sweep_dead(f, (bool *const *)run.removed, &arena);
        mir_subst_apply(f, &run.subst);
    }
    ms_arena_free(&arena);
    return removed_any;
}

/* ---- joining a `contains` test with the lookup after it ---- */

/* What one predecessor of a join passes for the map, and the earlier probe or `contains` of it. */
typedef struct SbPredPlan {
    uint32_t block;
    MirValue map;
    bool has_hit;
    uint32_t hit_block, hit_inst;
    bool hit_contains;
} SbPredPlan;

/* Facts about the function's slots and type descriptors, gathered once. */
typedef struct SbFacts {
    uint8_t *key_state; /* per slot: 0 never stored, 1 stored one value, 2 stored several */
    MirValue *key;
    MirImm *slot_imm;
    bool *is_slot;
    MirImm *desc_imm;
    MirTy *desc_ty;
    bool *is_desc;
    uint32_t *uses;
} SbFacts;

static SbFacts sb_facts(MsArena *arena, const MirFunc *f) {
    const uint32_t n = f->nvalues;
    SbFacts s = {ms_alloc_zeroed(arena, n, 1), ms_alloc_zeroed(arena, n, sizeof(MirValue)),
                 ms_alloc_zeroed(arena, n, sizeof(MirImm)), ms_alloc_zeroed(arena, n, sizeof(bool)),
                 ms_alloc_zeroed(arena, n, sizeof(MirImm)), ms_alloc_zeroed(arena, n, sizeof(MirTy)),
                 ms_alloc_zeroed(arena, n, sizeof(bool)), mir_use_counts(arena, f)};
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        for (uint32_t ii = 0; ii < f->blocks[bi].ninsts; ii++) {
            const MirInst *i = &f->blocks[bi].insts[ii];
            if (i->op == MOP_Slot && i->res != MIR_NONE) {
                s.is_slot[i->res] = true;
                s.slot_imm[i->res] = i->imm;
            } else if (i->op == MOP_TypeDesc && i->res != MIR_NONE) {
                s.is_desc[i->res] = true;
                s.desc_imm[i->res] = i->imm;
                s.desc_ty[i->res] = f->values[i->res];
            } else if (i->op == MOP_Store) {
                const MirValue slot = i->args[0];
                s.key_state[slot] = s.key_state[slot] == 0 ? 1 : 2;
                s.key[slot] = i->args[1];
            }
        }
    }
    return s;
}

/* The arguments `pb` passes to `ji` when it has exactly one edge there; false otherwise. */
static bool sb_arm_args(const MirFunc *f, uint32_t pb, uint32_t ji, const MirValue **args,
                        uint32_t *nargs) {
    const MirTerm *t = &f->blocks[pb].term;
    const MirTarget *arm = NULL;
    if (t->kind == MT_BR && t->a.block == ji) {
        arm = &t->a;
    } else if (t->kind == MT_CONDBR && (t->a.block == ji) != (t->b.block == ji)) {
        arm = t->a.block == ji ? &t->a : &t->b;
    }
    if (arm == NULL) {
        return false;
    }
    *args = arm->args;
    *nargs = arm->nargs;
    return true;
}

typedef struct SbJoin {
    MirModule *m;
    MirFunc *f;
    SbFacts facts;
    MirPreds preds;
    uint32_t ji;
    MirInst probe;
    MirValue key;
    const MirExtern *probe_ext;
    char pname[160], contains_name[160];
    uint32_t map_param;
} SbJoin;

static bool sb_ext_is(const MirModule *m, const MirExtern *e, const char *text) {
    return sb_name_eq(m, e->name, text);
}

/* Whether `i` is a probe or `contains` of map `a` for the join's key, with the join's descriptors;
 * *contains tells which. */
static bool sb_matches(const SbJoin *j, const MirInst *i, MirValue a, bool *contains) {
    const MirExtern *e = sb_extern_of(j->m, i);
    const SbFacts *s = &j->facts;
    if (e == NULL || i->nargs != 4 || i->args[0] != a) {
        return false;
    }
    const MirValue slot = i->args[3];
    if (s->key_state[slot] != 1 || s->key[slot] != j->key || !s->is_desc[i->args[1]] ||
        !s->is_desc[i->args[2]]) {
        return false;
    }
    if (!mir_imm_eq(&s->desc_imm[i->args[1]], &s->desc_imm[j->probe.args[1]]) ||
        !mir_imm_eq(&s->desc_imm[i->args[2]], &s->desc_imm[j->probe.args[2]])) {
        return false;
    }
    *contains = sb_ext_is(j->m, e, j->contains_name);
    return *contains || sb_ext_is(j->m, e, j->pname);
}

/* Walks back from `pb` through single-predecessor blocks, newest instruction first, to the earlier
 * probe or `contains` of map `a`; stops at anything that can change a map. */
static bool sb_find_hit(const SbJoin *j, uint32_t pb, MirValue a, SbPredPlan *plan) {
    uint32_t cur = pb;
    for (;;) {
        const MirBlockData *b = &j->f->blocks[cur];
        for (uint32_t ii = b->ninsts; ii-- > 0;) {
            bool contains = false;
            if (sb_matches(j, &b->insts[ii], a, &contains)) {
                plan->has_hit = true;
                plan->hit_block = cur;
                plan->hit_inst = ii;
                plan->hit_contains = contains;
                return true;
            }
            if (sb_clobbers(&b->insts[ii])) {
                return false;
            }
        }
        if (mir_preds_count(&j->preds, cur) != 1) {
            return false;
        }
        const uint32_t q = mir_pred(&j->preds, cur, 0);
        if (q == cur || q == j->ji) {
            return false;
        }
        cur = q;
    }
}

/* Finds the join's first probe, before anything that can change a map; false when there is none or
 * it does not qualify. Fills the join's description. */
static bool sb_join_probe(SbJoin *j) {
    const MirBlockData *jb = &j->f->blocks[j->ji];
    uint32_t pi = 0;
    bool found = false;
    for (uint32_t ii = 0; ii < jb->ninsts && !found; ii++) {
        if (sb_is_map_probe(j->m, &jb->insts[ii]) && jb->insts[ii].nargs == 4) {
            pi = ii;
            found = true;
        } else if (sb_clobbers(&jb->insts[ii])) {
            break;
        }
    }
    if (!found) {
        return false;
    }
    j->probe = jb->insts[pi];
    const SbFacts *s = &j->facts;
    const MirValue slot = j->probe.args[3];
    if (j->probe.res == MIR_NONE || s->key_state[slot] != 1) {
        return false;
    }
    j->key = s->key[slot];
    j->probe_ext = sb_extern_of(j->m, &j->probe);
    j->map_param = UINT32_MAX;
    for (uint32_t k = 0; k < jb->nparams; k++) {
        if (jb->params[k].value == j->probe.args[0]) {
            j->map_param = k;
            break;
        }
    }
    if (j->map_param == UINT32_MAX || !s->is_desc[j->probe.args[1]] ||
        !s->is_desc[j->probe.args[2]] || !s->is_slot[slot]) {
        return false;
    }
    /* The key must be defined outside the join, so it is available in each predecessor. */
    bool key_local = false;
    for (uint32_t k = 0; k < jb->nparams; k++) {
        key_local |= jb->params[k].value == j->key;
    }
    for (uint32_t ii = 0; ii < jb->ninsts; ii++) {
        key_local |= jb->insts[ii].res == j->key;
    }
    return !key_local && s->uses[slot] == 2;
}

/* Names of the probe and of the `contains` it pairs with: `get_ptr` becomes `contains`. */
static void sb_join_names(SbJoin *j) {
    const MsStr name = ms_name(&j->m->names, j->probe_ext->name);
    const char *from = "get_ptr";
    size_t out = 0, n = name.len < sizeof j->pname - 1 ? name.len : sizeof j->pname - 1;
    memcpy(j->pname, name.ptr, n);
    j->pname[n] = 0;
    for (size_t k = 0; k < n && out < sizeof j->contains_name - 16;) {
        if (strncmp(j->pname + k, from, strlen(from)) == 0) {
            memcpy(j->contains_name + out, "contains", 8);
            out += 8;
            k += strlen(from);
        } else {
            j->contains_name[out++] = j->pname[k++];
        }
    }
    j->contains_name[out] = 0;
}

/* Per predecessor: the map it passes and an earlier probe (or `contains`) of it. */
static bool sb_plan_join(const SbJoin *j, SbPredPlan plan[2]) {
    for (uint32_t k = 0; k < 2; k++) {
        const uint32_t pb = mir_pred(&j->preds, j->ji, k);
        const MirValue *args = NULL;
        uint32_t nargs = 0;
        if (!sb_arm_args(j->f, pb, j->ji, &args, &nargs) || j->map_param >= nargs) {
            return false;
        }
        plan[k] = (SbPredPlan){.block = pb, .map = args[j->map_param]};
        sb_find_hit(j, pb, plan[k].map, &plan[k]);
    }
    return plan[0].has_hit || plan[1].has_hit;
}

/* A `contains` becomes a probe whose null test and negation define its old result; returns the
 * address it yields. */
static MirValue sb_probe_from_contains(SbJoin *j, const SbPredPlan *p) {
    MirModule *m = j->m;
    MirFunc *f = j->f;
    const MirTy ptr = f->values[j->probe.res];
    const MirInst old = f->blocks[p->hit_block].insts[p->hit_inst];
    const MirValue new_ptr = mir_new_value(m, f, ptr);
    const MirValue null = mir_new_value(m, f, f->values[old.res]);
    MirBlockData *blk = &f->blocks[p->hit_block];
    blk->insts[p->hit_inst].imm = j->probe.imm;
    blk->insts[p->hit_inst].res = new_ptr;
    const MirInst is_null = mir_inst_make(m, MOP_PtrIsNull, &new_ptr, 1, (MirImm){0}, null, old.loc);
    mir_block_insert(m, blk, p->hit_inst + 1, &is_null);
    const MirInst negate = mir_inst_make(m, MOP_Not, &null, 1, (MirImm){0}, old.res, old.loc);
    mir_block_insert(m, blk, p->hit_inst + 2, &negate);
    return new_ptr;
}

/* A predecessor with no earlier probe probes before it branches, so no path pays more than
 * before; returns the address it yields. */
static MirValue sb_probe_in_pred(SbJoin *j, const SbPredPlan *p) {
    MirModule *m = j->m;
    MirFunc *f = j->f;
    const MirTy ptr = f->values[j->probe.res];
    const SbFacts *s = &j->facts;
    const MirLoc loc = j->probe.loc;
    const MirValue key_desc_src = j->probe.args[1], val_desc_src = j->probe.args[2];
    const MirValue slot_src = j->probe.args[3];
    const MirValue kd = mir_new_value(m, f, s->desc_ty[key_desc_src]);
    const MirValue vd = mir_new_value(m, f, s->desc_ty[val_desc_src]);
    const MirValue slot = mir_new_value(m, f, f->values[slot_src]);
    const MirValue got = mir_new_value(m, f, ptr);
    const MirValue store_args[2] = {slot, j->key};
    const MirValue call_args[4] = {p->map, kd, vd, slot};
    const MirInst insts[5] = {
        mir_inst_make(m, MOP_TypeDesc, NULL, 0, s->desc_imm[key_desc_src], kd, loc),
        mir_inst_make(m, MOP_TypeDesc, NULL, 0, s->desc_imm[val_desc_src], vd, loc),
        mir_inst_make(m, MOP_Slot, NULL, 0, s->slot_imm[slot_src], slot, loc),
        mir_inst_make(m, MOP_Store, store_args, 2, (MirImm){0}, MIR_NONE, loc),
        mir_inst_make(m, MOP_CallRt, call_args, 4, j->probe.imm, got, loc),
    };
    mir_block_append(m, &f->blocks[p->block], insts, 5);
    return got;
}

/* Adds `v` as the last argument of every edge from `pb` into the join. */
static void sb_push_edge_arg(MirModule *m, MirFunc *f, uint32_t pb, uint32_t ji, MirValue v) {
    MirTerm *t = &f->blocks[pb].term;
    for (uint32_t s = 0; s < mir_term_ntargets(t); s++) {
        MirTarget *tg = mir_term_target(t, s);
        if (tg->block != ji) {
            continue;
        }
        MirValue *args = MS_NEW_N(&m->arena, MirValue, tg->nargs + 2);
        memcpy(args, tg->args, sizeof(MirValue) * tg->nargs);
        args[tg->nargs] = v;
        tg->args = args;
        tg->nargs++;
    }
}

/* Rewrites the join: each predecessor passes the entry address as a new block parameter. */
static void sb_fuse(SbJoin *j, const SbPredPlan plan[2]) {
    MirModule *m = j->m;
    MirFunc *f = j->f;
    const MirValue res = j->probe.res, slot = j->probe.args[3];
    const MirValue param = mir_new_value(m, f, f->values[res]);
    MirValue edge_vals[2];
    for (uint32_t k = 0; k < 2; k++) {
        if (plan[k].has_hit && !plan[k].hit_contains) {
            edge_vals[k] = f->blocks[plan[k].hit_block].insts[plan[k].hit_inst].res;
        } else if (plan[k].has_hit) {
            edge_vals[k] = sb_probe_from_contains(j, &plan[k]);
        } else {
            edge_vals[k] = sb_probe_in_pred(j, &plan[k]);
        }
    }
    for (uint32_t k = 0; k < 2; k++) {
        sb_push_edge_arg(m, f, plan[k].block, j->ji, edge_vals[k]);
    }
    MirBlockData *jb = &f->blocks[j->ji];
    const MirBlockParam bp = {param, MM_BORROW};
    MIR_PUSH(m, jb->params, jb->nparams, jb->cparams, MirBlockParam, bp);
    /* The join's probe now reads the parameter; its key slot goes with it. */
    uint32_t kept = 0;
    for (uint32_t ii = 0; ii < jb->ninsts; ii++) {
        const MirInst *i = &jb->insts[ii];
        const bool gone = i->res == res || (i->op == MOP_Store && i->args[0] == slot) ||
                          i->res == slot;
        if (!gone) {
            jb->insts[kept++] = *i;
        }
    }
    jb->ninsts = kept;
    MsArena arena = {0};
    MirSubst subst = mir_subst_new(&arena, f->nvalues);
    mir_subst_set(&subst, res, param);
    mir_subst_apply(f, &subst);
    ms_arena_free(&arena);
}

/* `if not m.contains(k): m[k] = v` followed by `m[k].f += 1` probes twice on the common path: the
 * test finds the entry, the join's lookup finds it again. When a block with two predecessors starts
 * with a probe of a map that arrives as a block parameter, and one predecessor holds an earlier
 * probe or `contains` of its argument for the same key with nothing in between that can change the
 * map, that predecessor passes the entry address as a new block parameter instead. */
bool mir_simplify_fuse_contains(MirModule *m, MirFunc *f) {
    MsArena arena = {0};
    SbJoin j = {.m = m, .f = f};
    j.preds = mir_preds(&arena, f);
    j.facts = sb_facts(&arena, f);
    bool fused = false;
    for (uint32_t ji = 0; ji < f->nblocks && !fused; ji++) {
        if (mir_preds_count(&j.preds, ji) != 2 || mir_pred(&j.preds, ji, 0) == ji ||
            mir_pred(&j.preds, ji, 1) == ji) {
            continue;
        }
        j.ji = ji;
        SbPredPlan plan[2];
        if (!sb_join_probe(&j)) {
            continue;
        }
        sb_join_names(&j);
        if (sb_plan_join(&j, plan)) {
            sb_fuse(&j, plan);
            fused = true;
        }
    }
    ms_arena_free(&arena);
    return fused;
}

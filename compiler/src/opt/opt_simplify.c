/* The `simplify` pass: constant folding, algebraic identities, strength reduction, trivial
 * block-parameter elimination, branch folding, block merging, jump threading, dominator-scoped
 * value numbering and dead code elimination. This file holds the folding and the small rewrites;
 * opt_simplify_cfg.c holds control flow, value numbering and the map-probe rewrites.
 *
 * Checked operations are only weakened when the pass proves they cannot fault (constant operands
 * that do not overflow, a constant divisor other than 0 and -1). Owned droppable values are never
 * merged or deleted, so ownership stays linear. Port of crates/ms-mir/src/opt/simplify.rs; the
 * order of every rewrite and every value it creates is the Rust pass's. */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "opt/opt_simplify.h"

/* ---- shared helpers (declared in opt_simplify.h) ---- */

/* Removes the instructions flagged in `dead[block][index]` from every block. */
void mir_sweep_dead(MirFunc *f, bool *const *dead, MsArena *arena) {
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        MirBlockData *b = &f->blocks[bi];
        uint32_t *list = MS_NEW_N(arena, uint32_t, (size_t)b->ninsts + 1);
        uint32_t n = 0;
        for (uint32_t ii = 0; ii < b->ninsts; ii++) {
            if (dead[bi][ii]) {
                list[n++] = ii;
            }
        }
        if (n > 0) {
            mir_block_remove(b, list, n);
        }
    }
}

/* One cleared flag per instruction of each block, for mir_sweep_dead. */
bool **mir_dead_flags(MsArena *arena, const MirFunc *f) {
    bool **dead = MS_NEW_N(arena, bool *, (size_t)f->nblocks + 1);
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        dead[bi] = ms_alloc_zeroed(arena, f->blocks[bi].ninsts, sizeof(bool));
    }
    return dead;
}

MirSubst mir_subst_new(MsArena *arena, uint32_t nvalues) {
    MirSubst s = {ms_alloc_zeroed(arena, nvalues, sizeof(MirValue)), nvalues, 0};
    for (uint32_t v = 0; v < nvalues; v++) {
        s.to[v] = MIR_NONE;
    }
    return s;
}

void mir_subst_set(MirSubst *s, MirValue from, MirValue to) {
    if (s->to[from] == MIR_NONE) {
        s->count++;
    }
    s->to[from] = to;
}

static void sm_apply_use(void *ctx, MirValue *v) {
    *v = mir_subst_resolve(ctx, *v);
}

void mir_subst_apply(MirFunc *f, MirSubst *s) {
    if (s->count == 0) {
        return;
    }
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        MirBlockData *b = &f->blocks[bi];
        for (uint32_t ii = 0; ii < b->ninsts; ii++) {
            for (uint32_t k = 0; k < b->insts[ii].nargs; k++) {
                b->insts[ii].args[k] = mir_subst_resolve(s, b->insts[ii].args[k]);
            }
        }
        mir_term_each_use(&b->term, sm_apply_use, s);
    }
    /* A debugger name follows its value to what replaced it. */
    for (uint32_t k = 0; k < f->nnames; k++) {
        f->names[k].value = mir_subst_resolve(s, f->names[k].value);
    }
}

void mir_inst_vec_push(MsArena *arena, MirInstVec *vec, const MirInst *inst) {
    if (vec->n == vec->cap) {
        const uint32_t cap = vec->cap ? vec->cap * 2 : 8;
        MirInst *grown = ms_alloc(arena, sizeof(MirInst) * cap, _Alignof(MirInst));
        if (vec->n > 0) {
            memcpy(grown, vec->v, sizeof(MirInst) * vec->n);
        }
        vec->v = grown;
        vec->cap = cap;
    }
    vec->v[vec->n++] = *inst;
}

void mir_block_set_insts(MirModule *m, MirBlockData *b, const MirInst *src, uint32_t n) {
    if (n > b->cinsts) {
        b->insts = mir_grow(m, NULL, &b->cinsts, 0, sizeof(MirInst));
        while (b->cinsts < n) {
            b->insts = mir_grow(m, b->insts, &b->cinsts, b->cinsts, sizeof(MirInst));
        }
    }
    if (n > 0) {
        memmove(b->insts, src, sizeof(MirInst) * n);
    }
    b->ninsts = n;
}

void mir_block_append(MirModule *m, MirBlockData *b, const MirInst *src, uint32_t n) {
    for (uint32_t i = 0; i < n; i++) {
        const MirInst inst = src[i];
        MIR_PUSH(m, b->insts, b->ninsts, b->cinsts, MirInst, inst);
    }
}

bool mir_imm_eq(const MirImm *a, const MirImm *b) {
    return a->tag == b->tag && a->a == b->a && a->b == b->b && a->c == b->c && a->i == b->i;
}

bool mir_op_commutative(uint8_t op, const MirImm *imm) {
    switch ((MirOp)op) {
    case MOP_IAdd: case MOP_IMul: case MOP_IAddChk: case MOP_IMulChk: case MOP_IAddOverflow:
    case MOP_IMulOverflow: case MOP_And: case MOP_Or: case MOP_Xor:
        return true;
    case MOP_ICmp:
        return imm->tag == MI_CC && (imm->a == MCC_EQ || imm->a == MCC_NE);
    default:
        return false;
    }
}

MirTarget mir_target_clone(MirModule *m, const MirTarget *t) {
    MirTarget c = *t;
    c.args = MS_NEW_N(&m->arena, MirValue, t->nargs + 1);
    if (t->nargs > 0) {
        memcpy(c.args, t->args, sizeof(MirValue) * t->nargs);
    }
    return c;
}

bool mir_target_eq(const MirTarget *a, const MirTarget *b) {
    return a->block == b->block && a->nargs == b->nargs &&
           (a->nargs == 0 || memcmp(a->args, b->args, sizeof(MirValue) * a->nargs) == 0);
}

void mir_term_set_br(MirTerm *t, MirTarget target) {
    *t = (MirTerm){0};
    t->kind = MT_BR;
    t->value = MIR_NONE;
    t->a = target;
}

MirInst mir_inst_make(MirModule *m, MirOp op, const MirValue *args, uint32_t nargs, MirImm imm,
                      MirValue res, MirLoc loc) {
    MirInst inst = {.op = (uint8_t)op, .imm = imm, .res = res, .loc = loc, .nargs = nargs};
    inst.args = MS_NEW_N(&m->arena, MirValue, nargs + 1);
    if (nargs > 0) {
        memcpy(inst.args, args, sizeof(MirValue) * nargs);
    }
    return inst;
}


/* ---- helpers for the rewrites below ---- */

/* Removes the instructions flagged in `dead[bi][ii]` from every block. */
static void sm_term_use_state(void *ctx, MirValue v) {
    uint8_t *state = ctx;
    if (state[v] != 0) {
        state[v] = 2;
    }
}

static void sm_term_use_add2(void *ctx, MirValue v) {
    uint32_t *uses = ctx;
    uses[v] += 2;
}

/* An `opt.none_owned` whose every use is a drop owns nothing: the `none` and its drops go. */
static bool sm_dropped_nones(MirFunc *f) {
    MsArena arena = {0};
    uint8_t *state = ms_alloc_zeroed(&arena, f->nvalues, 1); /* 0 not a none, 1 only dropped, 2 used */
    bool any = false;
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        for (uint32_t ii = 0; ii < f->blocks[bi].ninsts; ii++) {
            const MirInst *i = &f->blocks[bi].insts[ii];
            if (i->op == MOP_OptNoneOwned && i->res != MIR_NONE) {
                state[i->res] = 1;
                any = true;
            }
        }
    }
    bool changed = false;
    for (uint32_t bi = 0; any && bi < f->nblocks; bi++) {
        const MirBlockData *b = &f->blocks[bi];
        for (uint32_t ii = 0; ii < b->ninsts; ii++) {
            for (uint32_t k = 0; k < b->insts[ii].nargs; k++) {
                const MirValue a = b->insts[ii].args[k];
                if (state[a] != 0 && !(b->insts[ii].op == MOP_Drop && k == 0)) {
                    state[a] = 2;
                }
            }
        }
        mir_term_each_value(&b->term, sm_term_use_state, state);
    }
    for (uint32_t bi = 0; any && bi < f->nblocks; bi++) {
        MirBlockData *b = &f->blocks[bi];
        uint32_t *list = MS_NEW_N(&arena, uint32_t, (size_t)b->ninsts + 1);
        uint32_t n = 0;
        for (uint32_t ii = 0; ii < b->ninsts; ii++) {
            const MirInst *i = &b->insts[ii];
            const bool none = i->op == MOP_OptNoneOwned && i->res != MIR_NONE && state[i->res] == 1;
            const bool drop = i->op == MOP_Drop && i->nargs > 0 && state[i->args[0]] == 1;
            if (none || drop) {
                list[n++] = ii;
            }
        }
        if (n > 0) {
            mir_block_remove(b, list, n);
            changed = true;
        }
    }
    ms_arena_free(&arena);
    return changed;
}

/* An `opt.some` whose only use is its drop never needed the box: drop the payload instead. */
static bool sm_dropped_somes(MirFunc *f) {
    MsArena arena = {0};
    uint32_t *uses = ms_alloc_zeroed(&arena, f->nvalues, sizeof(uint32_t));
    bool *dropped = ms_alloc_zeroed(&arena, f->nvalues, sizeof(bool));
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        const MirBlockData *b = &f->blocks[bi];
        for (uint32_t ii = 0; ii < b->ninsts; ii++) {
            const MirInst *i = &b->insts[ii];
            for (uint32_t k = 0; k < i->nargs; k++) {
                uses[i->args[k]]++;
            }
            if (i->op == MOP_Drop && i->nargs > 0) {
                dropped[i->args[0]] = true;
            }
        }
        mir_term_each_value(&b->term, sm_term_use_add2, uses);
    }
    /* Boxes used once, by a drop, with the payload they hold. */
    MirValue *payload = ms_alloc_zeroed(&arena, f->nvalues, sizeof(MirValue));
    bool any = false;
    for (uint32_t v = 0; v < f->nvalues; v++) {
        payload[v] = MIR_NONE;
    }
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        for (uint32_t ii = 0; ii < f->blocks[bi].ninsts; ii++) {
            const MirInst *i = &f->blocks[bi].insts[ii];
            if (i->op == MOP_OptSome && i->res != MIR_NONE && i->nargs == 1 && uses[i->res] == 1 &&
                dropped[i->res]) {
                payload[i->res] = i->args[0];
                any = true;
            }
        }
    }
    for (uint32_t bi = 0; any && bi < f->nblocks; bi++) {
        MirBlockData *b = &f->blocks[bi];
        uint32_t *list = MS_NEW_N(&arena, uint32_t, (size_t)b->ninsts + 1);
        uint32_t n = 0;
        for (uint32_t ii = 0; ii < b->ninsts; ii++) {
            MirInst *i = &b->insts[ii];
            if (i->op == MOP_Drop && i->nargs > 0 && payload[i->args[0]] != MIR_NONE) {
                i->args[0] = payload[i->args[0]];
            }
        }
        /* The box is gone: its payload is dropped where the box was. */
        for (uint32_t ii = 0; ii < b->ninsts; ii++) {
            const MirInst *i = &b->insts[ii];
            if (i->op == MOP_OptSome && i->res != MIR_NONE && payload[i->res] != MIR_NONE) {
                list[n++] = ii;
            }
        }
        mir_block_remove(b, list, n);
    }
    ms_arena_free(&arena);
    return any;
}

/* Removes every instruction `dead(ctx, inst)` accepts. */
typedef bool (*SmDeadFn)(const void *ctx, const MirInst *inst);

static void sm_remove_if(MirFunc *f, MsArena *arena, SmDeadFn dead, const void *ctx) {
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        MirBlockData *b = &f->blocks[bi];
        uint32_t *list = MS_NEW_N(arena, uint32_t, (size_t)b->ninsts + 1);
        uint32_t n = 0;
        for (uint32_t ii = 0; ii < b->ninsts; ii++) {
            if (dead(ctx, &b->insts[ii])) {
                list[n++] = ii;
            }
        }
        if (n > 0) {
            mir_block_remove(b, list, n);
        }
    }
}

/* Whether no operand of `inst` needs a drop. */
static bool sm_operands_plain(MirModule *m, const MirFunc *f, const MirInst *inst) {
    for (uint32_t k = 0; k < inst->nargs; k++) {
        if (mir_needs_drop(m, f->values[inst->args[k]])) {
            return false;
        }
    }
    return true;
}

/* Whether `inst` defines a value `subst` replaces. */
static bool sm_defines_substituted(const void *ctx, const MirInst *inst) {
    const MirSubst *s = ctx;
    return inst->res != MIR_NONE && s->to[inst->res] != MIR_NONE;
}

/* ---- known alternatives ---- */

typedef struct SmAlts {
    bool *known, *dead;
    uint32_t *kcase, *knargs;
    MirValue **kargs;
    MirSubst subst;
} SmAlts;

static bool sm_alts_collect(MirModule *m, const MirFunc *f, MsArena *arena, SmAlts *a) {
    a->known = ms_alloc_zeroed(arena, f->nvalues, sizeof(bool));
    a->kcase = ms_alloc_zeroed(arena, f->nvalues, sizeof(uint32_t));
    a->kargs = ms_alloc_zeroed(arena, f->nvalues, sizeof(MirValue *));
    a->knargs = ms_alloc_zeroed(arena, f->nvalues, sizeof(uint32_t));
    bool any = false;
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        for (uint32_t ii = 0; ii < f->blocks[bi].ninsts; ii++) {
            const MirInst *i = &f->blocks[bi].insts[ii];
            if (i->op != MOP_AltNew || i->imm.tag != MI_CASE || i->res == MIR_NONE ||
                !sm_operands_plain(m, f, i)) {
                continue;
            }
            a->known[i->res] = true;
            a->kcase[i->res] = i->imm.b;
            a->kargs[i->res] = i->args;
            a->knargs[i->res] = i->nargs;
            any = true;
        }
    }
    return any;
}

/* `alt.tag` of a known alternative is its case index; `alt.get` of the same case is the payload
 * operand. Returns whether a tag was folded. */
static bool sm_alts_fold(MirFunc *f, SmAlts *a) {
    bool changed = false;
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        for (uint32_t ii = 0; ii < f->blocks[bi].ninsts; ii++) {
            MirInst *i = &f->blocks[bi].insts[ii];
            if (i->nargs == 0 || !a->known[i->args[0]]) {
                continue;
            }
            const MirValue alt = i->args[0];
            if (i->op == MOP_AltTag) {
                i->op = MOP_IConst;
                i->imm = (MirImm){.tag = MI_INT, .i = (int64_t)a->kcase[alt]};
                i->nargs = 0;
                changed = true;
            } else if (i->op == MOP_AltGet && i->imm.tag == MI_ALTFIELD &&
                       i->imm.b == a->kcase[alt] && i->res != MIR_NONE &&
                       i->imm.c < a->knargs[alt]) {
                mir_subst_set(&a->subst, i->res, a->kargs[alt][i->imm.c]);
            }
        }
    }
    return changed;
}

static bool sm_dead_alt(const void *ctx, const MirInst *i) {
    const SmAlts *a = ctx;
    return (i->op == MOP_Drop && a->dead[i->args[0]]) || (i->res != MIR_NONE && a->dead[i->res]);
}

/* A value left with only its drop is never observed: delete both. */
static bool sm_alts_drop_dead(MirFunc *f, MsArena *arena, SmAlts *a) {
    uint32_t *uses = mir_use_counts(arena, f);
    uint32_t *drops = ms_alloc_zeroed(arena, f->nvalues, sizeof(uint32_t));
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        for (uint32_t ii = 0; ii < f->blocks[bi].ninsts; ii++) {
            const MirInst *i = &f->blocks[bi].insts[ii];
            if (i->op == MOP_Drop && a->known[i->args[0]]) {
                drops[i->args[0]]++;
            }
        }
    }
    a->dead = ms_alloc_zeroed(arena, f->nvalues, sizeof(bool));
    bool any = false;
    for (uint32_t v = 0; v < f->nvalues; v++) {
        a->dead[v] = a->known[v] && uses[v] > 0 && uses[v] == drops[v];
        any |= a->dead[v];
    }
    if (any) {
        sm_remove_if(f, arena, sm_dead_alt, a);
    }
    return any;
}

/* Folds operations on an alternative built in the same function by `alt.new` with a case whose
 * payload needs no drop: `alt.tag` becomes the case index, `alt.get` of the same case becomes the
 * payload operand, and when only drops remain the construction and the drops are deleted. */
static bool sm_known_alts(MirModule *m, MirFunc *f) {
    MsArena arena = {0};
    SmAlts a = {0};
    bool changed = false;
    if (sm_alts_collect(m, f, &arena, &a)) {
        a.subst = mir_subst_new(&arena, f->nvalues);
        changed = sm_alts_fold(f, &a);
        if (a.subst.count > 0) {
            sm_remove_if(f, &arena, sm_defines_substituted, &a.subst);
            mir_subst_apply(f, &a.subst);
            changed = true;
        }
        changed |= sm_alts_drop_dead(f, &arena, &a);
    }
    ms_arena_free(&arena);
    return changed;
}

/* ---- known interface boxes ---- */

typedef struct SmBoxes {
    MirValue *boxed;    /* box -> payload, MIR_NONE when not a candidate */
    MirValue *pointers; /* `iface.data` result -> box */
    uint32_t *handled, *uses;
} SmBoxes;

/* Every `iface.new` of a payload that needs no drop, and the `iface.data` pointers into them. */
static bool sm_boxes_collect(MirModule *m, const MirFunc *f, MsArena *arena, SmBoxes *x) {
    x->boxed = ms_alloc_zeroed(arena, f->nvalues, sizeof(MirValue));
    x->pointers = ms_alloc_zeroed(arena, f->nvalues, sizeof(MirValue));
    for (uint32_t v = 0; v < f->nvalues; v++) {
        x->boxed[v] = x->pointers[v] = MIR_NONE;
    }
    bool any = false;
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        for (uint32_t ii = 0; ii < f->blocks[bi].ninsts; ii++) {
            const MirInst *i = &f->blocks[bi].insts[ii];
            if (i->op == MOP_IfaceNew && i->nargs == 1 && i->res != MIR_NONE &&
                !mir_needs_drop(m, f->values[i->args[0]])) {
                x->boxed[i->res] = i->args[0];
                any = true;
            }
        }
    }
    for (uint32_t bi = 0; any && bi < f->nblocks; bi++) {
        for (uint32_t ii = 0; ii < f->blocks[bi].ninsts; ii++) {
            const MirInst *i = &f->blocks[bi].insts[ii];
            if (i->op == MOP_IfaceData && i->nargs == 1 && i->res != MIR_NONE &&
                x->boxed[i->args[0]] != MIR_NONE) {
                x->pointers[i->res] = i->args[0];
            }
        }
    }
    return any;
}

/* Counts the uses of each box and pointer that are drops, `iface.data` reads and loads of the
 * payload type. */
static void sm_boxes_count(const MirFunc *f, MsArena *arena, SmBoxes *x) {
    x->uses = mir_use_counts(arena, f);
    x->handled = ms_alloc_zeroed(arena, f->nvalues, sizeof(uint32_t));
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        for (uint32_t ii = 0; ii < f->blocks[bi].ninsts; ii++) {
            const MirInst *i = &f->blocks[bi].insts[ii];
            if (i->nargs != 1) {
                continue;
            }
            const MirValue a = i->args[0];
            const bool box_use = (i->op == MOP_Drop || i->op == MOP_IfaceData) &&
                                 x->boxed[a] != MIR_NONE;
            const bool payload_load = i->op == MOP_Load && x->pointers[a] != MIR_NONE &&
                                      i->res != MIR_NONE &&
                                      f->values[i->res] == f->values[x->boxed[x->pointers[a]]];
            x->handled[a] += box_use || payload_load;
        }
    }
}

/* Keeps only the boxes nothing else touches; false when none is left. */
static bool sm_boxes_prune(const MirFunc *f, MsArena *arena, SmBoxes *x) {
    bool *unplain_owner = ms_alloc_zeroed(arena, f->nvalues, sizeof(bool));
    for (uint32_t p = 0; p < f->nvalues; p++) {
        if (x->pointers[p] != MIR_NONE && x->handled[p] != x->uses[p]) {
            unplain_owner[x->pointers[p]] = true;
        }
    }
    bool any = false;
    for (uint32_t b = 0; b < f->nvalues; b++) {
        if (x->boxed[b] != MIR_NONE && (x->handled[b] != x->uses[b] || unplain_owner[b])) {
            x->boxed[b] = MIR_NONE;
        }
        any |= x->boxed[b] != MIR_NONE;
    }
    for (uint32_t p = 0; any && p < f->nvalues; p++) {
        if (x->pointers[p] != MIR_NONE && x->boxed[x->pointers[p]] == MIR_NONE) {
            x->pointers[p] = MIR_NONE;
        }
    }
    return any;
}

static bool sm_dead_box(const void *ctx, const MirInst *i) {
    const SmBoxes *x = ctx;
    const bool first = i->nargs > 0;
    const bool dropped = i->op == MOP_Drop && first && x->boxed[i->args[0]] != MIR_NONE;
    const bool defines = i->res != MIR_NONE &&
                         (x->boxed[i->res] != MIR_NONE || x->pointers[i->res] != MIR_NONE);
    const bool reads = i->op == MOP_Load && first && x->pointers[i->args[0]] != MIR_NONE;
    return dropped || defines || reads;
}

/* Removes the box of an interface value built in the same function from a payload that needs no
 * drop when nothing but `iface.data` reads, `load`s of the payload type and drops touch it: each
 * load becomes the payload operand and the allocation, the pointer and the drops are deleted. */
static bool sm_known_ifaces(MirModule *m, MirFunc *f) {
    MsArena arena = {0};
    SmBoxes x = {0};
    bool changed = false;
    if (sm_boxes_collect(m, f, &arena, &x)) {
        sm_boxes_count(f, &arena, &x);
        if (sm_boxes_prune(f, &arena, &x)) {
            /* A load of a surviving pointer yields the payload. */
            MirSubst subst = mir_subst_new(&arena, f->nvalues);
            for (uint32_t bi = 0; bi < f->nblocks; bi++) {
                for (uint32_t ii = 0; ii < f->blocks[bi].ninsts; ii++) {
                    const MirInst *i = &f->blocks[bi].insts[ii];
                    if (i->op == MOP_Load && i->nargs == 1 && i->res != MIR_NONE &&
                        x.pointers[i->args[0]] != MIR_NONE) {
                        mir_subst_set(&subst, i->res, x.boxed[x.pointers[i->args[0]]]);
                    }
                }
            }
            sm_remove_if(f, &arena, sm_dead_box, &x);
            mir_subst_apply(f, &subst);
            changed = true;
        }
    }
    ms_arena_free(&arena);
    return changed;
}

/* ---- known list literals ---- */

typedef struct SmLists {
    bool *known, *is_const;
    int64_t *consts;
    const MirValue **items;
    uint32_t *nitems;
} SmLists;

/* The element of a known list literal that `i`, a read at a constant index in range, yields;
 * MIR_NONE when it is not one. */
static MirValue sm_list_element(const SmLists *x, const MirInst *i) {
    if (i->nargs != 2 || (i->op != MOP_ListGet && i->op != MOP_ListGetU)) {
        return MIR_NONE;
    }
    const MirValue list = i->args[0], at = i->args[1];
    if (!x->known[list] || !x->is_const[at] || x->consts[at] < 0 ||
        (uint64_t)x->consts[at] >= x->nitems[list]) {
        return MIR_NONE;
    }
    return x->items[list][x->consts[at]];
}

/* The integer constants, and the `list.lit`s whose elements need no drop. */
static bool sm_lists_collect(MirModule *m, const MirFunc *f, MsArena *arena, SmLists *x) {
    const uint32_t n = f->nvalues;
    x->is_const = ms_alloc_zeroed(arena, n, sizeof(bool));
    x->consts = ms_alloc_zeroed(arena, n, sizeof(int64_t));
    x->known = ms_alloc_zeroed(arena, n, sizeof(bool));
    x->items = ms_alloc_zeroed(arena, n, sizeof(MirValue *));
    x->nitems = ms_alloc_zeroed(arena, n, sizeof(uint32_t));
    bool any = false;
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        for (uint32_t ii = 0; ii < f->blocks[bi].ninsts; ii++) {
            const MirInst *i = &f->blocks[bi].insts[ii];
            if (i->res == MIR_NONE) {
                continue;
            }
            if (i->op == MOP_IConst && i->imm.tag == MI_INT) {
                x->is_const[i->res] = true;
                x->consts[i->res] = i->imm.i;
            } else if (i->op == MOP_ListLit && sm_operands_plain(m, f, i)) {
                x->known[i->res] = true;
                x->items[i->res] = i->args;
                x->nitems[i->res] = i->nargs;
                any = true;
            }
        }
    }
    return any;
}

/* Keeps only the literals nothing but folded reads, `list.len` and drops touch. */
static bool sm_lists_prune(const MirFunc *f, MsArena *arena, SmLists *x) {
    uint32_t *uses = mir_use_counts(arena, f);
    uint32_t *folded = ms_alloc_zeroed(arena, f->nvalues, sizeof(uint32_t));
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        for (uint32_t ii = 0; ii < f->blocks[bi].ninsts; ii++) {
            const MirInst *i = &f->blocks[bi].insts[ii];
            if (i->nargs == 0 || !x->known[i->args[0]]) {
                continue;
            }
            const bool simple = (i->op == MOP_ListLen || i->op == MOP_Drop) && i->nargs == 1;
            folded[i->args[0]] += simple || sm_list_element(x, i) != MIR_NONE;
        }
    }
    bool any = false;
    for (uint32_t v = 0; v < f->nvalues; v++) {
        x->known[v] = x->known[v] && folded[v] > 0 && folded[v] == uses[v];
        any |= x->known[v];
    }
    return any;
}

typedef struct SmListRemoval {
    const SmLists *lists;
    const MirSubst *subst;
} SmListRemoval;

static bool sm_dead_list(const void *ctx, const MirInst *i) {
    const SmListRemoval *r = ctx;
    const bool drop = i->op == MOP_Drop && i->nargs > 0 && r->lists->known[i->args[0]];
    const bool def = i->res != MIR_NONE && r->lists->known[i->res];
    return sm_defines_substituted(r->subst, i) || drop || def;
}

/* Folds reads of a `list.lit` whose elements need no drop and that is only read: `list.len`
 * becomes the element count and a read at a constant index in range becomes that element. With
 * every read folded, the literal and its drops are deleted. */
static bool sm_known_lists(MirModule *m, MirFunc *f) {
    MsArena arena = {0};
    SmLists x = {0};
    bool changed = false;
    if (sm_lists_collect(m, f, &arena, &x) && sm_lists_prune(f, &arena, &x)) {
        MirSubst subst = mir_subst_new(&arena, f->nvalues);
        for (uint32_t bi = 0; bi < f->nblocks; bi++) {
            for (uint32_t ii = 0; ii < f->blocks[bi].ninsts; ii++) {
                MirInst *i = &f->blocks[bi].insts[ii];
                const MirValue element = sm_list_element(&x, i);
                if (i->res != MIR_NONE && element != MIR_NONE) {
                    mir_subst_set(&subst, i->res, element);
                } else if (i->op == MOP_ListLen && i->nargs > 0 && x.known[i->args[0]]) {
                    i->imm = (MirImm){.tag = MI_INT, .i = (int64_t)x.nitems[i->args[0]]};
                    i->op = MOP_IConst;
                    i->nargs = 0;
                }
            }
        }
        const SmListRemoval removal = {&x, &subst};
        sm_remove_if(f, &arena, sm_dead_list, &removal);
        mir_subst_apply(f, &subst);
        changed = true;
    }
    ms_arena_free(&arena);
    return changed;
}

/* ---- in-place mutators ---- */

typedef struct SmRoundtrip {
    uint32_t put_in, call, take_out, put_back;
    MirValue slot;
} SmRoundtrip;

static bool sm_has_arg(const MirInst *i, MirValue v) {
    for (uint32_t k = 0; k < i->nargs; k++) {
        if (i->args[k] == v) {
            return true;
        }
    }
    return false;
}

/* The first live instruction after `from` that satisfies `want`; false when there is none. */
static bool sm_find_after(const MirBlockData *b, const bool *removed, uint32_t from, MirOp op,
                          MirValue arg, int slot_pos, uint32_t *out) {
    for (uint32_t k = from; k < b->ninsts; k++) {
        const MirInst *i = &b->insts[k];
        if (removed[k]) {
            continue;
        }
        const bool match = op == MOP_COUNT ? sm_has_arg(i, arg)
                                           : i->op == op && i->nargs > (uint32_t)slot_pos &&
                                                 i->args[slot_pos] == arg;
        if (match) {
            *out = k;
            return true;
        }
    }
    return false;
}

/* The instruction indexes of the sequence starting with the `take` at `at`:
 * `(put into slot, call, take from slot, put back, slot)`. Instructions marked in `removed` are no
 * longer part of the block. */
static bool sm_find_roundtrip(const MirBlockData *b, const bool *removed, uint32_t at,
                              const uint32_t *uses, SmRoundtrip *out) {
    const MirInst *first = &b->insts[at];
    if (first->op != MOP_Take || first->res == MIR_NONE) {
        return false;
    }
    const MirValue a = first->res, p = first->args[0];
    if (uses[a] != 1) {
        return false;
    }
    uint32_t put_in = 0;
    if (!sm_find_after(b, removed, at + 1, MOP_Put, a, 1, &put_in)) {
        return false;
    }
    const MirValue slot = b->insts[put_in].args[0];
    bool def = false;
    for (uint32_t k = put_in; k-- > 0 && !def;) {
        const MirInst *d = &b->insts[k];
        def = !removed[k] && d->res == slot && d->op == MOP_Slot && mir_imm_eq(&d->imm, &first->imm);
    }
    if (!def || uses[slot] != 3) {
        return false;
    }
    uint32_t call = 0, take_out = 0, put_back = 0;
    if (!sm_find_after(b, removed, put_in + 1, MOP_COUNT, slot, 0, &call)) {
        return false;
    }
    uint32_t slot_uses = 0;
    for (uint32_t k = 0; k < b->insts[call].nargs; k++) {
        slot_uses += b->insts[call].args[k] == slot;
    }
    if (b->insts[call].op != MOP_CallRt || slot_uses != 1) {
        return false;
    }
    if (!sm_find_after(b, removed, call + 1, MOP_COUNT, slot, 0, &take_out)) {
        return false;
    }
    const MirInst *tk = &b->insts[take_out];
    if (tk->op != MOP_Take || tk->res == MIR_NONE) {
        return false;
    }
    const MirValue bv = tk->res;
    if (uses[bv] != 1 || !mir_imm_eq(&tk->imm, &first->imm)) {
        return false;
    }
    if (!sm_find_after(b, removed, take_out + 1, MOP_COUNT, bv, 0, &put_back)) {
        return false;
    }
    const MirInst *pb = &b->insts[put_back];
    if (pb->op != MOP_Put || pb->nargs != 2 || pb->args[0] != p || pb->args[1] != bv) {
        return false;
    }
    /* The memory at `p` is touched by nothing else in the window, and nothing else in it can read
     * or write through another pointer. */
    for (uint32_t k = at + 1; k < put_back; k++) {
        if (removed[k] || k == put_in || k == call || k == take_out) {
            continue;
        }
        const MirInst *w = &b->insts[k];
        if (sm_has_arg(w, p) || mir_op_info[w->op].effects != 0) {
            return false;
        }
    }
    *out = (SmRoundtrip){put_in, call, take_out, put_back, slot};
    return true;
}

/* Turns the move-out, call, move-back sequence lowering emits around a runtime mutator of a value
 * held in memory (`a = take P; put S, a; call f(S); b = take S; put P, b`) into a call that mutates
 * `P` directly. */
static bool sm_roundtrips(MirFunc *f) {
    MsArena arena = {0};
    uint32_t *uses = mir_use_counts(&arena, f);
    bool changed = false;
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        MirBlockData *b = &f->blocks[bi];
        bool *removed = ms_alloc_zeroed(&arena, b->ninsts, sizeof(bool));
        bool any = false;
        for (uint32_t i = 0; i < b->ninsts; i++) {
            SmRoundtrip rt;
            if (removed[i] || !sm_find_roundtrip(b, removed, i, uses, &rt)) {
                continue;
            }
            const MirValue p = b->insts[i].args[0];
            for (uint32_t k = 0; k < b->insts[rt.call].nargs; k++) {
                if (b->insts[rt.call].args[k] == rt.slot) {
                    b->insts[rt.call].args[k] = p;
                }
            }
            removed[rt.put_back] = removed[rt.take_out] = removed[rt.put_in] = removed[i] = true;
            any = true;
        }
        if (any) {
            uint32_t *list = MS_NEW_N(&arena, uint32_t, (size_t)b->ninsts + 1);
            uint32_t n = 0;
            for (uint32_t k = 0; k < b->ninsts; k++) {
                if (removed[k]) {
                    list[n++] = k;
                }
            }
            mir_block_remove(b, list, n);
            changed = true;
        }
    }
    ms_arena_free(&arena);
    return changed;
}

static uint8_t sm_role(const MirModule *m, const MirInst *inst) {
    return inst->op == MOP_CallRt && inst->imm.tag == MI_EXT ? m->externs[inst->imm.a].role
                                                              : (uint8_t)MR_NONE;
}

/* Whether no stop request can arrive inside `inst`: plain operations and leaf runtime calls. */
static bool sm_quiet(const MirModule *m, const MirInst *inst) {
    switch ((MirOp)inst->op) {
    case MOP_Poll: case MOP_CallInd: case MOP_CallMethod: case MOP_Call:
        return false;
    case MOP_CallRt:
        if (inst->imm.tag == MI_EXT) {
            const MirExtern *d = &m->externs[inst->imm.a];
            return d->leaf || d->noreturn;
        }
        return true;
    default:
        return true;
    }
}

/* A shield pair around code that cannot reach a cancellation point shields nothing: the
 * instructions between `shield_enter` and the next `shield_exit` of a block are plain operations
 * and leaf runtime calls, so no stop request can arrive inside. Both calls go. */
static bool sm_shields(MirModule *m, MirFunc *f) {
    MsArena arena = {0};
    bool changed = false;
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        MirBlockData *b = &f->blocks[bi];
        bool *removed = ms_alloc_zeroed(&arena, b->ninsts, sizeof(bool));
        bool is_open = false;
        uint32_t at = 0, count = 0;
        for (uint32_t i = 0; i < b->ninsts; i++) {
            const uint8_t role = sm_role(m, &b->insts[i]);
            if (role == MR_SHIELD_ENTER) {
                is_open = true;
                at = i;
            } else if (role == MR_SHIELD_EXIT && is_open) {
                removed[at] = removed[i] = true;
                count += 2;
                is_open = false;
                changed = true;
            } else if (is_open && !sm_quiet(m, &b->insts[i])) {
                is_open = false;
            }
        }
        if (count > 0) {
            uint32_t *list = MS_NEW_N(&arena, uint32_t, (size_t)count + 1);
            uint32_t n = 0;
            for (uint32_t k = 0; k < b->ninsts; k++) {
                if (removed[k]) {
                    list[n++] = k;
                }
            }
            mir_block_remove(b, list, n);
        }
    }
    ms_arena_free(&arena);
    return changed;
}

/* A value put into a slot and taken straight back out (inlining a callee that receives its
 * argument through a slot leaves `put S, v; r = take S`) is `v` itself: the pair is deleted and `r`
 * renamed to `v`, and only pure instructions may sit between the two. */
static bool sm_put_takes(MirFunc *f) {
    MsArena arena = {0};
    MirSubst subst = mir_subst_new(&arena, f->nvalues);
    bool **dead = mir_dead_flags(&arena, f);
    bool any = false;
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        const MirBlockData *b = &f->blocks[bi];
        for (uint32_t pi = 0; pi < b->ninsts; pi++) {
            const MirInst *put = &b->insts[pi];
            if (put->op != MOP_Put) {
                continue;
            }
            const MirValue slot = put->args[0], v = put->args[1];
            for (uint32_t ti = pi + 1; ti < b->ninsts; ti++) {
                const MirInst *take = &b->insts[ti];
                if (take->op == MOP_Take && take->args[0] == slot) {
                    if (take->res != MIR_NONE && f->values[take->res] == f->values[v]) {
                        mir_subst_set(&subst, take->res, v);
                        dead[bi][pi] = dead[bi][ti] = true;
                        any = true;
                    }
                    break;
                }
                if (sm_has_arg(take, slot) || mir_op_info[take->op].effects != 0) {
                    break;
                }
            }
        }
    }
    if (any) {
        mir_sweep_dead(f, (bool *const *)dead, &arena);
        mir_subst_apply(f, &subst);
    }
    ms_arena_free(&arena);
    return any;
}

/* ---- dead code ---- */

typedef struct SmWork {
    MirValue *v;
    uint32_t n;
} SmWork;

static bool sm_dce(MirModule *m, MirFunc *f) {
    MsArena arena = {0};
    uint32_t *uses = mir_use_counts(&arena, f);
    uint64_t *removable = ms_alloc_zeroed(&arena, f->nvalues, sizeof(uint64_t)); /* position + 1 */
    bool **dead = mir_dead_flags(&arena, f);
    uint32_t total = 0;
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        total += f->blocks[bi].ninsts;
    }
    SmWork work = {MS_NEW_N(&arena, MirValue, (size_t)f->nvalues + total + 1), 0};
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        for (uint32_t ii = 0; ii < f->blocks[bi].ninsts; ii++) {
            const MirInst *inst = &f->blocks[bi].insts[ii];
            if (inst->res == MIR_NONE) {
                continue;
            }
            const uint8_t e = mir_op_info[inst->op].effects;
            MirMode mode = MM_BORROW;
            const bool owned = mir_result_mode(m, f, inst, &mode) && mode == MM_MOVE;
            const bool removable_op = (e & (MIR_E_WRITES | MIR_E_FAULTS | MIR_E_IO | MIR_E_OWNERSHIP)) == 0;
            if (removable_op && !owned) {
                removable[inst->res] = (((uint64_t)bi << 32) | ii) + 1;
                if (uses[inst->res] == 0) {
                    work.v[work.n++] = inst->res;
                }
            }
        }
    }
    /* Deleting a user may make its operands dead. Each instruction and operand is visited once. */
    bool changed = false;
    while (work.n > 0) {
        const MirValue r = work.v[--work.n];
        if (removable[r] == 0) {
            continue;
        }
        const uint32_t bi = (uint32_t)((removable[r] - 1) >> 32), ii = (uint32_t)(removable[r] - 1);
        dead[bi][ii] = true;
        changed = true;
        const MirInst *inst = &f->blocks[bi].insts[ii];
        for (uint32_t k = 0; k < inst->nargs; k++) {
            if (--uses[inst->args[k]] == 0) {
                work.v[work.n++] = inst->args[k];
            }
        }
    }
    if (changed) {
        mir_sweep_dead(f, (bool *const *)dead, &arena);
    }
    ms_arena_free(&arena);
    return changed;
}

/* ---- the pass ---- */

/* The Rust pass works on a copy of each function and keeps it only when something reported a
 * change, so renumbering the blocks (which no pass reports) is undone when nothing changed. The
 * snapshot holds the blocks as they were; `cases` arrays are renumbered in place, so their
 * contents are saved too. */
typedef struct SmSnapshot {
    MirBlockData *blocks;
    MirCase **cases;
    uint32_t n;
} SmSnapshot;

static SmSnapshot sm_snapshot(MsArena *arena, const MirFunc *f) {
    SmSnapshot s = {MS_NEW_N(arena, MirBlockData, (size_t)f->nblocks + 1),
                    ms_alloc_zeroed(arena, f->nblocks, sizeof(MirCase *)), f->nblocks};
    memcpy(s.blocks, f->blocks, sizeof(MirBlockData) * f->nblocks);
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        const MirTerm *t = &f->blocks[bi].term;
        if (t->kind == MT_SWITCH && t->ncases > 0) {
            s.cases[bi] = MS_NEW_N(arena, MirCase, t->ncases);
            memcpy(s.cases[bi], t->cases, sizeof(MirCase) * t->ncases);
        }
    }
    return s;
}

static void sm_restore(MirFunc *f, const SmSnapshot *s) {
    f->nblocks = s->n; /* a block compaction since the snapshot may have dropped unreachable ones */
    memcpy(f->blocks, s->blocks, sizeof(MirBlockData) * s->n);
    for (uint32_t bi = 0; bi < s->n; bi++) {
        if (s->cases[bi] != NULL) {
            memcpy(f->blocks[bi].term.cases, s->cases[bi], sizeof(MirCase) * f->blocks[bi].term.ncases);
        }
    }
}

static bool sm_rounds(MirModule *m, MirFunc *f) {
    bool any = false;
    for (uint32_t round = 0; round < 24; round++) {
        bool c = false;
        c |= mir_simplify_fold(m, f);
        c |= sm_known_alts(m, f);
        c |= sm_dropped_somes(f);
        c |= sm_dropped_nones(f);
        c |= sm_known_ifaces(m, f);
        c |= sm_known_lists(m, f);
        c |= mir_simplify_phis(m, f);
        c |= sm_roundtrips(f);
        c |= sm_shields(m, f);
        c |= sm_put_takes(f);
        c |= mir_simplify_branches(m, f);
        c |= mir_simplify_cse(m, f);
        c |= mir_simplify_map_probes(m, f);
        c |= mir_simplify_fuse_contains(m, f);
        c |= sm_dce(m, f);
        if (!c) {
            break;
        }
        any = true;
    }
    return any;
}

bool mir_opt_simplify_func(MirModule *m, MirFunc *f) {
    MsArena arena = {0};
    const SmSnapshot snap = sm_snapshot(&arena, f);
    const bool any = sm_rounds(m, f);
    if (!any) {
        sm_restore(f, &snap);
    }
    ms_arena_free(&arena);
    return any;
}

bool mir_opt_simplify(MirModule *m) {
    bool changed = false;
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        changed |= mir_opt_simplify_func(m, &m->funcs[fi]);
    }
    return changed;
}

/* Only the trivial block-parameter elimination, which keeps every instruction in place. */
bool mir_opt_simplify_phis(MirModule *m) {
    bool changed = false;
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        MirFunc *f = &m->funcs[fi];
        MsArena arena = {0};
        const SmSnapshot snap = sm_snapshot(&arena, f);
        bool any = false;
        while (mir_simplify_phis(m, f)) {
            any = true;
        }
        if (!any) {
            sm_restore(f, &snap);
        }
        changed |= any;
        ms_arena_free(&arena);
    }
    return changed;
}

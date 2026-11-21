/* The `optparam` pass: splits an optional scalar that only reaches its readers through a block
 * parameter into a flag and a value.
 *
 *     b2: o = opt.none      br b4(o)          b2: br b4(false, 0)
 *     b3: o = opt.some x    br b4(o)    =>    b3: br b4(true, x)
 *     b4(p): opt.is_some p / opt.get p        b4(flag, val): flag / val
 *
 * The merge of two constructors then looks like any other scalar merge, so `if o != none` style
 * code becomes flag tests the other passes already fold and if-convert. Only parameters whose
 * every incoming value is a constructor, and whose every use is `opt.is_some` or `opt.get`, are
 * split. Port of the former Rust crates/ms-mir/src/opt/optparam.rs. */
#include <string.h>

#include "ms/mir_analysis.h"
#include "ms/mir_opt.h"
#include "ms_rt/safe.h"

/* One block parameter to split: its block, position and the scalar type inside the optional. */
typedef struct ParamSplit {
    MirBlock block;
    uint32_t param;
    MirTy inner;
} ParamSplit;

/* Where a value is defined by an instruction, for reading its constructor later. */
typedef struct DefSite {
    uint32_t *block; /* per value: block of the defining instruction, or MIR_NONE */
    uint32_t *index;
} DefSite;

static DefSite collect_defs(MsArena *arena, const MirFunc *f) {
    DefSite d = {MS_NEW_N(arena, uint32_t, (size_t)f->nvalues + 1),
                 MS_NEW_N(arena, uint32_t, (size_t)f->nvalues + 1)};
    for (uint32_t v = 0; v < f->nvalues; v++) {
        d.block[v] = MIR_NONE;
        d.index[v] = 0;
    }
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            const MirValue r = f->blocks[b].insts[i].res;
            if (r != MIR_NONE) {
                d.block[r] = b;
                d.index[r] = i;
            }
        }
    }
    return d;
}

static const MirInst *def_inst(const MirFunc *f, const DefSite *d, MirValue v) {
    return d->block[v] == MIR_NONE ? NULL : &f->blocks[d->block[v]].insts[d->index[v]];
}

/* The scalar type inside the optional `v` holds, when it is an optional of a scalar. */
static bool scalar_inner(const MirModule *m, const MirFunc *f, MirValue v, MirTy *inner) {
    const MirTyData *d = mir_ty_data(m, mir_value_ty(f, v));
    if (d->kind != MK_OPT || !mir_is_scalar(m, d->elem)) {
        return false;
    }
    *inner = d->elem;
    return true;
}

static bool is_constructor(const MirInst *inst) {
    return inst != NULL && (inst->op == MOP_OptNone || inst->op == MOP_OptNoneOwned ||
                            inst->op == MOP_OptSome);
}

typedef struct Edges {
    uint32_t *start;          /* per block: first of its incoming edges */
    const MirTarget **edge;   /* borrowed from the function's terminators */
} Edges;

static void mark_use(void *ctx, MirValue value) {
    mir_bits_set(ctx, value);
}

/* Every incoming edge of every block, grouped by destination: block b's edges are
 * `edge[start[b]..start[b + 1]]`. The counts are built one slot ahead so that filling advances
 * each block's slot into the next block's start. */
static Edges collect_edges(MsArena *arena, const MirFunc *f) {
    uint32_t total = 0;
    Edges e = {MS_NEW_N(arena, uint32_t, (size_t)f->nblocks + 2), NULL};
    memset(e.start, 0, sizeof(uint32_t) * ((size_t)f->nblocks + 2));
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t t = 0; t < mir_term_ntargets(&f->blocks[b].term); t++) {
            e.start[mir_term_target_const(&f->blocks[b].term, t)->block + 2]++;
            total++;
        }
    }
    for (uint32_t b = 0; b < f->nblocks; b++) {
        e.start[b + 2] += e.start[b + 1];
    }
    e.edge = MS_NEW_N(arena, const MirTarget *, (size_t)total + 1);
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t t = 0; t < mir_term_ntargets(&f->blocks[b].term); t++) {
            const MirTarget *target = mir_term_target_const(&f->blocks[b].term, t);
            e.edge[e.start[target->block + 1]++] = target;
        }
    }
    return e;
}

/* The constant of `ty` that stands for "no value" next to a false flag. */
static MirInst zero_const(MirModule *m, MirFunc *f, MirTy inner, MirLoc loc) {
    MirInst inst = {0};
    const uint8_t kind = mir_ty_data(m, inner)->kind;
    inst.res = mir_new_value(m, f, inner);
    inst.loc = loc;
    if (kind == MK_BOOL) {
        inst.op = MOP_BConst;
        inst.imm = (MirImm){.tag = MI_BOOL, .a = 0};
    } else if (kind == MK_FLOAT || kind == MK_FLOAT32) {
        inst.op = MOP_FConst;
        inst.imm = (MirImm){.tag = MI_FLOAT, .i = 0};
    } else {
        inst.op = MOP_IConst;
        inst.imm = (MirImm){.tag = MI_INT, .i = 0};
    }
    return inst;
}

static MirInst bool_const(MirModule *m, MirFunc *f, bool value, MirLoc loc) {
    MirInst inst = {0};
    inst.op = MOP_BConst;
    inst.imm = (MirImm){.tag = MI_BOOL, .a = value ? 1u : 0u};
    inst.res = mir_new_value(m, f, MIR_BOOL);
    inst.loc = loc;
    return inst;
}

/* The parameters of `f` that qualify. Returns how many; `*out` is in `arena`. */
static uint32_t plan_splits(MsArena *arena, const MirModule *m, const MirFunc *f,
                            ParamSplit **out) {
    const DefSite defs = collect_defs(arena, f);
    MirBits other_uses = mir_bits_new(arena, f->nvalues);
    for (uint32_t b = 0; b < f->nblocks; b++) {
        const MirBlockData *blk = &f->blocks[b];
        for (uint32_t i = 0; i < blk->ninsts; i++) {
            const MirInst *inst = &blk->insts[i];
            for (uint32_t k = 0; inst->op != MOP_OptIsSome && inst->op != MOP_OptGet && k < inst->nargs; k++) {
                mir_bits_set(&other_uses, inst->args[k]);
            }
        }
        mir_term_each_value(&blk->term, mark_use, &other_uses);
    }
    const Edges edges = collect_edges(arena, f);
    ParamSplit *splits = MS_NEW_N(arena, ParamSplit, (size_t)f->nvalues + 1);
    uint32_t count = 0;
    for (MirBlock b = 1; b < f->nblocks; b++) {
        const uint32_t first = edges.start[b], last = edges.start[b + 1];
        for (uint32_t k = 0; first < last && k < f->blocks[b].nparams; k++) {
            const MirValue p = f->blocks[b].params[k].value;
            MirTy inner = 0;
            bool all = scalar_inner(m, f, p, &inner) && !mir_bits_test(&other_uses, p);
            for (uint32_t e = first; all && e < last; e++) {
                all = is_constructor(def_inst(f, &defs, edges.edge[e]->args[k]));
            }
            if (all) {
                splits[count++] = (ParamSplit){b, k, inner};
            }
        }
    }
    *out = splits;
    return count;
}

typedef struct SubstCx {
    const MirValue *subst;
    uint32_t count;
} SubstCx;

static void apply_subst(void *ctx, MirValue *value) {
    const SubstCx *cx = ctx;
    if (*value < cx->count && cx->subst[*value] != MIR_NONE) {
        *value = cx->subst[*value];
    }
}

/* The new flag and value of a split parameter. */
typedef struct FlagValue {
    MirValue flag, value;
} FlagValue;

/* Replaces parameter `k` of `blk` by the flag and the value; returns the new values. */
static FlagValue split_param(MirModule *m, MirFunc *f, MirBlockData *blk, uint32_t k, MirTy inner) {
    FlagValue fv = {mir_new_value(m, f, MIR_BOOL), mir_new_value(m, f, inner)};
    const MirBlockParam none = {MIR_NONE, MM_BORROW};
    MIR_PUSH(m, blk->params, blk->nparams, blk->cparams, MirBlockParam, none);
    memmove(&blk->params[k + 2], &blk->params[k + 1],
            sizeof(MirBlockParam) * (blk->nparams - k - 2));
    blk->params[k] = (MirBlockParam){fv.flag, MM_BORROW};
    blk->params[k + 1] = (MirBlockParam){fv.value, MM_BORROW};
    return fv;
}

/* Replaces argument `k` of `target` by two. */
static void splice_args(MirModule *m, MirTarget *target, uint32_t k, MirValue first,
                        MirValue second) {
    MirValue *args = MS_NEW_N(&m->arena, MirValue, (size_t)target->nargs + 1);
    memcpy(args, target->args, sizeof(MirValue) * k);
    args[k] = first;
    args[k + 1] = second;
    memcpy(&args[k + 2], &target->args[k + 1], sizeof(MirValue) * (target->nargs - k - 1));
    target->args = args;
    target->nargs++;
}

/* Rewrites the edges of block `si` into split blocks: each passes a flag and a value. */
static void rewrite_edges(MirModule *m, MirFunc *f, MirBlock si, const ParamSplit *splits,
                          uint32_t nsplits, const DefSite *defs) {
    MirBlockData *blk = &f->blocks[si];
    for (uint32_t t = 0; t < mir_term_ntargets(&blk->term); t++) {
        MirTarget *target = mir_term_target(&blk->term, t);
        for (uint32_t s = nsplits; s-- > 0;) {
            if (splits[s].block != target->block) {
                continue;
            }
            const MirInst *ctor = def_inst(f, defs, target->args[splits[s].param]);
            MirInst flag = bool_const(m, f, ctor != NULL && ctor->op == MOP_OptSome, blk->term_loc);
            MirValue value = MIR_NONE;
            mir_block_insert(m, &f->blocks[si], f->blocks[si].ninsts, &flag);
            if (ctor != NULL && ctor->op == MOP_OptSome) {
                value = ctor->args[0];
            } else {
                MirInst zero = zero_const(m, f, splits[s].inner, blk->term_loc);
                value = zero.res;
                mir_block_insert(m, &f->blocks[si], f->blocks[si].ninsts, &zero);
            }
            blk = &f->blocks[si];
            target = mir_term_target(&blk->term, t);
            splice_args(m, target, splits[s].param, flag.res, value);
        }
    }
}

/* Replaces the readers of the split parameters by the flags and values. */
static void substitute_readers(MsArena *arena, MirFunc *f, const FlagValue *flags, uint32_t nvalues) {
    MirValue *subst = MS_NEW_N(arena, MirValue, (size_t)nvalues + 1);
    for (uint32_t v = 0; v < nvalues; v++) {
        subst[v] = MIR_NONE;
    }
    for (uint32_t b = 0; b < f->nblocks; b++) {
        MirBlockData *blk = &f->blocks[b];
        uint32_t kept = 0;
        for (uint32_t i = 0; i < blk->ninsts; i++) {
            const MirInst *inst = &blk->insts[i];
            const bool reads = inst->nargs > 0 && inst->args[0] < nvalues &&
                               flags[inst->args[0]].flag != MIR_NONE;
            if (reads) {
                const FlagValue fv = flags[inst->args[0]];
                subst[inst->res] = inst->op == MOP_OptIsSome ? fv.flag : fv.value;
            } else {
                blk->insts[kept++] = *inst;
            }
        }
        blk->ninsts = kept;
    }
    for (uint32_t b = 0; b < f->nblocks; b++) {
        MirBlockData *blk = &f->blocks[b];
        for (uint32_t i = 0; i < blk->ninsts; i++) {
            for (uint32_t k = 0; k < blk->insts[i].nargs; k++) {
                const MirValue a = blk->insts[i].args[k];
                blk->insts[i].args[k] = a < nvalues && subst[a] != MIR_NONE ? subst[a] : a;
            }
        }
        mir_term_each_use(&blk->term, apply_subst, &(SubstCx){subst, nvalues});
    }
}

static bool split_all(MirModule *m, MirFunc *f) {
    MsArena arena = {0};
    ParamSplit *splits = NULL;
    const uint32_t count = plan_splits(&arena, m, f, &splits);
    if (count == 0) {
        ms_arena_free(&arena);
        return false;
    }
    /* Snapshot the constructors before the function is rewritten edge by edge. */
    const uint32_t nvalues = f->nvalues;
    const DefSite defs = collect_defs(&arena, f);
    FlagValue *flags = MS_NEW_N(&arena, FlagValue, (size_t)nvalues + 1);
    for (uint32_t v = 0; v < nvalues; v++) {
        flags[v] = (FlagValue){MIR_NONE, MIR_NONE};
    }
    /* Per block, the highest parameter first, so earlier positions stay valid. */
    for (uint32_t s = count; s-- > 0;) {
        MirBlockData *blk = &f->blocks[splits[s].block];
        const MirValue p = blk->params[splits[s].param].value;
        flags[p] = split_param(m, f, blk, splits[s].param, splits[s].inner);
    }
    for (MirBlock si = 0; si < f->nblocks; si++) {
        rewrite_edges(m, f, si, splits, count, &defs);
    }
    substitute_readers(&arena, f, flags, nvalues);
    ms_arena_free(&arena);
    return true;
}

/* Runs the pass over one function; returns whether it changed. One sweep splits every eligible
 * parameter; a second confirms none is left. */
bool mir_opt_optparam_func(MirModule *m, MirFunc *f) {
    bool changed = false;
    while (split_all(m, f)) {
        changed = true;
    }
    return changed;
}

bool mir_opt_optparam(MirModule *m) {
    bool changed = false;
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        changed = mir_opt_optparam_func(m, &m->funcs[fi]) || changed;
    }
    return changed;
}

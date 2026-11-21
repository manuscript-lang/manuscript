/* The `strfuse` pass: grows a string in place for `s = s + piece`.
 *
 * `s = s.concat(piece)` lowers to a concat and a drop of the old `s`. When the drop follows with
 * no use of `s` in between, `string_append` takes `s` by move and grows it in place, so a loop
 * that builds a string stays linear even in an unoptimised build. A join whose first part is such
 * an `s` (`s += f"{k}={n};"`) becomes `string_append_fmtN`, which writes the other parts straight
 * onto `s`. Port of the former Rust crates/ms-mir/src/opt/strfuse.rs. */
#include <stdio.h>
#include <string.h>

#include "ms/mir_analysis.h"
#include "ms/mir_opt.h"
#include "ms_rt/safe.h"

/* One call to rewrite, the drop of its grown string, where that string sits among the arguments,
 * and how many parts the join has beyond it (`append_fmtN`, or `appends` for a plain concat). */
typedef struct FuseSite {
    MirBlock block;
    uint32_t call, drop, at;
    uint32_t parts;
    bool join;
} FuseSite;

/* Where the string to grow sits in `inst`, when it is a concat or join of a string. */
static bool twin_position(const MirModule *m, const MirFunc *f, const MirInst *inst, uint32_t *at,
                          bool *join) {
    if (inst->op != MOP_CallRt || inst->imm.tag != MI_EXT || inst->nargs == 0) {
        return false;
    }
    const uint8_t role = m->externs[inst->imm.a].role;
    if (role == MR_STRING_CONCAT) {
        *at = 0;
        *join = false;
        return true;
    }
    if (role == MR_STRING_JOIN) {
        *at = mir_value_ty(f, inst->args[0]) == MIR_INT ? 1 : 0;
        *join = true;
        return *at < inst->nargs;
    }
    return false;
}

static uint32_t count_uses(const MirInst *inst, MirValue v) {
    uint32_t n = 0;
    for (uint32_t k = 0; k < inst->nargs; k++) {
        n += inst->args[k] == v ? 1u : 0u;
    }
    return n;
}

static uint32_t find_fuse_sites(MsArena *arena, const MirModule *m, const MirFunc *f, FuseSite **out) {
    const MirBits owned = mir_owned_values(arena, m, f, false);
    uint32_t *next_block = MS_NEW_N(arena, uint32_t, f->nvalues + 1);
    uint32_t *next_index = MS_NEW_N(arena, uint32_t, f->nvalues + 1);
    for (uint32_t v = 0; v < f->nvalues; v++) {
        next_block[v] = MIR_NONE;
        next_index[v] = 0;
    }
    uint32_t count = 0;
    FuseSite *sites = MS_NEW_N(arena, FuseSite, mir_inst_count(f) + 1);
    for (uint32_t b = 0; b < f->nblocks; b++) {
        const MirBlockData *blk = &f->blocks[b];
        for (uint32_t i = blk->ninsts; i-- > 0;) {
            const MirInst *inst = &blk->insts[i];
            uint32_t at = 0;
            bool join = false;
            if (twin_position(m, f, inst, &at, &join)) {
                const MirValue a = inst->args[at];
                const uint32_t j = next_index[a];
                if (mir_value_ty(f, a) == MIR_STR && mir_bits_test(&owned, a) &&
                    count_uses(inst, a) == 1 && next_block[a] == b &&
                    blk->insts[j].op == MOP_Drop) {
                    sites[count++] = (FuseSite){b, i, j, at, inst->nargs - at - 1, join};
                }
            }
            for (uint32_t k = 0; k < inst->nargs; k++) {
                next_block[inst->args[k]] = b;
                next_index[inst->args[k]] = i;
            }
        }
    }
    *out = sites;
    return count;
}

/* The growing twin of a call with `nargs` arguments, `appends` when it takes just the two. */
static uint32_t fuse_extern(MirModule *m, const MirFunc *f, const MirInst *inst, const FuseSite *s,
                            bool appends) {
    char name[64];
    const int len = s->join ? snprintf(name, sizeof name, "msrt_string_append_fmt%u", s->parts)
                            : snprintf(name, sizeof name, "msrt_string_append");
    MirParam *params = MS_NEW_N(&m->arena, MirParam, inst->nargs);
    for (uint32_t k = 0; k < inst->nargs; k++) {
        params[k] = (MirParam){mir_value_ty(f, inst->args[k]), k == 0 ? MM_MOVE : MM_BORROW};
    }
    MirExtern def = {0};
    def.name = mir_name(m, name, (size_t)len);
    def.params = params;
    def.nparams = inst->nargs;
    def.ret = MIR_STR;
    def.fresh = true;
    def.leaf = true;
    def.role = appends ? MR_STRING_APPEND : MR_NONE;
    return mir_extern_intern(m, &def);
}

/* Rewrites the call of `s` to its twin; returns the zero it needs, or MIR_NONE. A join of strings
 * has no mask, so its twin takes a zero placed right before the call. */
static MirValue rewrite_call(MirModule *m, MirFunc *f, const FuseSite *s) {
    MirInst *inst = &f->blocks[s->block].insts[s->call];
    const bool appends = inst->nargs == 2;
    MirValue zero = MIR_NONE;
    MirInst twin = *inst;
    if (s->at == 0 && !appends) {
        zero = mir_new_value(m, f, MIR_INT);
        twin.nargs = inst->nargs + 1;
        twin.args = MS_NEW_N(&m->arena, MirValue, twin.nargs);
        twin.args[0] = inst->args[0];
        twin.args[1] = zero;
        memcpy(&twin.args[2], &inst->args[1], sizeof(MirValue) * (inst->nargs - 1));
    } else if (s->at == 1) {
        twin.args = MS_NEW_N(&m->arena, MirValue, inst->nargs);
        memcpy(twin.args, inst->args, sizeof(MirValue) * inst->nargs);
        twin.args[0] = inst->args[1];
        twin.args[1] = inst->args[0];
    }
    twin.imm.a = fuse_extern(m, f, &twin, s, appends);
    *inst = twin;
    return zero;
}

/* Per instruction position (blocks laid end to end), what the rebuild does there. */
typedef struct Edits {
    uint32_t *start;  /* first position of each block */
    bool *removed;    /* the drop that goes */
    MirValue *zero;   /* the zero constant defined just before, or MIR_NONE */
} Edits;

static Edits make_edits(MsArena *arena, const MirFunc *f) {
    const uint32_t total = mir_inst_count(f);
    Edits e = {MS_NEW_N(arena, uint32_t, f->nblocks + 1), MS_NEW_N(arena, bool, total + 1),
               MS_NEW_N(arena, MirValue, total + 1)};
    uint32_t at = 0;
    for (uint32_t b = 0; b < f->nblocks; b++) {
        e.start[b] = at;
        at += f->blocks[b].ninsts;
    }
    for (uint32_t i = 0; i < total; i++) {
        e.removed[i] = false;
        e.zero[i] = MIR_NONE;
    }
    return e;
}

static void rebuild_block(MirModule *m, MirBlockData *blk, const Edits *e, MirBlock b) {
    uint32_t extra = 0;
    for (uint32_t k = 0; k < blk->ninsts; k++) {
        extra += e->zero[e->start[b] + k] != MIR_NONE ? 1u : 0u;
    }
    MirInst *out = MS_NEW_N(&m->arena, MirInst, (size_t)blk->ninsts + extra + 1);
    uint32_t n = 0;
    for (uint32_t k = 0; k < blk->ninsts; k++) {
        const MirValue zero = e->zero[e->start[b] + k];
        if (zero != MIR_NONE) {
            MirInst constant = {0};
            constant.op = MOP_IConst;
            constant.imm = (MirImm){.tag = MI_INT, .i = 0};
            constant.res = zero;
            constant.loc = blk->insts[k].loc;
            out[n++] = constant;
        }
        if (!e->removed[e->start[b] + k]) {
            out[n++] = blk->insts[k];
        }
    }
    blk->insts = out;
    blk->ninsts = n;
    blk->cinsts = n;
}

bool mir_opt_strfuse(MirModule *m) {
    bool changed = false;
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        MirFunc *f = &m->funcs[fi];
        MsArena arena = {0};
        FuseSite *sites = NULL;
        const uint32_t count = find_fuse_sites(&arena, m, f, &sites);
        if (count > 0) {
            const Edits edits = make_edits(&arena, f);
            for (uint32_t s = 0; s < count; s++) {
                edits.zero[edits.start[sites[s].block] + sites[s].call] = rewrite_call(m, f, &sites[s]);
                edits.removed[edits.start[sites[s].block] + sites[s].drop] = true;
            }
            for (uint32_t b = 0; b < f->nblocks; b++) {
                rebuild_block(m, &f->blocks[b], &edits, b);
            }
            changed = true;
        }
        ms_arena_free(&arena);
    }
    return changed;
}

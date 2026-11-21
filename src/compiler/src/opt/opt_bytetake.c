/* The `bytetake` pass: a derived result of a value that dies at the call reuses its storage.
 *
 * `r = f(b, .., out); ...; drop b` copies `b` into a new allocation and then frees it. When `b` is
 * owned and nothing reads it between the call and its drop, and `f` declares a `<f>_take` twin
 * (`// ms: takes_self`), the call becomes the twin, which moves `b` in and builds the result in
 * the same allocation, so the drop disappears. A take of a dying value is a move, so nothing
 * observable changes. Port of the former Rust crates/ms-mir/src/opt/bytetake.rs. */
#include <string.h>

#include "ms/mir_analysis.h"
#include "ms/mir_opt.h"
#include "ms_rt/safe.h"

/* A call that can become its take twin, and the drop that goes with it. */
typedef struct TakeSite {
    MirBlock block;
    uint32_t call, drop, ext;
} TakeSite;

/* The twin of runtime function `ext`: the same signature with the first argument moved in, named
 * `<name>_take`. */
static uint32_t take_twin(MirModule *m, uint32_t ext) {
    MirExtern def = m->externs[ext];
    def.name = mir_name_suffixed(m, def.name, "_take", 5);
    MirParam *params = MS_NEW_N(&m->arena, MirParam, def.nparams);
    memcpy(params, def.params, sizeof(MirParam) * def.nparams);
    params[0].mode = MM_MOVE;
    def.params = params;
    def.role = MR_NONE;
    return mir_extern_intern(m, &def);
}

/* Finds the takes of one function. `next` holds, per value, the first later use seen by the
 * backward scan; terminator uses do not count, as in the Rust pass. */
static uint32_t find_take_sites(MsArena *arena, const MirModule *m, const MirFunc *f, TakeSite **out) {
    const MirBits owned = mir_owned_values(arena, m, f, true);
    uint32_t *next_block = MS_NEW_N(arena, uint32_t, f->nvalues + 1);
    uint32_t *next_index = MS_NEW_N(arena, uint32_t, f->nvalues + 1);
    for (uint32_t v = 0; v < f->nvalues; v++) {
        next_block[v] = MIR_NONE;
        next_index[v] = 0;
    }
    uint32_t count = 0;
    TakeSite *sites = MS_NEW_N(arena, TakeSite, mir_inst_count(f) + 1);
    for (uint32_t b = 0; b < f->nblocks; b++) {
        const MirBlockData *blk = &f->blocks[b];
        for (uint32_t i = blk->ninsts; i-- > 0;) {
            const MirInst *inst = &blk->insts[i];
            if (inst->op == MOP_CallRt && inst->imm.tag == MI_EXT && inst->nargs > 0 &&
                m->externs[inst->imm.a].role == MR_TAKES_DYING &&
                mir_bits_test(&owned, inst->args[0])) {
                bool again = false;
                for (uint32_t k = 1; k < inst->nargs; k++) {
                    again = again || inst->args[k] == inst->args[0];
                }
                const uint32_t j = next_index[inst->args[0]];
                if (!again && next_block[inst->args[0]] == b && blk->insts[j].op == MOP_Drop) {
                    sites[count++] = (TakeSite){b, i, j, inst->imm.a};
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

/* Removal wants ascending positions; sites arrive in scan order. */
static void sort_ascending(uint32_t *v, uint32_t n) {
    for (uint32_t i = 1; i < n; i++) {
        const uint32_t x = v[i];
        uint32_t k = i;
        for (; k > 0 && v[k - 1] > x; k--) {
            v[k] = v[k - 1];
        }
        v[k] = x;
    }
}

static void rewrite_takes(MirModule *m, MirFunc *f, MsArena *arena, const TakeSite *sites,
                          uint32_t count) {
    for (uint32_t s = 0; s < count; s++) {
        const uint32_t twin = take_twin(m, sites[s].ext);
        MirImm *imm = &f->blocks[sites[s].block].insts[sites[s].call].imm;
        imm->a = twin;
    }
    for (uint32_t b = 0; b < f->nblocks; b++) {
        uint32_t *dead = MS_NEW_N(arena, uint32_t, count + 1);
        uint32_t ndead = 0;
        for (uint32_t s = 0; s < count; s++) {
            if (sites[s].block == b) {
                dead[ndead++] = sites[s].drop;
            }
        }
        if (ndead == 0) {
            continue;
        }
        sort_ascending(dead, ndead);
        mir_block_remove(&f->blocks[b], dead, ndead);
    }
}

bool mir_opt_bytetake(MirModule *m) {
    bool changed = false;
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        MsArena arena = {0};
        TakeSite *sites = NULL;
        const uint32_t count = find_take_sites(&arena, m, &m->funcs[fi], &sites);
        if (count > 0) {
            rewrite_takes(m, &m->funcs[fi], &arena, sites, count);
            changed = true;
        }
        ms_arena_free(&arena);
    }
    return changed;
}

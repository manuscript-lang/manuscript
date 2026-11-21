/* slot_scope: which stack slots of a function live in one block only. Port of slot_scope.rs.
 *
 * A `slot` whose address is formed, offset, loaded through, stored through and passed to calls
 * inside one block, and whose first access there writes it, holds nothing before that block's first
 * access and nothing after its terminator. The backends may give such a slot's storage to another
 * block's temporary. Any other slot (its address stored, returned, passed to a block, kept by the
 * runtime, a view result pointing into it, or used in several blocks) keeps its place for the whole
 * function. */
#include <string.h>

#include "ms/mir_analysis.h"
#include "ms/mir_pass.h"

typedef enum SsAccess { SS_READ, SS_WRITE, SS_DERIVE, SS_ESCAPE } SsAccess;

/* Whether a runtime call keeps the address of an argument beyond the call. */
static bool ss_pins(const MirExtern *e) {
    return e->retains || e->role == MR_BORROWS_ARGUMENT || e->role == MR_VIEW_RESULT;
}

/* How an instruction touches the slot behind its operand `arg`. */
static SsAccess ss_access(const MirModule *m, const MirInst *in, uint32_t arg) {
    switch (in->op) {
    case MOP_Load: case MOP_Take: case MOP_PtrLoadU: case MOP_BytesPush:
        return arg == 0 ? SS_READ : SS_ESCAPE;
    case MOP_Store: case MOP_Put: case MOP_PtrStoreU:
        return arg == 0 ? SS_WRITE : SS_ESCAPE;
    case MOP_PtrField: case MOP_PtrAdd:
        return arg == 0 ? SS_DERIVE : SS_ESCAPE;
    case MOP_Call: case MOP_CallInd: case MOP_CallMethod:
        return SS_WRITE;
    case MOP_CallRt:
        return in->imm.tag == MI_EXT && !ss_pins(&m->externs[in->imm.a]) ? SS_WRITE : SS_ESCAPE;
    default:
        return SS_ESCAPE;
    }
}

typedef struct SsState {
    MirBlock block; /* MIR_NONE until the first access */
    bool confined, written;
} SsState;

typedef struct SsCx {
    const uint32_t *owner;
    SsState *seen;
} SsCx;

static void ss_term_use(void *ctx, MirValue v) {
    const SsCx *cx = ctx;
    if (cx->owner[v] != MIR_NONE && cx->seen[cx->owner[v]].block != MIR_NONE) {
        cx->seen[cx->owner[v]].confined = false;
    }
}

/* Every address derived from a slot maps to it; the slots are found first and the derivation
 * repeats until nothing is new, since blocks need not be in dominance order. */
static bool ss_owners(const MirModule *m, const MirFunc *f, uint32_t *owner) {
    bool any = false;
    for (uint32_t v = 0; v < f->nvalues; v++) {
        owner[v] = MIR_NONE;
    }
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        for (uint32_t k = 0; k < f->blocks[bi].ninsts; k++) {
            const MirInst *in = &f->blocks[bi].insts[k];
            if (in->op == MOP_Slot && in->res != MIR_NONE) {
                owner[in->res] = in->res;
                any = true;
            }
        }
    }
    for (bool grew = any; grew;) {
        grew = false;
        for (uint32_t bi = 0; bi < f->nblocks; bi++) {
            for (uint32_t k = 0; k < f->blocks[bi].ninsts; k++) {
                const MirInst *in = &f->blocks[bi].insts[k];
                if (in->res == MIR_NONE || in->nargs == 0 || owner[in->args[0]] == MIR_NONE ||
                    owner[in->res] != MIR_NONE || ss_access(m, in, 0) != SS_DERIVE) {
                    continue;
                }
                owner[in->res] = owner[in->args[0]];
                grew = true;
            }
        }
    }
    return any;
}

static void ss_inst(const MirModule *m, const SsCx *cx, const MirInst *in, MirBlock here) {
    for (uint32_t i = 0; i < in->nargs; i++) {
        const uint32_t slot = cx->owner[in->args[i]];
        if (slot == MIR_NONE) {
            continue;
        }
        SsAccess how = ss_access(m, in, i);
        /* An address in the value position of an operation is kept or handed on. */
        if (how == SS_DERIVE && i > 0) {
            how = SS_ESCAPE;
        }
        SsState *st = &cx->seen[slot];
        if (st->block == MIR_NONE) {
            *st = (SsState){.block = here, .confined = true, .written = false};
        }
        st->confined = st->confined && st->block == here;
        if (how == SS_ESCAPE) {
            st->confined = false;
        } else if (how == SS_READ) {
            st->confined = st->confined && st->written;
        } else if (how == SS_WRITE) {
            st->written = true;
        }
    }
}

/* Per value of `f` (`nvalues` entries, in `arena`): the block a confined `slot` lives in, MIR_NONE
 * for every other value. NULL when `f` has no slot. */
MirBlock *mir_confined_slots(MsArena *arena, const MirModule *m, const MirFunc *f) {
    const size_t n = f->nvalues ? f->nvalues : 1;
    uint32_t *owner = MS_NEW_N(arena, uint32_t, n);
    if (!ss_owners(m, f, owner)) {
        return NULL;
    }
    SsState *seen = MS_NEW_N(arena, SsState, n);
    for (uint32_t v = 0; v < f->nvalues; v++) {
        seen[v] = (SsState){.block = MIR_NONE};
    }
    SsCx cx = {owner, seen};
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        for (uint32_t k = 0; k < f->blocks[bi].ninsts; k++) {
            ss_inst(m, &cx, &f->blocks[bi].insts[k], bi);
        }
        mir_term_each_value(&f->blocks[bi].term, ss_term_use, &cx);
    }
    MirBlock *out = MS_NEW_N(arena, MirBlock, n);
    for (uint32_t v = 0; v < f->nvalues; v++) {
        out[v] = seen[v].block != MIR_NONE && seen[v].confined ? seen[v].block : MIR_NONE;
    }
    return out;
}

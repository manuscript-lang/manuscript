/* MIR analysis: ownership modes of operands and results, terminator targets, predecessors,
 * reverse post-order, dominators, value sets, and block editing. Port of the helpers named in
 * ms/mir_analysis.h; the output of every function equals the Rust one's (compared by
 * compiler/tests/mir-diff.sh). Owns nothing: results live in the arena the caller passes. */
#include <string.h>

#include "ms/mir_analysis.h"
#include "ms_rt/safe.h"

/* ---- ownership modes ---- */

static bool result_is_borrow(const MirModule *m, const MirFunc *f, const MirInst *inst) {
    switch ((MirOp)inst->op) {
    case MOP_TypeGet: case MOP_AltGet: case MOP_ListGet: case MOP_ListGetNn: case MOP_ListGetU:
    case MOP_OptGet: case MOP_ClosureCap: case MOP_GlobalGet: case MOP_Load: case MOP_StrLit:
    case MOP_BytesLit: case MOP_ListConstView: case MOP_StrAscii: case MOP_OptView:
    case MOP_OptViewAt: case MOP_AltPlain: case MOP_OptNone:
        return true;
    case MOP_Undef:
        return inst->imm.tag == MI_INT && inst->imm.i == 1;
    case MOP_AltView: {
        const MirTyData *d = mir_ty_data(m, mir_value_ty(f, inst->res));
        return !(d->kind == MK_ALT && m->alts[d->id].borrowed != 0);
    }
    case MOP_Call:
        return inst->imm.tag == MI_FUNC && m->funcs[inst->imm.a].ret_borrowed;
    default:
        return false;
    }
}

bool mir_result_mode(const MirModule *m, const MirFunc *f, const MirInst *inst, MirMode *mode) {
    if (inst->res == MIR_NONE || !mir_needs_drop(m, mir_value_ty(f, inst->res))) {
        return false;
    }
    *mode = result_is_borrow(m, f, inst) ? MM_BORROW : MM_MOVE;
    return true;
}

uint64_t mir_indirect_owned(const MirModule *m, const MirFunc *f, const MirInst *inst) {
    if (inst->op == MOP_CallMethod && inst->imm.tag == MI_METHOD) {
        if (inst->imm.a >= m->nifaces) {
            return 0;
        }
        const MirIfaceDef *iface = &m->ifaces[inst->imm.a];
        return inst->imm.b < iface->nmethods ? iface->methods[inst->imm.b].owned : 0;
    }
    if (inst->op == MOP_CallInd && inst->nargs > 0) {
        const MirTyData *d = mir_ty_data(m, mir_value_ty(f, inst->args[0]));
        return d->kind == MK_FN ? d->owned : 0;
    }
    return 0;
}

static void fill_modes(MirMode *out, uint32_t n, MirMode mode) {
    for (uint32_t i = 0; i < n; i++) {
        out[i] = mode;
    }
}

static void one_moved(MirMode *out, uint32_t n, uint32_t index) {
    fill_modes(out, n, MM_BORROW);
    if (index < n) {
        out[index] = MM_MOVE;
    }
}

/* Parameter modes of a callee, padded with borrows when the call passes more arguments. */
static void param_modes(const MirParam *params, uint32_t nparams, MirMode *out, uint32_t n) {
    fill_modes(out, n, MM_BORROW);
    for (uint32_t i = 0; i < n && i < nparams; i++) {
        out[i] = (MirMode)params[i].mode;
    }
}

void mir_arg_modes(const MirModule *m, const MirFunc *f, const MirInst *inst, MirMode *out) {
    const uint32_t n = inst->nargs;
    switch ((MirOp)inst->op) {
    case MOP_TypeNew: case MOP_AltNew: case MOP_ListLit: case MOP_ClosureNew:
    case MOP_TypeSet: case MOP_TypeFill: case MOP_ListPush: case MOP_ListDropLast:
    case MOP_ListSet: case MOP_ListSetNn: case MOP_ListSetU: case MOP_ListFill:
    case MOP_ListFillU: case MOP_ListPushU:
        fill_modes(out, n, MM_MOVE);
        return;
    case MOP_OptSome: case MOP_IfaceNew: case MOP_Drop: case MOP_Forget: case MOP_ListRelease:
    case MOP_GlobalSet: case MOP_AltUnbox: case MOP_AltRelease: case MOP_TypeRelease:
    case MOP_OptUnbox: case MOP_ListGrow:
        one_moved(out, n, 0);
        return;
    case MOP_Put: case MOP_DropIf:
        one_moved(out, n, 1);
        return;
    case MOP_Call:
        if (inst->imm.tag == MI_FUNC) {
            const MirFunc *callee = &m->funcs[inst->imm.a];
            param_modes(callee->params, callee->nparams, out, n);
            return;
        }
        fill_modes(out, n, MM_BORROW);
        return;
    case MOP_CallRt:
        if (inst->imm.tag == MI_EXT) {
            const MirExtern *callee = &m->externs[inst->imm.a];
            param_modes(callee->params, callee->nparams, out, n);
            return;
        }
        fill_modes(out, n, MM_BORROW);
        return;
    case MOP_CallInd: case MOP_CallMethod: {
        /* Operand 0 (the closure or interface value) is borrowed; argument `i` is operand `i + 1`. */
        const uint64_t owned = mir_indirect_owned(m, f, inst);
        fill_modes(out, n, MM_BORROW);
        for (uint32_t i = 1; i < n; i++) {
            out[i] = mir_owns(owned, i - 1) ? MM_MOVE : MM_BORROW;
        }
        return;
    }
    default:
        fill_modes(out, n, MM_BORROW);
        return;
    }
}

bool mir_result_views(const MirModule *m, const MirFunc *f, const MirInst *inst) {
    switch ((MirOp)inst->op) {
    case MOP_IfaceBorrow: case MOP_IfaceView:
        return true;
    case MOP_Call:
        if (inst->imm.tag == MI_FUNC && m->funcs[inst->imm.a].ret_view) {
            return true;
        }
        break;
    case MOP_CallRt:
        if (inst->imm.tag == MI_EXT && m->externs[inst->imm.a].role == MR_VIEW_RESULT) {
            return true;
        }
        break;
    case MOP_AltView: case MOP_CallInd: case MOP_CallMethod:
        break;
    default:
        return false;
    }
    /* A borrowing variant points into the arguments its borrowed cases came from. */
    if (inst->res == MIR_NONE) {
        return false;
    }
    const MirTyData *d = mir_ty_data(m, mir_value_ty(f, inst->res));
    return d->kind == MK_ALT && m->alts[d->id].borrowed != 0;
}

/* ---- terminators ---- */

uint32_t mir_term_ntargets(const MirTerm *t) {
    switch ((MirTermKind)t->kind) {
    case MT_BR: return 1;
    case MT_CONDBR: return 2;
    case MT_SWITCH: return t->ncases + 1;
    case MT_RET: case MT_FAULT: case MT_UNREACHABLE: return 0;
    }
    return 0;
}

const MirTarget *mir_term_target_const(const MirTerm *t, uint32_t index) {
    if (t->kind == MT_SWITCH && index < t->ncases) {
        return &t->cases[index].target;
    }
    return index == 0 ? &t->a : &t->b;
}

MirTarget *mir_term_target(MirTerm *t, uint32_t index) {
    if (t->kind == MT_SWITCH && index < t->ncases) {
        return &t->cases[index].target;
    }
    return index == 0 ? &t->a : &t->b;
}

void mir_term_each_use(MirTerm *t, MirUseFn fn, void *ctx) {
    if ((t->kind == MT_CONDBR || t->kind == MT_SWITCH || t->kind == MT_RET) && t->value != MIR_NONE) {
        fn(ctx, &t->value);
    }
    const uint32_t ntargets = mir_term_ntargets(t);
    for (uint32_t i = 0; i < ntargets; i++) {
        MirTarget *target = mir_term_target(t, i);
        for (uint32_t k = 0; k < target->nargs; k++) {
            fn(ctx, &target->args[k]);
        }
    }
}

/* ---- control flow ---- */

/* Calls `visit(ctx, from, to)` once per distinct edge, in block order. Edges out of one block
 * arrive together, so a repeat of the previous source is the only duplicate. */
typedef void (*EdgeFn)(void *ctx, MirBlock from, MirBlock to);

static void each_edge(const MirFunc *f, MirBlock *last, EdgeFn visit, void *ctx) {
    for (uint32_t i = 0; i < f->nblocks; i++) {
        last[i] = MIR_NONE;
    }
    for (uint32_t from = 0; from < f->nblocks; from++) {
        const uint32_t nt = mir_term_ntargets(&f->blocks[from].term);
        for (uint32_t k = 0; k < nt; k++) {
            const MirBlock to = mir_term_target_const(&f->blocks[from].term, k)->block;
            if (last[to] != from) {
                last[to] = from;
                visit(ctx, from, to);
            }
        }
    }
}

typedef struct PredFill {
    uint32_t *start;
    uint32_t *fill;
    MirBlock *list;
} PredFill;

static void count_edge(void *ctx, MirBlock from, MirBlock to) {
    (void)from;
    ((PredFill *)ctx)->start[to + 1]++;
}

static void store_edge(void *ctx, MirBlock from, MirBlock to) {
    PredFill *p = ctx;
    p->list[p->fill[to]++] = from;
}

MirPreds mir_preds(MsArena *arena, const MirFunc *f) {
    const size_t n = f->nblocks;
    PredFill p = {MS_NEW_N(arena, uint32_t, n + 1), MS_NEW_N(arena, uint32_t, n + 1), NULL};
    memset(p.start, 0, sizeof(uint32_t) * (n + 1));
    MirBlock *last = MS_NEW_N(arena, MirBlock, n + 1);
    each_edge(f, last, count_edge, &p);
    for (size_t i = 0; i < n; i++) {
        p.start[i + 1] += p.start[i];
    }
    memcpy(p.fill, p.start, sizeof(uint32_t) * (n + 1));
    p.list = MS_NEW_N(arena, MirBlock, (size_t)p.start[n] + 1);
    each_edge(f, last, store_edge, &p);
    return (MirPreds){p.start, p.list};
}

uint32_t mir_rpo(MsArena *arena, const MirFunc *f, MirBlock **order) {
    const uint32_t n = f->nblocks;
    bool *seen = MS_NEW_N(arena, bool, n ? n : 1);
    memset(seen, 0, n ? n : 1);
    MirBlock *post = MS_NEW_N(arena, MirBlock, n ? n : 1);
    /* One flat stack of (block, closing) entries; every edge pushes once, so the bound is
     * the number of edges plus the entry. */
    size_t edges = 1;
    for (uint32_t b = 0; b < n; b++) {
        size_t sum = 0;
        if (!ms_size_add(edges, (size_t)mir_term_ntargets(&f->blocks[b].term) + 1, &sum)) {
            sum = edges;
        }
        edges = sum;
    }
    uint32_t *stack = MS_NEW_N(arena, uint32_t, edges + 1);
    size_t top = 0, count = 0;
    stack[top++] = 0; /* entry, to open; the closing flag is the high bit */
    while (top > 0) {
        const uint32_t entry = stack[--top];
        const MirBlock b = entry & INT32_MAX;
        if ((entry >> 31) != 0) {
            post[count++] = b;
            continue;
        }
        if (seen[b]) {
            continue;
        }
        seen[b] = true;
        stack[top++] = b | (UINT32_C(1) << 31);
        const uint32_t nt = mir_term_ntargets(&f->blocks[b].term);
        for (uint32_t k = 0; k < nt; k++) {
            stack[top++] = mir_term_target_const(&f->blocks[b].term, k)->block;
        }
    }
    for (size_t i = 0; i < count / 2; i++) {
        const MirBlock tmp = post[i];
        post[i] = post[count - 1 - i];
        post[count - 1 - i] = tmp;
    }
    *order = post;
    return (uint32_t)count;
}

/* The nearest common dominator of `a` and `c` by walking up the dominator tree. */
static MirBlock intersect(const MirBlock *idom, const uint32_t *rank, MirBlock a, MirBlock c) {
    while (a != c) {
        while (rank[a] > rank[c]) {
            a = idom[a];
        }
        while (rank[c] > rank[a]) {
            c = idom[c];
        }
    }
    return a;
}

MirBlock *mir_dominators(MsArena *arena, const MirFunc *f, const MirBlock *order, uint32_t count,
                         const MirPreds *preds) {
    const uint32_t n = f->nblocks;
    uint32_t *rank = MS_NEW_N(arena, uint32_t, n ? n : 1);
    MirBlock *idom = MS_NEW_N(arena, MirBlock, n ? n : 1);
    for (uint32_t i = 0; i < n; i++) {
        rank[i] = MIR_NONE;
        idom[i] = MIR_NONE;
    }
    for (uint32_t i = 0; i < count; i++) {
        rank[order[i]] = i;
    }
    if (n == 0) {
        return idom;
    }
    idom[0] = 0;
    for (bool changed = true; changed;) {
        changed = false;
        for (uint32_t i = 1; i < count; i++) {
            const MirBlock b = order[i];
            MirBlock best = MIR_NONE;
            for (uint32_t k = 0; k < mir_preds_count(preds, b); k++) {
                const MirBlock p = mir_pred(preds, b, k);
                if (idom[p] == MIR_NONE || rank[p] == MIR_NONE) {
                    continue;
                }
                best = best == MIR_NONE ? p : intersect(idom, rank, p, best);
            }
            if (best != idom[b]) {
                idom[b] = best;
                changed = true;
            }
        }
    }
    return idom;
}

/* ---- value sets ---- */

MirBits mir_bits_new(MsArena *arena, uint32_t nbits) {
    const size_t nwords = ((size_t)nbits + 63) / 64;
    uint64_t *words = MS_NEW_N(arena, uint64_t, nwords ? nwords : 1);
    memset(words, 0, sizeof(uint64_t) * (nwords ? nwords : 1));
    return (MirBits){words, nbits};
}

/* ---- editing ---- */

void mir_block_insert(MirModule *m, MirBlockData *block, uint32_t at, const MirInst *inst) {
    MirInst placeholder = *inst;
    MIR_PUSH(m, block->insts, block->ninsts, block->cinsts, MirInst, placeholder);
    if (at + 1 < block->ninsts) {
        memmove(&block->insts[at + 1], &block->insts[at],
                sizeof(MirInst) * (size_t)(block->ninsts - 1 - at));
    }
    block->insts[at] = *inst;
}

void mir_block_remove(MirBlockData *block, const uint32_t *dead, uint32_t ndead) {
    uint32_t kept = 0, next = 0;
    for (uint32_t i = 0; i < block->ninsts; i++) {
        if (next < ndead && dead[next] == i) {
            next++;
            continue;
        }
        block->insts[kept++] = block->insts[i];
    }
    block->ninsts = kept;
}

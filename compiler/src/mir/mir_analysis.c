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
    /* A switch keeps its default in `b`, even when it has no cases. */
    if (t->kind == MT_SWITCH) {
        return &t->b;
    }
    return index == 0 ? &t->a : &t->b;
}

MirTarget *mir_term_target(MirTerm *t, uint32_t index) {
    if (t->kind == MT_SWITCH && index < t->ncases) {
        return &t->cases[index].target;
    }
    if (t->kind == MT_SWITCH) {
        return &t->b;
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

void mir_term_each_value(const MirTerm *t, MirValueFn fn, void *ctx) {
    if ((t->kind == MT_CONDBR || t->kind == MT_SWITCH || t->kind == MT_RET) && t->value != MIR_NONE) {
        fn(ctx, t->value);
    }
    const uint32_t ntargets = mir_term_ntargets(t);
    for (uint32_t i = 0; i < ntargets; i++) {
        const MirTarget *target = mir_term_target_const(t, i);
        for (uint32_t k = 0; k < target->nargs; k++) {
            fn(ctx, target->args[k]);
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

uint32_t mir_inst_count(const MirFunc *f) {
    uint32_t n = 0;
    for (uint32_t b = 0; b < f->nblocks; b++) {
        n += f->blocks[b].ninsts;
    }
    return n;
}

/* ---- value sets ---- */

MirBits mir_bits_new(MsArena *arena, uint32_t nbits) {
    const size_t nwords = ((size_t)nbits + 63) / 64;
    uint64_t *words = MS_NEW_N(arena, uint64_t, nwords ? nwords : 1);
    memset(words, 0, sizeof(uint64_t) * (nwords ? nwords : 1));
    return (MirBits){words, nbits};
}

MirBits mir_owned_values(MsArena *arena, const MirModule *m, const MirFunc *f, bool entry_params) {
    MirBits owned = mir_bits_new(arena, f->nvalues);
    for (uint32_t b = entry_params ? 0 : 1; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].nparams; i++) {
            if (f->blocks[b].params[i].mode == MM_MOVE) {
                mir_bits_set(&owned, f->blocks[b].params[i].value);
            }
        }
    }
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            MirMode mode = MM_BORROW;
            if (mir_result_mode(m, f, &f->blocks[b].insts[i], &mode) && mode == MM_MOVE) {
                mir_bits_set(&owned, f->blocks[b].insts[i].res);
            }
        }
    }
    return owned;
}

/* ---- editing ---- */

static bool same_signature(const MirExtern *a, const MirExtern *b) {
    if (a->name != b->name || a->ret != b->ret || a->nparams != b->nparams) {
        return false;
    }
    for (uint32_t i = 0; i < a->nparams; i++) {
        if (a->params[i].ty != b->params[i].ty) {
            return false;
        }
    }
    return true;
}

uint32_t mir_extern_intern(MirModule *m, const MirExtern *def) {
    for (uint32_t i = 0; i < m->nexterns; i++) {
        if (same_signature(&m->externs[i], def)) {
            return i;
        }
    }
    MirExtern copy = *def;
    copy.params = MS_NEW_N(&m->arena, MirParam, def->nparams ? def->nparams : 1);
    if (def->nparams > 0) {
        memcpy(copy.params, def->params, sizeof(MirParam) * def->nparams);
    }
    return mir_add_extern(m, &copy);
}

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

MsSym mir_name_suffixed(MirModule *m, MsSym base, const char *suffix, size_t suffix_len) {
    const MsStr name = ms_name(&m->names, base);
    char *text = ms_alloc(&m->arena, (size_t)name.len + suffix_len, 1);
    memcpy(text, name.ptr, name.len);
    memcpy(text + name.len, suffix, suffix_len);
    return mir_name(m, text, (size_t)name.len + suffix_len);
}

uint32_t mir_entry_insert_at(const MirFunc *f) {
    return f->blocks[0].ninsts > 0 && f->blocks[0].insts[0].op == MOP_DepthEnter ? 1u : 0u;
}

static void count_use(void *ctx, MirValue value) {
    ((uint32_t *)ctx)[value]++;
}

uint32_t *mir_use_counts(MsArena *arena, const MirFunc *f) {
    uint32_t *uses = MS_NEW_N(arena, uint32_t, (size_t)f->nvalues + 1);
    memset(uses, 0, sizeof(uint32_t) * ((size_t)f->nvalues + 1));
    for (uint32_t b = 0; b < f->nblocks; b++) {
        const MirBlockData *blk = &f->blocks[b];
        for (uint32_t i = 0; i < blk->ninsts; i++) {
            for (uint32_t k = 0; k < blk->insts[i].nargs; k++) {
                uses[blk->insts[i].args[k]]++;
            }
        }
        mir_term_each_value(&blk->term, count_use, uses);
    }
    return uses;
}

bool mir_is_scalar(const MirModule *m, MirTy ty) {
    switch ((MirTyKind)mir_ty_data(m, ty)->kind) {
    case MK_BOOL: case MK_INT: case MK_INT8: case MK_INT16: case MK_INT32: case MK_UINT8:
    case MK_UINT16: case MK_UINT32: case MK_UINT64: case MK_FLOAT: case MK_FLOAT32:
        return true;
    case MK_VOID: case MK_STR: case MK_BYTES: case MK_PTR: case MK_TYPE: case MK_ALT: case MK_LIST:
    case MK_OPT: case MK_OBJ: case MK_FN: case MK_IFACE:
        return false;
    }
    return false;
}

void mir_func_clone(MirModule *m, const MirFunc *f, MirFunc *out) {
    *out = *f;
    out->scopes = MS_NEW_N(&m->arena, MirScope, (size_t)f->cscopes + 1);
    out->names = MS_NEW_N(&m->arena, MirNamedValue, (size_t)f->cnames + 1);
    out->noalias = MS_NEW_N(&m->arena, uint32_t, (size_t)f->nnoalias + 1);
    if (f->nscopes > 0) {
        memcpy(out->scopes, f->scopes, sizeof(MirScope) * f->nscopes);
    }
    if (f->nnames > 0) {
        memcpy(out->names, f->names, sizeof(MirNamedValue) * f->nnames);
    }
    if (f->nnoalias > 0) {
        memcpy(out->noalias, f->noalias, sizeof(uint32_t) * f->nnoalias);
    }
    out->values = MS_NEW_N(&m->arena, MirTy, (size_t)f->cvalues + 1);
    if (f->nvalues > 0) {
        memcpy(out->values, f->values, sizeof(MirTy) * f->nvalues);
    }
    out->blocks = MS_NEW_N(&m->arena, MirBlockData, (size_t)f->cblocks + 1);
    if (f->nblocks > 0) {
        memcpy(out->blocks, f->blocks, sizeof(MirBlockData) * f->nblocks);
    }
    for (uint32_t b = 0; b < f->nblocks; b++) {
        MirBlockData *dst = &out->blocks[b];
        const MirBlockData *src = &f->blocks[b];
        dst->params = MS_NEW_N(&m->arena, MirBlockParam, (size_t)src->cparams + 1);
        if (src->nparams > 0) {
            memcpy(dst->params, src->params, sizeof(MirBlockParam) * src->nparams);
        }
        dst->insts = MS_NEW_N(&m->arena, MirInst, (size_t)src->cinsts + 1);
        if (src->ninsts > 0) {
            memcpy(dst->insts, src->insts, sizeof(MirInst) * src->ninsts);
        }
    }
}

void mir_func_compact_blocks(MirFunc *f) {
    MsArena arena = {0};
    MirBlock *order = NULL;
    const uint32_t count = mir_rpo(&arena, f, &order);
    bool in_place = count == f->nblocks;
    for (uint32_t i = 0; i < count && in_place; i++) {
        in_place = order[i] == i;
    }
    if (in_place) {
        ms_arena_free(&arena);
        return;
    }
    MirBlock *map = MS_NEW_N(&arena, MirBlock, (size_t)f->nblocks + 1);
    for (uint32_t i = 0; i < f->nblocks; i++) {
        map[i] = MIR_NONE;
    }
    for (uint32_t i = 0; i < count; i++) {
        map[order[i]] = i;
    }
    MirBlockData *moved = MS_NEW_N(&arena, MirBlockData, (size_t)count + 1);
    for (uint32_t i = 0; i < count; i++) {
        moved[i] = f->blocks[order[i]];
        for (uint32_t t = 0; t < mir_term_ntargets(&moved[i].term); t++) {
            MirTarget *target = mir_term_target(&moved[i].term, t);
            target->block = map[target->block];
        }
    }
    memcpy(f->blocks, moved, sizeof(MirBlockData) * count);
    f->nblocks = count;
    ms_arena_free(&arena);
}

void mir_narrow_range(const MirModule *m, MirTy from, MirTy to, int64_t *lo, int64_t *hi) {
    *lo = INT64_MIN;
    *hi = INT64_MAX;
    switch ((MirTyKind)mir_ty_data(m, to)->kind) {
    case MK_INT8: *lo = INT8_MIN; *hi = INT8_MAX; break;
    case MK_INT16: *lo = INT16_MIN; *hi = INT16_MAX; break;
    case MK_INT32: *lo = INT32_MIN; *hi = INT32_MAX; break;
    case MK_UINT8: *lo = 0; *hi = UINT8_MAX; break;
    case MK_UINT16: *lo = 0; *hi = UINT16_MAX; break;
    case MK_UINT32: *lo = 0; *hi = UINT32_MAX; break;
    case MK_UINT64: *lo = 0; break;
    default: break;
    }
    if (mir_ty_data(m, from)->kind == MK_UINT64 && *lo < 0) {
        *lo = 0;
    }
}

bool mir_sized_result_range(const MirModule *m, const MirFunc *f, const MirInst *inst, int64_t *lo, int64_t *hi) {
    switch ((MirOp)inst->op) {
    case MOP_IAddChk: case MOP_ISubChk: case MOP_IMulChk: case MOP_INegChk: case MOP_UAddChk:
    case MOP_USubChk: case MOP_UMulChk: case MOP_SDivChk: case MOP_SRemChk:
        break;
    default:
        return false;
    }
    if (inst->res == MIR_NONE) {
        return false;
    }
    switch ((MirTyKind)mir_ty_data(m, f->values[inst->res])->kind) {
    case MK_INT8: case MK_INT16: case MK_INT32: case MK_UINT8: case MK_UINT16: case MK_UINT32:
        mir_narrow_range(m, MIR_INT, f->values[inst->res], lo, hi);
        return true;
    default:
        return false;
    }
}

/* elaborate, emission: rebuilds each block from its entry state, threading drop flags and cleanup
 * handles through block parameters. Port of the `Em` block code in elaborate.rs. */
#include "mir/mir_elaborate.h"

/* ---- instruction and terminator helpers ---- */

MirBlock em_new_block(ElEm *em) {
    const MirBlock b = mir_new_block(em->m, em->f);
    em->f->blocks[b].term_loc = MIR_LOC_NONE;
    return b;
}

MirImm em_imm_func(uint32_t id) { return (MirImm){.tag = MI_FUNC, .a = id}; }

MirImm em_imm_case(uint32_t alt, uint32_t cs) { return (MirImm){.tag = MI_CASE, .a = alt, .b = cs}; }

MirValue em_push(ElEm *em, uint32_t at, MirOp op, const MirValue *args, uint32_t nargs, MirImm imm,
                 MirTy ty) {
    const MirValue res = ty == EM_NO_RESULT ? MIR_NONE : mir_new_value(em->m, em->f, ty);
    MirInst inst = mir_inst(op, imm, res, MIR_LOC_NONE, mir_args_copy(em->m, args, nargs), nargs);
    MirBlockData *blk = &em->f->blocks[at];
    MIR_PUSH(em->m, blk->insts, blk->ninsts, blk->cinsts, MirInst, inst);
    return res;
}

MirValue em_bconst(ElEm *em, uint32_t at, bool value) {
    return em_push(em, at, MOP_BConst, NULL, 0, (MirImm){.tag = MI_BOOL, .a = value}, MIR_BOOL);
}

MirValue em_iconst(ElEm *em, uint32_t at, int64_t value) {
    return em_push(em, at, MOP_IConst, NULL, 0, mir_imm_int(value), MIR_INT);
}

void em_br(ElEm *em, uint32_t at, MirBlock to, const MirValue *args, uint32_t nargs) {
    MirTerm *t = &em->f->blocks[at].term;
    memset(t, 0, sizeof *t);
    t->kind = MT_BR;
    t->a = (MirTarget){to, mir_args_copy(em->m, args, nargs), nargs};
}

void em_condbr(ElEm *em, uint32_t at, MirValue cond, MirBlock then, MirBlock els) {
    MirTerm *t = &em->f->blocks[at].term;
    memset(t, 0, sizeof *t);
    t->kind = MT_CONDBR;
    t->value = cond;
    t->a = (MirTarget){then, NULL, 0};
    t->b = (MirTarget){els, NULL, 0};
}

MirValue em_block_param(ElEm *em, MirBlock block, MirTy ty, MirMode mode) {
    const MirValue v = mir_new_value(em->m, em->f, ty);
    MirBlockData *blk = &em->f->blocks[block];
    const MirBlockParam p = {v, (uint8_t)mode};
    MIR_PUSH(em->m, blk->params, blk->nparams, blk->cparams, MirBlockParam, p);
    return v;
}

bool em_flag_of(const UwHash *h, MirValue key, MirValue *out) {
    uint64_t v;
    if (!uh_get(h, key, &v)) {
        return false;
    }
    *out = (MirValue)v;
    return true;
}

/* ---- cleanup entries ---- */

void em_discard(ElEm *em, uint32_t at, MirValue v) {
    MirValue h;
    if (em_flag_of(&em->handles, v, &h) && em->cx->discard != MIR_NONE) {
        em_push(em, at, MOP_CallRt, &h, 1, mir_imm_ext(em->cx->discard), MIR_VOID);
    }
}

/* The function that closes `v`: the module's `close` for kind 1 (it returns the failure code),
 * else the owner's own function, `fn(borrow T) -> unit`, named by kind - 2. */
bool em_closer(ElEm *em, MirValue v, uint32_t *close) {
    const int64_t kind = em->cx->tag_kind[v];
    if (kind != 1) {
        *close = (uint32_t)(kind - 2);
        return true;
    }
    *close = em->cx->close;
    return *close != MIR_NONE || el_fail(em->cx, "a closing owner needs a `close` function");
}

bool em_register(ElEm *em, uint32_t at, MirValue v) {
    uint32_t close;
    if (!em_closer(em, v, &close)) {
        return false;
    }
    const MirValue h = em_push(em, at, MOP_CleanupPush, &v, 1, em_imm_func(close), MIR_INT);
    uh_put(em->cx->ma, &em->handles, v, h);
    return true;
}

/* Registers a new cleanup entry for the refilled slot owner `v`; returns its handle. */
static bool em_reregister(ElEm *em, uint32_t at, MirValue v, MirValue key, MirValue *handle) {
    uint32_t close;
    if (!em_closer(em, v, &close)) {
        return false;
    }
    const MirValue h = em_push(em, at, MOP_CleanupPush, &v, 1, em_imm_func(close), MIR_INT);
    if (key != MIR_NONE) {
        uh_put(em->cx->ma, &em->flags, key, h);
    }
    *handle = h;
    return true;
}

/* Cancels the cleanup entry of a slot owner whose value moved out, and clears its flag: newer
 * entries stay, and the scope end discards this one. */
static void em_cancel(ElEm *em, uint32_t at, MirValue v) {
    MirValue h, key;
    const bool live = (em_flag_of(&em->hkeys, v, &key) && em_flag_of(&em->flags, key, &h)) ||
                      em_flag_of(&em->handles, v, &h);
    if (live && em->cx->cancel != MIR_NONE) {
        em_push(em, at, MOP_CallRt, &h, 1, mir_imm_ext(em->cx->cancel), MIR_VOID);
    }
    if (uh_has(&em->flagged, v)) {
        uh_put(em->cx->ma, &em->flags, v, em_bconst(em, at, false));
    }
}

/* The refilled owner holds a value again. */
static void em_set_held(ElEm *em, uint32_t at, MirValue v) {
    if (uh_has(&em->flagged, v)) {
        uh_put(em->cx->ma, &em->flags, v, em_bconst(em, at, true));
    }
}

/* Initializes the flag of a new flagged owner, and registers a closing owner that arrives as a
 * block parameter where it is defined. */
static void em_birth(ElEm *em, uint32_t at, MirValue v) {
    if (uh_has(&em->flagged, v)) {
        uh_put(em->cx->ma, &em->flags, v, em_bconst(em, at, true));
    }
    if (!el_tagged(em->cx, v) || em->cx->tag_kind[v] < 1 || uh_has(&em->handles, v)) {
        return;
    }
    for (uint32_t b = 0; b < em->f->nblocks; b++) {
        for (uint32_t i = 0; i < em->f->blocks[b].nparams; i++) {
            if (em->f->blocks[b].params[i].value == v) {
                em_register(em, at, v); /* an error here surfaces at the scope end */
                return;
            }
        }
    }
}

/* The operand for a consuming position: a flagged owner stays live and its operand is a
 * `move.out` of it; the flag turns false. A closing owner retires its cleanup entry. */
static MirValue em_move_arg(ElEm *em, uint32_t at, MirValue a) {
    em_discard(em, at, a);
    if (!uh_has(&em->flagged, a)) {
        return a;
    }
    const MirValue w = em_push(em, at, MOP_MoveOut, &a, 1, mir_imm_none(), em->f->values[a]);
    uh_put(em->cx->ma, &em->flags, a, em_bconst(em, at, false));
    return w;
}

/* ---- slot refill ---- */

/* Closes what the slot owner `v` holds, shielded, and releases what the close leaves; its cleanup
 * entry stays for the value stored next. */
static bool em_close_replaced(ElEm *em, uint32_t at, MirValue v) {
    uint32_t close;
    if (!em_closer(em, v, &close)) {
        return false;
    }
    const MirFunc *cf = &em->m->funcs[close];
    if (cf->has_slot_result) {
        MirValue r;
        if (!em_close_result(em, at, v, cf->slot_result, &r)) {
            return false;
        }
        em_drop_owned(em, at, r);
        return true;
    }
    if (em->cx->shield_enter == MIR_NONE) {
        return el_fail(em->cx, "a closing owner needs the shield calls");
    }
    em_push(em, at, MOP_CallRt, NULL, 0, mir_imm_ext(em->cx->shield_enter), MIR_VOID);
    em_push(em, at, MOP_Call, &v, 1, em_imm_func(close), MIR_VOID);
    em_push(em, at, MOP_CallRt, NULL, 0, mir_imm_ext(em->cx->shield_exit), MIR_VOID);
    if (cf->has_slot_close) {
        const MirValue left = em_push(em, at, MOP_Take, &v, 1,
                                      (MirImm){.tag = MI_TY, .a = cf->slot_close}, cf->slot_close);
        em_push(em, at, MOP_Drop, &left, 1, mir_imm_none(), EM_NO_RESULT);
    }
    return true;
}

/* The program is about to store a new value in the slot owner `v` (`scope.mark 2`): what it still
 * holds is closed shielded (the replaced value), and a slot whose value moved out registers a
 * fresh cleanup entry for the value stored next. Returns the block to continue in. */
static bool em_refill(ElEm *em, uint32_t *at, MirValue v, bool has_state, ElSt was) {
    MirValue flag = MIR_NONE, key = MIR_NONE, handle;
    em_flag_of(&em->flags, v, &flag);
    em_flag_of(&em->hkeys, v, &key);
    if (has_state && was == EL_MOVED) {
        if (!em_reregister(em, *at, v, key, &handle)) {
            return false;
        }
        em_set_held(em, *at, v);
        return true;
    }
    if (!has_state || (was != EL_MAYBE && was != EL_CLOSED_OR_MOVED)) {
        return em_close_replaced(em, *at, v);
    }
    if (flag == MIR_NONE) {
        return el_fail(em->cx, "a moved slot owner without a drop flag");
    }
    const MirBlock yes = em_new_block(em);
    const MirBlock no = em_new_block(em);
    const MirBlock join = em_new_block(em);
    em_condbr(em, *at, flag, yes, no);
    if (!em_close_replaced(em, yes, v)) {
        return false;
    }
    MirValue kept = MIR_NONE, fresh = MIR_NONE;
    if (key != MIR_NONE) {
        em_flag_of(&em->flags, key, &kept);
    }
    em_br(em, yes, join, &kept, kept != MIR_NONE);
    const bool again = em_reregister(em, no, v, key, &handle);
    if (!again) {
        return false;
    }
    fresh = key != MIR_NONE ? handle : MIR_NONE;
    em_br(em, no, join, &fresh, fresh != MIR_NONE);
    if (key != MIR_NONE) {
        uh_put(em->cx->ma, &em->flags, key, em_block_param(em, join, MIR_INT, MM_BORROW));
    }
    em_set_held(em, join, v);
    *at = join;
    return true;
}

/* ---- edges ---- */

/* The flag of the owner `owner` on an edge into a block with a flag parameter for it. */
static bool em_edge_flag(ElEm *em, uint32_t at, MirValue owner, const MirValue *moved, uint32_t nmoved,
                         MirValue *flag) {
    bool was_moved = false;
    for (uint32_t i = 0; i < nmoved; i++) {
        was_moved = was_moved || moved[i] == owner;
    }
    if (was_moved && uh_has(&em->flagged, owner)) {
        *flag = em_bconst(em, at, false);
        return true;
    }
    if (em_flag_of(&em->flags, owner, flag)) {
        return true;
    }
    /* The entry of an owner that no path has refilled yet is its first. */
    MirValue first = MIR_NONE;
    uint64_t *keys = uh_keys(em->cx->ma, &em->hkeys);
    for (uint32_t i = 0; i < em->hkeys.n && first == MIR_NONE; i++) {
        uint64_t key;
        if (uh_get(&em->hkeys, keys[i], &key) && key == owner) {
            first = (MirValue)keys[i];
        }
    }
    if (first != MIR_NONE && em_flag_of(&em->handles, first, flag)) {
        return true;
    }
    /* An owner this path no longer holds. */
    if (uh_has(&em->flagged, owner)) {
        *flag = em_bconst(em, at, false);
        return true;
    }
    return el_fail(em->cx, "no drop flag for %%%u", owner);
}

/* What one edge needs: the arguments for the destination (the flag arguments appended) and, when
 * the edge moves owners that need per-edge instructions, a trampoline body. */
typedef struct EmEdge {
    MirValue *args;
    uint32_t nargs;
    bool trampoline;
    MirInst *insts;
    uint32_t ninsts, cinsts;
} EmEdge;

static bool em_is_fparam(const ElFparams *fp, MirValue p) {
    for (uint32_t i = 0; i < fp->n; i++) {
        if (fp->param[i] == p) {
            return true;
        }
    }
    return false;
}

static bool em_edge(ElEm *em, uint32_t cur, const MirTarget *t, const ElFparams *fparams,
                    EmEdge *out) {
    const MirBlockData *dest = &em->f->blocks[t->block];
    const ElFparams *fp = &fparams[t->block];
    MirValue *args = MS_NEW_N(&em->m->arena, MirValue, t->nargs + fp->n + 1);
    if (t->nargs > 0) {
        memcpy(args, t->args, sizeof(MirValue) * t->nargs);
    }
    MirValue *moved = MS_NEW_N(em->cx->ma, MirValue, t->nargs + 1);
    uint32_t nmoved = 0;
    bool per_edge = false;
    uint32_t used = 0; /* the destination parameters that are not flag parameters */
    for (uint32_t p = 0; p < dest->nparams && used < t->nargs; p++) {
        if (em_is_fparam(fp, dest->params[p].value)) {
            continue;
        }
        const MirValue a = args[used++];
        if (dest->params[p].mode == MM_MOVE && mir_needs_drop(em->m, em->f->values[a])) {
            moved[nmoved++] = a;
            per_edge = per_edge || uh_has(&em->handles, a) || uh_has(&em->flagged, a);
        }
    }
    /* Build a trampoline body in a scratch block so the instructions land in order. */
    const uint32_t at = per_edge ? em_new_block(em) : cur;
    used = 0;
    for (uint32_t p = 0; p < dest->nparams && used < t->nargs; p++) {
        if (em_is_fparam(fp, dest->params[p].value)) {
            continue;
        }
        const MirValue a = args[used];
        if (dest->params[p].mode == MM_MOVE && mir_needs_drop(em->m, em->f->values[a])) {
            args[used] = em_move_arg(em, at, a);
        }
        used++;
    }
    uint32_t nargs = t->nargs;
    for (uint32_t i = 0; i < fp->n; i++) {
        if (!em_edge_flag(em, at, fp->key[i], moved, nmoved, &args[nargs])) {
            return false;
        }
        nargs++;
    }
    *out = (EmEdge){.args = args, .nargs = nargs, .trampoline = per_edge};
    if (per_edge) {
        MirBlockData *scratch = &em->f->blocks[at];
        out->insts = scratch->insts;
        out->ninsts = scratch->ninsts;
        out->cinsts = scratch->cinsts;
        em->f->nblocks--;
    }
    return true;
}

/* Each edge: the consumed owners retire their cleanup entry and the flags follow. */
static bool em_edges(ElEm *em, uint32_t cur, MirTerm *term, const ElFparams *fparams) {
    const uint32_t ntargets = mir_term_ntargets(term);
    MirBlock *tramps = MS_NEW_N(em->cx->ma, MirBlock, ntargets + 1);
    EmEdge *edges = MS_NEW_N(em->cx->ma, EmEdge, ntargets + 1);
    for (uint32_t i = 0; i < ntargets; i++) {
        MirTarget *t = mir_term_target(term, i);
        if (!em_edge(em, cur, t, fparams, &edges[i])) {
            return false;
        }
        if (edges[i].trampoline) {
            const MirBlock tramp = em_new_block(em);
            tramps[i] = tramp;
            const MirBlock dest = t->block;
            t->block = tramp;
            t->args = NULL;
            t->nargs = 0;
            em_br(em, tramp, dest, edges[i].args, edges[i].nargs);
        } else {
            t->args = edges[i].args;
            t->nargs = edges[i].nargs;
        }
    }
    for (uint32_t i = 0; i < ntargets; i++) {
        if (edges[i].trampoline) {
            MirBlockData *blk = &em->f->blocks[tramps[i]];
            blk->insts = edges[i].insts;
            blk->ninsts = edges[i].ninsts;
            blk->cinsts = edges[i].cinsts;
        }
    }
    return true;
}

/* ---- blocks ---- */

/* The start of a block: an owner that is surely open or surely closed by hand here has a constant
 * flag. */
static void em_known_flags(ElEm *em, uint32_t b, const ElState *st) {
    uint64_t *owners = uh_keys(em->cx->ma, &em->ckeys);
    const uint32_t n = em->ckeys.n;
    for (uint32_t i = 0; i < n; i++) {
        uint64_t key;
        ElSt s;
        if (!uh_get(&em->ckeys, owners[i], &key) || !el_get(st, (MirValue)owners[i], &s) ||
            uh_has(&em->flags, key) || (s != EL_LIVE && s != EL_CLOSED)) {
            continue;
        }
        uh_put(em->cx->ma, &em->flags, key, em_bconst(em, b, s == EL_CLOSED));
    }
}

/* `scope.own`: the owner joins its scope; a closing owner registers its cleanup entry. */
static bool em_own(ElEm *em, uint32_t cur, ElState *st, const MirInst *inst, MirValue v) {
    ElCx *cx = em->cx;
    ElSt was = EL_LIVE;
    const bool had = el_get(st, v, &was);
    if (!el_apply(cx, st, inst)) {
        return false;
    }
    MirValue key = MIR_NONE, handle;
    em_flag_of(&em->hkeys, v, &key);
    if (had && was == EL_MOVED && el_is_slot_owner(cx, v)) {
        if (!em_reregister(em, cur, v, key, &handle)) {
            return false;
        }
        em_set_held(em, cur, v);
        return true;
    }
    if (cx->tag_kind[v] >= 1 && !em_register(em, cur, v)) {
        return false;
    }
    if (uh_has(&em->flagged, v) && el_is_slot_owner(cx, v)) {
        uh_put(cx->ma, &em->flags, v, em_bconst(em, cur, true));
    }
    if (em_flag_of(&em->ckeys, v, &handle)) {
        uh_put(cx->ma, &em->flags, handle, em_bconst(em, cur, false));
    }
    if (key != MIR_NONE && em_flag_of(&em->handles, v, &handle)) {
        uh_put(cx->ma, &em->flags, key, handle);
    }
    return true;
}

/* The marker instructions of a Raw block; sets `*done` when `inst` was one. */
static bool em_marker(ElEm *em, uint32_t *cur, ElState *st, const MirInst *inst, bool *done) {
    *done = true;
    ElCx *cx = em->cx;
    const MirValue v = inst->nargs > 0 ? inst->args[0] : MIR_NONE;
    ElSt was = EL_LIVE;
    switch ((MirOp)inst->op) {
    case MOP_ScopeDisown: {
        const bool had = el_get(st, v, &was);
        if (!el_apply(cx, st, inst)) {
            return false;
        }
        if (el_is_slot_owner(cx, v) && had && (was == EL_LIVE || was == EL_CLOSED)) {
            em_cancel(em, *cur, v);
        }
        return true;
    }
    case MOP_ScopeMark: {
        const bool refill = inst->imm.i == 2;
        const bool had = el_get(st, v, &was);
        MirValue key;
        if (!el_apply(cx, st, inst) || (refill && !em_refill(em, cur, v, had, was))) {
            return false;
        }
        if (em_flag_of(&em->ckeys, v, &key)) {
            uh_put(cx->ma, &em->flags, key, em_bconst(em, *cur, !refill && inst->imm.i == 1));
        }
        return true;
    }
    case MOP_ScopeBegin:
        return true;
    case MOP_ScopeOwn:
        return em_own(em, *cur, st, inst, v);
    case MOP_ScopeEnd:
        return em_exit(em, cur, st, inst->imm.a);
    default:
        *done = false;
        return true;
    }
}

/* A real instruction: its consuming operands retire cleanup entries, its owned result is born. */
static bool em_plain(ElEm *em, uint32_t cur, ElState *st, MirInst *inst, MirValue returned) {
    MirMode *modes = MS_NEW_N(em->cx->ma, MirMode, inst->nargs + 1);
    mir_arg_modes(em->m, em->f, inst, modes);
    for (uint32_t k = 0; k < inst->nargs; k++) {
        if (modes[k] == MM_MOVE && mir_needs_drop(em->m, em->f->values[inst->args[k]])) {
            inst->args[k] = em_move_arg(em, cur, inst->args[k]);
        }
    }
    if (!el_apply(em->cx, st, inst)) {
        return false;
    }
    if (inst->res != MIR_NONE && inst->res == returned) {
        em->pending = returned;
    }
    MirMode result;
    const bool owned = inst->res != MIR_NONE && mir_result_mode(em->m, em->f, inst, &result) &&
                       result == MM_MOVE && mir_needs_drop(em->m, em->f->values[inst->res]);
    MirBlockData *blk = &em->f->blocks[cur];
    MIR_PUSH(em->m, blk->insts, blk->ninsts, blk->cinsts, MirInst, *inst);
    if (owned) {
        em_birth(em, cur, inst->res);
    }
    return true;
}

/* Emits one block from its entry state; the rest of the function follows from it. */
bool el_emit_block(ElEm *em, uint32_t b, const ElState *entry, const ElFparams *fparams) {
    MirFunc *f = em->f;
    const MirBlockData old = f->blocks[b];
    f->blocks[b] = (MirBlockData){.params = old.params, .nparams = old.nparams, .cparams = old.cparams,
                                  .term_loc = MIR_LOC_NONE};
    em->flags = (UwHash){0};
    for (uint32_t i = 0; i < fparams[b].n; i++) {
        uh_put(em->cx->ma, &em->flags, fparams[b].key[i], fparams[b].param[i]);
    }
    em->in_cancel = uh_has(&em->cx->cancel_blocks, b);
    /* The value the block returns is pending for a close only once it exists: one the block
     * defines is not pending for a scope that ends before that (a loop's, say). */
    const MirValue returned = old.term.kind == MT_RET ? old.term.value : MIR_NONE;
    em->pending = returned;
    for (uint32_t i = 0; i < old.ninsts && returned != MIR_NONE; i++) {
        if (old.insts[i].res == returned) {
            em->pending = MIR_NONE;
        }
    }
    ElState st = *entry;
    uint32_t cur = b, first = 0;
    /* The stack check stays the first instruction of the entry block. */
    if (old.ninsts > 0 && old.insts[0].op == MOP_DepthEnter) {
        MirBlockData *blk = &f->blocks[cur];
        MIR_PUSH(em->m, blk->insts, blk->ninsts, blk->cinsts, MirInst, old.insts[0]);
        first = 1;
    }
    em_known_flags(em, b, &st);
    MirValue *params;
    uint32_t nparams;
    el_own_params(em->cx, b, &params, &nparams);
    for (uint32_t i = 0; i < nparams; i++) {
        el_push(em->cx, &st, params[i], EL_LIVE);
        em_birth(em, cur, params[i]);
    }
    for (uint32_t i = first; i < old.ninsts; i++) {
        MirInst inst = old.insts[i];
        bool marker;
        if (!em_marker(em, &cur, &st, &inst, &marker) ||
            (!marker && !em_plain(em, cur, &st, &inst, returned))) {
            return false;
        }
    }
    if (returned != MIR_NONE) {
        if (uh_has(&em->flagged, returned)) {
            return el_fail(em->cx, "a drop-flagged owner is returned directly");
        }
        em_discard(em, cur, returned);
    }
    MirTerm term = old.term;
    if (!em_edges(em, cur, &term, fparams)) {
        return false;
    }
    f->blocks[cur].term = term;
    f->blocks[cur].term_loc = old.term_loc;
    return true;
}

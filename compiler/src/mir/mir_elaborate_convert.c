/* elaborate, cancel exits: the rewrite. Port of `convert` in cancel_exit.rs. Every parking call
 * ends its block with a test of the task's `unwinding` byte, branching to a leave block built from
 * the site (see mir_elaborate.h) and on to a tail that returns an undefined result. */
#include "mir/mir_elaborate.h"

typedef struct ElConv {
    ElCancel *all;
    MirModule *m;
    MirFunc *f;
    ElCx *cx;
    MirBlock tail;
} ElConv;

/* An instruction list under construction. */
typedef struct ElBuf { MirInst *insts; uint32_t n, cap; } ElBuf;

#define EL_NO_TY MIR_NONE

static MirImm el_imm_scope(uint32_t scope) {
    return (MirImm){.tag = MI_SCOPE, .a = scope, .b = 0};
}

static MirImm el_imm_ty(MirTy ty) { return (MirImm){.tag = MI_TY, .a = ty}; }

/* Appends an instruction with a fresh result of type `ty` (none for EL_NO_TY); returns the result. */
static MirValue ec_push(ElConv *c, ElBuf *buf, MirOp op, MirImm imm, MirTy ty, MirLoc loc,
                        const MirValue *args, uint32_t nargs) {
    const MirValue res = ty == EL_NO_TY ? MIR_NONE : mir_new_value(c->m, c->f, ty);
    const MirInst inst = mir_inst(op, imm, res, loc, mir_args_copy(c->m, args, nargs), nargs);
    MIR_PUSH(c->m, buf->insts, buf->n, buf->cap, MirInst, inst);
    return res;
}

static void ec_set(MirBlockData *blk, const ElBuf *buf) {
    blk->insts = buf->insts;
    blk->ninsts = buf->n;
    blk->cinsts = buf->cap;
}

/* The tail every leave block ends in: it resumes the task, pops the registrations the exit does
 * not run (they stay for faults), and returns an undefined result. */
static void ec_make_tail(ElConv *c, MirValue base, bool counts_depth) {
    MirFunc *f = c->f;
    const MirLoc loc = f->loc;
    c->tail = mir_new_block(c->m, f);
    ElBuf b = {0};
    (void)ec_push(c, &b, MOP_CallRt, mir_imm_ext(c->all->resume), MIR_VOID, loc, NULL, 0);
    (void)ec_push(c, &b, MOP_CallRt, mir_imm_ext(c->all->truncate), MIR_VOID, loc, &base, 1);
    if (counts_depth) {
        (void)ec_push(c, &b, MOP_DepthLeave, mir_imm_none(), EL_NO_TY, loc, NULL, 0);
    }
    MirValue ret = MIR_NONE;
    if (f->ret != MIR_VOID) {
        const MirImm imm = f->ret_borrowed ? mir_imm_int(1) : mir_imm_none();
        ret = ec_push(c, &b, MOP_Undef, imm, f->ret, loc, NULL, 0);
    }
    MirBlockData *tail = &f->blocks[c->tail];
    ec_set(tail, &b);
    tail->term = (MirTerm){.kind = MT_RET, .value = ret};
    tail->term_loc = MIR_LOC_NONE;
}

/* ---- the leave block of one site ---- */

/* The value leaves a slot a scope owns, as it does on the normal path: the scope end must not
 * close or drop what the `var` slot now holds. */
static void ec_returns(ElConv *c, ElBuf *body, const ElSite *site, MirLoc loc) {
    for (uint32_t i = 0; i < site->nreturns; i++) {
        const MirValue s = site->returns[i].a, w = site->returns[i].b;
        const MirTy ty = site->returns[i].ty;
        const bool owned = w < c->cx->nvalues0 && c->cx->tag_scope[w] >= 0;
        if (owned) {
            (void)ec_push(c, body, MOP_ScopeDisown, mir_imm_none(), EL_NO_TY, loc, &w, 1);
        }
        const MirValue held = ec_push(c, body, MOP_Take, el_imm_ty(ty), ty, loc, &w, 1);
        if (owned) {
            (void)ec_push(c, body, MOP_ScopeDisown, mir_imm_none(), EL_NO_TY, loc, &w, 1);
        }
        const MirValue put[2] = {s, held};
        (void)ec_push(c, body, MOP_Put, mir_imm_none(), EL_NO_TY, loc, put, 2);
    }
}

/* A part moved out into a slot is taken back, filled into the whole, and the whole put back. */
static void ec_refills(ElConv *c, ElBuf *body, const ElSite *site, MirLoc loc) {
    for (uint32_t i = 0; i < site->nrefills; i++) {
        const ElRefill *r = &site->refills[i];
        const MirValue part =
            ec_push(c, body, MOP_Take, el_imm_ty(r->part_ty), r->part_ty, loc, &r->part_slot, 1);
        const MirValue fargs[2] = {r->whole, part};
        MirInst fill = r->fill;
        fill.args = mir_args_copy(c->m, fargs, 2);
        fill.nargs = 2;
        fill.res = mir_new_value(c->m, c->f, r->whole_ty);
        MIR_PUSH(c->m, body->insts, body->n, body->cap, MirInst, fill);
        const MirValue put[2] = {r->slot, fill.res};
        (void)ec_push(c, body, MOP_Put, mir_imm_none(), EL_NO_TY, loc, put, 2);
    }
}

static void ec_putbacks(ElConv *c, ElBuf *body, const ElSite *site, MirLoc loc) {
    for (uint32_t i = 0; i < site->nputback; i++) {
        const MirValue put[2] = {site->putback[i].a, site->putback[i].b};
        (void)ec_push(c, body, MOP_Put, mir_imm_none(), EL_NO_TY, loc, put, 2);
    }
    for (uint32_t i = 0; i < site->nslot_drops; i++) {
        const MirTy ty = site->slot_drops[i].ty;
        const MirValue held = ec_push(c, body, MOP_Take, el_imm_ty(ty), ty, loc,
                                      &site->slot_drops[i].a, 1);
        (void)ec_push(c, body, MOP_Drop, mir_imm_none(), EL_NO_TY, loc, &held, 1);
    }
}

/* What the exit releases: the result the call produced is forgotten, the slots are put right, the
 * untagged owners are dropped, and the open scopes end. */
static void ec_leave_body(ElConv *c, ElBuf *body, const ElSite *site, const MirInst *call) {
    const MirLoc loc = call->loc;
    (void)ec_push(c, body, MOP_CallRt, mir_imm_ext(c->all->pause), MIR_VOID, loc, NULL, 0);
    MirMode mode = MM_BORROW;
    if (call->res != MIR_NONE && mir_result_mode(c->m, c->f, call, &mode) && mode == MM_MOVE &&
        mir_needs_drop(c->m, mir_value_ty(c->f, call->res))) {
        (void)ec_push(c, body, MOP_Forget, mir_imm_none(), EL_NO_TY, loc, &call->res, 1);
    }
    ec_returns(c, body, site, loc);
    ec_refills(c, body, site, loc);
    ec_putbacks(c, body, site, loc);
    for (uint32_t i = site->nexplicit; i > 0; i--) {
        (void)ec_push(c, body, MOP_Drop, mir_imm_none(), EL_NO_TY, loc, &site->explicit_drops[i - 1], 1);
    }
    for (uint32_t i = site->nscopes; i > 0; i--) {
        (void)ec_push(c, body, MOP_ScopeEnd, el_imm_scope(site->scopes[i - 1]), EL_NO_TY, loc, NULL, 0);
    }
}

/* Splits the block of one site after the call: the call is followed by the test of the `unwinding`
 * byte, branching to a leave block or on to a block holding the rest. Returns the leave block. */
static MirBlock ec_split_site(ElConv *c, const ElSite *site, uint32_t at) {
    MirFunc *f = c->f;
    const uint32_t bi = site->block;
    const MirInst call = f->blocks[bi].insts[at];
    const MirLoc sloc = call.loc;
    const uint32_t nrest = f->blocks[bi].ninsts - (at + 1);
    MirInst *rest = MS_NEW_N(&c->m->arena, MirInst, nrest ? nrest : 1);
    if (nrest > 0) {
        memcpy(rest, &f->blocks[bi].insts[at + 1], sizeof(MirInst) * nrest);
    }
    const MirTerm term = f->blocks[bi].term;
    const MirLoc term_loc = f->blocks[bi].term_loc;
    f->blocks[bi].ninsts = at + 1;
    const MirBlock next = mir_new_block(c->m, f);
    const MirBlock leave = mir_new_block(c->m, f);
    MirBlockData *nb = &f->blocks[next];
    nb->insts = rest;
    nb->ninsts = nb->cinsts = nrest;
    nb->term = term;
    nb->term_loc = term_loc;
    ElBuf head = {.insts = f->blocks[bi].insts, .n = f->blocks[bi].ninsts, .cap = f->blocks[bi].cinsts};
    const MirValue u = ec_push(c, &head, MOP_CallRt, mir_imm_ext(c->all->unwinding), MIR_UINT8, sloc, NULL, 0);
    const MirValue z = ec_push(c, &head, MOP_IConst, mir_imm_int(0), MIR_UINT8, sloc, NULL, 0);
    const MirValue pair[2] = {u, z};
    const MirValue cond = ec_push(c, &head, MOP_UICmp, mir_imm_cc(MCC_NE), MIR_BOOL, sloc, pair, 2);
    MirBlockData *hb = &f->blocks[bi];
    ec_set(hb, &head);
    hb->term = (MirTerm){.kind = MT_CONDBR, .value = cond, .a = {.block = leave}, .b = {.block = next}};
    hb->term_loc = sloc;
    return leave;
}

static void ec_site(ElConv *c, const ElSite *site) {
    MirFunc *f = c->f;
    const uint32_t at = site->inst + (site->block == 0 ? 1 : 0);
    const MirInst call = f->blocks[site->block].insts[at];
    const MirBlock leave = ec_split_site(c, site, at);
    ElBuf body = {0};
    ec_leave_body(c, &body, site, &call);
    MirBlockData *lb = &f->blocks[leave];
    ec_set(lb, &body);
    lb->term = (MirTerm){.kind = MT_BR, .value = MIR_NONE, .a = {.block = c->tail}};
    lb->term_loc = call.loc;
    (void)uh_put(c->cx->ma, &c->cx->cancel_blocks, leave, 0);
}

void el_cancel_convert(ElCancel *all, MirModule *m, MirFunc *f, ElCx *cx) {
    if (f->nblocks == 0 || f->unwind_only) {
        return;
    }
    ElSites sites = {0};
    const bool ok = el_cancel_sites(all, m, f, cx, &sites);
    /* A function that parks nowhere, or whose exits are built below, leaves its `var` slots as its
     * normal exit does. */
    all->restores[cx->fi] = ok;
    if (!ok || sites.n == 0) {
        return;
    }
    ElConv c = {.all = all, .m = m, .f = f, .cx = cx};
    const MirValue base = mir_new_value(m, f, MIR_INT);
    const MirInst base_inst = mir_inst(MOP_CallRt, mir_imm_ext(all->base), base, f->loc,
                                       mir_args_copy(m, NULL, 0), 0);
    const bool counts_depth = f->blocks[0].ninsts > 0 && f->blocks[0].insts[0].op == MOP_DepthEnter;
    mir_block_insert(m, &f->blocks[0], counts_depth ? 1 : 0, &base_inst);
    ec_make_tail(&c, base, counts_depth);
    /* The sites are walked from the last so indices hold. */
    for (uint32_t i = sites.n; i > 0; i--) {
        ec_site(&c, &sites.v[i - 1]);
    }
    f->explicit_cancel = true;
}

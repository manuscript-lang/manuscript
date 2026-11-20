/* expand: safety checks and list growth as explicit MIR, so the backends only lower. Port of
 * expand.rs.
 *
 * Run once after `unwind`, on the module a backend is about to compile. A checked list access
 * becomes the arithmetic that counts a negative index from the end, a compare of the index against
 * the length, a branch to a block that reports the fault, and the unchecked access (`list.get.u`,
 * `list.set.u`, `list.fill.u`, `list.addr.u`). `opt.unwrap` gets a branch to the none fault ahead
 * of it, and `list.push` becomes a test for a full list, growth to the next capacity (4 when
 * empty, else double) with `list.grow`, and `list.push.u`. With `checks` off the branches are left
 * out. Overflow and division checks stay with the backends.
 *
 * Fault blocks and the block that grows a list are marked cold: a backend lays them out of line
 * and treats the branch to them as unlikely. */
#include <string.h>

#include "ms/mir_pass.h"

static bool ex_expands(MirOp op) {
    return op == MOP_ListGet || op == MOP_ListGetNn || op == MOP_ListSet || op == MOP_ListSetNn ||
           op == MOP_ListFill || op == MOP_ListAddr || op == MOP_ListPush || op == MOP_OptUnwrap;
}

/* How many blocks `op` adds after the one it is in, apart from fault blocks. */
static uint32_t ex_continuations(MirOp op, bool checks) {
    if (op == MOP_ListPush) {
        return 2;
    }
    return ex_expands(op) && checks ? 1 : 0;
}

/* Rewrites one function. Blocks keep their order: a block that is split is followed by its
 * continuations, and the fault blocks come last, so numbering is known before any block is built
 * and a terminator only needs its targets renumbered. */
typedef struct Expander {
    MirModule *m;
    MirFunc *f;
    bool checks;
    uint32_t index_fault;
    MirBlockData *out;
    uint32_t nout, cout;
    MirBlockData *faults;
    uint32_t nfaults, cfaults;
    uint32_t fault_base; /* the number of the first fault block: after every block built in order */
    uint32_t next;       /* the number of the next continuation block of the current block */
} Expander;

static MirValue ex_emit(Expander *e, MirBlockData *b, MirOp op, const MirValue *args, uint32_t nargs,
                     MirImm imm, MirTy ty, MirLoc loc) {
    MirValue res = mir_new_value(e->m, e->f, ty);
    MirInst inst = mir_inst(op, imm, res, loc, mir_args_copy(e->m, args, nargs), nargs);
    MIR_PUSH(e->m, b->insts, b->ninsts, b->cinsts, MirInst, inst);
    return res;
}

static MirValue ex_emit_int(Expander *e, MirBlockData *b, int64_t n, MirLoc loc) {
    return ex_emit(e, b, MOP_IConst, NULL, 0, mir_imm_int(n), MIR_INT, loc);
}

static MirValue ex_emit_cmp(Expander *e, MirBlockData *b, MirOp op, MirCc cc, MirValue x, MirValue y,
                         MirLoc loc) {
    MirValue args[2] = {x, y};
    return ex_emit(e, b, op, args, 2, mir_imm_cc(cc), MIR_BOOL, loc);
}

static MirValue ex_emit_pure2(Expander *e, MirBlockData *b, MirOp op, MirValue x, MirValue y,
                           MirLoc loc) {
    MirValue args[2] = {x, y};
    return ex_emit(e, b, op, args, 2, mir_imm_none(), MIR_INT, loc);
}

static MirValue ex_emit_select(Expander *e, MirBlockData *b, MirValue cond, MirValue yes, MirValue no,
                            MirLoc loc) {
    MirValue args[3] = {cond, yes, no};
    return ex_emit(e, b, MOP_Select, args, 3, mir_imm_none(), MIR_INT, loc);
}

static MirTarget ex_target_to(MirBlock block) { return (MirTarget){.block = block}; }

/* Ends `cur` with a branch on `ok` to the next block of the chain, or to a new fault block that
 * holds `fault`, and leaves in `cur` the next block, ready for the rest of the instructions. */
static void ex_guard(Expander *e, MirBlockData *cur, MirValue ok, MirBlockData fault) {
    MirBlock to_fault = e->fault_base + e->nfaults;
    fault.cold = true;
    MIR_PUSH(e->m, e->faults, e->nfaults, e->cfaults, MirBlockData, fault);
    MirBlock cont = e->next++;
    cur->term = (MirTerm){.kind = MT_CONDBR, .value = ok, .a = ex_target_to(cont),
                          .b = ex_target_to(to_fault)};
    MIR_PUSH(e->m, e->out, e->nout, e->cout, MirBlockData, *cur);
    *cur = mir_block_empty();
}

static void expand_unwrap(Expander *e, MirInst inst, MirBlockData *cur) {
    if (e->checks) {
        MirValue some = ex_emit(e, cur, MOP_OptIsSome, inst.args, inst.nargs, mir_imm_none(), MIR_BOOL,
                             inst.loc);
        MirBlockData fault = mir_block_empty();
        fault.term = (MirTerm){.kind = MT_FAULT, .value = MIR_NONE, .fault = MF_NONE_UNWRAP};
        fault.term_loc = inst.loc;
        ex_guard(e, cur, some, fault);
    }
    MIR_PUSH(e->m, cur->insts, cur->ninsts, cur->cinsts, MirInst, inst);
}

/* The block that reports an index outside the list: `msrt_index_fault(index, length)`. */
static MirBlockData ex_index_fault_block(Expander *e, MirValue index, MirValue len, MirLoc loc) {
    MirBlockData fault = mir_block_empty();
    MirValue args[2] = {index, len};
    MirValue call = mir_new_value(e->m, e->f, MIR_VOID);
    MirInst inst = mir_inst(MOP_CallRt, mir_imm_ext(e->index_fault), call, loc,
                            mir_args_copy(e->m, args, 2), 2);
    MIR_PUSH(e->m, fault.insts, fault.ninsts, fault.cinsts, MirInst, inst);
    fault.term_loc = loc;
    return fault;
}

static MirOp ex_unchecked_op(MirOp op) {
    switch (op) {
    case MOP_ListGet:
    case MOP_ListGetNn:
        return MOP_ListGetU;
    case MOP_ListSet:
    case MOP_ListSetNn:
        return MOP_ListSetU;
    case MOP_ListFill:
        return MOP_ListFillU;
    default:
        return MOP_ListAddrU;
    }
}

/* A list access: `list.get`, `list.set`, `list.fill` and `list.addr` count a negative index from
 * the end; the `.nn` forms know it is not negative. */
static void expand_access(Expander *e, MirInst inst, MirBlockData *cur) {
    MirOp op = (MirOp)inst.op;
    MirLoc loc = inst.loc;
    MirValue list = inst.args[0], index = inst.args[1];
    bool wraps = op == MOP_ListGet || op == MOP_ListSet || op == MOP_ListFill || op == MOP_ListAddr;
    MirValue len = MIR_NONE;
    if (e->checks || wraps) {
        len = ex_emit(e, cur, MOP_ListLen, &list, 1, mir_imm_none(), MIR_INT, loc);
    }
    MirValue idx = index;
    if (wraps) {
        MirValue zero = ex_emit_int(e, cur, 0, loc);
        MirValue neg = ex_emit_cmp(e, cur, MOP_ICmp, MCC_LT, index, zero, loc);
        MirValue wrapped = ex_emit_pure2(e, cur, MOP_IAdd, index, len, loc);
        idx = ex_emit_select(e, cur, neg, wrapped, index, loc);
    }
    if (e->checks) {
        MirValue ok = ex_emit_cmp(e, cur, MOP_UICmp, MCC_LT, idx, len, loc);
        ex_guard(e, cur, ok, ex_index_fault_block(e, index, len, loc));
    }
    MirValue *args = MS_NEW_N(&e->m->arena, MirValue, inst.nargs);
    memcpy(args, inst.args, sizeof(MirValue) * inst.nargs);
    args[1] = idx;
    MirInst unchecked = mir_inst(ex_unchecked_op(op), inst.imm, inst.res, loc, args, inst.nargs);
    MIR_PUSH(e->m, cur->insts, cur->ninsts, cur->cinsts, MirInst, unchecked);
}

/* `list.push l, v`: when the list is full, grow it to 4 elements if it is empty and to twice its
 * capacity otherwise, then store the element after the last. */
static void expand_push(Expander *e, MirInst inst, MirBlockData *cur) {
    MirLoc loc = inst.loc;
    MirValue list = inst.args[0];
    MirTy ty = mir_value_ty(e->f, list);
    MirValue len = ex_emit(e, cur, MOP_ListLen, &list, 1, mir_imm_none(), MIR_INT, loc);
    MirValue cap = ex_emit(e, cur, MOP_ListCap, &list, 1, mir_imm_none(), MIR_INT, loc);
    MirValue full = ex_emit_cmp(e, cur, MOP_ICmp, MCC_EQ, len, cap, loc);
    MirBlock grow = e->next, ready = e->next + 1;
    e->next += 2;
    MirValue *to_ready = MS_NEW(&e->m->arena, MirValue);
    *to_ready = list;
    cur->term = (MirTerm){.kind = MT_CONDBR, .value = full, .a = ex_target_to(grow),
                          .b = {.block = ready, .args = to_ready, .nargs = 1}};
    MIR_PUSH(e->m, e->out, e->nout, e->cout, MirBlockData, *cur);

    MirBlockData g = mir_block_empty();
    g.cold = true;
    g.term_loc = loc;
    MirValue zero = ex_emit_int(e, &g, 0, loc);
    MirValue empty = ex_emit_cmp(e, &g, MOP_ICmp, MCC_EQ, cap, zero, loc);
    MirValue one = ex_emit_int(e, &g, 1, loc);
    MirValue doubled = ex_emit_pure2(e, &g, MOP_Shl, cap, one, loc);
    MirValue four = ex_emit_int(e, &g, 4, loc);
    MirValue ncap = ex_emit_select(e, &g, empty, four, doubled, loc);
    MirValue grow_args[2] = {list, ncap};
    MirValue grown = ex_emit(e, &g, MOP_ListGrow, grow_args, 2, mir_imm_none(), ty, loc);
    MirValue *grown_arg = MS_NEW(&e->m->arena, MirValue);
    *grown_arg = grown;
    g.term = (MirTerm){.kind = MT_BR, .value = MIR_NONE,
                       .a = {.block = ready, .args = grown_arg, .nargs = 1}};
    MIR_PUSH(e->m, e->out, e->nout, e->cout, MirBlockData, g);

    MirValue param = mir_new_value(e->m, e->f, ty);
    MirBlockData r = mir_block_empty();
    MirBlockParam bp = {param, MM_MOVE};
    MIR_PUSH(e->m, r.params, r.nparams, r.cparams, MirBlockParam, bp);
    MirValue push_args[2] = {param, inst.args[1]};
    MirInst pushed = mir_inst(MOP_ListPushU, mir_imm_none(), inst.res, loc,
                              mir_args_copy(e->m, push_args, 2), 2);
    MIR_PUSH(e->m, r.insts, r.ninsts, r.cinsts, MirInst, pushed);
    *cur = r;
}

static void expand_inst(Expander *e, MirInst inst, MirBlockData *cur) {
    switch ((MirOp)inst.op) {
    case MOP_ListPush:
        expand_push(e, inst, cur);
        break;
    case MOP_OptUnwrap:
        expand_unwrap(e, inst, cur);
        break;
    default:
        expand_access(e, inst, cur);
        break;
    }
}

/* Points the targets of an original terminator at the new numbers of the blocks they name. */
static void ex_renumber(MirModule *m, MirTerm *term, const uint32_t *start) {
    switch ((MirTermKind)term->kind) {
    case MT_BR:
        term->a.block = start[term->a.block];
        break;
    case MT_CONDBR:
        term->a.block = start[term->a.block];
        term->b.block = start[term->b.block];
        break;
    case MT_SWITCH: {
        MirCase *cases = MS_NEW_N(&m->arena, MirCase, term->ncases ? term->ncases : 1);
        for (uint32_t i = 0; i < term->ncases; i++) {
            cases[i] = term->cases[i];
            cases[i].target.block = start[cases[i].target.block];
        }
        term->cases = cases;
        term->b.block = start[term->b.block];
        break;
    }
    case MT_RET:
    case MT_FAULT:
    case MT_UNREACHABLE:
        break;
    }
}

static uint32_t ex_block_continuations(const MirBlockData *b, bool checks) {
    uint32_t n = 0;
    for (uint32_t i = 0; i < b->ninsts; i++) {
        n += ex_continuations((MirOp)b->insts[i].op, checks);
    }
    return n;
}

static void expand_func(Expander *e) {
    MirFunc *f = e->f;
    MirBlockData *old = f->blocks;
    uint32_t nold = f->nblocks;
    uint32_t *start = MS_NEW_N(&e->m->arena, uint32_t, nold);
    uint32_t total = 0;
    for (uint32_t bi = 0; bi < nold; bi++) {
        start[bi] = total;
        total += 1 + ex_block_continuations(&old[bi], e->checks);
    }
    e->fault_base = total;
    e->out = MS_NEW_N(&e->m->arena, MirBlockData, total);
    e->cout = total;
    for (uint32_t bi = 0; bi < nold; bi++) {
        e->next = start[bi] + 1;
        MirBlockData cur = mir_block_empty();
        cur.params = old[bi].params;
        cur.nparams = old[bi].nparams;
        cur.cparams = old[bi].cparams;
        cur.term_loc = old[bi].term_loc;
        cur.cold = old[bi].cold;
        for (uint32_t ii = 0; ii < old[bi].ninsts; ii++) {
            MirInst inst = old[bi].insts[ii];
            if (ex_expands((MirOp)inst.op)) {
                expand_inst(e, inst, &cur);
            } else {
                MIR_PUSH(e->m, cur.insts, cur.ninsts, cur.cinsts, MirInst, inst);
            }
        }
        cur.term = old[bi].term;
        ex_renumber(e->m, &cur.term, start);
        MIR_PUSH(e->m, e->out, e->nout, e->cout, MirBlockData, cur);
    }
    for (uint32_t i = 0; i < e->nfaults; i++) {
        MIR_PUSH(e->m, e->out, e->nout, e->cout, MirBlockData, e->faults[i]);
    }
    f->blocks = e->out;
    f->nblocks = e->nout;
    f->cblocks = e->cout;
}

static bool ex_func_expands(const MirFunc *f) {
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        for (uint32_t ii = 0; ii < f->blocks[bi].ninsts; ii++) {
            if (ex_expands((MirOp)f->blocks[bi].insts[ii].op)) {
                return true;
            }
        }
    }
    return false;
}

static uint32_t ex_add_index_fault(MirModule *m) {
    MirParam *params = MS_NEW_N(&m->arena, MirParam, 2);
    params[0] = params[1] = (MirParam){MIR_INT, MM_BORROW};
    MirExtern e = {.name = mir_name(m, "msrt_index_fault", 16), .params = params, .nparams = 2,
                   .ret = MIR_VOID, .noreturn = true, .leaf = true};
    return mir_add_extern(m, &e);
}

bool mir_expand(MirModule *m, bool checks) {
    uint32_t index_fault = MIR_NONE;
    bool changed = false;
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        if (!ex_func_expands(&m->funcs[fi])) {
            continue;
        }
        if (index_fault == MIR_NONE) {
            index_fault = ex_add_index_fault(m);
        }
        Expander e = {.m = m, .f = &m->funcs[fi], .checks = checks, .index_fault = index_fault};
        expand_func(&e);
        changed = true;
    }
    return changed;
}

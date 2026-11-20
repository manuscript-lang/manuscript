/* exit_drops: the program entry returns to a process that is about to exit, so the drops of plain
 * memory on its return paths (a map of types, a list of strings) only walk and free memory the
 * operating system takes back. Each such drop runs only when `msrt_exit_frees` says so: the
 * counting runtime that `make leak-check` links and `MS_FREE_AT_EXIT=1` (for valgrind) keep
 * them. Resources still close: a closer is a call, and a closure, an interface value or a runtime
 * handle is never skipped (`mir_drops_plain_memory`). Port of exit_drops.rs. */
#include <string.h>

#include "ms/mir_analysis.h"
#include "ms/mir_pass.h"

/* Instructions that may sit between the exit drops and the return. */
static bool xd_is_exit_tail(MirOp op) {
    return op == MOP_Drop || op == MOP_DropIf || op == MOP_DepthLeave || op == MOP_IConst ||
           op == MOP_BConst || op == MOP_VoidConst;
}

static bool xd_returns_plainly(const MirFunc *f, const MirBlockData *b) {
    if (b->term.kind == MT_RET) {
        return true;
    }
    if (b->term.kind != MT_BR) {
        return false;
    }
    /* A jump to a block that only builds the result and returns: what inlining `main` into the
     * entry leaves. */
    const MirBlockData *c = &f->blocks[b->term.a.block];
    for (uint32_t i = 0; i < c->ninsts; i++) {
        if (!xd_is_exit_tail((MirOp)c->insts[i].op)) {
            return false;
        }
    }
    return c->term.kind == MT_RET;
}

/* Where the run of exit drops that ends `b` starts. */
static uint32_t xd_exit_run_start(const MirBlockData *b) {
    uint32_t start = b->ninsts;
    while (start > 0 && xd_is_exit_tail((MirOp)b->insts[start - 1].op)) {
        start--;
    }
    return start;
}

static bool xd_drop_is_plain(const MirModule *m, const MirFunc *f, const MirInst *inst) {
    return inst->op == MOP_Drop && mir_drops_plain_memory(m, mir_value_ty(f, inst->args[0]));
}

/* Gates the instruction at `start` onward: the flag call goes first, then each plain drop
 * becomes `drop.if flag, v`. */
static void xd_gate_run(MirModule *m, MirFunc *f, uint32_t block, uint32_t start, uint32_t gate) {
    MirBlockData *b = &f->blocks[block];
    MirValue flag = mir_new_value(m, f, MIR_BOOL);
    MirLoc loc = b->insts[start].loc;
    /* Decide before inserting: the call is not a drop, but the run moves by one. */
    uint32_t run = b->ninsts - start;
    bool *plain = MS_NEW_N(&m->arena, bool, run);
    for (uint32_t i = 0; i < run; i++) {
        plain[i] = xd_drop_is_plain(m, f, &b->insts[start + i]);
    }
    MirInst call = mir_inst(MOP_CallRt, mir_imm_ext(gate), flag, loc, mir_args_copy(m, NULL, 0), 0);
    mir_block_insert(m, b, start, &call);
    for (uint32_t i = 0; i < run; i++) {
        MirInst *inst = &b->insts[start + 1 + i];
        if (!plain[i]) {
            continue;
        }
        MirValue *args = MS_NEW_N(&m->arena, MirValue, (size_t)inst->nargs + 1);
        args[0] = flag;
        memcpy(&args[1], inst->args, sizeof(MirValue) * inst->nargs);
        inst->op = MOP_DropIf;
        inst->args = args;
        inst->nargs++;
    }
}

static uint32_t xd_add_gate(MirModule *m) {
    MirExtern e = {.name = mir_name(m, "msrt_exit_frees", 15), .params = MS_NEW(&m->arena, MirParam),
                   .ret = MIR_BOOL, .leaf = true};
    return mir_add_extern(m, &e);
}

/* Gates the plain drops that end each returning path of `fid`. Every path is found before any is
 * rewritten, because a gated block no longer looks like one that only builds a result. */
static void xd_gate_returns(MirModule *m, uint32_t fid, uint32_t *gate) {
    MirFunc *f = &m->funcs[fid];
    uint32_t *starts = MS_NEW_N(&m->arena, uint32_t, f->nblocks);
    bool any_block = false;
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        const MirBlockData *b = &f->blocks[bi];
        starts[bi] = MIR_NONE;
        if (!xd_returns_plainly(f, b)) {
            continue;
        }
        uint32_t start = xd_exit_run_start(b);
        for (uint32_t i = start; i < b->ninsts && starts[bi] == MIR_NONE; i++) {
            if (xd_drop_is_plain(m, f, &b->insts[i])) {
                starts[bi] = start;
                any_block = true;
            }
        }
    }
    if (!any_block) {
        return;
    }
    if (*gate == MIR_NONE) {
        *gate = xd_add_gate(m);
    }
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        if (starts[bi] != MIR_NONE) {
            xd_gate_run(m, f, bi, starts[bi], *gate);
        }
    }
}

void mir_exit_drops(MirModule *m) {
    if (m->entry == MIR_NONE) {
        return;
    }
    uint32_t *callers = MS_NEW_N(&m->arena, uint32_t, m->nfuncs);
    uint32_t *last_caller = MS_NEW_N(&m->arena, uint32_t, m->nfuncs);
    memset(callers, 0, sizeof(uint32_t) * m->nfuncs);
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        const MirFunc *f = &m->funcs[fi];
        for (uint32_t bi = 0; bi < f->nblocks; bi++) {
            for (uint32_t ii = 0; ii < f->blocks[bi].ninsts; ii++) {
                const MirInst *inst = &f->blocks[bi].insts[ii];
                if (inst->op == MOP_Call && inst->imm.tag == MI_FUNC) {
                    callers[inst->imm.a]++;
                    last_caller[inst->imm.a] = fi;
                }
            }
        }
    }
    /* An entry that something calls again, or a `main` called from anywhere but the entry, is
     * left alone: its return is not the process exit. */
    uint32_t gate = MIR_NONE;
    uint32_t nfuncs = m->nfuncs;
    if (callers[m->entry] == 0) {
        xd_gate_returns(m, m->entry, &gate);
    }
    for (uint32_t gi = 0; gi < nfuncs; gi++) {
        MsStr name = ms_name(&m->names, m->funcs[gi].name);
        bool is_main = name.len == 4 && memcmp(name.ptr, "main", 4) == 0;
        if (is_main && gi != m->entry && callers[gi] == 1 && last_caller[gi] == m->entry) {
            xd_gate_returns(m, gi, &gate);
        }
    }
}

/* count_ops: puts a call of `msrt_ops_add(n)` at the head of every block, n being the block's
 * instruction count plus one for its terminator. Port of count_ops.rs. */
#include "ms/mir_analysis.h"
#include "ms/mir_pass.h"

void mir_count_ops(MirModule *m) {
    const MirTy int_param = MIR_INT;
    const MirExtern def = {.name = mir_name(m, "msrt_ops_add", 12),
                           .params = MS_NEW_N(&m->arena, MirParam, 1), .nparams = 1,
                           .ret = MIR_VOID, .leaf = true, .role = MR_NONE};
    def.params[0] = (MirParam){int_param, MM_BORROW};
    const uint32_t add = mir_add_extern(m, &def);
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        MirFunc *f = &m->funcs[fi];
        const uint32_t nblocks = f->nblocks;
        for (uint32_t bi = 0; bi < nblocks; bi++) {
            const int64_t n = (int64_t)f->blocks[bi].ninsts + 1;
            const MirLoc loc = f->blocks[bi].ninsts > 0 ? f->blocks[bi].insts[0].loc : f->blocks[bi].term_loc;
            const MirValue count = mir_new_value(m, f, MIR_INT);
            const MirValue done = mir_new_value(m, f, MIR_VOID);
            const MirInst head[2] = {
                mir_inst(MOP_IConst, mir_imm_int(n), count, loc, mir_args_copy(m, NULL, 0), 0),
                mir_inst(MOP_CallRt, mir_imm_ext(add), done, loc, mir_args_copy(m, &count, 1), 1),
            };
            mir_block_insert(m, &f->blocks[bi], 0, &head[1]);
            mir_block_insert(m, &f->blocks[bi], 0, &head[0]);
        }
    }
}

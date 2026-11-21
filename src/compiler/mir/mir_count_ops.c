/* count_ops: puts a call of `msrt_ops_add(n)` at the head of every block, n being the block's instruction count
 * plus one for its terminator. */
#include "compiler/mir/mir_count_ops.h"

#include "compiler/mir/mir_analysis.h"
#include "compiler/mir/mir_pass.h"

void mir_count_ops(MirModule *module) {
  const MirTy int_param = MIR_INT;
  uint32_t add = mir_extern_get(module, ms_span_of_text("msrt_ops_add"), &int_param, 1, MIR_VOID, true, MR_NONE);
  for (uint32_t index = 0; index < module->funcs.len; index++) {
    MirFunc *func = &module->funcs.ptr[index];
    for (uint32_t block = 0; block < func->blocks.len; block++) {
      MirBlockData *data = &func->blocks.ptr[block];
      MirLoc loc = data->insts.len > 0 ? data->insts.ptr[0].loc : data->term_loc;
      MirValue count = mir_new_value(func, MIR_INT);
      MirValue done = mir_new_value(func, MIR_VOID);
      MirInst head[2] = {
          mir_inst(MOP_IConst, mir_imm_int((int64_t)data->insts.len + 1), count, loc, mir_args_copy(module, NULL, 0), 0),
          mir_inst(MOP_CallRt, mir_imm_ext(add), done, loc, mir_args_copy(module, &count, 1), 1),
      };
      /* In the entry block the recursion check (`depth.enter`) stays first. */
      uint32_t at = block == 0 ? mir_entry_insert_at(func) : 0;
      mir_block_insert(data, at, &head[1]);
      mir_block_insert(data, at, &head[0]);
    }
  }
}

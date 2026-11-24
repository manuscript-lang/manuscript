/* cancel_edges: tells the runtime that every function of the program leaves on a delivered cancel by an ordinary
 * return (the exit after each call that can park, lower_unwind.c), so natives return with the unwinding byte set
 * instead of jumping. The program's entry says so first, in programs that start tasks. */

#include "compiler/mir/mir_cancel_edges.h"

#include "compiler/mir/mir_analysis.h"
#include "compiler/mir/mir_pass.h"

bool mir_cancel_edges(MirModule *m) {
  if (!mir_starts_tasks(m) || m->entry == MIR_NONE || m->funcs.ptr[m->entry].blocks.len == 0) {
    return false;
  }
  const uint32_t on = mir_extern_get(m, ms_span_of_text("msrt_cancel_edges"), NULL, 0, MIR_VOID, true, MR_NONE);
  MirFunc *f = &m->funcs.ptr[m->entry];
  const MirValue res = mir_new_value(f, MIR_VOID);
  const MirInst call = mir_inst(MOP_CallRt, mir_imm_ext(on), res, f->loc, mir_args_copy(m, NULL, 0), 0);
  mir_block_insert(&f->blocks.ptr[0], mir_entry_insert_at(f), &call);
  return true;
}

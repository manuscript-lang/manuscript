/* Owns the one-sided branch the lowering uses where LLVM's emitter writes `emit_if`: a side that runs only when a
 * condition holds, and a join whose words are zero when the side was skipped. */
#include "compiler/emit_cl/cl_cx.h"

ClIf cl_if_begin(ClCx *cx, ms_cl_val condition, uint32_t words) {
  ms_cl_fn *f = cx->fb;
  ClIf branch = {.then = ms_cl_block_new(f), .join = ms_cl_block_new(f), .words = words};
  ms_cl_val zeros[CL_IF_WORDS];
  for (uint32_t word = 0; word < words; word++) {
    (void)ms_cl_block_param_add(f, branch.join, MS_CL_I64);
    zeros[word] = cl_const(cx, 0);
  }
  ms_cl_brif(f, condition, branch.then, NULL, 0, branch.join, zeros, words);
  ms_cl_enter(f, branch.then);
  cx->cur = branch.then;
  return branch;
}

void cl_if_end(ClCx *cx, const ClIf *branch, const ms_cl_val *values, ms_cl_val *joined) {
  ms_cl_fn *f = cx->fb;
  ms_cl_jump(f, branch->join, values, branch->words);
  ms_cl_enter(f, branch->join);
  cx->cur = branch->join;
  for (uint32_t word = 0; word < branch->words; word++) {
    joined[word] = ms_cl_block_param(f, branch->join, word);
  }
}

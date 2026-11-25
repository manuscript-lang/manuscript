/* Owns the one-sided branch the lowering uses where LLVM's emitter writes `emit_if`: a side that runs only when a
 * condition holds, and a join whose words are zero when the side was skipped. */
#include "compiler/emit_cl/cl_cx.h"

ClIf clx_if_begin(ClCx *cx, cl_val condition, uint32_t words) {
  cl_fn *f = cx->fb;
  ClIf branch = {.then = cl_block_new(f), .join = cl_block_new(f), .words = words};
  cl_val zeros[CLX_IF_WORDS];
  for (uint32_t word = 0; word < words; word++) {
    (void)cl_block_param_add(f, branch.join, CL_I64);
    zeros[word] = clx_const(cx, 0);
  }
  cl_brif(f, condition, branch.then, NULL, 0, branch.join, zeros, words);
  cl_enter(f, branch.then);
  cx->cur = branch.then;
  return branch;
}

void clx_if_end(ClCx *cx, const ClIf *branch, const cl_val *values, cl_val *joined) {
  cl_fn *f = cx->fb;
  cl_jump(f, branch->join, values, branch->words);
  cl_enter(f, branch->join);
  cx->cur = branch->join;
  for (uint32_t word = 0; word < branch->words; word++) {
    joined[word] = cl_block_param(f, branch->join, word);
  }
}

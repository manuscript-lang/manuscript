/* Owns closures. A closure object is a header of three words, the clone, drop and code entries, then each capture at its
 * offset (`mir_closure_layout`). Its value is the object's address; the code takes that address as its first leaf, so
 * `call.ind` (cl_call.c) loads the code word and calls it with the closure first. */
#include "compiler/emit_cl/cl_cx.h"

/* The header word offsets of a closure object. */
enum { CLOSURE_CLONE = 0, CLOSURE_DROP = 8, CLOSURE_CODE = 16 };

static void store_entry(ClCx *cx, cl_val object, int32_t offset, uint32_t func) {
  cl_store(cx->fb, CL_NOTRAP, cl_func_addr(cx->fb, cx->mod->funcs[func]), object, offset);
}

/* `closure.new`: a frame slot or a heap block, the three header entries, then the captures. */
static bool closure_new(ClCx *cx, const MirInst *inst) {
  const uint32_t code = inst->imm.a;
  const bool framed = cx->framed != NULL && cx->framed[inst->res];
  const MirClosureLayout layout = mir_closure_layout(cx->layouts, &cx->module->funcs.ptr[code]);
  if (cx->mod->glue == NULL) {
    cx->why = "closure without glue";
    return false;
  }
  const uint32_t clone = mir_glue_find(cx->mod->glue, MG_CLOSURE_CLONE, MIR_VOID, code, 0);
  const uint32_t drop = mir_glue_find(cx->mod->glue, framed ? MG_CLOSURE_DROP_FRAMED : MG_CLOSURE_DROP, MIR_VOID, code, 0);
  if (clone == MIR_NONE || drop == MIR_NONE) {
    cx->why = "closure glue was not made";
    return false;
  }
  const cl_val object = framed ? cl_stack_addr(cx->fb, cl_stack_slot(cx->fb, layout.size, 4), 0)
                                  : clx_alloc(cx, layout.size);
  clx_set(cx, inst->res, 0, object);
  store_entry(cx, object, CLOSURE_CLONE, clone);
  store_entry(cx, object, CLOSURE_DROP, drop);
  store_entry(cx, object, CLOSURE_CODE, code);
  for (uint32_t capture = 0; capture < layout.ncaptures && capture < inst->nargs; capture++) {
    if (layout.captures[capture].leaves.len == 0) {
      continue;
    }
    const cl_val at = cl_iadd(cx->fb, object, clx_const(cx, layout.captures[capture].offset));
    clx_leaves_at(cx, inst->args[capture], at, false);
  }
  return true;
}

/* `closure.cap`, `closure.cap_addr`: capture `i` of the closure being run, by value or by address. */
static bool closure_capture(ClCx *cx, const MirInst *inst) {
  const MirClosureLayout layout = mir_closure_layout(cx->layouts, cx->func);
  const uint32_t index = inst->imm.a;
  if (index >= layout.ncaptures) {
    cx->why = "capture out of range";
    return false;
  }
  const cl_val at = cl_iadd(cx->fb, clx_arg(cx, inst, 0), clx_const(cx, layout.captures[index].offset));
  if (inst->op == MOP_ClosureCapAddr) {
    clx_set(cx, inst->res, 0, at);
  } else if (layout.captures[index].leaves.len != 0) {
    clx_leaves_at(cx, inst->res, at, true);
  }
  return true;
}

bool clx_closure_op(ClCx *cx, const MirInst *inst, bool *handled) {
  *handled = true;
  switch ((MirOp)inst->op) {
  case MOP_ClosureNew:
    return closure_new(cx, inst);
  case MOP_ClosureCap:
  case MOP_ClosureCapAddr:
    return closure_capture(cx, inst);
  default:
    *handled = false;
    return true;
  }
}

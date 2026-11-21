/* Owns closures and indirect calls. A closure object is a header of three words, the clone, drop and code
 * entries, then each capture at its offset (`mir_closure_layout`). Its value is the object's address; the code
 * takes that address as its first leaf, so `call.ind` loads the code word and calls it with the closure first. */
#include "compiler/emit/emit_cx.h"

/* The header word offsets of a closure object. */
enum { CLOSURE_CLONE = 0, CLOSURE_DROP = 8, CLOSURE_CODE = 16 };

void emit_offset_pointer(EmitCx *cx, const char *base, uint32_t offset, char *out, size_t capacity) {
  uint32_t number = cx->next++;
  ms_strbuild_printf(cx->out, "  %%q%u = getelementptr i8, ptr %s, i64 %u\n", number, base, offset);
  emit_register_name(out, capacity, "q", number);
}

/* `call.ind`: the code word of the closure in the first operand, called with the closure first. */
static void call_indirect(EmitCx *cx, const MirInst *inst, const EmitSite *site) {
  char env[24];
  char code_at[24];
  char callee[24];
  emit_pointer(cx, inst->args[0], env, sizeof env);
  emit_offset_pointer(cx, env, CLOSURE_CODE, code_at, sizeof code_at);
  uint32_t number = cx->next++;
  ms_strbuild_printf(cx->out, "  %%k%u = load ptr, ptr %s\n", number, code_at);
  emit_register_name(callee, sizeof callee, "k", number);
  emit_call_to(cx, inst, site, callee, NULL);
}

/* Stores `@func` at `offset` of the closure object `object`. */
static void store_entry(EmitCx *cx, const char *object, uint32_t offset, uint32_t func) {
  char at[24];
  emit_offset_pointer(cx, object, offset, at, sizeof at);
  ms_strbuild_append_text(cx->out, "  store ptr ");
  emit_function_symbol(cx, func);
  ms_strbuild_printf(cx->out, ", ptr %s\n", at);
}

/* `closure.new`: a frame slot or a heap block, the three header entries, then the captures. */
static bool closure_new(EmitCx *cx, const MirInst *inst, const EmitSite *site) {
  uint32_t code = inst->imm.a;
  bool framed = cx->framed != NULL && cx->framed[inst->res];
  MirClosureLayout layout = mir_closure_layout(cx->layouts, &cx->module->funcs.ptr[code]);
  if (cx->glue == NULL) {
    cx->why = "closure without glue";
    return false;
  }
  uint32_t clone = mir_glue_find(cx->glue, MG_CLOSURE_CLONE, MIR_VOID, code, 0);
  uint32_t drop = mir_glue_find(cx->glue, framed ? MG_CLOSURE_DROP_FRAMED : MG_CLOSURE_DROP, MIR_VOID, code, 0);
  if (clone == MIR_NONE || drop == MIR_NONE) {
    cx->why = "closure glue was not made";
    return false;
  }
  char object[24];
  if (framed) {
    emit_text_name(object, sizeof object, "o", site->block, "_", site->index);
    ms_strbuild_printf(cx->out, "  %%v%u = ptrtoint ptr %s to i64\n", inst->res, object);
  } else {
    ms_strbuild_printf(cx->out, "  %%v%u = call i64 @msrt_alloc(i64 %u)\n", inst->res, layout.size);
    emit_pointer(cx, inst->res, object, sizeof object);
  }
  store_entry(cx, object, CLOSURE_CLONE, clone);
  store_entry(cx, object, CLOSURE_DROP, drop);
  store_entry(cx, object, CLOSURE_CODE, code);
  for (uint32_t capture = 0; capture < layout.ncaptures && capture < inst->nargs; capture++) {
    if (layout.captures[capture].leaves.len == 0) {
      continue;
    }
    char at[24];
    emit_offset_pointer(cx, object, layout.captures[capture].offset, at, sizeof at);
    emit_leaves_at(cx, inst->args[capture], at, false);
  }
  return true;
}

/* `closure.cap`, `closure.cap_addr`: capture `i` of the closure being run, by value or by address. */
static bool closure_capture(EmitCx *cx, const MirInst *inst) {
  MirClosureLayout layout = mir_closure_layout(cx->layouts, cx->func);
  uint32_t index = inst->imm.a;
  if (index >= layout.ncaptures) {
    cx->why = "capture out of range";
    return false;
  }
  uint32_t offset = layout.captures[index].offset;
  if (inst->op == MOP_ClosureCapAddr) {
    ms_strbuild_printf(cx->out, "  %%v%u = add i64 %%v%u, %u\n", inst->res, inst->args[0], offset);
    return true;
  }
  if (layout.captures[index].leaves.len == 0) {
    return true;
  }
  char env[24];
  char at[24];
  emit_pointer(cx, inst->args[0], env, sizeof env);
  emit_offset_pointer(cx, env, offset, at, sizeof at);
  emit_leaves_at(cx, inst->res, at, true);
  return true;
}

bool emit_closure_op(EmitCx *cx, const MirInst *inst, const EmitSite *site, bool *handled) {
  *handled = true;
  switch ((MirOp)inst->op) {
  case MOP_FuncAddr:
    ms_strbuild_printf(cx->out, "  %%v%u = ptrtoint ptr ", inst->res);
    emit_function_symbol(cx, inst->imm.a);
    ms_strbuild_append_text(cx->out, " to i64\n");
    return true;
  case MOP_ClosureNew:
    return closure_new(cx, inst, site);
  case MOP_ClosureCap:
  case MOP_ClosureCapAddr:
    return closure_capture(cx, inst);
  case MOP_CallInd:
    call_indirect(cx, inst, site);
    return true;
  default:
    *handled = false;
    return true;
  }
}

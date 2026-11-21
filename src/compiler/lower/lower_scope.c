/* compiler/lower/lower_scope.c: ownership scopes. Lowering marks where each owned value belongs (`scope.own`)
 * and where each scope ends (`scope.end`); drop elaboration (mir_elab) turns the markers into drops, closes and
 * drop flags on the paths that still hold the value. */
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_analysis.h"

uint32_t fn_scope(const LowerFn *fn) {
  return fn->open[fn->nopen - 1];
}

uint32_t fn_scope_begin(LowerFn *fn) {
  const uint32_t id = fn->next_scope++;
  /* The parent is stored plus one so that zero means none. */
  const uint32_t parent_plus_one = fn->nopen > 0 ? fn->open[fn->nopen - 1] + 1 : 0;
  const MirImm imm = {.tag = MI_SCOPE, .a = id, .b = parent_plus_one};
  (void)mir_b_emit(&fn->b, MOP_ScopeBegin, NULL, 0, imm, MIR_NONE);
  if (fn->nopen == LOWER_MAX_SCOPES) {
    (void)fn_fail(fn, "scopes nest too deeply");
    return id;
  }
  fn->open[fn->nopen++] = id;
  return id;
}

static void emit_end(LowerFn *fn, uint32_t scope) {
  const MirImm imm = {.tag = MI_SCOPE, .a = scope, .b = 0};
  (void)mir_b_emit(&fn->b, MOP_ScopeEnd, NULL, 0, imm, MIR_NONE);
}

void fn_scope_end(LowerFn *fn) {
  if (fn->nopen == 0) {
    return;
  }
  emit_end(fn, fn->open[--fn->nopen]);
}

void fn_scope_unwind(LowerFn *fn, uint32_t keep) {
  for (uint32_t depth = fn->nopen; depth > keep; depth--) {
    emit_end(fn, fn->open[depth - 1]);
  }
}

void fn_own(LowerFn *fn, uint32_t scope, MirValue value) {
  const MirImm imm = {.tag = MI_SCOPE, .a = scope, .b = 0};
  (void)mir_b_emit(&fn->b, MOP_ScopeOwn, &value, 1, imm, MIR_NONE);
}

void fn_own_result(LowerFn *fn, MirValue result) {
  if (result == MIR_NONE) {
    return;
  }
  const MirInstList *insts = &fn->b.func.blocks.ptr[fn->b.cur].insts;
  MirMode mode = MM_BORROW;
  if (mir_result_mode(fn->cx->module, &fn->b.func, &insts->ptr[insts->len - 1], &mode) && mode == MM_MOVE) {
    fn_own(fn, fn_scope(fn), result);
  }
}

MirValue fn_emit(LowerFn *fn, MirOp op, const MirValue *args, uint32_t nargs, MirImm imm, MirTy ty) {
  const MirValue result = mir_b_emit(&fn->b, op, args, nargs, imm, ty);
  fn_own_result(fn, result);
  return result;
}

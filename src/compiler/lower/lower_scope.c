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

/* The scope owns what its `var` locals hold now, which only the end of the scope can know. */
static void own_vars(LowerFn *fn, uint32_t scope) {
  for (uint32_t at = fn->nowned_vars; at > 0; at--) {
    if (fn->owned_vars[at - 1].scope == scope) {
      fn_own(fn, scope, mir_b_use_var(&fn->b, fn->owned_vars[at - 1].var));
    }
  }
}

bool fn_scope_own_var(LowerFn *fn, MirVar var) {
  if (fn->nowned_vars == LOWER_MAX_OWNED_VARS) {
    uint32_t kept = 0; /* entries of scopes that ended on a path that returned are stale */
    for (uint32_t at = 0; at < fn->nowned_vars; at++) {
      for (uint32_t depth = 0; depth < fn->nopen; depth++) {
        if (fn->open[depth] == fn->owned_vars[at].scope) {
          fn->owned_vars[kept++] = fn->owned_vars[at];
          break;
        }
      }
    }
    fn->nowned_vars = kept;
    if (kept == LOWER_MAX_OWNED_VARS) {
      return fn_fail(fn, "too many mutable variables are open at once");
    }
  }
  fn->owned_vars[fn->nowned_vars++] = (LowerOwnedVar){fn_scope(fn), var};
  return true;
}

static void emit_end(LowerFn *fn, uint32_t scope) {
  own_vars(fn, scope);
  const MirImm imm = {.tag = MI_SCOPE, .a = scope, .b = 0};
  (void)mir_b_emit(&fn->b, MOP_ScopeEnd, NULL, 0, imm, MIR_NONE);
}

void fn_scope_end(LowerFn *fn) {
  if (fn->nopen == 0) {
    return;
  }
  const uint32_t scope = fn->open[--fn->nopen];
  emit_end(fn, scope);
  while (fn->nowned_vars > 0 && fn->owned_vars[fn->nowned_vars - 1].scope == scope) {
    fn->nowned_vars--;
  }
}

/* A return puts each `var` parameter's final value back into its caller's slot. */
static void put_var_params(LowerFn *fn) {
  for (uint32_t at = 0; at < fn->nvar_params; at++) {
    const LowerVarParam *param = &fn->var_params[at];
    const MirValue stored[2] = {param->slot, mir_b_use_var(&fn->b, param->var)};
    (void)mir_b_emit(&fn->b, mir_needs_drop(fn->cx->module, param->ty) ? MOP_Put : MOP_Store, stored, 2,
                     (MirImm){0}, MIR_NONE);
  }
}

void fn_scope_unwind(LowerFn *fn, uint32_t keep) {
  fn_writebacks_put(fn, keep);
  if (keep == 0) {
    put_var_params(fn);
  }
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

bool fn_is_borrowed_view(LowerFn *fn, MirValue value) {
  const MirInstList *insts = &fn->b.func.blocks.ptr[fn->b.cur].insts;
  if (insts->len == 0) {
    return false;
  }
  const MirInst *last = &insts->ptr[insts->len - 1];
  MirMode mode = MM_MOVE;
  return last->res == value && mir_result_mode(fn->cx->module, &fn->b.func, last, &mode) && mode == MM_BORROW;
}

bool fn_fresh_owner(LowerFn *fn, MirValue value) {
  const MirInstList *insts = &fn->b.func.blocks.ptr[fn->b.cur].insts;
  if (insts->len == 0) {
    return false;
  }
  const MirInst *last = &insts->ptr[insts->len - 1];
  if (last->op == MOP_ScopeOwn) {
    /* The scope took the result of the instruction before it. */
    return last->nargs == 1 && last->args[0] == value;
  }
  MirMode mode = MM_BORROW;
  return last->res == value && mir_result_mode(fn->cx->module, &fn->b.func, last, &mode) && mode == MM_MOVE;
}

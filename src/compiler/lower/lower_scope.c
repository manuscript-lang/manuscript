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
    if (fn->owned_vars[at - 1].scope != scope) {
      continue;
    }
    if (fn->owned_vars[at - 1].released) {
      continue;
    }
    const MirValue value = mir_b_use_var(&fn->b, fn->owned_vars[at - 1].var);
    const uint32_t moved = fn->owned_vars[at - 1].moved;
    if (moved == 0) {
      fn_own(fn, scope, value);
      continue;
    }
    /* A record that handed a field on releases the fields it still holds. */
    const MirImm mask = {.tag = MI_TYPEMASK, .a = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, value))->id, .b = moved};
    (void)mir_b_emit(&fn->b, MOP_TypeRelease, &value, 1, mask, MIR_NONE);
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
  fn->owned_vars[fn->nowned_vars++] = (LowerOwnedVar){fn_scope(fn), var, 0, false};
  return true;
}

void fn_scope_var_moved(LowerFn *fn, MirVar var, uint32_t field) {
  for (uint32_t at = fn->nowned_vars; at > 0 && field < 32; at--) {
    if (fn->owned_vars[at - 1].var == var) {
      fn->owned_vars[at - 1].moved |= UINT32_C(1) << field;
      return;
    }
  }
}

void fn_scope_var_released(LowerFn *fn, MirVar var, bool released) {
  for (uint32_t at = fn->nowned_vars; at > 0; at--) {
    if (fn->owned_vars[at - 1].var == var) {
      fn->owned_vars[at - 1].released = released;
      return;
    }
  }
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
  if (insts->len == 0 || insts->ptr[insts->len - 1].res != result) {
    return; /* not a result of the last instruction: a parameter or an earlier value already has its owner */
  }
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

/* The one switch of the rule against hidden copies: when true, a copy no `.clone()` asked for is a compile error.
 * Off while the stdlib and call sites that copy are made explicit (#6194); turn it back on once
 * the test sweep shows no loss. */
static const bool implicit_clone_is_error = false;

bool lower_hidden_copies_allowed(void) {
  return !implicit_clone_is_error;
}

MirValue fn_implicit_clone(LowerFn *fn, MirValue value, bool own) {
  if (value == MIR_NONE) {
    return MIR_NONE;
  }
  /* A function value never changes, so copying one is how it is shared. */
  if (implicit_clone_is_error && mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, value))->kind != MK_FN) {
    const MsSpan file = fn->b.loc.file < fn->cx->module->files.len ? fn->cx->module->files.ptr[fn->b.loc.file] : ms_span_of_text("?");
    (void)fn_user_fail(fn, "%.*s:%u:%u: this value would be copied implicitly, but `.clone()` is the only copy; write `.clone()`, move it, or borrow it",
                  (int)file.len, (const char *)file.ptr, fn->b.loc.line, fn->b.loc.col);
    return MIR_NONE;
  }
  const MirTy ty = mir_b_ty(&fn->b, value);
  return own ? fn_emit(fn, MOP_Clone, &value, 1, (MirImm){0}, ty) : mir_b_emit(&fn->b, MOP_Clone, &value, 1, (MirImm){0}, ty);
}

bool fn_owns_result(LowerFn *fn, MirValue value) {
  if (mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, value))) {
    return fn_fresh_owner(fn, value);
  }
  for (uint32_t block = 0; block < fn->b.func.blocks.len; block++) {
    const MirInstList *insts = &fn->b.func.blocks.ptr[block].insts;
    for (size_t at = 0; at < insts->len; at++) {
      if (insts->ptr[at].res == value) {
        return !mir_result_borrowed(fn->cx->module, &fn->b.func, &insts->ptr[at]);
      }
    }
  }
  return true;
}

bool fn_fresh_owner(LowerFn *fn, MirValue value) {
  const MirInstList *insts = &fn->b.func.blocks.ptr[fn->b.cur].insts;
  /* Walk back to the instruction that made `value`: a call that wrote its `var` receiver back, or took other
   * values out of their slots, leaves instructions after the result (and its scope.own). */
  for (size_t at = insts->len; at-- > 0;) {
    const MirInst *inst = &insts->ptr[at];
    if (inst->op == MOP_ScopeDisown && inst->nargs == 1 && inst->args[0] == value) {
      return false;
    }
    if (inst->op == MOP_ScopeOwn && inst->nargs == 1 && inst->args[0] == value) {
      return true;
    }
    if (inst->res == value) {
      if (inst->op == MOP_OptNone || inst->op == MOP_OptNoneOwned) {
        return true; /* `none` holds nothing: whoever takes it owns an empty value, so no copy is made */
      }
      MirMode mode = MM_BORROW;
      return mir_result_mode(fn->cx->module, &fn->b.func, inst, &mode) && mode == MM_MOVE;
    }
  }
  /* Made in a block above this one (a `move` parameter, an owner declared before an `if`): the scope that owns it
   * registered it there, and a disown in a sibling block is not on this path. */
  for (uint32_t block = 0; block < fn->b.func.blocks.len; block++) {
    if (block == fn->b.cur) {
      continue;
    }
    const MirInstList *list = &fn->b.func.blocks.ptr[block].insts;
    for (size_t at = 0; at < list->len; at++) {
      if (list->ptr[at].op == MOP_ScopeOwn && list->ptr[at].nargs == 1 && list->ptr[at].args[0] == value) {
        return true;
      }
    }
  }
  return false;
}

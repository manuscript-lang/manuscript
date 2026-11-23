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
  fn->open_closes[fn->nopen] = false;
  fn->open[fn->nopen++] = id;
  return id;
}

/* The scope owns what its `var` locals hold now, which only the end of the scope can know; a record that handed a field
 * on is settled by `settle_moved_vars` once the scope's other owners are done. */
static void own_vars(LowerFn *fn, uint32_t scope) {
  for (uint32_t at = fn->nowned_vars; at > 0; at--) {
    if (fn->owned_vars[at - 1].scope != scope) {
      continue;
    }
    if (fn->owned_vars[at - 1].released || fn->owned_vars[at - 1].pinned != MIR_NONE) {
      continue; /* handed on, or already owned by the end of an inner scope */
    }
    const MirValue value = mir_b_use_var(&fn->b, fn->owned_vars[at - 1].var);
    if (fn->owned_vars[at - 1].moved == 0) {
      fn_own(fn, scope, value);
    } else {
      fn_disown(fn, value); /* an exit before the move owned it: the settle after the scope ends takes over */
    }
  }
}

/* A record that handed a field on closes the resources it still holds, last field first, and releases the rest. It does
 * so after the scope's other owners ended: the record is declared before what it handed its field to. */
static void settle_moved_vars(LowerFn *fn, uint32_t scope) {
  for (uint32_t at = fn->nowned_vars; at > 0; at--) {
    const LowerOwnedVar *entry = &fn->owned_vars[at - 1];
    if (entry->scope != scope || entry->released || entry->pinned != MIR_NONE || entry->moved == 0) {
      continue;
    }
    const MirValue value = mir_b_use_var(&fn->b, entry->var);
    uint32_t handled = entry->moved;
    if (entry->has_mask && entry->checked != MS_TY_NONE) {
      handled |= fn_close_left_fields(fn, value, entry->checked, 0, NULL, entry->moved, mir_b_use_var(&fn->b, entry->mask));
    }
    const MirImm mask = {.tag = MI_TYPEMASK, .a = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, value))->id, .b = handled};
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
  LowerOwnedVar *entry = &fn->owned_vars[fn->nowned_vars++];
  *entry = (LowerOwnedVar){.scope = fn_scope(fn), .var = var, .checked = MS_TY_NONE, .pinned = MIR_NONE};
  if (mir_ty_data(fn->cx->module, fn->b.vars.ptr[var].ty)->kind == MK_TYPE) {
    entry->mask = mir_b_declare_var(&fn->b, MIR_INT, MM_MOVE);
    entry->has_mask = true;
    mir_b_def_var(&fn->b, entry->mask, mir_b_iconst(&fn->b, 0));
  }
  return true;
}

void fn_scope_var_moved(LowerFn *fn, MirVar var, uint32_t field, MsTy checked) {
  for (uint32_t at = fn->nowned_vars; at > 0 && field < 32; at--) {
    if (fn->owned_vars[at - 1].var == var) {
      fn->owned_vars[at - 1].moved |= UINT32_C(1) << field;
      fn->owned_vars[at - 1].checked = checked;
      if (fn->owned_vars[at - 1].has_mask) { /* the path taken records the move: another path may keep the field */
        const MirVar mask = fn->owned_vars[at - 1].mask;
        const MirValue bit = mir_b_iconst(&fn->b, (int64_t)(UINT64_C(1) << field));
        mir_b_def_var(&fn->b, mask, mir_b_binop(&fn->b, MOP_Or, mir_b_use_var(&fn->b, mask), bit));
      }
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

/* The depth at which `scope` is open; past every depth when it is not open (it ended on a path that returned). */
static uint32_t scope_depth(const LowerFn *fn, uint32_t scope) {
  uint32_t depth = fn->nopen;
  while (depth > 0 && fn->open[depth - 1] != scope) {
    depth--;
  }
  return depth > 0 ? depth - 1 : UINT32_MAX;
}

/* Ending a scope that closes a resource can leave the function when the close fails, and the `var` locals of the scopes
 * around it are owned only where those scopes end: until then the close failure's exit would leak them. The scope
 * that is ending owns them for it. */
static void pin_outer_vars(LowerFn *fn, uint32_t depth) {
  for (uint32_t at = fn->nowned_vars; at > 0; at--) {
    LowerOwnedVar *entry = &fn->owned_vars[at - 1];
    if (entry->released || entry->moved != 0 || entry->pinned != MIR_NONE || scope_depth(fn, entry->scope) >= depth) {
      continue;
    }
    entry->pinned = mir_b_use_var(&fn->b, entry->var);
    fn_own(fn, entry->scope, entry->pinned);
  }
}

/* Ends `scope`. A pinned value whose scope stays open past `keep` is the variable's again afterwards. */
static void emit_end(LowerFn *fn, uint32_t scope, uint32_t keep) {
  own_vars(fn, scope);
  const uint32_t depth = scope_depth(fn, scope);
  if (fn->open_closes[depth]) {
    pin_outer_vars(fn, depth);
  }
  const MirImm imm = {.tag = MI_SCOPE, .a = scope, .b = 0};
  (void)mir_b_emit(&fn->b, MOP_ScopeEnd, NULL, 0, imm, MIR_NONE);
  settle_moved_vars(fn, scope);
  for (uint32_t at = 0; at < fn->nowned_vars; at++) {
    LowerOwnedVar *entry = &fn->owned_vars[at];
    if (entry->pinned != MIR_NONE && scope_depth(fn, entry->scope) < keep) {
      (void)mir_b_emit(&fn->b, MOP_ScopeUnpin, &entry->pinned, 1, (MirImm){0}, MIR_NONE);
      entry->pinned = MIR_NONE;
    }
  }
}

void fn_scope_end(LowerFn *fn) {
  if (fn->nopen == 0) {
    return;
  }
  const uint32_t depth = fn->nopen - 1;
  emit_end(fn, fn->open[depth], depth);
  fn_scope_pop(fn);
}

/* Forgets the innermost scope, whose end the paths that leave it have already emitted. */
void fn_scope_pop(LowerFn *fn) {
  const uint32_t scope = fn->open[fn->nopen - 1];
  fn->nopen--;
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
    emit_end(fn, fn->open[depth - 1], keep);
  }
  for (uint32_t at = 0; at < fn->nowned_vars; at++) {
    fn->owned_vars[at].pinned = MIR_NONE; /* this path is over: the next one starts without the pins */
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
  if (!mir_needs_drop(fn->cx->module, ty)) {
    return value; /* a plain value is its own copy */
  }
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

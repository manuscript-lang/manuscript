/* compiler/lower/lower_scope.c: ownership scopes. Lowering marks where each owned value belongs (`scope.own`)
 * and where each scope ends (`scope.end`); drop elaboration (mir_elab) turns the markers into drops, closes and
 * drop flags on the paths that still hold the value. */
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_analysis.h"

/* Doubles `*items` (arena memory, so the old block is simply left) until it holds one more element than `used`. */
void *fn_grow(LowerFn *fn, void *items, uint32_t *cap, uint32_t used, size_t size) {
  const uint32_t need = used + 1;
  if (need <= *cap) {
    return items;
  }
  uint32_t next = *cap == 0 ? 16 : *cap * 2;
  while (next < need) {
    next *= 2;
  }
  void *fresh = ms_arena_alloc_zeroed(&fn->cx->module->arena, size * next, 16);
  if (used > 0) {
    __builtin_memcpy(fresh, items, size * used);
  }
  *cap = next;
  return fresh;
}

void fn_loop_push(LowerFn *fn, MirBlock break_to, MirBlock continue_to) {
  fn->loops = fn_grow(fn, fn->loops, &fn->loops_cap, fn->nloops, sizeof(LowerLoop));
  fn->loops[fn->nloops++] = (LowerLoop){break_to, continue_to, fn->nopen};
}

uint32_t fn_scope(const LowerFn *fn) {
  return fn->open[fn->nopen - 1];
}

uint32_t fn_scope_begin(LowerFn *fn) {
  const uint32_t id = fn->next_scope++;
  /* The parent is stored plus one so that zero means none. */
  const uint32_t parent_plus_one = fn->nopen > 0 ? fn->open[fn->nopen - 1] + 1 : 0;
  const MirImm imm = {.tag = MI_SCOPE, .a = id, .b = parent_plus_one};
  (void)mir_b_emit(&fn->b, MOP_ScopeBegin, NULL, 0, imm, MIR_NONE);
  uint32_t closes_cap = fn->open_cap; /* both arrays grow together, from the same capacity */
  fn->open = fn_grow(fn, fn->open, &closes_cap, fn->nopen, sizeof(uint32_t));
  fn->open_closes = fn_grow(fn, fn->open_closes, &fn->open_cap, fn->nopen, sizeof(uint32_t));
  fn->open_closes[fn->nopen] = 0;
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
    if (fn->owned_vars[at - 1].moved == 0 && !fn->owned_vars[at - 1].leaves) {
      fn_own(fn, scope, value);
    } else {
      fn_disown(fn, value); /* an exit before the move owned it: the settle after the scope ends takes over */
    }
  }
}

/* A record that handed a field on closes the resources it still holds, last field first, and releases the rest. It does
 * so after the scope's other owners ended: the record is declared before what it handed its field to. */
static void settle_moved_vars(LowerFn *fn, uint32_t scope, uint32_t closes_seq, bool before) {
  for (uint32_t at = fn->nowned_vars; at > 0; at--) {
    const LowerOwnedVar *entry = &fn->owned_vars[at - 1];
    if ((closes_seq != 0 && entry->seq > closes_seq) != before) {
      continue; /* settled by the other call */
    }
    if (entry->scope != scope || entry->released || entry->pinned != MIR_NONE || (entry->moved == 0 && !entry->leaves)) {
      continue;
    }
    const MirValue value = mir_b_use_var(&fn->b, entry->var);
    uint32_t handled = entry->moved;
    if (entry->has_mask && entry->checked != MS_TY_NONE) {
      const LowerPartMoves parts = {.partial = entry->partial, .bits = entry->nbits,
                                    .flag = entry->has_nmask ? mir_b_use_var(&fn->b, entry->nmask) : MIR_NONE, .inner = entry->inner};
      handled |= fn_close_left_fields(fn, value, entry->checked, 0, NULL, entry->moved, mir_b_use_var(&fn->b, entry->mask),
                                      entry->partial != 0 ? &parts : NULL);
    }
    const MirImm mask = {.tag = MI_TYPEMASK, .a = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, value))->id, .b = handled};
    (void)mir_b_emit(&fn->b, MOP_TypeRelease, &value, 1, mask, MIR_NONE);
  }
}

bool fn_scope_own_var(LowerFn *fn, MirVar var, MsTy leaves) {
  fn->owned_vars = fn_grow(fn, fn->owned_vars, &fn->owned_vars_cap, fn->nowned_vars, sizeof(LowerOwnedVar));
  LowerOwnedVar *entry = &fn->owned_vars[fn->nowned_vars++];
  *entry = (LowerOwnedVar){.scope = fn_scope(fn), .seq = ++fn->own_seq, .var = var, .checked = leaves, .leaves = leaves != MS_TY_NONE, .pinned = MIR_NONE};
  if (mir_ty_data(fn->cx->module, fn->b.vars.ptr[var].ty)->kind == MK_TYPE) {
    entry->mask = mir_b_declare_var(&fn->b, MIR_INT, MM_MOVE);
    entry->has_mask = true;
    mir_b_def_var(&fn->b, entry->mask, mir_b_iconst(&fn->b, 0));
    const MirTypeDef *def = &fn->cx->module->type_defs.ptr[mir_ty_data(fn->cx->module, fn->b.vars.ptr[var].ty)->id];
    for (uint32_t at = 0; at < def->nfields && at < 8; at++) { /* a record field may hand a part of its own on */
      if (mir_ty_data(fn->cx->module, def->fields[at].ty)->kind == MK_TYPE && mir_needs_drop(fn->cx->module, def->fields[at].ty)) {
        entry->nmask = mir_b_declare_var(&fn->b, MIR_INT, MM_MOVE);
        entry->has_nmask = true;
        mir_b_def_var(&fn->b, entry->nmask, mir_b_iconst(&fn->b, 0));
        break;
      }
    }
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

bool fn_scope_var_moved_part(LowerFn *fn, MirVar var, uint32_t field, uint32_t part, MsTy checked, MsTy field_type) {
  for (uint32_t at = fn->nowned_vars; at > 0 && field < 8 && part < 8; at--) {
    LowerOwnedVar *entry = &fn->owned_vars[at - 1];
    if (entry->var != var || !entry->has_nmask) {
      continue;
    }
    entry->moved |= UINT32_C(1) << field;
    entry->partial |= UINT32_C(1) << field;
    entry->nbits |= UINT64_C(1) << (field * 8 + part);
    entry->checked = checked;
    entry->inner[field] = field_type;
    const MirValue bit = mir_b_iconst(&fn->b, (int64_t)(UINT64_C(1) << (field * 8 + part)));
    mir_b_def_var(&fn->b, entry->nmask, mir_b_binop(&fn->b, MOP_Or, mir_b_use_var(&fn->b, entry->nmask), bit));
    return true;
  }
  return false;
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
  /* A close that fails leaves the function from the scope end, before any code after it. A record declared after
   * the scope's last closing owner closes before that owner, so it settles before the end and that exit has nothing
   * left to release; the others settle after it, once the scope's owners are done. */
  const uint32_t closes_seq = fn->open_closes[depth];
  settle_moved_vars(fn, scope, closes_seq, true);
  const MirImm imm = {.tag = MI_SCOPE, .a = scope, .b = 0};
  (void)mir_b_emit(&fn->b, MOP_ScopeEnd, NULL, 0, imm, MIR_NONE);
  settle_moved_vars(fn, scope, closes_seq, false);
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
  const MirInst *last = fn_just_made(fn, value);
  MirMode mode = MM_MOVE;
  return last != NULL && mir_result_mode(fn->cx->module, &fn->b.func, last, &mode) && mode == MM_BORROW;
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

/* Walks `insts` back from its end to the instruction that made `value`: 1 when a scope owns it or it is a fresh result,
 * 0 when it was disowned or is a borrow, -1 when the walk did not meet it. */
static int fresh_in(const LowerFn *fn, const MirInstList *insts, MirValue value) {
  for (size_t at = insts->len; at-- > 0;) {
    const MirInst *inst = &insts->ptr[at];
    if (inst->op == MOP_ScopeDisown && inst->nargs == 1 && inst->args[0] == value) {
      return 0;
    }
    if (inst->op == MOP_ScopeOwn && inst->nargs == 1 && inst->args[0] == value) {
      return 1;
    }
    if (inst->res == value) {
      if (inst->op == MOP_OptNone || inst->op == MOP_OptNoneOwned) {
        return 1; /* `none` holds nothing: whoever takes it owns an empty value, so no copy is made */
      }
      MirMode mode = MM_BORROW;
      return mir_result_mode(fn->cx->module, &fn->b.func, inst, &mode) && mode == MM_MOVE;
    }
  }
  return -1;
}

bool fn_fresh_owner(LowerFn *fn, MirValue value) {
  /* Walk back to the instruction that made `value`: a call that wrote its `var` receiver back, or took other
   * values out of their slots, leaves instructions after the result (and its scope.own). An unwind site's test
   * after the result puts the continuation in a new block, so the walk goes on in the block the result is in. */
  int found = fresh_in(fn, &fn->b.func.blocks.ptr[fn->b.cur].insts, value);
  if (found < 0 && fn->site_value == value && fn->site_block != fn->b.cur) {
    found = fresh_in(fn, &fn->b.func.blocks.ptr[fn->site_block].insts, value);
  }
  if (found >= 0) {
    return found != 0;
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

LowerFn fn_begin_reserved(Lower *cx, const MirFunc *reserved) {
  LowerFn fn = {.cx = cx,
                .facts = &cx->program->modules.ptr[0].facts,
                .module_index = 0,
                .file = lower_file(cx, 0),
                .ret = reserved->ret};
  mir_b_init(&fn.b, cx->module, reserved->name, reserved->params, reserved->nparams, reserved->ret);
  fn.b.func.loc = (MirLoc){fn.file, 0, 0, 0};
  (void)fn_scope_begin(&fn);
  fn.nvars = 16;
  fn.vars = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirVar, (size_t)fn.nvars + 1);
  return fn;
}

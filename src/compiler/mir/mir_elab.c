/* compiler/mir/mir_elab.c: drop elaboration: places the scope-exit cleanup of every Raw function (see
 * mir_elab.h). This file reads the scope markers, runs the move-state dataflow and drives the emitter. */
#include "compiler/mir/mir_elab.h"

#include "base/sort.h"

static bool is_raw(const MirFunc *func) {
  for (size_t b = 0; b < func->blocks.len; b++) {
    const MirInstList *insts = &func->blocks.ptr[b].insts;
    for (size_t i = 0; i < insts->len; i++) {
      const MirOp op = (MirOp)insts->ptr[i].op;
      if (op == MOP_ScopeBegin || op == MOP_ScopeOwn || op == MOP_ScopeEnd || op == MOP_ScopeDisown ||
          op == MOP_ScopeUnpin || op == MOP_ScopeMark) {
        return true;
      }
    }
  }
  return false;
}

/* ---- flags ---- */

/* The owners some block entry holds in a state that needs a flag. */
static MirHash flagged_owners(ElCx *cx, const ElState *entry, const bool *has) {
  MirHash maybe = {0};
  for (size_t b = 0; b < cx->f->blocks.len; b++) {
    uint32_t count = 0;
    const ElOwner *odd = has[b] ? el_odd(cx, &entry[b], &count) : NULL;
    for (uint32_t i = 0; odd != NULL && i < count; i++) {
      if (odd[i].st == EL_MAYBE || odd[i].st == EL_CLOSED_OR_MOVED) {
        (void)mh_put(cx->ma, &maybe, odd[i].v, 0);
      }
    }
  }
  return maybe;
}

/* The key of the closed-by-hand flag of each owner a join leaves possibly closed. */
static MirHash closed_keys(ElCx *cx, MirFunc *func, const ElState *entry, const bool *has) {
  MirHash keys = {0};
  for (size_t b = 0; b < func->blocks.len; b++) {
    uint32_t count = 0;
    const ElOwner *odd = has[b] ? el_odd(cx, &entry[b], &count) : NULL;
    for (uint32_t i = 0; odd != NULL && i < count; i++) {
      if ((odd[i].st == EL_MAYBE_CLOSED || odd[i].st == EL_CLOSED_OR_MOVED) && !mh_has(&keys, odd[i].v)) {
        (void)mh_put(cx->ma, &keys, odd[i].v, mir_new_value(func, MIR_BOOL));
      }
    }
  }
  return keys;
}

/* A slot owner refilled after a move, or handed on to another scope, registers a new cleanup entry: the
 * entry a later move cancels travels in a block parameter under a key of its own. */
static MirHash handle_keys(ElCx *cx, MirFunc *func) {
  MirHash keys = {0}, owned_at = {0};
  for (size_t b = 0; b < func->blocks.len; b++) {
    const MirInstList *insts = &func->blocks.ptr[b].insts;
    for (size_t i = 0; i < insts->len; i++) {
      const MirInst *inst = &insts->ptr[i];
      uint64_t seen = 0;
      if (inst->op == MOP_ScopeOwn) {
        (void)mh_get(&owned_at, inst->args[0], &seen);
        (void)mh_put(cx->ma, &owned_at, inst->args[0], seen + 1);
      }
      if (inst->op == MOP_ScopeMark && inst->imm.tag == MI_INT && (inst->imm.i == 2 || inst->imm.i == 3) && !mh_has(&keys, inst->args[0])) {
        (void)mh_put(cx->ma, &keys, inst->args[0], mir_new_value(func, MIR_INT));
      }
    }
  }
  const uint64_t *owners = mh_keys(cx->ma, &owned_at);
  for (uint32_t i = 0; i < owned_at.n; i++) {
    uint64_t seen = 0;
    (void)mh_get(&owned_at, owners[i], &seen);
    if (seen > 1 && el_is_slot_owner(cx, (MirValue)owners[i]) && !mh_has(&keys, owners[i])) {
      (void)mh_put(cx->ma, &keys, owners[i], mir_new_value(func, MIR_INT));
    }
  }
  return keys;
}

static void add_flag_param(ElCx *cx, MirFunc *func, uint32_t block, ElFparams *out, MirValue key, MirTy ty) {
  (void)cx;
  const MirValue param = mir_new_value(func, ty);
  mir_block_param_list_push(&func->blocks.ptr[block].params, (MirBlockParam){param, MM_BORROW});
  mir_idlist_push(&out->key, key);
  mir_idlist_push(&out->param, param);
}

static int64_t owner_by_position(uint8_t *env, const uint8_t *x, const uint8_t *y) {
  (void)env;
  ElOwner a, b;
  __builtin_memcpy(&a, x, sizeof a);
  __builtin_memcpy(&b, y, sizeof b);
  return (int64_t)a.pos - (int64_t)b.pos;
}

/* The owners of `candidates` live on entry to `block`, in definition order. */
static uint32_t live_candidates(ElCx *cx, const ElState *entry, const uint64_t *candidates, uint32_t count,
                                ElOwner *live) {
  uint32_t found = 0;
  for (uint32_t i = 0; i < count; i++) {
    ElOwner owner = {0, (MirValue)candidates[i], 0};
    if (el_position_of(entry, owner.v, &owner.pos) && el_get(entry, owner.v, &owner.st)) {
      live[found++] = owner;
    }
  }
  (void)cx;
  if (found > 1) {
    ms_sort((uint8_t *)live, found, sizeof *live, owner_by_position, NULL);
  }
  return found;
}

/* The flag parameters of every block: one per flagged owner that is live on entry. Only an owner with a
 * flag, a closed flag or a handle key has a parameter, so a block looks at those instead of every owner live
 * on entry. */
static void flag_params(ElCx *cx, MirFunc *func, const ElEm *em, const MirBlock *order, uint32_t norder,
                        const ElState *entry, const bool *has, ElFparams *out) {
  MirHash all = {0};
  const MirHash *sets[3] = {&em->flagged, &em->ckeys, &em->hkeys};
  for (uint32_t s = 0; s < 3; s++) {
    const uint64_t *keys = mh_keys(cx->ma, sets[s]);
    for (uint32_t i = 0; i < sets[s]->n; i++) {
      (void)mh_put(cx->ma, &all, keys[i], 0);
    }
  }
  const uint64_t *candidates = mh_keys(cx->ma, &all);
  ElOwner *live = MS_ARENA_NEW_ARRAY(cx->ma, ElOwner, (size_t)all.n + 1);
  for (uint32_t k = 0; k < norder; k++) {
    const MirBlock block = order[k];
    if (!has[block]) {
      continue;
    }
    const uint32_t count = live_candidates(cx, &entry[block], candidates, all.n, live);
    for (uint32_t i = 0; i < count; i++) {
      uint64_t key = 0;
      if (mh_has(&em->flagged, live[i].v)) {
        add_flag_param(cx, func, block, &out[block], live[i].v, MIR_BOOL);
      }
      if ((live[i].st == EL_MAYBE_CLOSED || live[i].st == EL_CLOSED_OR_MOVED) && mh_get(&em->ckeys, live[i].v, &key)) {
        add_flag_param(cx, func, block, &out[block], (MirValue)key, MIR_BOOL);
      }
      if (mh_get(&em->hkeys, live[i].v, &key)) {
        add_flag_param(cx, func, block, &out[block], (MirValue)key, MIR_INT);
      }
    }
  }
}

/* ---- one function ---- */

/* The values a `scope.disown` names. */
static MirHash disowned_values(ElCx *cx, const MirFunc *func) {
  MirHash set = {0};
  for (size_t b = 0; b < func->blocks.len; b++) {
    const MirInstList *insts = &func->blocks.ptr[b].insts;
    for (size_t i = 0; i < insts->len; i++) {
      if (insts->ptr[i].op == MOP_ScopeDisown || insts->ptr[i].op == MOP_ScopeUnpin) {
        (void)mh_put(cx->ma, &set, insts->ptr[i].args[0], 0);
      }
    }
  }
  return set;
}

/* The move state on entry to every block. A flagged owner that is disowned before the op consuming it needs
 * the moved state, so the exits after the move do not release it again. */
static bool block_states(ElCx *cx, const MirBlock *order, uint32_t norder, ElState *entry, bool *has,
                         MirHash *flagged) {
  MirHash seen = {0};
  for (size_t b = 0; b < cx->f->blocks.len; b++) {
    uint32_t nparams = 0;
    const MirValue *params = el_own_params(cx, (uint32_t)b, &nparams);
    for (uint32_t i = 0; i < nparams; i++) {
      (void)mh_put(cx->ma, &cx->param_owned, params[i], 0);
    }
    const MirInstList *insts = &cx->f->blocks.ptr[b].insts;
    for (size_t i = 0; i < insts->len; i++) {
      if (insts->ptr[i].op == MOP_ScopeOwn && !mh_put(cx->ma, &seen, insts->ptr[i].args[0], 0)) {
        (void)mh_put(cx->ma, &cx->reowned, insts->ptr[i].args[0], 0);
      }
    }
  }
  if (!el_analyze(cx, order, norder, entry, has)) {
    return false;
  }
  MirHash maybe = flagged_owners(cx, entry, has);
  const MirHash disowned = disowned_values(cx, cx->f);
  const uint64_t *keys = mh_keys(cx->ma, &maybe);
  for (uint32_t i = 0; i < maybe.n; i++) {
    if (mh_has(&disowned, keys[i])) {
      (void)mh_put(cx->ma, &cx->disown_moves, keys[i], 0);
    }
  }
  if (cx->disown_moves.n > 0) {
    if (!el_analyze(cx, order, norder, entry, has)) {
      return false;
    }
    maybe = flagged_owners(cx, entry, has);
  }
  *flagged = maybe;
  return true;
}

static bool counts_depth(const MirFunc *func) {
  for (size_t b = 0; b < func->blocks.len; b++) {
    const MirInstList *insts = &func->blocks.ptr[b].insts;
    for (size_t i = 0; i < insts->len; i++) {
      if (insts->ptr[i].op == MOP_DepthEnter) {
        return true;
      }
    }
  }
  return false;
}

static void free_fparams(ElFparams *fparams, size_t count) {
  for (size_t i = 0; i < count; i++) {
    mir_idlist_free(&fparams[i].key);
    mir_idlist_free(&fparams[i].param);
  }
}

static bool function_blocks(ElCx *cx, MirFunc *func, ElEm *em) {
  MirBlock *order = NULL;
  const uint32_t norder = mir_rpo(cx->ma, func, &order);
  const size_t nblocks = func->blocks.len;
  ElState *entry = MS_ARENA_NEW_ARRAY(cx->ma, ElState, nblocks + 1);
  bool *has = MS_ARENA_NEW_ARRAY(cx->ma, bool, nblocks + 1);
  if (!block_states(cx, order, norder, entry, has, &em->flagged)) {
    return false;
  }
  em->ckeys = closed_keys(cx, func, entry, has);
  em->hkeys = handle_keys(cx, func);
  ElFparams *fparams = MS_ARENA_NEW_ARRAY(cx->ma, ElFparams, nblocks + 1);
  flag_params(cx, func, em, order, norder, entry, has, fparams);
  em->counts_depth = counts_depth(func);
  bool ok = true;
  for (uint32_t k = 0; k < norder && ok; k++) {
    ok = !has[order[k]] || el_emit_block(em, order[k], &entry[order[k]], fparams);
  }
  free_fparams(fparams, nblocks + 1);
  return ok;
}

static bool elaborate_function(ElCx *cx, MirModule *module, MirFunc *func) {
  cx->f = func;
  el_tags(cx);
  ElEm em = {.cx = cx, .m = module, .f = func, .pending = MIR_NONE};
  const bool ok = function_blocks(cx, func, &em);
  if (ok) {
    el_prune_undominated_drops(cx);
  }
  el_tags_free(cx);
  return ok;
}

/* ---- the pass ---- */

/* `scratch` holds what the rewrite of one function needs and is reset on return. */
static bool run_one(MirModule *module, uint32_t index, const ElCx *shared, MsArena *scratch, MsStrBuild *error) {
  MsStrBuild message = ms_strbuild_new();
  ElCx cx = *shared;
  cx.ma = scratch;
  cx.m = module;
  cx.error = &message;
  /* The function is out of the module while it is rewritten; a stand-in with its signature stays, so a
   * recursive call still reads which arguments the callee consumes. */
  MirFunc func = module->funcs.ptr[index];
  MirFunc stand_in = mir_func_stand_in(module, &func);
  module->funcs.ptr[index] = stand_in;
  const bool ok = elaborate_function(&cx, module, &func);
  module->funcs.ptr[index] = func;
  mir_func_release(&stand_in);
  if (!ok) {
    ms_strbuild_append(error, ms_names_span(&module->names, func.name));
    ms_strbuild_append_text(error, ": ");
    ms_strbuild_append(error, ms_strbuild_span(&message));
  }
  ms_strbuild_free(&message);
  ms_arena_reset(scratch);
  return ok;
}

/* Declares the runtime entries scope closing calls. */
static void declare_runtime(MirModule *module, ElCx *shared) {
  const MirTy one = MIR_INT;
  shared->discard = mir_extern_get(module, ms_span_of_text("msrt_cleanup_discard"), &one, 1, MIR_VOID, true,
                                   MR_CLEANUP_DISCARD);
  shared->cancel = mir_extern_get(module, ms_span_of_text("msrt_cleanup_cancel"), &one, 1, MIR_VOID, true, MR_CLEANUP_CANCEL);
  shared->shield_enter = mir_extern_get(module, ms_span_of_text("msrt_shield_enter"), NULL, 0, MIR_VOID, true,
                                        MR_SHIELD_ENTER);
  shared->shield_exit = mir_extern_get(module, ms_span_of_text("msrt_shield_exit"), NULL, 0, MIR_VOID, true,
                                       MR_SHIELD_EXIT);
}

/* Whether any function is Raw, and whether a Raw function closes by hand or by a closing owner. */
static bool scan(const MirModule *module, bool *closes) {
  bool any_raw = false;
  for (size_t index = 0; index < module->funcs.len; index++) {
    const MirFunc *func = &module->funcs.ptr[index];
    const bool raw = is_raw(func);
    any_raw = any_raw || raw;
    for (size_t b = 0; raw && b < func->blocks.len; b++) {
      const MirInstList *insts = &func->blocks.ptr[b].insts;
      for (size_t i = 0; i < insts->len; i++) {
        *closes = *closes || (insts->ptr[i].op == MOP_ScopeOwn && insts->ptr[i].imm.b >= 1);
      }
    }
  }
  return any_raw;
}

bool mir_elaborate(MirModule *module, MsStrBuild *error) {
  ElCx shared = {.close = module->close,
                 .discard = MIR_NONE,
                 .cancel = MIR_NONE,
                 .shield_enter = MIR_NONE,
                 .shield_exit = MIR_NONE};
  bool closes = false;
  if (!scan(module, &closes)) {
    return true;
  }
  if (closes) {
    declare_runtime(module, &shared);
  }
  MsArena scratch = ms_arena_new();
  const size_t count = module->funcs.len;
  bool ok = true;
  for (size_t index = 0; index < count && ok; index++) {
    ok = !is_raw(&module->funcs.ptr[index]) || run_one(module, (uint32_t)index, &shared, &scratch, error);
  }
  ms_arena_free(&scratch);
  /* The helper references are consumed: later passes renumber functions. */
  for (size_t index = 0; ok && index < module->funcs.len; index++) {
    module->funcs.ptr[index].has_slot_result = false;
    module->funcs.ptr[index].has_close_exit = false;
  }
  return ok;
}

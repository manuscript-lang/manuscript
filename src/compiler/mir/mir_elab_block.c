/* compiler/mir/mir_elab_block.c: drop elaboration, blocks: rebuilds each block from its entry state,
 * threading drop flags and cleanup handles through block parameters. */
#include "compiler/mir/mir_elab.h"

/* The start of a block: an owner that is surely open or surely closed by hand here has a constant flag. */
static void known_flags(ElEm *em, uint32_t block, const ElState *state) {
  const uint64_t *owners = mh_keys(em->cx->ma, &em->ckeys);
  const uint32_t count = em->ckeys.n;
  for (uint32_t i = 0; i < count; i++) {
    uint64_t key = 0;
    ElSt kind = 0;
    if (!mh_get(&em->ckeys, owners[i], &key) || !el_get(state, (MirValue)owners[i], &kind) ||
        mh_has(&em->flags, key) || (kind != EL_LIVE && kind != EL_CLOSED)) {
      continue;
    }
    (void)mh_put(em->cx->ma, &em->flags, key, em_bconst(em, block, kind == EL_CLOSED));
  }
}

/* `scope.own`: the owner joins its scope; a closing owner registers its cleanup entry. */
static bool own_marker(ElEm *em, uint32_t cur, ElState *state, const MirInst *inst, MirValue value) {
  ElCx *cx = em->cx;
  ElSt was = EL_LIVE;
  const bool had = el_get(state, value, &was);
  if (!el_apply(cx, state, inst)) {
    return false;
  }
  MirValue key = MIR_NONE, handle = MIR_NONE;
  (void)em_flag_of(&em->hkeys, value, &key);
  if (had && was == EL_MOVED && el_is_slot_owner(cx, value)) {
    if (!em_reregister(em, cur, value, key, &handle)) {
      return false;
    }
    em_set_held(em, cur, value);
    return true;
  }
  if (cx->tag_kind[value] >= 1 && !em_register(em, cur, value)) {
    return false;
  }
  if (mh_has(&em->flagged, value) && el_is_slot_owner(cx, value)) {
    (void)mh_put(cx->ma, &em->flags, value, em_bconst(em, cur, true));
  }
  if (em_flag_of(&em->ckeys, value, &handle)) {
    (void)mh_put(cx->ma, &em->flags, handle, em_bconst(em, cur, false));
  }
  if (key != MIR_NONE && em_flag_of(&em->handles, value, &handle)) {
    (void)mh_put(cx->ma, &em->flags, key, handle);
  }
  return true;
}

static bool disown_marker(ElEm *em, uint32_t cur, ElState *state, const MirInst *inst, MirValue value) {
  ElSt was = EL_LIVE;
  const bool had = el_get(state, value, &was);
  if (!el_apply(em->cx, state, inst)) {
    return false;
  }
  if (el_is_slot_owner(em->cx, value) && had && (was == EL_LIVE || was == EL_CLOSED)) {
    em_cancel(em, cur, value);
  }
  return true;
}

static bool mark_marker(ElEm *em, uint32_t *cur, ElState *state, const MirInst *inst, MirValue value) {
  /* Kind 2 stores a new value in a slot (what it held closes); kind 3 puts back the value a lend took out, so only an
   * owner the lend moved out of is registered again. */
  const bool lend = inst->imm.i == 3;
  const bool refill = inst->imm.i == 2 || lend;
  ElSt was = EL_LIVE;
  MirValue key = MIR_NONE;
  const bool had = el_get(state, value, &was);
  const bool moved = had && (was == EL_MOVED || was == EL_MAYBE || was == EL_CLOSED_OR_MOVED);
  if (!el_apply(em->cx, state, inst) || (refill && (!lend || moved) && !em_refill(em, cur, value, had, was))) {
    return false;
  }
  if (em_flag_of(&em->ckeys, value, &key)) {
    (void)mh_put(em->cx->ma, &em->flags, key, em_bconst(em, *cur, !refill && inst->imm.i == 1));
  }
  return true;
}

/* The marker instructions of a Raw block; sets `*done` when `inst` was one. */
static bool marker(ElEm *em, uint32_t *cur, ElState *state, const MirInst *inst, bool *done) {
  *done = true;
  const MirValue value = inst->nargs > 0 ? inst->args[0] : MIR_NONE;
  switch ((MirOp)inst->op) {
  case MOP_ScopeDisown:
  case MOP_ScopeUnpin:
    return disown_marker(em, *cur, state, inst, value);
  case MOP_ScopeMark:
    return mark_marker(em, cur, state, inst, value);
  case MOP_ScopeBegin:
    return true;
  case MOP_ScopeOwn:
    return own_marker(em, *cur, state, inst, value);
  case MOP_ScopeEnd:
    return em_exit(em, cur, state, inst->imm.a);
  default:
    *done = false;
    return true;
  }
}

/* A real instruction: its consuming operands retire cleanup entries, its owned result is born. */
static bool plain(ElEm *em, uint32_t cur, ElState *state, MirInst *inst, MirValue returned) {
  MirMode *modes = MS_ARENA_NEW_ARRAY(em->cx->ma, MirMode, (size_t)inst->nargs + 1);
  mir_arg_modes(em->m, em->f, inst, modes);
  for (uint32_t k = 0; k < inst->nargs; k++) {
    if (modes[k] == MM_MOVE && mir_needs_drop(em->m, mir_value_ty(em->f, inst->args[k]))) {
      inst->args[k] = em_move_arg(em, cur, inst->args[k]);
    }
  }
  if (!el_apply(em->cx, state, inst)) {
    return false;
  }
  if (inst->res != MIR_NONE && inst->res == returned) {
    em->pending = returned;
  }
  MirMode result = MM_BORROW;
  const bool owned = inst->res != MIR_NONE && mir_result_mode(em->m, em->f, inst, &result) &&
                     result == MM_MOVE && mir_needs_drop(em->m, mir_value_ty(em->f, inst->res));
  mir_inst_list_push(&em->f->blocks.ptr[cur].insts, *inst);
  if (owned) {
    em_birth(em, cur, inst->res);
  }
  return true;
}

/* The value the block returns is pending for a close only once it exists: one the block defines is not
 * pending for a scope that ends before that (a loop's, say). */
static MirValue pending_return(const MirBlockData *old) {
  const MirValue returned = old->term.kind == MT_RET ? old->term.value : MIR_NONE;
  for (size_t i = 0; i < old->insts.len && returned != MIR_NONE; i++) {
    if (old->insts.ptr[i].res == returned) {
      return MIR_NONE;
    }
  }
  return returned;
}

static bool emit_insts(ElEm *em, uint32_t block, const MirBlockData *old, ElState *state, MirValue returned,
                       uint32_t *cur) {
  size_t first = 0;
  /* The stack check stays the first instruction of the entry block. */
  if (old->insts.len > 0 && old->insts.ptr[0].op == MOP_DepthEnter) {
    mir_inst_list_push(&em->f->blocks.ptr[*cur].insts, old->insts.ptr[0]);
    first = 1;
  }
  known_flags(em, block, state);
  uint32_t nparams = 0;
  const MirValue *params = el_own_params(em->cx, block, &nparams);
  for (uint32_t i = 0; i < nparams; i++) {
    el_push(em->cx, state, params[i], EL_LIVE);
    em_birth(em, *cur, params[i]);
  }
  for (size_t i = first; i < old->insts.len; i++) {
    MirInst inst = old->insts.ptr[i];
    bool done = false;
    if (!marker(em, cur, state, &inst, &done) || (!done && !plain(em, *cur, state, &inst, returned))) {
      return false;
    }
  }
  return true;
}

/* Emits one block from its entry state; the rest of the function follows from it. */
bool el_emit_block(ElEm *em, uint32_t block, const ElState *entry, const ElFparams *fparams) {
  MirFunc *func = em->f;
  MirBlockData old = func->blocks.ptr[block];
  func->blocks.ptr[block] = mir_block_empty();
  func->blocks.ptr[block].params = old.params;
  func->blocks.ptr[block].term_loc = MIR_LOC_NONE;
  em->flags = (MirHash){0};
  for (size_t i = 0; i < fparams[block].key.len; i++) {
    (void)mh_put(em->cx->ma, &em->flags, fparams[block].key.ptr[i], fparams[block].param.ptr[i]);
  }
  const MirValue returned = pending_return(&old);
  em->pending = returned;
  ElState state = *entry;
  uint32_t cur = block;
  /* A value the block defines becomes pending once its instruction is emitted. */
  const MirValue defined = old.term.kind == MT_RET ? old.term.value : MIR_NONE;
  bool ok = emit_insts(em, block, &old, &state, defined, &cur);
  if (ok && returned != MIR_NONE) {
    ok = !mh_has(&em->flagged, returned) || el_fail(em->cx, "a drop-flagged owner is returned directly");
    em_discard(em, cur, returned);
  }
  MirTerm term = old.term;
  ok = ok && em_edges(em, cur, &term, fparams);
  func->blocks.ptr[cur].term = term;
  func->blocks.ptr[cur].term_loc = old.term_loc;
  mir_inst_list_free(&old.insts);
  return ok;
}

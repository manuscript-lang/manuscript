/* compiler/mir/mir_elab_edge.c: drop elaboration, edges: the arguments an edge passes (consumed owners
 * retire their cleanup entry, flags follow) and the trampoline an edge needs when its moves need code. */
#include "compiler/mir/mir_elab.h"

/* The flag of the owner `owner` on an edge into a block with a flag parameter for it. */
static bool edge_flag(ElEm *em, uint32_t at, MirValue owner, const MirValue *moved, uint32_t nmoved,
                      MirValue *flag) {
  bool was_moved = false;
  for (uint32_t i = 0; i < nmoved; i++) {
    was_moved = was_moved || moved[i] == owner;
  }
  if (was_moved && mh_has(&em->flagged, owner)) {
    *flag = em_bconst(em, at, false);
    return true;
  }
  if (em_flag_of(&em->flags, owner, flag)) {
    return true;
  }
  /* The entry of an owner that no path has refilled yet is its first. */
  MirValue first = MIR_NONE;
  const uint64_t *keys = mh_keys(em->cx->ma, &em->hkeys);
  for (uint32_t i = 0; i < em->hkeys.n && first == MIR_NONE; i++) {
    uint64_t key = 0;
    if (mh_get(&em->hkeys, keys[i], &key) && key == owner) {
      first = (MirValue)keys[i];
    }
  }
  if (first != MIR_NONE && em_flag_of(&em->handles, first, flag)) {
    return true;
  }
  /* An owner this path no longer holds. */
  if (mh_has(&em->flagged, owner)) {
    *flag = em_bconst(em, at, false);
    return true;
  }
  return el_fail(em->cx, "no drop flag for %%%u", owner);
}

/* What one edge needs: the arguments for the destination (the flag arguments appended) and, when the edge
 * moves owners that need per-edge instructions, a trampoline body. */
typedef struct EmEdge {
  MirValue *args;
  uint32_t nargs;
  bool trampoline;
  MirInstList insts;
} EmEdge;

static bool is_flag_param(const ElFparams *fparams, MirValue param) {
  for (size_t i = 0; i < fparams->param.len; i++) {
    if (fparams->param.ptr[i] == param) {
      return true;
    }
  }
  return false;
}

/* The arguments of `target` that a moving parameter takes; `*per_edge` is set when one needs code. */
static uint32_t moved_args(ElEm *em, const MirTarget *target, const ElFparams *fp, const MirValue *args,
                           MirValue *moved, bool *per_edge) {
  const MirBlockData *dest = &em->f->blocks.ptr[target->block];
  uint32_t nmoved = 0, used = 0; /* used: the destination parameters that are not flag parameters */
  for (size_t p = 0; p < dest->params.len && used < target->nargs; p++) {
    if (is_flag_param(fp, dest->params.ptr[p].value)) {
      continue;
    }
    const MirValue arg = args[used++];
    if (dest->params.ptr[p].mode == MM_MOVE && mir_needs_drop(em->m, mir_value_ty(em->f, arg))) {
      moved[nmoved++] = arg;
      *per_edge = *per_edge || mh_has(&em->handles, arg) || mh_has(&em->flagged, arg);
    }
  }
  return nmoved;
}

static bool edge_build(ElEm *em, uint32_t cur, const ElState *state, const MirTarget *target, const ElFparams *fparams,
                       EmEdge *out) {
  const MirBlockData *dest = &em->f->blocks.ptr[target->block];
  const ElFparams *fp = &fparams[target->block];
  MirValue *args = MS_ARENA_NEW_ARRAY(&em->m->arena, MirValue, (size_t)target->nargs + fp->key.len + 1);
  if (target->nargs > 0) {
    __builtin_memcpy(args, target->args, sizeof(MirValue) * target->nargs);
  }
  MirValue *moved = MS_ARENA_NEW_ARRAY(em->cx->ma, MirValue, (size_t)target->nargs + 1);
  bool per_edge = false;
  const uint32_t nmoved = moved_args(em, target, fp, args, moved, &per_edge);
  /* A loop head's owning parameter is born again on every trip: the value of the trip that ends here, when a path
   * left it flagged, is settled before the edge, or nothing would ever release it. */
  uint32_t nredefined = 0;
  const MirValue *redefined = el_own_params(em->cx, target->block, &nredefined);
  for (uint32_t i = 0; i < nredefined && !per_edge; i++) {
    MirValue old_flag = MIR_NONE;
    per_edge = mh_has(&em->flagged, redefined[i]) && em_flag_of(&em->flags, redefined[i], &old_flag);
  }
  /* A trampoline body is built in a scratch block so the instructions land in order. */
  const uint32_t at = per_edge ? em_new_block(em) : cur;
  uint32_t used = 0;
  for (size_t p = 0; p < dest->params.len && used < target->nargs; p++) {
    if (is_flag_param(fp, dest->params.ptr[p].value)) {
      continue;
    }
    const MirValue arg = args[used];
    ElSt kind = 0;
    if (dest->params.ptr[p].mode == MM_MOVE && mir_needs_drop(em->m, mir_value_ty(em->f, arg)) &&
        el_get(state, arg, &kind) && kind == EL_MOVED && !mh_has(&em->cx->disown_moves, arg)) {
      /* The value left earlier and the parameter is moved with it: nothing is passed that anything could close. */
      args[used] = em_push(em, at, MOP_Undef, NULL, 0, mir_imm_none(), mir_value_ty(em->f, arg));
    } else if (dest->params.ptr[p].mode == MM_MOVE && mir_needs_drop(em->m, mir_value_ty(em->f, arg))) {
      args[used] = em_move_arg(em, at, arg);
    }
    used++;
  }
  for (uint32_t i = 0; i < nredefined; i++) {
    MirValue old_flag = MIR_NONE;
    if (mh_has(&em->flagged, redefined[i]) && em_flag_of(&em->flags, redefined[i], &old_flag)) {
      const MirValue settle[2] = {old_flag, redefined[i]};
      em_push(em, at, MOP_DropIf, settle, 2, mir_imm_none(), EM_NO_RESULT);
    }
  }
  uint32_t nargs = target->nargs;
  for (size_t i = 0; i < fp->key.len; i++) {
    if (!edge_flag(em, at, fp->key.ptr[i], moved, nmoved, &args[nargs])) {
      return false;
    }
    nargs++;
  }
  *out = (EmEdge){.args = args, .nargs = nargs, .trampoline = per_edge};
  if (per_edge) {
    out->insts = em->f->blocks.ptr[at].insts;
    mir_block_list_truncate(&em->f->blocks, em->f->blocks.len - 1);
  }
  return true;
}

/* Points `target` at a new trampoline block that branches on to the old destination. */
static MirBlock make_trampoline(ElEm *em, MirTarget *target, const EmEdge *edge) {
  const MirBlock tramp = em_new_block(em);
  const MirBlock dest = target->block;
  target->block = tramp;
  target->args = NULL;
  target->nargs = 0;
  em_br(em, tramp, dest, edge->args, edge->nargs);
  return tramp;
}

/* Each edge: the consumed owners retire their cleanup entry and the flags follow. */
bool em_edges(ElEm *em, uint32_t cur, const ElState *state, MirTerm *term, const ElFparams *fparams) {
  const uint32_t ntargets = mir_term_ntargets(term);
  MirBlock *tramps = MS_ARENA_NEW_ARRAY(em->cx->ma, MirBlock, (size_t)ntargets + 1);
  EmEdge *edges = MS_ARENA_NEW_ARRAY(em->cx->ma, EmEdge, (size_t)ntargets + 1);
  for (uint32_t i = 0; i < ntargets; i++) {
    MirTarget *target = mir_term_target(term, i);
    if (!edge_build(em, cur, state, target, fparams, &edges[i])) {
      return false;
    }
    if (edges[i].trampoline) {
      tramps[i] = make_trampoline(em, target, &edges[i]);
    } else {
      target->args = edges[i].args;
      target->nargs = edges[i].nargs;
    }
  }
  for (uint32_t i = 0; i < ntargets; i++) {
    if (edges[i].trampoline) {
      em->f->blocks.ptr[tramps[i]].insts = edges[i].insts;
    }
  }
  return true;
}

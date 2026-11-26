/* compiler/mir/mir_elab_chain.c: drop elaboration, shared unwind drops. Every call that can park or fault leaves the
 * function through an exit that drops what is owned there, so a function of n calls and n owners would hold n * n
 * drops. The owners an exit drops are the owners of the exit before it, plus the few made since: the exits drop them
 * through one chain of blocks, each dropping one owner and continuing in the block of the next older one, so a
 * function holds one block per owner however many exits reach it. */
#include "compiler/mir/mir_elab.h"

bool el_exit_tail(const ElEm *em, const MirBlockData *old, size_t at, ElTail *tail) {
  const MirInstList *insts = &old->insts;
  const size_t rest = insts->len - at - 1;
  if (!old->cold || old->term.kind != MT_RET || rest == 0 || rest > 2) {
    return false;
  }
  const MirInst *resume = &insts->ptr[at + 1];
  if (resume->op != MOP_CallRt || resume->nargs != 0 || resume->imm.tag != MI_EXT) {
    return false;
  }
  *tail = (ElTail){.resume = resume->imm, .loc = old->term_loc};
  if (rest == 1) {
    return old->term.value == MIR_NONE;
  }
  const MirInst *undef = &insts->ptr[at + 2];
  if (undef->op != MOP_Undef || undef->res == MIR_NONE || old->term.value != undef->res) {
    return false;
  }
  tail->has_undef = true;
  tail->undef_imm = undef->imm;
  tail->undef_ty = mir_value_ty(em->f, undef->res);
  return true;
}

static bool same_tail(const ElTail *x, const ElTail *y) {
  return x->resume.a == y->resume.a && x->has_undef == y->has_undef &&
         (!x->has_undef || (x->undef_ty == y->undef_ty && x->undef_imm.tag == y->undef_imm.tag &&
                            x->undef_imm.i == y->undef_imm.i));
}

static MirBlock new_cold_block(ElEm *em) {
  const MirBlock block = em_new_block(em);
  em->f->blocks.ptr[block].cold = true;
  return block;
}

/* The block that runs the tail: the end of every chain. */
static MirBlock chain_root(ElEm *em) {
  if (em->root != MIR_NONE) {
    return same_tail(&em->root_tail, em->tail) ? em->root : MIR_NONE;
  }
  const ElTail *tail = em->tail;
  const MirBlock root = new_cold_block(em);
  em_push(em, root, MOP_CallRt, NULL, 0, tail->resume, MIR_VOID);
  em->f->blocks.ptr[root].insts.ptr[0].loc = tail->loc;
  MirValue result = MIR_NONE;
  if (tail->has_undef) {
    result = em_push(em, root, MOP_Undef, NULL, 0, tail->undef_imm, tail->undef_ty);
    em->f->blocks.ptr[root].insts.ptr[1].loc = tail->loc;
  }
  MirTerm *term = &em->f->blocks.ptr[root].term;
  *term = (MirTerm){.kind = MT_RET, .value = result};
  em->f->blocks.ptr[root].term_loc = tail->loc;
  em->root = root;
  em->root_tail = *tail;
  return root;
}

/* The block that drops `owner` and continues in `next`. */
static MirBlock chain_link(ElEm *em, MirBlock next, MirValue owner) {
  const uint64_t key = (uint64_t)next << 32 | owner;
  uint64_t found = 0;
  if (mh_get(&em->chain, key, &found)) {
    return (MirBlock)found;
  }
  const MirBlock drop = new_cold_block(em);
  em_push(em, drop, MOP_Drop, &owner, 1, mir_imm_none(), EM_NO_RESULT);
  em->f->blocks.ptr[drop].insts.ptr[0].loc = em->tail->loc;
  em_br(em, drop, next, NULL, 0);
  em->f->blocks.ptr[drop].term_loc = em->tail->loc;
  (void)mh_put(em->cx->ma, &em->chain, key, drop);
  return drop;
}

static void leave_by(ElEm *em, uint32_t at, MirBlock chain) {
  em_br(em, at, chain, NULL, 0);
  em->f->blocks.ptr[at].term_loc = em->tail->loc;
  em->exited = true;
}

bool el_share_drops(ElEm *em, uint32_t at, const MirValue *owners, uint32_t count) {
  MirBlock next = chain_root(em);
  if (next == MIR_NONE) {
    return false;
  }
  for (uint32_t i = count; i-- > 0;) {
    next = chain_link(em, next, owners[i]);
  }
  leave_by(em, at, next);
  return true;
}

bool el_share_list(ElEm *em, uint32_t at, ElNode *tip) {
  const MirBlock root = chain_root(em);
  if (root == MIR_NONE) {
    return false;
  }
  uint32_t fresh = 0; /* the newest owners no chain holds yet */
  const ElNode *base = tip;
  while (base != NULL && base->block == MIR_NONE) {
    if (base->bad || mh_has(&em->flagged, base->v)) {
      return false;
    }
    fresh++;
    base = base->next;
  }
  if (fresh > 0) {
    ElNode **nodes = MS_ARENA_NEW_ARRAY(em->cx->ma, ElNode *, (size_t)fresh + 1);
    ElNode *node = tip;
    for (uint32_t i = fresh; i-- > 0; node = (ElNode *)(uintptr_t)node->next) {
      nodes[i] = node;
    }
    MirBlock next = base != NULL ? base->block : root;
    for (uint32_t i = 0; i < fresh; i++) {
      next = chain_link(em, next, nodes[i]->v);
      nodes[i]->block = next;
    }
  }
  leave_by(em, at, tip->block);
  return true;
}

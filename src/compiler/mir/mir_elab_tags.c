/* compiler/mir/mir_elab_tags.c: what a Raw function's scope markers say: each owner's scope and kind, and
 * each scope's parent. */
#include "compiler/mir/mir_elab.h"

static void list_remove(MirIdList *list, MirValue value) {
  size_t kept = 0;
  for (size_t index = 0; index < list->len; index++) {
    if (list->ptr[index] != value) {
      list->ptr[kept++] = list->ptr[index];
    }
  }
  mir_idlist_truncate(list, kept);
}

static bool scope_op(const MirInst *inst) {
  return inst->op == MOP_ScopeBegin || inst->op == MOP_ScopeOwn || inst->op == MOP_ScopeEnd;
}

/* Sizes the per-scope tables and reads each scope's parent from its `scope.begin`. */
static void read_scopes(ElCx *cx, const MirFunc *func) {
  uint32_t top = 0;
  for (size_t b = 0; b < func->blocks.len; b++) {
    const MirInstList *insts = &func->blocks.ptr[b].insts;
    for (size_t i = 0; i < insts->len; i++) {
      const MirInst *inst = &insts->ptr[i];
      top = scope_op(inst) && inst->imm.a + 1 > top ? inst->imm.a + 1 : top;
    }
  }
  cx->nscopes = top;
  cx->owners = MS_ARENA_NEW_ARRAY(cx->ma, MirIdList, (size_t)top + 1);
  cx->parent = MS_ARENA_NEW_ARRAY(cx->ma, int64_t, (size_t)top + 1);
  cx->has_parent = MS_ARENA_NEW_ARRAY(cx->ma, bool, (size_t)top + 1);
  for (size_t b = 0; b < func->blocks.len; b++) {
    const MirInstList *insts = &func->blocks.ptr[b].insts;
    for (size_t i = 0; i < insts->len; i++) {
      const MirInst *inst = &insts->ptr[i];
      if (inst->op == MOP_ScopeBegin) {
        cx->parent[inst->imm.a] = (int64_t)inst->imm.b - 1;
        cx->has_parent[inst->imm.a] = true;
      }
    }
  }
}

/* Frees the owner lists of a function's scopes. */
void el_tags_free(ElCx *cx) {
  for (uint32_t scope = 0; scope < cx->nscopes; scope++) {
    mir_idlist_free(&cx->owners[scope]);
  }
}

/* Whether scope `outer` encloses scope `inner`. */
static bool is_ancestor(const ElCx *cx, int64_t outer, int64_t inner) {
  int64_t current = (uint64_t)inner < cx->nscopes && cx->has_parent[inner] ? cx->parent[inner] : -1;
  while (current >= 0) {
    if (current == outer) {
      return true;
    }
    current = (uint64_t)current < cx->nscopes && cx->has_parent[current] ? cx->parent[current] : -1;
  }
  return false;
}

static bool dominates(const MirBlock *idom, MirBlock def, MirBlock at) {
  for (;;) {
    if (at == def) {
      return true;
    }
    if (at == 0 || idom[at] == MIR_NONE || idom[at] == at) {
      return false;
    }
    at = idom[at];
  }
}

static MirBlock defining_block(const MirFunc *func, MirValue value) {
  for (size_t b = 0; b < func->blocks.len; b++) {
    const MirBlockData *block = &func->blocks.ptr[b];
    for (size_t i = 0; i < block->params.len; i++) {
      if (block->params.ptr[i].value == value) {
        return (MirBlock)b;
      }
    }
    for (size_t i = 0; i < block->insts.len; i++) {
      if (block->insts.ptr[i].res == value) {
        return (MirBlock)b;
      }
    }
  }
  return MIR_NONE;
}

static bool block_ends_scope(const MirBlockData *block, int64_t scope) {
  for (size_t i = 0; i < block->insts.len; i++) {
    if (block->insts.ptr[i].op == MOP_ScopeEnd && (int64_t)block->insts.ptr[i].imm.a == scope) {
      return true;
    }
  }
  return false;
}

/* Whether the definition of `value` dominates every block that ends `scope`, so the scope can still hold it
 * there on every path. `*idom` is computed on first use. */
static bool defined_before_every_end(ElCx *cx, const MirBlock **idom, MirValue value, int64_t scope) {
  const MirFunc *func = cx->f;
  const MirBlock def = defining_block(func, value);
  if (def == MIR_NONE) {
    return true;
  }
  if (*idom == NULL) {
    MirBlock *order = NULL;
    const uint32_t count = mir_rpo(cx->ma, func, &order);
    const MirPreds preds = mir_preds(cx->ma, func);
    *idom = mir_dominators(cx->ma, func, order, count, &preds);
  }
  for (size_t b = 0; b < func->blocks.len; b++) {
    if (block_ends_scope(&func->blocks.ptr[b], scope) && !dominates(*idom, def, (MirBlock)b)) {
      return false;
    }
  }
  return true;
}

/* `scope.own S K v`: tags `v` with its scope and kind. A value an inner scope owns again (a statement's
 * temporary holding a moved local) stays the outer scope's: the path that never reaches the inner scope
 * still holds it there, and the inner scope's end finds it moved. That holds only while the outer scope can
 * still hold it at its own end: a value defined inside a branch and handed to a binding there
 * (`var kept = outer`) belongs to the inner scope, which must drop it where the branch ends. */
static void tag_owner(ElCx *cx, const MirBlock **idom, const MirBits *disowned, const MirInst *inst) {
  const MirValue value = inst->args[0];
  const int64_t scope = inst->imm.a, kind = inst->imm.b;
  if (el_tagged(cx, value)) {
    const int64_t old = cx->tag_scope[value];
    if (old != scope && is_ancestor(cx, old, scope) &&
        (!mir_bits_test(disowned, value) || defined_before_every_end(cx, idom, value, old))) {
      return;
    }
    /* A value owned again by a later scope leaves the earlier scope's list. */
    list_remove(&cx->owners[old], value);
  }
  cx->tag_scope[value] = scope;
  cx->tag_kind[value] = kind;
  mir_idlist_push(&cx->owners[scope], value);
}

/* Whether `value` is disowned in block `block` or in the blocks that lead to it without a join. */
static bool disowned_before(const ElCx *cx, const MirPreds *preds, MirBits *seen, MirBlock block,
                            MirValue value) {
  const MirFunc *func = cx->f;
  __builtin_memset(seen->words, 0, sizeof(uint64_t) * (((size_t)seen->nbits + 63) / 64));
  MirBlock current = block;
  while (!mir_bits_test(seen, current)) {
    mir_bits_set(seen, current);
    const MirInstList *insts = &func->blocks.ptr[current].insts;
    for (size_t i = 0; i < insts->len; i++) {
      if (insts->ptr[i].op == MOP_ScopeDisown && insts->ptr[i].args[0] == value) {
        return true;
      }
    }
    if (mir_preds_count(preds, current) != 1) {
      return false;
    }
    current = mir_pred(preds, current, 0);
  }
  return false;
}

/* Tags the block parameter `param` fed by `arg` along an edge out of `block`; whether it was new. */
static bool tag_param(ElCx *cx, const MirPreds *preds, MirBits *seen, MirBlock block, const MirBlockParam *param,
                      MirValue arg) {
  /* A disowned value left its scope: the parameter it feeds is the new owner's. The disown may sit in a
   * block this one follows without a join. */
  if (param->mode != MM_MOVE || !el_tagged(cx, arg) || disowned_before(cx, preds, seen, block, arg)) {
    return false;
  }
  const bool fresh = !el_tagged(cx, param->value);
  cx->tag_scope[param->value] = cx->tag_scope[arg];
  cx->tag_kind[param->value] = cx->tag_kind[arg];
  if (fresh) {
    mir_idlist_push(&cx->owners[cx->tag_scope[arg]], param->value);
  }
  return fresh;
}

/* A value that flows through a moving block parameter keeps its scope. */
static void tag_params(ElCx *cx) {
  const MirFunc *func = cx->f;
  const MirPreds preds = mir_preds(cx->ma, func);
  MirBits seen = mir_bits_new(cx->ma, (uint32_t)func->blocks.len);
  for (bool changed = true; changed;) {
    changed = false;
    for (size_t b = 0; b < func->blocks.len; b++) {
      const MirTerm *term = &func->blocks.ptr[b].term;
      for (uint32_t t = 0; t < mir_term_ntargets(term); t++) {
        const MirTarget *target = mir_term_target_const(term, t);
        const MirBlockData *dest = &func->blocks.ptr[target->block];
        for (size_t k = 0; k < target->nargs && k < dest->params.len; k++) {
          changed = tag_param(cx, &preds, &seen, (MirBlock)b, &dest->params.ptr[k], target->args[k]) || changed;
        }
      }
    }
  }
}

void el_tags(ElCx *cx) {
  const MirFunc *func = cx->f;
  const size_t nvalues = func->values.len;
  cx->tag_scope = MS_ARENA_NEW_ARRAY(cx->ma, int64_t, nvalues + 1);
  cx->tag_kind = MS_ARENA_NEW_ARRAY(cx->ma, int64_t, nvalues + 1);
  for (size_t i = 0; i <= nvalues; i++) {
    cx->tag_scope[i] = -1;
    cx->tag_kind[i] = -1;
  }
  cx->nvalues0 = (uint32_t)nvalues;
  read_scopes(cx, func);
  MirBits disowned = mir_bits_new(cx->ma, (uint32_t)nvalues);
  const MirBlock *idom = NULL;
  for (size_t b = 0; b < func->blocks.len; b++) {
    const MirInstList *insts = &func->blocks.ptr[b].insts;
    for (size_t i = 0; i < insts->len; i++) {
      const MirInst *inst = &insts->ptr[i];
      if (inst->op == MOP_ScopeDisown) {
        mir_bits_set(&disowned, inst->args[0]);
      }
      if (inst->op == MOP_ScopeOwn) {
        tag_owner(cx, &idom, &disowned, inst);
      }
    }
  }
  tag_params(cx);
}

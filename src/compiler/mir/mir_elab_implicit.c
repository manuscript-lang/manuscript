/* compiler/mir/mir_elab_implicit.c: the owner of a fresh value. Lowering says who owns a value only where it
 * remembers to; any other owned result (an `alt.take`, an `opt.unbox`, a `type.new` built by hand) would be dropped
 * by nothing if a later call unwinds before the instruction that consumes it. Before elaboration every owned
 * result no scope marker names is given to the innermost open scope where it is made, so elaboration closes it on
 * every exit and a consuming instruction ends its ownership like any other owner's. */
#include "compiler/mir/mir_elab.h"

/* The values a scope marker names, or a transfer carries away: lowering decided who owns them. `alias_moved`
 * receives the operands of a view whose result is named: the scope owns such an operand up to the view, then the
 * result's owner takes over. */
static MirBits named_values(MsArena *ma, const MirFunc *func, MirBits *alias_moved) {
  MirBits named = mir_bits_new(ma, (uint32_t)func->values.len + 1);
  MirBits carried = mir_bits_new(ma, (uint32_t)func->values.len + 1);
  for (size_t b = 0; b < func->blocks.len; b++) {
    const MirInstList *insts = &func->blocks.ptr[b].insts;
    MirBits here = mir_bits_new(ma, (uint32_t)func->values.len + 1); /* disowned in this block */
    for (size_t i = 0; i < insts->len; i++) {
      const MirInst *inst = &insts->ptr[i];
      for (uint32_t a = 0; inst->op == MOP_ScopeDisown && a < inst->nargs; a++) {
        mir_bits_set(&here, inst->args[a]);
      }
      const bool marker = inst->op == MOP_ScopeOwn || inst->op == MOP_ScopeMark ||
                          inst->op == MOP_ScopeUnpin;
      for (uint32_t a = 0; marker && a < inst->nargs; a++) {
        mir_bits_set(&named, inst->args[a]);
      }
      for (uint32_t a = 0; inst->op == MOP_Put && a < inst->nargs; a++) {
        if (!mir_bits_test(&here, inst->args[a])) {
          mir_bits_set(&carried, inst->args[a]); /* stored into a slot that keeps it */
        }
      }
    }
    /* A value carried on an edge or returned leaves its scope by that edge: lowering ended its ownership there. */
    MirTerm *term = &func->blocks.ptr[b].term;
    for (uint32_t t = 0; t < mir_term_ntargets(term); t++) {
      const MirTarget *edge = mir_term_target(term, t);
      for (uint32_t a = 0; a < edge->nargs; a++) {
        if (!mir_bits_test(&here, edge->args[a])) {
          mir_bits_set(&carried, edge->args[a]);
        }
      }
    }
    if (term->value != MIR_NONE && term->kind == MT_RET && !mir_bits_test(&here, term->value)) {
      mir_bits_set(&carried, term->value);
    }
  }
  for (uint32_t v = 0; v < (uint32_t)func->values.len; v++) {
    if (mir_bits_test(&carried, v)) {
      mir_bits_set(&named, v);
    }
  }
  /* A view hands its operand's ownership on to its result. */
  for (size_t b = 0; b < func->blocks.len; b++) {
    const MirInstList *insts = &func->blocks.ptr[b].insts;
    for (size_t i = 0; i < insts->len; i++) {
      const MirInst *inst = &insts->ptr[i];
      if (inst->op != MOP_OptView && inst->op != MOP_AltPlain) {
        continue;
      }
      MirBits *into = &named; /* the view's result owns it: the operand is not the scope's */
      (void)alias_moved;
      for (uint32_t a = 0; a < inst->nargs; a++) {
        mir_bits_set(into, inst->args[a]);
      }
    }
  }
  return named;
}

bool el_own_implicit(MirModule *module, MirFunc *func, MsArena *ma) {
  MirBits alias_moved = mir_bits_new(ma, (uint32_t)func->values.len + 1);
  MirBits named = named_values(ma, func, &alias_moved);
  const size_t nblocks = func->blocks.len;
  int64_t *exit_scope = MS_ARENA_NEW_ARRAY(ma, int64_t, nblocks + 1);
  bool *seen = MS_ARENA_NEW_ARRAY(ma, bool, nblocks + 1);
  int64_t *parent = NULL;
  uint32_t nscopes = 0;
  for (size_t b = 0; b < nblocks; b++) {
    const MirInstList *insts = &func->blocks.ptr[b].insts;
    for (size_t i = 0; i < insts->len; i++) {
      const MirInst *inst = &insts->ptr[i];
      nscopes = (inst->op == MOP_ScopeBegin || inst->op == MOP_ScopeOwn || inst->op == MOP_ScopeEnd) && inst->imm.a + 1 > nscopes
                    ? inst->imm.a + 1
                    : nscopes;
    }
  }
  if (nscopes == 0) {
    return true;
  }
  parent = MS_ARENA_NEW_ARRAY(ma, int64_t, (size_t)nscopes + 1);
  for (size_t b = 0; b < nblocks; b++) {
    const MirInstList *insts = &func->blocks.ptr[b].insts;
    for (size_t i = 0; i < insts->len; i++) {
      if (insts->ptr[i].op == MOP_ScopeBegin) {
        parent[insts->ptr[i].imm.a] = (int64_t)insts->ptr[i].imm.b - 1;
      }
    }
  }
  MirBlock *order = NULL;
  const uint32_t norder = mir_rpo(ma, func, &order);
  const MirPreds preds = mir_preds(ma, func);
  for (uint32_t k = 0; k < norder; k++) {
    const MirBlock b = order[k];
    int64_t current = -1;
    for (uint32_t p = 0; b != 0 && p < mir_preds_count(&preds, b); p++) {
      const MirBlock from = preds.list[preds.start[b] + p];
      if (seen[from]) {
        current = exit_scope[from];
        break;
      }
    }
    MirInstList old = func->blocks.ptr[b].insts;
    MirInstList fresh = {0};
    for (size_t i = 0; i < old.len; i++) {
      MirInst inst = old.ptr[i];
      mir_inst_list_push(&fresh, inst);
      for (uint32_t a = 0; a < inst.nargs && inst.res != MIR_NONE && (inst.op == MOP_OptView || inst.op == MOP_AltPlain); a++) {
        if (mir_bits_test(&alias_moved, inst.args[a])) {
          MirValue moved = inst.args[a];
          mir_inst_list_push(&fresh, mir_inst(MOP_ScopeDisown, (MirImm){0}, MIR_NONE, inst.loc, mir_args_copy(module, &moved, 1), 1));
        }
      }
      if (inst.op == MOP_ScopeBegin) {
        current = (int64_t)inst.imm.a;
      } else if (inst.op == MOP_ScopeEnd) {
        current = (uint64_t)inst.imm.a < nscopes ? parent[inst.imm.a] : -1;
      }
      MirMode mode = MM_BORROW;
      if (current < 0 || inst.res == MIR_NONE || mir_bits_test(&named, inst.res) ||
          !mir_needs_drop(module, mir_value_ty(func, inst.res)) || !mir_result_mode(module, func, &old.ptr[i], &mode) ||
          mode != MM_MOVE) {
        continue;
      }
      MirValue arg = inst.res;
      const MirImm own = {.tag = MI_SCOPE, .a = (uint32_t)current, .b = 0};
      mir_inst_list_push(&fresh, mir_inst(MOP_ScopeOwn, own, MIR_NONE, inst.loc, mir_args_copy(module, &arg, 1), 1));
    }
    mir_block_set_insts(&func->blocks.ptr[b], &fresh);
    exit_scope[b] = current;
    seen[b] = true;
  }
  return true;
}

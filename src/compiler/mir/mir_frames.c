/* compiler/mir/mir_frames.c: which values may live in their maker's frame: interface borrows and closure
 * objects used only where they cannot outlive it. One flag per value. */
#include "compiler/mir/mir_analysis.h"
#include "compiler/mir/mir_pass.h"

/* Clears the flag of every value the terminator uses beyond a plain operand: a returned value, a branch
 * condition or scrutinee, and every branch argument. */
static void clear_term_uses(const MirBlockData *block, bool *framed) {
  const MirTerm *term = &block->term;
  if ((term->kind == MT_RET || term->kind == MT_CONDBR || term->kind == MT_SWITCH) && term->value != MIR_NONE) {
    framed[term->value] = false;
  }
  for (uint32_t index = 0; index < mir_term_ntargets(term); index++) {
    const MirTarget *target = mir_term_target_const(term, index);
    for (uint32_t arg = 0; arg < target->nargs; arg++) {
      framed[target->args[arg]] = false;
    }
  }
}

/* Marks the results of the instructions `wanted` accepts; false when there are none. */
typedef bool (*MarkFn)(const MirModule *module, const MirInst *inst);

static bool mark_results(const MirModule *module, const MirFunc *func, bool *framed, MarkFn wanted) {
  bool any = false;
  for (size_t block = 0; block < func->blocks.len; block++) {
    const MirInstList *insts = &func->blocks.ptr[block].insts;
    for (size_t index = 0; index < insts->len; index++) {
      if (insts->ptr[index].res != MIR_NONE && wanted(module, &insts->ptr[index])) {
        framed[insts->ptr[index].res] = true;
        any = true;
      }
    }
  }
  return any;
}

static bool is_iface_borrow(const MirModule *module, const MirInst *inst) {
  (void)module;
  return inst->op == MOP_IfaceBorrow;
}

static bool is_closing_nothing_closure(const MirModule *module, const MirInst *inst) {
  return inst->op == MOP_ClosureNew && inst->imm.tag == MI_FUNC &&
         module->funcs.ptr[inst->imm.a].ncapture_closers == 0;
}

bool *mir_framed_iface_borrows(MsArena *arena, const MirModule *module, const MirFunc *func) {
  bool *framed = MS_ARENA_NEW_ARRAY(arena, bool, func->values.len + 1);
  if (!mark_results(module, func, framed, is_iface_borrow)) {
    return NULL;
  }
  for (size_t block = 0; block < func->blocks.len; block++) {
    const MirBlockData *data = &func->blocks.ptr[block];
    for (size_t index = 0; index < data->insts.len; index++) {
      const MirInst *inst = &data->insts.ptr[index];
      const bool plain = inst->op == MOP_Drop || ((inst->op == MOP_Call || inst->op == MOP_CallMethod) &&
                                                  !mir_result_views(module, func, inst));
      for (uint32_t arg = 0; !plain && arg < inst->nargs; arg++) {
        framed[inst->args[arg]] = false;
      }
    }
    clear_term_uses(data, framed);
  }
  return framed;
}

/* Whether argument `index` of call `inst` is borrowed. */
static bool borrows_argument(const MirModule *module, const MirInst *inst, uint32_t index) {
  if (inst->op == MOP_Call && inst->imm.tag == MI_FUNC) {
    const MirFunc *callee = &module->funcs.ptr[inst->imm.a];
    return index < callee->nparams && callee->params[index].mode == MM_BORROW;
  }
  if (inst->op == MOP_CallRt && inst->imm.tag == MI_EXT) {
    const MirExtern *external = &module->externs.ptr[inst->imm.a];
    return index < external->nparams && external->params[index].mode == MM_BORROW;
  }
  return inst->op == MOP_CallInd && index == 0;
}

bool *mir_framed_closures(MsArena *arena, const MirModule *module, const MirFunc *func) {
  bool *framed = MS_ARENA_NEW_ARRAY(arena, bool, func->values.len + 1);
  if (!mark_results(module, func, framed, is_closing_nothing_closure)) {
    return NULL;
  }
  for (size_t block = 0; block < func->blocks.len; block++) {
    const MirBlockData *data = &func->blocks.ptr[block];
    for (size_t index = 0; index < data->insts.len; index++) {
      const MirInst *inst = &data->insts.ptr[index];
      const bool call = inst->op == MOP_Call || inst->op == MOP_CallRt || inst->op == MOP_CallInd;
      const bool plain_call = call && !mir_result_views(module, func, inst);
      for (uint32_t arg = 0; arg < inst->nargs; arg++) {
        if (inst->op != MOP_Drop && !(plain_call && borrows_argument(module, inst, arg))) {
          framed[inst->args[arg]] = false;
        }
      }
    }
    clear_term_uses(data, framed);
  }
  return framed;
}

/* Owns the purity and glue-depth hints (see emit_hints.h). */
#include "compiler/emit/emit_hints.h"

void emit_hints_init(EmitHints *hints, const MirModule *module, const MirGlue *glue) {
  size_t count = module->funcs.len;
  hints->arena = ms_arena_new();
  hints->purity = MS_ARENA_NEW_ARRAY(&hints->arena, uint8_t, count);
  hints->depth = MS_ARENA_NEW_ARRAY(&hints->arena, uint32_t, count);
  hints->is_glue = MS_ARENA_NEW_ARRAY(&hints->arena, bool, count);
  for (size_t index = 0; glue != NULL && index < glue->entries.len; index++) {
    hints->is_glue[glue->entries.ptr[index].func] = true;
  }
}

void emit_hints_free(EmitHints *hints) {
  ms_arena_free(&hints->arena);
}

/* Whether every block reachable from `block` leads on without a cycle. `color`: 0 new, 1 on the path, 2 done. */
static bool acyclic_from(const MirFunc *func, uint8_t *color, MirBlock block) {
  if (color[block] != 0) {
    return color[block] == 2;
  }
  color[block] = 1;
  const MirTerm *term = &func->blocks.ptr[block].term;
  bool branch = term->kind == MT_BR || term->kind == MT_CONDBR;
  if (branch && !acyclic_from(func, color, term->a.block)) {
    return false;
  }
  if (term->kind == MT_CONDBR && !acyclic_from(func, color, term->b.block)) {
    return false;
  }
  color[block] = 2;
  return true;
}

static bool pure_block(EmitCx *cx, EmitHints *hints, const MirBlockData *block) {
  if (block->term.kind != MT_BR && block->term.kind != MT_CONDBR && block->term.kind != MT_RET) {
    return false;
  }
  for (uint32_t index = 0; index < block->insts.len; index++) {
    const MirInst *inst = &block->insts.ptr[index];
    bool pure = inst->op == MOP_Call ? emit_hint_pure(cx, hints, inst->imm.a)
                                     : mir_op_info[inst->op].effects == 0 && !mir_op_is_call((MirOp)inst->op);
    if (!pure) {
      return false;
    }
  }
  return true;
}

bool emit_hint_pure(EmitCx *cx, EmitHints *hints, uint32_t index) {
  if (hints->purity[index] != 0) {
    return hints->purity[index] == 2;
  }
  hints->purity[index] = 1;
  const MirFunc *func = &cx->module->funcs.ptr[index];
  bool pure = emit_leaves(cx, func->ret).len <= 1;
  for (uint32_t param = 0; pure && param < func->nparams; param++) {
    pure = !emit_is_indirect(cx, func->params[param].ty);
  }
  for (uint32_t block = 0; pure && block < func->blocks.len; block++) {
    pure = pure_block(cx, hints, &func->blocks.ptr[block]);
  }
  if (pure) {
    uint8_t *color = MS_ARENA_NEW_ARRAY(&hints->arena, uint8_t, func->blocks.len ? func->blocks.len : 1);
    pure = acyclic_from(func, color, 0);
  }
  hints->purity[index] = pure ? 2 : 3;
  return pure;
}

/* The longest chain of glue below `index`; a function on the current path counts as a leaf, which ends cycles. */
static uint32_t glue_depth(const MirModule *module, EmitHints *hints, uint32_t index) {
  if (hints->depth[index] != 0) {
    return hints->depth[index] - 1;
  }
  hints->depth[index] = 1;
  uint32_t below = 0;
  const MirFunc *func = &module->funcs.ptr[index];
  for (uint32_t block = 0; block < func->blocks.len; block++) {
    const MirInstList *insts = &func->blocks.ptr[block].insts;
    for (uint32_t at = 0; at < insts->len; at++) {
      const MirInst *inst = &insts->ptr[at];
      if (inst->op != MOP_Call || inst->imm.a == index || !hints->is_glue[inst->imm.a]) {
        continue;
      }
      uint32_t chain = 1 + glue_depth(module, hints, inst->imm.a);
      below = chain > below ? chain : below;
    }
  }
  hints->depth[index] = below + 1;
  return below;
}

bool emit_hint_deep_glue(const EmitCx *cx, EmitHints *hints, uint32_t index) {
  return hints->is_glue[index] && glue_depth(cx->module, hints, index) >= 3;
}

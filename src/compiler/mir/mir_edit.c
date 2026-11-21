/* compiler/mir/mir_edit.c: editing helpers for passes: inserting and removing instructions, interning
 * runtime declarations and names, cloning a function, and renumbering blocks. */
#include "compiler/mir/mir_analysis.h"

#include "base/strbuild.h"

/* ---- declarations ---- */

static bool same_signature(const MirExtern *a, const MirExtern *b) {
  if (a->name != b->name || a->ret != b->ret || a->nparams != b->nparams) {
    return false;
  }
  for (uint32_t index = 0; index < a->nparams; index++) {
    if (a->params[index].ty != b->params[index].ty) {
      return false;
    }
  }
  return true;
}

uint32_t mir_extern_intern(MirModule *module, const MirExtern *def) {
  for (size_t index = 0; index < module->externs.len; index++) {
    if (same_signature(&module->externs.ptr[index], def)) {
      return (uint32_t)index;
    }
  }
  MirExtern copy = *def;
  copy.params = MS_ARENA_NEW_ARRAY(&module->arena, MirParam, def->nparams);
  if (def->nparams != 0) {
    __builtin_memcpy(copy.params, def->params, sizeof(MirParam) * def->nparams);
  }
  return mir_add_extern(module, &copy);
}

MsName mir_name_suffixed(MirModule *module, MsName base, MsSpan suffix) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append(&text, ms_names_span(&module->names, base));
  ms_strbuild_append(&text, suffix);
  const MsName name = mir_name(module, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  return name;
}

/* ---- instructions ---- */

void mir_block_insert(MirBlockData *block, uint32_t at, const MirInst *inst) {
  mir_inst_list_push(&block->insts, *inst);
  const size_t last = block->insts.len - 1;
  if (at < last) {
    __builtin_memmove(&block->insts.ptr[at + 1], &block->insts.ptr[at], sizeof(MirInst) * (last - at));
  }
  block->insts.ptr[at] = *inst;
}

void mir_block_remove(MirBlockData *block, const uint32_t *dead, uint32_t ndead) {
  size_t kept = 0;
  uint32_t next = 0;
  for (size_t index = 0; index < block->insts.len; index++) {
    if (next < ndead && dead[next] == index) {
      next++;
      continue;
    }
    block->insts.ptr[kept++] = block->insts.ptr[index];
  }
  block->insts.len = kept;
}

uint32_t mir_entry_insert_at(const MirFunc *func) {
  const MirInstList *entry = &func->blocks.ptr[0].insts;
  return entry->len > 0 && entry->ptr[0].op == MOP_DepthEnter ? 1u : 0u;
}

/* ---- whole functions ---- */

static void free_block_lists(MirBlockData *block) {
  mir_block_param_list_free(&block->params);
  mir_inst_list_free(&block->insts);
}

void mir_func_release(MirFunc *func) {
  for (size_t index = 0; index < func->blocks.len; index++) {
    free_block_lists(&func->blocks.ptr[index]);
  }
  mir_block_list_free(&func->blocks);
  mir_scope_list_free(&func->scopes);
  mir_named_value_list_free(&func->names);
  mir_tylist_free(&func->values);
}

static void clone_block(const MirBlockData *from, MirBlockData *to) {
  *to = *from;
  to->params = (MirBlockParamList){0};
  to->insts = (MirInstList){0};
  mir_block_param_list_reserve(&to->params, from->params.len);
  for (size_t index = 0; index < from->params.len; index++) {
    mir_block_param_list_push(&to->params, from->params.ptr[index]);
  }
  mir_inst_list_reserve(&to->insts, from->insts.len);
  for (size_t index = 0; index < from->insts.len; index++) {
    mir_inst_list_push(&to->insts, from->insts.ptr[index]);
  }
}

void mir_func_clone(const MirFunc *func, MirFunc *out) {
  *out = *func;
  out->scopes = (MirScopeList){0};
  out->names = (MirNamedValueList){0};
  out->values = (MirTyList){0};
  out->blocks = (MirBlockList){0};
  for (size_t index = 0; index < func->scopes.len; index++) {
    mir_scope_list_push(&out->scopes, func->scopes.ptr[index]);
  }
  for (size_t index = 0; index < func->names.len; index++) {
    mir_named_value_list_push(&out->names, func->names.ptr[index]);
  }
  for (size_t index = 0; index < func->values.len; index++) {
    mir_tylist_push(&out->values, func->values.ptr[index]);
  }
  for (size_t index = 0; index < func->blocks.len; index++) {
    MirBlockData copy;
    clone_block(&func->blocks.ptr[index], &copy);
    mir_block_list_push(&out->blocks, copy);
  }
}

static bool already_in_order(const MirBlock *order, uint32_t count, size_t blocks) {
  if (count != blocks) {
    return false;
  }
  for (uint32_t index = 0; index < count; index++) {
    if (order[index] != index) {
      return false;
    }
  }
  return true;
}

void mir_func_compact_blocks(MirFunc *func) {
  MsArena arena = ms_arena_new();
  MirBlock *order = NULL;
  const uint32_t count = mir_rpo(&arena, func, &order);
  if (already_in_order(order, count, func->blocks.len)) {
    ms_arena_free(&arena);
    return;
  }
  MirBlock *map = MS_ARENA_NEW_ARRAY(&arena, MirBlock, func->blocks.len + 1);
  for (size_t index = 0; index < func->blocks.len; index++) {
    map[index] = MIR_NONE;
  }
  for (uint32_t index = 0; index < count; index++) {
    map[order[index]] = index;
  }
  MirBlockData *moved = MS_ARENA_NEW_ARRAY(&arena, MirBlockData, (size_t)count + 1);
  for (uint32_t index = 0; index < count; index++) {
    moved[index] = func->blocks.ptr[order[index]];
    for (uint32_t target = 0; target < mir_term_ntargets(&moved[index].term); target++) {
      MirTarget *edge = mir_term_target(&moved[index].term, target);
      edge->block = map[edge->block];
    }
  }
  for (size_t index = 0; index < func->blocks.len; index++) {
    if (map[index] == MIR_NONE) {
      free_block_lists(&func->blocks.ptr[index]);
    }
  }
  __builtin_memcpy(func->blocks.ptr, moved, sizeof(MirBlockData) * count);
  func->blocks.len = count;
  ms_arena_free(&arena);
}

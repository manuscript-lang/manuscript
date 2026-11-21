/* compiler/mir/mir_glue_demand.c: what the program asks glue for: the types its functions drop and clone, the
 * types descriptors point at, and the closure objects it makes. A type missing here only keeps the back end's
 * own function. Types are sets: a bit per unscoped type id, so a walk in id order is sorted and unique. */
#include "compiler/mir/mir_glue_demand.h"

static void want(MirBits *set, MirTy ty) {
  if (ty != MIR_NONE) {
    mir_bits_set(set, mir_ty_unscoped(ty));
  }
}

static MirTy arg_type(const MirFunc *func, const MirInst *inst, uint32_t index) {
  return index < inst->nargs ? mir_value_ty(func, inst->args[index]) : MIR_NONE;
}

/* Marks what one instruction drops or clones. */
static void want_inst(const MirModule *module, const MirFunc *func, const MirInst *inst, MirBits *drops,
                      MirBits *clones) {
  const MirTy first = arg_type(func, inst, 0);
  MirTy inner = MIR_NONE;
  switch ((MirOp)inst->op) {
  case MOP_Drop: want(drops, first); break;
  case MOP_DropIf: want(drops, arg_type(func, inst, 1)); break;
  case MOP_Clone: want(clones, first); break;
  case MOP_OptUnwrap:
    if (first != MIR_NONE && mirgl_is_opt(module, first, &inner)) {
      want(clones, inner);
    }
    break;
  case MOP_AltOwn:
    want(clones, inst->res == MIR_NONE ? MIR_NONE : mir_value_ty(func, inst->res));
    break;
  case MOP_AltRelease:
  case MOP_AltUnbox:
  case MOP_AltTake:
  case MOP_TypeRelease:
  case MOP_OptUnbox: want(drops, first); break;
  case MOP_ListSet:
  case MOP_ListSetNn:
  case MOP_ListSetU:
  case MOP_ListDropLast:
  case MOP_ListRelease:
    want(drops, first == MIR_NONE ? MIR_NONE : mirgl_elem(module, first, true));
    break;
  case MOP_TypeDesc:
    if (inst->imm.tag == MI_TY) {
      want(drops, inst->imm.a);
      want(clones, inst->imm.a);
    }
    break;
  default: break;
  }
}

/* `seed` and the types dropped (or cloned) when a value of one of them is, into `out`. */
static void close_into(const MirModule *module, const MirBits *seed, MirBits *out) {
  MirTyList todo = {0};
  for (uint32_t ty = 0; ty < seed->nbits; ty++) {
    if (mir_bits_test(seed, ty)) {
      mir_tylist_push(&todo, ty);
    }
  }
  while (todo.len > 0) {
    const MirTy ty = mir_ty_unscoped(todo.ptr[--todo.len]);
    if (ty < out->nbits && !mir_bits_test(out, ty)) {
      mir_bits_set(out, ty);
      mirgl_children(module, ty, &todo);
    }
  }
  mir_tylist_free(&todo);
}

static void merge(MirBits *into, const MirBits *from) {
  for (uint32_t index = 0; index < (into->nbits + 63) / 64; index++) {
    into->words[index] |= from->words[index];
  }
}

/* The types a descriptor key reaches through its inner descriptors, as slot-glue types (into `slots`) and
 * the interface payload types of the vtables (into `blocks`). */
static void descriptor_types(const MirModule *module, MirBits *slots, MirBits *blocks) {
  MirLayouts layouts;
  mir_layouts_init(&layouts, module);
  MirIdList keys = {0}, seen = {0};
  for (size_t fi = 0; fi < module->funcs.len; fi++) {
    const MirFunc *func = &module->funcs.ptr[fi];
    for (size_t bi = 0; bi < func->blocks.len; bi++) {
      const MirBlockData *block = &func->blocks.ptr[bi];
      for (size_t ii = 0; ii < block->insts.len; ii++) {
        const MirInst *inst = &block->insts.ptr[ii];
        if (inst->op == MOP_TypeDesc && inst->imm.tag == MI_TY) {
          mir_idlist_push(&keys, inst->imm.a);
        }
      }
    }
  }
  while (keys.len > 0) {
    const MirTy key = keys.ptr[--keys.len];
    bool known = false;
    for (size_t index = 0; index < seen.len && !known; index++) {
      known = seen.ptr[index] == key;
    }
    if (known) {
      continue;
    }
    mir_idlist_push(&seen, key);
    const MirDescPlan plan = mir_desc_plan(module, &layouts, key);
    for (uint32_t index = 0; index < 2; index++) {
      if (plan.inner[index] != MIR_NONE) {
        mir_idlist_push(&keys, plan.inner[index]);
      }
    }
    want(slots, plan.slot_glue);
  }
  for (size_t index = 0; index < module->vtables.len; index++) {
    want(blocks, module->vtables.ptr[index].data_ty);
  }
  mir_idlist_free(&keys);
  mir_idlist_free(&seen);
  mir_layouts_free(&layouts);
}

void mirgl_demand_types(MsArena *arena, const MirModule *module, GlDemand *demand) {
  const uint32_t ntypes = (uint32_t)module->types.kinds.len;
  MirBits drops = mir_bits_new(arena, ntypes), clones = mir_bits_new(arena, ntypes);
  for (size_t fi = 0; fi < module->funcs.len; fi++) {
    const MirFunc *func = &module->funcs.ptr[fi];
    for (size_t bi = 0; bi < func->blocks.len; bi++) {
      const MirBlockData *block = &func->blocks.ptr[bi];
      for (size_t ii = 0; ii < block->insts.len; ii++) {
        want_inst(module, func, &block->insts.ptr[ii], &drops, &clones);
      }
    }
  }
  demand->slots = mir_bits_new(arena, ntypes);
  demand->blocks = mir_bits_new(arena, ntypes);
  descriptor_types(module, &demand->slots, &demand->blocks);
  /* The slot and block functions call the drop and clone of their types. */
  MirBits addressed = mir_bits_new(arena, ntypes), closed = mir_bits_new(arena, ntypes);
  merge(&addressed, &demand->slots);
  merge(&addressed, &demand->blocks);
  close_into(module, &addressed, &closed);
  demand->drops = mir_bits_new(arena, ntypes);
  demand->clones = mir_bits_new(arena, ntypes);
  close_into(module, &drops, &demand->drops);
  close_into(module, &clones, &demand->clones);
  merge(&demand->drops, &closed);
  merge(&demand->clones, &closed);
}

/* ---- closures ---- */

void mirgl_demand_closures(MsArena *arena, const MirModule *module, GlDemand *demand) {
  const uint32_t nfuncs = (uint32_t)module->funcs.len;
  demand->heap_drops = mir_bits_new(arena, nfuncs);
  demand->framed_drops = mir_bits_new(arena, nfuncs);
  demand->closure_clones = mir_bits_new(arena, nfuncs);
  for (uint32_t fi = 0; fi < nfuncs; fi++) {
    const MirFunc *func = &module->funcs.ptr[fi];
    const bool *framed = mir_framed_closures(arena, module, func);
    for (size_t bi = 0; bi < func->blocks.len; bi++) {
      const MirBlockData *block = &func->blocks.ptr[bi];
      for (size_t ii = 0; ii < block->insts.len; ii++) {
        const MirInst *inst = &block->insts.ptr[ii];
        if (inst->op != MOP_ClosureNew || inst->imm.tag != MI_FUNC || inst->res == MIR_NONE) {
          continue;
        }
        const bool in_frame = framed != NULL && framed[inst->res];
        mir_bits_set(in_frame ? &demand->framed_drops : &demand->heap_drops, inst->imm.a);
        mir_bits_set(&demand->closure_clones, inst->imm.a);
      }
    }
  }
}

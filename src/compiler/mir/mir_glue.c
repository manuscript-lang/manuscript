/* compiler/mir/mir_glue.c: the glue pass. It plans which functions the module is missing from what its
 * functions drop, clone and name (mir_glue_demand.c), then builds them in a fixed order, so one module always
 * gets the same functions and names. */
#include "compiler/mir/mir_expand.h"
#include "compiler/mir/mir_glue_demand.h"

/* What this round makes. */
typedef struct GlPlan {
  MirTyList drops, clones, slots, blocks;
  MirIdList heap_drops, framed_drops, closure_clones; /* closure function ids */
} GlPlan;

static void plan_free(GlPlan *plan) {
  mir_tylist_free(&plan->drops);
  mir_tylist_free(&plan->clones);
  mir_tylist_free(&plan->slots);
  mir_tylist_free(&plan->blocks);
  mir_idlist_free(&plan->heap_drops);
  mir_idlist_free(&plan->framed_drops);
  mir_idlist_free(&plan->closure_clones);
}

/* A list of plain elements is copied by the back ends in one block copy; bytes and interfaces likewise. */
static bool back_end_copies(const MirModule *module, MirTy ty) {
  const MirTyData *data = mir_ty_data(module, ty);
  return (data->kind == MK_LIST && !mir_needs_drop(module, data->elem)) || data->kind == MK_BYTES ||
         data->kind == MK_IFACE;
}

static void plan_types(const MirModule *module, const MirGlue *glue, const GlDemand *demand, GlPlan *plan) {
  MirLayouts layouts;
  mir_layouts_init(&layouts, module);
  for (uint32_t ty = 0; ty < demand->drops.nbits; ty++) {
    if (mir_bits_test(&demand->drops, ty) && mirgl_eligible(module, &layouts, ty) &&
        mir_glue_find(glue, MG_DROP, ty, 0, 0) == MIR_NONE) {
      mir_tylist_push(&plan->drops, ty);
    }
    if (mir_bits_test(&demand->clones, ty) && mirgl_eligible(module, &layouts, ty) &&
        mir_glue_find(glue, MG_CLONE, ty, 0, 0) == MIR_NONE && !back_end_copies(module, ty)) {
      mir_tylist_push(&plan->clones, ty);
    }
    if (mir_bits_test(&demand->slots, ty) && mir_glue_find(glue, MG_SLOT_COPY, ty, 0, 0) == MIR_NONE) {
      mir_tylist_push(&plan->slots, ty);
    }
    if (mir_bits_test(&demand->blocks, ty) && mir_glue_find(glue, MG_BLOCK_DROP, ty, 0, 0) == MIR_NONE) {
      mir_tylist_push(&plan->blocks, ty);
    }
  }
  mir_layouts_free(&layouts);
}

static void plan_closures(const MirGlue *glue, const GlDemand *demand, GlPlan *plan) {
  for (uint32_t func = 0; func < demand->heap_drops.nbits; func++) {
    if (mir_bits_test(&demand->heap_drops, func) &&
        mir_glue_find(glue, MG_CLOSURE_DROP, MIR_VOID, func, 0) == MIR_NONE) {
      mir_idlist_push(&plan->heap_drops, func);
    }
    if (mir_bits_test(&demand->framed_drops, func) &&
        mir_glue_find(glue, MG_CLOSURE_DROP_FRAMED, MIR_VOID, func, 0) == MIR_NONE) {
      mir_idlist_push(&plan->framed_drops, func);
    }
    if (mir_bits_test(&demand->closure_clones, func) &&
        mir_glue_find(glue, MG_CLOSURE_CLONE, MIR_VOID, func, 0) == MIR_NONE) {
      mir_idlist_push(&plan->closure_clones, func);
    }
  }
}

static uint32_t plan_size(const GlPlan *plan) {
  return (uint32_t)(plan->drops.len + plan->clones.len + plan->slots.len + plan->blocks.len +
                    plan->heap_drops.len + plan->framed_drops.len + plan->closure_clones.len);
}

/* ---- building ---- */

static void build_types(MirModule *module, MirGlue *glue, const GlPlan *plan) {
  for (size_t index = 0; index < plan->drops.len; index++) {
    const MirTy ty = plan->drops.ptr[index];
    uint32_t id = mirgl_make_drop(module, glue, ty);
    if (mirgl_recurses(module, ty)) {
      id = mirgl_wrap_deep_drop(module, glue, ty, id);
    }
    mirgl_record(glue, MG_DROP, ty, 0, 0, id);
  }
  for (size_t index = 0; index < plan->clones.len; index++) {
    const MirTy ty = plan->clones.ptr[index];
    uint32_t id = mirgl_make_clone(module, glue, ty);
    if (mirgl_recurses(module, ty)) {
      id = mirgl_wrap_deep_clone(module, glue, ty, id);
    }
    mirgl_record(glue, MG_CLONE, ty, 0, 0, id);
  }
}

static void build_addressed(MirModule *module, MirGlue *glue, const GlPlan *plan) {
  for (size_t index = 0; index < plan->slots.len; index++) {
    const MirTy ty = plan->slots.ptr[index];
    if (mir_glue_find(glue, MG_SLOT_DROP, ty, 0, 0) == MIR_NONE) {
      mirgl_record(glue, MG_SLOT_DROP, ty, 0, 0, mirgl_make_slot_drop(module, ty));
    }
    mirgl_record(glue, MG_SLOT_COPY, ty, 0, 0, mirgl_make_slot_copy(module, ty));
  }
  for (size_t index = 0; index < plan->blocks.len; index++) {
    const MirTy ty = plan->blocks.ptr[index];
    mirgl_record(glue, MG_BLOCK_DROP, ty, 0, 0, mirgl_make_block_drop(module, ty));
    mirgl_record(glue, MG_BLOCK_CLONE, ty, 0, 0, mirgl_make_block_clone(module, ty));
  }
}

/* Heap and framed drops in function order, as the plan sorts them: a function's heap drop first. */
static void build_closures(MirModule *module, MirGlue *glue, const GlPlan *plan) {
  size_t heap = 0, framed = 0;
  while (heap < plan->heap_drops.len || framed < plan->framed_drops.len) {
    const uint32_t next_heap = heap < plan->heap_drops.len ? plan->heap_drops.ptr[heap] : MIR_NONE;
    const uint32_t next_framed = framed < plan->framed_drops.len ? plan->framed_drops.ptr[framed] : MIR_NONE;
    const bool is_framed = next_framed < next_heap;
    const uint32_t func = is_framed ? next_framed : next_heap;
    const MirGlueKind kind = is_framed ? MG_CLOSURE_DROP_FRAMED : MG_CLOSURE_DROP;
    mirgl_record(glue, kind, MIR_VOID, func, 0, mirgl_make_closure_drop(module, func, is_framed));
    heap += !is_framed;
    framed += is_framed;
  }
  for (size_t index = 0; index < plan->closure_clones.len; index++) {
    const uint32_t func = plan->closure_clones.ptr[index];
    if (mir_glue_find(glue, MG_CLOSURE_DROP, MIR_VOID, func, 0) == MIR_NONE) {
      mirgl_record(glue, MG_CLOSURE_DROP, MIR_VOID, func, 0, mirgl_make_closure_drop(module, func, false));
    }
    mirgl_record(glue, MG_CLOSURE_CLONE, MIR_VOID, func, 0, mirgl_make_closure_clone(module, glue, func));
  }
}

bool mir_glue(MirModule *module, MirGlue *glue) {
  MsArena scratch = ms_arena_new();
  GlDemand demand = {0};
  mirgl_demand_types(&scratch, module, &demand);
  mirgl_demand_closures(&scratch, module, &demand);
  GlPlan plan = {0};
  plan_types(module, glue, &demand, &plan);
  plan_closures(glue, &demand, &plan);
  ms_arena_free(&scratch);
  const bool made = plan_size(&plan) > 0;
  build_types(module, glue, &plan);
  build_addressed(module, glue, &plan);
  build_closures(module, glue, &plan);
  plan_free(&plan);
  return made;
}

void mir_glue_run_and_expand(MirModule *module, MirGlue *glue) {
  while (mir_glue(module, glue)) {
    (void)mir_expand_owned(module);
  }
  (void)mir_expand_owned(module);
}

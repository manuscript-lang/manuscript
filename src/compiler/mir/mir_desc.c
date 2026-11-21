/* compiler/mir/mir_desc.c: the plan of a type's descriptor. */
#include "compiler/mir/mir_desc.h"

static MsSpan runtime_descriptor(MirTyKind kind) {
  switch (kind) {
  case MK_INT: return ms_span_of_text("msrt_desc_int");
  case MK_FLOAT: return ms_span_of_text("msrt_desc_float");
  case MK_FLOAT32: return ms_span_of_text("msrt_desc_float32");
  case MK_BOOL: return ms_span_of_text("msrt_desc_bool");
  case MK_STR: return ms_span_of_text("msrt_desc_string");
  case MK_BYTES: return ms_span_of_text("msrt_desc_bytes");
  default: return (MsSpan){0};
  }
}

static MirTy arg_or_none(const MirTyData *data, uint32_t index) {
  return index < data->nargs ? data->args[index] : MIR_NONE;
}

/* Fills the kind and inner types of a type that has no descriptor of the runtime's. */
static void plan_shape(const MirModule *module, MirLayouts *layouts, MirTy ty, MirDescPlan *plan) {
  const MirTyData *data = mir_ty_data(module, ty);
  const bool collection = data->kind == MK_OBJ && data->obj_class == MIR_OBJ_COLLECTION;
  if (data->kind == MK_LIST) {
    plan->kind = MIR_DESC_LIST;
    plan->inner[0] = data->elem;
  } else if (collection && data->nargs > 1) {
    plan->kind = MIR_DESC_MAP;
    plan->inner[0] = arg_or_none(data, 0);
    plan->inner[1] = arg_or_none(data, 1);
  } else if (collection) {
    plan->kind = MIR_DESC_SET;
    plan->inner[0] = arg_or_none(data, 0);
  } else if (data->kind == MK_OBJ || data->kind == MK_FN ||
             (data->kind == MK_OPT && mir_opt_is_nullable(layouts, data->elem))) {
    plan->kind = MIR_DESC_SHARED; /* an object, a closure or a nullable optional is one shared word */
  } else if (!mir_needs_drop(module, ty)) {
    plan->kind = MIR_DESC_POD;
  } else {
    plan->kind = MIR_DESC_CUSTOM;
    plan->slot_glue = ty;
  }
}

/* The equality and hash glue of the key's own scope, else of the unscoped type. */
static void plan_eq_hash(const MirModule *module, MirTy key, MirDescPlan *plan) {
  const MirTy wanted[2] = {key, mir_ty_unscoped(key)};
  for (uint32_t pass = 0; pass < 2 && !plan->has_eq_hash; pass++) {
    for (size_t index = 0; index < module->desc_glue.len; index++) {
      const MirDescGlue *glue = &module->desc_glue.ptr[index];
      if (glue->ty == wanted[pass]) {
        plan->has_eq_hash = true;
        plan->eq = glue->eq;
        plan->hash = glue->hash;
        break;
      }
    }
  }
}

MirDescPlan mir_desc_plan(const MirModule *module, MirLayouts *layouts, MirTy key) {
  const uint32_t scope = mir_ty_scope(key);
  const MirTy ty = mir_ty_unscoped(key);
  MirDescPlan plan = {.inner = {MIR_NONE, MIR_NONE}, .slot_glue = MIR_NONE};
  plan.runtime = runtime_descriptor((MirTyKind)mir_ty_data(module, ty)->kind);
  if (plan.runtime.len != 0) {
    return plan;
  }
  const MirMemLayout mem = mir_type_mem(layouts, ty);
  plan.size = mem.size;
  plan.align = mem.align;
  plan.kind = MIR_DESC_POD;
  if (scope == MIR_FORGOTTEN_SCOPE) {
    return plan; /* plain bits whatever it holds */
  }
  plan_shape(module, layouts, ty, &plan);
  plan_eq_hash(module, key, &plan);
  for (uint32_t index = 0; index < 2; index++) {
    if (plan.inner[index] != MIR_NONE) {
      plan.inner[index] = mir_ty_unscoped(plan.inner[index]) | scope << MIR_SCOPE_SHIFT;
    }
  }
  return plan;
}

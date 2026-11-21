/* compiler/mir/mir_glue_types.c: the type queries glue asks: what a drop of a type drops, whether that
 * recurses, how big its block is, and whether glue is made for it. */
#include "compiler/mir/mir_glue_internal.h"

bool mirgl_is_opt(const MirModule *module, MirTy ty, MirTy *inner) {
  const MirTyData *data = mir_ty_data(module, ty);
  if (data->kind != MK_OPT) {
    return false;
  }
  *inner = data->elem;
  return true;
}

MirTy mirgl_elem(const MirModule *module, MirTy ty, bool seq) {
  const MirTyData *data = mir_ty_data(module, ty);
  if (data->kind == MK_LIST) {
    return data->elem;
  }
  return seq && data->kind == MK_BYTES ? MIR_UINT8 : MIR_NONE;
}

static void children_of_alt(const MirModule *module, uint32_t alt, MirTyList *out) {
  const MirAltDef *def = &module->alts.ptr[alt];
  for (uint32_t index = 0; index < def->ncases; index++) {
    if (mir_owns(def->borrowed, index)) {
      continue;
    }
    for (uint32_t field = 0; field < def->cases[index].nfields; field++) {
      mir_tylist_push(out, def->cases[index].fields[field].ty);
    }
  }
}

void mirgl_children(const MirModule *module, MirTy ty, MirTyList *out) {
  const MirTyData *data = mir_ty_data(module, ty);
  switch ((MirTyKind)data->kind) {
  case MK_OPT:
  case MK_LIST:
    mir_tylist_push(out, data->elem);
    return;
  case MK_OBJ:
    for (uint32_t index = 0; index < data->nargs && mir_ty_is_map_or_set(module, ty); index++) {
      mir_tylist_push(out, data->args[index]);
    }
    return;
  case MK_TYPE: {
    const MirTypeDef *def = &module->type_defs.ptr[data->id];
    for (uint32_t index = 0; index < def->nfields; index++) {
      mir_tylist_push(out, def->fields[index].ty);
    }
    return;
  }
  case MK_ALT:
    children_of_alt(module, data->id, out);
    return;
  default:
    return;
  }
}

bool mirgl_recurses(const MirModule *module, MirTy ty) {
  MsArena scratch = ms_arena_new();
  MirTyList todo = {0};
  MirBits seen = mir_bits_new(&scratch, (uint32_t)module->types.kinds.len);
  mirgl_children(module, ty, &todo);
  bool found = false;
  while (todo.len > 0 && !found) {
    const MirTy next = todo.ptr[--todo.len];
    found = next == ty;
    if (!found && !mir_bits_test(&seen, mir_ty_unscoped(next))) {
      mir_bits_set(&seen, mir_ty_unscoped(next));
      mirgl_children(module, next, &todo);
    }
  }
  mir_tylist_free(&todo);
  ms_arena_free(&scratch);
  return found;
}

uint32_t mirgl_mem_size(const MirModule *module, MirTy ty) {
  MirLayouts layouts;
  mir_layouts_init(&layouts, module);
  const uint32_t size = mir_type_mem(&layouts, ty).size;
  mir_layouts_free(&layouts);
  return size;
}

bool mirgl_alt_boxed(const MirModule *module, uint32_t alt) {
  MirLayouts layouts;
  mir_layouts_init(&layouts, module);
  const bool boxed = mir_layouts_alt_boxed(&layouts, alt);
  mir_layouts_free(&layouts);
  return boxed;
}

bool mirgl_opt_boxed(const MirModule *module, MirTy inner) {
  MirLayouts layouts;
  mir_layouts_init(&layouts, module);
  const bool boxed = mir_layouts_opt_boxed(&layouts, inner);
  mir_layouts_free(&layouts);
  return boxed;
}

bool mirgl_eligible(const MirModule *module, MirLayouts *layouts, MirTy ty) {
  const MirTyData *data = mir_ty_data(module, ty);
  bool kind = false;
  switch ((MirTyKind)data->kind) {
  case MK_TYPE:
  case MK_ALT:
  case MK_LIST:
  case MK_BYTES:
  case MK_IFACE:
    kind = true;
    break;
  case MK_OPT:
    /* A present flag and the payload's leaves, or a box; the other layouts are one pointer. */
    kind = (mir_layouts_opt_boxed(layouts, data->elem) || !mir_opt_is_nullable(layouts, data->elem)) &&
           !mir_is_str_like(layouts, ty);
    break;
  case MK_OBJ:
    kind = mir_ty_is_map_or_set(module, ty);
    break;
  default:
    break;
  }
  return kind && mir_needs_drop(module, ty);
}

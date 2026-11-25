/* compiler/mir/mir_layout.c: the layouts built on the shapes: alternative fields, heap blocks of records,
 * closure objects, and the pointer and boolean flags the LLVM emitter reads. Kept in the MirLayouts arena. */
#include "compiler/mir/mir_analysis.h"
#include "compiler/mir/mir_layout_internal.h"

/* ---- alternatives ---- */

static uint32_t total_fields(const MirAltDef *def) {
  uint32_t count = 0;
  for (uint32_t index = 0; index < def->ncases; index++) {
    count += def->cases[index].nfields;
  }
  return count;
}

static void fill_alt_fields(MirLayouts *layouts, const MirAltDef *def, const MirShape *shape,
                            uint32_t *case_start, MirAltField *fields) {
  uint32_t next = 0;
  for (uint32_t index = 0; index < def->ncases && shape->slot_start != NULL; index++) {
    case_start[index] = next;
    uint32_t at = shape->slot_start[index];
    for (uint32_t field = 0; field < def->cases[index].nfields; field++) {
      const MirTy field_ty = def->cases[index].fields[field].ty;
      const uint32_t width = (uint32_t)mir_leaves(layouts, field_ty).len;
      fields[next++] = (MirAltField){.ty = field_ty, .leaves = shape->slots + at, .nleaves = width};
      at += width;
    }
  }
  case_start[def->ncases] = next;
}

const MirAltFields *mir_alt_fields(MirLayouts *layouts, uint32_t alt) {
  static const MirAltFields none = {0};
  if (alt >= layouts->module->alts.len) {
    layouts->failed = true;
    return &none;
  }
  if (layouts->alt_fields_state[alt] != 0) {
    return &layouts->alt_fields[alt];
  }
  const MirTyData key = {.kind = MK_ALT, .id = alt};
  MirTy ty = 0;
  if (!mir_ty_find(layouts->module, &key, &ty)) {
    layouts->failed = true;
    return &none;
  }
  const MirShape *shape = mir_shape(layouts, ty);
  const MirAltDef *def = &layouts->module->alts.ptr[alt];
  uint32_t *case_start = MS_ARENA_NEW_ARRAY(&layouts->arena, uint32_t, (size_t)def->ncases + 1);
  MirAltField *fields = MS_ARENA_NEW_ARRAY(&layouts->arena, MirAltField, (size_t)total_fields(def) + 1);
  fill_alt_fields(layouts, def, shape, case_start, fields);
  layouts->alt_fields[alt] = (MirAltFields){case_start, fields, def->ncases};
  layouts->alt_fields_state[alt] = 1;
  return &layouts->alt_fields[alt];
}

bool mir_alt_slot_source(const MirAltFields *fields, uint32_t case_index, uint32_t slot, uint32_t *operand,
                         uint32_t *leaf) {
  const uint32_t first = fields->case_start[case_index];
  for (uint32_t field = first; field < fields->case_start[case_index + 1]; field++) {
    for (uint32_t index = 0; index < fields->fields[field].nleaves; index++) {
      if (fields->fields[field].leaves[index] == slot) {
        *operand = field - first;
        *leaf = index;
        return true;
      }
    }
  }
  return false;
}

bool mir_opt_has_flag(MirLayouts *layouts, MirTy opt) {
  const MirTy inner = mir_ty_data(layouts->module, opt)->elem;
  return !mir_layouts_opt_boxed(layouts, inner) && !mir_opt_is_nullable(layouts, inner) &&
         !mir_is_str_like(layouts, opt);
}

bool mir_boxed_block_size(MirLayouts *layouts, MirTy ty, uint32_t *size) {
  const MirShape *shape = mir_shape(layouts, ty);
  if (shape->alt != MIR_ALT_BOXED) {
    return false;
  }
  *size = mir_mem_layout(shape->block, NULL).size;
  return true;
}

/* ---- record blocks ---- */

/* The leaves of the heap block behind indirect type `type_id`: its fields' leaves in order, except that a map
 * or set field is one pointer to a header block that exists only while the collection is not the all-zero
 * empty value. */
static MsSpan mir_type_block(MirLayouts *layouts, uint32_t type_id) {
  const MirTypeDef *def = &layouts->module->type_defs.ptr[type_id];
  MirLeafList list = {0};
  for (uint32_t index = 0; index < def->nfields; index++) {
    const MsSpan leaves = mir_type_field_boxed(layouts, def->fields[index].ty)
                              ? mir_layout_one_word()
                              : mir_leaves(layouts, def->fields[index].ty);
    mir_layout_append(layouts, &list, leaves);
  }
  const MsSpan span = mir_layout_keep(layouts, &list);
  mir_leaf_list_free(&list);
  return span;
}

MirRecordBlock mir_record_block(MirLayouts *layouts, uint32_t type_id) {
  MsArena *arena = &layouts->arena;
  MirRecordBlock block = {.def = &layouts->module->type_defs.ptr[type_id]};
  block.leaves = mir_type_block(layouts, type_id);
  uint32_t *offsets = MS_ARENA_NEW_ARRAY(arena, uint32_t, block.leaves.len + 1);
  uint32_t *starts = MS_ARENA_NEW_ARRAY(arena, uint32_t, (size_t)block.def->nfields + 1);
  bool *boxed = MS_ARENA_NEW_ARRAY(arena, bool, (size_t)block.def->nfields + 1);
  block.size = mir_mem_layout(block.leaves, offsets).size;
  uint32_t at = 0;
  for (uint32_t index = 0; index < block.def->nfields; index++) {
    starts[index] = at;
    boxed[index] = mir_type_field_boxed(layouts, block.def->fields[index].ty);
    at += boxed[index] ? 1 : (uint32_t)mir_leaves(layouts, block.def->fields[index].ty).len;
  }
  block.offsets = offsets;
  block.starts = starts;
  block.boxed = boxed;
  return block;
}

uint32_t mir_field_offset(MirLayouts *layouts, uint32_t type_id, uint32_t field) {
  const MirTypeDef *def = &layouts->module->type_defs.ptr[type_id];
  MirLeafList all = {0};
  uint32_t start = 0;
  for (uint32_t index = 0; index < def->nfields; index++) {
    if (index == field) {
      start = (uint32_t)all.len;
    }
    mir_layout_append(layouts, &all, mir_leaves(layouts, def->fields[index].ty));
  }
  uint32_t offset = 0;
  if (start < all.len) {
    uint32_t *offsets = MS_ARENA_NEW_ARRAY(&layouts->arena, uint32_t, all.len);
    (void)mir_mem_layout(ms_span_of(all.ptr, all.len), offsets);
    offset = offsets[start];
  }
  mir_leaf_list_free(&all);
  return offset;
}

uint32_t mir_list_elem_size(MirLayouts *layouts, MirTy list) {
  return mir_type_mem(layouts, mir_ty_data(layouts->module, list)->elem).size;
}

/* ---- closures ---- */

MirClosureLayout mir_closure_layout(MirLayouts *layouts, const MirFunc *func) {
  const uint32_t count = func->kind == MFK_CLOSURE ? func->ncaptures : 0;
  MirCaptureSlot *slots = MS_ARENA_NEW_ARRAY(&layouts->arena, MirCaptureSlot, (size_t)count + 1);
  uint64_t offset = MIR_CLOSURE_CAPTURES_OFFSET;
  for (uint32_t index = 0; index < count; index++) {
    const MsSpan leaves = mir_leaves(layouts, func->captures[index]);
    const MirMemLayout mem = mir_mem_layout(leaves, NULL);
    offset = (offset + mem.align - 1) / mem.align * mem.align;
    slots[index] = (MirCaptureSlot){.ty = func->captures[index], .offset = (uint32_t)offset, .leaves = leaves};
    offset += mem.size;
    if (offset > UINT32_MAX / 2) {
      layouts->failed = true;
      offset = UINT32_MAX / 2;
    }
  }
  return (MirClosureLayout){.captures = slots, .ncaptures = count, .size = (uint32_t)((offset + 7) / 8 * 8)};
}

/* ---- pointer and boolean flags ---- */

static void leaf_flags(MirLayouts *layouts, MirTy ty, bool pointers, MirLeafList *out);

static void flag_run(MirLeafList *out, bool value, uint32_t count) {
  for (uint32_t index = 0; index < count; index++) {
    mir_leaf_list_push(out, value ? 1 : 0);
  }
}

static void field_flags(MirLayouts *layouts, const MirField *fields, uint32_t count, bool pointers,
                        MirLeafList *out) {
  for (uint32_t index = 0; index < count; index++) {
    leaf_flags(layouts, fields[index].ty, pointers, out);
  }
}

/* Whether a value of this type is one pointer word. */
static bool is_one_pointer(MirLayouts *layouts, const MirTyData *data) {
  const MirModule *module = layouts->module;
  switch ((MirTyKind)data->kind) {
  case MK_PTR: case MK_FN:
    return true;
  case MK_OBJ:
    return !mir_layout_is_map_or_set(data);
  case MK_TYPE:
    return module->type_defs.ptr[data->id].indirect;
  case MK_OPT:
    return mir_opt_is_nullable(layouts, data->elem);
  case MK_ALT:
    return mir_boxing_alt(&layouts->boxing, data->id);
  case MK_VOID: case MK_BOOL: case MK_INT: case MK_FLOAT: case MK_INT8: case MK_INT16: case MK_INT32:
  case MK_FLOAT32: case MK_UINT8: case MK_UINT16: case MK_UINT32: case MK_UINT64: case MK_STR:
  case MK_BYTES: case MK_LIST: case MK_IFACE:
    return false;
  }
  return false;
}

/* Appends one flag per register leaf of `ty`: a pointer (when `pointers`) or a boolean. */
static void leaf_flags_inner(MirLayouts *layouts, MirTy ty, bool pointers, MirLeafList *out) {
  const MirModule *module = layouts->module;
  const MirTyData *data = mir_ty_data(module, ty);
  const uint32_t width = (uint32_t)mir_leaves(layouts, ty).len;
  if (data->kind == MK_BOOL) {
    flag_run(out, !pointers, 1);
  } else if (is_one_pointer(layouts, data)) {
    flag_run(out, pointers, 1);
  } else if (data->kind == MK_IFACE) {
    flag_run(out, pointers, 2);
  } else if (data->kind == MK_BYTES || data->kind == MK_LIST) {
    flag_run(out, pointers, 1);
    flag_run(out, false, 2);
  } else if (data->kind == MK_TYPE) {
    const MirTypeDef *def = &module->type_defs.ptr[data->id];
    field_flags(layouts, def->fields, def->nfields, pointers, out);
  } else if (data->kind == MK_OPT && !mir_is_str_like(layouts, ty)) {
    flag_run(out, !pointers, 1);
    leaf_flags(layouts, data->elem, pointers, out);
  } else {
    flag_run(out, false, width);
  }
}

static void leaf_flags(MirLayouts *layouts, MirTy ty, bool pointers, MirLeafList *out) {
  if (layouts->depth >= MIR_LAYOUT_MAX_DEPTH) {
    layouts->failed = true;
    return;
  }
  layouts->depth++;
  leaf_flags_inner(layouts, ty, pointers, out);
  layouts->depth--;
}

bool mir_rt_direct(const MirModule *module, MirLayouts *layouts, MirTy ty) {
  const MirTyData *data = mir_ty_data(module, ty);
  switch ((MirTyKind)data->kind) {
  case MK_VOID: case MK_BOOL: case MK_INT: case MK_INT8: case MK_INT16: case MK_INT32:
  case MK_UINT8: case MK_UINT16: case MK_UINT32: case MK_UINT64: case MK_FLOAT:
  case MK_FLOAT32: case MK_PTR: case MK_FN: case MK_IFACE:
    return true;
  case MK_OBJ:
    return data->obj_class != MIR_OBJ_COLLECTION;
  case MK_OPT:
    return mir_opt_is_nullable(layouts, data->elem) || mir_is_scalar(module, data->elem);
  case MK_STR: case MK_BYTES: case MK_TYPE: case MK_ALT: case MK_LIST:
    return false;
  }
  return false;
}

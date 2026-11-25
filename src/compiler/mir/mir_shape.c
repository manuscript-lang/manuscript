/* compiler/mir/mir_shape.c: the flattened shape of every type: its register leaves, the payload slots of
 * alternatives, and the memory layout of a leaf sequence. Everything is computed on first ask and kept in the
 * MirLayouts arena, which owns it. */
#include "compiler/mir/mir_layout_internal.h"

static const MirLeaf no_leaves[1] = {MIR_LEAF_I64};
static const MirLeaf one_word[1] = {MIR_LEAF_I64};
static const MirShape empty_shape = {0};

/* Payload slots of an alternative are shared per leaf kind, widest first so each stays aligned. */
static const MirLeaf slot_kinds[MIR_LEAF_COUNT] = {MIR_LEAF_I64, MIR_LEAF_F64, MIR_LEAF_F32, MIR_LEAF_N32,
                                                   MIR_LEAF_U32, MIR_LEAF_N16, MIR_LEAF_U16, MIR_LEAF_N8,
                                                   MIR_LEAF_U8,  MIR_LEAF_I8};

uint32_t mir_leaf_size(MirLeaf leaf) {
  switch (leaf) {
  case MIR_LEAF_I8: case MIR_LEAF_N8: case MIR_LEAF_U8:
    return 1;
  case MIR_LEAF_N16: case MIR_LEAF_U16:
    return 2;
  case MIR_LEAF_N32: case MIR_LEAF_U32: case MIR_LEAF_F32:
    return 4;
  default:
    return 8;
  }
}

MirMemLayout mir_mem_layout(MsSpan leaves, uint32_t *offsets) {
  uint64_t offset = 0;
  uint32_t align = 1;
  for (size_t index = 0; index < leaves.len; index++) {
    const uint32_t width = mir_leaf_size(leaves.ptr[index]);
    if (width > align) {
      align = width;
    }
    offset = (offset + width - 1) / width * width;
    if (offsets != NULL) {
      offsets[index] = (uint32_t)offset;
    }
    offset += width;
  }
  return (MirMemLayout){.size = (uint32_t)((offset + align - 1) / align * align), .align = align};
}

void mir_layouts_init(MirLayouts *layouts, const MirModule *module) {
  *layouts = (MirLayouts){.module = module, .arena = ms_arena_new()};
  mir_boxing_init(&layouts->boxing, module);
  const size_t ntypes = module->types.kinds.len + 1;
  const size_t nalts = module->alts.len + 1;
  MsArena *arena = &layouts->arena;
  layouts->shapes = MS_ARENA_NEW_ARRAY(arena, MirShape, ntypes);
  layouts->state = MS_ARENA_NEW_ARRAY(arena, uint8_t, ntypes);
  layouts->pointer_marks = MS_ARENA_NEW_ARRAY(arena, const bool *, ntypes);
  layouts->bool_marks = MS_ARENA_NEW_ARRAY(arena, const bool *, ntypes);
  layouts->alt_fields = MS_ARENA_NEW_ARRAY(arena, MirAltFields, nalts);
  layouts->alt_fields_state = MS_ARENA_NEW_ARRAY(arena, uint8_t, nalts);
}

void mir_layouts_free(MirLayouts *layouts) {
  mir_boxing_free(&layouts->boxing);
  ms_arena_free(&layouts->arena);
  *layouts = (MirLayouts){0};
}

bool mir_layouts_alt_boxed(MirLayouts *layouts, uint32_t alt) {
  return mir_boxing_alt(&layouts->boxing, alt);
}

bool mir_layouts_opt_boxed(MirLayouts *layouts, MirTy inner) {
  return mir_boxing_opt(&layouts->boxing, inner);
}

/* ---- leaf lists ---- */

void mir_layout_append(MirLayouts *layouts, MirLeafList *list, MsSpan leaves) {
  if (list->len + leaves.len > MIR_LAYOUT_MAX_LEAVES) {
    layouts->failed = true;
    return;
  }
  MirLeaf *room = mir_leaf_list_extend(list, leaves.len);
  if (leaves.len != 0) {
    __builtin_memcpy(room, leaves.ptr, leaves.len);
  }
}

MsSpan mir_layout_keep(MirLayouts *layouts, const MirLeafList *list) {
  if (list->len == 0) {
    return ms_span_of(no_leaves, 0);
  }
  return ms_arena_copy(&layouts->arena, ms_span_of(list->ptr, list->len));
}

MsSpan mir_layout_one_word(void) {
  return ms_span_of(one_word, 1);
}

static MirShape plain_shape(MsSpan leaves) {
  return (MirShape){.leaves = leaves};
}

bool mir_layout_is_map_or_set(const MirTyData *data) {
  return data->kind == MK_OBJ && data->obj_class == MIR_OBJ_COLLECTION;
}

bool mir_ty_is_map_or_set(const MirModule *module, MirTy ty) {
  return mir_layout_is_map_or_set(mir_ty_data(module, ty));
}

bool mir_type_field_boxed(const MirLayouts *layouts, MirTy field_ty) {
  return mir_ty_is_map_or_set(layouts->module, field_ty);
}

bool mir_is_str_like(const MirLayouts *layouts, MirTy ty) {
  const MirTyData *data = mir_ty_data(layouts->module, ty);
  if (data->kind == MK_STR) {
    return true;
  }
  return data->kind == MK_OPT && mir_ty_data(layouts->module, data->elem)->kind == MK_STR;
}

bool mir_opt_is_nullable(MirLayouts *layouts, MirTy inner) {
  if (mir_boxing_opt(&layouts->boxing, inner)) {
    return true;
  }
  const MirTyData *data = mir_ty_data(layouts->module, inner);
  return data->kind == MK_FN || (data->kind == MK_OBJ && !mir_layout_is_map_or_set(data));
}

/* ---- shapes ---- */

MsSpan mir_leaves(MirLayouts *layouts, MirTy ty) {
  return mir_shape(layouts, ty)->leaves;
}

/* The leaves of each field of a record, one after another. */
static MirShape record_shape(MirLayouts *layouts, const MirField *fields, uint32_t count) {
  MirLeafList list = {0};
  for (uint32_t index = 0; index < count; index++) {
    mir_layout_append(layouts, &list, mir_leaves(layouts, fields[index].ty));
  }
  const MirShape shape = plain_shape(mir_layout_keep(layouts, &list));
  mir_leaf_list_free(&list);
  return shape;
}

static MirShape optional_shape(MirLayouts *layouts, MirTy ty, MirTy inner) {
  static const MirLeaf two_words[2] = {MIR_LEAF_I64, MIR_LEAF_I64};
  if (mir_opt_is_nullable(layouts, inner)) {
    return plain_shape(mir_layout_one_word());
  }
  if (mir_is_str_like(layouts, ty)) {
    return plain_shape(ms_span_of(two_words, 2));
  }
  MirLeafList list = {0};
  mir_leaf_list_push(&list, MIR_LEAF_I8);
  mir_layout_append(layouts, &list, mir_leaves(layouts, inner));
  const MirShape shape = plain_shape(mir_layout_keep(layouts, &list));
  mir_leaf_list_free(&list);
  return shape;
}

/* The shape of a scalar or fixed-size type, or false when the kind needs more than its tag. */
static bool fixed_shape(const MirTyData *data, MirShape *out) {
  static const MirLeaf scalar[MK_PTR + 1] = {
      [MK_BOOL] = MIR_LEAF_I8,     [MK_INT] = MIR_LEAF_I64,    [MK_FLOAT] = MIR_LEAF_F64,
      [MK_INT8] = MIR_LEAF_N8,     [MK_INT16] = MIR_LEAF_N16,  [MK_INT32] = MIR_LEAF_N32,
      [MK_FLOAT32] = MIR_LEAF_F32, [MK_UINT8] = MIR_LEAF_U8,   [MK_UINT16] = MIR_LEAF_U16,
      [MK_UINT32] = MIR_LEAF_U32,  [MK_UINT64] = MIR_LEAF_I64, [MK_PTR] = MIR_LEAF_I64};
  static const MirLeaf words[MIR_MAP_WORDS] = {MIR_LEAF_I64, MIR_LEAF_I64, MIR_LEAF_I64, MIR_LEAF_I64,
                                               MIR_LEAF_I64, MIR_LEAF_I64, MIR_LEAF_I64};
  switch ((MirTyKind)data->kind) {
  case MK_VOID:
    *out = plain_shape(ms_span_of(no_leaves, 0));
    return true;
  case MK_STR: case MK_IFACE:
    *out = plain_shape(ms_span_of(words, 2));
    return true;
  case MK_BYTES: case MK_LIST:
    *out = plain_shape(ms_span_of(words, 3));
    return true;
  case MK_FN:
    *out = plain_shape(mir_layout_one_word());
    return true;
  case MK_OBJ:
    *out = plain_shape(ms_span_of(words, mir_layout_is_map_or_set(data) ? MIR_MAP_WORDS : 1));
    return true;
  case MK_BOOL: case MK_INT: case MK_FLOAT: case MK_INT8: case MK_INT16: case MK_INT32:
  case MK_FLOAT32: case MK_UINT8: case MK_UINT16: case MK_UINT32: case MK_UINT64: case MK_PTR:
    *out = plain_shape(ms_span_of(&scalar[data->kind], 1));
    return true;
  case MK_TYPE: case MK_ALT: case MK_OPT:
    return false;
  }
  return false;
}

static uint32_t slot_kind(MirLeaf leaf) {
  for (uint32_t kind = 0; kind < MIR_LEAF_COUNT; kind++) {
    if (slot_kinds[kind] == leaf) {
      return kind;
    }
  }
  return 0;
}

/* The leaves of every case's fields, one span per case. */
static MsSpan *case_leaves(MirLayouts *layouts, const MirAltDef *def) {
  MsSpan *cases = MS_ARENA_NEW_ARRAY(&layouts->arena, MsSpan, (size_t)def->ncases + 1);
  for (uint32_t index = 0; index < def->ncases; index++) {
    cases[index] = record_shape(layouts, def->cases[index].fields, def->cases[index].nfields).leaves;
  }
  return cases;
}

/* The most slots of each kind any one case needs; also the total leaf count. */
static uint32_t widest_cases(const MsSpan *cases, uint32_t ncases, uint32_t *most) {
  uint32_t total = 0;
  for (uint32_t index = 0; index < ncases; index++) {
    uint32_t seen[MIR_LEAF_COUNT] = {0};
    for (size_t leaf = 0; leaf < cases[index].len; leaf++) {
      const uint32_t kind = slot_kind(cases[index].ptr[leaf]);
      if (++seen[kind] > most[kind]) {
        most[kind] = seen[kind];
      }
    }
    total += (uint32_t)cases[index].len;
  }
  return total;
}

/* Fills in the block (tag, then each kind's slots) and the slot index of every payload leaf. */
static void assign_slots(MirLayouts *layouts, const MsSpan *cases, uint32_t ncases, MirShape *shape) {
  uint32_t most[MIR_LEAF_COUNT] = {0};
  const uint32_t total = widest_cases(cases, ncases, most);
  MirLeafList block = {0};
  mir_leaf_list_push(&block, MIR_LEAF_I64); /* the tag */
  uint32_t next[MIR_LEAF_COUNT] = {0};
  for (uint32_t kind = 0; kind < MIR_LEAF_COUNT; kind++) {
    next[kind] = (uint32_t)block.len;
    for (uint32_t count = 0; count < most[kind]; count++) {
      mir_leaf_list_push(&block, slot_kinds[kind]);
    }
  }
  uint32_t *start = MS_ARENA_NEW_ARRAY(&layouts->arena, uint32_t, (size_t)ncases + 1);
  uint32_t *slots = MS_ARENA_NEW_ARRAY(&layouts->arena, uint32_t, (size_t)total + 1);
  uint32_t at = 0;
  for (uint32_t index = 0; index < ncases; index++) {
    uint32_t cursor[MIR_LEAF_COUNT];
    __builtin_memcpy(cursor, next, sizeof cursor);
    start[index] = at;
    for (size_t leaf = 0; leaf < cases[index].len; leaf++) {
      slots[at++] = cursor[slot_kind(cases[index].ptr[leaf])]++;
    }
  }
  start[ncases] = at;
  shape->slot_start = start;
  shape->slots = slots;
  shape->block = mir_layout_keep(layouts, &block);
  mir_leaf_list_free(&block);
}

static MirShape alt_shape(MirLayouts *layouts, uint32_t alt) {
  const MirAltDef *def = &layouts->module->alts.ptr[alt];
  const MsSpan *cases = case_leaves(layouts, def);
  MirShape shape = {0};
  assign_slots(layouts, cases, def->ncases, &shape);
  if (mir_boxing_alt(&layouts->boxing, alt)) {
    shape.alt = MIR_ALT_BOXED;
    shape.leaves = mir_layout_one_word();
  } else {
    shape.alt = MIR_ALT_INLINE;
    shape.leaves = shape.block;
    shape.block = ms_span_of(no_leaves, 0);
  }
  return shape;
}

static MirShape compute_shape(MirLayouts *layouts, MirTy ty) {
  const MirModule *module = layouts->module;
  const MirTyData *data = mir_ty_data(module, ty);
  MirShape shape = {0};
  if (fixed_shape(data, &shape)) {
    return shape;
  }
  switch ((MirTyKind)data->kind) {
  case MK_TYPE: {
    const MirTypeDef *def = &module->type_defs.ptr[data->id];
    return def->indirect ? plain_shape(mir_layout_one_word()) : record_shape(layouts, def->fields, def->nfields);
  }
  case MK_OPT:
    return optional_shape(layouts, ty, data->elem);
  case MK_ALT:
    return alt_shape(layouts, data->id);
  case MK_VOID: case MK_BOOL: case MK_INT: case MK_FLOAT: case MK_INT8: case MK_INT16: case MK_INT32:
  case MK_FLOAT32: case MK_UINT8: case MK_UINT16: case MK_UINT32: case MK_UINT64: case MK_STR:
  case MK_BYTES: case MK_PTR: case MK_LIST: case MK_OBJ: case MK_FN: case MK_IFACE:
    break;
  }
  return shape;
}

const MirShape *mir_shape(MirLayouts *layouts, MirTy ty) {
  if (ty >= layouts->module->types.kinds.len || layouts->depth >= MIR_LAYOUT_MAX_DEPTH) {
    layouts->failed = true;
    return &empty_shape;
  }
  if (layouts->state[ty] != 0) {
    return &layouts->shapes[ty];
  }
  layouts->depth++;
  const MirTyData *data = mir_ty_data(layouts->module, ty);
  if (data->kind == MK_ALT && mir_boxing_alt(&layouts->boxing, data->id)) {
    /* A boxed alternative is one pointer; this also ends the recursion through its own fields. */
    layouts->shapes[ty] = plain_shape(mir_layout_one_word());
    layouts->state[ty] = 1;
  }
  layouts->shapes[ty] = compute_shape(layouts, ty);
  layouts->state[ty] = 1;
  layouts->depth--;
  return &layouts->shapes[ty];
}

MirMemLayout mir_type_mem(MirLayouts *layouts, MirTy ty) {
  return mir_mem_layout(mir_leaves(layouts, ty), NULL);
}

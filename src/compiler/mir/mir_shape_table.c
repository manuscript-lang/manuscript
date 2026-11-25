/* compiler/mir/mir_shape_table.c: the ShapeTable (abi/shape.h) of a type, as static data. A `shape` instruction
 * names a type; MIR builds one read-only image of its shapes, members and names, a hook array that gives the
 * collection shapes their descriptors, and the three-word table that points at both. The runtime's generic
 * natives (the text form of a value, `repr`, JSON) walk the value through that table. */
#include "abi/shape.h"
#include "compiler/mir/mir_data_internal.h"
#include "compiler/mir/mir_json_tree.h"

MS_LIST_DEFINE(ShapeList, shape_list, MsShape)
MS_LIST_DEFINE(MemberList, member_list, MsShapeMember)
MS_LIST_DEFINE(ByteList, byte_list, uint8_t)

typedef struct ShapeBuild {
  const MirModule *module;
  MirLayouts *layouts;
  MsArena arena; /* the scratch tables of one build */
  ShapeList shapes;
  MemberList members;
  ByteList strings;
  MirTyList types; /* the type of each shape, by shape number */
} ShapeBuild;

MirRef mir_data_shape(const MirData *data, MirTy ty) {
  const MirRef *found = mir_desc_map_get(&data->shapes, ty);
  return found != NULL ? *found : (MirRef){.kind = MREF_RUNTIME};
}

static uint32_t add_name(ShapeBuild *build, MsSpan text) {
  const uint32_t at = (uint32_t)build->strings.len;
  for (size_t index = 0; index < text.len; index++) {
    byte_list_push(&build->strings, text.ptr[index]);
  }
  byte_list_push(&build->strings, 0);
  return at;
}

static uint32_t add_mir_name(ShapeBuild *build, MsName name) {
  return add_name(build, ms_names_span(&build->module->names, name));
}

/* A type's name without its type arguments: `Pair[Int, Int]` is shown as `Pair`. */
static uint32_t add_type_name(ShapeBuild *build, MsName name) {
  MsSpan text = ms_names_span(&build->module->names, name);
  for (size_t at = 0; at < text.len; at++) {
    if (text.ptr[at] == '[') {
      text.len = at;
      break;
    }
  }
  return add_name(build, text);
}

static MsShape scalar(MsShapeKind kind, uint32_t size) {
  return (MsShape){.kind = (uint8_t)kind, .align = (uint16_t)(size == 0 ? 1 : (size > 8 ? 8 : size)), .size = size,
                   .name = MS_SHAPE_NONE, .first = MS_SHAPE_NONE, .elem = MS_SHAPE_NONE,
                   .value = MS_SHAPE_NONE, .extra = MS_SHAPE_NONE};
}

static uint32_t shape_of(ShapeBuild *build, MirTy ty);

/* The scalar and string-like kinds, which have no parts. */
static bool plain_shape(const MirTyData *data, MsShape *out) {
  switch ((MirTyKind)data->kind) {
  case MK_VOID: *out = scalar(MS_SHAPE_VOID, 0); return true;
  case MK_BOOL: *out = scalar(MS_SHAPE_BOOL, 1); return true;
  case MK_INT: *out = scalar(MS_SHAPE_INT, 8); return true;
  case MK_INT8: *out = scalar(MS_SHAPE_INT, 1); return true;
  case MK_INT16: *out = scalar(MS_SHAPE_INT, 2); return true;
  case MK_INT32: *out = scalar(MS_SHAPE_INT, 4); return true;
  case MK_UINT8: *out = scalar(MS_SHAPE_UINT, 1); return true;
  case MK_UINT16: *out = scalar(MS_SHAPE_UINT, 2); return true;
  case MK_UINT32: *out = scalar(MS_SHAPE_UINT, 4); return true;
  case MK_UINT64: *out = scalar(MS_SHAPE_UINT, 8); return true;
  case MK_FLOAT: *out = scalar(MS_SHAPE_FLOAT, 8); return true;
  case MK_FLOAT32: *out = scalar(MS_SHAPE_FLOAT, 4); return true;
  case MK_STR: *out = scalar(MS_SHAPE_STRING, 16); return true;
  case MK_FN: *out = scalar(MS_SHAPE_FUNCTION, 8); return true;
  case MK_PTR:
  case MK_IFACE: *out = scalar(MS_SHAPE_OPAQUE, 8); return true;
  default: return false;
  }
}

static void fill_slot(ShapeBuild *build, MsShape *shape, MirTy ty) {
  const MirMemLayout mem = mir_type_mem(build->layouts, ty);
  shape->size = mem.size;
  shape->align = (uint16_t)mem.align;
}

static void optional_shape(ShapeBuild *build, MirTy ty, const MirTyData *data, MsShape *shape) {
  MirLayouts *layouts = build->layouts;
  shape->kind = MS_SHAPE_OPTIONAL;
  fill_slot(build, shape, ty);
  if (mir_opt_has_flag(layouts, ty)) {
    /* A presence byte at 0, then the payload leaves. */
    const MsSpan leaves = mir_leaves(layouts, ty);
    uint32_t offsets[64] = {0};
    if (leaves.len > 1 && leaves.len <= 64) {
      (void)mir_mem_layout(leaves, offsets);
      shape->extra = offsets[1];
    } else {
      shape->extra = 8;
    }
  } else {
    shape->flags |= MS_SHAPE_NULLABLE | (mir_layouts_opt_boxed(layouts, data->elem) ? MS_SHAPE_HEAP_PAYLOAD : 0);
  }
  shape->elem = MS_SHAPE_NONE;
  (void)data;
}

static uint32_t embed_shape(ShapeBuild *build, uint32_t shape_index, const uint32_t *abs, size_t n);

/* A copy of shape `original`, the shape of the same type, that the image keeps beside it. */
static uint32_t push_copy(ShapeBuild *build, uint32_t original, MsShape copy) {
  const uint32_t index = (uint32_t)build->shapes.len;
  shape_list_push(&build->shapes, copy);
  mir_tylist_push(&build->types, build->types.ptr[original]); /* the original, found first, stays the one a type maps to */
  return index;
}

/* A value inside a flattened image (an optional's payload, a case's field, a field of a record that sits there) has
 * its leaves where the host puts them, which is not where its own layout does when the leaves before it differ in
 * size: `{x Bool, y Int}` is at 0 and 8 alone and at 1 and 8 after a tag byte. `abs` holds the host offset of each of
 * the value's `n` leaves; the result is `shape_index` when every offset agrees with the shape's own, and otherwise a
 * copy whose offsets are relative to `abs[0]`, so a reader that adds them to the slot finds the leaves. */
static uint32_t embed_optional(ShapeBuild *build, uint32_t shape_index, const uint32_t *abs, size_t n) {
  const MsShape shape = build->shapes.ptr[shape_index];
  if ((shape.flags & MS_SHAPE_NULLABLE) != 0 || n < 2) {
    return shape_index;
  }
  MsShape copy = shape;
  copy.extra = abs[1] - abs[0];
  copy.elem = embed_shape(build, shape.elem, abs + 1, n - 1);
  if (copy.extra == shape.extra && copy.elem == shape.elem) {
    return shape_index;
  }
  return push_copy(build, shape_index, copy);
}

/* Places the fields of record `def` whose leaves lie at `abs` (`n` of them): fills `offsets` (from `abs[0]`) and `kids`
 * (each field's shape, embedded likewise). `old_first` is the member run of the shape being copied, or MS_SHAPE_NONE when
 * the record's own shape is being built; for a copy, `*changed` is set when a field moved. `counts[i]` is the number of
 * leaves of field `i`. Returns how many leaves the fields cover. */
static uint32_t embed_fields(ShapeBuild *build, const MirTypeDef *def, uint32_t old_first, const uint32_t *abs,
                             size_t n, const uint32_t *counts, uint32_t *offsets, uint32_t *kids, bool *changed) {
  uint32_t start = 0;
  for (uint32_t index = 0; index < def->nfields; index++) {
    const uint32_t leaves = counts[index];
    const uint32_t old_shape = old_first == MS_SHAPE_NONE ? shape_of(build, def->fields[index].ty)
                                                          : build->members.ptr[old_first + index].shape;
    const bool placed = start + leaves <= n && leaves > 0;
    offsets[index] = placed ? abs[start] - abs[0] : (old_first == MS_SHAPE_NONE ? 0 : build->members.ptr[old_first + index].offset);
    kids[index] = placed ? embed_shape(build, old_shape, abs + start, leaves) : old_shape;
    if (old_first != MS_SHAPE_NONE && (offsets[index] != build->members.ptr[old_first + index].offset || kids[index] != old_shape)) {
      *changed = true;
    }
    start += leaves;
  }
  return start;
}

static void push_fields(ShapeBuild *build, const MirTypeDef *def, uint32_t old_first, const uint32_t *offsets,
                        const uint32_t *kids) {
  for (uint32_t index = 0; index < def->nfields; index++) {
    MsShapeMember member = {.name = MS_SHAPE_NONE};
    if (old_first != MS_SHAPE_NONE) {
      member = build->members.ptr[old_first + index];
    } else {
      member.name = add_mir_name(build, def->fields[index].name);
      member.flags = def->fields[index].default_fn1 != 0 ? MS_SHAPE_MEMBER_DEFAULT : 0;
      member.reserved = def->fields[index].default_fn1; /* the build's note; the image keeps 0 */
    }
    member.shape = kids[index];
    member.offset = offsets[index];
    member_list_push(&build->members, member);
  }
}

/* The leaf count of each field of an inline record, in declaration order. */
static uint32_t *inline_counts(ShapeBuild *build, const MirTypeDef *def) {
  uint32_t *counts = MS_ARENA_NEW_ARRAY(&build->arena, uint32_t, (size_t)def->nfields + 1);
  for (uint32_t index = 0; index < def->nfields; index++) {
    counts[index] = (uint32_t)mir_leaves(build->layouts, def->fields[index].ty).len;
  }
  return counts;
}

static uint32_t embed_record(ShapeBuild *build, uint32_t shape_index, const uint32_t *abs, size_t n) {
  const MsShape shape = build->shapes.ptr[shape_index];
  const MirTyData *data = mir_ty_data(build->module, build->types.ptr[shape_index]);
  const MirTypeDef *def = &build->module->type_defs.ptr[data->id];
  uint32_t *offsets = MS_ARENA_NEW_ARRAY(&build->arena, uint32_t, (size_t)def->nfields + 1);
  uint32_t *kids = MS_ARENA_NEW_ARRAY(&build->arena, uint32_t, (size_t)def->nfields + 1);
  bool changed = false;
  const uint32_t used = embed_fields(build, def, shape.first, abs, n, inline_counts(build, def), offsets, kids, &changed);
  if (!changed || used > n) {
    return shape_index;
  }
  MsShape copy = shape;
  copy.first = (uint32_t)build->members.len;
  push_fields(build, def, shape.first, offsets, kids);
  return push_copy(build, shape_index, copy);
}

/* One member per field of a record, made after the field shapes so the members stay contiguous. */
static void record_shape(ShapeBuild *build, MirTy ty, const MirTyData *data, MsShape *shape) {
  MirLayouts *layouts = build->layouts;
  const MirTypeDef *def = &build->module->type_defs.ptr[data->id];
  shape->kind = def->decimal ? MS_SHAPE_DECIMAL : MS_SHAPE_RECORD;
  shape->flags |= (def->opaque ? MS_SHAPE_NAME_ONLY : 0) | (def->text_fn1 != 0 ? MS_SHAPE_TEXT_FORM : 0) | (def->json_fn1 != 0 ? MS_SHAPE_JSON_FORM : 0);
  shape->name = add_type_name(build, def->name);
  uint32_t *offsets = MS_ARENA_NEW_ARRAY(&build->arena, uint32_t, (size_t)def->nfields + 1);
  uint32_t *kids = MS_ARENA_NEW_ARRAY(&build->arena, uint32_t, (size_t)def->nfields + 1);
  uint32_t *counts = MS_ARENA_NEW_ARRAY(&build->arena, uint32_t, (size_t)def->nfields + 1);
  /* The offset of each leaf in the record's own memory image: its block when indirect, else the leaves in order. */
  MsSpan leaves = {0};
  if (def->indirect) {
    const MirRecordBlock block = mir_record_block(layouts, data->id);
    shape->flags |= MS_SHAPE_BOXED;
    shape->size = 8;
    shape->align = 8;
    shape->value = block.size;
    leaves = block.leaves;
    for (uint32_t index = 0; index < def->nfields; index++) {
      counts[index] = block.boxed[index] ? 1 : (uint32_t)mir_leaves(layouts, def->fields[index].ty).len;
    }
  } else {
    fill_slot(build, shape, ty);
    leaves = mir_leaves(layouts, ty);
    for (uint32_t index = 0; index < def->nfields; index++) {
      counts[index] = (uint32_t)mir_leaves(layouts, def->fields[index].ty).len;
    }
  }
  if (def->decimal) { /* the words are the runtime's: a number, with no members to name */
    shape->first = (uint32_t)build->members.len;
    return;
  }
  uint32_t *abs = MS_ARENA_NEW_ARRAY(&build->arena, uint32_t, leaves.len + 1);
  (void)mir_mem_layout(leaves, abs);
  bool changed = false;
  (void)embed_fields(build, def, MS_SHAPE_NONE, abs, leaves.len, counts, offsets, kids, &changed);
  /* a field's offset is from the record's own start, which is leaf 0 at offset 0 */
  shape->first = (uint32_t)build->members.len;
  shape->count = def->nfields;
  push_fields(build, def, MS_SHAPE_NONE, offsets, kids);
}

/* The byte offset of each leaf of an alternative's memory image (inline, or in its block when boxed). */
static const uint32_t *alt_offsets(ShapeBuild *build, MirTy ty, bool boxed) {
  const MirShape *flat = mir_shape(build->layouts, ty);
  const MsSpan leaves = boxed ? flat->block : flat->leaves;
  uint32_t *offsets = MS_ARENA_NEW_ARRAY(&build->arena, uint32_t, leaves.len + 1);
  (void)mir_mem_layout(leaves, offsets);
  return offsets;
}

/* Builds the case and payload-field members of the alternative `ty` whose leaves lie at `abs` (relative to `abs[0]`;
 * `n` of them), and returns the index of the first. `old_first` is the member run of a shape being copied, or
 * MS_SHAPE_NONE for the type's own shape. A false `*changed` after a copy means nothing moved. */
static uint32_t alt_members(ShapeBuild *build, MirTy ty, const MirAltDef *def, const MirAltFields *fields,
                            const uint32_t *abs, size_t n, uint32_t old_first, bool *changed) {
  const uint32_t total = fields->case_start[fields->ncases];
  uint32_t *shapes = MS_ARENA_NEW_ARRAY(&build->arena, uint32_t, (size_t)total + 1);
  uint32_t *offs = MS_ARENA_NEW_ARRAY(&build->arena, uint32_t, (size_t)total + 1);
  for (uint32_t index = 0; index < total; index++) {
    const MirAltField *field = &fields->fields[index];
    const uint32_t old = old_first == MS_SHAPE_NONE ? shape_of(build, field->ty)
                                                    : build->members.ptr[old_first + def->ncases + index].shape;
    shapes[index] = old;
    offs[index] = 0;
    bool placed = field->nleaves > 0;
    uint32_t *gathered = MS_ARENA_NEW_ARRAY(&build->arena, uint32_t, (size_t)field->nleaves + 1);
    for (uint32_t leaf = 0; leaf < field->nleaves && placed; leaf++) {
      placed = field->leaves[leaf] < n;
      gathered[leaf] = placed ? abs[field->leaves[leaf]] : 0;
    }
    if (placed) {
      offs[index] = gathered[0] - abs[0];
      shapes[index] = embed_shape(build, old, gathered, field->nleaves);
    }
    if (old_first != MS_SHAPE_NONE && (shapes[index] != old || offs[index] != build->members.ptr[old_first + def->ncases + index].offset)) {
      *changed = true;
    }
  }
  const uint32_t cases_at = (uint32_t)build->members.len;
  for (uint32_t kase = 0; kase < def->ncases; kase++) {
    MsShapeMember member = {.name = MS_SHAPE_NONE, .shape = MS_SHAPE_NONE, .tag = kase,
                            .first = cases_at + def->ncases + fields->case_start[kase],
                            .count = fields->case_start[kase + 1] - fields->case_start[kase]};
    member.name = old_first == MS_SHAPE_NONE ? add_mir_name(build, def->cases[kase].name) : build->members.ptr[old_first + kase].name;
    member_list_push(&build->members, member);
  }
  for (uint32_t kase = 0; kase < def->ncases; kase++) {
    for (uint32_t at = fields->case_start[kase]; at < fields->case_start[kase + 1]; at++) {
      const uint32_t name_at = at - fields->case_start[kase];
      MsShapeMember member = {.name = MS_SHAPE_NONE, .shape = shapes[at], .offset = offs[at]};
      if (old_first != MS_SHAPE_NONE) {
        member.name = build->members.ptr[old_first + def->ncases + at].name;
      } else if (name_at < def->cases[kase].nfields) {
        member.name = add_mir_name(build, def->cases[kase].fields[name_at].name);
      }
      member_list_push(&build->members, member);
    }
  }
  (void)ty;
  return cases_at;
}

static uint32_t embed_alternative(ShapeBuild *build, uint32_t shape_index, const uint32_t *abs, size_t n) {
  const MsShape shape = build->shapes.ptr[shape_index];
  const MirTy ty = build->types.ptr[shape_index];
  const MirTyData *data = mir_ty_data(build->module, ty);
  const MirAltDef *def = &build->module->alts.ptr[data->id];
  /* a dry run decides whether anything moves before members are pushed */
  bool changed = false;
  const uint32_t before = (uint32_t)build->members.len;
  const uint32_t first = alt_members(build, ty, def, mir_alt_fields(build->layouts, data->id), abs, n, shape.first, &changed);
  if (!changed) {
    build->members.len = before; /* drop the unused copy; shapes it pushed stay, harmlessly */
    return shape_index;
  }
  MsShape copy = shape;
  copy.first = first;
  return push_copy(build, shape_index, copy);
}

static uint32_t embed_shape(ShapeBuild *build, uint32_t shape_index, const uint32_t *abs, size_t n) {
  const MsShape shape = build->shapes.ptr[shape_index];
  if (n == 0 || shape_index == MS_SHAPE_NONE || (shape.flags & MS_SHAPE_BOXED) != 0) {
    return shape_index;
  }
  switch ((MsShapeKind)shape.kind) {
  case MS_SHAPE_OPTIONAL: return embed_optional(build, shape_index, abs, n);
  case MS_SHAPE_RECORD: return embed_record(build, shape_index, abs, n);
  case MS_SHAPE_ALTERNATIVE: return embed_alternative(build, shape_index, abs, n);
  default: return shape_index;
  }
}

static void alternative_shape(ShapeBuild *build, MirTy ty, const MirTyData *data, MsShape *shape) {
  MirLayouts *layouts = build->layouts;
  const MirAltDef *def = &build->module->alts.ptr[data->id];
  const MirAltFields *fields = mir_alt_fields(layouts, data->id);
  uint32_t block_size = 0;
  const bool boxed = mir_boxed_block_size(layouts, ty, &block_size);
  const uint32_t *offsets = alt_offsets(build, ty, boxed);
  shape->kind = MS_SHAPE_ALTERNATIVE;
  shape->flags |= (def->opaque ? MS_SHAPE_NAME_ONLY : 0) | (def->text_fn1 != 0 ? MS_SHAPE_TEXT_FORM : 0) | (def->json_fn1 != 0 ? MS_SHAPE_JSON_FORM : 0);
  if (mir_json_tree_shape(build->module, ty)) {
    shape->flags |= MS_SHAPE_JSON_TREE;
  }
  shape->name = add_type_name(build, def->name);
  shape->extra = 0; /* the tag is the first leaf */
  if (boxed) {
    shape->flags |= MS_SHAPE_BOXED;
    shape->size = 8;
    shape->align = 8;
    shape->value = block_size;
  } else {
    fill_slot(build, shape, ty);
  }
  const MirShape *flat = mir_shape(layouts, ty);
  const size_t count = boxed ? flat->block.len : flat->leaves.len;
  bool changed = false;
  shape->first = alt_members(build, ty, def, fields, offsets, count, MS_SHAPE_NONE, &changed);
  shape->count = def->ncases;
}

static void collection_shape(ShapeBuild *build, MirTy ty, const MirTyData *data, MsShape *shape) {
  fill_slot(build, shape, ty);
  shape->kind = data->nargs > 1 ? MS_SHAPE_MAP : MS_SHAPE_SET;
  shape->size = MIR_MAP_WORDS * 8;
  shape->align = 8;
}

static void hook_functions(const ShapeBuild *build, size_t index, uint32_t *text, uint32_t *json);

static uint32_t build_shape(ShapeBuild *build, MirTy ty, uint32_t index) {
  const MirModule *module = build->module;
  const MirTyData *data = mir_ty_data(module, ty);
  MsShape shape = scalar(MS_SHAPE_OPAQUE, 8);
  if (plain_shape(data, &shape)) {
    build->shapes.ptr[index] = shape;
    return index;
  }
  MirLayouts *layouts = build->layouts;
  if (data->kind == MK_BYTES || data->kind == MK_LIST) {
    shape.kind = data->kind == MK_LIST ? MS_SHAPE_LIST : MS_SHAPE_BYTES;
    fill_slot(build, &shape, ty);
    shape.elem = data->kind == MK_LIST ? shape_of(build, data->elem) : MS_SHAPE_NONE;
  } else if (data->kind == MK_OPT) {
    optional_shape(build, ty, data, &shape);
    shape.elem = shape_of(build, data->elem);
    if (mir_opt_has_flag(layouts, ty)) {
      const MsSpan leaves = mir_leaves(layouts, ty);
      uint32_t offsets[64] = {0};
      if (leaves.len > 1 && leaves.len <= 64) {
        (void)mir_mem_layout(leaves, offsets);
        shape.elem = embed_shape(build, shape.elem, offsets + 1, leaves.len - 1);
      }
    }
  } else if (data->kind == MK_TYPE) {
    record_shape(build, ty, data, &shape);
  } else if (data->kind == MK_ALT) {
    alternative_shape(build, ty, data, &shape);
  } else if (data->kind == MK_OBJ && data->obj_class == MIR_OBJ_COLLECTION) {
    collection_shape(build, ty, data, &shape);
    shape.elem = data->nargs > 0 ? shape_of(build, data->args[0]) : MS_SHAPE_NONE;
    shape.value = data->nargs > 1 ? shape_of(build, data->args[1]) : MS_SHAPE_NONE;
  } else if (data->kind == MK_OBJ) {
    shape.kind = data->obj_class == MIR_OBJ_VALUE ? MS_SHAPE_BIGINT : MS_SHAPE_OBJECT;
    uint32_t text = 0, json = 0;
    hook_functions(build, index, &text, &json);
    shape.flags |= (text != 0 ? MS_SHAPE_TEXT_FORM : 0) | (json != 0 ? MS_SHAPE_JSON_FORM : 0);
    shape.name = add_mir_name(build, data->name);
  }
  (void)layouts;
  build->shapes.ptr[index] = shape;
  return index;
}

static uint32_t shape_of(ShapeBuild *build, MirTy ty) {
  const MirTy key = mir_ty_unscoped(ty);
  for (size_t index = 0; index < build->types.len; index++) {
    if (build->types.ptr[index] == key) {
      return (uint32_t)index;
    }
  }
  const uint32_t index = (uint32_t)build->shapes.len;
  shape_list_push(&build->shapes, scalar(MS_SHAPE_OPAQUE, 8));
  mir_tylist_push(&build->types, key);
  return build_shape(build, key, index);
}

/* The record and alternative builders read `shapes.ptr[index]` after children were pushed, so a shape is
 * written back by index and never through a pointer taken before a push. */

static bool is_collection_shape(const MsShape *shape) {
  return shape->kind == MS_SHAPE_LIST || shape->kind == MS_SHAPE_MAP || shape->kind == MS_SHAPE_SET;
}

static void put32(uint8_t *at, uint32_t value) {
  for (uint32_t index = 0; index < 4; index++) {
    at[index] = (uint8_t)(value >> (8 * index));
  }
}

static void put_shape(uint8_t *at, const MsShape *shape) {
  at[0] = shape->kind;
  at[1] = shape->flags;
  at[2] = (uint8_t)(shape->align & 0xff);
  at[3] = (uint8_t)(shape->align >> 8);
  const uint32_t words[7] = {shape->size, shape->name, shape->first, shape->count, shape->elem, shape->value, shape->extra};
  for (uint32_t index = 0; index < 7; index++) {
    put32(at + 4 + 4 * index, words[index]);
  }
}

static void put_member(uint8_t *at, const MsShapeMember *member) {
  const uint32_t words[8] = {member->name, member->shape, member->offset, member->tag,
                             member->first, member->count, member->flags, 0};
  for (uint32_t index = 0; index < 8; index++) {
    put32(at + 4 * index, words[index]);
  }
}

/* The image: header, shapes, members, then names. */
static MsSpan image_bytes(ShapeBuild *build, uint32_t root) {
  const uint32_t shapes_at = sizeof(MsShapeImage);
  const uint32_t members_at = shapes_at + (uint32_t)build->shapes.len * (uint32_t)sizeof(MsShape);
  const uint32_t strings_at = members_at + (uint32_t)build->members.len * (uint32_t)sizeof(MsShapeMember);
  const uint32_t size = strings_at + (uint32_t)build->strings.len;
  uint8_t *bytes = MS_ARENA_NEW_ARRAY(&build->arena, uint8_t, (size_t)size + 8);
  const uint32_t header[8] = {MS_SHAPE_MAGIC, shapes_at, (uint32_t)build->shapes.len, members_at,
                              (uint32_t)build->members.len, strings_at, (uint32_t)build->strings.len, root};
  for (uint32_t index = 0; index < 8; index++) {
    put32(bytes + 4 * index, header[index]);
  }
  for (size_t index = 0; index < build->shapes.len; index++) {
    put_shape(bytes + shapes_at + index * sizeof(MsShape), &build->shapes.ptr[index]);
  }
  for (size_t index = 0; index < build->members.len; index++) {
    put_member(bytes + members_at + index * sizeof(MsShapeMember), &build->members.ptr[index]);
  }
  for (size_t index = 0; index < build->strings.len; index++) {
    bytes[strings_at + index] = build->strings.ptr[index];
  }
  return ms_span_of(bytes, size);
}

/* The functions a type's shape table calls for its own text and JSON form (1 + the function, 0 for none). */
static void hook_functions(const ShapeBuild *build, size_t index, uint32_t *text, uint32_t *json) {
  const MirTyData *data = mir_ty_data(build->module, build->types.ptr[index]);
  *text = 0;
  *json = 0;
  if (data->kind == MK_TYPE) {
    *text = build->module->type_defs.ptr[data->id].text_fn1;
    *json = build->module->type_defs.ptr[data->id].json_fn1;
  } else if (data->kind == MK_ALT) {
    *text = build->module->alts.ptr[data->id].text_fn1;
    *json = build->module->alts.ptr[data->id].json_fn1;
  } else if (data->kind == MK_OBJ) {
    for (size_t at = 0; at < build->module->obj_hooks.len; at++) {
      if (build->module->obj_hooks.ptr[at].ty == build->types.ptr[index]) {
        *text = build->module->obj_hooks.ptr[at].text_fn1;
        *json = build->module->obj_hooks.ptr[at].json_fn1;
      }
    }
  }
}

/* 1 + the constructor thunk of an untyped JSON tree shape, 0 for any other. */
static uint32_t tree_function(const ShapeBuild *build, size_t index) {
  const MirTyData *data = mir_ty_data(build->module, build->types.ptr[index]);
  return data->kind == MK_ALT ? build->module->alts.ptr[data->id].tree_fn1 : 0;
}

static bool is_scalar_shape(const MsShape *shape) {
  return shape->kind <= MS_SHAPE_BYTES;
}

static void want_child(const ShapeBuild *build, bool *wants, uint32_t child) {
  if (child != MS_SHAPE_NONE && child < build->shapes.len && !is_scalar_shape(&build->shapes.ptr[child])) {
    wants[child] = true;
  }
}

/* Which shapes get a descriptor in the hook array: a collection shape, and every non-scalar shape a collection holds
 * or a record or alternative has as a field, since a reader that fails midway drops what it built by descriptor. */
static bool *descriptor_wants(ShapeBuild *build) {
  bool *wants = MS_ARENA_NEW_ARRAY(&build->arena, bool, build->shapes.len + 1);
  for (size_t index = 0; index < build->shapes.len; index++) {
    wants[index] = false;
  }
  for (size_t index = 0; index < build->shapes.len; index++) {
    const MsShape *shape = &build->shapes.ptr[index];
    if (tree_function(build, index) != 0) {
      wants[index] = true; /* a parse builds the tree by its descriptor */
    }
    if (is_collection_shape(shape)) {
      wants[index] = true;
      want_child(build, wants, shape->elem);
      if (shape->kind == MS_SHAPE_MAP) {
        want_child(build, wants, shape->value);
      }
    } else if (shape->kind == MS_SHAPE_RECORD || shape->kind == MS_SHAPE_ALTERNATIVE) {
      for (uint32_t at = 0; at < shape->count && shape->first + at < build->members.len; at++) {
        want_child(build, wants, build->members.ptr[shape->first + at].shape);
      }
    }
  }
  return wants;
}

/* The hook array: one entry per shape; the first word of a shape that wants one is its descriptor, and a type with its
 * own text or JSON form names those functions. */
static uint32_t hook_symbol(DataCx *cx, ShapeBuild *build, uint32_t number) {
  const bool *wants = descriptor_wants(build);
  uint32_t wanted = 0;
  for (size_t index = 0; index < build->shapes.len; index++) {
    uint32_t text, json;
    hook_functions(build, index, &text, &json);
    wanted += (wants[index] ? 1 : 0) + (text != 0 ? 1 : 0) + (json != 0 ? 1 : 0) + (tree_function(build, index) != 0 ? 1 : 0);
  }
  if (wanted == 0) {
    return MIR_NONE;
  }
  const uint32_t entry = (uint32_t)sizeof(MsShapeHook);
  MirDataSym sym = {.name = mird_name(cx, "shape.hooks", number), .size = (uint32_t)build->shapes.len * entry, .align = 8,
                    .relocs = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirReloc, wanted)};
  for (size_t index = 0; index < build->shapes.len; index++) {
    uint32_t text, json;
    hook_functions(build, index, &text, &json);
    if (wants[index]) {
      sym.relocs[sym.nrelocs++] = (MirReloc){(uint32_t)index * entry, mird_descriptor(cx, build->types.ptr[index])};
    }
    if (text != 0) {
      sym.relocs[sym.nrelocs++] = (MirReloc){(uint32_t)(index * entry + offsetof(MsShapeHook, to_text)), {.kind = MREF_FUNC, .index = text - 1}};
    }
    if (json != 0) {
      sym.relocs[sym.nrelocs++] = (MirReloc){(uint32_t)(index * entry + offsetof(MsShapeHook, json_encode)), {.kind = MREF_FUNC, .index = json - 1}};
    }
    if (tree_function(build, index) != 0) {
      sym.relocs[sym.nrelocs++] = (MirReloc){(uint32_t)(index * entry + offsetof(MsShapeHook, tree_ctor)), {.kind = MREF_FUNC, .index = tree_function(build, index) - 1}};
    }
  }
  return mird_add_sym(cx, &sym);
}

/* The default builders: one function pointer per member, null for a member with no default. */
static uint32_t defaults_symbol(DataCx *cx, ShapeBuild *build, uint32_t number) {
  uint32_t wanted = 0;
  for (size_t index = 0; index < build->members.len; index++) {
    wanted += build->members.ptr[index].reserved != 0 ? 1 : 0;
  }
  if (wanted == 0) {
    return MIR_NONE;
  }
  MirDataSym sym = {.name = mird_name(cx, "shape.defaults", number), .size = (uint32_t)build->members.len * 8, .align = 8,
                    .relocs = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirReloc, wanted)};
  for (size_t index = 0; index < build->members.len; index++) {
    if (build->members.ptr[index].reserved != 0) {
      sym.relocs[sym.nrelocs++] = (MirReloc){(uint32_t)index * 8, {.kind = MREF_FUNC, .index = build->members.ptr[index].reserved - 1}};
    }
  }
  return mird_add_sym(cx, &sym);
}

static uint32_t table_symbol(DataCx *cx, ShapeBuild *build, MsSpan image) {
  const uint32_t number = (uint32_t)cx->data->syms.len;
  const MirDataSym image_sym = {.name = mird_name(cx, "shape.image", number), .size = (uint32_t)image.len, .align = 8,
                                .bytes = image};
  const uint32_t image_at = mird_add_sym(cx, &image_sym);
  const uint32_t hooks_at = hook_symbol(cx, build, number);
  const uint32_t defaults_at = defaults_symbol(cx, build, number);
  MirDataSym table = {.name = mird_name(cx, "shape", number), .size = (uint32_t)sizeof(MsShapeTable), .align = 8,
                      .relocs = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirReloc, 3)};
  table.relocs[table.nrelocs++] = (MirReloc){(uint32_t)offsetof(MsShapeTable, image), {.kind = MREF_DATA, .index = image_at}};
  if (hooks_at != MIR_NONE) {
    table.relocs[table.nrelocs++] = (MirReloc){(uint32_t)offsetof(MsShapeTable, hooks), {.kind = MREF_DATA, .index = hooks_at}};
  }
  if (defaults_at != MIR_NONE) {
    table.relocs[table.nrelocs++] =
        (MirReloc){(uint32_t)offsetof(MsShapeTable, defaults), {.kind = MREF_DATA, .index = defaults_at}};
  }
  return mird_add_sym(cx, &table);
}

void mird_visit_shape(DataCx *cx, const MirFunc *func, const MirInst *inst) {
  (void)func;
  if (inst->op != MOP_Shape || inst->imm.tag != MI_TY || mir_desc_map_get(&cx->data->shapes, inst->imm.a) != NULL) {
    return;
  }
  ShapeBuild build = {.module = cx->module, .layouts = cx->layouts, .arena = ms_arena_new()};
  const uint32_t root = shape_of(&build, inst->imm.a);
  /* The image is kept in the module's arena, past this build. */
  MsSpan image = image_bytes(&build, root);
  image = ms_arena_copy(&cx->module->arena, image);
  const uint32_t table = table_symbol(cx, &build, image);
  mir_desc_map_put(&cx->data->shapes, inst->imm.a, (MirRef){.kind = MREF_DATA, .index = table});
  shape_list_free(&build.shapes);
  member_list_free(&build.members);
  byte_list_free(&build.strings);
  mir_tylist_free(&build.types);
  ms_arena_free(&build.arena);
}

void mir_shape_desc_types(const MirModule *module, MirLayouts *layouts, MirTy ty, MirIdList *out) {
  ShapeBuild build = {.module = module, .layouts = layouts, .arena = ms_arena_new()};
  (void)shape_of(&build, ty);
  const bool *wants = descriptor_wants(&build);
  for (size_t index = 0; index < build.shapes.len; index++) {
    if (wants[index]) {
      mir_idlist_push(out, build.types.ptr[index]);
    }
  }
  shape_list_free(&build.shapes);
  member_list_free(&build.members);
  byte_list_free(&build.strings);
  mir_tylist_free(&build.types);
  ms_arena_free(&build.arena);
}

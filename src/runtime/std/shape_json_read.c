/* A value built from a JSON document, walked through its shape table. See shape_json.h. The document parser
 * and the node readers of json.h do the scanning; this file decides what each node means for each shape and
 * owns what it builds. Every decode either fills its slot or leaves nothing owned behind. */
#include <string.h>

#include "abi/status.h"
#include "base/alloc.h"
#include "base/desc.h"
#include "base/fatal.h"
#include "base/map.h"
#include "runtime/core/obj.h"
#include "runtime/std/bigint.h"
#include "runtime/std/decimal.h"
#include "runtime/std/encoding.h"
#include "runtime/std/json.h"
#include "runtime/std/shape_json.h"

/* Deeper documents than this do not fit: the walk is recursive. */
enum { MAX_DEPTH = 2048 };

/* The node kinds of json.h. */
enum { KIND_NULL = 0, KIND_BOOL = 1, KIND_NUMBER = 2, KIND_STRING = 3, KIND_ARRAY = 4, KIND_OBJECT = 5 };

/* The reasons of msstd_json_mismatch. */
enum { WHY_TYPE = 0, WHY_KIND = 1, WHY_MISSING = 2, WHY_UNKNOWN = 3, WHY_VARIANT = 4 };

typedef struct Decode {
  const MsShapeTable *table;
  const void *doc;
  bool strict; /* an unknown member fails */
} Decode;

static bool decode(Decode *state, uint32_t shape, uint32_t id, uint8_t *slot, int depth);

/* ---- failures ---- */

static bool mismatch(const Decode *state, uint32_t id, int64_t code, const char *text) {
  const MsString detail = ms_string_static(ms_span_of_text(text));
  msstd_json_mismatch(state->doc, id, code, &detail);
  return false;
}

/* The display name of a shape's type in a "does not fit" message. */
static const char *type_name(const Decode *state, const MsShape *shape) {
  if (shape->name != MS_SHAPE_NONE) {
    return ms_shape_text(state->table, shape->name);
  }
  switch (shape->kind) {
  case MS_SHAPE_BOOL:
    return "Bool";
  case MS_SHAPE_INT:
    return "Int";
  case MS_SHAPE_UINT:
    return "UInt";
  case MS_SHAPE_FLOAT:
    return "Float";
  case MS_SHAPE_STRING:
    return "String";
  case MS_SHAPE_BYTES:
    return "Bytes";
  case MS_SHAPE_LIST:
    return "List";
  case MS_SHAPE_MAP:
    return "Map";
  case MS_SHAPE_SET:
    return "Set";
  default:
    return "value";
  }
}

static bool misfit(const Decode *state, uint32_t id, const MsShape *shape) {
  return mismatch(state, id, WHY_TYPE, type_name(state, shape));
}

static const char *kind_name(int kind) {
  static const char *const names[] = {"null", "boolean", "number", "string", "array", "object"};
  return kind >= KIND_NULL && kind <= KIND_OBJECT ? names[kind] : "value";
}

static bool expect_kind(const Decode *state, uint32_t id, int kind) {
  if (msstd_json_kind(state->doc, id) == kind) {
    return true;
  }
  return mismatch(state, id, WHY_KIND, kind_name(kind));
}

/* ---- descriptors ---- */

static const MsTypeDesc pod_1 = {.size = 1, .align = 1, .kind = MS_KIND_POD};
static const MsTypeDesc pod_2 = {.size = 2, .align = 2, .kind = MS_KIND_POD};
static const MsTypeDesc pod_4 = {.size = 4, .align = 4, .kind = MS_KIND_POD};

/* The descriptor of a slot of `shape_index`: the table's hook, or the builtin of a scalar. A shape that owns
 * memory and has no descriptor is a compiler bug. */
static const MsTypeDesc *desc_of(const Decode *state, uint32_t shape_index) {
  const MsShapeHook *hook = ms_shape_hook(state->table, shape_index);
  if (hook != NULL && hook->desc != NULL) {
    return hook->desc;
  }
  const MsShape *shape = ms_shape_at(state->table, shape_index);
  switch (shape->kind) {
  case MS_SHAPE_BOOL:
    return &ms_desc_bool;
  case MS_SHAPE_INT:
  case MS_SHAPE_UINT:
    return shape->size == 8 ? &ms_desc_int : shape->size == 4 ? &pod_4 : shape->size == 2 ? &pod_2 : &pod_1;
  case MS_SHAPE_FLOAT:
    return shape->size == 4 ? &ms_desc_float32 : &ms_desc_float;
  case MS_SHAPE_STRING:
    return &ms_desc_string;
  case MS_SHAPE_BYTES:
    return &ms_desc_bytes;
  default:
    ms_fatal(MS_FATAL_INVARIANT, "a shape table lacks a type descriptor");
  }
}

static void drop_slot(const Decode *state, uint32_t shape_index, uint8_t *slot) {
  ms_slot_drop(desc_of(state, shape_index), slot);
}

/* ---- scalars ---- */

static void store_signed(const MsShape *shape, uint8_t *slot, int64_t value) {
  switch (shape->size) {
  case 1: {
    const int8_t narrow = (int8_t)value;
    memcpy(slot, &narrow, sizeof narrow);
    return;
  }
  case 2: {
    const int16_t narrow = (int16_t)value;
    memcpy(slot, &narrow, sizeof narrow);
    return;
  }
  case 4: {
    const int32_t narrow = (int32_t)value;
    memcpy(slot, &narrow, sizeof narrow);
    return;
  }
  default:
    memcpy(slot, &value, sizeof value);
    return;
  }
}

static bool decode_integer(const Decode *state, const MsShape *shape, uint32_t id, uint8_t *slot) {
  if (!expect_kind(state, id, KIND_NUMBER)) {
    return false;
  }
  MsString text = ms_string_empty();
  msstd_json_text(state->doc, id, &text);
  int64_t value = 0;
  uint8_t status;
  if (shape->kind == MS_SHAPE_UINT && shape->size == 8) {
    status = msstd_json_dec_uint(&text, &value);
  } else if (shape->size == 8) {
    status = msstd_json_dec_int(&text, &value);
  } else {
    const int bits = (int)shape->size * 8;
    const int64_t low = shape->kind == MS_SHAPE_UINT ? 0 : -((int64_t)1 << (bits - 1));
    const int64_t high =
        shape->kind == MS_SHAPE_UINT ? ((int64_t)1 << bits) - 1 : ((int64_t)1 << (bits - 1)) - 1;
    status = msstd_json_dec_int_in(&text, low, high, &value);
  }
  ms_string_release(&text);
  if (status != MS_STATUS_OK) {
    return misfit(state, id, shape);
  }
  store_signed(shape, slot, value);
  return true;
}

static bool decode_float(const Decode *state, const MsShape *shape, uint32_t id, uint8_t *slot) {
  if (!expect_kind(state, id, KIND_NUMBER)) {
    return false;
  }
  MsString text = ms_string_empty();
  msstd_json_text(state->doc, id, &text);
  double value = 0;
  const uint8_t status =
      shape->size == 4 ? msstd_json_dec_float32(&text, &value) : msstd_json_dec_float(&text, &value);
  ms_string_release(&text);
  if (status != MS_STATUS_OK) {
    return misfit(state, id, shape);
  }
  if (shape->size == 4) {
    const float narrow = (float)value;
    memcpy(slot, &narrow, sizeof narrow);
  } else {
    memcpy(slot, &value, sizeof value);
  }
  return true;
}

/* A BigInt or Decimal reads the digits of a JSON number exactly; one that does not fit is a misfit. */
static bool decode_digits(const Decode *state, const MsShape *shape, uint32_t id, uint8_t *slot) {
  if (!expect_kind(state, id, KIND_NUMBER)) {
    return false;
  }
  MsString text = ms_string_empty();
  msstd_json_text(state->doc, id, &text);
  uint8_t status = MS_STATUS_OK;
  if (shape->kind == MS_SHAPE_DECIMAL) {
    status = msstd_decimal_parse(&text, (MsDecimal *)(void *)slot);
  } else {
    MsBigCell *big = NULL;
    status = msstd_bigint_parse(&text, 10, 0, 0, &big);
    if (status == MS_STATUS_OK) {
      memcpy(slot, &big, sizeof big);
    }
  }
  ms_string_release(&text);
  return status == MS_STATUS_OK || misfit(state, id, shape);
}

static bool decode_string(const Decode *state, uint32_t id, uint8_t *slot) {
  if (!expect_kind(state, id, KIND_STRING)) {
    return false;
  }
  MsString text = ms_string_empty();
  msstd_json_text(state->doc, id, &text);
  memcpy(slot, &text, sizeof text);
  return true;
}

static bool decode_bytes(const Decode *state, const MsShape *shape, uint32_t id, uint8_t *slot) {
  if (!expect_kind(state, id, KIND_STRING)) {
    return false;
  }
  MsString text = ms_string_empty();
  msstd_json_text(state->doc, id, &text);
  MsBytes bytes;
  const uint8_t status = msstd_encoding_base64_decode(&text, 0, 0, 0, &bytes);
  ms_string_release(&text);
  if (status != MS_STATUS_OK) {
    return misfit(state, id, shape);
  }
  memcpy(slot, &bytes, sizeof bytes);
  return true;
}

/* ---- containers ---- */

static uint8_t *block_of(size_t size) {
  return ms_alloc_zeroed(size > 0 ? size : 1);
}

static bool decode_list(Decode *state, const MsShape *shape, uint32_t id, uint8_t *slot, int depth) {
  if (!expect_kind(state, id, KIND_ARRAY)) {
    return false;
  }
  const MsTypeDesc *element = desc_of(state, shape->elem);
  const int64_t count = msstd_json_len(state->doc, id);
  MsList list = {0};
  ms_list_reserve(&list, element->size, (size_t)count);
  for (int64_t at = 0; at < count; at++) {
    uint8_t *item = ms_list_slot(&list, element, (size_t)at);
    memset(item, 0, element->size);
    if (!decode(state, shape->elem, msstd_json_item(state->doc, id, at), item, depth + 1)) {
      ms_list_drop_desc(&list, element);
      return false;
    }
    list.len = (size_t)at + 1;
  }
  memcpy(slot, &list, sizeof list);
  return true;
}

static bool decode_set(Decode *state, const MsShape *shape, uint32_t id, uint8_t *slot, int depth) {
  if (!expect_kind(state, id, KIND_ARRAY)) {
    return false;
  }
  const MsTypeDesc *key = desc_of(state, shape->elem);
  const int64_t count = msstd_json_len(state->doc, id);
  MsMap map = {0};
  ms_map_reserve(&map, key, NULL, (size_t)count);
  uint8_t *item = block_of(key->size);
  for (int64_t at = 0; at < count; at++) {
    memset(item, 0, key->size);
    if (!decode(state, shape->elem, msstd_json_item(state->doc, id, at), item, depth + 1)) {
      ms_map_drop(&map, key, NULL);
      ms_free(item);
      return false;
    }
    ms_map_insert(&map, key, NULL, item, NULL);
  }
  ms_free(item);
  memcpy(slot, &map, sizeof map);
  return true;
}

/* An alternative whose cases may be named by a member name: some case has no payload. */
static bool key_alternative(const MsShapeTable *table, const MsShape *shape) {
  if (shape->kind != MS_SHAPE_ALTERNATIVE) {
    return false;
  }
  for (uint32_t at = 0; at < shape->count; at++) {
    if (ms_shape_member(table, shape->first + at)->count == 0) {
      return true;
    }
  }
  return false;
}

/* Reads the member name `name` as a key of `shape_index` into `slot`; false when it names no key. */
static bool decode_key(const Decode *state, uint32_t shape_index, const MsString *name, uint8_t *slot) {
  const MsShape *shape = ms_shape_at(state->table, shape_index);
  if (shape->kind == MS_SHAPE_STRING) {
    memcpy(slot, name, sizeof *name);
    return true;
  }
  if (shape->kind == MS_SHAPE_INT) {
    int64_t value = 0;
    if (msstd_json_dec_int(name, &value) != MS_STATUS_OK) {
      return false;
    }
    store_signed(shape, slot, value);
    return true;
  }
  if (shape->kind == MS_SHAPE_BOOL) {
    const MsSpan text = ms_string_span(name);
    if (!ms_span_is_text(text, "true") && !ms_span_is_text(text, "false")) {
      return false;
    }
    *slot = ms_span_is_text(text, "true") ? 1 : 0;
    return true;
  }
  if (!key_alternative(state->table, shape)) {
    return false;
  }
  for (uint32_t at = 0; at < shape->count; at++) {
    const MsShapeMember *which = ms_shape_member(state->table, shape->first + at);
    if (which->count == 0 &&
        ms_span_is_text(ms_string_span(name), ms_shape_text(state->table, which->name))) {
      const int64_t tag = (int64_t)which->tag;
      memcpy(slot + shape->extra, &tag, sizeof tag);
      return true;
    }
  }
  return false;
}

static bool decode_map(Decode *state, const MsShape *shape, uint32_t id, uint8_t *slot, int depth) {
  if (!expect_kind(state, id, KIND_OBJECT)) {
    return false;
  }
  const MsTypeDesc *key = desc_of(state, shape->elem);
  const MsTypeDesc *value = desc_of(state, shape->value);
  const MsShape *key_shape = ms_shape_at(state->table, shape->elem);
  const int64_t count = msstd_json_len(state->doc, id);
  MsMap map = {0};
  ms_map_reserve(&map, key, value, (size_t)count);
  uint8_t *key_slot = block_of(key->size);
  uint8_t *value_slot = block_of(value->size);
  bool ok = true;
  for (int64_t at = 0; at < count && ok; at++) {
    MsString name = ms_string_empty();
    msstd_json_key(state->doc, id, at, &name);
    memset(key_slot, 0, key->size);
    const bool named = decode_key(state, shape->elem, &name, key_slot);
    if (!named) {
      ms_string_release(&name);
      ok = misfit(state, id, shape);
      break;
    }
    if (key_shape->kind != MS_SHAPE_STRING) {
      ms_string_release(&name); /* a String key keeps the name */
    }
    memset(value_slot, 0, value->size);
    if (!decode(state, shape->value, msstd_json_item(state->doc, id, at), value_slot, depth + 1)) {
      drop_slot(state, shape->elem, key_slot);
      ok = false;
    } else if (ms_map_has(&map, key, value, key_slot)) {
      /* Two names that read as one key. */
      drop_slot(state, shape->elem, key_slot);
      drop_slot(state, shape->value, value_slot);
      ok = misfit(state, id, shape);
    } else {
      ms_map_insert(&map, key, value, key_slot, value_slot);
    }
  }
  ms_free(key_slot);
  ms_free(value_slot);
  if (!ok) {
    ms_map_drop(&map, key, value);
    return false;
  }
  memcpy(slot, &map, sizeof map);
  return true;
}

static bool decode_optional(Decode *state, const MsShape *shape, uint32_t id, uint8_t *slot, int depth) {
  if (msstd_json_kind(state->doc, id) == KIND_NULL) {
    return true; /* the slot is zero: none */
  }
  const bool nullable = (shape->flags & MS_SHAPE_NULLABLE) != 0;
  if ((shape->flags & MS_SHAPE_HEAP_PAYLOAD) != 0) {
    uint8_t *block = ms_alloc_zeroed(ms_shape_at(state->table, shape->elem)->size);
    if (!decode(state, shape->elem, id, block, depth + 1)) {
      ms_free(block);
      return false;
    }
    memcpy(slot, &block, sizeof block);
    return true;
  }
  if (!decode(state, shape->elem, id, nullable ? slot : slot + (int32_t)shape->extra, depth + 1)) {
    return false;
  }
  if (!nullable) {
    *slot = 1;
  }
  return true;
}

/* ---- fields ---- */

/* The names of the `count` members from `first`, as the list msstd_json_has_unknown reads. */
static MsList names_of(const MsShapeTable *table, uint32_t first, uint32_t count) {
  MsString *names = ms_alloc((size_t)(count > 0 ? count : 1) * sizeof *names);
  for (uint32_t at = 0; at < count; at++) {
    names[at] =
        ms_string_static(ms_span_of_text(ms_shape_text(table, ms_shape_member(table, first + at)->name)));
  }
  return (MsList){.ptr = (uint8_t *)(void *)names, .len = count, .cap = count};
}

static bool no_unknown_member(const Decode *state, uint32_t first, uint32_t count, uint32_t id) {
  MsList names = names_of(state->table, first, count);
  const bool unknown = msstd_json_has_unknown(state->doc, id, &names) != 0;
  ms_free(names.ptr);
  return !unknown || mismatch(state, id, WHY_UNKNOWN, "");
}

/* Builds the `count` fields from member `first` of the object node `id` into the value at `base`. A field
 * that is absent takes its default, or none when optional; a required one is missing. On failure the fields
 * already built are dropped. */
static bool decode_fields(Decode *state, uint32_t first, uint32_t count, uint32_t id, uint8_t *base,
                          int depth) {
  if (state->strict && !no_unknown_member(state, first, count, id)) {
    return false;
  }
  for (uint32_t at = 0; at < count; at++) {
    const MsShapeMember *field = ms_shape_member(state->table, first + at);
    const MsShape *shape = ms_shape_at(state->table, field->shape);
    uint8_t *slot = base + field->offset;
    const MsString name = ms_string_static(ms_span_of_text(ms_shape_text(state->table, field->name)));
    const int64_t found = msstd_json_find(state->doc, id, &name);
    bool built = true;
    if (found >= 0) {
      built = decode(state, field->shape, msstd_json_item(state->doc, id, found), slot, depth + 1);
    } else if ((field->flags & MS_SHAPE_MEMBER_DEFAULT) != 0 && state->table->defaults != NULL) {
      state->table->defaults[first + at](slot, base);
    } else if (shape->kind != MS_SHAPE_OPTIONAL && shape->kind != MS_SHAPE_VOID) {
      built = mismatch(state, id, WHY_MISSING, ms_shape_text(state->table, field->name));
    }
    if (!built) {
      for (uint32_t done = 0; done < at; done++) {
        const MsShapeMember *earlier = ms_shape_member(state->table, first + done);
        drop_slot(state, earlier->shape, base + earlier->offset);
      }
      return false;
    }
  }
  return true;
}

static bool decode_record(Decode *state, const MsShape *shape, uint32_t id, uint8_t *base, int depth) {
  return expect_kind(state, id, KIND_OBJECT) &&
         decode_fields(state, shape->first, shape->count, id, base, depth);
}

/* A string or single-key object names the case; a case with fields carries them as an object. */
static bool decode_alternative(Decode *state, const MsShape *shape, uint32_t id, uint8_t *base, int depth) {
  MsString *list = ms_alloc((size_t)shape->count * sizeof *list);
  for (uint32_t at = 0; at < shape->count; at++) {
    list[at] = ms_string_static(
        ms_span_of_text(ms_shape_text(state->table, ms_shape_member(state->table, shape->first + at)->name)));
  }
  const MsList case_names = {.ptr = (uint8_t *)(void *)list, .len = shape->count, .cap = shape->count};
  int64_t payload = -1;
  const int64_t index = msstd_json_variant(state->doc, id, &case_names, &payload);
  ms_free(list);
  if (index < 0) {
    return mismatch(state, id, WHY_VARIANT, "");
  }
  const MsShapeMember *which = ms_shape_member(state->table, shape->first + (uint32_t)index);
  if (which->count == 0) {
    if (payload >= 0) {
      return misfit(state, id, shape);
    }
  } else {
    if (payload < 0) {
      return misfit(state, id, shape);
    }
    const uint32_t payload_id = (uint32_t)((uint64_t)payload & 0xffffffffu);
    if (!expect_kind(state, payload_id, KIND_OBJECT) ||
        !decode_fields(state, which->first, which->count, payload_id, base, depth)) {
      return false;
    }
  }
  const int64_t tag = (int64_t)which->tag;
  memcpy(base + shape->extra, &tag, sizeof tag);
  return true;
}

/* ---- the walk ---- */

/* Builds a RECORD or ALTERNATIVE, in its slot or in a block the slot points to. */
static bool decode_composite(Decode *state, const MsShape *shape, uint32_t id, uint8_t *slot, int depth) {
  const bool boxed = (shape->flags & MS_SHAPE_BOXED) != 0;
  uint8_t *base = slot;
  if (boxed) {
    base = block_of(shape->value);
  }
  const bool ok = shape->kind == MS_SHAPE_RECORD ? decode_record(state, shape, id, base, depth)
                                                 : decode_alternative(state, shape, id, base, depth);
  if (!boxed) {
    return ok;
  }
  if (!ok) {
    ms_free(base);
    return false;
  }
  memcpy(slot, &base, sizeof base);
  return true;
}

static bool decode(Decode *state, uint32_t shape_index, uint32_t id, uint8_t *slot, int depth) {
  const MsShape *shape = ms_shape_at(state->table, shape_index);
  if (depth >= MAX_DEPTH) {
    return misfit(state, id, shape);
  }
  const MsShapeHook *hook = ms_shape_hook(state->table, shape_index);
  if ((shape->flags & MS_SHAPE_JSON_FORM) != 0 && hook != NULL && hook->json_decode != NULL) {
    return hook->json_decode(state->doc, id, slot) == 0 || misfit(state, id, shape);
  }
  if ((shape->flags & MS_SHAPE_JSON_TREE) != 0 && hook != NULL && hook->tree_ctor != NULL && hook->desc != NULL) {
    /* The untyped tree is read as it is, wherever it sits; it fits any node. The constructor writes the slot. */
    return msstd_json_node_tree(state->doc, id, hook->desc, hook->tree_ctor, slot) == MS_STATUS_OK || misfit(state, id, shape);
  }
  switch (shape->kind) {
  case MS_SHAPE_BOOL:
    if (!expect_kind(state, id, KIND_BOOL)) {
      return false;
    }
    *slot = msstd_json_bool(state->doc, id) != 0 ? 1 : 0;
    return true;
  case MS_SHAPE_INT:
  case MS_SHAPE_UINT:
    return decode_integer(state, shape, id, slot);
  case MS_SHAPE_FLOAT:
    return decode_float(state, shape, id, slot);
  case MS_SHAPE_STRING:
    return decode_string(state, id, slot);
  case MS_SHAPE_BYTES:
    return decode_bytes(state, shape, id, slot);
  case MS_SHAPE_LIST:
    return decode_list(state, shape, id, slot, depth);
  case MS_SHAPE_SET:
    return decode_set(state, shape, id, slot, depth);
  case MS_SHAPE_MAP:
    return decode_map(state, shape, id, slot, depth);
  case MS_SHAPE_OPTIONAL:
    return decode_optional(state, shape, id, slot, depth);
  case MS_SHAPE_RECORD:
  case MS_SHAPE_ALTERNATIVE:
    return decode_composite(state, shape, id, slot, depth);
  case MS_SHAPE_BIGINT:
  case MS_SHAPE_DECIMAL:
    return decode_digits(state, shape, id, slot);
  case MS_SHAPE_OBJECT: {
    const MsObjectCodec *codec = ms_object_codec(ms_shape_text(state->table, shape->name));
    MsString text = ms_string_empty();
    if (codec == NULL || !expect_kind(state, id, KIND_STRING)) {
      return codec == NULL ? misfit(state, id, shape) : false;
    }
    msstd_json_text(state->doc, id, &text);
    MsObj *object = NULL;
    const uint8_t status = codec->parse(&text, &object);
    ms_string_release(&text);
    if (status != MS_STATUS_OK) {
      return misfit(state, id, shape);
    }
    memcpy(slot, &object, sizeof object);
    return true;
  }
  default: /* VOID, BIGINT and DECIMAL without a hook, OPAQUE, FUNCTION: never readable */
    return misfit(state, id, shape);
  }
}

uint8_t msstd_json_decode(const MsShapeTable *table, const MsString *text, uint8_t has_max_bytes,
                          int64_t max_bytes, uint8_t has_max_depth, int64_t max_depth, uint8_t has_max_values,
                          int64_t max_values, uint8_t ignore_unknown_fields, void *out, MsString *err) {
  void *doc = NULL;
  uint32_t root = 0;
  const uint8_t parsed = msstd_json_parse(text, has_max_bytes, max_bytes, has_max_depth, max_depth,
                                          has_max_values, max_values, &doc, &root, err);
  if (parsed != MS_STATUS_OK) {
    return parsed;
  }
  Decode state = {.table = table, .doc = doc, .strict = ignore_unknown_fields == 0};
  const MsShape *shape = ms_shape_at(table, table->image->root);
  uint8_t *slot = out;
  memset(slot, 0, shape->size);
  uint8_t status = MS_STATUS_OK;
  if (!decode(&state, table->image->root, root & 0xffffffffu, slot, 0)) {
    msstd_json_mismatch_text(doc, root & 0xffffffffu, err);
    status = MS_STATUS_INVALID_DATA;
  }
  msrt_obj_drop((MsObj *)doc);
  return status;
}

/* JSON text of a value, walked through its shape table. See shape_json.h. The writer natives of json.h do the
 * framing, escaping, indent and budgets; this file decides what to write for each shape. */
#include "base/map.h"
#include "abi/status.h"
#include "runtime/core/obj.h"
#include "runtime/std/encoding.h"
#include "runtime/std/json.h"
#include "runtime/std/shape_json.h"
#include "runtime/std/shape_text.h"

/* Deeper data than this has no JSON form: the walk is recursive. */
enum { MAX_DEPTH = 2048 };

#define AT(type, address) ((const type *)(const void *)(address))

typedef struct Encode {
  const MsShapeTable *table;
  void *writer;
} Encode;

/* Whether a value was written: 0, or -1 when it has no JSON form and nothing was written. */
enum { WRITTEN = 0, NO_FORM = -1 };

static int encode(Encode *encode, uint32_t shape, const uint8_t *slot, int depth);

static int no_form(Encode *state) {
  msstd_json_w_no_form(state->writer);
  return NO_FORM;
}

static int64_t read_signed(const MsShape *shape, const uint8_t *slot) {
  switch (shape->size) {
  case 1:
    return *(const int8_t *)slot;
  case 2:
    return *AT(int16_t, slot);
  case 4:
    return *AT(int32_t, slot);
  default:
    return *AT(int64_t, slot);
  }
}

static int64_t read_unsigned(const MsShape *shape, const uint8_t *slot) {
  switch (shape->size) {
  case 1:
    return *slot;
  case 2:
    return *AT(uint16_t, slot);
  case 4:
    return *AT(uint32_t, slot);
  default:
    return (int64_t)*AT(uint64_t, slot);
  }
}

/* Writes a number in a slot: 8-byte unsigned goes through the unsigned writer, smaller integers are widened.
 */
static int encode_number(Encode *state, const MsShape *shape, const uint8_t *slot) {
  if (shape->kind == MS_SHAPE_UINT && shape->size == 8) {
    msstd_json_w_uint(state->writer, read_unsigned(shape, slot));
  } else if (shape->kind == MS_SHAPE_UINT) {
    msstd_json_w_int(state->writer, read_unsigned(shape, slot));
  } else if (shape->kind == MS_SHAPE_INT) {
    msstd_json_w_int(state->writer, read_signed(shape, slot));
  } else if (shape->size == 4) {
    msstd_json_w_float32(state->writer, (double)*AT(float, slot));
  } else {
    msstd_json_w_float(state->writer, *AT(double, slot));
  }
  return WRITTEN;
}

/* One array item; an element without a JSON form is `null`. */
static void encode_item(Encode *state, uint32_t shape, const uint8_t *slot, int depth) {
  msstd_json_w_item(state->writer);
  if (encode(state, shape, slot, depth + 1) == NO_FORM) {
    msstd_json_w_undo(state->writer);
    msstd_json_w_item(state->writer);
    msstd_json_w_null(state->writer);
  }
}

static int encode_list(Encode *state, const MsShape *shape, const uint8_t *slot, int depth) {
  const MsList *list = AT(MsList, slot);
  const MsShape *element = ms_shape_at(state->table, shape->elem);
  msstd_json_w_begin_array(state->writer);
  for (size_t at = 0; at < list->len; at++) {
    encode_item(state, shape->elem, (const uint8_t *)list->ptr + at * element->size, depth);
  }
  msstd_json_w_end_array(state->writer);
  return WRITTEN;
}

static int encode_bytes(Encode *state, const uint8_t *slot) {
  MsString text = ms_string_empty();
  msstd_encoding_base64_encode((const MsBytes *)(const void *)slot, 0, &text);
  msstd_json_w_string(state->writer, &text);
  ms_string_release(&text);
  return WRITTEN;
}

/* The entry layout of a map or set shape. */
static MsMapLayout map_layout(const MsShapeTable *table, const MsShape *shape) {
  const MsShape *key = ms_shape_at(table, shape->elem);
  if (shape->kind == MS_SHAPE_SET) {
    return ms_map_layout_of(key->size, key->align, 0, 1);
  }
  const MsShape *value = ms_shape_at(table, shape->value);
  return ms_map_layout_of(key->size, key->align, value->size, value->align);
}

static const uint8_t *live_entry(const MsMap *map, const MsMapLayout *layout, size_t at) {
  const uint8_t *entry = map->slots + at * layout->stride;
  return (*AT(uint64_t, entry) & MS_MAP_LIVE) != 0 ? entry : NULL;
}

static int encode_set(Encode *state, const MsShape *shape, const uint8_t *slot, int depth) {
  const MsMap *map = AT(MsMap, slot);
  const MsMapLayout layout = map_layout(state->table, shape);
  msstd_json_w_begin_array(state->writer);
  for (size_t at = 0; at < map->used; at++) {
    const uint8_t *entry = live_entry(map, &layout, at);
    if (entry != NULL) {
      encode_item(state, shape->elem, entry + layout.key_offset, depth);
    }
  }
  msstd_json_w_end_array(state->writer);
  return WRITTEN;
}

/* An alternative whose cases all lack a payload: a map key can name its case. */
static bool plain_alternative(const MsShapeTable *table, const MsShape *shape) {
  if (shape->kind != MS_SHAPE_ALTERNATIVE || shape->count == 0) {
    return false;
  }
  for (uint32_t at = 0; at < shape->count; at++) {
    if (ms_shape_member(table, shape->first + at)->count != 0) {
      return false;
    }
  }
  return true;
}

static bool keyable(const MsShapeTable *table, const MsShape *key) {
  switch (key->kind) {
  case MS_SHAPE_STRING:
  case MS_SHAPE_INT:
  case MS_SHAPE_UINT:
  case MS_SHAPE_BOOL:
  case MS_SHAPE_FLOAT:
  case MS_SHAPE_DECIMAL:
    return true;
  default:
    return (key->flags & MS_SHAPE_TEXT_FORM) != 0 || plain_alternative(table, key);
  }
}

static void encode_key(Encode *state, uint32_t shape_index, const uint8_t *slot) {
  const MsShape *shape = ms_shape_at(state->table, shape_index);
  if (shape->kind == MS_SHAPE_STRING) {
    msstd_json_w_key(state->writer, AT(MsString, slot));
    return;
  }
  MsString name = ms_string_empty();
  if (plain_alternative(state->table, shape)) {
    const MsShapeMember *which = ms_shape_active_case(state->table, shape, ms_shape_resolve(shape, slot));
    name = ms_string_static(ms_span_of_text(ms_shape_text(state->table, which->name)));
  } else {
    ms_shape_text_at(state->table, shape_index, slot, false, &name);
  }
  msstd_json_w_key(state->writer, &name);
  ms_string_release(&name);
}

/* A map is an object keyed by the text of its keys; a value without a JSON form leaves its entry out. */
static int encode_map(Encode *state, const MsShape *shape, const uint8_t *slot, int depth) {
  if (!keyable(state->table, ms_shape_at(state->table, shape->elem))) {
    return no_form(state);
  }
  const MsMap *map = AT(MsMap, slot);
  const MsMapLayout layout = map_layout(state->table, shape);
  msstd_json_w_begin_object(state->writer);
  for (size_t at = 0; at < map->used; at++) {
    const uint8_t *entry = live_entry(map, &layout, at);
    if (entry == NULL) {
      continue;
    }
    encode_key(state, shape->elem, entry + layout.key_offset);
    if (encode(state, shape->value, entry + layout.value_offset, depth + 1) == NO_FORM) {
      msstd_json_w_undo(state->writer);
    }
  }
  msstd_json_w_end_object(state->writer);
  return WRITTEN;
}

static int encode_optional(Encode *state, const MsShape *shape, const uint8_t *slot, int depth) {
  const uint8_t *payload = ms_shape_some(shape, slot);
  if (payload == NULL) {
    msstd_json_w_null(state->writer);
    return WRITTEN;
  }
  return encode(state, shape->elem, payload, depth + 1);
}

/* Writes member `field` of the value at `base` unless it has no JSON form; an absent optional is left out. */
static void encode_member(Encode *state, const MsShapeMember *field, const uint8_t *base, int depth) {
  uint32_t shape_index = field->shape;
  const uint8_t *slot = base + field->offset;
  const MsShape *shape = ms_shape_at(state->table, shape_index);
  if (shape->kind == MS_SHAPE_OPTIONAL && (shape->flags & MS_SHAPE_JSON_FORM) == 0) {
    slot = ms_shape_some(shape, ms_shape_resolve(shape, slot));
    if (slot == NULL) {
      return;
    }
    shape_index = shape->elem;
  }
  const MsString name = ms_string_static(ms_span_of_text(ms_shape_text(state->table, field->name)));
  msstd_json_w_key(state->writer, &name);
  if (encode(state, shape_index, slot, depth + 1) == NO_FORM) {
    msstd_json_w_undo(state->writer);
  }
}

static int encode_record(Encode *state, const MsShape *shape, const uint8_t *base, int depth) {
  msstd_json_w_begin_object(state->writer);
  for (uint32_t at = 0; at < shape->count; at++) {
    encode_member(state, ms_shape_member(state->table, shape->first + at), base, depth);
  }
  msstd_json_w_end_object(state->writer);
  return WRITTEN;
}

/* A bare case is its name; a case with fields is `{"Case": {fields}}`. */
static int encode_alternative(Encode *state, const MsShape *shape, const uint8_t *base, int depth) {
  const MsShapeMember *which = ms_shape_active_case(state->table, shape, base);
  const MsString name = ms_string_static(ms_span_of_text(ms_shape_text(state->table, which->name)));
  if (which->count == 0) {
    msstd_json_w_string(state->writer, &name);
    return WRITTEN;
  }
  msstd_json_w_begin_object(state->writer);
  msstd_json_w_key(state->writer, &name);
  msstd_json_w_begin_object(state->writer);
  for (uint32_t at = 0; at < which->count; at++) {
    encode_member(state, ms_shape_member(state->table, which->first + at), base, depth);
  }
  msstd_json_w_end_object(state->writer);
  msstd_json_w_end_object(state->writer);
  return WRITTEN;
}

/* The untyped JSON value is its own document: its case holds the value, a number as its token text. */
static int encode_tree(Encode *state, const MsShape *shape, const uint8_t *base, int depth) {
  const MsShapeMember *first = ms_shape_member(state->table, shape->first);
  const MsShapeMember *which = ms_shape_active_case(state->table, shape, base);
  const MsShapeMember *field = ms_shape_member(state->table, which->first);
  const uint8_t *payload = base + field->offset;
  switch (which - first) {
  case 2:
    msstd_json_w_number(state->writer, AT(MsString, payload));
    return WRITTEN;
  case 0:
    msstd_json_w_null(state->writer);
    return WRITTEN;
  default: /* bool, string, array and object: the payload's own form */
    return encode(state, field->shape, payload, depth + 1);
  }
}

/* A BigInt or Decimal is its digits, written as a number. */
static int encode_digits(Encode *state, uint32_t shape_index, const uint8_t *slot) {
  MsString digits = ms_string_empty();
  ms_shape_text_at(state->table, shape_index, slot, false, &digits);
  msstd_json_w_number(state->writer, &digits);
  ms_string_release(&digits);
  return WRITTEN;
}

static int encode(Encode *state, uint32_t shape_index, const uint8_t *slot, int depth) {
  const MsShape *shape = ms_shape_at(state->table, shape_index);
  if (depth >= MAX_DEPTH) {
    return no_form(state);
  }
  const uint8_t *value = ms_shape_resolve(shape, slot);
  const MsShapeHook *hook = ms_shape_hook(state->table, shape_index);
  if ((shape->flags & MS_SHAPE_JSON_FORM) != 0 && hook != NULL && hook->json_encode != NULL) {
    return hook->json_encode(slot, state->writer) == 0 ? WRITTEN : no_form(state);
  }
  if ((shape->flags & MS_SHAPE_JSON_TREE) != 0 && shape->kind == MS_SHAPE_ALTERNATIVE) {
    return encode_tree(state, shape, value, depth);
  }
  switch (shape->kind) {
  case MS_SHAPE_BOOL:
    msstd_json_w_bool(state->writer, *value);
    return WRITTEN;
  case MS_SHAPE_INT:
  case MS_SHAPE_UINT:
  case MS_SHAPE_FLOAT:
    return encode_number(state, shape, value);
  case MS_SHAPE_STRING:
    msstd_json_w_string(state->writer, AT(MsString, value));
    return WRITTEN;
  case MS_SHAPE_BYTES:
    return encode_bytes(state, value);
  case MS_SHAPE_LIST:
    return encode_list(state, shape, value, depth);
  case MS_SHAPE_SET:
    return encode_set(state, shape, value, depth);
  case MS_SHAPE_MAP:
    return encode_map(state, shape, value, depth);
  case MS_SHAPE_OPTIONAL:
    return encode_optional(state, shape, value, depth);
  case MS_SHAPE_RECORD:
    return encode_record(state, shape, value, depth);
  case MS_SHAPE_ALTERNATIVE:
    return encode_alternative(state, shape, value, depth);
  case MS_SHAPE_BIGINT:
  case MS_SHAPE_DECIMAL:
    return encode_digits(state, shape_index, value);
  default: /* VOID, OPAQUE, FUNCTION, OBJECT */
    return no_form(state);
  }
}

uint8_t msstd_json_w_value(void *writer, const MsShapeTable *table, const void *slot) {
  Encode state = {.table = table, .writer = writer};
  return encode(&state, table->image->root, slot, 0) == WRITTEN ? 0 : 1;
}

uint8_t msstd_json_stringify(const MsShapeTable *table, const void *value, uint8_t has_max_bytes,
                             int64_t max_bytes, uint8_t has_indent, int64_t indent, uint8_t strict,
                             MsString *out) {
  void *writer = msstd_json_writer_new(has_max_bytes, max_bytes, has_indent, indent);
  Encode state = {.table = table, .writer = writer};
  const int written = encode(&state, table->image->root, value, 0);
  uint8_t status = MS_STATUS_OK;
  if (written == NO_FORM || (strict != 0 && msstd_json_w_lost(writer) != 0)) {
    status = MS_STATUS_INVALID_DATA;
  } else {
    status = msstd_json_w_finish(writer, out);
  }
  msrt_obj_drop((MsObj *)writer);
  return status;
}

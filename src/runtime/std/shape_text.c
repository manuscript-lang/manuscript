/* The text form of a value, walked through its shape table. See shape_text.h. */
#include <string.h>
#include "base/map.h"
#include "base/strbuild.h"
#include "runtime/core/num.h"
#include "runtime/core/string_text.h"
#include "runtime/std/bigint.h"
#include "runtime/std/shape_text.h"

enum { MAX_DEPTH = 64 };

/* A slot address as a typed pointer; slots are aligned as their shape says. */
#define AT(type, address) ((const type *)(const void *)(address))

typedef struct Text {
  const MsShapeTable *table;
  MsStrBuild out;
  bool repr;
} Text;

static void emit(Text *text, uint32_t shape, const uint8_t *slot, int depth, bool nested);

static void append_owned(Text *text, MsString *piece) {
  ms_strbuild_append_string(&text->out, piece);
  ms_string_release(piece);
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

static uint64_t read_unsigned(const MsShape *shape, const uint8_t *slot) {
  switch (shape->size) {
  case 1:
    return *slot;
  case 2:
    return *AT(uint16_t, slot);
  case 4:
    return *AT(uint32_t, slot);
  default:
    return *AT(uint64_t, slot);
  }
}

static void append_number(Text *text, const MsShape *shape, const uint8_t *slot) {
  MsString piece = ms_string_empty();
  if (shape->kind == MS_SHAPE_UINT) {
    msrt_uint_to_string((int64_t)read_unsigned(shape, slot), &piece);
  } else if (shape->kind == MS_SHAPE_INT) {
    msrt_int_to_string(read_signed(shape, slot), &piece);
  } else if (shape->size == 4) {
    msrt_float32_to_string((double)*AT(float, slot), &piece);
  } else {
    msrt_float_to_string(*AT(double, slot), &piece);
  }
  append_owned(text, &piece);
}

static void append_string(Text *text, const uint8_t *slot, bool nested) {
  const MsString *string = AT(MsString, slot);
  if (text->repr) {
    MsString quoted = ms_string_empty();
    msrt_string_quote(string, &quoted);
    append_owned(text, &quoted);
  } else if (nested && ms_string_length(string) == 0) {
    ms_strbuild_append_text(&text->out, "\"\"");
  } else {
    ms_strbuild_append_string(&text->out, string);
  }
}

/* A scalar's text; false for a shape that is not one. */
static bool emit_scalar(Text *text, const MsShape *shape, const uint8_t *slot, bool nested) {
  switch (shape->kind) {
  case MS_SHAPE_VOID:
    ms_strbuild_append_text(&text->out, "void");
    return true;
  case MS_SHAPE_BOOL:
    ms_strbuild_append_text(&text->out, *slot != 0 ? "true" : "false");
    return true;
  case MS_SHAPE_INT:
  case MS_SHAPE_UINT:
  case MS_SHAPE_FLOAT:
    append_number(text, shape, slot);
    return true;
  case MS_SHAPE_STRING:
    append_string(text, slot, nested);
    return true;
  case MS_SHAPE_FUNCTION:
    ms_strbuild_append_text(&text->out, "[function]");
    return true;
  case MS_SHAPE_OBJECT:
    ms_strbuild_append_text(&text->out, "[object]");
    return true;
  default:
    return false;
  }
}

/* One nested value, or `...` once it would sit at the depth limit. */
static void emit_element(Text *text, uint32_t shape, const uint8_t *slot, int depth) {
  if (depth + 1 >= MAX_DEPTH) {
    ms_strbuild_append_text(&text->out, "...");
    return;
  }
  emit(text, shape, slot, depth + 1, true);
}

static void emit_list(Text *text, const MsShape *shape, const uint8_t *slot, int depth) {
  const MsList *list = AT(MsList, slot);
  const MsShape *element = ms_shape_at(text->table, shape->elem);
  ms_strbuild_append_byte(&text->out, '[');
  for (size_t at = 0; at < list->len; at++) {
    if (at > 0) {
      ms_strbuild_append_text(&text->out, ", ");
    }
    emit_element(text, shape->elem, (const uint8_t *)list->ptr + at * element->size, depth);
  }
  ms_strbuild_append_byte(&text->out, ']');
}

static void emit_bytes(Text *text, const uint8_t *slot) {
  const MsList *bytes = AT(MsList, slot);
  ms_strbuild_append_text(&text->out, text->repr ? "Bytes([" : "Bytes(");
  for (size_t at = 0; at < bytes->len; at++) {
    ms_strbuild_printf(&text->out, at > 0 ? ", %u" : "%u", (unsigned)AT(uint8_t, bytes->ptr)[at]);
  }
  ms_strbuild_append_text(&text->out, text->repr ? "])" : ")");
}

static void emit_map(Text *text, const MsShape *shape, const uint8_t *slot, int depth) {
  const bool is_map = shape->kind == MS_SHAPE_MAP;
  const MsMap *map = AT(MsMap, slot);
  const MsShape *key = ms_shape_at(text->table, shape->elem);
  const MsShape *value = is_map ? ms_shape_at(text->table, shape->value) : NULL;
  const MsMapLayout layout =
      ms_map_layout_of(key->size, key->align, is_map ? value->size : 0, is_map ? value->align : 1);
  ms_strbuild_append_text(&text->out, is_map ? "Map(" : "Set(");
  bool first = true;
  for (size_t at = 0; at < map->used; at++) {
    const uint8_t *entry = map->slots + at * layout.stride;
    if ((*AT(uint64_t, entry) & MS_MAP_LIVE) == 0) {
      continue;
    }
    if (!first) {
      ms_strbuild_append_text(&text->out, ", ");
    }
    first = false;
    emit_element(text, shape->elem, entry + layout.key_offset, depth);
    if (is_map) {
      ms_strbuild_append_text(&text->out, ": ");
      emit_element(text, shape->value, entry + layout.value_offset, depth);
    }
  }
  ms_strbuild_append_byte(&text->out, ')');
}

static void emit_optional(Text *text, const MsShape *shape, const uint8_t *slot, int depth) {
  const uint8_t *payload = ms_shape_some(shape, slot);
  if (payload == NULL) {
    ms_strbuild_append_text(&text->out, "none");
    return;
  }
  ms_strbuild_append_text(&text->out, "some(");
  emit_element(text, shape->elem, payload, depth);
  ms_strbuild_append_byte(&text->out, ')');
}

/* `label: value` of one field; the label only when `labeled`. */
static void emit_field(Text *text, const MsShapeMember *field, const uint8_t *base, bool labeled, int depth) {
  if (labeled) {
    ms_strbuild_append_text(&text->out, ms_shape_text(text->table, field->name));
    ms_strbuild_append_text(&text->out, ": ");
  }
  emit_element(text, field->shape, base + field->offset, depth);
}

/* Whether field `a` is written before field `b` in the plain form: by name. */
static bool name_before(const MsShapeTable *table, const MsShapeMember *a, const MsShapeMember *b) {
  const MsSpan left = ms_span_of_text(ms_shape_text(table, a->name));
  const MsSpan right = ms_span_of_text(ms_shape_text(table, b->name));
  const size_t common = left.len < right.len ? left.len : right.len;
  for (size_t at = 0; at < common; at++) {
    if (left.ptr[at] != right.ptr[at]) {
      return left.ptr[at] < right.ptr[at];
    }
  }
  return left.len < right.len;
}

/* The place of field `index` among the `count` fields from `first` when written by name; equal names keep
 * their declaration order. */
static uint32_t name_rank(const MsShapeTable *table, uint32_t first, uint32_t count, uint32_t index) {
  const MsShapeMember *field = ms_shape_member(table, first + index);
  uint32_t rank = 0;
  for (uint32_t other = 0; other < count; other++) {
    const MsShapeMember *candidate = ms_shape_member(table, first + other);
    if (name_before(table, candidate, field) || (!name_before(table, field, candidate) && other < index)) {
      rank++;
    }
  }
  return rank;
}

/* The field written at `position`: that field for repr, the one of that rank by name otherwise. */
static uint32_t field_at(const Text *text, uint32_t first, uint32_t count, uint32_t position) {
  if (text->repr) {
    return position;
  }
  for (uint32_t index = 0; index < count; index++) {
    if (name_rank(text->table, first, count, index) == position) {
      return index;
    }
  }
  return position;
}

/* The `count` fields from `first` as `(a: 1, b: 2)`, labeled when `labeled`. */
static void emit_fields(Text *text, uint32_t first, uint32_t count, const uint8_t *base, bool labeled,
                        int depth) {
  ms_strbuild_append_byte(&text->out, '(');
  for (uint32_t position = 0; position < count; position++) {
    if (position > 0) {
      ms_strbuild_append_text(&text->out, ", ");
    }
    const uint32_t index = field_at(text, first, count, position);
    emit_field(text, ms_shape_member(text->table, first + index), base, labeled, depth);
  }
  ms_strbuild_append_byte(&text->out, ')');
}

static void emit_record(Text *text, const MsShape *shape, const uint8_t *base, int depth) {
  ms_strbuild_append_text(&text->out, ms_shape_text(text->table, shape->name));
  emit_fields(text, shape->first, shape->count, base, true, depth);
}

/* `Case` and its payload; the plain form spells `Type.Case`, except for Result. */
static void emit_alternative(Text *text, const MsShape *shape, const uint8_t *base, int depth) {
  const MsShapeMember *which = ms_shape_active_case(text->table, shape, base);
  const char *type_name = ms_shape_text(text->table, shape->name);
  const MsSpan name = ms_span_of_text(type_name);
  const MsSpan result = ms_span_of_text("Result");
  const bool is_result = name.len >= result.len && __builtin_memcmp(name.ptr, result.ptr, result.len) == 0 &&
                         (name.len == result.len || name.ptr[result.len] == '[');
  if (!text->repr && !is_result) {
    ms_strbuild_append_text(&text->out, type_name);
    ms_strbuild_append_byte(&text->out, '.');
  }
  ms_strbuild_append_text(&text->out, ms_shape_text(text->table, which->name));
  if (which->count > 0) {
    emit_fields(text, which->first, which->count, base, text->repr, depth);
  }
}

static void emit(Text *text, uint32_t shape_index, const uint8_t *slot, int depth, bool nested) {
  const MsShape *shape = ms_shape_at(text->table, shape_index);
  const MsShapeHook *hook = ms_shape_hook(text->table, shape_index);
  if (emit_scalar(text, shape, slot, nested)) {
    return;
  }
  const uint8_t *value = ms_shape_resolve(shape, slot);
  if ((shape->flags & MS_SHAPE_TEXT_FORM) != 0 && hook != NULL && hook->to_text != NULL) {
    MsString piece = ms_string_empty();
    hook->to_text(slot, &piece);
    append_owned(text, &piece);
    return;
  }
  switch (shape->kind) {
  case MS_SHAPE_LIST:
    emit_list(text, shape, value, depth);
    return;
  case MS_SHAPE_BYTES:
    emit_bytes(text, value);
    return;
  case MS_SHAPE_MAP:
  case MS_SHAPE_SET:
    emit_map(text, shape, value, depth);
    return;
  case MS_SHAPE_OPTIONAL:
    emit_optional(text, shape, value, depth);
    return;
  case MS_SHAPE_RECORD:
    emit_record(text, shape, value, depth);
    return;
  case MS_SHAPE_ALTERNATIVE:
    emit_alternative(text, shape, value, depth);
    return;
  case MS_SHAPE_BIGINT: {
    MsString digits = ms_string_empty();
    msstd_bigint_to_string_radix(*(MsBigCell *const *)(const void *)slot, 10, &digits);
    append_owned(text, &digits);
    return;
  }
  default: /* OPAQUE, and DECIMAL without a text hook, show the type name */
    ms_strbuild_append_text(&text->out, ms_shape_text(text->table, shape->name));
    return;
  }
}

void ms_shape_text_at(const MsShapeTable *table, uint32_t shape, const void *value, bool repr,
                      MsString *out) {
  Text text = {.table = table, .out = ms_strbuild_new(), .repr = repr};
  emit(&text, shape, value, 0, false);
  *out = ms_strbuild_finish(&text.out);
  ms_strbuild_free(&text.out);
}

void ms_shape_text_of(const MsShapeTable *table, const void *value, bool repr, MsString *out) {
  ms_shape_text_at(table, table->image->root, value, repr, out);
}

void msstd_test_repr(const MsShapeTable *table, const void *value, MsString *out) {
  ms_shape_text_of(table, value, true, out);
}

void msstd_value_text(const MsShapeTable *table, const void *value, MsString *out) {
  ms_shape_text_of(table, value, false, out);
}

/* `value.to_string()` on a type with no `to_string` of its own is its printed form. */
void msstd_value_to_string(const MsShapeTable *table, const void *value, MsString *out) {
  ms_shape_text_of(table, value, false, out);
}

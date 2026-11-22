/* Structural equality of two values, walked through their shape table. See shape_equal.h. */
#include "base/map.h"
#include "runtime/std/shape_equal.h"

#define AT(type, address) ((const type *)(const void *)(address))

static bool equal_at(const MsShapeTable *table, uint32_t shape_index, const uint8_t *a, const uint8_t *b, int depth);

static bool same_bytes(const uint8_t *a, const uint8_t *b, size_t count) {
  return count == 0 || __builtin_memcmp(a, b, count) == 0;
}

static bool equal_strings(const MsString *a, const MsString *b) {
  const MsSpan left = ms_string_span(a);
  const MsSpan right = ms_string_span(b);
  return left.len == right.len && same_bytes(left.ptr, right.ptr, left.len);
}

static bool equal_lists(const MsShapeTable *table, const MsShape *shape, const uint8_t *a, const uint8_t *b, int depth) {
  const MsList *left = AT(MsList, a);
  const MsList *right = AT(MsList, b);
  const MsShape *element = ms_shape_at(table, shape->elem);
  if (left->len != right->len) {
    return false;
  }
  for (size_t at = 0; at < left->len; at++) {
    const size_t offset = at * element->size;
    if (!equal_at(table, shape->elem, (const uint8_t *)left->ptr + offset, (const uint8_t *)right->ptr + offset,
                  depth + 1)) {
      return false;
    }
  }
  return true;
}

static bool equal_fields(const MsShapeTable *table, uint32_t first, uint32_t count, const uint8_t *a, const uint8_t *b,
                         int depth) {
  for (uint32_t at = 0; at < count; at++) {
    const MsShapeMember *field = ms_shape_member(table, first + at);
    if (!equal_at(table, field->shape, a + field->offset, b + field->offset, depth + 1)) {
      return false;
    }
  }
  return true;
}

/* The live entry of `map` whose key equals the key at `key`, or NULL. */
static const uint8_t *find_entry(const MsShapeTable *table, const MsShape *shape, const MsMap *map,
                                 const MsMapLayout *layout, const uint8_t *key, int depth) {
  for (size_t at = 0; at < map->used; at++) {
    const uint8_t *entry = map->slots + at * layout->stride;
    if ((*AT(uint64_t, entry) & MS_MAP_LIVE) != 0 &&
        equal_at(table, shape->elem, entry + layout->key_offset, key, depth + 1)) {
      return entry;
    }
  }
  return NULL;
}

static bool equal_maps(const MsShapeTable *table, const MsShape *shape, const uint8_t *a, const uint8_t *b, int depth) {
  const bool is_map = shape->kind == MS_SHAPE_MAP;
  const MsMap *left = AT(MsMap, a);
  const MsMap *right = AT(MsMap, b);
  const MsShape *key = ms_shape_at(table, shape->elem);
  const MsShape *value = is_map ? ms_shape_at(table, shape->value) : NULL;
  const MsMapLayout layout = ms_map_layout_of(key->size, key->align, is_map ? value->size : 0, is_map ? value->align : 1);
  if (left->len != right->len) {
    return false;
  }
  for (size_t at = 0; at < left->used; at++) {
    const uint8_t *entry = left->slots + at * layout.stride;
    if ((*AT(uint64_t, entry) & MS_MAP_LIVE) == 0) {
      continue;
    }
    const uint8_t *other = find_entry(table, shape, right, &layout, entry + layout.key_offset, depth);
    if (other == NULL || (is_map && !equal_at(table, shape->value, entry + layout.value_offset,
                                              other + layout.value_offset, depth + 1))) {
      return false;
    }
  }
  return true;
}

static bool equal_scalar(const MsShape *shape, const uint8_t *a, const uint8_t *b) {
  if (shape->kind == MS_SHAPE_FLOAT) {
    return shape->size == 4 ? *AT(float, a) == *AT(float, b) : *AT(double, a) == *AT(double, b);
  }
  return same_bytes(a, b, shape->size);
}

static bool equal_at(const MsShapeTable *table, uint32_t shape_index, const uint8_t *a, const uint8_t *b, int depth) {
  const MsShape *shape = ms_shape_at(table, shape_index);
  if (depth > 256) {
    return false;
  }
  switch (shape->kind) {
  case MS_SHAPE_VOID:
    return true;
  case MS_SHAPE_BOOL:
  case MS_SHAPE_INT:
  case MS_SHAPE_UINT:
  case MS_SHAPE_FLOAT:
    return equal_scalar(shape, a, b);
  case MS_SHAPE_STRING:
    return equal_strings(AT(MsString, a), AT(MsString, b));
  default:
    break;
  }
  const uint8_t *left = ms_shape_resolve(shape, a);
  const uint8_t *right = ms_shape_resolve(shape, b);
  switch (shape->kind) {
  case MS_SHAPE_BYTES: {
    const MsList *x = AT(MsList, left);
    const MsList *y = AT(MsList, right);
    return x->len == y->len && same_bytes(x->ptr, y->ptr, x->len);
  }
  case MS_SHAPE_LIST:
    return equal_lists(table, shape, left, right, depth);
  case MS_SHAPE_MAP:
  case MS_SHAPE_SET:
    return equal_maps(table, shape, left, right, depth);
  case MS_SHAPE_OPTIONAL: {
    const uint8_t *x = ms_shape_some(shape, left);
    const uint8_t *y = ms_shape_some(shape, right);
    return x == NULL || y == NULL ? x == y : equal_at(table, shape->elem, x, y, depth + 1);
  }
  case MS_SHAPE_RECORD:
    return equal_fields(table, shape->first, shape->count, left, right, depth);
  case MS_SHAPE_ALTERNATIVE: {
    const MsShapeMember *x = ms_shape_active_case(table, shape, left);
    const MsShapeMember *y = ms_shape_active_case(table, shape, right);
    return x == y && equal_fields(table, x->first, x->count, left, right, depth);
  }
  default: /* a handle, a function, a number of unbounded size: the same value or none */
    return left == right;
  }
}

uint8_t msstd_value_equals(const MsShapeTable *table, const void *a, const void *b) {
  return equal_at(table, table->image->root, a, b, 0) ? 1 : 0;
}

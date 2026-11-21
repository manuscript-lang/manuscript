/* The tree natives of @std/data/json for the untyped `JsonValue`: parse text straight into a value of that
 * recursive alternative, and write such a value as JSON. The alternative's layout belongs to the compiler, so
 * it passes two thunks: a constructor that moves a payload (a Bool byte, a String, a list or a String-keyed
 * map of the alternative) into a value of a case, and a view that writes a value's case itself. Both sides
 * are iterative, so nesting depth costs heap and not native stack. */
#include "runtime/std/json_internal.h"
#include "base/array.h"
#include "base/list.h"
#include "base/desc.h"
#include "runtime/std/json.h"
#include "base/map.h"
#include "runtime/core/map.h"
#include "base/strbuild.h"

/* The cases of the alternative, as the constructor thunk numbers them. */
enum { CASE_NULL = 0, CASE_BOOL = 1, CASE_NUMBER = 2, CASE_STRING = 3, CASE_ARRAY = 4, CASE_OBJECT = 5 };

/* ---- building a tree from parse events ---- */

/* Where an open container began on the two stacks. */
typedef struct Mark {
  size_t values;
  size_t keys;
} Mark;

typedef struct TreeBuilder {
  const MsTypeDesc *desc;
  JsonCtorFn ctor;
  size_t size;     /* bytes per value, a multiple of 8 */
  uint8_t *values; /* owned: completed values not yet moved into a container, `size` bytes each */
  size_t value_count;
  size_t value_capacity;
  MsString *keys; /* owned: keys of the open objects' members so far */
  size_t key_count;
  size_t key_capacity;
  Mark *marks; /* owned */
  size_t mark_count;
  size_t mark_capacity;
} TreeBuilder;

static uint8_t *value_at(const TreeBuilder *builder, size_t index) {
  return builder->values + index * builder->size;
}

/* Room for one more completed value; the constructor writes it. */
static uint8_t scalar(TreeBuilder *builder, int64_t kind, uint8_t *payload) {
  void *values = builder->values;
  if (!ms_array_reserve(&values, &builder->value_capacity, builder->value_count + 1, builder->size)) {
    return MS_STATUS_LIMIT_EXCEEDED;
  }
  builder->values = values;
  (void)builder->ctor(kind, payload, value_at(builder, builder->value_count));
  builder->value_count++;
  return MS_STATUS_OK;
}

static uint8_t tree_null(void *sink) {
  return scalar(sink, CASE_NULL, NULL);
}

static uint8_t tree_boolean(void *sink, bool value) {
  uint8_t byte = value ? 1 : 0;
  return scalar(sink, CASE_BOOL, &byte);
}

static uint8_t tree_text(TreeBuilder *builder, int64_t kind, JsonText text) {
  MsString string = {0};
  *(&string) = ms_string_from_span(ms_span_of(text.bytes.ptr, text.bytes.len));
  return scalar(builder, kind, (uint8_t *)&string);
}

static uint8_t tree_number(void *sink, JsonText text) {
  return tree_text(sink, CASE_NUMBER, text);
}
static uint8_t tree_string(void *sink, JsonText text) {
  return tree_text(sink, CASE_STRING, text);
}

static uint8_t tree_key(void *sink, JsonText text) {
  TreeBuilder *builder = sink;
  void *keys = builder->keys;
  if (!ms_array_reserve(&keys, &builder->key_capacity, builder->key_count + 1, sizeof *builder->keys)) {
    return MS_STATUS_LIMIT_EXCEEDED;
  }
  builder->keys = keys;
  *(&builder->keys[builder->key_count++]) = ms_string_from_span(ms_span_of(text.bytes.ptr, text.bytes.len));
  return MS_STATUS_OK;
}

static uint8_t tree_open(void *sink, bool is_array) {
  TreeBuilder *builder = sink;
  void *marks = builder->marks;
  (void)is_array;
  if (!ms_array_reserve(&marks, &builder->mark_capacity, builder->mark_count + 1, sizeof *builder->marks)) {
    return MS_STATUS_LIMIT_EXCEEDED;
  }
  builder->marks = marks;
  builder->marks[builder->mark_count++] = (Mark){.values = builder->value_count, .keys = builder->key_count};
  return MS_STATUS_OK;
}

/* Moves the children above `from` into a list and builds the array case. */
static uint8_t close_array(TreeBuilder *builder, Mark mark) {
  const size_t count = builder->value_count - mark.values;
  MsList list = {0};
  size_t bytes = 0;
  if (count > 0) {
    if (!ms_size_mul(count, builder->size, &bytes)) {
      return MS_STATUS_LIMIT_EXCEEDED;
    }
    list.ptr = ms_alloc(bytes);
    memcpy(list.ptr, value_at(builder, mark.values), bytes);
    list.len = count;
    list.cap = count;
  }
  builder->value_count = mark.values;
  return scalar(builder, CASE_ARRAY, (uint8_t *)&list);
}

/* Releases the members from `from` on, which a map did not take. */
static void drop_members(TreeBuilder *builder, Mark mark, size_t from) {
  for (size_t i = from; i < builder->key_count - mark.keys; i++) {
    ms_slot_drop(&ms_desc_string, (uint8_t *)&builder->keys[mark.keys + i]);
    ms_slot_drop(builder->desc, value_at(builder, mark.values + i));
  }
}

/* Moves the members above `from` into a String-keyed map and builds the object case. MS_STATUS_INVALID_DATA
 * when two members share a key (everything is released). */
static uint8_t close_object(TreeBuilder *builder, Mark mark) {
  const size_t count = builder->key_count - mark.keys;
  MsMap map = {0};
  uint8_t status = MS_STATUS_OK;
  msrt_map_new(&map);
  msrt_map_stamp(&map, &ms_desc_string);
  if (count > 0) {
    msrt_map_reserve(&map, &ms_desc_string, builder->desc, (int64_t)count);
  }
  for (size_t i = 0; i < count && status == MS_STATUS_OK; i++) {
    uint8_t *key = (uint8_t *)&builder->keys[mark.keys + i];
    if (msrt_map_contains(&map, &ms_desc_string, builder->desc, key)) {
      drop_members(builder, mark, i);
      msrt_map_drop(&map, &ms_desc_string, builder->desc);
      status = MS_STATUS_INVALID_DATA;
    } else {
      msrt_map_add(&map, &ms_desc_string, builder->desc, key, value_at(builder, mark.values + i));
    }
  }
  builder->key_count = mark.keys;
  builder->value_count = mark.values;
  return status == MS_STATUS_OK ? scalar(builder, CASE_OBJECT, (uint8_t *)&map) : status;
}

static uint8_t tree_close(void *sink, bool is_array) {
  TreeBuilder *builder = sink;
  const Mark mark = builder->marks[--builder->mark_count];
  return is_array ? close_array(builder, mark) : close_object(builder, mark);
}

static const JsonSinkOps tree_ops = {.null = tree_null,
                                     .boolean = tree_boolean,
                                     .number = tree_number,
                                     .string = tree_string,
                                     .key = tree_key,
                                     .open = tree_open,
                                     .close = tree_close};

/* Releases every value and key still on the stacks, and the stacks. */
static void builder_free(TreeBuilder *builder) {
  for (size_t i = 0; i < builder->value_count; i++) {
    ms_slot_drop(builder->desc, value_at(builder, i));
  }
  for (size_t i = 0; i < builder->key_count; i++) {
    ms_slot_drop(&ms_desc_string, (uint8_t *)&builder->keys[i]);
  }
  ms_free(builder->values);
  ms_free(builder->keys);
  ms_free(builder->marks);
}

/* Parses `text` into one value of the alternative described by `desc`, built by `ctor`, written to `out` on
 * success. */
uint8_t msstd_json_parse_tree(const MsString *text, uint8_t has_max_bytes, int64_t max_bytes,
                              uint8_t has_max_depth, int64_t max_depth, uint8_t has_max_values,
                              int64_t max_values, const MsTypeDesc *desc, JsonCtorFn ctor, uint8_t *out,
                              MsString *err) {
  if (err != NULL) {
    *(err) = ms_string_empty(); /* the caller may read the slot for any failure status */
  }
  const MsSpan source = ms_string_span(text);
  JsonLimits limits = {0};
  const uint8_t limited = json_limits(source.len, has_max_bytes, max_bytes, has_max_depth, max_depth,
                                      has_max_values, max_values, &limits);
  if (limited != MS_STATUS_OK) {
    return limited;
  }
  if (desc->align > 8 || desc->size % 8 != 0 || desc->size == 0) {
    return MS_STATUS_FAILED;
  }
  TreeBuilder builder = {.desc = desc, .ctor = ctor, .size = desc->size};
  JsonStop stop = {0};
  const uint8_t status = json_scan(source, limits, &tree_ops, &builder, &stop);
  if (status == MS_STATUS_OK && builder.value_count == 1 && builder.mark_count == 0) {
    memcpy(out, builder.values, builder.size);
    builder.value_count = 0; /* moved to the caller */
    builder_free(&builder);
    return MS_STATUS_OK;
  }
  builder_free(&builder);
  if (status == MS_STATUS_OK) {
    return MS_STATUS_FAILED;
  }
  if (status == MS_STATUS_INVALID_DATA && err != NULL) {
    json_explain(source, stop, err);
  }
  return status;
}

/* ---- walking a tree into the writer ---- */

/* An open container of a walk: the next element of an array, or the next slot of a map's storage. */
typedef struct Open {
  bool is_array;
  const uint8_t *at; /* array: the next element */
  size_t left;       /* array: elements left */
  MsMap map;         /* object: a copy of the map header; the entries stay where they are */
  size_t slot;       /* object: the next slot of the map's storage */
  size_t slots;
} Open;

struct JsonWalk {
  JsonWriter *writer;
  const MsTypeDesc *desc;
  Open *open; /* owned */
  size_t open_count;
  size_t open_capacity;
};

static void walk_push(JsonWalk *walk, Open open) {
  void *items = walk->open;
  if (!ms_array_reserve(&items, &walk->open_capacity, walk->open_count + 1, sizeof *walk->open)) {
    return;
  }
  walk->open = items;
  walk->open[walk->open_count++] = open;
}

void msstd_json_tree_array(JsonWalk *walk, const MsList *list) {
  json_writer_begin(walk->writer, true);
  walk_push(walk, (Open){.is_array = true, .at = list->ptr, .left = list->len});
}

void msstd_json_tree_object(JsonWalk *walk, const MsMap *map) {
  json_writer_begin(walk->writer, false);
  walk_push(walk, (Open){.map = *map, .slots = (size_t)msrt_map_slot_count(map)});
}

/* The next value of an open array: the element after the last one visited. */
static bool next_element(JsonWalk *walk, Open *top, const uint8_t **value) {
  if (top->left == 0) {
    json_writer_end(walk->writer, true);
    return false;
  }
  json_writer_item(walk->writer);
  *value = top->at;
  top->at += walk->desc->size;
  top->left--;
  return true;
}

/* The next member of an open object, after writing its key. */
static bool next_member(JsonWalk *walk, Open *top, const uint8_t **value) {
  const uint8_t *key = NULL;
  while (top->slot < top->slots) {
    if (msrt_map_entry_ptrs(&top->map, &ms_desc_string, walk->desc, (int64_t)top->slot++, &key, value)) {
      MsString name;
      memcpy(&name, key, sizeof name);
      json_writer_key(walk->writer, ms_string_span(&name));
      return true;
    }
  }
  json_writer_end(walk->writer, false);
  return false;
}

/* Walks `root`, a value of the alternative described by `desc` read through `view`, writing it as the
 * writer's next value. */
void msstd_json_w_tree(void *w, const MsTypeDesc *desc, JsonViewFn view, const uint8_t *root) {
  JsonWalk walk = {.writer = w, .desc = desc};
  const uint8_t *value = root;
  for (;;) {
    view(value, w, (uint8_t *)&walk);
    bool found = false;
    while (walk.open_count > 0 && !found) {
      Open *top = &walk.open[walk.open_count - 1];
      found = top->is_array ? next_element(&walk, top, &value) : next_member(&walk, top, &value);
      if (!found) {
        walk.open_count--;
      }
    }
    if (!found) {
      break;
    }
  }
  ms_free(walk.open);
}

/* The JSON document handle of @std/data/json: a parse yields a document (an arena of nodes) that the
 * generated typed decoders read through node ids, and the cold path that explains why a typed decode rejected
 * a node. A document allocates a handful of arrays however large it is: strings and numbers are spans of one
 * text buffer (the parsed source, then decoded escapes), and containers are ranges of two shared pools. Node
 * ids are only valid for the document that issued them. */
#include <stdio.h>
#include <string.h>

#include "runtime/std/json_internal.h"
#include "base/array.h"
#include "base/list.h"
#include "runtime/std/json.h"
#include "base/strbuild.h"

/* The node kinds are the ABI kinds of msstd_json_kind. */
enum { KIND_NULL = 0, KIND_BOOL = 1, KIND_NUMBER = 2, KIND_STRING = 3, KIND_ARRAY = 4, KIND_OBJECT = 5 };

/* A node: a bool holds its value in `first`; a number or string, its span of the text (offset and length); an
 * array or object, a range of the item or member pool (start and count). */
typedef struct JsonNode {
  uint8_t kind;
  uint32_t first;
  uint32_t count;
} JsonNode;

typedef struct JsonMember {
  uint32_t key_offset;
  uint32_t key_length;
  uint32_t value; /* node id */
} JsonMember;

/* The last node a typed decoder rejected, see json_mismatch_text. */
typedef struct Mismatch {
  bool present;
  uint32_t node;
  uint8_t code;
  MsString text; /* owned */
} Mismatch;

typedef struct JsonDoc {
  MsObj header;
  JsonBuffer text; /* the source, then decoded escapes */
  JsonNode *nodes; /* owned */
  size_t node_count;
  size_t node_capacity;
  uint32_t *items; /* owned: array children */
  size_t item_count;
  size_t item_capacity;
  JsonMember *members; /* owned */
  size_t member_count;
  size_t member_capacity;
  Mismatch *mismatch; /* owned: the cold-path record, written through a const handle */
} JsonDoc;

static void doc_drop(MsObj *object) {
  JsonDoc *doc = (JsonDoc *)object;
  json_buffer_free(&doc->text);
  ms_free(doc->nodes);
  ms_free(doc->items);
  ms_free(doc->members);
  if (doc->mismatch != NULL && doc->mismatch->present) {
    ms_string_release(&doc->mismatch->text);
  }
  ms_free(doc->mismatch);
  ms_free(doc);
}

/* ---- building a document from parse events ---- */

/* An open container and where its children begin in `pending` (arrays) or `open_members` (objects). */
typedef struct Frame {
  bool is_array;
  size_t start;
} Frame;

typedef struct DocBuilder {
  JsonDoc *doc;
  size_t source_length; /* the source copy at the start of the text */
  uint32_t *pending;    /* owned: children of the open arrays, not yet in the pool */
  size_t pending_count;
  size_t pending_capacity;
  JsonMember *open_members; /* owned: members of the open objects, the last one awaiting its value */
  size_t open_members_count;
  size_t open_members_capacity;
  Frame *frames; /* owned */
  size_t frames_count;
  size_t frames_capacity;
  uint32_t root;
} DocBuilder;

#define BUILDER_PUSH(builder, field, value)                                                                  \
  (ms_array_reserve((void **)&(builder)->field, &(builder)->field##_capacity, (builder)->field##_count + 1,  \
                    sizeof *(builder)->field)                                                                \
       ? ((builder)->field[(builder)->field##_count++] = (value), true)                                      \
       : false)

static bool doc_node(JsonDoc *doc, JsonNode node, uint32_t *id) {
  if (!ms_array_reserve((void **)&doc->nodes, &doc->node_capacity, doc->node_count + 1, sizeof *doc->nodes) ||
      doc->node_count >= UINT32_MAX) {
    return false;
  }
  *id = (uint32_t)doc->node_count;
  doc->nodes[doc->node_count++] = node;
  return true;
}

/* Attaches a completed value to the open container, or makes it the root. */
static uint8_t attach(DocBuilder *builder, uint32_t id) {
  if (builder->frames_count == 0) {
    builder->root = id;
    return MS_STATUS_OK;
  }
  if (builder->frames[builder->frames_count - 1].is_array) {
    return BUILDER_PUSH(builder, pending, id) ? MS_STATUS_OK : MS_STATUS_LIMIT_EXCEEDED;
  }
  builder->open_members[builder->open_members_count - 1].value = id;
  return MS_STATUS_OK;
}

static uint8_t add_leaf(DocBuilder *builder, JsonNode node) {
  uint32_t id = 0;
  return doc_node(builder->doc, node, &id) ? attach(builder, id) : MS_STATUS_LIMIT_EXCEEDED;
}

/* The span of `text` in the document's text: a span of the source copy, or the decoded bytes appended. */
static bool text_span(DocBuilder *builder, JsonText text, uint32_t *offset) {
  JsonBuffer *buffer = &builder->doc->text;
  if (text.source_offset != JSON_DECODED) {
    *offset = (uint32_t)text.source_offset;
    return true;
  }
  if (buffer->bytes.len > UINT32_MAX || !json_buffer_append(buffer, text.bytes)) {
    return false;
  }
  *offset = (uint32_t)(buffer->bytes.len - text.bytes.len);
  return true;
}

static uint8_t doc_null(void *sink) {
  return add_leaf(sink, (JsonNode){.kind = KIND_NULL});
}

static uint8_t doc_boolean(void *sink, bool value) {
  return add_leaf(sink, (JsonNode){.kind = KIND_BOOL, .first = value});
}

static uint8_t doc_text(DocBuilder *builder, uint8_t kind, JsonText text) {
  uint32_t offset = 0;
  if (!text_span(builder, text, &offset) || text.bytes.len > UINT32_MAX) {
    return MS_STATUS_LIMIT_EXCEEDED;
  }
  return add_leaf(builder, (JsonNode){.kind = kind, .first = offset, .count = (uint32_t)text.bytes.len});
}

static uint8_t doc_number(void *sink, JsonText text) {
  return doc_text(sink, KIND_NUMBER, text);
}
static uint8_t doc_string(void *sink, JsonText text) {
  return doc_text(sink, KIND_STRING, text);
}

static uint8_t doc_key(void *sink, JsonText text) {
  DocBuilder *builder = sink;
  uint32_t offset = 0;
  if (!text_span(builder, text, &offset) || text.bytes.len > UINT32_MAX) {
    return MS_STATUS_LIMIT_EXCEEDED;
  }
  const JsonMember member = {.key_offset = offset, .key_length = (uint32_t)text.bytes.len};
  return BUILDER_PUSH(builder, open_members, member) ? MS_STATUS_OK : MS_STATUS_LIMIT_EXCEEDED;
}

static uint8_t doc_open(void *sink, bool is_array) {
  DocBuilder *builder = sink;
  const Frame frame = {.is_array = is_array,
                       .start = is_array ? builder->pending_count : builder->open_members_count};
  return BUILDER_PUSH(builder, frames, frame) ? MS_STATUS_OK : MS_STATUS_LIMIT_EXCEEDED;
}

static bool key_equal(const JsonDoc *doc, const JsonMember *a, const JsonMember *b) {
  return ms_span_equal(ms_span_of(doc->text.bytes.ptr + a->key_offset, a->key_length),
                       ms_span_of(doc->text.bytes.ptr + b->key_offset, b->key_length));
}

/* A hash of the key's length and its first and last eight bytes (fewer for a short key), read as words. Keys
 * that collide are compared in full, so this only has to spread keys, not identify them. */
static uint64_t key_hash(const JsonDoc *doc, const JsonMember *member) {
  const uint8_t *key = doc->text.bytes.ptr + member->key_offset;
  const size_t length = member->key_length;
  uint64_t first = 0;
  uint64_t last = 0;
  if (length >= 8) {
    first = ms_load64(key);
    last = ms_load64(key + length - 8);
  } else if (length >= 4) {
    first = ms_load32(key);
    last = ms_load32(key + length - 4);
  } else if (length > 0) {
    first = key[0];
    last = (uint64_t)key[length - 1] | ((uint64_t)key[length / 2] << 8);
  }
  const uint64_t mixed = (first ^ ((last << 29) | (last >> 35)) ^ length) * UINT64_C(0x9E3779B97F4A7C15);
  return mixed ^ (mixed >> 32);
}

/* Objects up to this many members detect a repeated key by pairwise comparison; larger ones hash their keys,
 * into a table on the stack up to STACK_TABLE_SLOTS slots. */
enum { LINEAR_KEYS = 4, STACK_TABLE_SLOTS = 128 };

/* Whether two of the `count` members share a key: each member's index, plus one, goes into an open-addressing
 * table of at least twice as many slots, and a key that lands on an equal one is a repeat. */
static bool has_duplicate(const JsonDoc *doc, const JsonMember *members, size_t count) {
  if (count <= LINEAR_KEYS) {
    for (size_t i = 1; i < count; i++) {
      for (size_t j = 0; j < i; j++) {
        if (key_equal(doc, &members[i], &members[j])) {
          return true;
        }
      }
    }
    return false;
  }
  size_t size = 4;
  while (size < count * 2) {
    size *= 2;
  }
  uint32_t stack_table[STACK_TABLE_SLOTS];
  uint32_t *table = stack_table;
  if (size > STACK_TABLE_SLOTS) {
    table = ms_alloc_zeroed(size * sizeof *table);
  } else {
    memset(stack_table, 0, size * sizeof *table);
  }
  bool found = false;
  for (size_t i = 0; i < count && !found; i++) {
    size_t slot = (size_t)key_hash(doc, &members[i]) & (size - 1);
    while (table[slot] != 0) {
      if (key_equal(doc, &members[table[slot] - 1], &members[i])) {
        found = true;
        break;
      }
      slot = (slot + 1) & (size - 1);
    }
    table[slot] = (uint32_t)i + 1;
  }
  if (table != stack_table) {
    ms_free(table);
  }
  return found;
}

/* Moves the closing container's children into the pools and adds its node. */
static uint8_t doc_close(void *sink, bool is_array) {
  DocBuilder *builder = sink;
  JsonDoc *doc = builder->doc;
  const Frame frame = builder->frames[--builder->frames_count];
  JsonNode node = {.kind = is_array ? KIND_ARRAY : KIND_OBJECT};
  if (is_array) {
    const size_t count = builder->pending_count - frame.start;
    if (!ms_array_reserve((void **)&doc->items, &doc->item_capacity, doc->item_count + count,
                          sizeof *doc->items)) {
      return MS_STATUS_LIMIT_EXCEEDED;
    }
    node.first = (uint32_t)doc->item_count;
    node.count = (uint32_t)count;
    if (count > 0) {
      memcpy(doc->items + doc->item_count, builder->pending + frame.start, count * sizeof *doc->items);
    }
    doc->item_count += count;
    builder->pending_count = frame.start;
  } else {
    const size_t count = builder->open_members_count - frame.start;
    const JsonMember *members = builder->open_members + frame.start;
    if (has_duplicate(doc, members, count)) {
      return MS_STATUS_INVALID_DATA;
    }
    if (!ms_array_reserve((void **)&doc->members, &doc->member_capacity, doc->member_count + count,
                          sizeof *doc->members)) {
      return MS_STATUS_LIMIT_EXCEEDED;
    }
    node.first = (uint32_t)doc->member_count;
    node.count = (uint32_t)count;
    if (count > 0) {
      memcpy(doc->members + doc->member_count, members, count * sizeof *doc->members);
    }
    doc->member_count += count;
    builder->open_members_count = frame.start;
  }
  return add_leaf(builder, node);
}

static const JsonSinkOps doc_ops = {.null = doc_null,
                                    .boolean = doc_boolean,
                                    .number = doc_number,
                                    .string = doc_string,
                                    .key = doc_key,
                                    .open = doc_open,
                                    .close = doc_close};

static void builder_free(DocBuilder *builder) {
  ms_free(builder->pending);
  ms_free(builder->open_members);
  ms_free(builder->frames);
}

/* ---- parse ---- */

uint8_t msstd_json_parse(const MsString *text, uint8_t has_max_bytes, int64_t max_bytes,
                         uint8_t has_max_depth, int64_t max_depth, uint8_t has_max_values, int64_t max_values,
                         void **out, uint32_t *root, MsString *err) {
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
  JsonDoc *doc = ms_alloc_zeroed(sizeof *doc);
  doc->header.drop = doc_drop;
  doc->mismatch = ms_alloc_zeroed(sizeof *doc->mismatch);
  doc->text.limit = MS_STRING_MAX_LENGTH;
  DocBuilder builder = {.doc = doc, .source_length = source.len};
  JsonStop stop = {0};
  uint8_t status = json_buffer_append(&doc->text, source)
                       ? json_scan(source, limits, &doc_ops, &builder, &stop)
                       : MS_STATUS_LIMIT_EXCEEDED;
  builder_free(&builder);
  if (status != MS_STATUS_OK) {
    if (status == MS_STATUS_INVALID_DATA && err != NULL) {
      json_explain(source, stop, err);
    }
    doc_drop(&doc->header);
    return status;
  }
  *out = doc;
  *root = builder.root;
  return MS_STATUS_OK;
}

/* ---- reading a document ---- */

static const JsonNode *node_of(const JsonDoc *doc, uint32_t id) {
  return id < doc->node_count ? &doc->nodes[id] : NULL;
}

static MsSpan span_of(const JsonDoc *doc, uint32_t offset, uint32_t length) {
  return ms_span_of(doc->text.bytes.ptr + offset, length);
}

/* The text of a string or number node, else empty. */
static MsSpan text_of(const JsonDoc *doc, uint32_t id) {
  const JsonNode *node = node_of(doc, id);
  if (node == NULL || (node->kind != KIND_NUMBER && node->kind != KIND_STRING)) {
    return ms_span_of(NULL, 0);
  }
  return span_of(doc, node->first, node->count);
}

/* The members of an object node, else none. */
static const JsonMember *members_of(const JsonDoc *doc, uint32_t id, size_t *count) {
  const JsonNode *node = node_of(doc, id);
  *count = node != NULL && node->kind == KIND_OBJECT ? node->count : 0;
  return *count == 0 ? NULL : doc->members + node->first;
}

/* The children of an array node, else none. */
static const uint32_t *items_of(const JsonDoc *doc, uint32_t id, size_t *count) {
  const JsonNode *node = node_of(doc, id);
  *count = node != NULL && node->kind == KIND_ARRAY ? node->count : 0;
  return *count == 0 ? NULL : doc->items + node->first;
}

/* The caller owns the string: the document may be dropped while a decoded value still holds the text. */
static void owned_text(MsSpan bytes, MsString *out) {
  *(out) = ms_string_from_span(ms_span_of(bytes.ptr, bytes.len));
}

uint8_t msstd_json_kind(const void *d, uint32_t id) {
  const JsonNode *node = node_of(d, id);
  return node == NULL ? KIND_NULL : node->kind;
}

uint8_t msstd_json_bool(const void *d, uint32_t id) {
  const JsonNode *node = node_of(d, id);
  return node != NULL && node->kind == KIND_BOOL && node->first != 0;
}

void msstd_json_text(const void *d, uint32_t id, MsString *out) {
  owned_text(text_of(d, id), out);
}

int64_t msstd_json_len(const void *d, uint32_t id) {
  const JsonNode *node = node_of(d, id);
  return node != NULL && (node->kind == KIND_ARRAY || node->kind == KIND_OBJECT) ? (int64_t)node->count : 0;
}

/* `i` is below msstd_json_len. */
uint32_t msstd_json_item(const void *d, uint32_t id, int64_t i) {
  size_t count = 0;
  const uint32_t *items = items_of(d, id, &count);
  if (i >= 0 && (uint64_t)i < count) {
    return items[i];
  }
  const JsonMember *members = members_of(d, id, &count);
  return i >= 0 && (uint64_t)i < count ? members[i].value : 0;
}

void msstd_json_key(const void *d, uint32_t id, int64_t i, MsString *out) {
  size_t count = 0;
  const JsonMember *members = members_of(d, id, &count);
  if (i < 0 || (uint64_t)i >= count) {
    owned_text(ms_span_of(NULL, 0), out);
    return;
  }
  owned_text(span_of(d, members[i].key_offset, members[i].key_length), out);
}

static bool key_is(const JsonDoc *doc, const JsonMember *member, MsSpan name) {
  return ms_span_equal(span_of(doc, member->key_offset, member->key_length), name);
}

int64_t msstd_json_find(const void *d, uint32_t id, const MsString *key) {
  size_t count = 0;
  const JsonMember *members = members_of(d, id, &count);
  const MsSpan name = ms_string_span(key);
  for (size_t i = 0; i < count; i++) {
    if (key_is(d, &members[i], name)) {
      return (int64_t)i;
    }
  }
  return -1;
}

/* The index of `name` in the list of strings, or -1. */
static int64_t name_index(const MsList *names, MsSpan name) {
  for (size_t i = 0; i < names->len; i++) {
    MsString entry;
    memcpy(&entry, names->ptr + i * sizeof entry, sizeof entry);
    if (ms_span_equal(ms_string_span(&entry), name)) {
      return (int64_t)i;
    }
  }
  return -1;
}

uint8_t msstd_json_has_unknown(const void *d, uint32_t id, const MsList *names) {
  size_t count = 0;
  const JsonMember *members = members_of(d, id, &count);
  for (size_t i = 0; i < count; i++) {
    if (name_index(names, span_of(d, members[i].key_offset, members[i].key_length)) < 0) {
      return 1;
    }
  }
  return 0;
}

/* The index of the variant name in `names` (-1 when unknown); `payload` is the payload node (-1 for a bare
 * name) and is written only for a string or a single-key object. */
int64_t msstd_json_variant(const void *d, uint32_t id, const MsList *names, int64_t *payload) {
  const JsonNode *node = node_of(d, id);
  if (node != NULL && node->kind == KIND_STRING) {
    *payload = -1;
    return name_index(names, text_of(d, id));
  }
  size_t count = 0;
  const JsonMember *members = members_of(d, id, &count);
  if (count != 1) {
    return -1;
  }
  *payload = (int64_t)members[0].value;
  return name_index(names, span_of(d, members[0].key_offset, members[0].key_length));
}

/* ---- why a typed decode failed ---- */

void msstd_json_mismatch(const void *d, uint32_t id, int64_t code, const MsString *text) {
  Mismatch *record = ((const JsonDoc *)d)->mismatch;
  if (record->present) {
    ms_string_release(&record->text);
  }
  *record = (Mismatch){.present = true, .node = id, .code = (uint8_t)code};
  *(&record->text) = ms_string_clone(text);
}

/* One level of the walk to a node: a container and the child being visited. */
typedef struct PathFrame {
  uint32_t node;
  size_t next;
} PathFrame;

/* Appends the path from `root` to `target` to `path` as `[i]` and `.key` steps. False when `target` is not
 * below `root`. The walk is iterative, so a document at the depth ceiling costs heap and not stack. */
static bool path_to(const JsonDoc *doc, uint32_t root, uint32_t target, JsonBuffer *path) {
  if (root == target) {
    return true;
  }
  PathFrame *stack = NULL;
  size_t depth = 0;
  size_t capacity = 0;
  bool found = false;
  if (ms_array_reserve((void **)&stack, &capacity, 1, sizeof *stack)) {
    stack[depth++] = (PathFrame){.node = root};
  }
  while (depth > 0 && !found) {
    PathFrame *top = &stack[depth - 1];
    size_t count = 0;
    const uint32_t *items = items_of(doc, top->node, &count);
    const JsonMember *members = items == NULL ? members_of(doc, top->node, &count) : NULL;
    if (top->next >= count) {
      depth--;
      continue;
    }
    const uint32_t child = items != NULL ? items[top->next] : members[top->next].value;
    top->next++;
    if (!ms_array_reserve((void **)&stack, &capacity, depth + 1, sizeof *stack)) {
      break;
    }
    stack[depth++] = (PathFrame){.node = child};
    found = child == target;
  }
  for (size_t level = 0; found && level + 1 < depth; level++) {
    const PathFrame *frame = &stack[level];
    size_t count = 0;
    const bool is_array = items_of(doc, frame->node, &count) != NULL;
    char step[32];
    if (is_array) {
      const int length = snprintf(step, sizeof step, "[%zu]", frame->next - 1);
      found = json_buffer_append(path, ms_span_of((const uint8_t *)step, (size_t)length));
    } else {
      const JsonMember *member = &members_of(doc, frame->node, &count)[frame->next - 1];
      found = json_buffer_push(path, '.') &&
              json_buffer_append(path, span_of(doc, member->key_offset, member->key_length));
    }
  }
  ms_free(stack);
  return found;
}

static const char *kind_name(const JsonNode *node) {
  if (node == NULL) {
    return "value";
  }
  switch (node->kind) {
  case KIND_NULL:
    return "null";
  case KIND_BOOL:
    return "boolean";
  case KIND_NUMBER:
    return "number";
  case KIND_STRING:
    return "string";
  case KIND_ARRAY:
    return "array";
  default:
    return "object";
  }
}

MS_NODISCARD static bool put(JsonBuffer *out, const char *text) {
  return json_buffer_append(out, ms_span_of_text(text));
}

/* The reason a node was rejected. Codes: 0 value does not fit type `detail`; 1 expected kind `detail`; 2
 * missing field `detail`; 3 unknown field; 4 unknown variant. */
MS_NODISCARD static bool append_reason(JsonBuffer *out, const JsonNode *node, uint8_t code, MsSpan detail) {
  const char *found = kind_name(node);
  switch (code) {
  case 0:
    return put(out, found) && put(out, " does not fit ") && json_buffer_append(out, detail);
  case 1:
    return put(out, "expected ") && json_buffer_append(out, detail) && put(out, ", found ") &&
           put(out, found);
  case 2:
    return put(out, "missing field \"") && json_buffer_append(out, detail) && put(out, "\"");
  case 3:
    return put(out, "unknown field");
  default:
    return put(out, found) && put(out, " is not a known variant");
  }
}

/* `JSON: invalid data: at $.items[0].count: expected Int, found string` for the recorded rejection under
 * `root`, else `JSON: invalid data`. */
void msstd_json_mismatch_text(const void *d, uint32_t root, MsString *out) {
  static const char plain[] = "JSON: invalid data";
  const JsonDoc *doc = d;
  const Mismatch *record = doc->mismatch;
  JsonBuffer text = {.limit = MS_STRING_MAX_LENGTH};
  JsonBuffer path = {.limit = MS_STRING_MAX_LENGTH};
  const bool located = record->present && path_to(doc, root, record->node, &path);
  const MsSpan detail = ms_string_span(&record->text);
  const bool full = located && put(&text, plain) && put(&text, ": at $") &&
                    json_buffer_append(&text, ms_span_of(path.bytes.ptr, path.bytes.len)) &&
                    put(&text, ": ") &&
                    append_reason(&text, node_of(doc, record->node), record->code, detail);
  *(out) = ms_string_from_span(ms_span_of((const uint8_t *)plain, sizeof plain - 1));
  if (full) {
    ms_string_release(out);
    *(out) = ms_string_from_span(ms_span_of(text.bytes.ptr, text.bytes.len));
  }
  json_buffer_free(&text);
  json_buffer_free(&path);
}

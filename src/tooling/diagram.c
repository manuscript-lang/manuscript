/* Owns the call graph renderers of inspect.h: port of `diagram_ascii` and `Inspection::mermaid`. */
#include "base/sha256.h"
#include "base/sort.h"
#include "tooling/inspect.h"

typedef struct Edge {
  MsSpan owner, label, kind;
  size_t count;
} Edge;

MS_LIST_DEFINE(EdgeList, edge_list, Edge)

static int64_t compare_edge(uint8_t *env, const uint8_t *left, const uint8_t *right) {
  (void)env;
  const Edge *a = (const Edge *)(const void *)left;
  const Edge *b = (const Edge *)(const void *)right;
  int64_t order = ms_span_compare(a->owner, b->owner);
  order = order != 0 ? order : ms_span_compare(a->label, b->label);
  return order != 0 ? order : ms_span_compare(a->kind, b->kind);
}

/* The entity with `id`, or NULL; entities are sorted by id. */
static const MsEntity *find_entity(const MsInspection *inspection, MsSpan id) {
  size_t low = 0;
  size_t high = inspection->entities.len;
  while (low < high) {
    const size_t mid = low + (high - low) / 2;
    const int64_t order = ms_span_compare(inspection->entities.ptr[mid].id, id);
    if (order == 0) {
      return &inspection->entities.ptr[mid];
    }
    if (order < 0) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return NULL;
}

static MsSpan label_of(const MsInspection *inspection, MsArena *arena, MsSpan id) {
  const MsEntity *entity = find_entity(inspection, id);
  return entity == NULL ? ms_readable_id(arena, id) : ms_message_format(arena, "%S::%S", entity->file, entity->name);
}

void ms_diagram_ascii(const MsInspection *inspection, MsArena *arena, MsStrBuild *out) {
  EdgeList edges = {0};
  for (size_t i = 0; i < inspection->calls.len; i++) {
    const MsCallSite *call = &inspection->calls.ptr[i];
    edge_list_push(&edges, (Edge){.owner = call->owner, .label = label_of(inspection, arena, call->target),
                                  .kind = call->kind, .count = 1});
  }
  ms_sort((uint8_t *)edges.ptr, edges.len, sizeof(Edge), compare_edge, NULL);
  ms_strbuild_append_text(out, "CALL GRAPH\n");
  size_t next = 0;
  for (size_t i = 0; i < inspection->entities.len; i++) {
    const MsEntity *entity = &inspection->entities.ptr[i];
    ms_strbuild_append(out, label_of(inspection, arena, entity->id));
    ms_strbuild_append_text(out, " [");
    ms_strbuild_append(out, entity->kind);
    ms_strbuild_append_text(out, "]\n");
    while (next < edges.len && ms_span_compare(edges.ptr[next].owner, entity->id) < 0) {
      next++; /* an owner that is not an entity prints nothing */
    }
    while (next < edges.len && ms_span_compare(edges.ptr[next].owner, entity->id) == 0) {
      size_t count = 1;
      while (next + count < edges.len && compare_edge(NULL, (const uint8_t *)&edges.ptr[next],
                                                      (const uint8_t *)&edges.ptr[next + count]) == 0) {
        count++;
      }
      ms_strbuild_append_text(out, "  -> ");
      ms_strbuild_append(out, edges.ptr[next].label);
      ms_strbuild_append_text(out, " (");
      ms_strbuild_append(out, edges.ptr[next].kind);
      ms_strbuild_append_text(out, ")");
      if (count > 1) {
        ms_strbuild_printf(out, " x%zu", count);
      }
      ms_strbuild_append_text(out, "\n");
      next += count;
    }
  }
  edge_list_free(&edges);
}

/* ---- mermaid ---- */

typedef struct Seen {
  MsSpanList ids;
  MsSpanList keys;
} Seen;

static void append_label(MsStrBuild *out, MsSpan label) {
  for (size_t i = 0; i < label.len; i++) {
    const uint8_t b = label.ptr[i];
    const char *text = b == '&' ? "&amp;" : b == '"' ? "&quot;" : b == '<' ? "&lt;" : b == '>' ? "&gt;" : b == '\n' ? " " : NULL;
    if (text != NULL) {
      ms_strbuild_append_text(out, text);
    } else {
      ms_strbuild_append_byte(out, b);
    }
  }
}

/* The node key of `id`, declaring the node on first use. */
static MsSpan node(Seen *seen, MsArena *arena, MsStrBuild *out, MsSpan id, MsSpan label) {
  for (size_t i = 0; i < seen->ids.len; i++) {
    if (ms_span_equal(seen->ids.ptr[i], id)) {
      return seen->keys.ptr[i];
    }
  }
  uint8_t hex[MS_SHA256_HEX_LEN];
  ms_sha256_hex(id, hex);
  const MsSpan key = ms_message_format(arena, "n%S", ms_span_of(hex, 16));
  ms_span_list_push(&seen->ids, id);
  ms_span_list_push(&seen->keys, key);
  ms_strbuild_append_text(out, "    ");
  ms_strbuild_append(out, key);
  ms_strbuild_append_text(out, "[\"");
  append_label(out, label);
  ms_strbuild_append_text(out, "\"]\n");
  return key;
}

void ms_diagram_mermaid(const MsInspection *inspection, MsArena *arena, MsStrBuild *out) {
  Seen seen = {0};
  ms_strbuild_append_text(out, "flowchart TD\n");
  for (size_t i = 0; i < inspection->entities.len; i++) {
    const MsEntity *e = &inspection->entities.ptr[i];
    (void)node(&seen, arena, out, e->id, ms_message_format(arena, "%S::%S", e->file, e->name));
  }
  for (size_t i = 0; i < inspection->calls.len; i++) {
    const MsCallSite *c = &inspection->calls.ptr[i];
    const MsSpan owner = node(&seen, arena, out, c->owner, c->owner);
    const MsSpan target = node(&seen, arena, out, c->target, ms_readable_id(arena, c->target));
    ms_strbuild_append_text(out, "    ");
    ms_strbuild_append(out, owner);
    ms_strbuild_append_text(out, " -->|");
    ms_strbuild_append(out, c->kind);
    ms_strbuild_append_text(out, "| ");
    ms_strbuild_append(out, target);
    ms_strbuild_append_text(out, "\n");
  }
  ms_span_list_free(&seen.ids);
  ms_span_list_free(&seen.keys);
}

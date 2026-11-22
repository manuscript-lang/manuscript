/* Owns the class, ownership and mermaid renderings of views.h: the custom views of `ms inspect`. */
#include "tooling/views.h"
#include "tooling/views_private.h"

#include "compiler/syntax/diag_json.h"

static void indent(MsStrBuild *out, size_t depth) {
  for (size_t i = 0; i < depth; i++) {
    ms_strbuild_append_text(out, "  ");
  }
}

void ms_view_json(const MsViewNode *node, size_t depth, MsStrBuild *out) {
  ms_strbuild_append_text(out, "{\n");
  const struct {
    const char *key;
    MsSpan value;
  } fields[] = {{"label", node->label}, {"kind", node->kind}, {"reference", node->reference}, {"file", node->file}};
  for (size_t i = 0; i < 4; i++) {
    indent(out, depth + 1);
    ms_strbuild_printf(out, "\"%s\": ", fields[i].key);
    ms_json_string(out, fields[i].value);
    ms_strbuild_append_text(out, ",\n");
  }
  indent(out, depth + 1);
  ms_strbuild_printf(out, "\"line\": %zu,\n", node->line);
  indent(out, depth + 1);
  ms_strbuild_printf(out, "\"omitted\": %zu,\n", node->omitted);
  indent(out, depth + 1);
  ms_strbuild_append_text(out, "\"children\": ");
  if (node->kids.len == 0) {
    ms_strbuild_append_text(out, "[]\n");
  } else {
    ms_strbuild_append_text(out, "[\n");
    for (size_t i = 0; i < node->kids.len; i++) {
      indent(out, depth + 2);
      ms_view_json(node->kids.ptr[i], depth + 2, out);
      ms_strbuild_append_text(out, i + 1 < node->kids.len ? ",\n" : "\n");
    }
    indent(out, depth + 1);
    ms_strbuild_append_text(out, "]\n");
  }
  indent(out, depth);
  ms_strbuild_append_text(out, "}");
}

static MsSpan mermaid_text(MsArena *arena, MsSpan value) {
  uint8_t *copy = MS_ARENA_NEW_ARRAY(arena, uint8_t, value.len + 1);
  for (size_t i = 0; i < value.len; i++) {
    copy[i] = (value.ptr[i] == '[' || value.ptr[i] == ']') ? (uint8_t)'~' : value.ptr[i];
  }
  return ms_span_of(copy, value.len);
}

/* The data types a types view draws: all of them, or the entity and what it holds to `depth` levels. False when the
 * entity is not a data type. */
static bool class_set(MsArena *arena, const MsFactModel *model, MsSpan entity, int64_t depth, Roots *chosen) {
  if (entity.len == 0) {
    for (size_t i = 0; i < model->entities.len; i++) {
      if (ms_views_is_data_type(&model->entities.ptr[i])) {
        ms_views_roots_push(arena, chosen, &model->entities.ptr[i]);
      }
    }
    return true;
  }
  MsSpan ignored = {0};
  const MsFact *start = ms_find_entity(arena, model, entity, &ignored);
  if (start == NULL || !ms_views_is_data_type(start)) {
    return false;
  }
  ms_views_roots_push(arena, chosen, start);
  Roots frontier = {0};
  ms_views_roots_push(arena, &frontier, start);
  for (int64_t level = 0; level < depth; level++) {
    Roots next = {0};
    for (size_t i = 0; i < frontier.len; i++) {
      const MsFact *f = frontier.ptr[i];
      for (size_t s = 0; s < f->slots.len; s++) {
        for (size_t r = 0; r < f->slots.ptr[s].refs.len; r++) {
          const MsFact *t = ms_views_fact_of(model, f->slots.ptr[s].refs.ptr[r]);
          bool seen = false;
          for (size_t c = 0; t != NULL && c < chosen->len; c++) {
            seen = seen || ms_span_equal(chosen->ptr[c]->key, t->key);
          }
          if (t != NULL && !seen) {
            ms_views_roots_push(arena, chosen, t);
            ms_views_roots_push(arena, &next, t);
          }
        }
      }
    }
    frontier = next;
  }
  return true;
}

static bool in_chosen(const Roots *chosen, const MsFact *t) {
  for (size_t i = 0; i < chosen->len && i < MS_NODE_CAP; i++) {
    if (ms_span_equal(chosen->ptr[i]->key, t->key)) {
      return true;
    }
  }
  return false;
}

static MsSpan member_text(MsArena *arena, const MsFact *f, const MsSlot *s) {
  return is(f->kind, "type") ? ms_message_format(arena, "%S: %S", s->name, s->ty) : ms_message_format(arena, "%S%S", s->name, s->ty);
}

/* Display width in characters of UTF-8 text: the Rust port pads by byte length, so bytes it is. */
static void pad(MsStrBuild *out, MsSpan value, size_t width) {
  ms_strbuild_append(out, value);
  for (size_t i = value.len; i < width; i++) {
    ms_strbuild_append_byte(out, ' ');
  }
}

static void rule(MsStrBuild *out, size_t width) {
  ms_strbuild_append_text(out, "+-");
  for (size_t i = 0; i < width; i++) {
    ms_strbuild_append_byte(out, '-');
  }
  ms_strbuild_append_text(out, "-+\n");
}

static void ascii_classes(MsArena *arena, const MsFactModel *model, const Roots *chosen, MsStrBuild *out) {
  (void)model;
  for (size_t c = 0; c < chosen->len && c < MS_NODE_CAP; c++) {
    const MsFact *f = chosen->ptr[c];
    const MsSpan title = is(f->kind, "type") ? f->name : ms_message_format(arena, "<<%S>> %S", f->kind, f->name);
    size_t width = title.len;
    for (size_t i = 0; i < f->slots.len; i++) {
      const size_t n = member_text(arena, f, &f->slots.ptr[i]).len;
      width = n > width ? n : width;
    }
    rule(out, width);
    ms_strbuild_append_text(out, "| ");
    pad(out, title, width);
    ms_strbuild_append_text(out, " |\n");
    if (f->slots.len > 0) {
      rule(out, width);
      for (size_t i = 0; i < f->slots.len; i++) {
        ms_strbuild_append_text(out, "| ");
        pad(out, member_text(arena, f, &f->slots.ptr[i]), width);
        ms_strbuild_append_text(out, " |\n");
      }
    }
    rule(out, width);
    for (size_t i = 0; i < f->slots.len; i++) {
      const MsSlot *s = &f->slots.ptr[i];
      for (size_t r = 0; r < s->refs.len; r++) {
        const MsFact *t = ms_views_fact_of(model, s->refs.ptr[r]);
        if (t != NULL && in_chosen(chosen, t)) {
          ms_strbuild_append(out, ms_message_format(arena, "  <>-- %S --> %S\n", s->name, t->name));
        }
      }
    }
    ms_strbuild_append_text(out, "\n");
  }
  if (chosen->len == 0) {
    ms_strbuild_append_text(out, "none\n");
  }
}

static void signature_lines(MsArena *arena, const MsFactModel *model, const MsFact *f, int64_t level, int64_t depth,
                            MsSpans *path, size_t *lines, MsStrBuild *out) {
  MsStrBuild params = ms_strbuild_new();
  bool first = true;
  if (f->receiver.len > 0) {
    ms_strbuild_append(&params, is(f->receiver, "borrow") ? text("self") : ms_message_format(arena, "%S self", f->receiver));
    first = false;
  }
  for (size_t i = 0; i < f->slots.len; i++) {
    const MsSlot *s = &f->slots.ptr[i];
    ms_strbuild_append_text(&params, first ? "" : ", ");
    ms_strbuild_append_text(&params, s->var ? "var " : "");
    ms_strbuild_append(&params, ms_message_format(arena, "%S: %S", s->name, s->ty));
    first = false;
  }
  for (int64_t i = 0; i < level; i++) {
    ms_strbuild_append_text(out, "  ");
  }
  ms_strbuild_append(out, ms_message_format(arena, "%S(%S) %S", f->name, ms_strbuild_span(&params), f->has_result ? f->result.ty : (MsSpan){0}));
  ms_strbuild_free(&params);
  if (f->scopes > 0) {
    ms_strbuild_append(out, ms_message_format(arena, "  [closes %z]", f->scopes));
  }
  ms_strbuild_append_text(out, "\n");
  (*lines)++;
  if (level >= depth) {
    return;
  }
  ms_spans_push(arena, path, f->key);
  for (size_t i = 0; i < f->calls.len; i++) {
    const MsFact *callee = ms_views_fact_of(model, f->calls.ptr[i]);
    if (callee == NULL || contains(path, f->calls.ptr[i]) || *lines >= MS_NODE_CAP) {
      continue;
    }
    signature_lines(arena, model, callee, level + 1, depth, path, lines, out);
  }
  path->len--;
}

/* The roots of the ownership renderings: the entity when it resolves, else every candidate. */
static void ownership_roots(MsArena *arena, const MsFactModel *model, MsSpan entity, Roots *roots) {
  MsSpan ignored = {0};
  const MsFact *f = entity.len > 0 ? ms_find_entity(arena, model, entity, &ignored) : NULL;
  if (f != NULL) {
    ms_views_roots_push(arena, roots, f);
    return;
  }
  for (size_t i = 0; i < model->entities.len; i++) {
    if (ms_views_ownership_candidate(&model->entities.ptr[i])) {
      ms_views_roots_push(arena, roots, &model->entities.ptr[i]);
    }
  }
}

static void ascii_ownership(MsArena *arena, const MsFactModel *model, MsSpan entity, int64_t depth, MsStrBuild *out) {
  Roots roots = {0};
  ownership_roots(arena, model, entity, &roots);
  size_t lines = 0;
  for (size_t i = 0; i < roots.len; i++) {
    if (lines >= MS_NODE_CAP) {
      ms_strbuild_append(out, ms_message_format(arena, "+more (output capped at %z lines)\n", (size_t)MS_NODE_CAP));
      break;
    }
    MsSpans path = {0};
    signature_lines(arena, model, roots.ptr[i], 0, depth, &path, &lines, out);
  }
  if (lines == 0) {
    ms_strbuild_append_text(out, "none\n");
  }
}

bool ms_view_ascii_custom(MsArena *arena, const MsFactModel *model, MsSpan view, MsSpan entity, int64_t depth, MsStrBuild *out) {
  if (is(view, "overview")) {
    ms_views_overview_ascii(arena, model, out);
    return true;
  }
  if (is(view, "types")) {
    Roots chosen = {0};
    if (!class_set(arena, model, entity, depth <= 0 ? 3 : depth, &chosen)) {
      return false;
    }
    ascii_classes(arena, model, &chosen, out);
    return true;
  }
  if (is(view, "ownership")) {
    ascii_ownership(arena, model, entity, depth <= 0 ? 1 : depth, out);
    return true;
  }
  return false;
}

/* ---- mermaid ---- */

static MsSpan class_id(MsArena *arena, const MsFact *f) {
  uint8_t *copy = MS_ARENA_NEW_ARRAY(arena, uint8_t, f->name.len + 1);
  for (size_t i = 0; i < f->name.len; i++) {
    const uint8_t b = f->name.ptr[i];
    const bool keep = (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') || (b >= '0' && b <= '9') || b == '_' || b >= 0x80;
    copy[i] = keep ? b : '_';
  }
  return ms_span_of(copy, f->name.len);
}

static bool class_diagram(MsArena *arena, const MsFactModel *model, MsSpan entity, int64_t depth, MsStrBuild *out) {
  Roots all = {0};
  if (!class_set(arena, model, entity, depth, &all)) {
    return false;
  }
  const size_t n = all.len < MS_NODE_CAP ? all.len : MS_NODE_CAP;
  MsSpans reserved = {0};
  MsSpans assigned = {0};
  MsSpan *ids = MS_ARENA_NEW_ARRAY(arena, MsSpan, n + 1);
  for (size_t i = 0; i < n; i++) {
    ms_spans_push(arena, &reserved, class_id(arena, all.ptr[i]));
  }
  size_t next_id = 0;
  for (size_t i = 0; i < n; i++) {
    const MsSpan name = class_id(arena, all.ptr[i]);
    if (!contains(&assigned, name)) {
      ms_spans_push(arena, &assigned, name);
      ids[i] = name;
      continue;
    }
    for (;;) {
      const MsSpan id = ms_message_format(arena, "__ms_type_%z", next_id++);
      if (!contains(&reserved, id)) {
        ms_spans_push(arena, &reserved, id);
        ids[i] = id;
        break;
      }
    }
  }
  ms_strbuild_append_text(out, "classDiagram\n");
  for (size_t i = 0; i < n; i++) {
    const MsFact *f = all.ptr[i];
    const MsSpan name = class_id(arena, f);
    if (ms_span_equal(ids[i], name)) {
      ms_strbuild_append(out, ms_message_format(arena, "    class %S {\n", ids[i]));
    } else {
      ms_strbuild_append(out, ms_message_format(arena, "    class %S[\"%S\"] {\n", ids[i], name));
    }
    if (!is(f->kind, "type")) {
      ms_strbuild_append(out, ms_message_format(arena, "        <<%S>>\n", f->kind));
    }
    for (size_t s = 0; s < f->slots.len; s++) {
      const MsSlot *slot = &f->slots.ptr[s];
      if (is(f->kind, "type")) {
        ms_strbuild_append(out, ms_message_format(arena, "        +%S %S\n", mermaid_text(arena, slot->ty), slot->name));
      } else {
        ms_strbuild_append(out, ms_message_format(arena, "        %S%S\n", slot->name, mermaid_text(arena, slot->ty)));
      }
    }
    ms_strbuild_append_text(out, "    }\n");
  }
  for (size_t i = 0; i < n; i++) {
    const MsFact *f = all.ptr[i];
    for (size_t s = 0; s < f->slots.len; s++) {
      for (size_t r = 0; r < f->slots.ptr[s].refs.len; r++) {
        for (size_t t = 0; t < n; t++) {
          if (ms_span_equal(all.ptr[t]->key, f->slots.ptr[s].refs.ptr[r])) {
            ms_strbuild_append(out, ms_message_format(arena, "    %S *-- %S : %S\n", ids[i], ids[t], f->slots.ptr[s].name));
          }
        }
      }
    }
  }
  return true;
}

static MsSpan flow_type_node(MsArena *arena, MsStrBuild *out, MsSpans *declared, MsSpan ty) {
  const MsSpan id = ms_message_format(arena, "t_%S", ms_views_sanitize(arena, ty, false));
  if (!contains(declared, id)) {
    MsStrBuild label = ms_strbuild_new();
    for (size_t i = 0; i < ty.len; i++) {
      ms_strbuild_append_byte(&label, ty.ptr[i] == '"' ? '\'' : ty.ptr[i]);
    }
    ms_strbuild_append(out, ms_message_format(arena, "    %S([\"%S\"])\n", id, ms_strbuild_span(&label)));
    ms_strbuild_free(&label);
    ms_spans_push(arena, declared, id);
  }
  return id;
}

static const char *link_style(const char *mode) {
  if (is(text(mode), "var")) {
    return "stroke:#d33,stroke-width:3px";
  }
  if (is(text(mode), "copy")) {
    return "stroke:#999,stroke-dasharray:4";
  }
  if (is(text(mode), "move")) {
    return "stroke:#2a2,stroke-width:3px";
  }
  return "stroke:#37b";
}

static void ownership_flow(MsArena *arena, const MsFactModel *model, MsSpan entity, int64_t depth, MsStrBuild *out) {
  Roots roots = {0};
  ownership_roots(arena, model, entity, &roots);
  ms_strbuild_append_text(out, "flowchart LR\n");
  MsSpans styles = {0};
  MsSpans declared = {0};
  MsSpans done = {0};
  Roots frontier = {0};
  for (size_t i = 0; i < roots.len && i < MS_NODE_CAP; i++) {
    ms_views_roots_push(arena, &frontier, roots.ptr[i]);
  }
  for (int64_t level = 0; level <= depth; level++) {
    Roots next = {0};
    for (size_t i = 0; i < frontier.len; i++) {
      const MsFact *f = frontier.ptr[i];
      if (contains(&done, f->key)) {
        continue;
      }
      ms_spans_push(arena, &done, f->key);
      const MsSpan fid = ms_message_format(arena, "f%z", done.len);
      MsStrBuild name = ms_strbuild_new();
      for (size_t k = 0; k < f->name.len; k++) {
        ms_strbuild_append_byte(&name, f->name.ptr[k] == '"' ? '\'' : f->name.ptr[k]);
      }
      const MsSpan closes = f->scopes > 0 ? ms_message_format(arena, "<br/>closes %z", f->scopes) : (MsSpan){0};
      ms_strbuild_append(out, ms_message_format(arena, "    %S[\"%S()%S\"]:::fn\n", fid, ms_strbuild_span(&name), closes));
      ms_strbuild_free(&name);
      if (f->receiver.len > 0) {
        const MsSpan tid = flow_type_node(arena, out, &declared, text("self"));
        ms_strbuild_append(out, ms_message_format(arena, "    %S -->|\"self %S\"| %S\n", tid, f->receiver, fid));
        ms_spans_push(arena, &styles, is(f->receiver, "var") ? text("stroke:#d33,stroke-width:3px")
                                     : is(f->receiver, "move") ? text("stroke:#2a2,stroke-width:3px")
                                                              : text("stroke:#37b"));
      }
      for (size_t s = 0; s < f->slots.len; s++) {
        const MsSlot *slot = &f->slots.ptr[s];
        const char *mode = ms_passing_mode(slot);
        const MsSpan tid = flow_type_node(arena, out, &declared, slot->ty);
        MsSpan label = mode[0] == '\0' ? slot->name : ms_message_format(arena, "%S %s", slot->name, mode);
        ms_strbuild_append(out, ms_message_format(arena, "    %S -->|\"%S\"| %S\n", tid, label, fid));
        ms_spans_push(arena, &styles, text(link_style(mode)));
      }
      if (f->has_result) {
        const MsSpan tid = flow_type_node(arena, out, &declared, f->result.ty);
        ms_strbuild_append(out, ms_message_format(arena, "    %S -->|\"%s\"| %S\n", fid, ms_result_label(f->result_ownership), tid));
        ms_spans_push(arena, &styles, f->result_ownership == MS_RESULT_BORROW ? text("stroke:#37b") : text("stroke:#2a2,stroke-width:3px"));
      }
      if (level < depth) {
        for (size_t c = 0; c < f->calls.len; c++) {
          const MsFact *callee = ms_views_fact_of(model, f->calls.ptr[c]);
          if (callee != NULL) {
            ms_views_roots_push(arena, &next, callee);
          }
        }
      }
    }
    frontier = next;
  }
  ms_strbuild_append_text(out, "    classDef fn fill:#fff3cd,stroke:#b8860b\n");
  for (size_t i = 0; i < styles.len; i++) {
    ms_strbuild_append(out, ms_message_format(arena, "    linkStyle %z %S\n", i, styles.ptr[i]));
  }
}

bool ms_view_mermaid_custom(MsArena *arena, const MsFactModel *model, MsSpan view, MsSpan entity, int64_t depth, MsStrBuild *out) {
  if (is(view, "overview")) {
    ms_views_overview_mermaid(arena, model, out);
    return true;
  }
  if (is(view, "types")) {
    return class_diagram(arena, model, entity, depth <= 0 ? 3 : depth, out);
  }
  if (is(view, "ownership")) {
    ownership_flow(arena, model, entity, depth <= 0 ? 1 : depth, out);
    return true;
  }
  return false;
}

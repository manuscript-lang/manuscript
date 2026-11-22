/* Owns html.h. The data is compact: files are interned, entities are arrays that refer to each other by index, and flows
 * are arrays of `[kind, label, callee, children]`. It is escaped for a script element, so no program text can close it. */
#include "tooling/html.h"

#include "base/message.h"
#include "base/sort.h"
#include "compiler/syntax/diag_json.h"
#include "tooling/views.h"

extern const uint8_t ms_page_html[];
extern const size_t ms_page_html_size;

enum { LABEL_CAP = 100 };

typedef struct Index {
  const MsFactModel *model;
  MsSpans files;
} Index;

static bool has_file(const Index *ix, MsSpan file, size_t *at) {
  for (size_t i = 0; i < ix->files.len; i++) {
    if (ms_span_equal(ix->files.ptr[i], file)) {
      *at = i;
      return true;
    }
  }
  return false;
}

static size_t file_index(const Index *ix, MsSpan file) {
  size_t at = 0;
  return has_file(ix, file, &at) ? at : 0;
}

/* The index of the entity with `key`, or -1. The entities are sorted by key. */
static long entity_index(const Index *ix, MsSpan key) {
  size_t low = 0;
  size_t high = ix->model->entities.len;
  while (low < high) {
    const size_t mid = low + (high - low) / 2;
    const int order = ms_span_compare(ix->model->entities.ptr[mid].key, key);
    if (order == 0) {
      return (long)mid;
    }
    if (order < 0) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return -1;
}

static void number(MsStrBuild *out, size_t value) {
  ms_strbuild_append_u64(out, value);
}

static void strings(MsStrBuild *out, const MsSpans *list) {
  ms_strbuild_append_byte(out, '[');
  for (size_t i = 0; i < list->len; i++) {
    ms_strbuild_append_text(out, i > 0 ? "," : "");
    ms_json_string(out, list->ptr[i]);
  }
  ms_strbuild_append_byte(out, ']');
}

static void indices(const Index *ix, MsStrBuild *out, const MsSpans *keys) {
  ms_strbuild_append_byte(out, '[');
  bool first = true;
  for (size_t i = 0; i < keys->len; i++) {
    const long at = entity_index(ix, keys->ptr[i]);
    if (at < 0) {
      continue;
    }
    ms_strbuild_append_text(out, first ? "" : ",");
    number(out, (size_t)at);
    first = false;
  }
  ms_strbuild_append_byte(out, ']');
}

static void slot(const Index *ix, MsStrBuild *out, const MsSlot *s, bool parameter) {
  ms_strbuild_append_byte(out, '[');
  ms_json_string(out, s->name);
  ms_strbuild_append_byte(out, ',');
  ms_json_string(out, s->ty);
  ms_strbuild_append_text(out, s->var ? ",1," : ",0,");
  indices(ix, out, &s->refs);
  if (parameter) {
    ms_strbuild_append_byte(out, ',');
    ms_json_string(out, ms_span_of_text(ms_passing_mode(s)));
  }
  ms_strbuild_append_byte(out, ']');
}

/* The first LABEL_CAP characters of `label`. */
static MsSpan capped(MsSpan label) {
  size_t chars = 0;
  for (size_t i = 0; i < label.len; i++) {
    if ((label.ptr[i] & 0xC0) != 0x80) {
      if (chars == LABEL_CAP) {
        return ms_span_of(label.ptr, i);
      }
      chars++;
    }
  }
  return label;
}

static void flow(const Index *ix, MsStrBuild *out, const MsViewNodes *nodes) {
  ms_strbuild_append_byte(out, '[');
  for (size_t i = 0; i < nodes->len; i++) {
    const MsViewNode *n = nodes->ptr[i];
    ms_strbuild_append_text(out, i > 0 ? ",[" : "[");
    ms_json_string(out, n->kind);
    ms_strbuild_append_byte(out, ',');
    ms_json_string(out, capped(n->label));
    ms_strbuild_append_byte(out, ',');
    ms_strbuild_append_i64(out, entity_index(ix, n->reference));
    ms_strbuild_append_byte(out, ',');
    flow(ix, out, &n->kids);
    ms_strbuild_append_byte(out, ']');
  }
  ms_strbuild_append_byte(out, ']');
}

static void entity(const Index *ix, MsStrBuild *out, const MsFact *f) {
  const bool callable = ms_span_is_text(f->kind, "fn") || ms_span_is_text(f->kind, "method");
  ms_strbuild_append_byte(out, '[');
  number(out, file_index(ix, f->file));
  ms_strbuild_append_byte(out, ',');
  ms_json_string(out, f->kind);
  ms_strbuild_append_byte(out, ',');
  ms_json_string(out, f->name);
  ms_strbuild_append_byte(out, ',');
  number(out, f->line);
  ms_strbuild_append_text(out, f->exported ? ",1," : ",0,");
  strings(out, &f->effects);
  ms_strbuild_append_byte(out, ',');
  ms_json_string(out, f->error);
  ms_strbuild_append_byte(out, ',');
  number(out, f->scopes);
  ms_strbuild_append_byte(out, ',');
  indices(ix, out, &f->calls);
  ms_strbuild_append_byte(out, ',');
  strings(out, &f->external);
  ms_strbuild_append_text(out, ",[");
  for (size_t i = 0; i < f->slots.len; i++) {
    ms_strbuild_append_text(out, i > 0 ? "," : "");
    slot(ix, out, &f->slots.ptr[i], callable);
  }
  ms_strbuild_append_text(out, "],");
  if (f->has_result) {
    ms_strbuild_append_byte(out, '[');
    ms_json_string(out, f->result.ty);
    ms_strbuild_append_byte(out, ',');
    indices(ix, out, &f->result.refs);
    ms_strbuild_append_byte(out, ',');
    ms_json_string(out, ms_span_of_text(ms_result_label(f->result_ownership)));
    ms_strbuild_append_byte(out, ']');
  } else {
    ms_strbuild_append_byte(out, '0');
  }
  ms_strbuild_append_byte(out, ',');
  flow(ix, out, &f->flow);
  ms_strbuild_append_byte(out, ',');
  number(out, f->first);
  ms_strbuild_append_byte(out, ',');
  number(out, f->last);
  ms_strbuild_append_byte(out, ',');
  ms_json_string(out, f->label.len == 0 ? f->name : f->label);
  ms_strbuild_append_byte(out, ']');
}

static MsSpan source_of(const MsFactModel *model, MsSpan file) {
  for (size_t i = 0; i < model->imports.len; i++) {
    if (ms_span_equal(model->imports.ptr[i].file, file)) {
      return model->imports.ptr[i].source;
    }
  }
  return ms_span_of_text("");
}

enum { HINT_CAP = 200000 };

typedef struct HintRow {
  size_t file, line, col, len, ty;
} HintRow;

static int64_t compare_row(uint8_t *env, const uint8_t *left, const uint8_t *right) {
  (void)env;
  const size_t *x = (const size_t *)(const void *)left;
  const size_t *y = (const size_t *)(const void *)right;
  for (size_t i = 0; i < 5; i++) {
    if (x[i] != y[i]) {
      return x[i] < y[i] ? -1 : 1;
    }
  }
  return 0;
}

/* `[type table, [file index, line, column, length, type index, ...]]`, rows in source order. */
static void hints_json(MsArena *arena, const Index *ix, const MsTypeHints *hints, MsStrBuild *out) {
  MsSpans table = {0};
  HintRow *rows = MS_ARENA_NEW_ARRAY(arena, HintRow, hints->len + 1);
  size_t count = 0;
  for (size_t i = 0; hints != NULL && i < hints->len && i < HINT_CAP; i++) {
    const MsTypeHint *hint = &hints->ptr[i];
    size_t file = 0;
    if (!has_file(ix, hint->file, &file)) {
      continue;
    }
    size_t ty = 0;
    while (ty < table.len && !ms_span_equal(table.ptr[ty], hint->ty)) {
      ty++;
    }
    if (ty == table.len) {
      ms_spans_push(arena, &table, hint->ty);
    }
    rows[count++] = (HintRow){file, hint->line, hint->col, hint->len, ty};
  }
  ms_sort((uint8_t *)rows, count, sizeof(HintRow), compare_row, NULL);
  ms_strbuild_append_byte(out, '[');
  strings(out, &table);
  ms_strbuild_append_text(out, ",[");
  for (size_t i = 0; i < count; i++) {
    ms_strbuild_append_text(out, i > 0 ? "," : "");
    number(out, rows[i].file);
    ms_strbuild_append_byte(out, ',');
    number(out, rows[i].line);
    ms_strbuild_append_byte(out, ',');
    number(out, rows[i].col);
    ms_strbuild_append_byte(out, ',');
    number(out, rows[i].len);
    ms_strbuild_append_byte(out, ',');
    number(out, rows[i].ty);
  }
  ms_strbuild_append_text(out, "]]");
}

static void data(MsArena *arena, const MsFactModel *model, const MsFindings *changes, const MsTypeHints *hints, MsStrBuild *out) {
  Index ix = {.model = model};
  size_t at = 0;
  for (size_t i = 0; i < model->entities.len; i++) {
    if (!has_file(&ix, model->entities.ptr[i].file, &at)) {
      ms_spans_push(arena, &ix.files, model->entities.ptr[i].file);
    }
  }
  for (size_t i = 0; i < model->imports.len; i++) {
    if (!has_file(&ix, model->imports.ptr[i].file, &at)) {
      ms_spans_push(arena, &ix.files, model->imports.ptr[i].file);
    }
  }
  ms_strbuild_append_text(out, "{\"f\":");
  strings(out, &ix.files);
  ms_strbuild_append_text(out, ",\"s\":[");
  for (size_t i = 0; i < ix.files.len; i++) {
    ms_strbuild_append_text(out, i > 0 ? "," : "");
    ms_json_string(out, source_of(model, ix.files.ptr[i]));
  }
  ms_strbuild_append_text(out, "],\"m\":[");
  for (size_t i = 0; i < model->imports.len; i++) {
    ms_strbuild_append_text(out, i > 0 ? ",[" : "[");
    number(out, file_index(&ix, model->imports.ptr[i].file));
    ms_strbuild_append_byte(out, ',');
    strings(out, &model->imports.ptr[i].paths);
    ms_strbuild_append_byte(out, ']');
  }
  ms_strbuild_append_text(out, "],\"e\":[");
  for (size_t i = 0; i < model->entities.len; i++) {
    ms_strbuild_append_text(out, i > 0 ? "," : "");
    entity(&ix, out, &model->entities.ptr[i]);
  }
  ms_strbuild_append_text(out, "],\"t\":");
  hints_json(arena, &ix, hints, out);
  if (changes != NULL) {
    /* [entity index or -1 when removed, name, tier, what changed] */
    ms_strbuild_append_text(out, ",\"x\":[");
    for (size_t i = 0; i < changes->len; i++) {
      const MsFinding *f = &changes->ptr[i];
      ms_strbuild_append_text(out, i > 0 ? ",[" : "[");
      ms_strbuild_append_i64(out, entity_index(&ix, f->id));
      ms_strbuild_append_byte(out, ',');
      ms_json_string(out, f->entity);
      ms_strbuild_append_byte(out, ',');
      ms_json_string(out, f->tier);
      ms_strbuild_append_byte(out, ',');
      strings(out, &f->changes);
      ms_strbuild_append_byte(out, ']');
    }
    ms_strbuild_append_byte(out, ']');
  }
  ms_strbuild_append_byte(out, '}');
}

void ms_html_page(MsArena *arena, const MsFactModel *model, const MsFindings *changes, const MsTypeHints *hints, MsStrBuild *out) {
  MsStrBuild json = ms_strbuild_new();
  data(arena, model, changes, hints, &json);
  const MsSpan page = ms_span_of(ms_page_html, ms_page_html_size);
  size_t at = 0;
  if (!ms_span_find(page, ms_span_of_text("__DATA__"), &at)) {
    ms_strbuild_append(out, page);
  } else {
    ms_strbuild_append(out, ms_span_of(page.ptr, at));
    ms_strbuild_append(out, ms_strbuild_span(&json));
    ms_strbuild_append(out, ms_span_of(page.ptr + at + 8, page.len - at - 8));
  }
  ms_strbuild_free(&json);
}

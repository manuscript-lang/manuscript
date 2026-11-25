/* compiler/project/toml.c: the TOML subset of ms.toml (see toml.h). */
#include "compiler/project/toml.h"

#include "base/strbuild.h"

typedef struct Scanner {
  MsArena *arena;
  MsSpan text;
  size_t bom;
  size_t at;     /* offset of the line being read */
  size_t resume; /* where the next line starts; a value that spans lines moves it */
  TomlDocument *document;
  int64_t open; /* the entry a `[dependencies.name]` header started, or -1 */
  MsPos error_at;
  MsSpan error_text;
} Scanner;

static MsPos position_at(const Scanner *s, size_t offset) {
  uint32_t line = 1;
  size_t line_start = 0;
  for (size_t i = 0; i < offset && i < s->text.len; i++) {
    if (s->text.ptr[i] == '\n') {
      line++;
      line_start = i + 1;
    }
  }
  return (MsPos){.offset = (uint32_t)(offset + s->bom), .line = line, .column = (uint32_t)(offset - line_start + 1)};
}

/* The offset of the newline ending the line that holds `at`, or the end of the text. */
static size_t line_end_of(const Scanner *s, size_t at) {
  while (at < s->text.len && s->text.ptr[at] != '\n') {
    at++;
  }
  return at;
}

static bool fail(Scanner *s, size_t offset, const char *message) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "invalid ms.toml: ");
  ms_strbuild_append_text(&text, message);
  s->error_at = position_at(s, offset);
  s->error_text = ms_arena_copy(s->arena, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  return false;
}

static bool is_blank(uint8_t c) {
  return c == ' ' || c == '\t';
}

static bool is_bare(uint8_t c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-';
}

static size_t skip_blank(const Scanner *s, size_t at, size_t end) {
  while (at < end && is_blank(s->text.ptr[at])) {
    at++;
  }
  return at;
}

/* Appends the escape at `text[at]` (after the backslash) to `out`; returns the offset after it, or 0. */
static size_t append_escape(MsStrBuild *out, MsSpan text, size_t at) {
  static const char from[] = "btnfr\"\\";
  static const char to[] = "\b\t\n\f\r\"\\";
  for (size_t i = 0; from[i] != 0; i++) {
    if (at < text.len && text.ptr[at] == (uint8_t)from[i]) {
      ms_strbuild_append_byte(out, (uint8_t)to[i]);
      return at + 1;
    }
  }
  return 0;
}

/* Reads a quoted string that starts at `at` (the quote) and stays on the line ending at `end`. Returns the
 * offset after the closing quote, or 0 after reporting. */
static size_t read_string(Scanner *s, size_t at, size_t end, MsSpan *value) {
  const uint8_t quote = s->text.ptr[at];
  MsStrBuild out = ms_strbuild_new();
  size_t i = at + 1;
  while (i < end && s->text.ptr[i] != quote) {
    if (quote == '"' && s->text.ptr[i] == '\\') {
      i = append_escape(&out, s->text, i + 1);
      if (i == 0) {
        ms_strbuild_free(&out);
        (void)fail(s, at, "unsupported escape in a string");
        return 0;
      }
      continue;
    }
    ms_strbuild_append_byte(&out, s->text.ptr[i++]);
  }
  if (i >= end) {
    ms_strbuild_free(&out);
    (void)fail(s, at, "unterminated string");
    return 0;
  }
  *value = ms_arena_copy(s->arena, ms_strbuild_span(&out));
  ms_strbuild_free(&out);
  return i + 1;
}

static bool read_key(Scanner *s, size_t *at, size_t end, MsSpan *key) {
  const uint8_t first = s->text.ptr[*at];
  if (first == '"' || first == '\'') {
    *at = read_string(s, *at, end, key);
    return *at != 0;
  }
  const size_t start = *at;
  while (*at < end && is_bare(s->text.ptr[*at])) {
    (*at)++;
  }
  if (*at == start) {
    return fail(s, start, "expected a key");
  }
  *key = ms_arena_copy(s->arena, ms_span_of(s->text.ptr + start, *at - start));
  return true;
}

/* The end of the content of a line: before a `#` comment that is not inside a string, without trailing blanks. */
static size_t content_end(const Scanner *s, size_t from, size_t end) {
  uint8_t quote = 0;
  size_t i = from;
  for (; i < end; i++) {
    const uint8_t c = s->text.ptr[i];
    if (quote != 0) {
      i += (quote == '"' && c == '\\') ? 1 : 0;
      quote = (c == quote) ? 0 : quote;
    } else if (c == '"' || c == '\'') {
      quote = c;
    } else if (c == '#') {
      break;
    }
  }
  while (i > from && is_blank(s->text.ptr[i - 1])) {
    i--;
  }
  return i;
}

static bool only_comment(const Scanner *s, size_t at, size_t end) {
  at = skip_blank(s, at, end);
  return at == end || s->text.ptr[at] == '#';
}


static int64_t table_entry(Scanner *s, int32_t table, MsSpan key, MsPos key_at);

/* `[dependencies.name]`: the fields below it belong to the dependency `name` of the [dependencies] table. */
static bool read_dependency_header(Scanner *s, size_t at, size_t close) {
  size_t i = at + 1 + sizeof "dependencies." - 1;
  MsSpan key = {0};
  if (!read_key(s, &i, close, &key)) {
    return false;
  }
  if (i != close) {
    return fail(s, at, "unsupported table header");
  }
  int32_t table = -1;
  for (size_t t = 0; t < s->document->tables.len; t++) {
    table = ms_span_is_text(s->document->tables.ptr[t].name, "dependencies") ? (int32_t)t : table;
  }
  if (table < 0) {
    toml_table_list_push(&s->document->tables,
                         (TomlTable){.name = ms_span_of_text("dependencies"), .at = position_at(s, at)});
    table = (int32_t)s->document->tables.len - 1;
  }
  for (size_t e = 0; e < s->document->entries.len; e++) {
    if (s->document->entries.ptr[e].table == table && ms_span_equal(s->document->entries.ptr[e].key, key)) {
      return fail(s, at, "duplicate key");
    }
  }
  s->open = table_entry(s, table, key, position_at(s, at));
  return true;
}

static bool read_header(Scanner *s, size_t at, size_t end) {
  size_t close = at + 1;
  while (close < end && s->text.ptr[close] != ']') {
    close++;
  }
  if (close >= end || s->text.ptr[at + 1] == '[') {
    return fail(s, at, "unsupported table header");
  }
  if (!only_comment(s, close + 1, end)) {
    return fail(s, close + 1, "unexpected content after a table header");
  }
  const MsSpan name = ms_span_of(s->text.ptr + at + 1, close - at - 1);
  s->open = -1;
  if (ms_span_starts_with_text(name, "dependencies.")) {
    return read_dependency_header(s, at, close);
  }
  for (size_t i = 0; i < s->document->tables.len; i++) {
    if (ms_span_equal(s->document->tables.ptr[i].name, name)) {
      return fail(s, at, "duplicate key");
    }
  }
  toml_table_list_push(&s->document->tables,
                       (TomlTable){.name = ms_arena_copy(s->arena, name), .at = position_at(s, at)});
  return true;
}

/* A string, or the raw text of a value, ending at a `,` or `closer` outside strings and nested brackets. */
static bool read_element(Scanner *s, size_t *at, uint8_t closer, TomlValue *out) {
  const size_t start = *at;
  out->at = position_at(s, start);
  const uint8_t first = s->text.ptr[start];
  if (first == '"' || first == '\'') {
    const size_t after = read_string(s, start, line_end_of(s, start), &out->text);
    if (after == 0) {
      return false;
    }
    out->is_string = true;
    *at = after;
    return true;
  }
  size_t i = start;
  int depth = 0;
  while (i < s->text.len && s->text.ptr[i] != '\n') {
    const uint8_t c = s->text.ptr[i];
    if (depth == 0 && (c == ',' || c == closer || c == '#')) {
      break;
    }
    if (c == '"' || c == '\'') {
      const size_t after = read_string(s, i, line_end_of(s, i), &out->text);
      if (after == 0) {
        return false;
      }
      i = after;
      continue;
    }
    depth += (c == '[' || c == '{') - (c == ']' || c == '}');
    i++;
  }
  size_t stop = i;
  while (stop > start && (is_blank(s->text.ptr[stop - 1]) || s->text.ptr[stop - 1] == '\r')) {
    stop--;
  }
  out->text = ms_arena_copy(s->arena, ms_span_of(s->text.ptr + start, stop - start));
  *at = i;
  return true;
}

/* Skips blanks, and (in an array) line breaks and comments. */
static size_t skip_space(const Scanner *s, size_t at, bool lines) {
  while (at < s->text.len) {
    const uint8_t c = s->text.ptr[at];
    if (is_blank(c) || (lines && (c == '\n' || c == '\r'))) {
      at++;
    } else if (lines && c == '#') {
      at = line_end_of(s, at);
    } else {
      break;
    }
  }
  return at;
}

static bool read_array(Scanner *s, size_t at, TomlEntry *entry, size_t *after) {
  entry->kind = TOML_ARRAY;
  entry->first = s->document->values.len;
  size_t i = skip_space(s, at + 1, true);
  while (i < s->text.len && s->text.ptr[i] != ']') {
    TomlValue element = {0};
    if (!read_element(s, &i, ']', &element)) {
      return false;
    }
    toml_value_list_push(&s->document->values, element);
    entry->count++;
    i = skip_space(s, i, true);
    if (i < s->text.len && s->text.ptr[i] == ',') {
      i = skip_space(s, i + 1, true);
    } else if (i >= s->text.len || s->text.ptr[i] != ']') {
      return fail(s, i, "expected `,` or `]` in an array");
    }
  }
  if (i >= s->text.len) {
    return fail(s, at, "unterminated array");
  }
  entry->text = ms_arena_copy(s->arena, ms_span_of(s->text.ptr + at, i + 1 - at));
  *after = i + 1;
  return true;
}

static bool read_inline_table(Scanner *s, size_t at, TomlEntry *entry, size_t *after) {
  entry->kind = TOML_TABLE;
  entry->first = s->document->values.len;
  const size_t end = line_end_of(s, at);
  size_t i = skip_space(s, at + 1, false);
  while (i < end && s->text.ptr[i] != '}') {
    TomlValue field = {0};
    const size_t key_at = i;
    if (!read_key(s, &i, end, &field.key)) {
      return false;
    }
    i = skip_space(s, i, false);
    if (i >= end || s->text.ptr[i] != '=') {
      return fail(s, i, "expected `=` after a key");
    }
    i = skip_space(s, i + 1, false);
    if (i >= end || !read_element(s, &i, '}', &field)) {
      return i >= end ? fail(s, i, "expected a value") : false;
    }
    field.at = position_at(s, key_at);
    toml_value_list_push(&s->document->values, field);
    entry->count++;
    i = skip_space(s, i, false);
    if (i < end && s->text.ptr[i] == ',') {
      i = skip_space(s, i + 1, false);
    } else if (i >= end || s->text.ptr[i] != '}') {
      return fail(s, i, "expected `,` or `}` in an inline table");
    }
  }
  if (i >= end) {
    return fail(s, at, "unterminated inline table");
  }
  entry->text = ms_arena_copy(s->arena, ms_span_of(s->text.ptr + at, i + 1 - at));
  *after = i + 1;
  return true;
}

/* Reads the value at `at`; `*after` is the offset after it. The rest of its last line may only hold a comment. */
static bool read_value(Scanner *s, size_t at, size_t end, TomlEntry *entry) {
  entry->value_at = position_at(s, at);
  if (at >= end) {
    return fail(s, at, "expected a value");
  }
  const uint8_t first = s->text.ptr[at];
  size_t after = end;
  if (first == '"' || first == '\'') {
    if (at + 2 < end && s->text.ptr[at + 1] == first && s->text.ptr[at + 2] == first) {
      return fail(s, at, "multi-line strings are not supported");
    }
    after = read_string(s, at, end, &entry->text);
    if (after == 0) {
      return false;
    }
    entry->kind = TOML_STRING;
    entry->is_string = true;
  } else if (first == '[') {
    if (!read_array(s, at, entry, &after)) {
      return false;
    }
  } else if (first == '{') {
    if (!read_inline_table(s, at, entry, &after)) {
      return false;
    }
  } else {
    const size_t stop = content_end(s, at, end);
    entry->text = ms_arena_copy(s->arena, ms_span_of(s->text.ptr + at, stop - at));
    return true;
  }
  const size_t last = line_end_of(s, after);
  const size_t content = last > after && s->text.ptr[last - 1] == '\r' ? last - 1 : last;
  if (!only_comment(s, after, content)) {
    return fail(s, after, "unexpected content after a value");
  }
  s->resume = last + 1;
  return true;
}



/* The index of the entry `key` in `table` that holds a table's fields, made when missing; -1 when `key` is taken by
 * another kind of value. */
static int64_t table_entry(Scanner *s, int32_t table, MsSpan key, MsPos key_at) {
  TomlEntryList *entries = &s->document->entries;
  for (size_t i = 0; i < entries->len; i++) {
    if (entries->ptr[i].table == table && ms_span_equal(entries->ptr[i].key, key)) {
      return entries->ptr[i].kind == TOML_TABLE ? (int64_t)i : -1;
    }
  }
  toml_entry_list_push(entries, (TomlEntry){.table = table, .key = key, .kind = TOML_TABLE, .key_at = key_at,
                                            .value_at = key_at, .first = s->document->values.len});
  return (int64_t)entries->len - 1;
}

/* Adds `field` to the table entry `index`; its fields stay one run in `values`, so a run that another table's
 * fields followed moves to the end first. */
static bool add_field(Scanner *s, int64_t index, TomlValue field) {
  TomlEntryList *entries = &s->document->entries;
  TomlValueList *values = &s->document->values;
  const size_t first = entries->ptr[index].first;
  const size_t count = entries->ptr[index].count;
  for (size_t i = 0; i < count; i++) {
    if (ms_span_equal(values->ptr[first + i].key, field.key)) {
      return fail(s, field.at.offset - s->bom, "duplicate key");
    }
  }
  if (count > 0 && first + count != values->len) {
    const size_t moved = values->len;
    for (size_t i = 0; i < count; i++) {
      toml_value_list_push(values, values->ptr[first + i]);
    }
    entries->ptr[index].first = moved;
  }
  toml_value_list_push(values, field);
  entries->ptr[index].count++;
  return true;
}

/* `key = value` of a dotted key or a `[dependencies.name]` table, added to the table entry `index`. */
static bool read_field(Scanner *s, int64_t index, size_t at, size_t end) {
  TomlValue field = {.at = position_at(s, at)};
  if (!read_key(s, &at, end, &field.key)) {
    return false;
  }
  at = skip_blank(s, at, end);
  if (at >= end || s->text.ptr[at] != '=') {
    return fail(s, at, "expected `=` after a key");
  }
  at = skip_blank(s, at + 1, end);
  const MsPos key_at = field.at;
  if (at >= end || !read_element(s, &at, 0, &field)) {
    return at >= end ? fail(s, at, "expected a value") : false;
  }
  field.at = key_at;
  if (!only_comment(s, at, end)) {
    return fail(s, at, "unexpected content after a value");
  }
  return add_field(s, index, field);
}

static bool read_assignment(Scanner *s, size_t at, size_t end) {
  TomlEntry entry = {.table = (int32_t)s->document->tables.len - 1};
  entry.key_at = position_at(s, at);
  if (s->open >= 0) {
    return read_field(s, s->open, at, end);
  }
  if (!read_key(s, &at, end, &entry.key)) {
    return false;
  }
  if (at < end && s->text.ptr[at] == '.') {
    const int64_t index = table_entry(s, entry.table, entry.key, entry.key_at);
    return index < 0 ? fail(s, at, "duplicate key") : read_field(s, index, at + 1, end);
  }
  at = skip_blank(s, at, end);
  if (at >= end || s->text.ptr[at] != '=') {
    return fail(s, at, "expected `=` after a key");
  }
  at = skip_blank(s, at + 1, end);
  if (!read_value(s, at, end, &entry)) {
    return false;
  }
  for (size_t i = 0; i < s->document->entries.len; i++) {
    const TomlEntry *seen = &s->document->entries.ptr[i];
    if (seen->table == entry.table && ms_span_equal(seen->key, entry.key)) {
      return fail(s, entry.key_at.offset - s->bom, "duplicate key");
    }
  }
  toml_entry_list_push(&s->document->entries, entry);
  return true;
}

static bool read_line(Scanner *s, size_t end) {
  size_t stop = end;
  if (stop > s->at && s->text.ptr[stop - 1] == '\r') {
    stop--;
  }
  const size_t at = skip_blank(s, s->at, stop);
  if (at == stop || s->text.ptr[at] == '#') {
    return true;
  }
  return s->text.ptr[at] == '[' ? read_header(s, at, stop) : read_assignment(s, at, stop);
}

bool toml_parse(MsArena *arena, MsSpan text, size_t bom, TomlDocument *out, MsPos *error_at,
                MsSpan *error_text) {
  Scanner s = {.arena = arena, .text = text, .bom = bom, .document = out, .open = -1};
  while (s.at <= text.len) {
    const size_t end = line_end_of(&s, s.at);
    s.resume = end + 1;
    if (!read_line(&s, end)) {
      *error_at = s.error_at;
      *error_text = s.error_text;
      return false;
    }
    s.at = s.resume;
  }
  return true;
}

void toml_free(TomlDocument *document) {
  toml_table_list_free(&document->tables);
  toml_entry_list_free(&document->entries);
  toml_value_list_free(&document->values);
}

/* Owns the text edits of ms.toml for `ms add` and `ms remove` (edit.h): whole lines are inserted or removed, so every
 * comment and the formatting of the rest of the file stay. A comment or blank line belongs to the item that follows
 * it, so removing an item removes the notes written above it. */
#include "compiler/project/edit.h"

#include "base/strbuild.h"
#include "compiler/project/manifest_internal.h"

/* The text with LF line endings, split into lines. */
typedef struct Lines {
  MsSpan text;
  size_t *starts; /* offset of each line */
  size_t count;
  bool crlf;
} Lines;

/* `table`: the entries of one table of the document, with the line ranges that belong to each item. */
typedef struct Items {
  size_t header;     /* line of the header */
  size_t keys;       /* entries */
  size_t bound[64];  /* bound[0]: start of the header item; bound[i]: start of entry i - 1's item; the last is the end */
  size_t entry[63];  /* index in the document's entries */
} Items;

static bool blank_or_comment(const Lines *lines, size_t line) {
  size_t at = lines->starts[line];
  const size_t end = line + 1 < lines->count ? lines->starts[line + 1] : lines->text.len;
  while (at < end && (lines->text.ptr[at] == ' ' || lines->text.ptr[at] == '\t' || lines->text.ptr[at] == '\n')) {
    at++;
  }
  return at == end || lines->text.ptr[at] == '#';
}

/* The first line of the notes directly above `line`, no earlier than `floor`. */
static size_t prefix_start(const Lines *lines, size_t line, size_t floor) {
  while (line > floor && blank_or_comment(lines, line - 1)) {
    line--;
  }
  return line;
}

static MsSpan normalized(MsArena *arena, MsSpan text, bool *crlf) {
  *crlf = false;
  MsStrBuild out = ms_strbuild_new();
  for (size_t i = 0; i < text.len; i++) {
    if (text.ptr[i] == '\r' && i + 1 < text.len && text.ptr[i + 1] == '\n') {
      *crlf = true;
      continue;
    }
    ms_strbuild_append_byte(&out, text.ptr[i]);
  }
  const MsSpan copy = ms_arena_copy(arena, ms_strbuild_span(&out));
  ms_strbuild_free(&out);
  return copy;
}

static void lines_split(MsArena *arena, Lines *lines) {
  size_t count = 1;
  for (size_t i = 0; i < lines->text.len; i++) {
    count += lines->text.ptr[i] == '\n' && i + 1 < lines->text.len ? 1 : 0;
  }
  lines->starts = MS_ARENA_NEW_ARRAY(arena, size_t, count);
  lines->count = lines->text.len == 0 ? 0 : count;
  size_t line = 0;
  for (size_t i = 0; i < lines->text.len; i++) {
    if (i == 0 || lines->text.ptr[i - 1] == '\n') {
      lines->starts[line++] = i;
    }
  }
}

/* The text of the edited lines, in the line endings of the original. */
static MsSpan restored(MsArena *arena, const MsStrBuild *edited, bool crlf) {
  if (!crlf) {
    return ms_arena_copy(arena, ms_strbuild_span(edited));
  }
  MsStrBuild out = ms_strbuild_new();
  const MsSpan text = ms_strbuild_span(edited);
  for (size_t i = 0; i < text.len; i++) {
    if (text.ptr[i] == '\n') {
      ms_strbuild_append_byte(&out, '\r');
    }
    ms_strbuild_append_byte(&out, text.ptr[i]);
  }
  const MsSpan copy = ms_arena_copy(arena, ms_strbuild_span(&out));
  ms_strbuild_free(&out);
  return copy;
}

static bool parse(MsArena *arena, MsSpan text, Lines *lines, TomlDocument *document, MsSpan *error) {
  const bool bom = text.len >= 3 && text.ptr[0] == 0xEF && text.ptr[1] == 0xBB && text.ptr[2] == 0xBF;
  const MsSpan body = ms_span_of(text.ptr + (bom ? 3 : 0), text.len - (bom ? 3 : 0));
  lines->text = normalized(arena, body, &lines->crlf);
  lines_split(arena, lines);
  MsPos at = {0};
  MsSpan message = {0};
  if (!toml_parse(arena, lines->text, 0, document, &at, &message)) {
    MsStrBuild text_error = ms_strbuild_new();
    ms_strbuild_append_text(&text_error, "ms.toml is not valid TOML: ");
    ms_strbuild_append(&text_error, message);
    *error = ms_arena_copy(arena, ms_strbuild_span(&text_error));
    ms_strbuild_free(&text_error);
    return false;
  }
  return true;
}

static int32_t find_table(const TomlDocument *document, const char *name) {
  for (size_t i = 0; i < document->tables.len; i++) {
    if (ms_span_is_text(document->tables.ptr[i].name, name)) {
      return (int32_t)i;
    }
  }
  return -1;
}

/* The line ranges of table `index`. False when it holds more entries than an edit handles. */
static bool table_items(const Lines *lines, const TomlDocument *document, int32_t index, Items *items) {
  *items = (Items){.header = document->tables.ptr[index].at.line - 1};
  for (size_t i = 0; i < document->entries.len; i++) {
    if (document->entries.ptr[i].table != index) {
      continue;
    }
    if (items->keys == 62) {
      return false;
    }
    items->entry[items->keys++] = i;
  }
  size_t end = lines->count;
  if ((size_t)index + 1 < document->tables.len) {
    end = prefix_start(lines, document->tables.ptr[index + 1].at.line - 1, items->header + 1);
  } else {
    while (end > items->header + 1 && blank_or_comment(lines, end - 1)) {
      end--;
    }
  }
  items->bound[0] = prefix_start(lines, items->header, 0);
  for (size_t k = 0; k < items->keys; k++) {
    const size_t line = document->entries.ptr[items->entry[k]].key_at.line - 1;
    items->bound[k + 1] = prefix_start(lines, line, items->bound[k] + 1);
  }
  items->bound[items->keys + 1] = end;
  return true;
}

static size_t find_key(const TomlDocument *document, const Items *items, MsSpan key) {
  for (size_t k = 0; k < items->keys; k++) {
    if (ms_span_equal(document->entries.ptr[items->entry[k]].key, key)) {
      return k + 1;
    }
  }
  return 0;
}

static size_t line_offset(const Lines *lines, size_t line) {
  return line < lines->count ? lines->starts[line] : lines->text.len;
}

static void append_lines(const Lines *lines, MsStrBuild *out, size_t from, size_t to) {
  ms_strbuild_append(out, ms_span_of(lines->text.ptr + line_offset(lines, from),
                                     line_offset(lines, to) - line_offset(lines, from)));
}

static void append_quoted(MsStrBuild *out, MsSpan text) {
  ms_strbuild_append_byte(out, '"');
  for (size_t i = 0; i < text.len; i++) {
    if (text.ptr[i] == '"' || text.ptr[i] == '\\') {
      ms_strbuild_append_byte(out, '\\');
    }
    ms_strbuild_append_byte(out, text.ptr[i]);
  }
  ms_strbuild_append_byte(out, '"');
}

/* The text with lines [from, to) replaced by `with`. */
static void replace_lines(const Lines *lines, MsStrBuild *out, size_t from, size_t to, MsSpan with) {
  append_lines(lines, out, 0, from);
  ms_strbuild_append(out, with);
  append_lines(lines, out, to, lines->count);
}

/* The text with `with` inserted before line `at` (a missing final newline is supplied first). */
static void insert_lines(const Lines *lines, MsStrBuild *out, size_t at, MsSpan with) {
  append_lines(lines, out, 0, at);
  const MsSpan before = ms_strbuild_span(out);
  if (before.len > 0 && before.ptr[before.len - 1] != '\n') {
    ms_strbuild_append_byte(out, '\n');
  }
  ms_strbuild_append(out, with);
  append_lines(lines, out, at, lines->count);
}

/* Appends `[name]` and `entry` as a new table at the end of the text. */
static void append_table(const Lines *lines, MsStrBuild *out, const char *name, MsSpan entry) {
  append_lines(lines, out, 0, lines->count);
  const MsSpan before = ms_strbuild_span(out);
  if (before.len > 0) {
    if (before.ptr[before.len - 1] != '\n') {
      ms_strbuild_append_byte(out, '\n');
    }
    ms_strbuild_append_byte(out, '\n');
  }
  ms_strbuild_printf(out, "[%s]\n", name);
  ms_strbuild_append(out, entry);
}

/* Adds the entry text `entry` to table `name`, creating the table when it is missing. */
static void add_entry(const Lines *lines, const TomlDocument *document, const char *name, MsSpan entry,
                      MsStrBuild *out) {
  const int32_t index = find_table(document, name);
  Items items;
  if (index < 0 || !table_items(lines, document, index, &items)) {
    append_table(lines, out, name, entry);
    return;
  }
  insert_lines(lines, out, items.bound[items.keys + 1], entry);
}

static MsSpan entry_text(MsArena *arena, MsSpan name, MsSpan value) {
  MsStrBuild line = ms_strbuild_new();
  append_quoted(&line, name);
  ms_strbuild_append_text(&line, " = ");
  ms_strbuild_append(&line, value);
  ms_strbuild_append_byte(&line, '\n');
  const MsSpan text = ms_arena_copy(arena, ms_strbuild_span(&line));
  ms_strbuild_free(&line);
  return text;
}

static MsSpan error_text(MsArena *arena, const char *format, MsSpan name) {
  MsStrBuild text = ms_strbuild_new();
  const char *at = format;
  while (*at != 0) {
    if (at[0] == '%' && at[1] == 'N') {
      ms_strbuild_append(&text, name);
      at += 2;
      continue;
    }
    ms_strbuild_append_byte(&text, (uint8_t)*at++);
  }
  const MsSpan copy = ms_arena_copy(arena, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  return copy;
}

bool ms_edit_default_name(MsArena *arena, MsSpan url, MsSpan *name) {
  size_t end = url.len;
  while (end > 0 && url.ptr[end - 1] == '/') {
    end--;
  }
  size_t start = end;
  while (start > 0 && url.ptr[start - 1] != '/' && url.ptr[start - 1] != ':') {
    start--;
  }
  MsSpan base = ms_span_of(url.ptr + start, end - start);
  if (ms_span_ends_with(base, ms_span_of_text(".git"))) {
    base = ms_span_of(base.ptr, base.len - 4);
  }
  if (ms_span_starts_with(base, ms_span_of_text("ms-"))) {
    base = ms_span_of(base.ptr + 3, base.len - 3);
  }
  MsStrBuild alias = ms_strbuild_new();
  ms_strbuild_append_byte(&alias, '@');
  for (size_t i = 0; i < base.len; i++) {
    ms_strbuild_append_byte(&alias, base.ptr[i] == '-' ? '_' : base.ptr[i]);
  }
  const bool valid = manifest_valid_alias(ms_strbuild_span(&alias));
  *name = ms_arena_copy(arena, ms_strbuild_span(&alias));
  ms_strbuild_free(&alias);
  return valid;
}

static const char *kind_key(MsSourceKind kind) {
  return kind == MS_SOURCE_TAG ? "tag" : kind == MS_SOURCE_SHA ? "sha" : "version";
}

static MsSpan dependency_value(MsArena *arena, const MsDependencyEdit *dependency) {
  MsStrBuild value = ms_strbuild_new();
  ms_strbuild_append_text(&value, "{ url = ");
  append_quoted(&value, dependency->url);
  ms_strbuild_printf(&value, ", %s = ", kind_key(dependency->kind));
  append_quoted(&value, dependency->pin);
  ms_strbuild_append_text(&value, " }");
  const MsSpan text = ms_arena_copy(arena, ms_strbuild_span(&value));
  ms_strbuild_free(&value);
  return text;
}

bool ms_edit_add_dependency(MsArena *arena, MsSpan text, const MsDependencyEdit *dependency, MsSpan *out,
                            MsSpan *error) {
  Lines lines = {0};
  TomlDocument document = {0};
  if (!parse(arena, text, &lines, &document, error)) {
    return false;
  }
  const int32_t index = find_table(&document, "dependencies");
  Items items;
  if (index >= 0 && table_items(&lines, &document, index, &items) &&
      find_key(&document, &items, dependency->name) != 0) {
    *error = error_text(arena, "%N is already in [dependencies]; run `ms remove %N` first, or edit its entry",
                        dependency->name);
    toml_free(&document);
    return false;
  }
  MsStrBuild edited = ms_strbuild_new();
  add_entry(&lines, &document, "dependencies", entry_text(arena, dependency->name, dependency_value(arena, dependency)),
            &edited);
  *out = restored(arena, &edited, lines.crlf);
  ms_strbuild_free(&edited);
  toml_free(&document);
  return true;
}

bool ms_edit_allow_effects(MsArena *arena, MsSpan text, MsSpan name, const MsSpan *effects, size_t count,
                           MsSpan *out, MsSpan *error) {
  Lines lines = {0};
  TomlDocument document = {0};
  if (!parse(arena, text, &lines, &document, error)) {
    return false;
  }
  MsStrBuild value = ms_strbuild_new();
  ms_strbuild_append_byte(&value, '[');
  for (size_t i = 0; i < count; i++) {
    ms_strbuild_append_text(&value, i == 0 ? "" : ", ");
    append_quoted(&value, effects[i]);
  }
  ms_strbuild_append_byte(&value, ']');
  const MsSpan entry = entry_text(arena, name, ms_strbuild_span(&value));
  ms_strbuild_free(&value);
  MsStrBuild edited = ms_strbuild_new();
  const int32_t index = find_table(&document, "effects");
  Items items;
  const size_t existing = index >= 0 && table_items(&lines, &document, index, &items) ? find_key(&document, &items, name) : 0;
  if (existing != 0) {
    const size_t line = document.entries.ptr[items.entry[existing - 1]].key_at.line - 1;
    replace_lines(&lines, &edited, line, items.bound[existing + 1], entry);
  } else {
    add_entry(&lines, &document, "effects", entry, &edited);
  }
  *out = restored(arena, &edited, lines.crlf);
  ms_strbuild_free(&edited);
  toml_free(&document);
  return true;
}

/* Removes `name` from table `table_name` when it is there; the table goes too when that empties it. Marks the line
 * ranges to drop in `drop` (a per-line flag). */
static bool mark_removal(const Lines *lines, const TomlDocument *document, const char *table_name, MsSpan name,
                         bool *drop) {
  const int32_t index = find_table(document, table_name);
  Items items;
  if (index < 0 || !table_items(lines, document, index, &items)) {
    return false;
  }
  const size_t key = find_key(document, &items, name);
  if (key == 0) {
    return false;
  }
  const size_t from = items.keys == 1 ? items.bound[0] : items.bound[key];
  const size_t to = items.keys == 1 ? items.bound[2] : items.bound[key + 1];
  for (size_t line = from; line < to; line++) {
    drop[line] = true;
  }
  return true;
}

bool ms_edit_remove_dependency(MsArena *arena, MsSpan text, MsSpan name, MsSpan *out, MsSpan *error) {
  Lines lines = {0};
  TomlDocument document = {0};
  if (!parse(arena, text, &lines, &document, error)) {
    return false;
  }
  bool *drop = MS_ARENA_NEW_ARRAY(arena, bool, lines.count + 1);
  if (!mark_removal(&lines, &document, "dependencies", name, drop)) {
    *error = error_text(arena, "%N is not in [dependencies]", name);
    toml_free(&document);
    return false;
  }
  (void)mark_removal(&lines, &document, "effects", name, drop);
  MsStrBuild edited = ms_strbuild_new();
  for (size_t line = 0; line < lines.count; line++) {
    if (!drop[line]) {
      append_lines(&lines, &edited, line, line + 1);
    }
  }
  *out = restored(arena, &edited, lines.crlf);
  ms_strbuild_free(&edited);
  toml_free(&document);
  return true;
}

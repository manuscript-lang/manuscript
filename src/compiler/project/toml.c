/* compiler/project/toml.c: the TOML subset of ms.toml (see toml.h). */
#include "compiler/project/toml.h"

#include "base/strbuild.h"

typedef struct Scanner {
  MsArena *arena;
  MsSpan text;
  size_t bom;
  size_t at;         /* offset of the next byte */
  size_t line_start; /* offset of the current line */
  uint32_t line;
  TomlDocument *document;
  MsPos error_at;
  MsSpan error_text;
} Scanner;

static MsPos position_at(const Scanner *s, size_t offset) {
  return (MsPos){.offset = (uint32_t)(offset + s->bom),
                 .line = s->line,
                 .column = (uint32_t)(offset - s->line_start + 1)};
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
  for (size_t i = 0; i < s->document->tables.len; i++) {
    if (ms_span_equal(s->document->tables.ptr[i].name, name)) {
      return fail(s, at, "duplicate key");
    }
  }
  toml_table_list_push(&s->document->tables,
                       (TomlTable){.name = ms_arena_copy(s->arena, name), .at = position_at(s, at)});
  return true;
}

static bool read_value(Scanner *s, size_t at, size_t end, TomlEntry *entry) {
  entry->value_at = position_at(s, at);
  if (at >= end) {
    return fail(s, at, "expected a value");
  }
  const uint8_t first = s->text.ptr[at];
  if (first == '"' || first == '\'') {
    if (at + 2 < end && s->text.ptr[at + 1] == first && s->text.ptr[at + 2] == first) {
      return fail(s, at, "multi-line strings are not supported");
    }
    const size_t after = read_string(s, at, end, &entry->text);
    if (after == 0) {
      return false;
    }
    entry->is_string = true;
    if (!only_comment(s, after, end)) {
      return fail(s, after, "unexpected content after a value");
    }
    return true;
  }
  const size_t stop = content_end(s, at, end);
  entry->text = ms_arena_copy(s->arena, ms_span_of(s->text.ptr + at, stop - at));
  return true;
}

static bool read_assignment(Scanner *s, size_t at, size_t end) {
  TomlEntry entry = {.table = (int32_t)s->document->tables.len - 1};
  entry.key_at = position_at(s, at);
  if (!read_key(s, &at, end, &entry.key)) {
    return false;
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
  Scanner s = {.arena = arena, .text = text, .bom = bom, .line = 1, .document = out};
  while (s.at <= text.len) {
    size_t newline = 0;
    const bool more = ms_span_find(ms_span_of(text.ptr + s.at, text.len - s.at), ms_span_of_text("\n"), &newline);
    const size_t end = more ? s.at + newline : text.len;
    if (!read_line(&s, end)) {
      *error_at = s.error_at;
      *error_text = s.error_text;
      return false;
    }
    if (!more) {
      break;
    }
    s.at = end + 1;
    s.line_start = s.at;
    s.line++;
  }
  return true;
}

void toml_free(TomlDocument *document) {
  toml_table_list_free(&document->tables);
  toml_entry_list_free(&document->entries);
}

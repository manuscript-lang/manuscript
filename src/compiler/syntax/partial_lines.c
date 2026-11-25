/* Owns the line-level rules of editor recovery: which column-zero lines start a declaration. */
#include "base/chars.h"
#include "compiler/syntax/partial_internal.h"

static bool is_space(uint8_t b) {
  return b == ' ' || b == '\t' || b == '\n' || b == '\r' || b == '\v' || b == '\f';
}

static MsSpan partial_trim_start(MsSpan text) {
  size_t at = 0;
  while (at < text.len && is_space(text.ptr[at])) {
    at++;
  }
  return ms_span_of(text.ptr + at, text.len - at);
}

MsSpan partial_trim_end(MsSpan text) {
  size_t end = text.len;
  while (end > 0 && is_space(text.ptr[end - 1])) {
    end--;
  }
  return ms_span_of(text.ptr, end);
}

MsSpan partial_trim(MsSpan text) {
  return partial_trim_start(partial_trim_end(text));
}

size_t partial_leading_space(MsSpan line) {
  size_t at = 0;
  while (at < line.len && (line.ptr[at] == ' ' || line.ptr[at] == '\t')) {
    at++;
  }
  return at;
}

bool partial_is_candidate_line(MsSpan line) {
  if (line.len == 0 || line.ptr[0] == ' ' || line.ptr[0] == '\t') {
    return false;
  }
  MsSpan trimmed = partial_trim(line);
  return trimmed.len != 0 && !ms_span_starts_with_text(trimmed, "//");
}

/* The text after `keyword` when it ends at a word boundary. */
static bool after_keyword(MsSpan source, const char *keyword, MsSpan *rest) {
  MsSpan word = ms_span_of_text(keyword);
  if (!ms_span_starts_with(source, word)) {
    return false;
  }
  MsSpan tail = ms_span_of(source.ptr + word.len, source.len - word.len);
  if (tail.len != 0 && ms_ascii_is_ident(tail.ptr[0])) {
    return false;
  }
  *rest = tail;
  return true;
}

static size_t identifier_length(MsSpan text) {
  size_t at = 0;
  while (at < text.len && ms_ascii_is_ident(text.ptr[at])) {
    at++;
  }
  return at;
}

/* A module constant starts `name :=` or `name: Type :=`. */
static bool constant_start(MsSpan source) {
  size_t name = identifier_length(source);
  if (name == 0 || ms_ascii_is_digit(source.ptr[0])) {
    return false;
  }
  MsSpan rest = partial_trim_start(ms_span_of(source.ptr + name, source.len - name));
  return ms_span_starts_with_text(rest, ":=");
}

/* A named function needs a parameter or type-parameter list after its name. Inferred callbacks can continue
 * their header on later lines. */
static bool function_start(MsSpan source) {
  MsSpan rest = {0};
  if (!after_keyword(source, "fn", &rest)) {
    return false;
  }
  rest = partial_trim_start(rest);
  if (rest.len == 0 || !ms_ascii_is_ident_start(rest.ptr[0])) {
    return false;
  }
  MsSpan after = partial_trim_start(ms_span_of(rest.ptr + identifier_length(rest),
                                               rest.len - identifier_length(rest)));
  return after.len != 0 && (after.ptr[0] == '(' || after.ptr[0] == '[');
}

static bool opaque_start(MsSpan source) {
  MsSpan rest = {0};
  MsSpan unused = {0};
  if (!after_keyword(source, "opaque", &rest)) {
    return false;
  }
  rest = partial_trim_start(rest);
  return after_keyword(rest, "type", &unused) || after_keyword(rest, "enum", &unused);
}

bool partial_root_start(MsSpan source) {
  static const char *const keywords[] = {"import", "export", "extern",    "type",
                                         "enum",   "interface", "impl", "test"};
  MsSpan rest = {0};
  for (size_t i = 0; i < sizeof keywords / sizeof keywords[0]; i++) {
    if (after_keyword(source, keywords[i], &rest)) {
      return true;
    }
  }
  if (constant_start(source) || function_start(source) || opaque_start(source)) {
    return true;
  }
  if (after_keyword(source, "bench", &rest)) {
    rest = partial_trim_start(rest);
    return rest.len != 0 && rest.ptr[0] == '"';
  }
  return false;
}

bool partial_is_declaration_line(MsSpan line) {
  return partial_is_candidate_line(line) && partial_root_start(partial_trim(line));
}

bool partial_single_root(const MsModule *module) {
  bool has_root = false;
  uint32_t root = 0;
  for (uint32_t i = 0; i < module->nimports; i++) {
    uint32_t at = module->imports[i].pos.offset;
    if (has_root && root != at) {
      return false;
    }
    has_root = true;
    root = at;
  }
  for (uint32_t i = 0; i < module->ndecls; i++) {
    uint32_t at = module->decls[i]->pos.offset;
    if (has_root && root != at) {
      return false;
    }
    has_root = true;
    root = at;
  }
  return has_root;
}

static bool split_name(MsSpan fields, MsSpan *name) {
  MsSpan rest = partial_trim_start(fields);
  size_t at = 0;
  while (at < rest.len && !is_space(rest.ptr[at])) {
    at++;
  }
  MsSpan keyword = ms_span_of(rest.ptr, at);
  if (!ms_span_is_text(keyword, "fn") && !ms_span_is_text(keyword, "type") && !ms_span_is_text(keyword, "enum") &&
      !ms_span_is_text(keyword, "interface")) {
    return false;
  }
  rest = partial_trim_start(ms_span_of(rest.ptr + at, rest.len - at));
  size_t end = 0;
  while (end < rest.len && !is_space(rest.ptr[end])) {
    end++;
  }
  /* The first non-empty piece of the second field, split at `(`, `[` or `:`. */
  size_t from = 0;
  while (from < end && (rest.ptr[from] == '(' || rest.ptr[from] == '[' || rest.ptr[from] == ':')) {
    from++;
  }
  size_t to = from;
  while (to < end && rest.ptr[to] != '(' && rest.ptr[to] != '[' && rest.ptr[to] != ':') {
    to++;
  }
  if (end == 0 || from == end) {
    return false;
  }
  *name = ms_span_of(rest.ptr + from, to - from);
  return true;
}

bool partial_declared_name(MsSpan chunk, MsSpan *name) {
  size_t at = 0;
  while (at <= chunk.len) {
    size_t end = at;
    while (end < chunk.len && chunk.ptr[end] != '\n') {
      end++;
    }
    MsSpan line = partial_trim(ms_span_of(chunk.ptr + at, end - at));
    at = end + 1;
    if (line.len == 0 || ms_span_starts_with_text(line, "//")) {
      continue;
    }
    MsSpan rest = line;
    if (ms_span_starts_with_text(rest, "export ")) {
      rest = ms_span_of(rest.ptr + 7, rest.len - 7);
    }
    if (ms_span_starts_with_text(rest, "opaque ")) {
      rest = ms_span_of(rest.ptr + 7, rest.len - 7);
    }
    return split_name(rest, name);
  }
  return false;
}

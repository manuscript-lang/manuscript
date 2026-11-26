/* Owns decl_header.h. */
#include "tooling/decl_header.h"

#include "base/message.h"
#include "base/strbuild.h"
#include "compiler/syntax/format.h"

static bool is_word_byte(uint8_t c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
}

/* Whether `fn` stands as a word in `text`. */
static bool has_fn_word(MsSpan text) {
  for (size_t i = 0; i + 1 < text.len; i++) {
    if (text.ptr[i] != 'f' || text.ptr[i + 1] != 'n') continue;
    if (i > 0 && is_word_byte(text.ptr[i - 1])) continue;
    if (i + 2 < text.len && is_word_byte(text.ptr[i + 2])) continue;
    return true;
  }
  return false;
}

/* Where the header ends: the body's `{` or `...`, or the end of the line, outside brackets and strings. */
static size_t header_end(MsSpan source, size_t from) {
  int depth = 0;
  for (size_t i = from; i < source.len; i++) {
    const uint8_t c = source.ptr[i];
    if (c == '"') {
      for (i++; i < source.len && source.ptr[i] != '"' && source.ptr[i] != '\n'; i++) {
        if (source.ptr[i] == '\\') i++;
      }
    } else if (c == '(' || c == '[') {
      depth++;
    } else if (c == ')' || c == ']') {
      if (depth > 0) depth--;
    } else if (depth == 0 && (c == '{' || c == '\n')) {
      return i;
    } else if (depth == 0 && c == '.' && i + 2 < source.len && source.ptr[i + 1] == '.' && source.ptr[i + 2] == '.') {
      return i;
    }
  }
  return source.len;
}

static MsSpan trim(MsSpan s) {
  size_t from = 0;
  size_t to = s.len;
  while (from < to && (s.ptr[from] == ' ' || s.ptr[from] == '\t' || s.ptr[from] == '\r' || s.ptr[from] == '\n')) from++;
  while (to > from && (s.ptr[to - 1] == ' ' || s.ptr[to - 1] == '\t' || s.ptr[to - 1] == '\r' || s.ptr[to - 1] == '\n')) to--;
  return ms_span_of(s.ptr + from, to - from);
}

/* The header laid out by the formatter: wrapped in an empty body so it parses as a declaration. A header with no body
 * (an interface operation) is not a module, so it keeps its source words. */
static MsSpan formatted(MsArena *arena, MsSpan header) {
  MsStrBuild wrapped = ms_strbuild_new();
  ms_strbuild_append(&wrapped, header);
  ms_strbuild_append_text(&wrapped, " {\n}\n");
  MsStrBuild out = ms_strbuild_new();
  MsDiag diag = {0};
  MsSpan result = header;
  if (ms_format(arena, ms_strbuild_span(&wrapped), &out, &diag)) {
    MsSpan text = trim(ms_strbuild_span(&out));
    while (text.len > 0 && text.ptr[text.len - 1] != '{') text.len--;
    if (text.len > 0) {
      text.len--;
      result = trim(text);
    }
  }
  const MsSpan kept = ms_arena_copy(arena, result);
  ms_strbuild_free(&wrapped);
  ms_strbuild_free(&out);
  return kept;
}

/* The written header of the function declared on the line holding `offset`, and where `offset` falls in it. Empty when the
 * line declares no function. */
static MsSpan raw_header(MsSpan source, size_t offset, size_t *rel) {
  if (offset > source.len) return ms_span_of(NULL, 0);
  size_t start = offset;
  while (start > 0 && source.ptr[start - 1] != '\n') start--;
  while (start < offset && (source.ptr[start] == ' ' || source.ptr[start] == '\t')) start++;
  if (!has_fn_word(ms_span_of(source.ptr + start, offset - start))) return ms_span_of(NULL, 0);
  const size_t end = header_end(source, offset);
  const MsSpan raw = ms_span_of(source.ptr + start, end - start);
  *rel = offset - start;
  return raw;
}

MsSpan ms_declaration_header(MsArena *arena, MsSpan source, size_t offset) {
  size_t rel;
  const MsSpan raw = raw_header(source, offset, &rel);
  return raw.len == 0 ? raw : formatted(arena, trim(raw));
}

static bool is_modifier(MsSpan word) {
  return ms_span_is_text(word, "move") || ms_span_is_text(word, "var") || ms_span_is_text(word, "hold");
}

/* The written type of one parameter `segment` (`move name Type = default`): its start and end, or false when it has none. */
static bool parameter_type(MsSpan segment, size_t *from, size_t *to) {
  size_t at = 0;
  for (;;) {
    while (at < segment.len && segment.ptr[at] == ' ') at++;
    size_t word_end = at;
    while (word_end < segment.len && segment.ptr[word_end] != ' ') word_end++;
    if (word_end == at) return false;
    if (!is_modifier(ms_span_of(segment.ptr + at, word_end - at))) {
      at = word_end; /* past the name */
      break;
    }
    at = word_end;
  }
  while (at < segment.len && segment.ptr[at] == ' ') at++;
  if (at >= segment.len || segment.ptr[at] == '=') return false;
  size_t end = segment.len;
  int depth = 0;
  for (size_t i = at; i < segment.len; i++) {
    const uint8_t c = segment.ptr[i];
    depth += (c == '(' || c == '[') - (c == ')' || c == ']');
    if (depth == 0 && c == '=') {
      end = i;
      break;
    }
  }
  while (end > at && segment.ptr[end - 1] == ' ') end--;
  *from = at;
  *to = end;
  return end > at;
}

/* The written header with `types` in place of its parameter and result types. */
static void substitute(MsStrBuild *out, MsSpan raw, size_t rel, MsSpan name, const MsSigTypes *types) {
  size_t open = rel + name.len;
  while (open < raw.len && raw.ptr[open] != '(') {
    if (raw.ptr[open] == '[') {
      int depth = 0;
      for (; open < raw.len; open++) {
        depth += (raw.ptr[open] == '[') - (raw.ptr[open] == ']');
        if (depth == 0) break;
      }
    }
    open++;
  }
  if (open >= raw.len) {
    ms_strbuild_append(out, raw);
    return;
  }
  ms_strbuild_append(out, ms_span_of(raw.ptr, open + 1));
  size_t at = open + 1;
  size_t index = 0;
  int depth = 0;
  size_t segment_start = at;
  for (; at <= raw.len; at++) {
    const uint8_t c = at < raw.len ? raw.ptr[at] : ')';
    if (c == '(' || c == '[') depth++;
    const bool close = c == ')' && depth == 0;
    if (c == ')' || c == ']') depth--;
    if (!close && !(c == ',' && depth == 0)) continue;
    const MsSpan segment = ms_span_of(raw.ptr + segment_start, at - segment_start);
    size_t from, to;
    if (index < types->count && types->params[index].len > 0 && parameter_type(segment, &from, &to)) {
      ms_strbuild_append(out, ms_span_of(segment.ptr, from));
      ms_strbuild_append(out, types->params[index]);
      ms_strbuild_append(out, ms_span_of(segment.ptr + to, segment.len - to));
    } else {
      ms_strbuild_append(out, segment);
    }
    index++;
    if (close) break;
    ms_strbuild_append_byte(out, ',');
    segment_start = at + 1;
  }
  ms_strbuild_append_byte(out, ')');
  MsSpan rest = trim(ms_span_of(raw.ptr + at + 1, at + 1 < raw.len ? raw.len - at - 1 : 0));
  ms_strbuild_append_byte(out, ' ');
  if (types->result.len > 0 && rest.len > 0) {
    if (rest.ptr[0] == '&') ms_strbuild_append_byte(out, '&');
    ms_strbuild_append(out, types->result);
  } else {
    ms_strbuild_append(out, rest);
  }
}

MsSpan ms_declaration_signature(MsArena *arena, MsSpan source, size_t offset, MsSpan name, const MsSigTypes *types) {
  size_t rel;
  const MsSpan raw = raw_header(source, offset, &rel);
  if (raw.len == 0) return raw;
  MsStrBuild written = ms_strbuild_new();
  if (types != NULL) {
    substitute(&written, raw, rel, name, types);
  } else {
    ms_strbuild_append(&written, raw);
  }
  const MsSpan header = formatted(arena, trim(ms_strbuild_span(&written)));
  ms_strbuild_free(&written);
  /* From the parameter list on: past the name and any type parameters. */
  for (size_t i = 0; i + name.len < header.len; i++) {
    if (!ms_span_equal(ms_span_of(header.ptr + i, name.len), name) || (i > 0 && header.ptr[i - 1] != ' ' && header.ptr[i - 1] != '.')) continue;
    const size_t at = i + name.len;
    if (at < header.len && (header.ptr[at] == '(' || header.ptr[at] == '[')) return ms_span_of(header.ptr + at, header.len - at);
  }
  return ms_span_of(NULL, 0);
}

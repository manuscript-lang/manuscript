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

MsSpan ms_declaration_header(MsArena *arena, MsSpan source, size_t offset) {
  if (offset > source.len) return ms_span_of(NULL, 0);
  size_t start = offset;
  while (start > 0 && source.ptr[start - 1] != '\n') start--;
  while (start < offset && (source.ptr[start] == ' ' || source.ptr[start] == '\t')) start++;
  if (!has_fn_word(ms_span_of(source.ptr + start, offset - start))) return ms_span_of(NULL, 0);
  const size_t end = header_end(source, offset);
  return formatted(arena, trim(ms_span_of(source.ptr + start, end - start)));
}

/* Owns the lexical rules of lint.h: trailing whitespace (MSL001), a missing final newline (MSL002) and a `//` that
 * reads like floor division (MSL133). */
#include "base/chars.h"
#include "compiler/syntax/lex.h"
#include "tooling/lint.h"

/* The tokens of a file, lexed once and only when a candidate finding needs them. */
typedef struct Tokens {
  MsArena *arena;
  MsSpan source;
  bool lexed, ok;
  MsLexed lex;
} Tokens;

/* Whether byte `at` is outside any text literal, by the lexer; an unlexable file reports false. */
static bool outside_text(Tokens *tokens, size_t at) {
  if (!tokens->lexed) {
    MsDiag diag = {0};
    tokens->ok = ms_lex(tokens->arena, tokens->source, &tokens->lex, &diag);
    tokens->lexed = true;
  }
  if (!tokens->ok) {
    return false;
  }
  size_t low = 0;
  size_t high = tokens->lex.ntokens;
  while (low < high) {
    const size_t middle = low + (high - low) / 2;
    if (tokens->lex.tokens[middle].end.offset <= at) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  if (low == tokens->lex.ntokens) {
    return true;
  }
  const MsToken *next = &tokens->lex.tokens[low];
  return !(next->kind == MS_T_String && next->pos.offset <= at);
}

static bool is_ascii_digit(uint8_t byte) {
  return byte >= '0' && byte <= '9';
}

static bool is_ascii_alnum(uint8_t byte) {
  return is_ascii_digit(byte) || (byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z');
}

static bool is_ascii_alpha(uint8_t byte) {
  return is_ascii_alnum(byte) && !is_ascii_digit(byte);
}

/* `line` with trailing spaces and tabs cut. */
static size_t trim_end(MsSpan line, size_t end) {
  while (end > 0 && ms_ascii_is_blank(line.ptr[end - 1])) {
    end--;
  }
  return end;
}

/* Whether the `//` at byte `slash` of `line` ends an expression and holds only a number: `mid := (lo + hi) // 2`,
 * a Python floor division that compiles as `(lo + hi)`. */
static bool floor_division_shape(MsSpan line, size_t slash) {
  const size_t before = trim_end(line, slash);
  const bool operand_end =
      before > 0 && (is_ascii_alnum(line.ptr[before - 1]) || line.ptr[before - 1] == ')' ||
                     line.ptr[before - 1] == ']' || line.ptr[before - 1] == '_');
  /* The comment: what follows `//`, trimmed, without trailing brackets. */
  size_t start = slash + 2;
  size_t stop = line.len;
  while (start < stop && (ms_ascii_is_blank(line.ptr[start]) || line.ptr[start] == '\r')) {
    start++;
  }
  while (stop > start && (ms_ascii_is_blank(line.ptr[stop - 1]) || line.ptr[stop - 1] == '\r')) {
    stop--;
  }
  while (stop > start && (line.ptr[stop - 1] == ')' || line.ptr[stop - 1] == ']')) {
    stop--;
  }
  /* `total := 1 + 2 * 3 // 7` annotates a result: the expression is all literals. */
  size_t expression = before;
  while (expression > 0 && line.ptr[expression - 1] != '=' && line.ptr[expression - 1] != ':') {
    expression--;
  }
  bool names_a_value = false;
  for (size_t i = expression; i < before; i++) {
    names_a_value = names_a_value || is_ascii_alpha(line.ptr[i]) || line.ptr[i] == '_';
  }
  if (!operand_end || !names_a_value || start >= stop || !is_ascii_digit(line.ptr[start])) {
    return false;
  }
  for (size_t i = start; i < stop; i++) {
    if (!is_ascii_digit(line.ptr[i]) && line.ptr[i] != '.') {
      return false;
    }
  }
  return true;
}

static bool find_slashes(MsSpan body, size_t *slash) {
  for (size_t i = 0; i + 1 < body.len; i++) {
    if (body.ptr[i] == '/' && body.ptr[i + 1] == '/') {
      *slash = i;
      return true;
    }
  }
  return false;
}

void ms_lint_source(MsArena *arena, MsSpan file, MsSpan source, MsLintFindingList *findings) {
  Tokens tokens = {.arena = arena, .source = source};
  size_t offset = 0;
  uint32_t line = 0;
  while (offset < source.len) {
    size_t end = offset;
    while (end < source.len && source.ptr[end] != '\n') {
      end++;
    }
    const size_t next = end < source.len ? end + 1 : end;
    line++;
    MsSpan body = ms_span_of(source.ptr + offset, end - offset);
    if (body.len > 0 && body.ptr[body.len - 1] == '\r') {
      body.len--;
    }
    const size_t trimmed = trim_end(body, body.len);
    if (trimmed != body.len && outside_text(&tokens, offset + trimmed)) {
      ms_lint_add(findings, "MSL001", file, (MsPos){(uint32_t)(offset + trimmed), line, (uint32_t)trimmed + 1},
                  ms_span_of_text("Remove trailing whitespace"));
    }
    size_t slash = 0;
    if (find_slashes(body, &slash) && floor_division_shape(body, slash) && outside_text(&tokens, offset + slash)) {
      ms_lint_add(findings, "MSL133", file, (MsPos){(uint32_t)(offset + slash), line, (uint32_t)slash + 1},
                  ms_span_of_text("`//` starts a comment, so everything after it is ignored; Int `/` already "
                                  "truncates, so write `a / 2` for a floor division"));
    }
    offset = next;
  }
  if (source.len > 0 && source.ptr[source.len - 1] != '\n') {
    uint32_t newlines = 0;
    size_t last = source.len;
    for (size_t i = 0; i < source.len; i++) {
      if (source.ptr[i] == '\n') {
        newlines++;
        last = i;
      }
    }
    const uint32_t column = newlines == 0 ? (uint32_t)source.len + 1 : (uint32_t)(source.len - last);
    ms_lint_add(findings, "MSL002", file, (MsPos){(uint32_t)source.len, newlines + 1, column},
                ms_span_of_text("End the file with a newline"));
  }
}

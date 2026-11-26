/* lsp/lsp_text.c: UTF-16 positions and the forgiving token scanner behind diagnostic ranges. Text may be malformed: an invalid byte counts as one UTF-16 unit. */
#include <string.h>

#include "base/alloc.h"
#include "base/utf8.h"
#include "lsp/lsp_internal.h"
#include "tooling/decl_header.h"

static bool is_identifier(uint8_t b) {
  return b == '_' || (b >= '0' && b <= '9') || (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z');
}

/* The UTF-16 width and byte size of the first rune of `bytes`; an invalid byte is one unit and one byte. */
static void rune_width(const uint8_t *bytes, size_t length, size_t *width, size_t *size) {
  const MsRune rune = ms_utf8_decode(bytes, length);
  *size = rune.width;
  *width = (rune.rune == MS_RUNE_ERROR && rune.width == 1) ? 1 : (rune.rune >= 0x10000 ? 2 : 1);
}

static size_t lsp_utf16_length(MsSpan bytes) {
  size_t length = 0;
  for (size_t at = 0; at < bytes.len;) {
    size_t width, size;
    rune_width(bytes.ptr + at, bytes.len - at, &width, &size);
    length += width;
    at += size;
  }
  return length;
}

LspPosition lsp_position(MsSpan source, size_t offset) {
  if (offset > source.len) offset = source.len;
  size_t line = 0, start = 0;
  for (size_t i = 0; i < offset; i++) {
    if (source.ptr[i] == '\n') {
      line++;
      start = i + 1;
    }
  }
  return (LspPosition){line, lsp_utf16_length(ms_span_of(source.ptr + start, offset - start))};
}

void lsp_lines_init(LspLines *lines, MsSpan source) {
  size_t count = 1;
  for (size_t i = 0; i < source.len; i++) {
    count += source.ptr[i] == '\n' ? 1u : 0u;
  }
  lines->source = source;
  lines->count = count;
  lines->starts = ms_alloc(sizeof(size_t) * count);
  size_t line = 1;
  lines->starts[0] = 0;
  for (size_t i = 0; i < source.len; i++) {
    if (source.ptr[i] == '\n') {
      lines->starts[line++] = i + 1;
    }
  }
}

void lsp_lines_free(LspLines *lines) {
  ms_free(lines->starts);
  *lines = (LspLines){0};
}

LspPosition lsp_lines_position(const LspLines *lines, size_t offset) {
  if (offset > lines->source.len) offset = lines->source.len;
  size_t low = 0, high = lines->count; /* the last line starting at or before the offset */
  while (high - low > 1) {
    const size_t mid = low + (high - low) / 2;
    if (lines->starts[mid] <= offset) low = mid;
    else high = mid;
  }
  const size_t start = lines->starts[low];
  return (LspPosition){low, lsp_utf16_length(ms_span_of(lines->source.ptr + start, offset - start))};
}

bool lsp_offset(MsSpan source, LspPosition position, bool clamp, size_t *offset) {
  size_t at = 0;
  for (size_t line = 0; line < position.line; line++) {
    const uint8_t *newline = at < source.len ? memchr(source.ptr + at, '\n', source.len - at) : NULL;
    if (newline == NULL) {
      if (!clamp) return false;
      *offset = source.len;
      return true;
    }
    at = (size_t)(newline - source.ptr) + 1;
  }
  size_t column = 0;
  while (at < source.len && source.ptr[at] != '\n' && source.ptr[at] != '\r') {
    if (column == position.character) {
      *offset = at;
      return true;
    }
    size_t width, size;
    rune_width(source.ptr + at, source.len - at, &width, &size);
    column += width;
    at += size;
    if (column > position.character) return false;
  }
  if (column != position.character && !clamp) return false;
  *offset = at;
  return true;
}

static bool starts(MsSpan source, size_t at, const char *text) {
  return ms_span_starts_with_text(ms_span_of(source.ptr + at, source.len - at), text);
}

static size_t find(MsSpan source, size_t from, const char *needle) {
  size_t at;
  if (!ms_span_find(ms_span_of(source.ptr + from, source.len - from), ms_span_of_text(needle), &at)) return source.len;
  return from + at;
}

/* The tokens of `source`, forgiving of anything that does not lex. */
void lsp_scan_tokens(MsSpan source, LspTokenList *tokens) {
  size_t at = 0;
  while (at < source.len) {
    const size_t start = at;
    const uint8_t b = source.ptr[at];
    if (b == ' ' || b == '\r' || b == '\t') {
      at++;
    } else if (starts(source, at, "//")) {
      while (at < source.len && source.ptr[at] != '\n') at++;
      lsp_token_list_push(tokens, (LspEditorToken){LSP_TOKEN_COMMENT, start, at});
    } else if (starts(source, at, "/*")) {
      /* One token per line, so clients that do not take multi-line tokens still color it. */
      const size_t found = find(source, at + 2, "*/");
      const size_t close = found == source.len ? source.len : found + 2;
      size_t line = at;
      while (line < close) {
        size_t end = line;
        while (end < close && source.ptr[end] != '\n') end++;
        if (end > line) lsp_token_list_push(tokens, (LspEditorToken){LSP_TOKEN_COMMENT, line, end});
        line = end + 1;
      }
      at = close;
    } else if (starts(source, at, "\"\"\"") || starts(source, at, "r\"\"\"") || starts(source, at, "f\"\"\"")) {
      at += source.ptr[at] == '"' ? 3 : 4;
      const size_t found = find(source, at, "\"\"\"");
      at = found == source.len ? source.len : found + 3;
      lsp_token_list_push(tokens, (LspEditorToken){LSP_TOKEN_STRING, start, at});
    } else if (b == '"' || starts(source, at, "f\"")) {
      at += b == '"' ? 1 : 2;
      while (at < source.len) {
        if (source.ptr[at] == '\\') {
          at += at + 1 < source.len ? 2 : 1;
        } else if (source.ptr[at++] == '"') {
          break;
        }
      }
      lsp_token_list_push(tokens, (LspEditorToken){LSP_TOKEN_STRING, start, at});
    } else if (is_identifier(b)) {
      while (at < source.len && is_identifier(source.ptr[at])) at++;
      lsp_token_list_push(tokens, (LspEditorToken){LSP_TOKEN_NAME, start, at});
    } else {
      size_t width, size;
      rune_width(source.ptr + at, source.len - at, &width, &size);
      at += size;
      lsp_token_list_push(tokens, (LspEditorToken){LSP_TOKEN_CHAR, start, at});
    }
  }
}

bool lsp_literal_closed(MsSpan source, const LspEditorToken *token) {
  size_t open = 1;
  if (source.ptr[token->start] == 'r' || source.ptr[token->start] == 'f') open = 2;
  const size_t length = token->end - token->start;
  const bool triple = length >= open + 2 && source.ptr[token->start + open] == '"' && source.ptr[token->start + open + 1] == '"' &&
                      (open == 1 || source.ptr[token->start + open - 1] == '"');
  if (source.ptr[token->start] == '"' && length >= 3 && source.ptr[token->start + 1] == '"' && source.ptr[token->start + 2] == '"') {
    return length >= 6 && source.ptr[token->end - 1] == '"' && source.ptr[token->end - 2] == '"' && source.ptr[token->end - 3] == '"';
  }
  if (triple || (open == 2 && length >= 4 && source.ptr[token->start + 2] == '"' && source.ptr[token->start + 3] == '"')) {
    return length >= 7 && source.ptr[token->end - 1] == '"' && source.ptr[token->end - 2] == '"' && source.ptr[token->end - 3] == '"';
  }
  if (length < open + 1 || source.ptr[token->end - 1] != '"') return false;
  size_t slashes = 0;
  while (token->end - 2 - slashes > token->start + open - 1 && source.ptr[token->end - 2 - slashes] == '\\') slashes++;
  return slashes % 2 == 0;
}

/* Where a diagnostic at `offset` inside `token` ends. A text literal is one token, but a diagnostic inside its
 * interpolation (`{name}`) covers only the name there, not the rest of the literal. */
static size_t diagnostic_end(MsSpan source, const LspEditorToken *token, size_t offset) {
  if (token->kind != LSP_TOKEN_STRING || offset == token->start) return token->end;
  size_t name = 0;
  while (offset + name < token->end && is_identifier(source.ptr[offset + name])) name++;
  return name == 0 ? token->end : offset + name;
}

LspRange lsp_diagnostic_range(MsSpan source, size_t offset) {
  const LspPosition start = lsp_position(source, offset);
  LspRange range = {start, start};
  LspTokenList tokens = {0};
  lsp_scan_tokens(source, &tokens);
  for (size_t i = 0; i < tokens.len; i++) {
    const LspEditorToken *token = &tokens.ptr[i];
    if (offset >= token->start && offset < token->end) {
      range.end = lsp_position(source, diagnostic_end(source, token, offset));
      break;
    }
  }
  lsp_token_list_free(&tokens);
  return range;
}

bool lsp_header(MsSpan source, size_t offset, MsSpan name, size_t *at) {
  if (offset > source.len || name.len == 0) return false;
  size_t start = offset;
  if (starts(source, start, "\r\n")) start += 2;
  else if (starts(source, start, "\n")) start += 1;
  size_t end = start;
  while (end < source.len && source.ptr[end] != '\n') end++;
  const MsSpan line = ms_span_of(source.ptr + start, end - start);
  LspTokenList tokens = {0};
  lsp_scan_tokens(line, &tokens);
  bool found = false;
  for (size_t i = 0; i < tokens.len && !found; i++) {
    const LspEditorToken *token = &tokens.ptr[i];
    if (token->kind == LSP_TOKEN_NAME && ms_span_equal(ms_span_of(line.ptr + token->start, token->end - token->start), name)) {
      *at = start + token->start;
      found = true;
    }
  }
  lsp_token_list_free(&tokens);
  return found;
}

bool lsp_line_opens_suite(MsSpan line) {
  LspTokenList tokens = {0};
  lsp_scan_tokens(line, &tokens);
  bool opens = false;
  for (size_t i = tokens.len; i > 0; i--) {
    const LspEditorToken *token = &tokens.ptr[i - 1];
    if (token->kind == LSP_TOKEN_COMMENT) continue;
    opens = token->kind == LSP_TOKEN_CHAR && line.ptr[token->start] == '{';
    break;
  }
  lsp_token_list_free(&tokens);
  return opens;
}

bool lsp_function_detail(MsArena *arena, MsStrBuild *detail, MsSpan source, size_t offset, MsSpan name) {
  size_t at;
  if (name.len == 0 || !lsp_header(source, offset, name, &at)) return false;
  const MsSpan signature = ms_declaration_signature(arena, source, at, name, NULL);
  ms_strbuild_append(detail, signature);
  return signature.len > 0;
}

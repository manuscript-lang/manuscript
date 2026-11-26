/* Owns statement recovery: a failed declaration retried with its offending statements blanked. */
#include "compiler/syntax/partial_internal.h"

enum { MAX_ATTEMPTS = 8, MAX_TRIMS = 3 };

typedef struct Buffer {
  uint8_t *text;   /* the chunk, edited in place; line breaks never move */
  size_t length;
  MsSpanMut *lines; /* each physical line, including its break, as spans of `text` */
  size_t nlines;
} Buffer;

static Buffer buffer_of(Partial *partial, MsSpan chunk) {
  Buffer buffer = {.text = ms_arena_alloc(partial->arena, chunk.len + 1, 1), .length = chunk.len};
  if (chunk.len != 0) {
    __builtin_memcpy(buffer.text, chunk.ptr, chunk.len);
  }
  size_t count = 0;
  for (size_t i = 0; i < chunk.len; i++) {
    count += chunk.ptr[i] == '\n';
  }
  buffer.lines = MS_ARENA_NEW_ARRAY(partial->arena, MsSpanMut, count + 1);
  size_t start = 0;
  for (size_t i = 0; i < chunk.len; i++) {
    if (buffer.text[i] == '\n') {
      buffer.lines[buffer.nlines++] = ms_span_mut_of(buffer.text + start, i + 1 - start);
      start = i + 1;
    }
  }
  if (start < chunk.len) {
    buffer.lines[buffer.nlines++] = ms_span_mut_of(buffer.text + start, chunk.len - start);
  }
  return buffer;
}

static MsSpan buffer_span(const Buffer *buffer) {
  return ms_span_of(buffer->text, buffer->length);
}

/* Replaces every byte but line breaks with a space, keeping offsets. */
static void blank(MsSpanMut line) {
  uint8_t *bytes = line.ptr;
  for (size_t i = 0; i < line.len; i++) {
    if (bytes[i] != '\r' && bytes[i] != '\n') {
      bytes[i] = ' ';
    }
  }
}

static bool parse_ok(Partial *partial, MsSpan text, MsChunk where, MsDiag *error) {
  MsModule module;
  return ms_parse_chunk(partial->arena, partial->names, text, where, &module, error);
}

static bool is_dangling(uint8_t c) {
  return c == '.' || c == '?' || c == '+' || c == '-' || c == '*' || c == '/' || c == '%' || c == '<' ||
         c == '>' || c == '=' || c == '!' || c == ',' || c == '|' || c == ' ';
}

/* Drops a trailing `and`, `or` or `not` word that follows a space. */
static size_t without_word(const uint8_t *code, size_t length) {
  static const char *const words[] = {"and", "or", "not"};
  for (size_t i = 0; i < 3; i++) {
    size_t n = __builtin_strlen(words[i]);
    if (length > n && __builtin_memcmp(code + length - n, words[i], n) == 0 && code[length - n - 1] == ' ') {
      return length - n;
    }
  }
  return length;
}

/* The column-preserving line `code` padded to `width`, then the line break. */
static void set_line(MsSpanMut line, const uint8_t *code, size_t code_length, size_t width) {
  uint8_t *bytes = line.ptr;
  __builtin_memcpy(bytes, code, code_length);
  for (size_t i = code_length; i < width; i++) {
    bytes[i] = ' ';
  }
}

/* Removes the dangling tail of line `at` (a trailing `.`, `?.`, operator or separator) until the declaration
 * parses, keeping the line's columns by padding with spaces. */
static bool trim_dangling(Partial *partial, const Buffer *buffer, size_t at, MsSpan *out) {
  MsSpan line = ms_span_view(buffer->lines[at]);
  size_t width = line.len;
  while (width > 0 && (line.ptr[width - 1] == '\n' || line.ptr[width - 1] == '\r')) {
    width--;
  }
  size_t length = partial_trim_end(ms_span_of(line.ptr, width)).len;
  for (size_t i = 0; i < length; i++) {
    if (line.ptr[i] == '"' || (line.ptr[i] == '/' && i + 1 < length && line.ptr[i + 1] == '/')) {
      return false;
    }
  }
  uint8_t *code = ms_arena_alloc(partial->arena, line.len + 1, 1);
  __builtin_memcpy(code, line.ptr, length);
  for (int attempt = 0; attempt < MAX_TRIMS; attempt++) {
    size_t kept = length;
    while (kept > 0 && is_dangling(code[kept - 1])) {
      kept--;
    }
    kept = without_word(code, kept);
    if (kept == length || partial_trim(ms_span_of(code, kept)).len == 0) {
      return false;
    }
    length = partial_trim_end(ms_span_of(code, kept)).len;
    Buffer trial = buffer_of(partial, buffer_span(buffer));
    set_line(trial.lines[at], code, length, width);
    MsDiag error = {0};
    if (parse_ok(partial, buffer_span(&trial), (MsChunk){0}, &error)) {
      *out = buffer_span(&trial);
      return true;
    }
  }
  return false;
}

static bool is_blank(MsSpan line) {
  return partial_trim(line).len == 0;
}

/* The line to drop for `issue`, 1-based within the chunk. */
static size_t offending_line(const Buffer *buffer, const MsDiag *issue, MsChunk where, int attempt) {
  size_t line = issue->pos.line > where.base_line ? issue->pos.line - where.base_line : 0;
  size_t opened = issue->opener_line > where.base_line ? issue->opener_line - where.base_line : 0;
  /* An unterminated delimiter is reported at the end of the chunk; the statement to drop is the one that
   * opened it. Only the first failure is redirected: a delimiter left open by an earlier blanking is a
   * cascade, and the declaration is omitted rather than reported twice. */
  if (opened > 0 && attempt == 0) {
    line = opened;
  }
  /* A misindented line of multi-line text drops the whole statement. */
  if (attempt == 0 && ms_span_starts_with_text(issue->message, "text line is indented less")) {
    while (line > 1 && line <= buffer->nlines &&
           !ms_span_ends_with_text(partial_trim_end(ms_span_view(buffer->lines[line - 1])), "\"\"\"")) {
      line--;
    }
  }
  return line;
}

/* Whether the statement at `at` stands alone: the next non-blank line is not indented deeper. */
static bool is_single_statement(const Buffer *buffer, size_t at, size_t indent) {
  for (size_t i = at + 1; i < buffer->nlines; i++) {
    if (!is_blank(ms_span_view(buffer->lines[i]))) {
      return partial_leading_space(ms_span_view(buffer->lines[i])) <= indent;
    }
  }
  return true;
}

static void blank_statement(const Buffer *buffer, size_t at, size_t indent) {
  for (size_t i = at; i < buffer->nlines; i++) {
    if (i > at && !is_blank(ms_span_view(buffer->lines[i])) && partial_leading_space(ms_span_view(buffer->lines[i])) <= indent) {
      return;
    }
    blank(buffer->lines[i]);
  }
}

/* Writes `...` at `indent` on a blanked line when it is long enough to hold it. */
static bool stand_in(MsSpanMut line, size_t indent) {
  size_t room = line.len;
  while (room > 0 && (line.ptr[room - 1] == '\n' || line.ptr[room - 1] == '\r')) {
    room--;
  }
  if (room < indent + 3) {
    return false;
  }
  __builtin_memcpy(line.ptr + indent, "...", 3);
  return true;
}

bool partial_recover_statements(Partial *partial, MsSpan chunk, MsChunk where, const MsDiag *first, MsSpan *out,
                                DiagList *issues) {
  Buffer buffer = buffer_of(partial, chunk);
  MsDiag issue = *first;
  for (int attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    size_t line = offending_line(&buffer, &issue, where, attempt);
    /* The header line (line 1) failing means the signature is unusable. */
    if (line < 2 || line > buffer.nlines) {
      return false;
    }
    diag_list_push(issues, issue);
    size_t at = line - 1;
    size_t indent = partial_leading_space(ms_span_view(buffer.lines[at]));
    if (is_blank(ms_span_view(buffer.lines[at])) || indent == 0) {
      return false;
    }
    /* A one-line statement cut off mid-expression (`return g.`, `let v = a +`) keeps its operands for
     * navigation once the dangling tail is trimmed. */
    if (is_single_statement(&buffer, at, indent) && trim_dangling(partial, &buffer, at, out)) {
      return true;
    }
    blank_statement(&buffer, at, indent);
    MsDiag error = {0};
    if (parse_ok(partial, buffer_span(&buffer), where, &error)) {
      *out = buffer_span(&buffer);
      return true;
    }
    /* Blanking the only statement leaves an empty block; `...` stands in so the declaration survives. */
    if (ms_span_starts_with_text(error.message, "a block cannot be empty") && stand_in(buffer.lines[at], indent)) {
      MsDiag again = {0};
      if (parse_ok(partial, buffer_span(&buffer), where, &again)) {
        *out = buffer_span(&buffer);
        return true;
      }
    }
    issue = error;
  }
  return false;
}

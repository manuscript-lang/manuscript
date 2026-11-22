/* compiler/check/effects_directives.c: reading effect directives out of comment lines. */
#include "compiler/check/effects_directives.h"
#include "base/chars.h"

void ms_directives_free(MsDirectives *directives) {
  ms_span_list_free(&directives->declared);
  ms_span_list_free(&directives->allow);
  ms_span_list_free(&directives->words);
}

static MsSpan trim(MsSpan text) {
  size_t start = 0;
  size_t end = text.len;
  while (start < end && ms_ascii_is_space(text.ptr[start])) {
    start++;
  }
  while (end > start && ms_ascii_is_space(text.ptr[end - 1])) {
    end--;
  }
  return ms_span_of(text.ptr + start, end - start);
}

static MsSpan after(MsSpan text, const char *prefix) {
  return ms_span_of(text.ptr + ms_span_of_text(prefix).len, text.len - ms_span_of_text(prefix).len);
}

/* Records the directive on one comment line, if it is one. */
static void read_line(MsDirectives *directives, MsSpan line) {
  const MsSpan text = trim(line);
  if (!ms_span_starts_with(text, ms_span_of_text("// ms:"))) {
    return;
  }
  const MsSpan rest = trim(after(text, "// ms:"));
  if (ms_span_starts_with(rest, ms_span_of_text("allow_effect "))) {
    ms_span_list_push(&directives->allow, trim(after(rest, "allow_effect ")));
    directives->has_allow = true;
  } else if (ms_span_starts_with(rest, ms_span_of_text("words "))) {
    ms_span_list_push(&directives->words, trim(after(rest, "words ")));
  } else if (ms_span_starts_with(rest, ms_span_of_text("effect "))) {
    ms_span_list_push(&directives->declared, trim(after(rest, "effect ")));
  }
}

/* The line starting at `at` without its newline (and CR); `next` is where the following line starts. */
static MsSpan line_at(MsSpan source, size_t at, size_t *next) {
  size_t end = at;
  while (end < source.len && source.ptr[end] != '\n') {
    end++;
  }
  *next = end < source.len ? end + 1 : source.len + 1;
  size_t length = end - at;
  if (length > 0 && source.ptr[at + length - 1] == '\r') {
    length--;
  }
  return ms_span_of(source.ptr + at, length);
}

static bool is_comment(MsSpan line) {
  return ms_span_starts_with(trim(line), ms_span_of_text("//"));
}

/* The offset just past the leading comment lines of the file, or 0 when the file does not start with one. */
static size_t comment_block_end(MsSpan source) {
  size_t at = 0;
  size_t next = 0;
  while (at <= source.len && is_comment(line_at(source, at, &next))) {
    at = next;
  }
  return at;
}

MsDirectives ms_directives_header(MsSpan source) {
  MsDirectives found = {0};
  const size_t end = comment_block_end(source);
  size_t next = 0;
  if (end == 0 || end > source.len || trim(line_at(source, end, &next)).len != 0) {
    return found;
  }
  for (size_t cursor = 0; cursor < end;) {
    read_line(&found, line_at(source, cursor, &next));
    cursor = next;
  }
  return found;
}

MsDirectives ms_directives_above(MsSpan source, uint32_t line) {
  MsDirectives found = {0};
  MsSpanList lines = {0};
  size_t next = 0;
  for (size_t cursor = 0; cursor <= source.len; cursor = next) {
    ms_span_list_push(&lines, line_at(source, cursor, &next));
  }
  size_t at = line > 0 ? line - 1 : 0;
  while (at > 0 && at <= lines.len && ms_span_starts_with(trim(lines.ptr[at - 1]), ms_span_of_text("//"))) {
    read_line(&found, lines.ptr[at - 1]);
    at--;
  }
  ms_span_list_free(&lines);
  return found;
}

bool ms_effect_matches(MsSpan pattern, MsSpan effect) {
  if (ms_span_is_text(pattern, "*")) {
    return true;
  }
  if (ms_span_ends_with(pattern, ms_span_of_text(".*"))) {
    const MsSpan prefix = ms_span_of(pattern.ptr, pattern.len - 2);
    return ms_span_starts_with(effect, prefix) && effect.len > prefix.len && effect.ptr[prefix.len] == '.';
  }
  if (ms_span_starts_with(pattern, ms_span_of_text("*."))) {
    const MsSpan suffix = ms_span_of(pattern.ptr + 2, pattern.len - 2);
    size_t dot = effect.len;
    while (dot > 0 && effect.ptr[dot - 1] != '.') {
      dot--;
    }
    return dot > 0 && ms_span_equal(ms_span_of(effect.ptr + dot, effect.len - dot), suffix);
  }
  return ms_span_equal(pattern, effect);
}

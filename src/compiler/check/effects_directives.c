/* compiler/check/effects_directives.c: reading effect directives out of comment lines. */
#include <stdint.h>
#include "compiler/check/effects_directives.h"
#include "base/chars.h"

void ms_directives_free(MsDirectives *directives) {
  ms_span_list_free(&directives->declared);
  ms_span_list_free(&directives->allow);
  ms_span_list_free(&directives->words);
}

static MsSpan after(MsSpan text, const char *prefix) {
  return ms_span_of(text.ptr + ms_span_of_text(prefix).len, text.len - ms_span_of_text(prefix).len);
}

/* Records the directive on one comment line, if it is one. */
static void read_line(MsDirectives *directives, MsSpan line) {
  const MsSpan text = ms_span_trim(line);
  if (!ms_span_starts_with(text, ms_span_of_text("// ms:"))) {
    return;
  }
  const MsSpan rest = ms_span_trim(after(text, "// ms:"));
  if (ms_span_starts_with(rest, ms_span_of_text("allow_effect "))) {
    ms_span_list_push(&directives->allow, ms_span_trim(after(rest, "allow_effect ")));
    directives->has_allow = true;
  } else if (ms_span_starts_with(rest, ms_span_of_text("words "))) {
    ms_span_list_push(&directives->words, ms_span_trim(after(rest, "words ")));
  } else if (ms_span_starts_with(rest, ms_span_of_text("effect "))) {
    ms_span_list_push(&directives->declared, ms_span_trim(after(rest, "effect ")));
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
  return ms_span_starts_with(ms_span_trim(line), ms_span_of_text("//"));
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
  if (end == 0 || end > source.len || ms_span_trim(line_at(source, end, &next)).len != 0) {
    return found;
  }
  for (size_t cursor = 0; cursor < end;) {
    read_line(&found, line_at(source, cursor, &next));
    cursor = next;
  }
  return found;
}

uint32_t *ms_line_starts(MsArena *arena, MsSpan source, uint32_t *count) {
  uint32_t lines = 1;
  for (size_t at = 0; at < source.len; at++) {
    lines += source.ptr[at] == '\n' ? 1u : 0u;
  }
  uint32_t *starts = MS_ARENA_NEW_ARRAY_UNINIT(arena, uint32_t, lines);
  uint32_t line = 1;
  starts[0] = 0;
  for (size_t at = 0; at < source.len; at++) {
    if (source.ptr[at] == '\n') {
      starts[line++] = (uint32_t)at + 1;
    }
  }
  *count = lines;
  return starts;
}

MsDirectives ms_directives_above(MsSpan source, const uint32_t *line_starts, uint32_t line_count, uint32_t line) {
  MsDirectives found = {0};
  const size_t above = line > 0 ? line - 1 : 0; /* the 0-based index of the line above the declaration, plus one */
  if (above == 0) {
    return found;
  }
  size_t start = above - 1 < line_count ? line_starts[above - 1] : SIZE_MAX;
  while (start != SIZE_MAX) {
    size_t next = 0;
    const MsSpan text = line_at(source, start, &next);
    if (!ms_span_starts_with(ms_span_trim(text), ms_span_of_text("//"))) {
      break;
    }
    read_line(&found, text);
    if (start == 0) {
      break;
    }
    start--; /* the newline that ends the line above */
    while (start > 0 && source.ptr[start - 1] != '\n') {
      start--;
    }
  }
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

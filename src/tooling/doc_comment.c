/* Owns doc_comment.h. */
#include "tooling/doc_comment.h"

#include "base/message.h"
#include "compiler/syntax/format.h"
#include "base/strbuild.h"

static bool is_blank_byte(uint8_t c) {
  return c == ' ' || c == '\t' || c == '\r' || c == '\n';
}

static MsSpan trim_start(MsSpan s) {
  size_t i = 0;
  while (i < s.len && is_blank_byte(s.ptr[i])) {
    i++;
  }
  return ms_span_of(s.ptr + i, s.len - i);
}

static MsSpan trim_end(MsSpan s) {
  size_t n = s.len;
  while (n > 0 && is_blank_byte(s.ptr[n - 1])) {
    n--;
  }
  return ms_span_of(s.ptr, n);
}

static MsSpan trim(MsSpan s) {
  return trim_start(trim_end(s));
}

static MsSpan drop_prefix(MsSpan s, size_t n) {
  return ms_span_of(s.ptr + n, s.len - n);
}

/* The lines above a position, nearest first, read from the end only as far as they are asked for. */
typedef struct Lines {
  MsArena *arena;
  MsSpans nearest;
  MsSpan rest;
  bool has_rest;
} Lines;

static void fill(Lines *lines, size_t upto) {
  while (lines->nearest.len <= upto && lines->has_rest) {
    size_t cut = lines->rest.len;
    while (cut > 0 && lines->rest.ptr[cut - 1] != '\n') {
      cut--;
    }
    if (cut == 0) {
      ms_spans_push(lines->arena, &lines->nearest, lines->rest);
      lines->has_rest = false;
    } else {
      ms_spans_push(lines->arena, &lines->nearest, ms_span_of(lines->rest.ptr + cut, lines->rest.len - cut));
      lines->rest = ms_span_of(lines->rest.ptr, cut - 1);
    }
  }
}

static MsSpan strip_cr(MsSpan line) {
  return line.len > 0 && line.ptr[line.len - 1] == '\r' ? ms_span_of(line.ptr, line.len - 1) : line;
}

/* The text of a block comment given as whole lines: markers removed, the common indentation of the interior lines removed,
 * and the blank lines next to the markers dropped. */
static MsSpan block_text(MsArena *arena, const MsSpan *lines, size_t count) {
  MsSpan first = trim_start(lines[0]);
  first = ms_span_starts_with(first, ms_span_of_text("/*")) ? drop_prefix(first, 2) : ms_span_of_text("");
  MsSpan last = strip_cr(trim_end(lines[count - 1]));
  last = ms_span_ends_with(last, ms_span_of_text("*/")) ? ms_span_of(last.ptr, last.len - 2) : last;
  if (count == 1) {
    MsSpan one = ms_span_ends_with(first, ms_span_of_text("*/")) ? ms_span_of(first.ptr, first.len - 2) : first;
    return ms_arena_copy(arena, trim(one));
  }
  MsSpans rows = {0};
  ms_spans_push(arena, &rows, trim_end(first));
  for (size_t i = 1; i + 1 < count; i++) {
    ms_spans_push(arena, &rows, trim_end(lines[i]));
  }
  ms_spans_push(arena, &rows, trim_end(last));
  size_t common = (size_t)-1;
  for (size_t i = 1; i < rows.len; i++) {
    if (trim(rows.ptr[i]).len == 0) {
      continue;
    }
    const size_t lead = rows.ptr[i].len - trim_start(rows.ptr[i]).len;
    common = lead < common ? lead : common;
  }
  if (common == (size_t)-1) {
    common = 0;
  }
  for (size_t i = 0; i < rows.len; i++) {
    rows.ptr[i] = i == 0 ? trim_start(rows.ptr[i]) : (common <= rows.ptr[i].len ? drop_prefix(rows.ptr[i], common) : ms_span_of_text(""));
  }
  size_t from = 0;
  size_t to = rows.len;
  while (from < to && trim(rows.ptr[from]).len == 0) {
    from++;
  }
  while (to > from && trim(rows.ptr[to - 1]).len == 0) {
    to--;
  }
  MsStrBuild out = ms_strbuild_new();
  for (size_t i = from; i < to; i++) {
    if (i > from) {
      ms_strbuild_append_byte(&out, '\n');
    }
    ms_strbuild_append(&out, rows.ptr[i]);
  }
  const MsSpan text = ms_message_take_builder(arena, &out);
  return text;
}

#define ANY_INDENT SIZE_MAX

static MsSpan comments_above(MsArena *arena, MsSpan source, size_t line_start, size_t indent) {
  MsSpan before = ms_span_of(source.ptr, line_start < source.len ? line_start : source.len);
  if (before.len > 0 && before.ptr[before.len - 1] == '\n') {
    before = ms_span_of(before.ptr, before.len - 1);
  }
  Lines lines = {.arena = arena, .rest = before, .has_rest = before.len > 0};
  MsSpans blocks = {0};
  size_t used = 0;
  for (;;) {
    fill(&lines, used);
    if (used >= lines.nearest.len) {
      break;
    }
    const MsSpan line = strip_cr(lines.nearest.ptr[used]);
    if (indent != ANY_INDENT && ms_indent_columns(line) != indent) {
      break;
    }
    const MsSpan text = trim(line);
    if (ms_span_starts_with(text, ms_span_of_text("// ms:"))) {
      used++;
    } else if (ms_span_starts_with(text, ms_span_of_text("//"))) {
      MsSpan comment = drop_prefix(text, 2);
      if (comment.len > 0 && comment.ptr[0] == ' ') {
        comment = drop_prefix(comment, 1);
      }
      ms_spans_push(arena, &blocks, trim_end(comment));
      used++;
    } else if (ms_span_ends_with(text, ms_span_of_text("*/"))) {
      size_t open = used;
      bool found = false;
      for (;; open++) {
        fill(&lines, open);
        if (open >= lines.nearest.len) {
          break;
        }
        if (ms_span_starts_with(trim_start(lines.nearest.ptr[open]), ms_span_of_text("/*"))) {
          found = true;
          break;
        }
      }
      if (!found || (indent != ANY_INDENT && ms_indent_columns(lines.nearest.ptr[open]) != indent)) {
        break;
      }
      const size_t count = open - used + 1;
      MsSpan *ordered = MS_ARENA_NEW_ARRAY(arena, MsSpan, count);
      for (size_t i = 0; i < count; i++) {
        ordered[i] = lines.nearest.ptr[open - i];
      }
      ms_spans_push(arena, &blocks, block_text(arena, ordered, count));
      used = open + 1;
    } else {
      break;
    }
  }
  MsStrBuild out = ms_strbuild_new();
  for (size_t i = blocks.len; i > 0; i--) {
    if (i != blocks.len) {
      ms_strbuild_append_byte(&out, '\n');
    }
    ms_strbuild_append(&out, blocks.ptr[i - 1]);
  }
  const MsSpan text = ms_message_take_builder(arena, &out);
  return text;
}

/* The end of the text literal that opens at `line[0]` (a quote, or `f"`), or 0 when it never closes. */
static size_t quoted_end(MsSpan line, size_t start) {
  size_t i = start;
  if (line.ptr[i] == 'f') {
    i++;
  }
  i++;
  while (i < line.len) {
    if (line.ptr[i] == '\\') {
      i += 2;
      continue;
    }
    if (line.ptr[i] == '"') {
      return i + 1;
    }
    i++;
  }
  return 0;
}

/* The `//` comment that follows code on the line holding `offset`; text literals on the line are skipped. */
static MsSpan trailing_comment(MsArena *arena, MsSpan source, size_t offset) {
  if (offset > source.len) {
    return ms_span_of_text("");
  }
  size_t start = offset;
  while (start > 0 && source.ptr[start - 1] != '\n') {
    start--;
  }
  size_t end = start;
  while (end < source.len && source.ptr[end] != '\n') {
    end++;
  }
  const MsSpan line = strip_cr(ms_span_of(source.ptr + start, end - start));
  size_t i = 0;
  while (i < line.len) {
    if (line.ptr[i] == '"') {
      const bool formatted = i > 0 && line.ptr[i - 1] == 'f' &&
                             (i == 1 || !((line.ptr[i - 2] >= '0' && line.ptr[i - 2] <= '9') ||
                                          (line.ptr[i - 2] >= 'a' && line.ptr[i - 2] <= 'z') ||
                                          (line.ptr[i - 2] >= 'A' && line.ptr[i - 2] <= 'Z') || line.ptr[i - 2] == '_'));
      const size_t from = i - (formatted ? 1 : 0);
      const size_t close = quoted_end(line, from);
      if (close == 0) {
        return ms_span_of_text("");
      }
      i = close;
      continue;
    }
    if (line.ptr[i] == '/' && i + 1 < line.len && line.ptr[i + 1] == '/') {
      if (trim(ms_span_of(line.ptr, i)).len == 0) {
        return ms_span_of_text("");
      }
      MsSpan rest = drop_prefix(line, i + 2);
      if (rest.len > 0 && rest.ptr[0] == ' ') {
        rest = drop_prefix(rest, 1);
      }
      return ms_arena_copy(arena, trim_end(rest));
    }
    i++;
  }
  return ms_span_of_text("");
}

/* Whether every word of `prefix` is one of `words`. */
static bool words_among(MsSpan prefix, const char *const *words, size_t count) {
  size_t i = 0;
  while (i < prefix.len) {
    while (i < prefix.len && is_blank_byte(prefix.ptr[i])) {
      i++;
    }
    size_t j = i;
    while (j < prefix.len && !is_blank_byte(prefix.ptr[j])) {
      j++;
    }
    if (j > i) {
      bool known = false;
      for (size_t w = 0; w < count; w++) {
        known = known || ms_span_is_text(ms_span_of(prefix.ptr + i, j - i), words[w]);
      }
      if (!known) {
        return false;
      }
    }
    i = j;
  }
  return true;
}

MsSpan ms_leading_comment(MsArena *arena, MsSpan source, size_t offset) {
  if (offset > source.len) {
    return ms_span_of_text("");
  }
  size_t line_start = offset;
  while (line_start > 0 && source.ptr[line_start - 1] != '\n') {
    line_start--;
  }
  const MsSpan own_line = ms_span_of(source.ptr + line_start, offset - line_start);
  const MsSpan prefix = trim(own_line);
  /* Names of cases and operations follow their keyword; inline payload fields do not begin a declaration line. A receiver
   * method's name follows its receiver: `fn Type.name`, `fn var Type[T].name`. */
  const bool receiver_method = ms_span_starts_with(prefix, ms_span_of_text("fn ")) && ms_span_ends_with(prefix, ms_span_of_text("."));
  static const char *const MODIFIERS[] = {"export", "opaque", "extern"};
  const bool lead = words_among(prefix, MODIFIERS, 3) || ms_span_is_text(prefix, "fn") || ms_span_is_text(prefix, "var fn") ||
                    ms_span_is_text(prefix, "move fn") || ms_span_is_text(prefix, "case");
  if (!lead && !receiver_method) {
    return ms_span_of_text("");
  }
  const MsSpan above = comments_above(arena, source, line_start, ms_indent_columns(own_line));
  if (above.len > 0) {
    return above;
  }
  return trailing_comment(arena, source, offset);
}

void ms_declared_effects(MsArena *arena, MsSpan source, size_t offset, MsSpans *out) {
  if (offset > source.len) {
    return;
  }
  size_t line_start = offset;
  while (line_start > 0 && source.ptr[line_start - 1] != '\n') {
    line_start--;
  }
  MsSpans found = {0};
  size_t end = line_start;
  while (end > 0) {
    size_t stop = end - 1; /* the newline ending the line above */
    size_t begin = stop;
    while (begin > 0 && source.ptr[begin - 1] != '\n') {
      begin--;
    }
    const MsSpan line = trim_start(strip_cr(ms_span_of(source.ptr + begin, stop - begin)));
    if (!ms_span_starts_with(line, ms_span_of_text("//"))) {
      break;
    }
    if (ms_span_starts_with(line, ms_span_of_text("// ms: effect "))) {
      ms_spans_push(arena, &found, trim(drop_prefix(line, 14)));
    }
    end = begin;
  }
  for (size_t i = found.len; i > 0; i--) {
    ms_spans_push(arena, out, found.ptr[i - 1]);
  }
}

MsSpan ms_declaration_comment(MsArena *arena, MsSpan source, size_t offset, uint32_t line) {
  if (line <= 1 || offset > source.len) {
    return ms_span_of_text("");
  }
  size_t line_start = offset;
  while (line_start > 0 && source.ptr[line_start - 1] != '\n') {
    line_start--;
  }
  const MsSpan above = comments_above(arena, source, line_start, ANY_INDENT);
  const MsSpan docs = above.len > 0 ? above : trailing_comment(arena, source, offset);
  return trim(docs);
}

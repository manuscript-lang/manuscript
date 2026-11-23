/* cli/snippet.c: the excerpt under a terminal diagnostic. Columns are 1-based byte columns except that each
 * leading tab counts as four (the lexer's column). */
#include "cli/snippet.h"

#include "base/utf8.h"

enum { TAB_WIDTH = 4, LINE_LIMIT = 200, CONTEXT_BEFORE = 60, WINDOW = 160, MARK_LIMIT = 80 };

static bool is_indent(uint32_t rune) {
  return rune == '\t' || rune == ' ';
}

/* The byte offset of lexer column `column` in `line`. */
static size_t byte_index(MsSpan line, uint32_t column) {
  const size_t target = column == 0 ? 0 : column - 1;
  size_t columns = 0;
  bool leading = true;
  for (size_t at = 0; at < line.len;) {
    const MsRune rune = ms_utf8_decode(line.ptr + at, line.len - at);
    leading = leading && is_indent(rune.rune);
    const size_t span = leading && rune.rune == '\t' ? TAB_WIDTH : rune.width;
    if (columns + span > target) {
      return at;
    }
    columns += span;
    at += rune.width;
  }
  return line.len;
}

static size_t cell_width(uint32_t c) {
  if (c == '\t') {
    return TAB_WIDTH;
  }
  if ((c >= 0x200b && c <= 0x200f) || (c >= 0x0300 && c <= 0x036f) || (c >= 0xfe00 && c <= 0xfe0f)) {
    return 0;
  }
  const bool wide = (c >= 0x1100 && c <= 0x115f) || (c >= 0x2e80 && c <= 0xa4cf) ||
                    (c >= 0xac00 && c <= 0xd7a3) || (c >= 0xf900 && c <= 0xfaff) ||
                    (c >= 0xfe30 && c <= 0xfe6f) || (c >= 0xff00 && c <= 0xff60) ||
                    (c >= 0xffe0 && c <= 0xffe6) || (c >= 0x1f300 && c <= 0x1f64f) ||
                    (c >= 0x1f900 && c <= 0x1f9ff) || (c >= 0x20000 && c <= 0x3fffd);
  return wide ? 2 : 1;
}

static size_t text_width(MsSpan text) {
  size_t width = 0;
  for (size_t at = 0; at < text.len;) {
    const MsRune rune = ms_utf8_decode(text.ptr + at, text.len - at);
    width += cell_width(rune.rune);
    at += rune.width;
  }
  return width;
}

/* The line as printed: tabs become spaces and a control character becomes its one-cell picture, so a source
 * line cannot drive the terminal. */
static void append_expanded(MsStrBuild *out, MsSpan line) {
  for (size_t at = 0; at < line.len;) {
    const MsRune rune = ms_utf8_decode(line.ptr + at, line.len - at);
    const uint32_t c = rune.rune;
    if (c == '\t') {
      ms_strbuild_append_text(out, "    ");
    } else if (c < 0x20) {
      ms_strbuild_append_utf8(out, 0x2400 + c);
    } else if (c == 0x7f) {
      ms_strbuild_append_utf8(out, 0x2421);
    } else if (c >= 0x80 && c <= 0x9f) {
      ms_strbuild_append_utf8(out, MS_RUNE_ERROR);
    } else {
      ms_strbuild_append(out, ms_span_of(line.ptr + at, rune.width));
    }
    at += rune.width;
  }
}

/* The cells [first, first + limit) of `text`, cut on character boundaries; returns the cell the window really
 * starts at and sets `*reached_end` when the whole remainder fits. */
static size_t append_cells(MsStrBuild *out, MsSpan text, size_t first, size_t limit, bool *reached_end) {
  size_t cells = 0;
  size_t at = 0;
  while (at < text.len && cells < first) {
    const MsRune rune = ms_utf8_decode(text.ptr + at, text.len - at);
    cells += cell_width(rune.rune);
    at += rune.width;
  }
  const size_t from = cells;
  while (at < text.len) {
    const MsRune rune = ms_utf8_decode(text.ptr + at, text.len - at);
    const size_t width = cell_width(rune.rune);
    if (cells - from + width > limit) {
      break;
    }
    ms_strbuild_append(out, ms_span_of(text.ptr + at, rune.width));
    cells += width;
    at += rune.width;
  }
  *reached_end = at >= text.len;
  return from;
}

static void append_repeated(MsStrBuild *out, uint8_t byte, size_t count) {
  for (size_t i = 0; i < count; i++) {
    ms_strbuild_append_byte(out, byte);
  }
}

/* The text of 1-based `line`, without its newline and a trailing carriage return. */
static bool line_of(MsSpan source, uint32_t line, MsSpan *text) {
  if (line == 0) {
    return false;
  }
  size_t start = 0;
  for (uint32_t number = 1; number < line; number++) {
    size_t newline = 0;
    if (!ms_span_find(ms_span_of(source.ptr + start, source.len - start), ms_span_of_text("\n"), &newline)) {
      return false;
    }
    start += newline + 1;
  }
  size_t stop = source.len;
  size_t newline = 0;
  if (ms_span_find(ms_span_of(source.ptr + start, source.len - start), ms_span_of_text("\n"), &newline)) {
    stop = start + newline;
  }
  if (stop > start && source.ptr[stop - 1] == '\r') {
    stop--;
  }
  *text = ms_span_of(source.ptr + start, stop - start);
  return true;
}

void ms_snippet_excerpt(MsStrBuild *out, MsSpan source, MsPos pos, bool has_end, MsPos end) {
  MsSpan line = {0};
  if (!line_of(source, pos.line, &line)) {
    return;
  }
  const size_t start = byte_index(line, pos.column);
  size_t stop = start;
  if (has_end && end.line == pos.line) {
    stop = byte_index(line, end.column);
  } else if (has_end && end.line > pos.line) {
    stop = line.len;
  }
  const size_t indent = text_width(ms_span_of(line.ptr, start));
  size_t marks = text_width(ms_span_of(line.ptr + start, (stop > start ? stop : start) - start));
  marks = marks == 0 ? 1 : marks;
  MsStrBuild number = ms_strbuild_new();
  ms_strbuild_append_u64(&number, pos.line);
  const size_t digits = ms_strbuild_length(&number);
  ms_strbuild_append_text(out, "\n ");
  append_repeated(out, ' ', digits);
  ms_strbuild_append_text(out, " |\n ");
  ms_strbuild_append(out, ms_strbuild_span(&number));
  ms_strbuild_append_text(out, " | ");
  size_t caret_indent = indent;
  if (indent + marks <= LINE_LIMIT && text_width(line) <= LINE_LIMIT) {
    append_expanded(out, line);
  } else {
    /* A long line (minified or generated code) shows a window around the span, with ellipses for the rest. */
    MsStrBuild expanded = ms_strbuild_new();
    append_expanded(&expanded, line);
    const size_t first = indent > CONTEXT_BEFORE ? indent - CONTEXT_BEFORE : 0;
    bool reached_end = false;
    if (first > 0) {
      ms_strbuild_append_utf8(out, 0x2026);
    }
    const size_t from = append_cells(out, ms_strbuild_span(&expanded), first, WINDOW, &reached_end);
    if (!reached_end) {
      ms_strbuild_append_utf8(out, 0x2026);
    }
    caret_indent = indent - from + (first > 0 ? 1 : 0);
    marks = marks > MARK_LIMIT ? MARK_LIMIT : marks;
    ms_strbuild_free(&expanded);
  }
  ms_strbuild_append_text(out, "\n ");
  append_repeated(out, ' ', digits);
  ms_strbuild_append_text(out, " | ");
  append_repeated(out, ' ', caret_indent);
  append_repeated(out, '^', marks);
  ms_strbuild_free(&number);
}

/* syntax/format_text.c: line, tab and literal-text helpers of the formatter, and one formatting pass. */
#include "compiler/syntax/format_internal.h"
#include "compiler/syntax/walk.h"

/* ---- strings, lines and sections ---- */

/* `text` with "\r\n" replaced by "\n". */
MsSpan fmt_normalize(Fmt *f, MsSpan text) {
  MsStrBuild out = {0};
  for (size_t i = 0; i < text.len; i++) {
    if (text.ptr[i] == '\r' && i + 1 < text.len && text.ptr[i + 1] == '\n') {
      continue;
    }
    ms_strbuild_append_byte(&out, (uint8_t)(text.ptr[i]));
  }
  return fmt_take(f, &out);
}

/* The lines of `text` split at '\n': one more than there are newlines. */
size_t fmt_split_lines(MsSpan text, SpanList *lines) {
  size_t start = 0;
  for (size_t i = 0; i <= text.len; i++) {
    if (i == text.len || text.ptr[i] == '\n') {
      span_list_push(lines, fmt_slice(text, start, i));
      start = i + 1;
    }
  }
  return lines->len;
}

/* The lines joined by '\n'. */
MsSpan fmt_join_lines(Fmt *f, const MsSpan *lines, size_t count) {
  MsStrBuild out = {0};
  for (size_t i = 0; i < count; i++) {
    if (i > 0) {
      ms_strbuild_append_byte(&out, (uint8_t)('\n'));
    }
    fmt_put(&out, lines[i]);
  }
  return fmt_take(f, &out);
}

/* The columns of leading whitespace in `line`, a tab counting four. */
static size_t fmt_indent_columns(MsSpan line) {
  size_t columns = 0;
  for (size_t i = 0; i < line.len && (line.ptr[i] == ' ' || line.ptr[i] == '\t'); i++) {
    columns += line.ptr[i] == '\t' ? 4 : 1;
  }
  return columns;
}

/* Writes each full group of four leading spaces as a tab, one token per level; spaces left over
 * align continuation lines. The formatter works in spaces and converts once on exit. */
static MsSpan fmt_tabify(Fmt *f, MsSpan text) {
  MsStrBuild out = {0};
  size_t start = 0;
  for (size_t i = 0; i <= text.len; i++) {
    if (i < text.len && text.ptr[i] != '\n') {
      continue;
    }
    const MsSpan line = fmt_slice(text, start, i);
    const size_t spaces = fmt_indent_of(line);
    if (start > 0) {
      ms_strbuild_append_byte(&out, (uint8_t)('\n'));
    }
    for (size_t tab = 0; tab < spaces / 4; tab++) {
      ms_strbuild_append_byte(&out, (uint8_t)('\t'));
    }
    fmt_put(&out, fmt_slice(line, spaces / 4 * 4, line.len));
    start = i + 1;
  }
  return fmt_take(f, &out);
}

/* Replaces each tab in a code line's leading whitespace with four spaces, leaving lines inside
 * multi-line text and block comments untouched. */
static bool fmt_expand_indent_tabs(Fmt *f, MsSpan text, MsSpan *out) {
  MsArena scratch = {0};
  MsLexed lexed;
  if (!fmt_lex(f, &scratch, text, &lexed)) {
    ms_arena_free(&scratch);
    return false;
  }
  RangeList protected_ranges = {0};
  for (size_t i = 0; i < lexed.ntokens; i++) {
    const MsToken *t = &lexed.tokens[i];
    if (t->kind == MS_T_String && fmt_contains(fmt_token_text(text, t), "\n")) {
      range_list_push(&protected_ranges, ((MsByteRange){t->lo, t->hi}));
    }
  }
  for (size_t i = 0; i < lexed.nblocks; i++) {
    range_list_push(&protected_ranges, lexed.blocks[i]);
  }
  const MsByteRange *ranges = protected_ranges.ptr;
  const size_t nranges = protected_ranges.len;
  MsStrBuild result = {0};
  size_t at = 0;
  while (at < text.len) {
    size_t end = at;
    while (end < text.len && text.ptr[end] != '\n') {
      end++;
    }
    if (end < text.len) {
      end++; // the line keeps its newline
    }
    const MsSpan line = fmt_slice(text, at, end);
    bool inside = false;
    for (size_t k = 0; k < nranges; k++) {
      inside = inside || (ranges[k].start < at && at < ranges[k].end);
    }
    const MsSpan body = fmt_trim_start_set(line, " \t");
    if (inside || line.ptr[0] != '\t') {
      fmt_put(&result, line);
    } else {
      for (size_t i = 0; i < line.len - body.len; i++) {
        ms_strbuild_append_text(&result, line.ptr[i] == '\t' ? "    " : " ");
      }
      fmt_put(&result, body);
    }
    at = end;
  }
  range_list_free(&protected_ranges);
  ms_arena_free(&scratch);
  *out = fmt_take(f, &result);
  return true;
}

/* ---- literal text that the line passes cannot see ---- */

/* Removes `columns` of leading whitespace, a tab counting four; false when the line lacks them or
 * a tab would be split. */
static bool fmt_strip_columns(MsSpan line, size_t columns, MsSpan *rest) {
  size_t taken = 0;
  for (size_t at = 0; at < line.len; at++) {
    if (taken == columns) {
      *rest = fmt_slice(line, at, line.len);
      return true;
    }
    if (line.ptr[at] == ' ') {
      taken += 1;
    } else if (line.ptr[at] == '\t') {
      taken += 4;
    } else {
      return false;
    }
    if (taken > columns) {
      return false;
    }
  }
  *rest = ms_span_of_text("");
  return taken == columns;
}

/* Moves every line after the first of `text` from indentation `before` to `after`; the text is
 * unchanged when a line lacks the indentation to give up. */
static MsSpan fmt_shift_lines(Fmt *f, MsSpan text, size_t before, size_t after) {
  MsStrBuild out = {0};
  size_t start = 0;
  bool first = true;
  for (size_t i = 0; i <= text.len; i++) {
    if (i < text.len && text.ptr[i] != '\n') {
      continue;
    }
    const MsSpan line = fmt_slice(text, start, i);
    start = i + 1;
    if (first) {
      fmt_put(&out, line);
      first = false;
      continue;
    }
    ms_strbuild_append_byte(&out, (uint8_t)('\n'));
    MsSpan rest;
    if (line.len == 0) {
      continue;
    }
    if (after >= before) {
      fmt_spaces(&out, after - before);
      fmt_put(&out, line);
    } else if (fmt_strip_columns(line, before - after, &rest)) {
      fmt_put(&out, rest);
    } else {
      ms_strbuild_free(&out);
      return text;
    }
  }
  return fmt_take(f, &out);
}

typedef struct Span {
  size_t lo, hi;
  bool block;
} Span;
MS_LIST_DEFINE(LitList, lit_list, Span)

static int span_order(const void *a, const void *b) {
  const Span *x = a;
  const Span *y = b;
  if (x->lo != y->lo) {
    return x->lo < y->lo ? -1 : 1;
  }
  if (x->hi != y->hi) {
    return x->hi < y->hi ? -1 : 1;
  }
  return (int)x->block - (int)y->block;
}

/* A private-use marker absent from `text`, for placeholders that survive the line passes. */
static MsSpan fmt_marker(Fmt *f, MsSpan text) {
  for (uint32_t c = 0xE000; c <= 0xF8FF; c++) {
    MsStrBuild encoded = {0};
    ms_strbuild_append_utf8(&encoded, c);
    if (fmt_find(text, ms_strbuild_span(&encoded)) == FMT_NONE) {
      return fmt_take(f, &encoded);
    }
    ms_strbuild_free(&encoded);
  }
  for (size_t i = 0;; i++) {
    const MsSpan candidate = ms_message_format(f->arena, "\xee\x80\x80%z\xee\x80\x80", i);
    if (fmt_find(text, candidate) == FMT_NONE) {
      return candidate;
    }
  }
}

static MsSpan fmt_placeholder(Fmt *f, MsSpan marker, size_t index, bool block) {
  return block ? ms_message_format(f->arena, "//%S%z%S", marker, index, marker)
               : ms_message_format(f->arena, "\"%S%z\"", marker, index);
}

/* The multi-line string literals and block comments of `source`, in `spans`. False when the text
 * does not lex. */
static bool fmt_literal_spans(Fmt *f, MsSpan source, LitList *spans) {
  MsArena scratch = {0};
  MsLexed lexed;
  if (!fmt_lex(f, &scratch, source, &lexed)) {
    ms_arena_free(&scratch);
    return false;
  }
  for (size_t i = 0; i < lexed.ntokens; i++) {
    const MsToken *t = &lexed.tokens[i];
    if (t->kind == MS_T_String && fmt_contains(fmt_token_text(source, t), "\n")) {
      lit_list_push(spans, ((Span){t->lo, t->hi, false}));
    }
  }
  for (size_t i = 0; i < lexed.nblocks; i++) {
    lit_list_push(spans, ((Span){lexed.blocks[i].start, lexed.blocks[i].end, true}));
  }
  ms_arena_free(&scratch);
  return true;
}

/* `source` with a one-line placeholder in place of each span. */
static MsSpan fmt_mask_spans(Fmt *f, MsSpan source, MsSpan marker, const Span *spans, size_t nspans) {
  MsStrBuild masked = {0};
  size_t copied = 0;
  for (size_t i = 0; i < nspans; i++) {
    fmt_put(&masked, fmt_slice(source, copied, spans[i].lo));
    fmt_put(&masked, fmt_placeholder(f, marker, i, spans[i].block));
    copied = spans[i].hi;
  }
  fmt_put(&masked, fmt_slice(source, copied, source.len));
  return fmt_take(f, &masked);
}

/* `formatted` with each placeholder replaced by the span's original text, shifted to the
 * indentation of the line it landed on. */
static MsSpan fmt_unmask_spans(Fmt *f, MsSpan source, MsSpan formatted, MsSpan marker, const Span *spans,
                               size_t nspans) {
  MsStrBuild result = {0};
  size_t copied = 0;
  for (size_t i = 0; i < nspans; i++) {
    const MsSpan text = fmt_slice(source, spans[i].lo, spans[i].hi);
    const size_t line_break = fmt_rfind_byte(fmt_slice(source, 0, spans[i].lo), '\n');
    const size_t line_start = line_break == FMT_NONE ? 0 : line_break + 1;
    const size_t before = fmt_indent_of(fmt_slice(source, line_start, source.len));
    const MsSpan placeholder = fmt_placeholder(f, marker, i, spans[i].block);
    const size_t at = copied + fmt_find(fmt_slice(formatted, copied, formatted.len), placeholder);
    fmt_put(&result, fmt_slice(formatted, copied, at));
    const MsSpan so_far = fmt_tail(&result, 0);
    const size_t last_break = fmt_rfind_byte(so_far, '\n');
    const size_t result_line_start = last_break == FMT_NONE ? 0 : last_break + 1;
    const size_t after = fmt_indent_columns(fmt_slice(so_far, result_line_start, so_far.len));
    fmt_put(&result, fmt_shift_lines(f, text, before, after));
    copied = at + placeholder.len;
  }
  fmt_put(&result, fmt_slice(formatted, copied, formatted.len));
  return fmt_take(f, &result);
}

/* One formatting pass over `source`. */
bool fmt_once(Fmt *f, MsSpan source, MsSpan *out) {
  MsArena scratch = {0};
  MsModule module;
  const bool valid = fmt_parse(f, &scratch, source, &module);
  ms_arena_free(&scratch);
  if (!valid) {
    return false;
  }
  MsSpan normalized = fmt_normalize(f, source);
  if (fmt_contains(normalized, "\t") && !fmt_expand_indent_tabs(f, normalized, &normalized)) {
    return false;
  }
  LitList spans = {0};
  if (!fmt_literal_spans(f, normalized, &spans)) {
    return false;
  }
  const size_t nspans = spans.len;
  Span *list = spans.ptr;
  MsSpan lined;
  if (nspans == 0) {
    lit_list_free(&spans);
    if (!fmt_lines(f, normalized, &lined)) {
      return false;
    }
    *out = fmt_tabify(f, lined);
    return true;
  }
  qsort(list, nspans, sizeof *list, span_order);
  // The line-based passes cannot see inside a multi-line text literal, so a one-line placeholder
  // stands in for each and the literal text returns afterwards, shifted with the line it lands on.
  const MsSpan marker = fmt_marker(f, normalized);
  const MsSpan masked = fmt_mask_spans(f, normalized, marker, list, nspans);
  const bool formatted_ok = fmt_lines(f, masked, &lined);
  if (formatted_ok) {
    const MsSpan formatted = fmt_tabify(f, lined);
    *out = fmt_unmask_spans(f, normalized, formatted, marker, list, nspans);
  }
  lit_list_free(&spans);
  if (!formatted_ok) {
    return false;
  }
  MsArena check = {0};
  const bool ok = fmt_parse(f, &check, *out, &module);
  ms_arena_free(&check);
  return ok;
}

/* ---- imports ---- */

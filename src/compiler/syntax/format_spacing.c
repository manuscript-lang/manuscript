/* syntax/format_spacing.c: comment reflow, token spacing and suite headers. */
#include "compiler/syntax/format_internal.h"
#include "compiler/syntax/walk.h"

/* `key: value` lines such as `conform:`, `ms:`, `manuscript:`, `expect-debug:` are data read by
 * tools, so they are never reflowed. */
static bool fmt_directive_key(MsSpan body) {
  size_t start = 0;
  while (start < body.len) {
    uint32_t scalar;
    const size_t width = fmt_scalar_at(body, start, &scalar);
    if (!ms_utf8_is_space(scalar)) {
      break;
    }
    start += width;
  }
  size_t end = start;
  while (end < body.len) {
    uint32_t scalar;
    const size_t width = fmt_scalar_at(body, end, &scalar);
    if (ms_utf8_is_space(scalar)) {
      break;
    }
    end += width;
  }
  const MsSpan word = fmt_slice(body, start, end);
  const size_t colon = fmt_find_byte(word, ':');
  if (colon == FMT_NONE || colon == 0) {
    return false;
  }
  for (size_t i = 0; i < colon; i++) {
    const char c = (char)word.ptr[i];
    if (!((c >= 'a' && c <= 'z') || c == '-' || c == '_' || c == '.')) {
      return false;
    }
  }
  return true;
}

/* The text of a plain prose comment line (`// text`), or false for anything a reflow must leave
 * alone: code, an empty comment, indented or list or table text, a code fence, tool metadata, or a
 * block-comment placeholder. */
static bool fmt_prose_comment(MsSpan line, MsSpan *body_out) {
  const MsSpan trimmed = fmt_trim_start_set(line, " ");
  if (!fmt_starts(trimmed, "// ")) {
    return false;
  }
  const MsSpan body = fmt_slice(trimmed, 3, trimmed.len);
  if (body.len == 0) {
    return false;
  }
  uint32_t first;
  (void)fmt_scalar_at(body, 0, &first);
  const bool listed = first == '-' || first == '*' || first == '|' || first == '`' || first == '#' ||
                      first == '<' || first == '>' || (first >= 0xE000 && first <= 0xF8FF);
  bool numbered = false;
  const size_t dot = fmt_find(body, ms_span_of_text(". "));
  if (dot != FMT_NONE) {
    numbered = true;
    for (size_t i = 0; i < dot; i++) {
      numbered = numbered && body.ptr[i] >= '0' && body.ptr[i] <= '9';
    }
  }
  if (ms_utf8_is_space(first) || listed || fmt_directive_key(body) || numbered) {
    return false;
  }
  *body_out = body;
  return true;
}

/* Splits comment text into words, keeping a short backtick span whole so code is not broken
 * across lines. The words are appended to `words`. */
static void fmt_comment_words(Fmt *f, MsSpan text, SpanList *words) {
  bool open = false;
  size_t at = 0;
  while (at < text.len) {
    // The next whitespace-separated word.
    while (at < text.len) {
      uint32_t scalar;
      const size_t width = fmt_scalar_at(text, at, &scalar);
      if (!ms_utf8_is_space(scalar)) {
        break;
      }
      at += width;
    }
    size_t end = at;
    while (end < text.len) {
      uint32_t scalar;
      const size_t width = fmt_scalar_at(text, end, &scalar);
      if (ms_utf8_is_space(scalar)) {
        break;
      }
      end += width;
    }
    if (end == at) {
      break;
    }
    const MsSpan word = fmt_slice(text, at, end);
    size_t ticks = 0;
    for (size_t i = 0; i < word.len; i++) {
      ticks += word.ptr[i] == '`';
    }
    const size_t nwords = words->len;
    if (nwords > 0 && open && fmt_chars(words->ptr[nwords - 1]) < 60) {
      MsSpan *last = &words->ptr[nwords - 1];
      *last = ms_message_format(f->arena, "%S %S", *last, word);
    } else {
      span_list_push(words, word);
    }
    if (ticks % 2 == 1) {
      open = !open;
    }
    at = end;
  }
}

/* Refills the `count` lines of one wide prose comment paragraph at `indent`, whose first line's text is
 * `first`, appending the wrapped lines. */
static void fmt_refill_paragraph(Fmt *f, const MsSpan *lines, size_t count, size_t indent, MsSpan first,
                                 SpanList *out) {
  MsStrBuild prefix_buf = {0};
  fmt_spaces(&prefix_buf, indent);
  ms_strbuild_append_text(&prefix_buf, "// ");
  const MsSpan prefix = fmt_take(f, &prefix_buf);
  const size_t prefix_chars = fmt_chars(prefix);
  const size_t room = FMT_WIDTH > prefix_chars ? FMT_WIDTH - prefix_chars : 0;
  SpanList words = {0};
  fmt_comment_words(f, first, &words);
  for (size_t k = 1; k < count; k++) {
    MsSpan text;
    if (fmt_prose_comment(lines[k], &text)) {
      fmt_comment_words(f, text, &words);
    }
  }
  MsStrBuild row = {0};
  const MsSpan *list = words.ptr;
  for (size_t w = 0; w < words.len; w++) {
    const size_t width = fmt_chars(fmt_tail(&row, 0)) + (ms_strbuild_length(&row) != 0) + fmt_chars(list[w]);
    if (ms_strbuild_length(&row) != 0 && width > room) {
      MsStrBuild line = {0};
      fmt_put(&line, prefix);
      fmt_put(&line, fmt_tail(&row, 0));
      span_list_push(out, fmt_take(f, &line));
      ms_strbuild_clear(&row);
    }
    if (ms_strbuild_length(&row) != 0) {
      ms_strbuild_append_byte(&row, (uint8_t)(' '));
    }
    fmt_put(&row, list[w]);
  }
  MsStrBuild line = {0};
  fmt_put(&line, prefix);
  fmt_put(&line, fmt_tail(&row, 0));
  span_list_push(out, fmt_take(f, &line));
  ms_strbuild_free(&row);
  span_list_free(&words);
}

/* Rewraps each paragraph of consecutive prose `//` lines that has a line wider than the formatter
 * width, filling lines greedily up to the width. Paragraphs that already fit, and everything that
 * is not plain prose, are unchanged. */
void fmt_wrap_comments(Fmt *f, const MsSpan *lines, size_t count, SpanList *out) {
  bool fenced = false;
  size_t i = 0;
  while (i < count) {
    const MsSpan trimmed = fmt_trim_start_set(lines[i], " ");
    if (fmt_starts(trimmed, "// ```")) {
      fenced = !fenced;
    }
    MsSpan first;
    if (fenced || !fmt_prose_comment(lines[i], &first)) {
      span_list_push(out, lines[i]);
      i++;
      continue;
    }
    const size_t indent = lines[i].len - trimmed.len;
    size_t end = i + 1;
    MsSpan ignored;
    while (end < count && lines[end].len - fmt_trim_start_set(lines[end], " ").len == indent &&
           fmt_prose_comment(lines[end], &ignored)) {
      end++;
    }
    bool wide = false;
    for (size_t k = i; k < end; k++) {
      wide = wide || fmt_chars(lines[k]) > FMT_WIDTH;
    }
    if (!wide) {
      for (size_t k = i; k < end; k++) {
        span_list_push(out, lines[k]);
      }
      i = end;
      continue;
    }
    fmt_refill_paragraph(f, lines + i, end - i, indent, first, out);
    i = end;
  }
}

/* ---- spacing between tokens on a line ---- */

/* Whether the final `)` closes the parameter list of an `fn` declaration or function type, so a
 * `(` after it opens a parenthesized return type (`fn f() (fn() Int)?`) rather than calling a
 * result. Returns -1 when the matching `(` is not among `tokens` (a line that starts at the `)`). */
static int fmt_closes_parameter_list(const MsToken *tokens, size_t count) {
  int depth = 0;
  bool found = false;
  size_t at = 0;
  for (size_t index = count; index > 0; index--) {
    const MsTok kind = (MsTok)tokens[index - 1].kind;
    if (kind == MS_T_RParen) {
      depth++;
    } else if (kind == MS_T_LParen) {
      depth--;
      if (depth == 0) {
        at = index - 1;
        found = true;
        break;
      }
    }
  }
  if (!found) {
    return -1;
  }
  if (at > 0 && tokens[at - 1].kind == MS_T_RBracket) {
    depth = 0;
    while (at > 0) {
      at--;
      if (tokens[at].kind == MS_T_RBracket) {
        depth++;
      } else if (tokens[at].kind == MS_T_LBracket) {
        depth--;
        if (depth == 0) {
          break;
        }
      }
    }
  }
  const bool one_fn = at >= 1 && tokens[at - 1].kind == MS_T_Fn;
  const bool named_fn = at >= 2 && tokens[at - 1].kind == MS_T_Name && tokens[at - 2].kind == MS_T_Fn;
  return one_fn || named_fn;
}

static bool fmt_after_operand(MsTok previous) {
  return previous == MS_T_Plus || previous == MS_T_Minus || previous == MS_T_Star || previous == MS_T_Slash ||
         previous == MS_T_Percent;
}

/* Whether the `-` before tokens[at] is a sign: the first token, or after an operator or opener. */
static bool minus_is_unary(const MsToken *tokens, size_t at) {
  if (at == 1) {
    return true;
  }
  switch ((MsTok)tokens[at - 2].kind) {
  case MS_T_Assign:
  case MS_T_ColonAssign:
  case MS_T_LParen:
  case MS_T_LBracket:
  case MS_T_Comma:
  case MS_T_Colon:
  case MS_T_Return:
  case MS_T_Plus:
  case MS_T_Minus:
  case MS_T_Star:
  case MS_T_Slash:
  case MS_T_Percent:
  case MS_T_Lt:
  case MS_T_Gt:
  case MS_T_EqEq:
  case MS_T_NotEq:
  case MS_T_Le:
  case MS_T_Ge:
    return true;
  default:
    return false;
  }
}

bool fmt_token_space(const MsToken *tokens, size_t at) {
  const MsTok current = (MsTok)tokens[at].kind;
  const MsTok previous = (MsTok)tokens[at - 1].kind;
  if (current == MS_T_Dot && (previous == MS_T_Pipe || previous == MS_T_Try)) {
    return true;
  }
  if (previous == MS_T_Bang && current == MS_T_Name && tokens[at].lo == tokens[at - 1].hi) {
    return false;
  }
  if (current == MS_T_DotDot || previous == MS_T_DotDot) {
    return false;
  }
  switch (current) {
  case MS_T_RParen:
  case MS_T_RBracket:
  case MS_T_RBrace:
  case MS_T_Comma:
  case MS_T_Dot:
  case MS_T_Colon:
  case MS_T_Question:
  case MS_T_Bang:
    return false;
  default:
    break;
  }
  if (previous == MS_T_LParen || previous == MS_T_LBracket || previous == MS_T_LBrace ||
      previous == MS_T_Dot) {
    return false;
  }
  if (current == MS_T_Assign && fmt_after_operand(previous) &&
      tokens[at - 1].end.offset == tokens[at].pos.offset) {
    return false; // the two tokens of a compound assignment such as +=
  }
  if (current == MS_T_LParen && (previous == MS_T_Name || previous == MS_T_RParen ||
                                 previous == MS_T_RBracket || previous == MS_T_Fn)) {
    if (previous == MS_T_Name) {
      // `limit (fn() Int)?` is a name and its parenthesized type, `limit(1)` a call: per-line spacing
      // cannot tell them apart, so the authored gap decides.
      return tokens[at].lo != tokens[at - 1].hi;
    }
    if (previous != MS_T_RParen) {
      return false;
    }
    // Per-line spacing cannot see a `(` on an earlier line; keep the authored gap.
    const int closes = fmt_closes_parameter_list(tokens, at);
    return closes < 0 ? tokens[at].lo != tokens[at - 1].hi : closes == 1;
  }
  if (current == MS_T_LBracket && (previous == MS_T_Name || previous == MS_T_SelfKw ||
                                   previous == MS_T_RBracket || previous == MS_T_RParen)) {
    return false;
  }
  if (previous == MS_T_Minus && minus_is_unary(tokens, at)) {
    return false;
  }
  return true;
}

/* ---- suite headers ---- */

/* Re-indents a suite whose header spans several lines and ends on a line indented differently from
 * the statement's first line. Fills `out` with the new lines; false when nothing moves. */
bool fmt_align_suite_headers(Fmt *f, const MsSpan *lines, size_t nlines, const MsToken *tokens,
                             size_t ntokens, SpanList *out) {
  int64_t *shift = MS_ARENA_NEW_ARRAY(f->arena, int64_t, nlines + 2);
  memset(shift, 0, (nlines + 2) * sizeof *shift);
  bool changed = false;
  int64_t depth = 0;
  for (size_t i = 0; i < ntokens; i++) {
    const MsTok kind = (MsTok)tokens[i].kind;
    if (fmt_is_open(kind)) {
      depth++;
    } else if (kind == MS_T_RParen || kind == MS_T_RBracket || kind == MS_T_RBrace) {
      depth--;
    }
    if (kind != MS_T_Indent || depth != 0 || i < 3 || i + 1 >= ntokens || tokens[i + 1].kind == MS_T_Dedent ||
        tokens[i - 1].kind != MS_T_Newline || tokens[i - 2].kind != MS_T_Colon) {
      continue;
    }
    size_t start = i - 2;
    // A parameter default can contain its own suite. Its layout tokens belong to the enclosing
    // group, not the start of this header.
    int groups = 0;
    while (start > 0) {
      const MsTok before = (MsTok)tokens[start - 1].kind;
      if (before == MS_T_RParen || before == MS_T_RBracket || before == MS_T_RBrace) {
        groups++;
      } else if (fmt_is_open(before)) {
        groups--;
      } else if ((before == MS_T_Newline || before == MS_T_Indent || before == MS_T_Dedent) && groups == 0) {
        break;
      }
      start--;
    }
    const uint32_t header = tokens[i - 2].pos.line;
    const uint32_t first = tokens[start].pos.line;
    if (header == first || header > nlines ||
        fmt_indent_of(lines[header - 1]) == fmt_indent_of(lines[first - 1])) {
      continue;
    }
    size_t end = nlines;
    int nesting = 0;
    for (size_t later = i; later < ntokens; later++) {
      if (tokens[later].kind == MS_T_Indent) {
        nesting++;
      } else if (tokens[later].kind == MS_T_Dedent) {
        nesting--;
        if (nesting == 0) {
          const size_t line = tokens[later].pos.line - 1;
          end = end < line ? end : line;
          break;
        }
      }
    }
    const int64_t delta =
        (int64_t)fmt_indent_of(lines[first - 1]) - (int64_t)fmt_indent_of(lines[header - 1]);
    for (size_t slot = header; slot <= end && slot < nlines + 2; slot++) {
      shift[slot] += delta;
    }
    changed = true;
  }
  if (!changed) {
    return false;
  }
  for (size_t index = 0; index < nlines; index++) {
    const int64_t delta = shift[index + 1];
    if (delta > 0 && !fmt_is_blank(lines[index])) {
      MsStrBuild line = {0};
      fmt_spaces(&line, (size_t)delta);
      fmt_put(&line, lines[index]);
      span_list_push(out, fmt_take(f, &line));
    } else if (delta < 0) {
      const size_t indent = fmt_indent_of(lines[index]);
      const size_t cut = (size_t)-delta < indent ? (size_t)-delta : indent;
      span_list_push(out, fmt_slice(lines[index], cut, lines[index].len));
    } else {
      span_list_push(out, lines[index]);
    }
  }
  return true;
}

/* ---- blank lines between paragraphs ---- */
